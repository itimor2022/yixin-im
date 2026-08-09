// 文件用途：提供 clipboard image 在 Web 平台的实现，服务于通用工具。
// 核心逻辑：实现 clipboard image 的 Web 平台分支，适配浏览器 API 和资源生命周期，并保持与原生实现相同的调用契约。
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

// 关键声明：clipboard image web 是 Web 平台实现，负责把浏览器资源和异步生命周期适配为跨平台接口。
// 流程逻辑：`readImageFromClipboard` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
/// Web 平台：从剪贴板读取图片字节
Future<Uint8List?> readImageFromClipboard() async {
  try {
    // 浏览器通常要求 HTTPS、安全上下文、用户手势和剪贴板权限，任一不满足均回退 null。
    final clipboard = html.window.navigator.clipboard;
    if (clipboard == null) return null;

    // 当前 API 只消费 file 类型的 image/*，文本中的 data URL 不在此处解析。
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
        // 等待 FileReader 完成后再读取 result，避免返回仍由浏览器异步填充的对象。
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
