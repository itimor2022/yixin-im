import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/api/chat_service.dart';

void main() {
  test('UserChat parses persisted mention state', () {
    final chat = UserChat.fromJson({
      'id': 1,
      'chat_id': 'chat-1',
      'unread_count': 2,
      'has_mention': true,
    });

    expect(chat.hasMention, isTrue);
  });

  test('UserChat defaults missing mention state to false', () {
    final chat = UserChat.fromJson({
      'id': 1,
      'chat_id': 'chat-1',
    });

    expect(chat.hasMention, isFalse);
  });

  test('UserChat hides an S3 preview that requires media-id authorization', () {
    final chat = UserChat.fromJson({
      'id': 1,
      'chat_id': 'chat-1',
      'last_msg_media_url':
          'https://bucket.s3.ap-southeast-1.amazonaws.com/uploads/a.png',
    });

    expect(chat.lastMsgMediaUrl, isNull);
  });

  test('UserChat keeps a non-S3 preview URL', () {
    final chat = UserChat.fromJson({
      'id': 1,
      'chat_id': 'chat-1',
      'last_msg_media_url': 'https://cdn.example.com/uploads/a.png',
    });

    expect(chat.lastMsgMediaUrl, contains('cdn.example.com'));
  });
}
