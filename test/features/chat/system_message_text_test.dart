import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/i18n/app_localizations.dart';
import 'package:generic_im/features/chat/utils/system_message_text.dart';

void main() {
  tearDown(() {
    AppLocalizations.setCurrentLanguage(AppLanguage.zhCN);
  });

  test('meeting ended event code is localized for chat previews', () {
    AppLocalizations.setCurrentLanguage(AppLanguage.zhCN);

    expect(looksLikeServerSystemPreviewText('meeting_ended'), isTrue);
    expect(resolveServerPreviewText('meeting_ended'), '会议已经结束');
  });

  test('meeting ended event code keeps English when language is English', () {
    AppLocalizations.setCurrentLanguage(AppLanguage.en);

    expect(resolveServerPreviewText('meeting_ended'), 'Meeting ended');
  });

  test('legacy English meeting ended preview is localized', () {
    AppLocalizations.setCurrentLanguage(AppLanguage.zhCN);

    const preview = 'voice group meeting ended: host_end';
    expect(looksLikeServerSystemPreviewText(preview), isTrue);
    expect(resolveServerPreviewText(preview), '会议已经结束');
  });
}
