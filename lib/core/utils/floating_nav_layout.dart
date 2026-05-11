import 'package:flutter/widgets.dart';

import 'platform_utils.dart';

class FloatingNavLayout {
  const FloatingNavLayout._();

  static const double barHeight = 64;
  static const double defaultBottomGap = 12;
  static const double safeAreaExtraGap = 6;
  static const double defaultContentGap = 16;

  static bool get isEnabled => PlatformUtils.isMobile;

  static double bottomOffset(BuildContext context) {
    if (!isEnabled) return 0;
    final safeBottom = MediaQuery.of(context).viewPadding.bottom;
    return safeBottom > 0 ? safeBottom + safeAreaExtraGap : defaultBottomGap;
  }

  static double reservedSpace(
    BuildContext context, {
    double extra = defaultContentGap,
  }) {
    if (!isEnabled) return 0;
    return barHeight + bottomOffset(context) + extra;
  }
}
