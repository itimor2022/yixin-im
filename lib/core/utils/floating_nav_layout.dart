// 文件用途：提供 FloatingNavLayout 相关工具函数与通用转换逻辑，属于通用工具。
// 核心逻辑：提供 FloatingNavLayout 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
import 'package:flutter/widgets.dart';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。

import 'platform_utils.dart';

// 关键声明：floating nav layout 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
class FloatingNavLayout {
  const FloatingNavLayout._();

  static const double barHeight = 66;
  static const double defaultBottomGap = 12;
  static const double safeAreaExtraGap = 6;
  static const double defaultContentGap = 16;

  static bool isEnabledForContext(BuildContext context) {
    return PlatformUtils.isMobile || PlatformUtils.isMobileWebLayout(context);
  }

  static bool get isEnabled => PlatformUtils.isMobile;

  static double bottomOffset(BuildContext context) {
    if (!isEnabledForContext(context)) return 0;
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    return safeBottom > 0 ? safeBottom + safeAreaExtraGap : defaultBottomGap;
  }

  static double reservedSpace(
    BuildContext context, {
    double extra = defaultContentGap,
  }) {
    if (!isEnabledForContext(context)) return 0;
    return barHeight + bottomOffset(context) + extra;
  }
}
