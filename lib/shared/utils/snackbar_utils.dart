// 文件用途：提供 SnackBarType 相关工具函数与通用转换逻辑，属于跨模块共享能力。
// 核心逻辑：提供 SnackBarType 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
import 'package:flutter/material.dart';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。

import '../../core/i18n/app_localizations.dart';

// 关键声明：snackbar utils 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
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
    String? retryLabel,
  }) {
    show(
      context,
      message: message,
      type: SnackBarType.error,
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: retryLabel ?? AppLocalizations.of(context).retry,
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
