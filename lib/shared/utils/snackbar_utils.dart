import 'package:flutter/material.dart';

/// ============================================================
/// 全站 SnackBar / 顶部 Toast 提示
/// ============================================================
///
/// 视觉规范：
///   - 深色中性卡片（#1F2937）—— 不再使用充盈红底
///   - 圆角 16 + 悬浮 + 顶部/底部安全距离
///   - 左侧彩色小圆形图标（红/绿/橙/蓝）用于类型指示
///   - 白色文本，14px 中号字重
///   - 悬浮位置在 [AppSnackBarPosition.top]（默认）或 bottom
///
/// 与旧版本 API 保持兼容：`AppSnackBar.error(context, '...')` 等
/// 调用点无需改动，样式自动升级。
class AppSnackBar {
  /// SnackBar 默认展示时长
  static const Duration _defaultDuration = Duration(seconds: 2);

  /// 卡片背景（深色中性）
  static const Color _cardBg = Color(0xFF1F2937);

  /// 类型对应的图标背景色（左侧小圆点）
  static const Color _errorTint = Color(0xFFEF4444); // red-500
  static const Color _successTint = Color(0xFF22C55E); // green-500
  static const Color _warningTint = Color(0xFFF59E0B); // amber-500
  static const Color _infoTint = Color(0xFF38BDF8); // sky-400

  /// 显示 SnackBar
  static void show(
    BuildContext context, {
    required String message,
    SnackBarType type = SnackBarType.info,
    Duration duration = _defaultDuration,
    SnackBarAction? action,
    AppSnackBarPosition position = AppSnackBarPosition.top,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.hideCurrentSnackBar();

    final Color tint = _tint(type);
    final IconData icon = _icon(type);
    final double topInset = MediaQuery.of(context).viewPadding.top;

    // 用一个只占顶部空间的 margin 实现"看起来在顶部"的浮动 SnackBar；
    // Flutter 原生 SnackBar 只有 floating/fixed 两种，通过巨大的
    // bottom-margin 把它顶到屏幕上方是最少改动的做法。
    final EdgeInsets margin = position == AppSnackBarPosition.top
        ? EdgeInsets.fromLTRB(
            14,
            topInset + 12,
            14,
            _computeTopBottomMargin(context),
          )
        : const EdgeInsets.fromLTRB(14, 12, 14, 20);

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: tint.withOpacity(0.18),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 18, color: tint),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: _cardBg,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        action: action,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        margin: margin,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  static void info(BuildContext context, String message) {
    show(context, message: message, type: SnackBarType.info);
  }

  static void success(BuildContext context, String message) {
    show(context, message: message, type: SnackBarType.success);
  }

  static void warning(BuildContext context, String message) {
    show(context, message: message, type: SnackBarType.warning);
  }

  static void error(BuildContext context, String message) {
    show(context, message: message, type: SnackBarType.error);
  }

  static void errorWithRetry(
    BuildContext context, {
    required String message,
    required VoidCallback onRetry,
    String retryLabel = '重试',
  }) {
    show(
      context,
      message: message,
      type: SnackBarType.error,
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: retryLabel,
        textColor: _errorTint,
        onPressed: onRetry,
      ),
    );
  }

  static Color _tint(SnackBarType type) {
    switch (type) {
      case SnackBarType.success:
        return _successTint;
      case SnackBarType.error:
        return _errorTint;
      case SnackBarType.warning:
        return _warningTint;
      case SnackBarType.info:
        return _infoTint;
    }
  }

  static IconData _icon(SnackBarType type) {
    switch (type) {
      case SnackBarType.success:
        return Icons.check_circle_outline_rounded;
      case SnackBarType.error:
        return Icons.error_outline_rounded;
      case SnackBarType.warning:
        return Icons.warning_amber_rounded;
      case SnackBarType.info:
        return Icons.info_outline_rounded;
    }
  }

  /// 把 SnackBar 顶到顶部：给一个大的 bottom margin
  static double _computeTopBottomMargin(BuildContext context) {
    final size = MediaQuery.of(context).size;
    // 顶部浮动：让 bottom-margin 撑到 (屏幕高 - 顶部安全 - 卡片估计高) 附近，
    // 卡片估计高 60px，再留 12px 顶部间距。
    final topInset = MediaQuery.of(context).viewPadding.top;
    return (size.height - topInset - 60 - 12).clamp(0, size.height);
  }
}

/// SnackBar 类型（保持兼容旧代码）
enum SnackBarType {
  info,
  success,
  warning,
  error,
}

/// SnackBar 显示位置
enum AppSnackBarPosition {
  top,
  bottom,
}

/// 便捷扩展：`context.showAppError('xxx')`
extension AppSnackBarContext on BuildContext {
  void showAppError(String message) => AppSnackBar.error(this, message);
  void showAppSuccess(String message) => AppSnackBar.success(this, message);
  void showAppWarning(String message) => AppSnackBar.warning(this, message);
  void showAppInfo(String message) => AppSnackBar.info(this, message);
}

/// ============================================================
/// 全局 SnackBarThemeData
/// ============================================================
///
/// 在 [MaterialApp.theme] 里应用，让**所有**直接 `ScaffoldMessenger.
/// of(context).showSnackBar(SnackBar(...))` 的调用点也自动继承新的
/// "深色中性卡片" 视觉，从此不再有充盈红底的 SnackBar。
///
/// 注意：如果某个调用点显式传了 `backgroundColor: Colors.red`，那
/// 一行会覆盖主题——需要在调用点单独去掉，才能生效。项目里的
/// 这些覆盖已经做过一轮清理，见 [replace_all_red_snackbars.md](../..)。
SnackBarThemeData buildAppSnackBarTheme() {
  return SnackBarThemeData(
    backgroundColor: const Color(0xFF1F2937),
    behavior: SnackBarBehavior.floating,
    elevation: 8,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    contentTextStyle: const TextStyle(
      color: Colors.white,
      fontSize: 14,
      height: 1.35,
      fontWeight: FontWeight.w500,
    ),
    actionTextColor: const Color(0xFF60A5FA), // 蓝色 action，主题友好
    insetPadding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
  );
}
