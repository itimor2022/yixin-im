import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/features/chat/providers/message_provider.dart';

MessageItem _message({
  required String id,
  required String senderId,
  String? senderAvatar,
}) {
  return MessageItem(
    id: id,
    chatId: 'group-1',
    senderId: senderId,
    senderName: '旧昵称',
    senderAvatar: senderAvatar,
    type: MessageItemType.text,
    content: '消息',
    isOutgoing: false,
    status: MessageStatus.sent,
    createdAt: DateTime(2026, 7, 16),
  );
}

void main() {
  test('群成员资料变化会刷新其已加载历史消息头像和昵称', () {
    final target = _message(
      id: 'm1',
      senderId: 'user-1',
      senderAvatar: 'https://old.example/avatar.png',
    );
    final other = _message(
      id: 'm2',
      senderId: 'user-2',
      senderAvatar: 'https://other.example/avatar.png',
    );

    final updated = debugApplyUserProfileToMessages(
      [target, other],
      userId: 'user-1',
      name: '新昵称',
      avatarProvided: true,
      avatar: 'https://new.example/avatar.png',
    );

    expect(updated.first.senderName, '新昵称');
    expect(updated.first.senderAvatar, 'https://new.example/avatar.png');
    expect(identical(updated.last, other), isTrue);
  });

  test('删除头像会清空群聊历史消息中的旧头像', () {
    final updated = debugApplyUserProfileToMessages(
      [
        _message(
          id: 'm1',
          senderId: 'user-1',
          senderAvatar: 'https://old.example/avatar.png',
        ),
      ],
      userId: 'user-1',
      avatarProvided: true,
      avatar: null,
    );

    expect(updated.single.senderAvatar, isNull);
  });
}
