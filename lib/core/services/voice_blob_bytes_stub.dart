import 'dart:typed_data';

/// Native 端占位实现。Native 上语音走 File 路径而非 blob URL，本函数不会被调用。
/// 万一被误调，抛异常而不是静默返回 null，便于早发现问题。
Future<Uint8List> readBlobBytes(String blobUrl) async {
  throw UnsupportedError(
    'readBlobBytes 只在 Web 端可用；Native 端请直接读文件。got=$blobUrl',
  );
}
