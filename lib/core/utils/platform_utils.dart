import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';

/// Platform helpers shared across UI and services.
class PlatformUtils {
  PlatformUtils._();

  static bool get isWeb => kIsWeb;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isLinux => !kIsWeb && Platform.isLinux;

  /// Web is treated as desktop-like for layout purposes.
  static bool get isDesktop => isWeb || isMacOS || isWindows || isLinux;

  /// Real desktop operating systems only.
  static bool get isPhysicalDesktop => isMacOS || isWindows || isLinux;

  static bool get isMobile => isIOS || isAndroid;
  static bool get isApple => isIOS || isMacOS;

  // Capability checks.
  static bool get supportsCameraCapture => isMobile;
  static bool get supportsCallKit => isIOS;
  static bool get supportsBackgroundService => isAndroid;
  static bool get supportsSystemTray => isPhysicalDesktop;
  static bool get supportsPictureInPicture => isMobile;
  static bool get supportsGallery => isMobile;
  static bool get supportsPushNotification => isMobile;
  static bool get supportsLocalNotification => true;
  static bool get supportsBiometrics =>
      isIOS || isAndroid || isMacOS || isWindows;
  static bool get supportsVoiceVideoCall =>
      isIOS || isAndroid || isMacOS || isWindows;
  static bool get supportsWindowManager => isPhysicalDesktop;
  static bool get supportsHotkeys => isPhysicalDesktop;

  static String get platformName {
    if (isWeb) return 'Web';
    if (isIOS) return 'iOS';
    if (isAndroid) return 'Android';
    if (isMacOS) return 'macOS';
    if (isWindows) return 'Windows';
    if (isLinux) return 'Linux';
    return 'Unknown';
  }

  static String get deviceType {
    if (isWeb) return 'web';
    if (isIOS) return 'ios';
    if (isAndroid) return 'android';
    if (isMacOS) return 'macos';
    if (isWindows) return 'windows';
    if (isLinux) return 'linux';
    return 'unknown';
  }

  static const double desktopMinWidth = 800;
  static const double desktopMinHeight = 600;
  static const double desktopDefaultWidth = 1200;
  static const double desktopDefaultHeight = 800;
  static const double desktopSidebarWidth = 320;
  static const double desktopSidebarMinWidth = 260;
  static const double desktopSidebarMaxWidth = 450;

  static const double breakpointTablet = 768;
  static const double breakpointDesktop = 1024;

  static bool shouldUseDesktopLayout(double screenWidth) {
    return isDesktop || screenWidth >= breakpointTablet;
  }

  static bool shouldShowSplitView(double screenWidth) {
    return screenWidth >= breakpointTablet;
  }

  static bool isLargeScreen(double screenWidth) {
    return screenWidth >= breakpointDesktop;
  }
}

class PlatformRunner {
  static T? runOnMobile<T>(T Function() action) {
    if (PlatformUtils.isMobile) return action();
    return null;
  }

  static T? runOnDesktop<T>(T Function() action) {
    if (PlatformUtils.isPhysicalDesktop) return action();
    return null;
  }

  static T? runOnIOS<T>(T Function() action) {
    if (PlatformUtils.isIOS) return action();
    return null;
  }

  static T? runOnAndroid<T>(T Function() action) {
    if (PlatformUtils.isAndroid) return action();
    return null;
  }

  static T? runOnMacOS<T>(T Function() action) {
    if (PlatformUtils.isMacOS) return action();
    return null;
  }

  static T? runOnWindows<T>(T Function() action) {
    if (PlatformUtils.isWindows) return action();
    return null;
  }
}
