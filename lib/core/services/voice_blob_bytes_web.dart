import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// 把 `blob:https://...` URL 拉成 Uint8List，供 dio MultipartFile.fromBytes 上传。
///
/// 走 XHR + arraybuffer 是浏览器里读 blob 最简单的通道：
///   - fetch() 也行，但 `package:web` 的 Response API 拿 bytes 稍绕；
///   - 匹配当前项目已在用的 `package:web` + `dart:js_interop` 新范式；
///   - 对上只暴露一个 Future<Uint8List>，message_provider 的调用点不用感知。
Future<Uint8List> readBlobBytes(String blobUrl) async {
  final xhr = web.XMLHttpRequest();
  xhr.open('GET', blobUrl);
  xhr.responseType = 'arraybuffer';

  final completer = Completer<Uint8List>();

  // XHR 的 onload/onerror EventHandler 类型是可空 JSFunction，
  // 用无参 Dart 闭包 + `.toJS` 是本项目其它 web 侧代码统一的写法。
  xhr.onload = (() {
    try {
      final buffer = (xhr.response as JSArrayBuffer).toDart;
      if (!completer.isCompleted) {
        completer.complete(buffer.asUint8List());
      }
    } catch (e, st) {
      if (!completer.isCompleted) {
        completer.completeError(e, st);
      }
    }
  }).toJS;

  xhr.onerror = (() {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError('无法读取 blob URL 内容: $blobUrl'),
      );
    }
  }).toJS;

  xhr.send();
  return completer.future;
}
