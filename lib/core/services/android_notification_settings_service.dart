import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_io/io.dart';

class AndroidNotificationSettingsService {
  static const MethodChannel _channel = MethodChannel('com.gaoranim/settings');

  static Future<PermissionStatus> status() async {
    if (!Platform.isAndroid) return PermissionStatus.granted;
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
}
