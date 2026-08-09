// 文件用途：提供 clipboard image 的跨平台占位实现，供条件导入在不支持的平台使用。
// 核心逻辑：提供 clipboard image 的无平台能力占位实现，让条件导入在不支持的平台仍能完成编译和安全降级。
import 'dart:typed_data';

// 关键声明：clipboard image stub 是条件导入占位实现，保持公共 API 可调用并在不支持的平台安全返回降级结果。
// 流程逻辑：`readImageFromClipboard` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
/// 不具备 dart:html 或 dart:io 能力的编译目标使用该占位实现。
Future<Uint8List?> readImageFromClipboard() async => null;
