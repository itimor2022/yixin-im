/// 剪贴板图片读取工具（跨平台条件导入）
///
/// Web 平台：使用 dart:html 调用浏览器 Clipboard API
/// 其他平台：返回 null（占位 stub）
export 'clipboard_image_stub.dart'
    if (dart.library.html) 'clipboard_image_web.dart';
