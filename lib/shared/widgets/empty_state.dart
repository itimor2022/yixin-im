// 文件用途：提供 EmptyStateType 可复用界面组件，服务于跨模块共享能力。
// 核心逻辑：根据输入模型和状态渲染 EmptyStateType，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:flutter/material.dart';

import '../../core/i18n/app_localizations.dart';

String _emptyStateText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 关键声明：empty state 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
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

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark ? Colors.grey.shade600 : Colors.grey.shade400;
    final titleColor = isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    final subtitleColor = isDark ? Colors.grey.shade500 : Colors.grey.shade500;

    final displayIcon = icon ?? _getDefaultIcon();
    final displayTitle = title ?? _getDefaultTitle(context);
    final displaySubtitle = subtitle ?? _getDefaultSubtitle(context);

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

  String _getDefaultTitle(BuildContext context) {
    switch (type) {
      case EmptyStateType.chat:
        return _emptyStateText(
          context,
          zhCN: '暂无会话',
          zhTW: '暫無會話',
          en: 'No chats yet',
        );
      case EmptyStateType.contact:
        return _emptyStateText(
          context,
          zhCN: '暂无联系人',
          zhTW: '暫無聯絡人',
          en: 'No contacts yet',
        );
      case EmptyStateType.message:
        return _emptyStateText(
          context,
          zhCN: '暂无消息',
          zhTW: '暫無訊息',
          en: 'No messages yet',
        );
      case EmptyStateType.moment:
        return _emptyStateText(
          context,
          zhCN: '暂无动态',
          zhTW: '暫無動態',
          en: 'No moments yet',
        );
      case EmptyStateType.search:
        return _emptyStateText(
          context,
          zhCN: '未找到结果',
          zhTW: '找不到結果',
          en: 'No results found',
        );
      case EmptyStateType.notification:
        return _emptyStateText(
          context,
          zhCN: '暂无通知',
          zhTW: '暫無通知',
          en: 'No notifications yet',
        );
      case EmptyStateType.file:
        return _emptyStateText(
          context,
          zhCN: '暂无文件',
          zhTW: '暫無檔案',
          en: 'No files yet',
        );
      case EmptyStateType.generic:
        return _emptyStateText(
          context,
          zhCN: '暂无内容',
          zhTW: '暫無內容',
          en: 'No content yet',
        );
    }
  }

  String _getDefaultSubtitle(BuildContext context) {
    switch (type) {
      case EmptyStateType.chat:
        return _emptyStateText(
          context,
          zhCN: '开始一段新的对话吧',
          zhTW: '開始一段新的對話吧',
          en: 'Start a new conversation',
        );
      case EmptyStateType.contact:
        return _emptyStateText(
          context,
          zhCN: '添加好友开始聊天',
          zhTW: '新增好友開始聊天',
          en: 'Add friends to start chatting',
        );
      case EmptyStateType.message:
        return _emptyStateText(
          context,
          zhCN: '发送第一条消息吧',
          zhTW: '發送第一則訊息吧',
          en: 'Send the first message',
        );
      case EmptyStateType.moment:
        return _emptyStateText(
          context,
          zhCN: '分享你的精彩瞬间',
          zhTW: '分享你的精彩瞬間',
          en: 'Share your best moments',
        );
      case EmptyStateType.search:
        return _emptyStateText(
          context,
          zhCN: '试试其他关键词',
          zhTW: '試試其他關鍵字',
          en: 'Try different keywords',
        );
      case EmptyStateType.notification:
        return _emptyStateText(
          context,
          zhCN: '新消息会显示在这里',
          zhTW: '新訊息會顯示在這裡',
          en: 'New notifications will appear here',
        );
      case EmptyStateType.file:
        return _emptyStateText(
          context,
          zhCN: '文件会显示在这里',
          zhTW: '檔案會顯示在這裡',
          en: 'Files will appear here',
        );
      case EmptyStateType.generic:
        return '';
    }
  }
}

/// 错误状态组件
class ErrorState extends StatelessWidget {
  final String? message;
  final VoidCallback? onRetry;
  final String? retryLabel;

  const ErrorState({
    super.key,
    this.message,
    this.onRetry,
    this.retryLabel,
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
              _emptyStateText(
                context,
                zhCN: '加载失败',
                zhTW: '載入失敗',
                en: 'Load failed',
              ),
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
                label: Text(
                  retryLabel ??
                      _emptyStateText(
                        context,
                        zhCN: '重试',
                        zhTW: '重試',
                        en: 'Retry',
                      ),
                ),
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
