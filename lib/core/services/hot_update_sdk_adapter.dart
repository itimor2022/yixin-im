import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart' as shorebird;
import 'package:universal_io/io.dart';

import 'api/hot_update_service.dart';

class HotUpdateSupportStatus {
  final bool available;
  final bool sdkIntegrated;
  final String platform;
  final String message;

  const HotUpdateSupportStatus({
    required this.available,
    required this.sdkIntegrated,
    this.platform = '',
    this.message = '',
  });
}

class HotUpdateApplyResult {
  final bool success;
  final bool requiresRestart;
  final String message;

  const HotUpdateApplyResult({
    required this.success,
    this.requiresRestart = false,
    this.message = '',
  });
}

enum HotUpdateProgressPhase {
  preparing,
  downloading,
  verifying,
  applyingPatch,
  launchingInstaller,
}

class HotUpdateProgress {
  final HotUpdateProgressPhase phase;
  final int receivedBytes;
  final int totalBytes;
  final double? progress;
  final String message;

  const HotUpdateProgress({
    required this.phase,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.progress,
    this.message = '',
  });
}

typedef HotUpdateProgressCallback = void Function(HotUpdateProgress progress);

class HotUpdateSdkAdapter {
  static const MethodChannel _channel = MethodChannel(
    'com.gaoranim/hot_update',
  );
  static const int _shorebirdAvailabilityRetryAttempts = 4;

  final Dio _downloadClient;
  final shorebird.ShorebirdUpdater _shorebirdUpdater;

  HotUpdateSdkAdapter({Dio? downloadClient})
      : _shorebirdUpdater = shorebird.ShorebirdUpdater(),
        _downloadClient = downloadClient ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(minutes: 20),
                sendTimeout: const Duration(minutes: 5),
                followRedirects: true,
                responseType: ResponseType.bytes,
                validateStatus: (status) => status != null && status < 400,
              ),
            );

  Future<HotUpdateSupportStatus> getSupportStatus() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return const HotUpdateSupportStatus(
        available: false,
        sdkIntegrated: false,
        message: 'hot_update_platform_not_supported',
      );
    }

    if (_shorebirdUpdater.isAvailable) {
      return HotUpdateSupportStatus(
        available: true,
        sdkIntegrated: true,
        platform: Platform.isIOS ? 'ios' : 'android',
        message: 'shorebird_engine_ready',
      );
    }

    try {
      final result = await _channel.invokeMethod<dynamic>('isSupported');
      if (result is bool) {
        return HotUpdateSupportStatus(
          available: result,
          sdkIntegrated: result,
          platform: Platform.isIOS ? 'ios' : 'android',
          message: result ? 'self_hosted_updater_ready' : 'sdk_not_available',
        );
      }

      if (result is Map) {
        final map = Map<String, dynamic>.from(result);
        return HotUpdateSupportStatus(
          available: map['available'] == true,
          sdkIntegrated: map['sdkIntegrated'] == true,
          platform: map['platform']?.toString() ?? '',
          message: map['message']?.toString() ?? '',
        );
      }

      return const HotUpdateSupportStatus(
        available: false,
        sdkIntegrated: false,
        message: 'hot_update_sdk_not_available',
      );
    } on MissingPluginException {
      return const HotUpdateSupportStatus(
        available: false,
        sdkIntegrated: false,
        message: 'hot_update_sdk_not_available',
      );
    } catch (e) {
      debugPrint('[HotUpdateSDK] getSupportStatus error: $e');
      return HotUpdateSupportStatus(
        available: false,
        sdkIntegrated: false,
        message: e.toString(),
      );
    }
  }

  Future<bool> isSupported() async {
    final status = await getSupportStatus();
    return status.available && status.sdkIntegrated;
  }

  Future<bool> supportsShorebird() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      return false;
    }
    return _shorebirdUpdater.isAvailable;
  }

  Future<HotUpdateSupportStatus> getSupportStatusForPatch(
    HotUpdatePatch patch,
  ) async {
    if (patch.deliveryMode != 'shorebird') {
      return getSupportStatus();
    }

    if (!(Platform.isAndroid || Platform.isIOS)) {
      return const HotUpdateSupportStatus(
        available: false,
        sdkIntegrated: false,
        message: 'hot_update_platform_not_supported',
      );
    }

    if (_shorebirdUpdater.isAvailable) {
      return HotUpdateSupportStatus(
        available: true,
        sdkIntegrated: true,
        platform: Platform.isIOS ? 'ios' : 'android',
        message: 'shorebird_engine_ready',
      );
    }

    return HotUpdateSupportStatus(
      available: true,
      sdkIntegrated: false,
      platform: Platform.isIOS ? 'ios' : 'android',
      message: 'hot_update_sdk_not_integrated',
    );
  }

  Future<int?> readCurrentShorebirdPatchNumber() async {
    if (!_shorebirdUpdater.isAvailable) {
      return null;
    }

    try {
      final patch = await _shorebirdUpdater.readCurrentPatch();
      return patch?.number;
    } catch (e) {
      debugPrint('[HotUpdateSDK] readCurrentShorebirdPatchNumber error: $e');
      return null;
    }
  }

  Future<int?> readNextShorebirdPatchNumber() async {
    if (!_shorebirdUpdater.isAvailable) {
      return null;
    }

    try {
      final patch = await _shorebirdUpdater.readNextPatch();
      return patch?.number;
    } catch (e) {
      debugPrint('[HotUpdateSDK] readNextShorebirdPatchNumber error: $e');
      return null;
    }
  }

  Future<HotUpdateApplyResult> applyPatch(
    HotUpdatePatch patch, {
    HotUpdateProgressCallback? onProgress,
  }) async {
    if (patch.deliveryMode == 'shorebird') {
      if ((Platform.isAndroid || Platform.isIOS) &&
          _shorebirdUpdater.isAvailable) {
        return _applyShorebirdPatch(patch, onProgress: onProgress);
      }

      return const HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'hot_update_sdk_not_integrated',
      );
    }

    final supportStatus = await getSupportStatus();
    if (!supportStatus.available) {
      return HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: supportStatus.message.isEmpty
            ? 'hot_update_sdk_not_available'
            : supportStatus.message,
      );
    }
    if (!supportStatus.sdkIntegrated) {
      return HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: supportStatus.message.isEmpty
            ? 'hot_update_sdk_not_integrated'
            : supportStatus.message,
      );
    }

    if (Platform.isAndroid) {
      return _applyAndroidPatch(patch, onProgress: onProgress);
    }
    if (Platform.isIOS) {
      return _applyIOSPatch(patch, onProgress: onProgress);
    }

    return const HotUpdateApplyResult(
      success: false,
      requiresRestart: false,
      message: 'hot_update_platform_not_supported',
    );
  }

  Future<HotUpdateApplyResult> _applyShorebirdPatch(
    HotUpdatePatch patch, {
    HotUpdateProgressCallback? onProgress,
  }) async {
    final track = _resolveShorebirdTrack(patch.channel);

    _emitProgress(
      onProgress,
      const HotUpdateProgress(
        phase: HotUpdateProgressPhase.preparing,
        progress: null,
        message: '正在检查补丁...',
      ),
    );

    try {
      final status = await _waitForShorebirdUpdateAvailability(
        track: track,
        onProgress: onProgress,
      );
      if (status == shorebird.UpdateStatus.upToDate) {
        return const HotUpdateApplyResult(
          success: false,
          requiresRestart: false,
          message: 'shorebird_no_update_available_after_retry',
        );
      }

      if (status == shorebird.UpdateStatus.restartRequired) {
        return const HotUpdateApplyResult(
          success: true,
          requiresRestart: true,
          message: 'shorebird_restart_required',
        );
      }

      if (status == shorebird.UpdateStatus.unavailable) {
        return const HotUpdateApplyResult(
          success: false,
          requiresRestart: false,
          message: 'hot_update_sdk_not_integrated',
        );
      }

      _emitProgress(
        onProgress,
        const HotUpdateProgress(
          phase: HotUpdateProgressPhase.downloading,
          progress: null,
          message: '正在下载补丁...',
        ),
      );

      final updateResult = await _downloadShorebirdPatchWithRetry(
        track: track,
        onProgress: onProgress,
      );
      if (updateResult != null) {
        return updateResult;
      }

      _emitProgress(
        onProgress,
        const HotUpdateProgress(
          phase: HotUpdateProgressPhase.applyingPatch,
          progress: 1,
          message: '补丁已下载完成，重启应用后生效。',
        ),
      );

      return const HotUpdateApplyResult(
        success: true,
        requiresRestart: true,
        message: 'shorebird_update_downloaded',
      );
    } on shorebird.UpdateException catch (e) {
      switch (e.reason) {
        case shorebird.UpdateFailureReason.noUpdate:
          return const HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: 'shorebird_no_update_available_after_retry',
          );
        case shorebird.UpdateFailureReason.downloadFailed:
          return const HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: 'shorebird_download_failed',
          );
        case shorebird.UpdateFailureReason.installFailed:
          return const HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: 'shorebird_install_failed',
          );
        case shorebird.UpdateFailureReason.unknown:
          return HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: 'shorebird_update_failed:${e.message}',
          );
      }
    } catch (e) {
      debugPrint('[HotUpdateSDK] Shorebird applyPatch error: $e');
      return HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'shorebird_update_failed:$e',
      );
    }
  }

  Future<shorebird.UpdateStatus> _waitForShorebirdUpdateAvailability({
    required shorebird.UpdateTrack track,
    required HotUpdateProgressCallback? onProgress,
  }) async {
    for (var attempt = 1;
        attempt <= _shorebirdAvailabilityRetryAttempts;
        attempt++) {
      final status = await _shorebirdUpdater.checkForUpdate(track: track);
      if (status != shorebird.UpdateStatus.upToDate) {
        return status;
      }

      if (attempt >= _shorebirdAvailabilityRetryAttempts) {
        return status;
      }

      _emitProgress(
        onProgress,
        HotUpdateProgress(
          phase: HotUpdateProgressPhase.preparing,
          progress: null,
          message:
              '补丁正在同步，正在自动重试 (${attempt + 1}/$_shorebirdAvailabilityRetryAttempts)...',
        ),
      );
      await Future<void>.delayed(Duration(seconds: attempt < 3 ? 2 : 3));
    }

    return shorebird.UpdateStatus.upToDate;
  }

  Future<HotUpdateApplyResult?> _downloadShorebirdPatchWithRetry({
    required shorebird.UpdateTrack track,
    required HotUpdateProgressCallback? onProgress,
  }) async {
    for (var attempt = 1;
        attempt <= _shorebirdAvailabilityRetryAttempts;
        attempt++) {
      try {
        await _shorebirdUpdater.update(track: track);
        return null;
      } on shorebird.UpdateException catch (e) {
        if (e.reason == shorebird.UpdateFailureReason.noUpdate) {
          if (attempt >= _shorebirdAvailabilityRetryAttempts) {
            return const HotUpdateApplyResult(
              success: false,
              requiresRestart: false,
              message: 'shorebird_no_update_available_after_retry',
            );
          }

          _emitProgress(
            onProgress,
            HotUpdateProgress(
              phase: HotUpdateProgressPhase.downloading,
              progress: null,
              message:
                  '补丁正在同步，正在重新拉取 (${attempt + 1}/$_shorebirdAvailabilityRetryAttempts)...',
            ),
          );
          await Future<void>.delayed(
            Duration(seconds: attempt < 3 ? 2 : 3),
          );
          continue;
        }

        if (e.reason == shorebird.UpdateFailureReason.downloadFailed) {
          return const HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: 'shorebird_download_failed',
          );
        }
        if (e.reason == shorebird.UpdateFailureReason.installFailed) {
          return const HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: 'shorebird_install_failed',
          );
        }
        return HotUpdateApplyResult(
          success: false,
          requiresRestart: false,
          message: 'shorebird_update_failed:${e.message}',
        );
      }
    }

    return const HotUpdateApplyResult(
      success: false,
      requiresRestart: false,
      message: 'shorebird_no_update_available_after_retry',
    );
  }

  Future<HotUpdateApplyResult> _applyAndroidPatch(
    HotUpdatePatch patch, {
    HotUpdateProgressCallback? onProgress,
  }) async {
    final uri = _normalizeUri(patch.patchUrl);
    if (uri == null || !_isHttpUri(uri)) {
      return const HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'patch_url_invalid',
      );
    }

    try {
      File? descriptorFile;
      File? packageFile;

      _emitProgress(
        onProgress,
        const HotUpdateProgress(
          phase: HotUpdateProgressPhase.preparing,
          progress: null,
          message: '正在准备下载更新包...',
        ),
      );
      final downloadDir = await _ensureHotUpdateDirectory();
      final fileName = _buildDownloadFileName(
        uri,
        fallbackExtension: '.apk',
        fallbackStem: _fallbackStem(patch),
      );
      final file =
          File('${downloadDir.path}${Platform.pathSeparator}$fileName');
      if (await file.exists()) {
        await file.delete();
      }

      await _downloadClient.download(
        uri.toString(),
        file.path,
        onReceiveProgress: (received, total) {
          final progress = total > 0 ? received / total : null;
          _emitProgress(
            onProgress,
            HotUpdateProgress(
              phase: HotUpdateProgressPhase.downloading,
              receivedBytes: received,
              totalBytes: total > 0 ? total : 0,
              progress: progress,
              message: total > 0 ? '正在下载更新包...' : '正在下载更新包，等待获取进度...',
            ),
          );
        },
      );
      _emitProgress(
        onProgress,
        const HotUpdateProgress(
          phase: HotUpdateProgressPhase.verifying,
          progress: 1,
          message: '下载完成，正在校验文件...',
        ),
      );
      final verifyError = await _verifyDownloadedFile(
        file: file,
        expectedHash: patch.patchHash,
      );
      if (verifyError != null) {
        await _safeDelete(file);
        return HotUpdateApplyResult(
          success: false,
          requiresRestart: false,
          message: verifyError,
        );
      }

      _emitProgress(
        onProgress,
        const HotUpdateProgress(
          phase: HotUpdateProgressPhase.launchingInstaller,
          progress: 1,
          message: '校验完成，正在启动安装器...',
        ),
      );
      final result = await _channel.invokeMethod<dynamic>('applyPatch', {
        'platform': 'android',
        'local_file_path': file.path,
        'file_name': fileName,
        'patch_url': uri.toString(),
      });

      return _parseApplyResult(
        result,
        defaultMessage: 'android_installer_opened',
        defaultRequiresRestart: true,
      );
    } on DioException catch (e) {
      debugPrint('[HotUpdateSDK] Android patch download failed: $e');
      return HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'patch_download_failed:${e.message ?? 'unknown'}',
      );
    } catch (e) {
      debugPrint('[HotUpdateSDK] Android applyPatch error: $e');
      return HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: e.toString(),
      );
    }
  }

  Future<HotUpdateApplyResult> _applyIOSPatch(
    HotUpdatePatch patch, {
    HotUpdateProgressCallback? onProgress,
  }) async {
    final normalizedPatchUri = _normalizeUri(patch.patchUrl);
    if (normalizedPatchUri == null) {
      return const HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'patch_url_invalid',
      );
    }

    File? descriptorFile;
    File? packageFile;

    try {
      _emitProgress(
        onProgress,
        const HotUpdateProgress(
          phase: HotUpdateProgressPhase.preparing,
          progress: null,
          message: '正在准备更新...',
        ),
      );
      final descriptorUri = _resolveIOSDescriptorUri(normalizedPatchUri);
      if (descriptorUri == null) {
        return const HotUpdateApplyResult(
          success: false,
          requiresRestart: false,
          message: 'ios_install_url_invalid',
        );
      }
      if (patch.patchHash.trim().isNotEmpty) {
        final downloadDir = await _ensureHotUpdateDirectory();
        final fileName = _buildDownloadFileName(
          descriptorUri,
          fallbackExtension: '.plist',
          fallbackStem: _fallbackStem(patch),
        );
        descriptorFile = File(
          '${downloadDir.path}${Platform.pathSeparator}$fileName',
        );
        if (await descriptorFile.exists()) {
          await descriptorFile.delete();
        }

        await _downloadClient.download(
          descriptorUri.toString(),
          descriptorFile.path,
          onReceiveProgress: (received, total) {
            final progress = total > 0 ? received / total : null;
            _emitProgress(
              onProgress,
              HotUpdateProgress(
                phase: HotUpdateProgressPhase.downloading,
                receivedBytes: received,
                totalBytes: total > 0 ? total : 0,
                progress: progress,
                message: total > 0 ? '正在下载更新描述文件...' : '正在下载更新描述文件...',
              ),
            );
          },
        );

        final descriptorText = await descriptorFile.readAsString();
        final packageUri = _extractIOSPackageUri(descriptorText, descriptorUri);
        if (packageUri == null) {
          await _safeDelete(descriptorFile);
          return const HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: 'ios_manifest_package_url_missing',
          );
        }

        packageFile = File(
          '${downloadDir.path}${Platform.pathSeparator}'
          '${_buildDownloadFileName(packageUri, fallbackExtension: '.ipa', fallbackStem: _fallbackStem(patch))}',
        );
        if (await packageFile.exists()) {
          await packageFile.delete();
        }

        await _downloadClient.download(
          packageUri.toString(),
          packageFile.path,
          onReceiveProgress: (received, total) {
            final progress = total > 0 ? received / total : null;
            _emitProgress(
              onProgress,
              HotUpdateProgress(
                phase: HotUpdateProgressPhase.downloading,
                receivedBytes: received,
                totalBytes: total > 0 ? total : 0,
                progress: progress,
                message: total > 0 ? '正在下载 iOS 安装包...' : '正在下载 iOS 安装包...',
              ),
            );
          },
        );
        _emitProgress(
          onProgress,
          const HotUpdateProgress(
            phase: HotUpdateProgressPhase.verifying,
            progress: 1,
            message: '下载完成，正在校验安装包...',
          ),
        );
        final verifyError = await _verifyDownloadedFile(
          file: packageFile,
          expectedHash: patch.patchHash,
        );
        if (verifyError != null) {
          await _safeDelete(packageFile);
          await _safeDelete(descriptorFile);
          return HotUpdateApplyResult(
            success: false,
            requiresRestart: false,
            message: verifyError,
          );
        }

        await _safeDelete(packageFile);
        await _safeDelete(descriptorFile);
      }

      _emitProgress(
        onProgress,
        const HotUpdateProgress(
          phase: HotUpdateProgressPhase.launchingInstaller,
          progress: 1,
          message: '校验完成，正在打开安装页面...',
        ),
      );
      final result = await _channel.invokeMethod<dynamic>('applyPatch', {
        'platform': 'ios',
        'patch_url': normalizedPatchUri.toString(),
      });

      return _parseApplyResult(
        result,
        defaultMessage: 'ios_install_started',
        defaultRequiresRestart: true,
      );
    } on DioException catch (e) {
      debugPrint('[HotUpdateSDK] iOS patch descriptor download failed: $e');
      return HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: 'patch_download_failed:${e.message ?? 'unknown'}',
      );
    } catch (e) {
      debugPrint('[HotUpdateSDK] iOS applyPatch error: $e');
      return HotUpdateApplyResult(
        success: false,
        requiresRestart: false,
        message: e.toString(),
      );
    } finally {
      if (packageFile != null) {
        await _safeDelete(packageFile);
      }
      if (descriptorFile != null) {
        await _safeDelete(descriptorFile);
      }
    }
  }

  Future<Directory> _ensureHotUpdateDirectory() async {
    final root = await getTemporaryDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}hot_update',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  Future<String?> _verifyDownloadedFile({
    required File file,
    required String expectedHash,
  }) async {
    final normalizedHash = expectedHash.trim();
    if (normalizedHash.isEmpty) {
      return null;
    }

    final parsed = _ParsedHash.parse(normalizedHash);
    if (parsed == null) {
      return 'patch_hash_invalid';
    }

    final actualHash = await parsed.compute(file);
    if (actualHash != parsed.hash) {
      return 'patch_hash_mismatch';
    }

    return null;
  }

  String _buildDownloadFileName(
    Uri uri, {
    required String fallbackStem,
    required String fallbackExtension,
  }) {
    final path = uri.path.trim();
    var fileName = path.isEmpty ? '' : path.split('/').last.trim();
    if (fileName.isEmpty) {
      fileName = fallbackStem + fallbackExtension;
    }

    final hasExtension = fileName.contains('.') && !fileName.endsWith('.');
    if (!hasExtension) {
      fileName += fallbackExtension;
    }

    return _sanitizeFileName(fileName);
  }

  String _sanitizeFileName(String input) {
    final sanitized = input.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (sanitized.isEmpty) {
      return 'hot_update.bin';
    }
    return sanitized;
  }

  String _fallbackStem(HotUpdatePatch patch) {
    final candidates = [
      patch.patchVersion.trim(),
      patch.targetAppVersion.trim(),
      patch.patchId.trim(),
      patch.name.trim(),
    ];
    for (final item in candidates) {
      if (item.isNotEmpty) {
        return item.replaceAll(RegExp(r'\s+'), '_');
      }
    }
    return 'hot_update_${DateTime.now().millisecondsSinceEpoch}';
  }

  Uri? _normalizeUri(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    try {
      if (trimmed.startsWith('itms-services://')) {
        return Uri.parse(trimmed);
      }
      if (trimmed.contains('://')) {
        return Uri.parse(trimmed);
      }
      return Uri.parse('https://$trimmed');
    } catch (_) {
      return null;
    }
  }

  bool _isHttpUri(Uri uri) {
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  Uri? _resolveIOSDescriptorUri(Uri patchUri) {
    if (_isIOSManifestUri(patchUri)) {
      return patchUri;
    }
    if (patchUri.scheme != 'itms-services') {
      return null;
    }
    final embeddedUrl = patchUri.queryParameters['url']?.trim();
    if (embeddedUrl == null || embeddedUrl.isEmpty) {
      return null;
    }
    final normalizedEmbeddedUri = _normalizeUri(Uri.decodeFull(embeddedUrl));
    if (normalizedEmbeddedUri == null ||
        !_isIOSManifestUri(normalizedEmbeddedUri)) {
      return null;
    }
    return normalizedEmbeddedUri;
  }

  bool _isIOSManifestUri(Uri uri) {
    if (!_isHttpUri(uri)) {
      return false;
    }
    return uri.path.toLowerCase().endsWith('.plist');
  }

  Uri? _extractIOSPackageUri(String plistContent, Uri descriptorUri) {
    final softwarePackageMatch = RegExp(
      r'<key>\s*kind\s*</key>\s*<string>\s*software-package\s*</string>.*?<key>\s*url\s*</key>\s*<string>\s*([^<]+)\s*</string>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(plistContent);
    final fallbackMatch = RegExp(
      r'<key>\s*url\s*</key>\s*<string>\s*([^<]+)\s*</string>',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(plistContent);

    final rawValue = softwarePackageMatch?.group(1)?.trim() ??
        fallbackMatch?.group(1)?.trim();
    if (rawValue == null || rawValue.isEmpty) {
      return null;
    }

    final decoded = rawValue
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'");
    final parsed = Uri.tryParse(decoded);
    if (parsed == null) {
      return null;
    }
    final resolved =
        parsed.hasScheme ? parsed : descriptorUri.resolveUri(parsed);
    if (!_isHttpUri(resolved)) {
      return null;
    }
    return resolved;
  }

  void _emitProgress(
    HotUpdateProgressCallback? callback,
    HotUpdateProgress progress,
  ) {
    if (callback == null) {
      return;
    }
    callback(progress);
  }

  shorebird.UpdateTrack _resolveShorebirdTrack(String rawChannel) {
    final channel = rawChannel.trim().toLowerCase();
    switch (channel) {
      case '':
      case 'stable':
        return shorebird.UpdateTrack.stable;
      case 'beta':
        return shorebird.UpdateTrack.beta;
      case 'staging':
        return shorebird.UpdateTrack.staging;
      default:
        return shorebird.UpdateTrack(channel);
    }
  }

  HotUpdateApplyResult _parseApplyResult(
    dynamic result, {
    required String defaultMessage,
    required bool defaultRequiresRestart,
  }) {
    if (result is Map) {
      final map = Map<String, dynamic>.from(result);
      return HotUpdateApplyResult(
        success: map['success'] == true,
        requiresRestart: map['requires_restart'] == true,
        message: map['message']?.toString() ?? defaultMessage,
      );
    }

    if (result is bool) {
      return HotUpdateApplyResult(
        success: result,
        requiresRestart: result && defaultRequiresRestart,
        message: result ? defaultMessage : 'patch_apply_failed',
      );
    }

    return HotUpdateApplyResult(
      success: false,
      requiresRestart: false,
      message: 'patch_apply_result_invalid',
    );
  }

  Future<void> _safeDelete(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}

final hotUpdateSdkAdapterProvider = Provider<HotUpdateSdkAdapter>((ref) {
  return HotUpdateSdkAdapter();
});

class _ParsedHash {
  final String algorithm;
  final String hash;

  const _ParsedHash({
    required this.algorithm,
    required this.hash,
  });

  static _ParsedHash? parse(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }

    if (normalized.startsWith('sha256:')) {
      final hash = normalized.substring('sha256:'.length);
      return _build('sha256', hash);
    }
    if (normalized.startsWith('sha1:')) {
      final hash = normalized.substring('sha1:'.length);
      return _build('sha1', hash);
    }
    if (normalized.startsWith('md5:')) {
      final hash = normalized.substring('md5:'.length);
      return _build('md5', hash);
    }

    if (RegExp(r'^[a-f0-9]{64}$').hasMatch(normalized)) {
      return _ParsedHash(algorithm: 'sha256', hash: normalized);
    }
    if (RegExp(r'^[a-f0-9]{40}$').hasMatch(normalized)) {
      return _ParsedHash(algorithm: 'sha1', hash: normalized);
    }
    if (RegExp(r'^[a-f0-9]{32}$').hasMatch(normalized)) {
      return _ParsedHash(algorithm: 'md5', hash: normalized);
    }

    return null;
  }

  static _ParsedHash? _build(String algorithm, String hash) {
    final cleaned = hash.trim().toLowerCase();
    if (cleaned.isEmpty) {
      return null;
    }
    final pattern = switch (algorithm) {
      'sha256' => RegExp(r'^[a-f0-9]{64}$'),
      'sha1' => RegExp(r'^[a-f0-9]{40}$'),
      'md5' => RegExp(r'^[a-f0-9]{32}$'),
      _ => null,
    };
    if (pattern == null || !pattern.hasMatch(cleaned)) {
      return null;
    }
    return _ParsedHash(algorithm: algorithm, hash: cleaned);
  }

  Future<String> compute(File file) async {
    final stream = file.openRead();
    switch (algorithm) {
      case 'sha256':
        return (await crypto.sha256.bind(stream).first)
            .toString()
            .toLowerCase();
      case 'sha1':
        return (await crypto.sha1.bind(stream).first).toString().toLowerCase();
      case 'md5':
        return (await crypto.md5.bind(stream).first).toString().toLowerCase();
      default:
        throw UnsupportedError('Unsupported hash algorithm: $algorithm');
    }
  }
}
