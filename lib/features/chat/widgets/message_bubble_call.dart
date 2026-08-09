// 文件用途：提供 _MessageBubbleCall 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _MessageBubbleCall，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble call 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
extension _MessageBubbleCall on MessageBubble {
  // 流程逻辑：`_buildCallBubble` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  /// 构建通话记录气泡
  Widget _buildCallBubble(
    BuildContext context,
    Color bubbleColor,
    Color textColor,
    Color timeColor,
    bool isOutgoing,
  ) {
    final callInfo = formatChatCallPreview(
      text: message.content,
      durationSeconds: message.mediaDuration,
      isOutgoing: isOutgoing,
      language: AppLocalizations.of(context).language,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isAttention = callInfo.isAttention;
    final callIconColor = isAttention
        ? AppColors.error
        : (isDark ? AppColors.callMeetingIconDark : AppColors.callMeetingIcon);
    final callIconBackground = isDark
        ? AppColors.callMeetingIconBackgroundDark
        : AppColors.callMeetingIconBackground;
    final detail = callInfo.detail;

    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: _getBubbleRadius(isOutgoing),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: callIconBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(
              callInfo.isVideo
                  ? (isAttention ? Icons.videocam_off : Icons.videocam)
                  : (isAttention ? Icons.phone_missed : Icons.phone),
              size: 20,
              color: callIconColor,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  callInfo.title,
                  style: TextStyle(
                    fontSize: 15,
                    color: textColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                if (detail != null && detail.isNotEmpty) ...[
                  Text(
                    detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: isAttention ? AppColors.error : timeColor,
                      fontWeight:
                          isAttention ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 1),
                ],
                Text(
                  DateFormat('HH:mm')
                      .format(toCurrentLocalTime(message.createdAt)),
                  style: TextStyle(fontSize: 11, color: timeColor),
                ),
              ],
            ),
          ),
          if (isOutgoing) ...[
            const SizedBox(width: 4),
            _buildStatusIcon(timeColor),
          ],
        ],
      ),
    );
  }
}
