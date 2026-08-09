import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/features/chat/providers/chat_provider.dart';

void main() {
  test('chat draft can be saved and explicitly cleared', () {
    final chat = ChatItem(
      id: 'chat-1',
      name: 'Peer',
      type: ChatItemType.private,
      createdAt: DateTime(2026, 7, 16),
    );

    final saved = chat.copyWith(draft: 'account isolated draft');
    final cleared = saved.copyWith(clearDraft: true);

    expect(saved.draft, 'account isolated draft');
    expect(cleared.draft, isNull);
  });

  test('server refresh preserves local account draft for matching chat', () {
    final serverChats = [
      ChatItem(
        id: 'chat-1',
        name: 'Updated peer',
        lastMessage: 'new server message',
        type: ChatItemType.private,
        createdAt: DateTime(2026, 7, 18),
      ),
      ChatItem(
        id: 'chat-2',
        name: 'Other peer',
        type: ChatItemType.private,
        createdAt: DateTime(2026, 7, 18),
      ),
    ];
    final localChats = [
      ChatItem(
        id: 'chat-1',
        name: 'Old peer',
        draft: 'account isolated draft',
        type: ChatItemType.private,
        createdAt: DateTime(2026, 7, 17),
      ),
    ];

    final merged = mergeServerChatsWithLocalDrafts(serverChats, localChats);

    expect(merged[0].name, 'Updated peer');
    expect(merged[0].lastMessage, 'new server message');
    expect(merged[0].draft, 'account isolated draft');
    expect(merged[1].draft, isNull);
  });

  test('server refresh preserves a newer failed local preview', () {
    final serverTime = DateTime(2026, 7, 18, 10);
    final failedTime = serverTime.add(const Duration(seconds: 2));
    final merged = mergeServerChatsWithLocalDrafts(
      [
        ChatItem(
          id: 'chat-1',
          name: 'Peer',
          lastMessage: 'server message',
          lastMessageTime: serverTime,
          type: ChatItemType.private,
          createdAt: serverTime,
        ),
      ],
      [
        ChatItem(
          id: 'chat-1',
          name: 'Peer',
          lastMessage: 'failed local message',
          lastMessageTime: failedTime,
          lastMessageFailed: true,
          isSentByMe: true,
          draft: 'failed local message',
          type: ChatItemType.private,
          createdAt: serverTime,
        ),
      ],
    );

    expect(merged.single.lastMessage, 'failed local message');
    expect(merged.single.lastMessageFailed, isTrue);
    expect(merged.single.draft, 'failed local message');
  });

  test('newer server message supersedes an older failed local preview', () {
    final failedTime = DateTime(2026, 7, 18, 10);
    final serverTime = failedTime.add(const Duration(seconds: 2));
    final merged = mergeServerChatsWithLocalDrafts(
      [
        ChatItem(
          id: 'chat-1',
          name: 'Peer',
          lastMessage: 'new server message',
          lastMessageTime: serverTime,
          type: ChatItemType.private,
          createdAt: serverTime,
        ),
      ],
      [
        ChatItem(
          id: 'chat-1',
          name: 'Peer',
          lastMessage: 'old failed message',
          lastMessageTime: failedTime,
          lastMessageFailed: true,
          isSentByMe: true,
          type: ChatItemType.private,
          createdAt: failedTime,
        ),
      ],
    );

    expect(merged.single.lastMessage, 'new server message');
    expect(merged.single.lastMessageFailed, isFalse);
  });

  test('chat preview fields can be explicitly cleared after history removal',
      () {
    final chat = ChatItem(
      id: 'chat-1',
      name: 'Peer',
      lastMessage: 'old message',
      lastMessageTime: DateTime(2026, 7, 16, 19),
      lastMessageSender: 'Peer',
      lastMessageType: MessageContentType.photo,
      lastMessageMediaUrl: '/old.jpg',
      lastMessageSeq: 88,
      unreadCount: 3,
      hasMention: true,
      type: ChatItemType.private,
      createdAt: DateTime(2026, 7, 16),
    );

    final cleared = chat.copyWith(
      clearLastMessage: true,
      clearLastMessageTime: true,
      clearLastMessageSender: true,
      clearLastMessageType: true,
      lastMessageMediaUrl: null,
      lastMessageSeq: 0,
      unreadCount: 0,
      hasMention: false,
    );

    expect(cleared.lastMessage, isNull);
    expect(cleared.lastMessageTime, isNull);
    expect(cleared.lastMessageSender, isNull);
    expect(cleared.lastMessageType, isNull);
    expect(cleared.lastMessageMediaUrl, isNull);
    expect(cleared.lastMessageSeq, 0);
    expect(cleared.unreadCount, 0);
    expect(cleared.hasMention, isFalse);
  });
}
