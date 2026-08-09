import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/api/api_client.dart';
import 'package:generic_im/core/services/s3_direct_upload_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('falls back to proxy upload for current direct-upload gate codes', () {
    for (final code in <int>[1430, 1431, 1432, 1433]) {
      expect(
        shouldFallbackToProxyUpload(code: code, message: ''),
        isTrue,
        reason: 'code $code should use the proxy upload fallback',
      );
    }
  });

  test('preserves legacy fallback codes without bypassing rate limits', () {
    for (final code in <int>[4601, 4602, 4603, 4604]) {
      expect(
        shouldFallbackToProxyUpload(code: code, message: ''),
        isTrue,
      );
    }
    expect(
      shouldFallbackToProxyUpload(code: 1429, message: '上传请求过于频繁'),
      isFalse,
    );
    expect(
      shouldFallbackToProxyUpload(code: 401, message: '请先登录'),
      isFalse,
    );
  });

  test('only pre-completion direct transfer failures request proxy fallback',
      () {
    expect(
      const DirectUploadProxyFallbackException('S3 PUT failed'),
      isA<DirectUploadException>(),
    );
    expect(
      const DirectUploadException('complete response timed out'),
      isNot(isA<DirectUploadProxyFallbackException>()),
    );
  });

  test('coalesces concurrent direct uploads with the same request id',
      () async {
    final singleFlight = DirectUploadSingleFlight<int>();
    final completer = Completer<int>();
    var starts = 0;

    Future<int> start() {
      return singleFlight.run('message-1', () {
        starts++;
        return completer.future;
      });
    }

    final first = start();
    final second = start();
    expect(starts, 1);

    completer.complete(42);
    expect(await Future.wait(<Future<int>>[first, second]), <int>[42, 42]);

    expect(await singleFlight.run('message-1', () async => 7), 7);
    expect(starts, 1);
  });

  test('plans consecutive multipart ranges with a short final part', () {
    final parts = planDirectUploadParts(34, 16);

    expect(parts, hasLength(3));
    expect(
      parts.map((part) => (part.number, part.start, part.length)).toList(),
      <(int, int, int)>[
        (1, 0, 16),
        (2, 16, 16),
        (3, 32, 2),
      ],
    );
  });

  test('does not plan parts for invalid sizes', () {
    expect(planDirectUploadParts(0, 16), isEmpty);
    expect(planDirectUploadParts(10, 0), isEmpty);
  });

  test('plans the 100 MB P1 boundary into 16 MB parts', () {
    const megabyte = 1024 * 1024;
    final parts = planDirectUploadParts(100 * megabyte, 16 * megabyte);

    expect(parts, hasLength(7));
    expect(parts.first.length, 16 * megabyte);
    expect(parts.last.start, 96 * megabyte);
    expect(parts.last.length, 4 * megabyte);
  });

  test('computes a stable SHA-256 for direct-upload bytes', () async {
    final checksum = await computeDirectUploadSHA256(
      bytes: Uint8List.fromList(<int>[97, 98, 99]),
    );

    expect(
      checksum,
      'ba7816bf8f01cfea414140de5dae2223'
      'b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('restores a resumable direct-upload session from persisted state', () {
    final session = DirectUploadSession.fromJson('message-1', {
      'upload_id': 'media-1',
      'category': 'video',
      'file_name': 'clip.mp4',
      'mime_type': 'video/mp4',
      'size': 104857600,
      'file_path': '/storage/emulated/0/Movies/clip.mp4',
      'updated_at': '2026-07-27T12:00:00Z',
    });

    expect(session, isNotNull);
    expect(session!.clientRequestId, 'message-1');
    expect(session.uploadId, 'media-1');
    expect(session.canResumeFromFile, isTrue);
  });

  test('rejects incomplete persisted upload sessions', () {
    expect(
      DirectUploadSession.fromJson('message-1', {
        'upload_id': 'media-1',
        'category': 'video',
      }),
      isNull,
    );
  });

  test('reuses persisted init metadata when resuming after restart', () {
    final persisted = DirectUploadSession.fromJson('message-1', {
      'upload_id': 'media-1',
      'category': 'video',
      'file_name': 'video_1785157916057.mp4',
      'mime_type': 'video/mp4',
      'size': 104857600,
      'file_path': '/storage/emulated/0/Movies/clip.mp4',
      'updated_at': '2026-07-27T12:00:00Z',
    });

    final metadata = resolveDirectUploadInitMetadata(
      category: 'video',
      fileName: 'video_message-1.mp4',
      mimeType: 'video/mp4',
      size: 104857600,
      persistedSession: persisted,
    );

    expect(metadata.fileName, 'video_1785157916057.mp4');
    expect(metadata.category, 'video');
    expect(metadata.mimeType, 'video/mp4');
    expect(metadata.size, 104857600);
  });

  test('rejects resuming a persisted session with a changed local file', () {
    final persisted = DirectUploadSession.fromJson('message-1', {
      'upload_id': 'media-1',
      'category': 'video',
      'file_name': 'clip.mp4',
      'mime_type': 'video/mp4',
      'size': 104857600,
      'file_path': '/storage/emulated/0/Movies/clip.mp4',
      'updated_at': '2026-07-27T12:00:00Z',
    });

    expect(
      () => resolveDirectUploadInitMetadata(
        category: 'video',
        fileName: 'clip.mp4',
        mimeType: 'video/mp4',
        size: 104857599,
        persistedSession: persisted,
      ),
      throwsA(isA<DirectUploadException>()),
    );
  });

  test('falls back to legacy access-url when batch route is unavailable',
      () async {
    final api = _LegacyAccessURLApiClient();
    final service = S3DirectUploadService(api);

    final resolved = await service.resolveAccessURLs(
      <String>['media-a', 'media-b'],
    );

    expect(api.batchCalls, 1);
    expect(api.singleCalls, 2);
    expect(
      resolved,
      <String, String>{
        'media-a': 'https://signed.example.com/media-a',
        'media-b': 'https://signed.example.com/media-b',
      },
    );
  });

  test('reads an exact file chunk before closing the random access file',
      () async {
    final directory = await Directory.systemTemp.createTemp('direct-upload-');
    final file = File('${directory.path}/fixture.bin');
    try {
      await file.writeAsBytes(List<int>.generate(64, (index) => index));

      final chunk = await readDirectUploadFileChunk(
        filePath: file.path,
        start: 17,
        length: 23,
      );

      expect(chunk, List<int>.generate(23, (index) => index + 17));
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

class _LegacyAccessURLApiClient extends ApiClient {
  _LegacyAccessURLApiClient() : super.forTesting();

  int batchCalls = 0;
  int singleCalls = 0;

  @override
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    T Function(dynamic)? fromJson,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    if (path == '/media/access-urls') {
      batchCalls++;
      return ApiResponse<T>(code: 404, message: 'Not Found');
    }
    throw StateError('Unexpected POST $path');
  }

  @override
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    CancelToken? cancelToken,
  }) async {
    singleCalls++;
    final mediaId = path.split('/')[2];
    final data = <String, dynamic>{
      'media_id': mediaId,
      'url': 'https://signed.example.com/$mediaId',
      'expires_at': '2026-07-29T16:00:00Z',
    };
    return ApiResponse<T>(
      code: 0,
      message: '',
      data: (fromJson?.call(data) ?? data) as T,
    );
  }
}
