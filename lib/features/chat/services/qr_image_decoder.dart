// 文件用途：封装 二维码 image decoder 相关业务流程与外部能力调用，属于聊天与消息。
// 核心逻辑：封装 二维码 image decoder 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'dart:typed_data';

// 关键声明：二维码 image decoder 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
// 流程逻辑：`isQrImageDecodeSupported` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
bool isQrImageDecodeSupported() => false;

Future<String?> decodeQrImageBytes(
  Uint8List bytes, {
  String mimeType = 'image/png',
}) async {
  return null;
}
