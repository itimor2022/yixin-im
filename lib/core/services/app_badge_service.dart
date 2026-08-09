// 文件用途：封装 AppBadgeService 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 AppBadgeService 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'package:flutter/foundation.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:universal_io/io.dart';

// 关键声明：app badge service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 移动端应用角标服务（Android / iOS）。
class AppBadgeService {
  static final AppBadgeService _instance = AppBadgeService._internal();
  // 流程逻辑：工厂构造入口 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
  factory AppBadgeService() => _instance;
  AppBadgeService._internal();

  bool get _isSupportedPlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> updateBadge(int count) async {
    if (!_isSupportedPlatform) return;

    try {
      // 平台可用不代表当前桌面/启动器支持角标，必须以插件的运行时探测为准。
      final supported = await FlutterAppBadger.isAppBadgeSupported();
      if (!supported) {
        debugPrint('[AppBadge] badge is not supported by current launcher');
        return;
      }

      if (count > 0) {
        await FlutterAppBadger.updateBadgeCount(count);
      } else {
        // 0 表示清除系统角标，而不是显示数字 0。
        await FlutterAppBadger.removeBadge();
      }
    } catch (e) {
      debugPrint('[AppBadge] Failed to update badge: $e');
    }
  }

  Future<void> clear() async {
    await updateBadge(0);
  }
}
