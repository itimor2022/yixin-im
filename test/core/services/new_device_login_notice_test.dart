import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/i18n/app_localizations.dart';
import 'package:generic_im/core/services/new_device_login_notice.dart';

void main() {
  test('new device login notice includes audit context', () {
    final notice = NewDeviceLoginNotice.fromPayload({
      'event_id': 'event-1',
      'device_id': 'phone-b',
      'device_type': 'android',
      'device_name': 'Huawei B',
      'ip': '192.0.2.9',
      'occurred_at': '2026-07-17T19:04:05Z',
    });

    final message = notice.localizedMessage(AppLanguage.zhCN);
    expect(notice.eventId, 'event-1');
    expect(message, contains('Huawei B'));
    expect(message, contains('192.0.2.9'));
    expect(message, contains('2026-'));
    expect(message, contains('修改密码'));
  });

  test('new device login notice has safe fallback', () {
    final notice = NewDeviceLoginNotice.fromPayload(const {});

    final message = notice.localizedMessage(AppLanguage.en);
    expect(message, contains('A new device'));
    expect(message, contains('review signed-in devices'));
  });
}
