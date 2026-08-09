// 文件用途：封装 DirectUploadProgress 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 DirectUploadProgress 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_io/io.dart';

import 'api/api_client.dart';

// 关键声明：s3 direct upload service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
typedef DirectUploadProgress = void Function(int sent, int total);

@visibleForTesting
bool shouldFallbackToProxyUpload({
  required int code,
  required String message,
}) {
  // Current backend contract: 1430-1433 mean direct upload is unavailable
  // because of storage, feature, platform, or rollout configuration. Keep the
  // legacy 4601-4604 range for compatibility with older deployments.
  if ((code >= 1430 && code <= 1433) || (code >= 4601 && code <= 4604)) {
    return true;
  }
  final normalizedMessage = message.toLowerCase();
  return normalizedMessage.contains('未启用 amazon s3') ||
      normalizedMessage.contains('direct upload') ||
      normalizedMessage.contains('amazon s3 配置不可用');
}

@visibleForTesting
class DirectUploadSingleFlight<T> {
  final Map<String, Future<T>> _tasks = <String, Future<T>>{};

  // 流程逻辑：`run` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
  Future<T> run(String key, Future<T> Function() operation) {
    final existing = _tasks[key];
    if (existing != null) return existing;

    final task = operation();
    _tasks[key] = task;
    return task.whenComplete(() {
      if (identical(_tasks[key], task)) {
        _tasks.remove(key);
      }
    });
  }
}

@visibleForTesting
Future<String> computeDirectUploadSHA256({
  String? filePath,
  Uint8List? bytes,
}) async {
  if (bytes != null) {
    return sha256.convert(bytes).toString();
  }
  final normalizedPath = filePath?.trim() ?? '';
  if (normalizedPath.isEmpty) {
    throw ArgumentError('filePath or bytes is required');
  }
  final digest = await sha256.bind(File(normalizedPath).openRead()).first;
  return digest.toString();
}

@visibleForTesting
Future<Uint8List> readDirectUploadFileChunk({
  required String filePath,
  required int start,
  required int length,
}) async {
  if (start < 0 || length < 0) {
    throw ArgumentError('start and length must be non-negative');
  }
  final file = await File(filePath).open();
  try {
    await file.setPosition(start);
    final chunk = Uint8List(length);
    var offset = 0;
    while (offset < length) {
      final count = await file.readInto(chunk, offset, length);
      if (count <= 0) {
        throw const DirectUploadException('本地文件读取不完整，无法继续上传');
      }
      offset += count;
    }
    return chunk;
  } finally {
    await file.close();
  }
}

@visibleForTesting
List<DirectUploadPartRange> planDirectUploadParts(int size, int partSize) {
  if (size <= 0 || partSize <= 0) return const <DirectUploadPartRange>[];
  final result = <DirectUploadPartRange>[];
  for (var start = 0, number = 1; start < size; start += partSize, number++) {
    result.add(
      DirectUploadPartRange(
        number: number,
        start: start,
        length: (size - start).clamp(0, partSize).toInt(),
      ),
    );
  }
  return result;
}

@immutable
class DirectUploadPartRange {
  const DirectUploadPartRange({
    required this.number,
    required this.start,
    required this.length,
  });

  final int number;
  final int start;
  final int length;
}

@immutable
class DirectUploadInitMetadata {
  const DirectUploadInitMetadata({
    required this.category,
    required this.fileName,
    required this.mimeType,
    required this.size,
  });

  final String category;
  final String fileName;
  final String mimeType;
  final int size;
}

@visibleForTesting
DirectUploadInitMetadata resolveDirectUploadInitMetadata({
  required String category,
  required String fileName,
  required String mimeType,
  required int size,
  DirectUploadSession? persistedSession,
}) {
  if (persistedSession == null) {
    return DirectUploadInitMetadata(
      category: category,
      fileName: fileName,
      mimeType: mimeType,
      size: size,
    );
  }
  if (persistedSession.size != size) {
    throw const DirectUploadException('本地文件已变化，无法继续原上传任务');
  }
  return DirectUploadInitMetadata(
    category: persistedSession.category,
    fileName: persistedSession.fileName,
    mimeType: persistedSession.mimeType,
    size: persistedSession.size,
  );
}

/// Amazon S3 直传协调器。
///
/// 后端是上传状态的权威来源；本地只保存恢复索引，让消息重试在重启后复用同一幂等键。
/// 分片是否已上传始终向后端/S3 查询，不能仅凭本地记录推断。
class S3DirectUploadService {
  S3DirectUploadService(this._apiClient, {Dio? directClient})
      : _directClient = directClient ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(minutes: 10),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

  static const _sessionPrefix = 's3_direct_upload_session_v1:';
  static const _maxAttempts = 3;
  static const _singleUploadLimit = 100 * 1024 * 1024;

  final ApiClient _apiClient;
  final Dio _directClient;
  final DirectUploadSingleFlight<Map<String, dynamic>?> _uploadSingleFlight =
      DirectUploadSingleFlight<Map<String, dynamic>?>();
  final Map<String, _CachedAccessURL> _accessURLCache =
      <String, _CachedAccessURL>{};

  Future<List<DirectUploadSession>> pendingSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = <DirectUploadSession>[];
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_sessionPrefix)) continue;
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final value = jsonDecode(raw);
        if (value is! Map) continue;
        final session = DirectUploadSession.fromJson(
          key.substring(_sessionPrefix.length),
          Map<String, dynamic>.from(value),
        );
        if (session != null) sessions.add(session);
      } catch (_) {}
    }
    sessions.sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return sessions;
  }

  Future<bool> hasPendingSession(String clientRequestId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('$_sessionPrefix$clientRequestId');
  }

  Future<void> forgetPendingSession(String clientRequestId) =>
      _removeSession(clientRequestId);

  Future<Map<String, dynamic>?> tryUpload({
    required String clientRequestId,
    required String category,
    required String fileName,
    required String mimeType,
    String? filePath,
    Uint8List? bytes,
    DirectUploadProgress? onProgress,
    CancelToken? cancelToken,
    bool retainSessionUntilAcknowledged = false,
  }) {
    return _uploadSingleFlight.run(clientRequestId, () {
      return _tryUpload(
        clientRequestId: clientRequestId,
        category: category,
        fileName: fileName,
        mimeType: mimeType,
        filePath: filePath,
        bytes: bytes,
        onProgress: onProgress,
        cancelToken: cancelToken,
        retainSessionUntilAcknowledged: retainSessionUntilAcknowledged,
      );
    });
  }

  Future<Map<String, dynamic>?> _tryUpload({
    required String clientRequestId,
    required String category,
    required String fileName,
    required String mimeType,
    String? filePath,
    Uint8List? bytes,
    DirectUploadProgress? onProgress,
    CancelToken? cancelToken,
    bool retainSessionUntilAcknowledged = false,
  }) async {
    // 返回 null 表示直传能力不可用或对象存储传输已明确失败，调用方可降级到传统上传。
    // complete 阶段的结果具有歧义，仍抛错，避免同一消息绑定两个不同对象。
    if ((filePath == null || filePath.trim().isEmpty) && bytes == null) {
      throw ArgumentError('filePath or bytes is required');
    }
    final size = bytes?.length ?? await File(filePath!).length();
    final persistedSession = await _loadSession(clientRequestId);
    final initMetadata = resolveDirectUploadInitMetadata(
      category: category,
      fileName: fileName,
      mimeType: mimeType,
      size: size,
      persistedSession: persistedSession,
    );
    // A single PUT exposes the full-object SHA-256 when the signed checksum
    // header is supplied. Multipart SHA-256 is composite and is intentionally
    // kept out of this P0 full-file comparison.
    final checksumSHA256 = size < _singleUploadLimit
        ? await computeDirectUploadSHA256(filePath: filePath, bytes: bytes)
        : null;
    final init = await _apiClient.post<Map<String, dynamic>>(
      '/media/uploads/init',
      data: <String, dynamic>{
        'client_request_id': clientRequestId,
        'category': initMetadata.category,
        'file_name': initMetadata.fileName,
        'size': initMetadata.size,
        'mime_type': initMetadata.mimeType,
        if (checksumSHA256 != null) 'checksum_sha256': checksumSHA256,
      },
      fromJson: _asMap,
      cancelToken: cancelToken,
      receiveTimeout: const Duration(minutes: 35),
    );
    if (!init.isSuccess || init.data == null) {
      if (_isDirectUploadUnavailable(init)) return null;
      throw DirectUploadException(init.message);
    }

    final session = init.data!;
    final uploadId = session['upload_id']?.toString() ?? '';
    if (uploadId.isEmpty) {
      throw const DirectUploadException('服务端未返回上传任务 ID');
    }
    if (session['status'] == 'uploaded' || session['status'] == 'bound') {
      // 媒体上传完成不等于聊天消息已确认；需要可靠发送时保留会话，直到消息 ACK 后显式清理。
      if (retainSessionUntilAcknowledged) {
        await _saveSession(clientRequestId, <String, dynamic>{
          'upload_id': uploadId,
          'category': initMetadata.category,
          'file_name': initMetadata.fileName,
          'mime_type': initMetadata.mimeType,
          'size': initMetadata.size,
          'file_path': filePath,
          'completed': true,
          'updated_at': DateTime.now().toIso8601String(),
        });
      } else {
        await _removeSession(clientRequestId);
      }
      return session;
    }

    await _saveSession(clientRequestId, <String, dynamic>{
      'upload_id': uploadId,
      'category': initMetadata.category,
      'file_name': initMetadata.fileName,
      'mime_type': initMetadata.mimeType,
      'size': initMetadata.size,
      'file_path': filePath,
      'updated_at': DateTime.now().toIso8601String(),
    });

    try {
      final mode = session['mode']?.toString() ?? 'single';
      if (mode == 'multipart') {
        await _uploadMultipart(
          uploadId: uploadId,
          session: session,
          size: size,
          filePath: filePath,
          bytes: bytes,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
      } else {
        await _uploadSingle(
          session: session,
          size: size,
          filePath: filePath,
          bytes: bytes,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
      }
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) {
        try {
          await abort(uploadId);
        } finally {
          await _removeSession(clientRequestId);
        }
        rethrow;
      }
      await _abortAndForgetForProxyFallback(
        uploadId: uploadId,
        clientRequestId: clientRequestId,
        error: error,
      );
      return null;
    } on DirectUploadProxyFallbackException catch (error) {
      await _abortAndForgetForProxyFallback(
        uploadId: uploadId,
        clientRequestId: clientRequestId,
        error: error,
      );
      return null;
    }

    // Do not proxy-fallback after S3 reports the object upload as successful:
    // a timeout/error here cannot prove whether complete committed server-side.
    final completed = await _apiClient.post<Map<String, dynamic>>(
      '/media/uploads/$uploadId/complete',
      data: const <String, dynamic>{},
      fromJson: _asMap,
      cancelToken: cancelToken,
      receiveTimeout: const Duration(minutes: 35),
    );
    if (!completed.isSuccess || completed.data == null) {
      throw DirectUploadException(completed.message);
    }
    if (retainSessionUntilAcknowledged) {
      await _saveSession(clientRequestId, <String, dynamic>{
        'upload_id': uploadId,
        'category': initMetadata.category,
        'file_name': initMetadata.fileName,
        'mime_type': initMetadata.mimeType,
        'size': initMetadata.size,
        'file_path': filePath,
        'completed': true,
        'updated_at': DateTime.now().toIso8601String(),
      });
    } else {
      await _removeSession(clientRequestId);
    }
    return completed.data!;
  }

  Future<void> _uploadSingle({
    required Map<String, dynamic> session,
    required int size,
    String? filePath,
    Uint8List? bytes,
    DirectUploadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    final url = session['put_url']?.toString() ?? '';
    if (url.isEmpty) {
      throw const DirectUploadProxyFallbackException(
        '服务端未返回 S3 上传地址',
      );
    }
    final headers = _stringMap(session['headers']);
    headers[Headers.contentLengthHeader] = size;

    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final data = bytes ?? File(filePath!).openRead();
        await _directClient.put<void>(
          url,
          data: data,
          options: Options(
            headers: headers,
            responseType: ResponseType.plain,
            validateStatus: (status) =>
                status != null && status >= 200 && status < 300,
          ),
          onSendProgress: onProgress,
          cancelToken: cancelToken,
        );
        return;
      } catch (error) {
        lastError = error;
        if (error is DioException && CancelToken.isCancel(error)) rethrow;
        if (attempt < _maxAttempts) {
          await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
        }
      }
    }
    throw DirectUploadProxyFallbackException('S3 上传失败：$lastError');
  }

  Future<void> _uploadMultipart({
    required String uploadId,
    required Map<String, dynamic> session,
    required int size,
    String? filePath,
    Uint8List? bytes,
    DirectUploadProgress? onProgress,
    CancelToken? cancelToken,
  }) async {
    final partSize = _asInt(session['part_size']);
    final partCount = _asInt(session['part_count']);
    if (partSize <= 0 || partCount <= 0) {
      throw const DirectUploadProxyFallbackException('分片上传参数无效');
    }
    final partRanges = planDirectUploadParts(size, partSize);
    if (partRanges.length != partCount) {
      throw const DirectUploadProxyFallbackException(
        '分片数量与文件大小不匹配',
      );
    }

    // 每次恢复都从服务端读取已完成分片，避免本地崩溃点与 S3 实际状态不一致。
    final status = await _apiClient.get<Map<String, dynamic>>(
      '/media/uploads/$uploadId',
      fromJson: _asMap,
      cancelToken: cancelToken,
    );
    if (!status.isSuccess || status.data == null) {
      throw DirectUploadProxyFallbackException(status.message);
    }
    final uploaded = <int>{};
    var completedBytes = 0;
    final rawParts = status.data!['uploaded_parts'];
    if (rawParts is List) {
      for (final raw in rawParts) {
        if (raw is! Map) continue;
        final part = Map<String, dynamic>.from(raw);
        final number = _asInt(part['part_number']);
        if (number > 0) {
          uploaded.add(number);
          completedBytes += _asInt(part['size']);
        }
      }
    }
    debugPrint(
      '[S3DirectUpload] resume upload=$uploadId '
      'uploaded_parts=${uploaded.toList()..sort()}',
    );
    onProgress?.call(completedBytes.clamp(0, size).toInt(), size);

    for (final range in partRanges) {
      final number = range.number;
      if (uploaded.contains(number)) {
        debugPrint(
          '[S3DirectUpload] skip completed part upload=$uploadId part=$number',
        );
        continue;
      }
      final chunk = await _readChunk(
        start: range.start,
        length: range.length,
        filePath: filePath,
        bytes: bytes,
      );

      Object? lastError;
      var sent = false;
      for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
        try {
          debugPrint(
            '[S3DirectUpload] upload part upload=$uploadId '
            'part=$number attempt=$attempt',
          );
          final presigned = await _presignPart(uploadId, number, cancelToken);
          final headers = _stringMap(presigned['headers']);
          headers[Headers.contentLengthHeader] = chunk.length;
          await _directClient.put<void>(
            presigned['put_url']?.toString() ?? '',
            data: chunk,
            options: Options(
              headers: headers,
              responseType: ResponseType.plain,
              validateStatus: (status) =>
                  status != null && status >= 200 && status < 300,
            ),
            onSendProgress: (partSent, _) {
              onProgress?.call(
                (completedBytes + partSent).clamp(0, size).toInt(),
                size,
              );
            },
            cancelToken: cancelToken,
          );
          sent = true;
          debugPrint(
            '[S3DirectUpload] uploaded part upload=$uploadId part=$number',
          );
          break;
        } catch (error) {
          lastError = error;
          if (error is DioException && CancelToken.isCancel(error)) rethrow;
          if (attempt < _maxAttempts) {
            await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
          }
        }
      }
      if (!sent) {
        throw DirectUploadProxyFallbackException(
          'S3 第 $number 片上传失败：$lastError',
        );
      }
      completedBytes += chunk.length;
      onProgress?.call(completedBytes.clamp(0, size).toInt(), size);
    }
  }

  Future<Map<String, dynamic>> _presignPart(
    String uploadId,
    int partNumber,
    CancelToken? cancelToken,
  ) async {
    final response = await _apiClient.post<Map<String, dynamic>>(
      '/media/uploads/$uploadId/parts/presign',
      data: <String, dynamic>{
        'part_numbers': <int>[partNumber],
      },
      fromJson: _asMap,
      cancelToken: cancelToken,
    );
    if (!response.isSuccess || response.data == null) {
      throw DirectUploadProxyFallbackException(response.message);
    }
    final parts = response.data!['parts'];
    if (parts is! List || parts.isEmpty || parts.first is! Map) {
      throw const DirectUploadProxyFallbackException(
        '服务端未返回分片上传地址',
      );
    }
    return Map<String, dynamic>.from(parts.first as Map);
  }

  Future<Uint8List> _readChunk({
    required int start,
    required int length,
    String? filePath,
    Uint8List? bytes,
  }) async {
    if (bytes != null) {
      return Uint8List.sublistView(bytes, start, start + length);
    }
    return readDirectUploadFileChunk(
      filePath: filePath!,
      start: start,
      length: length,
    );
  }

  Future<void> abort(String uploadId) async {
    if (uploadId.trim().isEmpty) return;
    await _apiClient.post<Map<String, dynamic>>(
      '/media/uploads/$uploadId/abort',
      data: const <String, dynamic>{},
      fromJson: _asMap,
    );
  }

  Future<void> _abortAndForgetForProxyFallback({
    required String uploadId,
    required String clientRequestId,
    required Object error,
  }) async {
    debugPrint(
      '[S3DirectUpload] direct transfer failed, falling back to proxy: $error',
    );
    try {
      await abort(uploadId);
    } catch (abortError) {
      debugPrint('[S3DirectUpload] abort before proxy fallback failed: '
          '$abortError');
    } finally {
      await _removeSession(clientRequestId);
    }
  }

  Future<String> resolveAccessURL(
    String mediaId, {
    bool forceRefresh = false,
  }) async {
    mediaId = mediaId.trim();
    if (mediaId.isEmpty) {
      throw const DirectUploadException('媒体 ID 不能为空');
    }
    final resolved = await resolveAccessURLs(
      <String>[mediaId],
      forceRefresh: forceRefresh,
    );
    final url = resolved[mediaId];
    if (url == null || url.isEmpty) {
      throw const DirectUploadException('服务端未返回媒体访问地址');
    }
    return url;
  }

  Future<Map<String, String>> resolveAccessURLs(
    Iterable<String> mediaIds, {
    bool forceRefresh = false,
  }) async {
    final ids = mediaIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const <String, String>{};

    // 私有媒体 URL 有时效性，缓存预留 30 秒安全窗口，防止渲染过程中链接刚好过期。
    final now = DateTime.now();
    final resolved = <String, String>{};
    final missing = <String>[];
    for (final mediaId in ids) {
      final cached = _accessURLCache[mediaId];
      if (!forceRefresh &&
          cached != null &&
          cached.expiresAt.isAfter(now.add(const Duration(seconds: 30)))) {
        resolved[mediaId] = cached.url;
      } else {
        missing.add(mediaId);
      }
    }
    if (missing.isEmpty) return resolved;

    final response = await _apiClient.post<Map<String, dynamic>>(
      '/media/access-urls',
      data: <String, dynamic>{'media_ids': missing},
      fromJson: _asMap,
    );
    if (response.isSuccess && response.data != null) {
      final items = response.data!['items'];
      if (items is List) {
        for (final raw in items) {
          if (raw is! Map) continue;
          final item = Map<String, dynamic>.from(raw);
          final mediaId = item['media_id']?.toString().trim() ?? '';
          final url = item['url']?.toString() ?? '';
          if (mediaId.isEmpty || url.isEmpty) continue;
          _rememberAccessURL(
            mediaId,
            url,
            item['expires_at'],
            fallbackNow: now,
          );
          resolved[mediaId] = url;
        }
        return resolved;
      }
    }

    // Rolling deployments can put a newer client in front of a backend that
    // does not yet expose the batch route. Keep the established single-item
    // endpoint as a compatibility fallback so private S3 media remains
    // downloadable during that window.
    for (var start = 0; start < missing.length; start += 6) {
      final end = math.min(start + 6, missing.length);
      await Future.wait(
        missing.sublist(start, end).map((mediaId) async {
          final legacy = await _apiClient.get<Map<String, dynamic>>(
            '/media/$mediaId/access-url',
            fromJson: _asMap,
          );
          if (!legacy.isSuccess || legacy.data == null) return;
          final url = legacy.data!['url']?.toString() ?? '';
          if (url.isEmpty) return;
          _rememberAccessURL(
            mediaId,
            url,
            legacy.data!['expires_at'],
            fallbackNow: now,
          );
          resolved[mediaId] = url;
        }),
      );
    }
    return resolved;
  }

  void _rememberAccessURL(
    String mediaId,
    String url,
    dynamic expiresAt, {
    required DateTime fallbackNow,
  }) {
    final parsedExpiry =
        DateTime.tryParse(expiresAt?.toString() ?? '')?.toLocal();
    _accessURLCache[mediaId] = _CachedAccessURL(
      url,
      parsedExpiry ?? fallbackNow.add(const Duration(minutes: 8)),
    );
  }

  bool _isDirectUploadUnavailable(ApiResponse<Map<String, dynamic>> response) {
    return shouldFallbackToProxyUpload(
      code: response.code,
      message: response.message,
    );
  }

  Future<void> _saveSession(
    String clientRequestId,
    Map<String, dynamic> value,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_sessionPrefix$clientRequestId',
      jsonEncode(value),
    );
  }

  Future<DirectUploadSession?> _loadSession(String clientRequestId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_sessionPrefix$clientRequestId');
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return null;
      return DirectUploadSession.fromJson(
        clientRequestId,
        Map<String, dynamic>.from(value),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _removeSession(String clientRequestId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_sessionPrefix$clientRequestId');
  }

  static Map<String, dynamic> _asMap(dynamic raw) =>
      Map<String, dynamic>.from(raw as Map);

  static Map<String, dynamic> _stringMap(dynamic raw) {
    if (raw is! Map) return <String, dynamic>{};
    return raw.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
  }

  static int _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}

class _CachedAccessURL {
  const _CachedAccessURL(this.url, this.expiresAt);

  final String url;
  final DateTime expiresAt;
}

@immutable
class DirectUploadSession {
  const DirectUploadSession({
    required this.clientRequestId,
    required this.uploadId,
    required this.category,
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.filePath,
    required this.updatedAt,
  });

  final String clientRequestId;
  final String uploadId;
  final String category;
  final String fileName;
  final String mimeType;
  final int size;
  final String? filePath;
  final DateTime updatedAt;

  bool get canResumeFromFile => filePath != null && filePath!.isNotEmpty;

  static DirectUploadSession? fromJson(
    String clientRequestId,
    Map<String, dynamic> json,
  ) {
    final uploadId = json['upload_id']?.toString().trim() ?? '';
    final category = json['category']?.toString().trim() ?? '';
    final fileName = json['file_name']?.toString().trim() ?? '';
    final mimeType = json['mime_type']?.toString().trim() ?? '';
    final size = S3DirectUploadService._asInt(json['size']);
    if (clientRequestId.isEmpty ||
        uploadId.isEmpty ||
        category.isEmpty ||
        fileName.isEmpty ||
        mimeType.isEmpty ||
        size <= 0) {
      return null;
    }
    final rawPath = json['file_path']?.toString().trim() ?? '';
    return DirectUploadSession(
      clientRequestId: clientRequestId,
      uploadId: uploadId,
      category: category,
      fileName: fileName,
      mimeType: mimeType,
      size: size,
      filePath: rawPath.isEmpty ? null : rawPath,
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class DirectUploadException implements Exception {
  const DirectUploadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A failure that happened before the direct-upload object was completed.
///
/// The coordinator can safely abort that session and let the caller retry the
/// same local file through the authenticated proxy upload endpoint.
class DirectUploadProxyFallbackException extends DirectUploadException {
  const DirectUploadProxyFallbackException(super.message);
}
