// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

/// Web 平台：从剪贴板读取图片字节
Future<Uint8List?> readImageFromClipboard() async {
  try {
    final clipboard = html.window.navigator.clipboard;
    if (clipboard == null) return null;

    // ClipboardItem list (Chrome 86+)
    final dataTransfer = await clipboard.read();
    final items = dataTransfer.items;
    if (items == null) return null;

    final length = items.length ?? 0;
    for (var i = 0; i < length; i++) {
      final item = items[i];
      if (item == null) continue;
      final kind = item.kind;
      final type = item.type ?? '';
      if (kind == 'file' && type.startsWith('image/')) {
        final file = item.getAsFile();
        if (file == null) continue;
        final reader = html.FileReader();
        reader.readAsArrayBuffer(file);
        await reader.onLoad.first;
        final result = reader.result;
        if (result is Uint8List) return result;
        if (result is ByteBuffer) return result.asUint8List();
        if (result is List<int>) return Uint8List.fromList(result);
      }
    }
  } catch (_) {
    // 用户拒绝权限或浏览器不支持
  }
  return null;
}
