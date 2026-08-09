// 文件用途：集中定义响应式布局断点和尺寸阈值，供桌面、平板和移动端布局统一使用。
// 核心逻辑：集中维护 Breakpoints 的稳定常量，作为界面、服务和校验逻辑共享的单一配置来源。
import 'package:universal_io/io.dart';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
import 'package:flutter/foundation.dart';

// 关键声明：breakpoints 是共享常量入口，修改时需要同步检查使用它的 UI、服务和校验规则。
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
