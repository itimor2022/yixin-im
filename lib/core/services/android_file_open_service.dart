// 文件用途：封装 AndroidFileOpenResult 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 AndroidFileOpenResult 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'package:flutter/services.dart';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。

// 关键声明：android file open service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
class AndroidFileOpenResult {
  final bool opened;
  final String reason;

  const AndroidFileOpenResult({required this.opened, required this.reason});
}

/// 通过 Android FileProvider 打开应用私有目录中的文件。
///
/// 新版 Android 会拒绝把原始 `file://` URI 交给其他应用。原生侧负责将路径
/// 转为只读 `content://` URI，并仅向被选中的应用授予临时读取权限。
/// 调用失败统一转换为结果对象，调用方无需捕获平台通道异常。
class AndroidFileOpenService {
  static const MethodChannel _channel = MethodChannel('com.genericim/file_open');

  static Future<AndroidFileOpenResult> openFile({
    required String path,
    required String fileName,
  }) async {
    try {
      // path 仅传给受信任的原生实现，URI 暴露和临时授权均在 Android 侧完成。
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'openFile',
        <String, dynamic>{'path': path, 'file_name': fileName},
      );
      return AndroidFileOpenResult(
        opened: response?['opened'] == true,
        reason: response?['reason']?.toString() ?? 'unknown',
      );
    } on PlatformException catch (error) {
      return AndroidFileOpenResult(
        opened: false,
        reason: error.code.isEmpty ? 'platform_error' : error.code,
      );
    } on MissingPluginException {
      return const AndroidFileOpenResult(
        opened: false,
        reason: 'not_supported',
      );
    }
  }
}
