// 文件用途：提供 clipboard image 相关工具函数与通用转换逻辑，属于通用工具。
// 核心逻辑：提供 clipboard image 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
// 关键声明：clipboard image 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
/// 剪贴板图片读取工具（跨平台条件导入）
///
/// Web 平台：使用 dart:html 调用浏览器 Clipboard API
/// dart:io 平台：先读剪贴板图片字节，再回退到剪贴板文件路径
/// 其他编译目标：使用 stub 返回 null
///
/// 统一契约中 null 同时表示“没有图片、不支持、无权限或解码失败”，调用方按
/// 普通粘贴未命中处理，不应据此展示具体权限错误。
export 'clipboard_image_stub.dart'
    if (dart.library.html) 'clipboard_image_web.dart'
    if (dart.library.io) 'clipboard_image_io.dart';
