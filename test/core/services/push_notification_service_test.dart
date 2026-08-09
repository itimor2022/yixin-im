import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/push_notification_service.dart';

void main() {
  test('notification tap signature separates announcements in one chat', () {
    final first = debugNotificationTapSignature(<String, dynamic>{
      'type': 'chat_announcement',
      'chat_id': 'group-1',
      'announcement_id': '42',
      'notification_id': '100042',
    });
    final duplicate = debugNotificationTapSignature(<String, dynamic>{
      'notification_id': 100042,
      'announcement_id': 42,
      'chat_id': 'group-1',
      'type': 'chat_announcement',
    });
    final second = debugNotificationTapSignature(<String, dynamic>{
      'type': 'chat_announcement',
      'chat_id': 'group-1',
      'announcement_id': '43',
      'notification_id': '100043',
    });

    expect(duplicate, first);
    expect(second, isNot(first));
  });
}
