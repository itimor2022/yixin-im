// 文件用途：提供 voice record blob reader 在 Web 平台的实现，服务于业务服务。
// 核心逻辑：实现 voice record blob reader 的 Web 平台分支，适配浏览器 API 和资源生命周期，并保持与原生实现相同的调用契约。
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

// 关键声明：voice record blob reader web 是 Web 平台实现，负责把浏览器资源和异步生命周期适配为跨平台接口。
// 流程逻辑：`readWebRecordingBytes` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
/// 将录音插件返回的 Blob URL 完整复制为 Dart 字节。
///
/// 返回后字节由 Dart 持有；调用方必须再调用 [revokeWebRecordingUrl] 释放
/// 浏览器侧 Object URL，且不能继续把该 URL 当作持久地址使用。
Future<Uint8List> readWebRecordingBytes(String url) async {
  final response = await web.window.fetch(url.toJS).toDart;
  if (!response.ok) {
    throw StateError('Unable to fetch web recording blob: ${response.status}');
  }
  final buffer = await response.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

void revokeWebRecordingUrl(String url) {
  // revoke 只释放 URL 映射，不影响已经复制到 Uint8List 的录音内容。
  if (url.isNotEmpty) {
    web.URL.revokeObjectURL(url);
  }
}
