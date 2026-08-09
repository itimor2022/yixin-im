import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/api/chat_service.dart';

SearchMessageItem messageItem({
  required int type,
  Map<String, dynamic> content = const {},
}) {
  return SearchMessageItem(
    id: 'message-1',
    seq: 1,
    chatId: 'chat-1',
    senderId: 'user-1',
    type: type,
    content: content,
    createdAt: DateTime.utc(2026, 7, 18),
  );
}

void main() {
  test('search message item keeps text content as preview', () {
    expect(
      messageItem(type: 1, content: const {'text': 'hello'}).text,
      'hello',
    );
  });

  test('search message item renders useful non-text previews', () {
    expect(messageItem(type: 2).text, '[图片]');
    expect(
      messageItem(type: 4, content: const {
        'voice': {'transcript': 'voice transcript'},
      }).text,
      'voice transcript',
    );
    expect(
      messageItem(type: 5, content: const {
        'file': {'name': 'report.pdf'},
      }).text,
      'report.pdf',
    );
  });
}
