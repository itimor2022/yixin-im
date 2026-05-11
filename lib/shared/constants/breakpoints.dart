import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';

/// 统一的响应式断点
class Breakpoints {
  /// 手机最大宽度
  static const double mobile = 600;
  
  /// 平板最大宽度
  static const double tablet = 900;
  
  /// 桌面最小宽度
  static const double desktop = 900;
  
  /// 大屏桌面最小宽度
  static const double largeDesktop = 1200;
  
  /// 判断是否为手机布局
  static bool isMobile(double width) => width < mobile;
  
  /// 判断是否为平板布局
  static bool isTablet(double width) => width >= mobile && width < tablet;
  
  /// 判断是否为桌面布局
  static bool isDesktop(double width) => width >= desktop;
  
  /// 判断是否为大屏桌面
  static bool isLargeDesktop(double width) => width >= largeDesktop;
  
  /// 获取当前平台是否为桌面端
  static bool get isDesktopPlatform {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }
  
  /// 获取当前平台是否为移动端
  static bool get isMobilePlatform {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid;
  }
}
