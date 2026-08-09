import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/i18n/app_localizations.dart';
import 'package:generic_im/core/services/force_logout_notice.dart';

void main() {
  test('force logout notice includes actor device and server time', () {
    final notice = ForceLogoutNotice.fromPayload({
      'reason': 'device_terminated',
      'actor_device_name': 'Huawei B',
      'occurred_at': '2026-07-17T19:04:05Z',
    });

    final message = notice.localizedMessage(AppLanguage.zhCN);
    expect(message, contains('Huawei B'));
    expect(message, contains('下线'));
    expect(message, contains('重新登录'));
    expect(message, contains('2026-'));
  });

  test('force logout notice has safe fallback without metadata', () {
    final notice = ForceLogoutNotice.fromPayload(const {});

    final message = notice.localizedMessage(AppLanguage.en);
    expect(message, contains('another device'));
    expect(message, contains('Sign in again'));
  });
}
