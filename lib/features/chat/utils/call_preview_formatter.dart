// 文件用途：提供 ChatCallKind 相关工具函数与通用转换逻辑，属于聊天与消息。
// 核心逻辑：提供 ChatCallKind 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
import '../../../core/i18n/app_localizations.dart';

// 关键声明：call preview formatter 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
enum ChatCallKind { voice, video }

enum ChatCallOutcome {
  completed,
  missed,
  noAnswer,
  declined,
  cancelled,
  busy,
  ended,
  unknown,
}

class ChatCallPreview {
  final ChatCallKind kind;
  final ChatCallOutcome outcome;
  final int? durationSeconds;
  final String title;
  final String? detail;
  final bool isAttention;

  const ChatCallPreview({
    required this.kind,
    required this.outcome,
    required this.title,
    this.detail,
    this.durationSeconds,
    this.isAttention = false,
  });

  bool get isVideo => kind == ChatCallKind.video;

  String get summary {
    final value = detail?.trim();
    if (value == null || value.isEmpty) return title;
    return '$title $value';
  }
}

ChatCallPreview formatChatCallPreview({
  String? text,
  String? callType,
  String? status,
  int? durationSeconds,
  bool isOutgoing = false,
  AppLanguage? language,
}) {
  final lang = language ?? AppLocalizations.currentLanguage;
  final raw = _repairMojibakeCallPreview((text ?? '').trim());
  final lower = raw.toLowerCase();
  final statusValue = (status ?? '').trim().toLowerCase();
  final kind = _detectKind(raw: raw, callType: callType);
  final duration = _normalizeDurationSeconds(
    durationSeconds ?? _durationSecondsFromText(raw),
  );
  final outcome = _detectOutcome(
    raw: raw,
    lower: lower,
    status: statusValue,
    durationSeconds: duration,
    isOutgoing: isOutgoing,
  );

  return ChatCallPreview(
    kind: kind,
    outcome: outcome,
    durationSeconds: duration,
    title: _callTitle(kind, lang),
    detail: _detailForOutcome(outcome, duration, lang),
    isAttention: _isAttentionOutcome(outcome),
  );
}

ChatCallKind _detectKind({required String raw, String? callType}) {
  final type = (callType ?? '').trim().toLowerCase();
  final lower = raw.toLowerCase();
  if (type == 'video' ||
      lower.contains('video') ||
      raw.contains('视频') ||
      raw.contains('視訊') ||
      raw.contains(_legacyVideoCallMojibake) ||
      raw.contains(_legacyVideoCallMarker) ||
      raw.contains(_legacyVideoCallMarkerAlt)) {
    return ChatCallKind.video;
  }
  return ChatCallKind.voice;
}

ChatCallOutcome _detectOutcome({
  required String raw,
  required String lower,
  required String status,
  required int? durationSeconds,
  required bool isOutgoing,
}) {
  if (status == 'decline' ||
      status == 'declined' ||
      status == 'reject' ||
      status == 'rejected' ||
      lower.contains('declined') ||
      lower.contains('rejected') ||
      raw.contains('已拒绝') ||
      raw.contains('已拒絕') ||
      raw.contains('拒绝') ||
      raw.contains('拒絕')) {
    return ChatCallOutcome.declined;
  }

  if (status == 'busy' ||
      lower.contains('busy') ||
      raw.contains('对方忙') ||
      raw.contains('對方忙')) {
    return ChatCallOutcome.busy;
  }

  if (status == 'cancelled' ||
      status == 'canceled' ||
      status == 'cancel' ||
      lower.contains('cancelled') ||
      lower.contains('canceled') ||
      raw.contains('已取消') ||
      raw.contains('取消')) {
    return ChatCallOutcome.cancelled;
  }

  if (status == 'timeout' ||
      status == 'missed' ||
      status == 'no_answer' ||
      lower.contains('no answer') ||
      lower.contains('missed') ||
      raw.contains('無應答')) {
    return isOutgoing ? ChatCallOutcome.noAnswer : ChatCallOutcome.missed;
  }

  if (status == 'hangup' ||
      status == 'remote_hangup' ||
      status == 'completed' ||
      status == 'ended') {
    if ((durationSeconds ?? 0) > 0) return ChatCallOutcome.completed;
    return ChatCallOutcome.ended;
  }

  if ((durationSeconds ?? 0) > 0) {
    return ChatCallOutcome.completed;
  }

  if (durationSeconds == 0 && _hasDurationText(raw)) {
    return isOutgoing ? ChatCallOutcome.noAnswer : ChatCallOutcome.missed;
  }

  if (_containsCallType(raw)) {
    return ChatCallOutcome.ended;
  }

  return ChatCallOutcome.unknown;
}

String? _detailForOutcome(
  ChatCallOutcome outcome,
  int? durationSeconds,
  AppLanguage language,
) {
  switch (outcome) {
    case ChatCallOutcome.completed:
      return _formatDuration(durationSeconds ?? 0);
    case ChatCallOutcome.missed:
      return _localized(language, zhCN: '未接听', zhTW: '未接聽', en: 'Missed');
    case ChatCallOutcome.noAnswer:
      return _localized(language, zhCN: '未接通', zhTW: '未接通', en: 'No answer');
    case ChatCallOutcome.declined:
      return _localized(language, zhCN: '已拒绝', zhTW: '已拒絕', en: 'Declined');
    case ChatCallOutcome.cancelled:
      return _localized(language, zhCN: '已取消', zhTW: '已取消', en: 'Cancelled');
    case ChatCallOutcome.busy:
      return _localized(language, zhCN: '对方忙', zhTW: '對方忙', en: 'Busy');
    case ChatCallOutcome.ended:
      return _localized(language, zhCN: '已结束', zhTW: '已結束', en: 'Ended');
    case ChatCallOutcome.unknown:
      return null;
  }
}

// 流程逻辑：`_isAttentionOutcome` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
bool _isAttentionOutcome(ChatCallOutcome outcome) {
  switch (outcome) {
    case ChatCallOutcome.missed:
    case ChatCallOutcome.noAnswer:
    case ChatCallOutcome.declined:
    case ChatCallOutcome.cancelled:
    case ChatCallOutcome.busy:
      return true;
    case ChatCallOutcome.completed:
    case ChatCallOutcome.ended:
    case ChatCallOutcome.unknown:
      return false;
  }
}

String _callTitle(ChatCallKind kind, AppLanguage language) {
  if (kind == ChatCallKind.video) {
    return _localized(language, zhCN: '视频通话', zhTW: '視訊通話', en: 'Video call');
  }
  return _localized(language, zhCN: '语音通话', zhTW: '語音通話', en: 'Voice call');
}

String _localized(
  AppLanguage language, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

int? _durationSecondsFromText(String raw) {
  final match = RegExp(r'(\d{1,2}:)?\d{1,2}:\d{2}').firstMatch(raw);
  if (match == null) return null;
  final parts = match.group(0)!.split(':').map(int.tryParse).toList();
  if (parts.any((e) => e == null)) return null;
  if (parts.length == 3) {
    return parts[0]! * 3600 + parts[1]! * 60 + parts[2]!;
  }
  return parts[0]! * 60 + parts[1]!;
}

bool _hasDurationText(String raw) {
  return RegExp(r'(\d{1,2}:)?\d{1,2}:\d{2}').hasMatch(raw);
}

int? _normalizeDurationSeconds(int? value) {
  if (value == null) return null;
  if (value < 0) return null;
  return value;
}

String _formatDuration(int seconds) {
  final safeSeconds = seconds < 0 ? 0 : seconds;
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  final remainingSeconds = safeSeconds % 60;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${remainingSeconds.toString().padLeft(2, '0')}';
  }
  return '${minutes.toString().padLeft(2, '0')}:'
      '${remainingSeconds.toString().padLeft(2, '0')}';
}

bool _containsCallType(String raw) {
  final lower = raw.toLowerCase();
  return lower.contains('voice') ||
      lower.contains('video') ||
      raw.contains('语音') ||
      raw.contains('語音') ||
      raw.contains('视频') ||
      raw.contains('視訊') ||
      raw.contains(_legacyVoiceCallMojibake) ||
      raw.contains(_legacyVideoCallMojibake) ||
      _looksLikeLegacyMojibakeCall(raw);
}

String _repairMojibakeCallPreview(String raw) {
  if (raw.isEmpty) return raw;
  var repaired = raw
      .replaceAll(_legacyVoiceCallMojibake, '语音通话')
      .replaceAll(_legacyVideoCallMojibake, '视频通话');

  if (!_looksLikeLegacyMojibakeCall(repaired)) return repaired;

  final hasVideo = repaired.contains(_legacyVideoCallMarker) ||
      repaired.contains(_legacyVideoCallMarkerAlt);
  final label = hasVideo ? '视频通话' : '语音通话';
  final duration =
      RegExp(r'\d{1,2}:\d{2}(?::\d{2})?').firstMatch(repaired)?.group(0);
  final lower = repaired.toLowerCase();

  String suffix = '';
  if (lower.contains('cancelled') || lower.contains('canceled')) {
    suffix = ' 已取消';
  } else if (lower.contains('declined') || lower.contains('rejected')) {
    suffix = ' 已拒绝';
  } else if (lower.contains('busy')) {
    suffix = ' 对方忙';
  } else if (lower.contains('missed') || lower.contains('no answer')) {
    suffix = ' 未接';
  } else if (duration != null && duration.isNotEmpty) {
    suffix = ' $duration';
  }
  return '$label$suffix';
}

bool _looksLikeLegacyMojibakeCall(String raw) {
  return raw.contains(_legacyCallRequiredMarkerA) &&
      raw.contains(_legacyCallRequiredMarkerB) &&
      (raw.contains(_legacyVoiceCallMarkerA) ||
          raw.contains(_legacyVoiceCallMarkerB) ||
          raw.contains(_legacyVideoCallMarker) ||
          raw.contains(_legacyVideoCallMarkerB) ||
          raw.contains(_legacyVideoCallMarkerAlt));
}

final _legacyVoiceCallMojibake =
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
