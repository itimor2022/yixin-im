import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/api/chat_service.dart';

void main() {
  test('search result keeps message seq for deterministic navigation', () {
    final item = SearchMessageItem.fromJson({
      'id': 'message-298',
      'seq': 298,
      'chat_id': 'chat-1',
      'sender_id': 'user-1',
      'type': 1,
      'content': {'text': 'target'},
      'created_at': '2026-07-16T20:00:00Z',
    });

    expect(item.id, 'message-298');
    expect(item.seq, 298);
    expect(item.text, 'target');
  });

  test('group member display name prefers the effective group nickname', () {
    final member = ChatMember.fromJson({
      'user_id': 'user-1',
      'username': 'account_name',
      'nickname': 'group nickname',
      'global_nickname': 'profile nickname',
      'nickname_in_chat': 'group nickname',
      'role': 1,
    });

    expect(member.displayName, 'group nickname');
  });

  test('announcement acknowledgement progress is parsed', () {
    final item = AnnouncementItem.fromJson({
      'id': 9,
      'chat_id': 3,
      'content': 'Important notice',
      'author_id': 1,
      'is_pinned': true,
      'acknowledged': true,
      'acknowledged_count': 2,
      'member_count': 3,
      'created_at': '2026-07-16T20:00:00Z',
      'updated_at': '2026-07-16T20:00:00Z',
    });

    expect(item.acknowledged, isTrue);
    expect(item.acknowledgedCount, 2);
    expect(item.memberCount, 3);
  });
}
