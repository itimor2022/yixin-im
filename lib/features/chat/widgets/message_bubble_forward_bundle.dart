// 文件用途：提供 _MessageBubbleForwardBundle 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _MessageBubbleForwardBundle，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble forward bundle 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
extension _MessageBubbleForwardBundle on MessageBubble {
  // 流程逻辑：`_buildForwardBundleBubble` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  Widget _buildForwardBundleBubble(
    BuildContext context,
    Color bubbleColor,
    Color textColor,
    Color timeColor,
    bool isOutgoing,
  ) {
    final bundle = ForwardBundleSnapshot.tryParse(message.content);
    if (bundle == null) {
      return _buildTextBubble(
        context,
        bubbleColor,
        textColor,
        timeColor,
        isOutgoing,
      );
    }
    final english = AppLocalizations.of(context).language == AppLanguage.en;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ForwardBundlePreviewPage(bundle: bundle),
        ),
      ),
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 310),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              bundle.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 7),
            ...bundle.items.take(4).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      '${item.senderName}: ${item.preview(english: english)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: textColor.withOpacity(0.78),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
            if (bundle.items.length > 4)
              Text(
                english
                    ? '${bundle.items.length} messages'
                    : '共 ${bundle.items.length} 条消息',
                style:
                    TextStyle(color: textColor.withOpacity(0.6), fontSize: 12),
              ),
            Divider(color: textColor.withOpacity(0.12), height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    english ? 'Chat history' : '聊天记录',
                    style: TextStyle(
                        color: textColor.withOpacity(0.65), fontSize: 12),
                  ),
                ),
                Text(
                  DateFormat('HH:mm')
                      .format(toCurrentLocalTime(message.createdAt)),
                  style: TextStyle(color: timeColor, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
