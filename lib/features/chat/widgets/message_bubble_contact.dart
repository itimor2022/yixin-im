// 文件用途：提供 _MessageBubbleContact 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _MessageBubbleContact，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble contact 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
extension _MessageBubbleContact on MessageBubble {
  // 流程逻辑：`_buildContactCardBubble` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  /// 构建名片气泡
  Widget _buildContactCardBubble(
    BuildContext context,
    Color bubbleColor,
    Color textColor,
    Color timeColor,
    bool isOutgoing,
  ) {
    final l10n = AppLocalizations.of(context);
    final contactName = message.contactName ?? l10n.get('user');
    final contactUsername = message.contactUsername;
    final contactAvatar = message.contactAvatar;
    final contactUserId = message.contactUserId;
    final contactNicknameColor = message.contactNicknameColor;
    final contactEmojiAvatar = message.contactEmojiAvatar;

    return Builder(
      builder: (context) => GestureDetector(
        onTap: () {
          if (contactUserId != null) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => UserProfilePage(
                  userId: contactUserId,
                  name: contactName,
                  avatar: contactAvatar,
                ),
              ),
            );
          }
        },
        child: Container(
          constraints: const BoxConstraints(maxWidth: 260),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: _getBubbleRadius(isOutgoing),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    AvatarWidget(
                      name: contactName,
                      avatar: contactAvatar,
                      userId: contactUserId ?? '',
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: ColoredNameWidget(
                                  name: contactName,
                                  nicknameColor: contactNicknameColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  defaultColor: textColor,
                                ),
                              ),
                              if (contactEmojiAvatar != null &&
                                  contactEmojiAvatar.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                EmojiStatusWidget(
                                  emoji: contactEmojiAvatar,
                                  size: 18,
                                ),
                              ],
                            ],
                          ),
                          if (contactUsername != null &&
                              contactUsername.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              '@$contactUsername',
                              style: TextStyle(
                                fontSize: 13,
                                color: textColor.withOpacity(0.6),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: 20,
                      color: textColor.withOpacity(0.4),
                    ),
                  ],
                ),
              ),
              Container(height: 0.5, color: textColor.withOpacity(0.1)),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.contact_page_outlined,
                      size: 14,
                      color: textColor.withOpacity(0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.get('contact_card'),
                      style: TextStyle(
                        fontSize: 12,
                        color: textColor.withOpacity(0.5),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      DateFormat('HH:mm')
                          .format(toCurrentLocalTime(message.createdAt)),
                      style: TextStyle(fontSize: 11, color: timeColor),
                    ),
                    if (isOutgoing) ...[
                      const SizedBox(width: 3),
                      _buildStatusIcon(timeColor),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
