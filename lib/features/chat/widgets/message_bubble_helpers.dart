// 文件用途：提供 _MessageBubbleHelpers 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _MessageBubbleHelpers，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble helpers 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
extension _MessageBubbleHelpers on MessageBubble {
  // 流程逻辑：`_buildSenderHeader` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  Widget _buildSenderHeader(BuildContext context, bool isOutgoing) {
    final name = message.senderName.trim().isNotEmpty
        ? message.senderName.trim()
        : _localizedUiText(
            context,
            zhCN: '未知用户',
            zhTW: '未知使用者',
            en: 'Unknown user',
          );

    return Padding(
      padding: EdgeInsets.only(
        left: isOutgoing ? 0 : 4,
        right: isOutgoing ? 4 : 0,
        bottom: 4,
      ),
      child: GestureDetector(
        onTap: canOpenMemberProfile ? () => _openSenderProfile(context) : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment:
              isOutgoing ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(
              child: message.senderNicknameColor != null &&
                      message.senderNicknameColor!.isNotEmpty
                  ? ColoredNameWidget(
                      name: name,
                      nicknameColor: message.senderNicknameColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption.copyWith(
                        color: _getSenderColor(message.senderId),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
            if (message.senderEmojiAvatar != null &&
                message.senderEmojiAvatar!.isNotEmpty) ...[
              const SizedBox(width: 4),
              EmojiStatusWidget(
                emoji: message.senderEmojiAvatar!,
                size: 14,
              ),
            ],
            if (message.senderVipActive && message.senderVipLevel > 0) ...[
              const SizedBox(width: 5),
              VipBadge(
                level: message.senderVipLevel,
                text: message.senderVipBadge,
                iconUrl: message.senderVipBadgeIcon,
                height: 16,
                compact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(Color color) {
    IconData icon;

    switch (message.status) {
      case MessageStatus.sending:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: color),
        );
      case MessageStatus.sent:
        icon = Icons.check_rounded;
        break;
      case MessageStatus.delivered:
        icon = Icons.done_all_rounded;
        break;
      case MessageStatus.read:
        return Icon(
          Icons.done_all_rounded,
          size: 16,
          color: AppColors.messageRead,
        );
      case MessageStatus.failed:
        final icon = Icon(
          Icons.error_outline_rounded,
          size: 16,
          color: AppColors.error,
        );
        if (!message.isOutgoing || onRetry == null) {
          return icon;
        }
        return Semantics(
          button: true,
          label: 'Retry send',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRetry,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: icon,
            ),
          ),
        );
    }

    return Icon(icon, size: 16, color: color);
  }

  BorderRadius _getBubbleRadius(bool isOutgoing) {
    const radius = Radius.circular(18);
    const smallRadius = Radius.circular(4);

    if (isOutgoing) {
      return BorderRadius.only(
        topLeft: radius,
        topRight: isFirstInGroup ? radius : smallRadius,
        bottomLeft: radius,
        bottomRight: isLastInGroup ? radius : smallRadius,
      );
    } else {
      return BorderRadius.only(
        topLeft: isFirstInGroup ? radius : smallRadius,
        topRight: radius,
        bottomLeft: isLastInGroup ? radius : smallRadius,
        bottomRight: radius,
      );
    }
  }

  /// 根据发送者ID生成颜色（群聊中不同人不同颜色）
  Color _getSenderColor(String senderId) {
    final colors = [
      const Color(0xFF4CAF50),
      const Color(0xFF2196F3),
      const Color(0xFFFF9800),
      const Color(0xFFE91E63),
      const Color(0xFF9C27B0),
      const Color(0xFF00BCD4),
      const Color(0xFFFF5722),
      const Color(0xFF795548),
    ];
    final index = senderId.hashCode.abs() % colors.length;
    return colors[index];
  }

  void _openSenderProfile(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UserProfilePage(
          userId: message.senderId,
          name: message.senderName,
          avatar: message.senderAvatar,
        ),
      ),
    );
  }
}
