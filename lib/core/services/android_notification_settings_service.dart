// 文件用途：封装 AndroidBackgroundRestrictionStatus 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 AndroidBackgroundRestrictionStatus 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_io/io.dart';

// 关键声明：android notification settings service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
class AndroidBackgroundRestrictionStatus {
  const AndroidBackgroundRestrictionStatus({
    required this.ignoringBatteryOptimizations,
    required this.backgroundRestricted,
  });

  final bool ignoringBatteryOptimizations;
  final bool backgroundRestricted;

  bool get needsAttention =>
      !ignoringBatteryOptimizations || backgroundRestricted;

  // 流程逻辑：`fromMap` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
  factory AndroidBackgroundRestrictionStatus.fromMap(
    Map<String, dynamic>? value,
  ) {
    return AndroidBackgroundRestrictionStatus(
      ignoringBatteryOptimizations:
          value?['ignoring_battery_optimizations'] == true,
      backgroundRestricted: value?['background_restricted'] == true,
    );
  }
}

class AndroidNotificationSettingsService {
  static const MethodChannel _channel = MethodChannel('com.genericim/settings');

  static Future<PermissionStatus> status() async {
    if (!Platform.isAndroid) return PermissionStatus.granted;
    try {
      // Android 的可通知状态同时取决于运行时权限和系统级应用通知开关。
      final state = await _channel.invokeMapMethod<String, dynamic>(
        'getNotificationPermissionStatus',
      );
      if (state?['enabled'] == true) return PermissionStatus.granted;
      if (state?['runtime_granted'] == true &&
          state?['system_enabled'] == false) {
        return PermissionStatus.permanentlyDenied;
      }
    } catch (_) {}
    return Permission.notification.status;
  }

  static Future<bool> request() async {
    if (!Platform.isAndroid) return true;
    try {
      final granted =
          await _channel.invokeMethod<bool>('requestNotificationPermission');
      if (granted == true) return true;
    } catch (_) {
      final status = await Permission.notification.request();
      return status.isGranted || status.isLimited || status.isProvisional;
    }
    final status = await Permission.notification.status;
    return status.isGranted || status.isLimited || status.isProvisional;
  }

  static Future<bool> open() async {
    if (!Platform.isAndroid) return false;
    try {
      final opened =
          await _channel.invokeMethod<bool>('openNotificationSettings');
      if (opened == true) return true;
    } catch (_) {}
    return openAppSettings();
  }

  static Future<bool> openAppSettingsPage() async {
    if (!Platform.isAndroid) return false;
    return openAppSettings();
  }

  static Future<bool> openBatterySettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final opened = await _channel.invokeMethod<bool>('openBatterySettings');
      if (opened == true) return true;
    } catch (_) {}
    return openAppSettings();
  }

  static Future<AndroidBackgroundRestrictionStatus?>
      backgroundRestrictionStatus() async {
    if (!Platform.isAndroid) return null;
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>(
        'getBackgroundRestrictionStatus',
      );
      return AndroidBackgroundRestrictionStatus.fromMap(value);
    } catch (_) {
      return null;
    }
  }

  static Future<bool> openAutoStartSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final opened = await _channel.invokeMethod<bool>('openAutoStartSettings');
      if (opened == true) return true;
    } catch (_) {}
    return openAppSettings();
  }
}
