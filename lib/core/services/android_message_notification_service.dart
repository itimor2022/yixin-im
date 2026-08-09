// 文件用途：封装 AndroidMessageNotificationService 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 AndroidMessageNotificationService 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../utils/platform_utils.dart';

const String androidNotificationMasterMirrorKey =
    'android_notification_master_enabled_v1';
const String androidMessageNotificationReplyActionId = 'reply';

// 流程逻辑：`androidMessageNotificationActionsForPayload` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
List<AndroidNotificationAction> androidMessageNotificationActionsForPayload(
  Map<String, dynamic>? payload,
) {
  if (payload?['type']?.toString().trim() != 'new_message' ||
      payload?['chat_id']?.toString().trim().isNotEmpty != true) {
    return const <AndroidNotificationAction>[];
  }
  return const <AndroidNotificationAction>[
    AndroidNotificationAction(
      androidMessageNotificationReplyActionId,
      '回复',
      showsUserInterface: true,
      allowGeneratedReplies: true,
      cancelNotification: false,
      inputs: <AndroidNotificationActionInput>[
        AndroidNotificationActionInput(label: '回复'),
      ],
    ),
  ];
}

bool isMeetingNotificationType(Object? rawType) {
  final type = rawType?.toString().trim();
  return type == 'meeting_invite' ||
      type == 'meeting_join_request' ||
      type == 'meeting_join_request_reviewed' ||
      type == 'meeting_status';
}

bool isAnnouncementNotificationType(Object? rawType) {
  final type = rawType?.toString().trim();
  return type == 'chat_announcement' || type == 'system_announcement';
}

bool isFcmBackgroundVisibleNotificationPayload(Map<String, dynamic> payload) {
  final type = payload['type']?.toString().trim();
  if (type == 'new_message' || type == 'chat_announcement') {
    return payload['chat_id']?.toString().trim().isNotEmpty == true;
  }
  if (type == 'system_announcement') {
    return payload['broadcast_id']?.toString().trim().isNotEmpty == true &&
        payload['notification_id']?.toString().trim().isNotEmpty == true;
  }
  if (isMeetingNotificationType(type)) {
    return payload['meeting_id']?.toString().trim().isNotEmpty == true;
  }
  return false;
}

String encodeAndroidMessageNotificationTap(Map<String, dynamic> payload) {
  return jsonEncode(payload);
}

Map<String, dynamic>? decodeAndroidMessageNotificationTap(String? payload) {
  final raw = payload?.trim() ?? '';
  if (raw.isEmpty) return null;
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  } catch (_) {
    // Older local notifications stored only the chat id.
  }
  return <String, dynamic>{'type': 'new_message', 'chat_id': raw};
}

Map<String, dynamic>? androidMessageNotificationResponseData(
  NotificationResponse response, {
  String? clientMessageId,
}) {
  final data = decodeAndroidMessageNotificationTap(response.payload);
  if (data == null) return null;
  if (response.actionId == androidMessageNotificationReplyActionId) {
    return <String, dynamic>{
      ...data,
      'type': 'notification_reply',
      'reply_text': response.input?.trim() ?? '',
      'client_msg_id': clientMessageId ?? const Uuid().v4(),
    };
  }
  return data;
}

Future<void> writeAndroidNotificationMasterMirror(bool enabled) async {
  // 该镜像供 Flutter 未运行时的原生推送接收器读取，不等同于系统通知权限。
  final preferences = await SharedPreferences.getInstance();
  await preferences.setBool(androidNotificationMasterMirrorKey, enabled);
}

Future<bool> readAndroidNotificationMasterMirror() async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  return preferences.getBool(androidNotificationMasterMirrorKey) ?? true;
}

/// Returns the chat whose visible message notification must be removed.
///
/// Keeping this parser independent from the push provider lets HMS, FCM and
/// the native vendor bridge use the same revocation contract.
String? revokedMessageNotificationChatId(Map<String, dynamic> payload) {
  if (payload['type']?.toString().trim() != 'message_revoked') return null;
  final chatId = payload['chat_id']?.toString().trim() ?? '';
  return chatId.isEmpty ? null : chatId;
}

/// A chat is only truly visible while Flutter is resumed. Android performs a
/// second screen/keyguard check before suppressing the actual notification.
bool shouldTreatActiveChatAsVisible({
  required bool activeChatMatches,
  required AppLifecycleState? lifecycleState,
}) {
  return activeChatMatches && lifecycleState == AppLifecycleState.resumed;
}

/// Keeps notification privacy wording identical across local and remote paths.
({String title, String body}) messageNotificationPrivacyText({
  required bool showPreview,
  required String title,
  required String body,
}) {
  if (showPreview) return (title: title, body: body);
  return (title: '新消息', body: '您收到一条新消息');
}

// 关键声明：android message notification service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
class AndroidMessageNotificationService {
  AndroidMessageNotificationService._();

  static final AndroidMessageNotificationService instance =
      AndroidMessageNotificationService._();

  static const String messageChannelId = 'genericim_messages';
  static const String messageChannelName = 'Messages';
  static const String messageChannelDescription =
      'Chat messages and push alerts';
  static const String announcementChannelId = 'genericim_announcements_v1';
  static const String announcementChannelName = 'Announcements';
  static const String announcementChannelDescription =
      'Group and system announcement alerts';
  static const String meetingChannelId = 'genericim_meetings_v1';
  static const String meetingChannelName = 'Meetings';
  static const String meetingChannelDescription =
      'Meeting invitations and status alerts';
  static const String _defaultIcon = 'ic_notification';
  static const MethodChannel _nativeChannel =
      MethodChannel('com.genericim/message_notifications');

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  Future<void>? _initializeFuture;
  bool _isInitialized = false;
  Function(Map<String, dynamic>)? _onNotificationTap;
  Map<String, dynamic>? _pendingNotificationTap;

  set onNotificationTap(Function(Map<String, dynamic>)? handler) {
    _onNotificationTap = handler;
    final pending = _pendingNotificationTap;
    if (handler != null && pending != null) {
      // 冷启动时路由层通常晚于通知插件就绪，暂存点击并在处理器注册后补投递。
      _pendingNotificationTap = null;
      handler(pending);
    }
  }

  void clearPendingNotificationTap() {
    _pendingNotificationTap = null;
  }

  Future<void> initialize() {
    if (!PlatformUtils.isAndroid) return Future<void>.value();
    // 复用同一个 Future，避免多个消息入口并发初始化通知插件。
    return _initializeFuture ??= _initialize();
  }

  Future<void> _initialize() async {
    if (_isInitialized) return;

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings(_defaultIcon),
    );

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _captureNotificationTap,
    );

    final launchDetails =
        await _notifications.getNotificationAppLaunchDetails();
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchResponse != null) {
      _captureNotificationTap(launchResponse);
    }

    _isInitialized = true;
  }

  void _captureNotificationTap(NotificationResponse response) {
    final data = androidMessageNotificationResponseData(response);
    if (data == null) return;
    debugPrint(
      '[AndroidMessageNotification] tapped keys=${data.keys.join(',')}',
    );
    final handler = _onNotificationTap;
    if (handler == null) {
      _pendingNotificationTap = data;
      return;
    }
    handler(data);
  }

  Future<void> showMessageNotification({
    required String chatId,
    String? messageId,
    required String title,
    required String body,
    int? unreadCount,
    bool activeChatMatches = false,
    bool enforceMasterSwitch = false,
    Map<String, dynamic>? tapData,
    int? notificationId,
    String channelId = messageChannelId,
    String channelName = messageChannelName,
    String channelDescription = messageChannelDescription,
    AndroidNotificationCategory category = AndroidNotificationCategory.message,
  }) async {
    if (!PlatformUtils.isAndroid) return;
    if (enforceMasterSwitch && !await readAndroidNotificationMasterMirror()) {
      debugPrint(
        '[AndroidMessageNotification] background message skipped: master disabled',
      );
      return;
    }
    await initialize();
    if (enforceMasterSwitch && !await readAndroidNotificationMasterMirror()) {
      return;
    }
    final displayTitle = _repairLegacyMojibakeText(title);
    final displayBody = _repairLegacyMojibakeText(body);

    final isMessageNotification =
        (tapData?['type']?.toString().trim() ?? 'new_message') ==
                'new_message' &&
            channelId == messageChannelId;
    final shownByNative = isMessageNotification
        ? await _showNativeMessageNotification(
            chatId: chatId,
            messageId: messageId,
            title: displayTitle,
            body: displayBody,
            unreadCount: unreadCount,
            activeChatMatches: activeChatMatches,
          )
        : false;
    // 原生桥接可在锁屏/后台准确判断可见性；不可用时才回退到 Flutter 插件。
    if (shownByNative) return;
    if (enforceMasterSwitch && !await readAndroidNotificationMasterMirror()) {
      return;
    }

    final notificationTapData = tapData ??
        <String, dynamic>{
          'type': 'new_message',
          'chat_id': chatId,
          if (messageId?.trim().isNotEmpty == true)
            'message_id': messageId!.trim(),
        };
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: category,
      visibility: NotificationVisibility.private,
      channelShowBadge: true,
      enableVibration: true,
      playSound: true,
      autoCancel: true,
      ticker: displayTitle,
      number: unreadCount == null || unreadCount <= 0 ? null : unreadCount,
      styleInformation: BigTextStyleInformation(displayBody),
      actions: androidMessageNotificationActionsForPayload(notificationTapData),
    );

    await _notifications.show(
      notificationId ?? _notificationIdForChat(chatId),
      displayTitle,
      displayBody,
      NotificationDetails(android: androidDetails),
      payload: encodeAndroidMessageNotificationTap(notificationTapData),
    );
  }

  /// 将当前账号的通知总开关镜像到原生存储。
  ///
  /// HMS 等厂商服务可在 Flutter 停止时执行该开关，但系统通知权限仍由操作系统管理。
  Future<void> setMasterEnabled(bool enabled) async {
    await writeAndroidNotificationMasterMirror(enabled);
    if (!PlatformUtils.isAndroid) return;
    try {
      await _nativeChannel.invokeMapMethod<String, dynamic>(
        'setNotificationMasterEnabled',
        <String, dynamic>{'enabled': enabled},
      );
    } catch (e) {
      debugPrint('[AndroidMessageNotification] master switch sync failed: $e');
    }
  }

  /// 消息撤回等场景下，移除该会话已经展示的通知。
  Future<void> cancelMessageNotification({
    required String chatId,
    String? messageId,
    bool markRevoked = true,
  }) async {
    if (!PlatformUtils.isAndroid) return;
    final normalizedChatId = chatId.trim();
    if (normalizedChatId.isEmpty) return;

    final notificationId = _notificationIdForChat(normalizedChatId);
    final fcmTag = debugAndroidMessageNotificationTagForId(notificationId);

    final cancelledByNative = await _cancelNativeMessageNotification(
      normalizedChatId,
      messageId: messageId,
      markRevoked: markRevoked,
    );
    if (cancelledByNative) return;

    // FCM SDK 展示的通知使用 id=0 和服务端 tag；这里同时取消两种标识，
    // 以兼容 MainActivity 不可用的无界面后台 isolate。
    await initialize();
    await _notifications.cancel(notificationId);
    await _notifications.cancel(0, tag: fcmTag);
  }

  Future<bool> _cancelNativeMessageNotification(
    String chatId, {
    String? messageId,
    required bool markRevoked,
  }) async {
    try {
      final result = await _nativeChannel.invokeMapMethod<String, dynamic>(
        'cancelMessageNotification',
        <String, dynamic>{
          'chat_id': chatId,
          if (messageId?.trim().isNotEmpty == true)
            'message_id': messageId!.trim(),
          'mark_revoked': markRevoked,
        },
      );
      final cancelled = result?['cancelled'] == true;
      if (!cancelled) {
        debugPrint(
          '[AndroidMessageNotification] native cancel skipped: $result',
        );
      }
      return cancelled;
    } catch (e) {
      debugPrint('[AndroidMessageNotification] native cancel failed: $e');
      return false;
    }
  }

  Future<bool> _showNativeMessageNotification({
    required String chatId,
    String? messageId,
    required String title,
    required String body,
    int? unreadCount,
    required bool activeChatMatches,
  }) async {
    try {
      final result = await _nativeChannel.invokeMapMethod<String, dynamic>(
        'showMessageNotification',
        <String, dynamic>{
          'chat_id': chatId,
          if (messageId?.trim().isNotEmpty == true)
            'message_id': messageId!.trim(),
          'title': title,
          'body': body,
          if (unreadCount != null) 'unread_count': unreadCount,
          'active_chat_matches': activeChatMatches,
        },
      );
      final handled = result?['shown'] == true ||
          result?['reason'] == 'active_chat_visible' ||
          result?['reason'] == 'master_disabled';
      if (!handled) {
        debugPrint(
          '[AndroidMessageNotification] native show skipped: $result',
        );
      }
      return handled;
    } catch (e) {
      debugPrint('[AndroidMessageNotification] native show failed: $e');
      return false;
    }
  }

  int _notificationIdForChat(String chatId) {
    return debugAndroidMessageNotificationIdForChat(chatId);
  }
}

/// 供回归测试验证；非空会话 ID 的计算必须与 MainActivity 原生实现完全一致，
/// 否则 Flutter 无法取消原生侧已经展示的通知。
int debugAndroidMessageNotificationIdForChat(String chatId) {
  var hash = 0;
  for (final unit in chatId.codeUnits) {
    hash = (hash * 31 + unit) & 0x3fffffff;
  }
  return 10000 + (hash % 80000);
}

String debugAndroidMessageNotificationTagForId(int notificationId) {
  return 'genericim-message-$notificationId';
}

String _repairLegacyMojibakeText(String value) {
  var repaired = value.trim();
  if (repaired.isEmpty) return '';

  repaired = repaired
      .replaceAll(_legacySystemSenderMojibake, '系统消息')
      .replaceAll(_legacyVoiceCallMojibakeA, '语音通话')
      .replaceAll(_legacyVoiceCallMojibakeB, '语音通话')
      .replaceAll(_legacyVoiceCallMojibakeC, '语音通话')
      .replaceAll(_legacyVideoCallMojibake, '视频通话');

  final looksLikeLegacyCall = repaired.contains(_legacyCallRequiredMarkerA) &&
      repaired.contains(_legacyCallRequiredMarkerB) &&
      (repaired.contains(_legacyVoiceCallMarkerA) ||
          repaired.contains(_legacyVoiceCallMarkerB) ||
          repaired.contains(_legacyVideoCallMarker) ||
          repaired.contains(_legacyVideoCallMarkerB) ||
          repaired.contains(_legacyVideoCallMarkerAlt));
  if (!looksLikeLegacyCall) return repaired;

  final label = repaired.contains(_legacyVideoCallMarker) ||
          repaired.contains(_legacyVideoCallMarkerAlt)
      ? '视频通话'
      : '语音通话';
  final duration =
      RegExp(r'\d{1,2}:\d{2}(?::\d{2})?').firstMatch(repaired)?.group(0);
  return duration == null ? label : '$label $duration';
}

final _legacySystemSenderMojibake =
    String.fromCharCodes([0x7eef, 0x837b, 0x7cba, 0x5a11, 0x581f, 0x4f05]);
final _legacyVoiceCallMojibakeA =
    String.fromCharCodes([0x7487, 0xe162, 0x7176, 0x95ab, 0x6c33, 0x761d]);
final _legacyVoiceCallMojibakeB =
    String.fromCharCodes([0x7487, 0xe162, 0x7176, 0x95ab, 0x6c33, 0x763d]);
final _legacyVoiceCallMojibakeC =
    String.fromCharCodes([0x7487, 0xe162, 0x7176, 0x95ab, 0x6c33, 0x763d]);
final _legacyVideoCallMojibake =
    String.fromCharCodes([0x7459, 0x55db, 0xe576, 0x95ab, 0x6c33, 0x763d]);
final _legacyCallRequiredMarkerA = String.fromCharCodes([0x95ab]);
final _legacyCallRequiredMarkerB = String.fromCharCodes([0x763d]);
final _legacyVoiceCallMarkerA = String.fromCharCodes([0x7487]);
final _legacyVoiceCallMarkerB = String.fromCharCodes([0x7176]);
final _legacyVideoCallMarker = String.fromCharCodes([0x7459]);
final _legacyVideoCallMarkerB = String.fromCharCodes([0x55db]);
final _legacyVideoCallMarkerAlt = String.fromCharCodes([0xe576]);
