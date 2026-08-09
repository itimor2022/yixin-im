import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:generic_im/core/services/android_message_notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('revokedMessageNotificationChatId', () {
    test('returns normalized chat id only for revocation pushes', () {
      expect(
        revokedMessageNotificationChatId({
          'type': 'message_revoked',
          'chat_id': '  chat-205  ',
        }),
        'chat-205',
      );
      expect(
        revokedMessageNotificationChatId({
          'type': 'new_message',
          'chat_id': 'chat-205',
        }),
        isNull,
      );
      expect(
        revokedMessageNotificationChatId({
          'type': 'message_revoked',
          'chat_id': '   ',
        }),
        isNull,
      );
    });
  });

  test('per-chat notification id is stable and bounded', () {
    final first = debugAndroidMessageNotificationIdForChat('chat-205');
    final second = debugAndroidMessageNotificationIdForChat('chat-205');
    final other = debugAndroidMessageNotificationIdForChat('chat-206');

    expect(second, first);
    expect(first, inInclusiveRange(10000, 89999));
    expect(other, isNot(first));
  });

  test('notification id matches Android native hash contract', () {
    expect(debugAndroidMessageNotificationIdForChat('chat-205'), 48082);
    expect(debugAndroidMessageNotificationIdForChat('群聊-205'), 75168);
  });

  test('legacy FCM automatic tag remains cancellable after client gating', () {
    expect(
      debugAndroidMessageNotificationTagForId(
        debugAndroidMessageNotificationIdForChat('chat-205'),
      ),
      'genericim-message-48082',
    );
  });

  test('FCM background gate accepts routable messages announcements meetings',
      () {
    expect(
      isFcmBackgroundVisibleNotificationPayload({
        'type': 'new_message',
        'chat_id': 'chat-349',
      }),
      isTrue,
    );
    expect(
      isFcmBackgroundVisibleNotificationPayload({
        'type': 'message_revoked',
        'chat_id': 'chat-349',
      }),
      isFalse,
    );
    expect(
      isFcmBackgroundVisibleNotificationPayload({'type': 'new_message'}),
      isFalse,
    );
    expect(
      isFcmBackgroundVisibleNotificationPayload({
        'type': 'chat_announcement',
        'chat_id': 'group-347',
        'notification_id': '347001',
      }),
      isTrue,
    );
    for (final type in <String>[
      'meeting_invite',
      'meeting_join_request',
      'meeting_join_request_reviewed',
      'meeting_status',
    ]) {
      expect(isMeetingNotificationType(type), isTrue, reason: type);
      expect(
        isFcmBackgroundVisibleNotificationPayload({
          'type': type,
          'meeting_id': 'meeting-349',
        }),
        isTrue,
        reason: type,
      );
    }
    expect(isMeetingNotificationType('new_message'), isFalse);
    expect(isAnnouncementNotificationType('chat_announcement'), isTrue);
    expect(isAnnouncementNotificationType('system_announcement'), isTrue);
    expect(
      isFcmBackgroundVisibleNotificationPayload({
        'type': 'system_announcement',
        'broadcast_id': '88',
        'notification_id': '2000088',
      }),
      isTrue,
    );
    expect(
      isFcmBackgroundVisibleNotificationPayload({
        'type': 'system_announcement',
        'broadcast_id': '88',
      }),
      isFalse,
    );
    expect(
      isFcmBackgroundVisibleNotificationPayload({
        'type': 'meeting_invite',
      }),
      isFalse,
    );
  });

  test('local notification tap keeps the full FCM route payload', () {
    final encoded = encodeAndroidMessageNotificationTap({
      'type': 'new_message',
      'chat_id': 'chat-349',
      'chat_type': 'group',
      'message_id': 'message-349',
    });

    expect(decodeAndroidMessageNotificationTap(encoded), {
      'type': 'new_message',
      'chat_id': 'chat-349',
      'chat_type': 'group',
      'message_id': 'message-349',
    });
    expect(decodeAndroidMessageNotificationTap('legacy-chat'), {
      'type': 'new_message',
      'chat_id': 'legacy-chat',
    });
  });

  test('client-gated FCM notification preserves inline reply', () {
    final actions = androidMessageNotificationActionsForPayload({
      'type': 'new_message',
      'chat_id': 'chat-355',
    });
    expect(actions, hasLength(1));
    expect(actions.single.id, androidMessageNotificationReplyActionId);
    expect(actions.single.showsUserInterface, isTrue);
    expect(actions.single.cancelNotification, isFalse);
    expect(actions.single.inputs, hasLength(1));

    final response = NotificationResponse(
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
      actionId: androidMessageNotificationReplyActionId,
      input: '  快捷回复内容  ',
      payload: encodeAndroidMessageNotificationTap({
        'type': 'new_message',
        'chat_id': 'chat-355',
        'chat_type': 'private',
      }),
    );
    expect(
      androidMessageNotificationResponseData(
        response,
        clientMessageId: 'reply-client-355',
      ),
      {
        'type': 'notification_reply',
        'chat_id': 'chat-355',
        'chat_type': 'private',
        'reply_text': '快捷回复内容',
        'client_msg_id': 'reply-client-355',
      },
    );
    expect(androidMessageNotificationActionsForPayload(null), isEmpty);
  });

  test('background master mirror persists the final local gate', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    expect(await readAndroidNotificationMasterMirror(), isTrue);

    await writeAndroidNotificationMasterMirror(false);
    expect(await readAndroidNotificationMasterMirror(), isFalse);

    await writeAndroidNotificationMasterMirror(true);
    expect(await readAndroidNotificationMasterMirror(), isTrue);
  });

  test('active chat is visible only while app is resumed', () {
    expect(
      shouldTreatActiveChatAsVisible(
        activeChatMatches: true,
        lifecycleState: AppLifecycleState.resumed,
      ),
      isTrue,
    );
    for (final state in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    ]) {
      expect(
        shouldTreatActiveChatAsVisible(
          activeChatMatches: true,
          lifecycleState: state,
        ),
        isFalse,
        reason: state.name,
      );
    }
  });

  test('disabled preview removes both sender and message text', () {
    final hidden = messageNotificationPrivacyText(
      showPreview: false,
      title: 'Alice',
      body: '私密正文',
    );
    expect(hidden.title, '新消息');
    expect(hidden.body, '您收到一条新消息');
    expect('${hidden.title}${hidden.body}', isNot(contains('Alice')));
    expect('${hidden.title}${hidden.body}', isNot(contains('私密正文')));
  });
}
