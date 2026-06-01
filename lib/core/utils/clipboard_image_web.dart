import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web 平台：从剪贴板读取图片字节
/// 使用 package:web + dart:js_interop 替代已废弃的 dart:html
/// 支持 Chrome 86+ / Edge 86+（Firefox 暂不支持 clipboard.read()）
Future<Uint8List?> readImageFromClipboard() async {
  try {
    final clipboard = web.window.navigator.clipboard;

    // clipboard.read() → JSPromise<JSArray<ClipboardItem>>
    final jsItems = await clipboard.read().toDart;

    // JSArray<ClipboardItem> → List<ClipboardItem>
    final items = jsItems.toDart;

    for (final item in items) {
      // types: JSArray<JSString> → List<JSString>
      final typeList = item.types.toDart;

      String? imageType;
      for (final jsStr in typeList) {
        final t = jsStr.toDart;
        if (t.startsWith('image/')) {
          imageType = t;
          break;
        }
      }
      if (imageType == null) continue;

      // getType → JSPromise<Blob>
      final blob = await item.getType(imageType).toDart;

      // Blob.arrayBuffer() → JSPromise<JSArrayBuffer>
      final jsBuffer = await blob.arrayBuffer().toDart;

      // JSArrayBuffer → ByteBuffer → Uint8List
      return jsBuffer.toDart.asUint8List();
    }
  } catch (_) {
    // 用户拒绝权限、浏览器不支持 clipboard.read()，或无图片内容
  }
  return null;
}
