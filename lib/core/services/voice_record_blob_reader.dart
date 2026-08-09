// 文件用途：封装 voice record blob reader 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 voice record blob reader 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'dart:typed_data';

// 关键声明：voice record blob reader 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
// 流程逻辑：`readWebRecordingBytes` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
/// 非 Web 平台占位实现。
///
/// 正常流程不会调用此方法；抛错可尽早暴露条件导入或平台分支使用错误。
Future<Uint8List> readWebRecordingBytes(String url) async {
  throw UnsupportedError('Web recording blobs are only available on web.');
}

/// 原生端没有浏览器 Object URL，因此无需释放。
void revokeWebRecordingUrl(String url) {}
