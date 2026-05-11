import 'package:flutter/material.dart';

/// SnackBar 类型
enum SnackBarType {
  info,
  success,
  warning,
  error,
}

/// 统一的 SnackBar 工具类
class AppSnackBar {
  /// 显示 SnackBar
  static void show(
    BuildContext context, {
    required String message,
    SnackBarType type = SnackBarType.info,
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    // 清除当前显示的 SnackBar
    messenger.hideCurrentSnackBar();

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              _getIcon(type),
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        backgroundColor: _getBackgroundColor(type),
        behavior: SnackBarBehavior.floating,
        duration: duration,
        action: action,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  /// 显示信息提示
  static void info(BuildContext context, String message) {
    show(context, message: message, type: SnackBarType.info);
  }

  /// 显示成功提示
  static void success(BuildContext context, String message) {
    show(context, message: message, type: SnackBarType.success);
  }

  /// 显示警告提示
  static void warning(BuildContext context, String message) {
    show(context, message: message, type: SnackBarType.warning);
  }

  /// 显示错误提示
  static void error(BuildContext context, String message) {
    show(context, message: message, type: SnackBarType.error);
  }

  /// 显示带重试按钮的错误提示
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
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: retryLabel,
        textColor: Colors.white,
        onPressed: onRetry,
      ),
    );
  }

  static Color _getBackgroundColor(SnackBarType type) {
    switch (type) {
      case SnackBarType.success:
        return const Color(0xFF4CAF50);
      case SnackBarType.error:
        return const Color(0xFFE53935);
      case SnackBarType.warning:
        return const Color(0xFFFFA726);
      case SnackBarType.info:
        return const Color(0xFF2196F3);
    }
  }

  static IconData _getIcon(SnackBarType type) {
    switch (type) {
      case SnackBarType.success:
        return Icons.check_circle_outline;
      case SnackBarType.error:
        return Icons.error_outline;
      case SnackBarType.warning:
        return Icons.warning_amber_outlined;
      case SnackBarType.info:
        return Icons.info_outline;
    }
  }
}
