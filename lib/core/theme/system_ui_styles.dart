// 文件用途：定义 AppSystemUiStyles 相关主题、颜色或视觉样式，供应用界面统一使用。
// 核心逻辑：定义 AppSystemUiStyles 的颜色、字体或组件样式，供主题构建和系统 UI 适配统一复用。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 关键声明：system ui styles 统一提供视觉参数或主题对象，避免页面直接写死颜色、字体和尺寸。
/// Route-scoped system UI styles for pages whose top background differs from
/// the active app theme.
class AppSystemUiStyles {
  AppSystemUiStyles._();

  /// A visibly separated strip for the wallet's near-black header.
  static const Color walletStatusBarColor = Color(0xFF2B2E36);

  /// White status-bar content for black, dark, saturated, or media headers.
  static const SystemUiOverlayStyle onDarkBackground = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
  );

  /// Wallet-specific style. The explicit color supports Android versions that
  /// still paint the native status bar; the page also paints the same strip
  /// beneath transparent edge-to-edge system bars.
  static const SystemUiOverlayStyle onWalletBackground = SystemUiOverlayStyle(
    statusBarColor: walletStatusBarColor,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemStatusBarContrastEnforced: false,
  );

  /// Dark status-bar content for white and other light headers.
  static const SystemUiOverlayStyle onLightBackground = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemStatusBarContrastEnforced: false,
  );

  static SystemUiOverlayStyle forBackground(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? onDarkBackground
        : onLightBackground;
  }
}

/// Keeps system-bar contrast tied to the route instead of mutating the global
/// overlay style, so the previous page restores automatically after pop.
class DarkSystemUiScope extends StatelessWidget {
  const DarkSystemUiScope({
    super.key,
    required this.child,
  });

  final Widget child;

  // 流程逻辑：`build` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppSystemUiStyles.onDarkBackground,
      child: child,
    );
  }
}
