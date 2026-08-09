import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/features/settings/pages/privacy_settings_page.dart';

void main() {
  test('privacy activity settings default to enabled for old payloads', () {
    final settings = PrivacySettings.fromJson(const <String, dynamic>{});

    expect(settings.sendReadReceipts, isTrue);
    expect(settings.showTypingStatus, isTrue);
  });

  test('privacy activity settings parse and copy independently', () {
    final settings = PrivacySettings.fromJson(const <String, dynamic>{
      'send_read_receipts': false,
      'show_typing_status': false,
    });

    expect(settings.sendReadReceipts, isFalse);
    expect(settings.showTypingStatus, isFalse);
    expect(settings.copyWith(sendReadReceipts: true).sendReadReceipts, isTrue);
    expect(settings.copyWith(showTypingStatus: true).showTypingStatus, isTrue);
  });
}
