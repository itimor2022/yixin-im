// 文件用途：提供 _MessageBubbleReplyPreview 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _MessageBubbleReplyPreview，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble reply 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
extension _MessageBubbleReplyPreview on MessageBubble {
  // 流程逻辑：`_buildReplyPreview` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  Widget _buildReplyPreview(BuildContext context, Color textColor) {
    final replyAccentColor = message.isOutgoing
        ? const Color(0xFF4CAF50)
        : AppColors.primaryFor(context);

    return GestureDetector(
      onTap: onReplyTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: textColor.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 3, height: 36, color: replyAccentColor),
              const SizedBox(width: 8),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message.replyTo!.senderName,
                        style: TextStyle(
                          fontSize:
                              (messageFontSize - 2).clamp(12, 18).toDouble(),
                          fontWeight: FontWeight.w600,
                          color: replyAccentColor,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        message.replyTo!.content,
                        style: TextStyle(
                          fontSize:
                              (messageFontSize - 2).clamp(12, 18).toDouble(),
                          color: textColor.withOpacity(0.7),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}
