import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/i18n/app_localizations.dart';
import 'package:generic_im/features/chat/utils/call_preview_formatter.dart';

void main() {
  tearDown(() {
    AppLocalizations.setCurrentLanguage(AppLanguage.zhCN);
  });

  test('completed voice call shows duration', () {
    final preview = formatChatCallPreview(
      callType: 'voice',
      status: 'hangup',
      durationSeconds: 36,
      language: AppLanguage.zhCN,
    );

    expect(preview.summary, '语音通话 00:36');
    expect(preview.isAttention, isFalse);
  });

  test('incoming timeout shows missed call', () {
    final preview = formatChatCallPreview(
      callType: 'voice',
      status: 'timeout',
      durationSeconds: 0,
      isOutgoing: false,
      language: AppLanguage.zhCN,
    );

    expect(preview.summary, '语音通话 未接听');
    expect(preview.isAttention, isTrue);
  });

  test('outgoing timeout shows no answer', () {
    final preview = formatChatCallPreview(
      callType: 'voice',
      status: 'timeout',
      durationSeconds: 0,
      isOutgoing: true,
      language: AppLanguage.zhCN,
    );

    expect(preview.summary, '语音通话 未接通');
    expect(preview.isAttention, isTrue);
  });

  test('declined video call keeps video type', () {
    final preview = formatChatCallPreview(
      callType: 'video',
      status: 'decline',
      language: AppLanguage.zhCN,
    );

    expect(preview.summary, '视频通话 已拒绝');
    expect(preview.isVideo, isTrue);
    expect(preview.isAttention, isTrue);
  });

  test('legacy text with duration is parsed', () {
    final preview = formatChatCallPreview(
      text: '视频通话 01:02',
      language: AppLanguage.zhCN,
    );

    expect(preview.summary, '视频通话 01:02');
    expect(preview.isVideo, isTrue);
  });

  test('cancelled English text is localized', () {
    final preview = formatChatCallPreview(
      text: 'voice call cancelled',
      language: AppLanguage.zhCN,
    );

    expect(preview.summary, '语音通话 已取消');
  });

  test('legacy mojibake cancelled text is repaired', () {
    final legacyVoiceCall =
        String.fromCharCodes([0x7487, 0xe162, 0x7176, 0x95ab, 0x6c33, 0x763d]);
    final preview = formatChatCallPreview(
      text: '$legacyVoiceCall cancelled',
      language: AppLanguage.zhCN,
    );

    expect(preview.summary, '语音通话 已取消');
  });

  test('partial legacy mojibake cancelled text is repaired', () {
    final partialLegacy =
        String.fromCharCodes([0x7487, 0x7176, 0x95ab, 0x6c33, 0x763d]);
    final preview = formatChatCallPreview(
      text: '$partialLegacy cancelled',
      language: AppLanguage.zhCN,
    );

    expect(preview.summary, '语音通话 已取消');
  });
}
