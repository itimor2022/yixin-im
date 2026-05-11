import 'package:flutter/material.dart';

/// 空状态类型
enum EmptyStateType {
  chat,
  contact,
  message,
  moment,
  search,
  notification,
  file,
  generic,
}

/// 统一的空状态组件
class EmptyState extends StatelessWidget {
  final EmptyStateType type;
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Widget? action;
  final double iconSize;

  const EmptyState({
    super.key,
    this.type = EmptyStateType.generic,
    this.title,
    this.subtitle,
    this.icon,
    this.action,
    this.iconSize = 80,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.grey.shade600 : Colors.grey.shade400;
    final titleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final subtitleColor = isDark ? Colors.grey.shade500 : Colors.grey.shade500;

    final displayIcon = icon ?? _getDefaultIcon();
    final displayTitle = title ?? _getDefaultTitle();
    final displaySubtitle = subtitle ?? _getDefaultSubtitle();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 图标
            Container(
              width: iconSize + 40,
              height: iconSize + 40,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                displayIcon,
                size: iconSize,
                color: iconColor,
              ),
            ),
            const SizedBox(height: 24),
            // 标题
            Text(
              displayTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: titleColor,
              ),
              textAlign: TextAlign.center,
            ),
            if (displaySubtitle.isNotEmpty) ...[
              const SizedBox(height: 8),
              // 副标题
              Text(
                displaySubtitle,
                style: TextStyle(
                  fontSize: 14,
                  color: subtitleColor,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }

  IconData _getDefaultIcon() {
    switch (type) {
      case EmptyStateType.chat:
        return Icons.chat_bubble_outline_rounded;
      case EmptyStateType.contact:
        return Icons.people_outline_rounded;
      case EmptyStateType.message:
        return Icons.message_outlined;
      case EmptyStateType.moment:
        return Icons.photo_library_outlined;
      case EmptyStateType.search:
        return Icons.search_off_rounded;
      case EmptyStateType.notification:
        return Icons.notifications_off_outlined;
      case EmptyStateType.file:
        return Icons.folder_open_rounded;
      case EmptyStateType.generic:
        return Icons.inbox_rounded;
    }
  }

  String _getDefaultTitle() {
    switch (type) {
      case EmptyStateType.chat:
        return '暂无会话';
      case EmptyStateType.contact:
        return '暂无联系人';
      case EmptyStateType.message:
        return '暂无消息';
      case EmptyStateType.moment:
        return '暂无动态';
      case EmptyStateType.search:
        return '未找到结果';
      case EmptyStateType.notification:
        return '暂无通知';
      case EmptyStateType.file:
        return '暂无文件';
      case EmptyStateType.generic:
        return '暂无内容';
    }
  }

  String _getDefaultSubtitle() {
    switch (type) {
      case EmptyStateType.chat:
        return '开始一段新的对话吧';
      case EmptyStateType.contact:
        return '添加好友开始聊天';
      case EmptyStateType.message:
        return '发送第一条消息吧';
      case EmptyStateType.moment:
        return '分享你的精彩瞬间';
      case EmptyStateType.search:
        return '试试其他关键词';
      case EmptyStateType.notification:
        return '新消息会显示在这里';
      case EmptyStateType.file:
        return '文件会显示在这里';
      case EmptyStateType.generic:
        return '';
    }
  }
}

/// 错误状态组件
class ErrorState extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  final String retryLabel;

  const ErrorState({
    super.key,
    this.message,
    this.onRetry,
    this.retryLabel = '重试',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = Colors.red.shade400;
    final textColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 60,
                color: iconColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '加载失败',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: TextStyle(
                  fontSize: 14,
                  color: textColor.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(retryLabel),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).primaryColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 加载状态组件
class LoadingState extends StatelessWidget {
  final String? message;

  const LoadingState({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 16),
            Text(
              message!,
              style: TextStyle(
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
