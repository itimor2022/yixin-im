// 文件用途：提供 clipboard image 在原生平台的实现，服务于通用工具。
// 核心逻辑：实现 clipboard image 的原生平台分支，封装系统权限或文件能力，并保持跨平台调用契约一致。
import 'dart:io';
import 'dart:typed_data';

import 'package:pasteboard/pasteboard.dart';

// 关键声明：clipboard image io 是原生平台实现，集中处理系统权限、文件或窗口能力，避免业务层散落平台判断。
// 流程逻辑：`readImageFromClipboard` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
Future<Uint8List?> readImageFromClipboard() async {
  try {
    // 优先读取平台直接提供的图片格式，并复制字节以脱离插件缓冲区生命周期。
    final bytes = await Pasteboard.image;
    if (bytes != null && bytes.isNotEmpty) {
      return Uint8List.fromList(bytes);
    }

    // 部分桌面应用只把图片作为文件列表写入剪贴板，此时按常见扩展名回退读取。
    final files = await Pasteboard.files();
    for (final path in files) {
      if (!_isImagePath(path)) continue;
      final file = File(path);
      if (await file.exists()) {
        final data = await file.readAsBytes();
        if (data.isNotEmpty) return data;
      }
    }
  } catch (_) {
    // 平台拒绝访问或插件无法解码时按“未读取到图片”降级。
  }
  return null;
}

bool _isImagePath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.heif');
}
