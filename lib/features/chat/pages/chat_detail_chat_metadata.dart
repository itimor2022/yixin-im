// 文件用途：实现 _ChatDetailChatMetadata 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailChatMetadata 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail chat metadata 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailChatMetadata on _ChatDetailPageState {
  ChatItem? _findCurrentChatItem(ChatListState chatListState) {
    for (final chat in chatListState.allChats) {
      if (chat.id == widget.chatId) return chat;
    }
    return null;
  }

  ContactItem? _findPrivateContact(
    List<ContactItem> contacts,
    api.Chat? detailChat,
    ChatItem? listChat,
  ) {
    if (widget.chatType != ChatType.private) return null;

    final ids = <String?>[
      detailChat?.targetUserId,
      listChat?.targetUserUuid,
      listChat?.targetUserId,
      widget.chatId,
    ].where((id) => id != null && id.isNotEmpty).cast<String>().toSet();

    for (final contact in contacts) {
      if ((contact.uuid != null && ids.contains(contact.uuid)) ||
          ids.contains(contact.id)) {
        return contact;
      }
    }
    return null;
  }

  // 流程逻辑：`_resolveChatDisplayName` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  String _resolveChatDisplayName(
    api.Chat? detailChat,
    ChatItem? listChat,
    ContactItem? privateContact,
  ) {
    final candidates = widget.chatType == ChatType.private
        ? <String?>[
            privateContact?.name,
            detailChat?.name,
            listChat?.name,
            widget.chatName,
          ]
        : <String?>[detailChat?.name, listChat?.name, widget.chatName];

    for (final value in candidates) {
      final text = value?.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return _localizedText(zhCN: '聊天', zhTW: '聊天', en: 'Chat');
  }

  Map<String, String> _buildContactDisplayNameMap(List<ContactItem> contacts) {
    final result = <String, String>{};
    for (final contact in contacts) {
      final name = contact.name.trim();
      if (name.isEmpty) continue;
      if (contact.id.isNotEmpty) result[contact.id] = name;
      final uuid = contact.uuid;
      if (uuid != null && uuid.isNotEmpty) result[uuid] = name;
    }
    return result;
  }

  MessageItem _applyContactDisplayName(
    MessageItem message,
    Map<String, String> contactDisplayNames,
  ) {
    if (message.isOutgoing) return message;
    final displayName = contactDisplayNames[message.senderId];
    if (displayName == null ||
        displayName.isEmpty ||
        displayName == message.senderName) {
      return message;
    }
    return message.copyWith(senderName: displayName);
  }
}
