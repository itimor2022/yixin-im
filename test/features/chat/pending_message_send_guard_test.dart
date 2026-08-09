import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/features/chat/providers/message_provider.dart';

void main() {
  test('cancels the active upload and retains the cancellation decision', () {
    final guard = PendingMessageSendGuard();
    final token = guard.registerUpload('local-message-1');

    expect(guard.cancel('local-message-1'), isTrue);
    expect(token.isCancelled, isTrue);
    expect(guard.isCancelled('local-message-1'), isTrue);

    guard.uploadFinished('local-message-1');
    expect(guard.isCancelled('local-message-1'), isTrue);
  });

  test('rejects an upload registered after the message was cancelled', () {
    final guard = PendingMessageSendGuard();
    guard.cancel('local-message-2');

    final token = guard.registerUpload('local-message-2');

    expect(token.isCancelled, isTrue);
    expect(guard.isCancelled('local-message-2'), isTrue);
  });
}
