// 文件用途：封装 android callkit helper 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 android callkit helper 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:uuid/uuid.dart';

import 'api/system_settings_service.dart';

// 关键声明：android callkit helper 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
const Duration kIncomingCallkitDuration = Duration(seconds: 30);

DateTime? parseIncomingCallExpiresAt(Object? rawExpiresAt) {
  final raw = rawExpiresAt?.toString().trim() ?? '';
  if (raw.isEmpty) return null;

  final numeric = int.tryParse(raw);
  if (numeric != null) {
    if (numeric <= 0) return null;
    final milliseconds = numeric >= 1000000000000 ? numeric : numeric * 1000;
    try {
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    } on RangeError {
      return null;
    }
  }

  return DateTime.tryParse(raw)?.toUtc();
}

// 流程逻辑：`incomingCallExpiryPassed` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
bool incomingCallExpiryPassed(Object? rawExpiresAt, DateTime now) {
  final expiresAt = parseIncomingCallExpiresAt(rawExpiresAt);
  return expiresAt != null && !expiresAt.isAfter(now.toUtc());
}

Duration incomingCallDisplayDuration(
  Map<String, dynamic> data, {
  DateTime? now,
}) {
  final expiresAt = parseIncomingCallExpiresAt(data['expires_at']);
  if (expiresAt == null) return kIncomingCallkitDuration;

  final remaining = expiresAt.difference((now ?? DateTime.now()).toUtc());
  if (remaining <= Duration.zero) return Duration.zero;
  if (remaining > kIncomingCallkitDuration) {
    return kIncomingCallkitDuration;
  }
  return remaining;
}

bool incomingCallPayloadIsExpired(
  Map<String, dynamic> data, {
  DateTime? now,
}) {
  return incomingCallExpiryPassed(
    data['expires_at'],
    now ?? DateTime.now(),
  );
}

bool shouldShowAndroidIncomingCallNotification(
  Map<String, dynamic> data, {
  required bool masterEnabled,
  DateTime? now,
}) {
  if (!masterEnabled || !isIncomingCallPayload(data)) return false;
  return !incomingCallPayloadIsExpired(data, now: now);
}

String _stringValue(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

bool _boolValue(dynamic value) {
  return value == true || value?.toString().toLowerCase() == 'true';
}

String _stableAndroidCallKitId(Map<String, dynamic> payload) {
  final callId = _stringValue(payload, ['call_id', 'callId']);
  if (callId.isNotEmpty) return 'call-$callId';
  return const Uuid().v4();
}

String _callActionText(String actionKey) {
  switch (actionKey) {
    case 'answer':
      return '\u63a5\u542c';
    case 'decline':
      return '\u62d2\u7edd';
    default:
      return '\u901a\u8bdd';
  }
}

/// 把 FCM、WebSocket 和系统回调的兼容字段归一为 CallKit 可恢复的稳定载荷。
Map<String, dynamic> normalizeIncomingCallPayload(Map<String, dynamic> data) {
  final callType =
      data['call_type']?.toString() == 'video' || _boolValue(data['is_video'])
          ? 'video'
          : 'voice';
  final channelName = _stringValue(data, ['channel_name', 'room_name']);
  final roomName = _stringValue(data, ['room_name', 'channel_name']);
  final provider = _stringValue(data, ['rtc_provider', 'provider']);
  final serverUrl = _stringValue(data, ['server_url', 'livekit_server_url']);

  return <String, dynamic>{
    ...data,
    'type': 'incoming_call',
    'call_id': data['call_id'] ?? data['callId'],
    'callId': data['callId'] ?? data['call_id'],
    'caller_id': _stringValue(data, ['caller_id']),
    'caller_name': _stringValue(data, ['caller_name', 'title', 'nameCaller']),
    'caller_avatar': _stringValue(data, ['caller_avatar', 'avatar']),
    'call_type': callType,
    'is_video': callType == 'video',
    'channel_name': channelName,
    'room_name': roomName.isNotEmpty ? roomName : channelName,
    'provider': provider,
    'rtc_provider': provider,
    'server_url': serverUrl,
    'livekit_server_url': serverUrl,
  };
}

bool isIncomingCallPayload(Map<String, dynamic> data) {
  final payload = normalizeIncomingCallPayload(data);
  return payload['type'] == 'incoming_call' &&
      payload['call_id'] != null &&
      payload['caller_id']?.toString().isNotEmpty == true &&
      payload['caller_name']?.toString().isNotEmpty == true &&
      payload['channel_name']?.toString().isNotEmpty == true;
}

CallKitParams buildAndroidIncomingCallParams(
  Map<String, dynamic> data, {
  String? uuid,
  DateTime? now,
}) {
  final payload = normalizeIncomingCallPayload(data);
  final id = uuid ?? _stableAndroidCallKitId(payload);
  final callerName = payload['caller_name']?.toString() ?? '';
  final callerAvatar = payload['caller_avatar']?.toString() ?? '';
  final isVideo = payload['call_type'] == 'video';

  return CallKitParams(
    id: id,
    nameCaller: callerName,
    appName: defaultAppDisplayName(),
    avatar: callerAvatar.isNotEmpty ? callerAvatar : null,
    handle: callerName,
    type: isVideo ? 1 : 0,
    duration: incomingCallDisplayDuration(data, now: now).inMilliseconds,
    textAccept: _callActionText('answer'),
    textDecline: _callActionText('decline'),
    extra: payload,
    headers: const <String, dynamic>{},
    android: const AndroidParams(
      isCustomNotification: true,
      isShowLogo: false,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#5865F2',
      backgroundUrl: '',
      actionColor: '#4CAF50',
      textColor: '#FFFFFF',
      isShowFullLockedScreen: true,
      isShowCallID: false,
      incomingCallNotificationChannelName: '\u6765\u7535\u901a\u77e5',
      missedCallNotificationChannelName: '\u672a\u63a5\u6765\u7535',
      isImportant: true,
    ),
  );
}

Future<void> showAndroidIncomingCallFromPayload(
  Map<String, dynamic> data, {
  Future<bool> Function()? notificationMasterEnabled,
}) async {
  // 后台 isolate 可能在准备通知期间收到设置变化，因此展示前后各校验一次总开关与过期时间。
  final firstMasterState =
      notificationMasterEnabled == null || await notificationMasterEnabled();
  final now = DateTime.now();
  if (!shouldShowAndroidIncomingCallNotification(
    data,
    masterEnabled: firstMasterState,
    now: now,
  )) {
    if (!firstMasterState) {
      debugPrint(
          '[CallKit] Incoming call skipped: notification master disabled');
      return;
    }
    if (!isIncomingCallPayload(data)) {
      debugPrint('[CallKit] Invalid incoming call payload: $data');
      return;
    }
    debugPrint(
      '[CallKit] Expired incoming call suppressed: '
      '${data['call_id'] ?? data['callId']}',
    );
    return;
  }
  if (notificationMasterEnabled != null && !await notificationMasterEnabled()) {
    debugPrint(
      '[CallKit] Incoming call skipped after preparation: '
      'notification master disabled',
    );
    return;
  }
  if (!isIncomingCallPayload(data)) {
    debugPrint('[CallKit] Invalid incoming call payload: $data');
    return;
  }
  if (incomingCallPayloadIsExpired(data, now: now)) {
    debugPrint(
      '[CallKit] Expired incoming call suppressed: '
      '${data['call_id'] ?? data['callId']}',
    );
    return;
  }
  await FlutterCallkitIncoming.showCallkitIncoming(
    buildAndroidIncomingCallParams(data, now: now),
  );
}
