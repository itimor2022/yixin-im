import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/offline_message_queue.dart';

void main() {
  test('offline message persists its owning account', () {
    final message = OfflineMessage(
      accountId: 'account-a',
      id: 'client-message-1',
      chatId: 'chat-1',
      type: OfflineMessageType.text,
      content: 'hello',
      createdAt: DateTime.utc(2026, 7, 14),
    );

    final restored = OfflineMessage.fromJson(message.toJson());

    expect(restored.accountId, 'account-a');
    expect(restored.id, message.id);
    expect(restored.chatId, message.chatId);
    expect(restored.content, message.content);
  });
}
