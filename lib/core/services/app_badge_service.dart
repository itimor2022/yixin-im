import 'package:flutter/foundation.dart';
import 'package:flutter_app_badger/flutter_app_badger.dart';
import 'package:universal_io/io.dart';

/// 移动端应用角标服务（Android / iOS）。
class AppBadgeService {
  static final AppBadgeService _instance = AppBadgeService._internal();
  factory AppBadgeService() => _instance;
  AppBadgeService._internal();

  bool get _isSupportedPlatform => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> updateBadge(int count) async {
    if (!_isSupportedPlatform) return;

    try {
      final supported = await FlutterAppBadger.isAppBadgeSupported();
      if (!supported) {
        if (kDebugMode) debugPrint('[AppBadge] badge is not supported by current launcher');
        return;
      }

      if (count > 0) {
        await FlutterAppBadger.updateBadgeCount(count);
      } else {
        await FlutterAppBadger.removeBadge();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[AppBadge] Failed to update badge: $e');
    }
  }

  Future<void> clear() async {
    await updateBadge(0);
  }
}

