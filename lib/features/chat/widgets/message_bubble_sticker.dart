// 文件用途：提供 _MessageBubbleSticker 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _MessageBubbleSticker，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble sticker 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
extension _MessageBubbleSticker on MessageBubble {
  // 流程逻辑：`_buildStickerBubble` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  Widget _buildStickerBubble(Color timeColor) {
    return Column(
      crossAxisAlignment: message.isOutgoing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        SizedBox(width: 150, height: 150, child: _buildMediaImage()),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                DateFormat('HH:mm')
                    .format(toCurrentLocalTime(message.createdAt)),
                style: AppTextStyles.timestamp.copyWith(color: timeColor),
              ),
              if (message.isOutgoing) ...[
                const SizedBox(width: 3),
                _buildStatusIcon(timeColor),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
