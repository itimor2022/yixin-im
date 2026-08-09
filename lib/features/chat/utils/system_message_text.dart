// 文件用途：提供 system message text 相关工具函数与通用转换逻辑，属于聊天与消息。
// 核心逻辑：提供 system message text 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
import 'dart:convert';

import '../../../core/i18n/app_localizations.dart';

// 关键声明：system message text 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
String _systemMessageText({
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

String _systemOtherParty() => _systemMessageText(
      zhCN: '对方',
      zhTW: '對方',
      en: 'Other party',
    );

String _meetingTypeLabel(bool isVoice) => isVoice
    ? _systemMessageText(
        zhCN: '语音群会议',
        zhTW: '語音群會議',
        en: 'voice group meeting',
      )
    : _systemMessageText(
        zhCN: '视频群会议',
        zhTW: '視訊群會議',
        en: 'video group meeting',
      );

// 流程逻辑：`resolveSystemMessageText` 集中处理输入规范化、空值和兼容字段，输出稳定的数据结构，避免调用方重复实现边界判断。
String resolveSystemMessageText(String rawText, {String? currentUserId}) {
  if (rawText.isEmpty) {
    return _systemMessageText(
      zhCN: '[系统消息]',
      zhTW: '[系統訊息]',
      en: '[System message]',
    );
  }

  try {
    final data = jsonDecode(rawText) as Map<String, dynamic>;
    final type = data['type'] as String?;

    if (type == 'red_packet_claimed') {
      final claimerName =
          (data['claimer_name'] ?? _systemOtherParty()).toString();
      return _systemMessageText(
        zhCN: '$claimerName 领取了红包',
        zhTW: '$claimerName 領取了紅包',
        en: '$claimerName claimed the red packet',
      );
    }

    if (type == 'transfer_accepted') {
      final receiverName =
          (data['receiver_name'] ?? _systemOtherParty()).toString();
      return _systemMessageText(
        zhCN: '$receiverName 已收款',
        zhTW: '$receiverName 已收款',
        en: '$receiverName received the transfer',
      );
    }

    if (type == 'contact_added_system_message') {
      final adderId = (data['adder_id'] ?? '').toString();
      final adderName = (data['adder_name'] ?? _systemOtherParty()).toString();
      final targetId = (data['target_id'] ?? '').toString();
      final targetName =
          (data['target_name'] ?? _systemOtherParty()).toString();

      if (currentUserId != null && currentUserId.isNotEmpty) {
        if (currentUserId == adderId) {
          return _systemMessageText(
            zhCN: '您刚刚把$targetName添加到通讯录，现在可以开始聊天了',
            zhTW: '您剛剛把$targetName加入通訊錄，現在可以開始聊天了',
            en: 'You just added $targetName to your contacts. You can start chatting now.',
          );
        }
        if (currentUserId == targetId) {
          return _systemMessageText(
            zhCN: '$adderName刚刚把您添加到通讯录，现在可以开始聊天了',
            zhTW: '$adderName剛剛把您加入通訊錄，現在可以開始聊天了',
            en: '$adderName just added you to contacts. You can start chatting now.',
          );
        }
      }

      return _systemMessageText(
        zhCN: '$adderName刚刚把$targetName添加到通讯录，现在可以开始聊天了',
        zhTW: '$adderName剛剛把$targetName加入通訊錄，現在可以開始聊天了',
        en: '$adderName just added $targetName to contacts. You can start chatting now.',
      );
    }

    if (type == 'meeting_started') {
      final hostId = (data['host_user_id'] ?? '').toString();
      final hostName = (data['host_name'] ?? _systemOtherParty()).toString();
      final title =
          _shortenMeetingTitle(data['title']?.toString().trim() ?? '');
      final isVoice = (data['meeting_type'] ?? 'video').toString() == 'voice';
      final meetingType = _meetingTypeLabel(isVoice);
      final isCurrentUserHost =
          currentUserId != null && currentUserId == hostId;
      if (title.isNotEmpty) {
        return isCurrentUserHost
            ? _systemMessageText(
                zhCN: '您发起了$meetingType：$title',
                zhTW: '您發起了$meetingType：$title',
                en: 'You started a $meetingType: $title',
              )
            : _systemMessageText(
                zhCN: '$hostName发起了$meetingType：$title',
                zhTW: '$hostName發起了$meetingType：$title',
                en: '$hostName started a $meetingType: $title',
              );
      }
      return isCurrentUserHost
          ? _systemMessageText(
              zhCN: '您发起了$meetingType',
              zhTW: '您發起了$meetingType',
              en: 'You started a $meetingType',
            )
          : _systemMessageText(
              zhCN: '$hostName发起了$meetingType',
              zhTW: '$hostName發起了$meetingType',
              en: '$hostName started a $meetingType',
            );
    }

    if (type == 'meeting_invite') {
      final inviterName =
          (data['inviter_name'] ?? _systemOtherParty()).toString();
      final title =
          _shortenMeetingTitle(data['title']?.toString().trim() ?? '');
      final isVoice = (data['meeting_type'] ?? 'video').toString() == 'voice';
      final meetingType = _meetingTypeLabel(isVoice);
      if (title.isNotEmpty) {
        return _systemMessageText(
          zhCN: '$inviterName 邀请您加入$meetingType：$title',
          zhTW: '$inviterName 邀請您加入$meetingType：$title',
          en: '$inviterName invited you to join the $meetingType: $title',
        );
      }
      return _systemMessageText(
        zhCN: '$inviterName 邀请您加入$meetingType',
        zhTW: '$inviterName 邀請您加入$meetingType',
        en: '$inviterName invited you to join the $meetingType',
      );
    }

    if (type == 'meeting_ended') {
      final title =
          _shortenMeetingTitle(data['title']?.toString().trim() ?? '');
      final isVoice = (data['meeting_type'] ?? 'video').toString() == 'voice';
      final meetingType = _meetingTypeLabel(isVoice);
      final reason = (data['end_reason'] ?? '').toString().trim();
      final base = _systemMessageText(
        zhCN: '$meetingType已结束',
        zhTW: '$meetingType已結束',
        en: 'The $meetingType has ended',
      );
      if (title.isNotEmpty) {
        return '$base：$title';
      }
      if (reason.isNotEmpty && reason != 'host_end') {
        return '$base（$reason）';
      }
      return base;
    }

    if (type == 'meeting_title_updated') {
      final operatorName =
          (data['operator_name'] ?? _systemOtherParty()).toString();
      final title =
          _shortenMeetingTitle(data['title']?.toString().trim() ?? '');
      if (title.isNotEmpty) {
        return _systemMessageText(
          zhCN: '$operatorName 更新了群会议名称：$title',
          zhTW: '$operatorName 更新了群會議名稱：$title',
          en: '$operatorName updated the group meeting title: $title',
        );
      }
      return _systemMessageText(
        zhCN: '$operatorName 更新了群会议名称',
        zhTW: '$operatorName 更新了群會議名稱',
        en: '$operatorName updated the group meeting title',
      );
    }
  } catch (_) {
    // Ignore and try plain-text server system messages below.
  }

  return _resolvePlainSystemMessageText(rawText);
}

String _shortenMeetingTitle(String text, {int maxLen = 18}) {
  final value = text.trim();
  if (value.isEmpty || value.length <= maxLen) return value;
  return '${value.substring(0, maxLen)}...';
}

String resolveServerPreviewText(String rawText, {String? currentUserId}) {
  final value = rawText.trim();
  if (value.isEmpty) {
    return value;
  }

  if (value.startsWith('{') && value.endsWith('}')) {
    return resolveSystemMessageText(value, currentUserId: currentUserId);
  }

  return _resolvePlainSystemMessageText(value);
}

bool looksLikeServerSystemPreviewText(String rawText) {
  final text = rawText.trim();
  if (text.isEmpty) {
    return false;
  }
  if (_serverSystemEventText(text) != null) {
    return true;
  }
  if (_legacyEnglishMeetingEventText(text) != null) {
    return true;
  }
  if (text.startsWith('{') && text.endsWith('}')) {
    return true;
  }
  if (<String>{
    '你撤回了一条消息',
    '有人撤回了一条消息',
    '消息已撤回',
    '红包已过期',
    '转账已过期',
    '已拒收',
    '已退款',
  }.contains(text)) {
    return true;
  }

  return RegExp(r'^.+?\s*领取了红包$').hasMatch(text) ||
      RegExp(r'^.+?\s*已收款$').hasMatch(text) ||
      RegExp(r'^.+?刚刚把.+?添加到通讯录，现在可以开始聊天了$').hasMatch(text) ||
      RegExp(r'^.+?\s*创建了(群聊|频道)$').hasMatch(text) ||
      RegExp(r'^.+?\s+邀请\s+.+?\s+加入了群组$').hasMatch(text) ||
      RegExp(r'^.+?\s+邀请\s+\d+\s+位成员加入了群组$').hasMatch(text) ||
      RegExp(r'^.+?\s+已被\s+.+?\s+禁言\s+.+$').hasMatch(text) ||
      RegExp(r'^.+?\s+已被\s+.+?\s+解除禁言$').hasMatch(text) ||
      RegExp(r'^.+?发起了(语音群会议|视频群会议)(：.+)?$').hasMatch(text) ||
      RegExp(r'^.+?\s*邀请[您你]加入(语音群会议|视频群会议)(：.+)?$').hasMatch(text) ||
      RegExp(r'^(语音群会议|视频群会议)已结束([：:].+|（.+）)?$').hasMatch(text) ||
      RegExp(r'^.+?\s*更新了群会议名称(：.+)?$').hasMatch(text);
}

String _resolvePlainSystemMessageText(String rawText) {
  final text = rawText.trim();
  if (text.isEmpty) {
    return _systemMessageText(
      zhCN: '[系统消息]',
      zhTW: '[系統訊息]',
      en: '[System message]',
    );
  }

  final eventText = _serverSystemEventText(text);
  if (eventText != null) {
    return eventText;
  }
  final legacyEnglishMeetingText = _legacyEnglishMeetingEventText(text);
  if (legacyEnglishMeetingText != null) {
    return legacyEnglishMeetingText;
  }

  switch (text) {
    case '你撤回了一条消息':
      return _systemMessageText(
        zhCN: '你撤回了一条消息',
        zhTW: '你撤回了一條訊息',
        en: 'You revoked a message',
      );
    case '有人撤回了一条消息':
      return _systemMessageText(
        zhCN: '有人撤回了一条消息',
        zhTW: '有人撤回了一條訊息',
        en: 'Someone revoked a message',
      );
    case '消息已撤回':
      return _systemMessageText(
        zhCN: '消息已撤回',
        zhTW: '訊息已撤回',
        en: 'Message revoked',
      );
    case '红包已过期':
      return _systemMessageText(
        zhCN: '红包已过期',
        zhTW: '紅包已過期',
        en: 'Red packet expired',
      );
    case '转账已过期':
      return _systemMessageText(
        zhCN: '转账已过期',
        zhTW: '轉帳已過期',
        en: 'Transfer expired',
      );
    case '已拒收':
      return _systemMessageText(
        zhCN: '已拒收',
        zhTW: '已拒收',
        en: 'Declined',
      );
    case '已退款':
      return _systemMessageText(
        zhCN: '已退款',
        zhTW: '已退款',
        en: 'Refunded',
      );
  }

  final redPacketClaimed = RegExp(r'^(.+?)\s*领取了红包$').firstMatch(text);
  if (redPacketClaimed != null) {
    final name = redPacketClaimed.group(1)!.trim();
    return _systemMessageText(
      zhCN: '$name 领取了红包',
      zhTW: '$name 領取了紅包',
      en: '$name claimed the red packet',
    );
  }

  final transferAccepted = RegExp(r'^(.+?)\s*已收款$').firstMatch(text);
  if (transferAccepted != null) {
    final name = transferAccepted.group(1)!.trim();
    return _systemMessageText(
      zhCN: '$name 已收款',
      zhTW: '$name 已收款',
      en: '$name received the transfer',
    );
  }

  final contactAdded = RegExp(
    r'^(.+?)刚刚把(.+?)添加到通讯录，现在可以开始聊天了$',
  ).firstMatch(text);
  if (contactAdded != null) {
    final adder = contactAdded.group(1)!.trim();
    final target = contactAdded.group(2)!.trim();
    return _systemMessageText(
      zhCN: '$adder刚刚把$target添加到通讯录，现在可以开始聊天了',
      zhTW: '$adder剛剛把$target加入通訊錄，現在可以開始聊天了',
      en: '$adder just added $target to contacts. You can start chatting now.',
    );
  }

  final createdChat = RegExp(r'^(.+?)\s*创建了(群聊|频道)$').firstMatch(text);
  if (createdChat != null) {
    final name = createdChat.group(1)!.trim();
    final chatType = createdChat.group(2) == '频道'
        ? _systemMessageText(zhCN: '频道', zhTW: '頻道', en: 'channel')
        : _systemMessageText(zhCN: '群聊', zhTW: '群聊', en: 'group');
    return _systemMessageText(
      zhCN: '$name 创建了$chatType',
      zhTW: '$name 建立了$chatType',
      en: '$name created the $chatType',
    );
  }

  final invitedOne = RegExp(r'^(.+?)\s+邀请\s+(.+?)\s+加入了群组$').firstMatch(text);
  if (invitedOne != null) {
    final inviter = invitedOne.group(1)!.trim();
    final target = invitedOne.group(2)!.trim();
    return _systemMessageText(
      zhCN: '$inviter 邀请 $target 加入了群组',
      zhTW: '$inviter 邀請 $target 加入了群組',
      en: '$inviter invited $target to the group',
    );
  }

  final invitedMany = RegExp(
    r'^(.+?)\s+邀请\s+(\d+)\s+位成员加入了群组$',
  ).firstMatch(text);
  if (invitedMany != null) {
    final inviter = invitedMany.group(1)!.trim();
    final count = invitedMany.group(2)!.trim();
    return _systemMessageText(
      zhCN: '$inviter 邀请 $count 位成员加入了群组',
      zhTW: '$inviter 邀請 $count 位成員加入了群組',
      en: '$inviter invited $count members to the group',
    );
  }

  final muted = RegExp(r'^(.+?)\s+已被\s+(.+?)\s+禁言\s+(.+)$').firstMatch(text);
  if (muted != null) {
    final target = muted.group(1)!.trim();
    final operator = muted.group(2)!.trim();
    final duration = _localizeMuteDuration(muted.group(3)!.trim());
    return _systemMessageText(
      zhCN: '$target 已被 $operator 禁言 ${muted.group(3)!.trim()}',
      zhTW: '$target 已被 $operator 禁言 ${muted.group(3)!.trim()}',
      en: '$target was muted by $operator for $duration',
    );
  }

  final unmuted = RegExp(r'^(.+?)\s+已被\s+(.+?)\s+解除禁言$').firstMatch(text);
  if (unmuted != null) {
    final target = unmuted.group(1)!.trim();
    final operator = unmuted.group(2)!.trim();
    return _systemMessageText(
      zhCN: '$target 已被 $operator 解除禁言',
      zhTW: '$target 已被 $operator 解除禁言',
      en: '$target was unmuted by $operator',
    );
  }

  final meetingStarted = RegExp(
    r'^(.+?)发起了(语音群会议|视频群会议)(：(.+))?$',
  ).firstMatch(text);
  if (meetingStarted != null) {
    final host = meetingStarted.group(1)!.trim();
    final meetingType =
        _meetingTypeLabelFromCn(meetingStarted.group(2)!.trim());
    final title = meetingStarted.group(4)?.trim();
    return title != null && title.isNotEmpty
        ? _systemMessageText(
            zhCN: '$host发起了${meetingStarted.group(2)!.trim()}：$title',
            zhTW: '$host發起了${meetingStarted.group(2)!.trim()}：$title',
            en: '$host started a $meetingType: $title',
          )
        : _systemMessageText(
            zhCN: '$host发起了${meetingStarted.group(2)!.trim()}',
            zhTW: '$host發起了${meetingStarted.group(2)!.trim()}',
            en: '$host started a $meetingType',
          );
  }

  final meetingInvite = RegExp(
    r'^(.+?)\s*邀请([您你])加入(语音群会议|视频群会议)(：(.+))?$',
  ).firstMatch(text);
  if (meetingInvite != null) {
    final inviter = meetingInvite.group(1)!.trim();
    final meetingType = _meetingTypeLabelFromCn(meetingInvite.group(3)!.trim());
    final title = meetingInvite.group(5)?.trim();
    return title != null && title.isNotEmpty
        ? _systemMessageText(
            zhCN:
                '$inviter 邀请${meetingInvite.group(2)}加入${meetingInvite.group(3)}：$title',
            zhTW:
                '$inviter 邀請${meetingInvite.group(2)}加入${meetingInvite.group(3)}：$title',
            en: '$inviter invited you to join the $meetingType: $title',
          )
        : _systemMessageText(
            zhCN:
                '$inviter 邀请${meetingInvite.group(2)}加入${meetingInvite.group(3)}',
            zhTW:
                '$inviter 邀請${meetingInvite.group(2)}加入${meetingInvite.group(3)}',
            en: '$inviter invited you to join the $meetingType',
          );
  }

  final meetingEnded = RegExp(
    r'^(语音群会议|视频群会议)已结束(?:：(.+)|（(.+)）)?$',
  ).firstMatch(text);
  if (meetingEnded != null) {
    final meetingType = _meetingTypeLabelFromCn(meetingEnded.group(1)!.trim());
    final title = meetingEnded.group(2)?.trim();
    final reason = meetingEnded.group(3)?.trim();
    if (title != null && title.isNotEmpty) {
      return _systemMessageText(
        zhCN: '${meetingEnded.group(1)}已结束：$title',
        zhTW: '${meetingEnded.group(1)}已結束：$title',
        en: 'The $meetingType has ended: $title',
      );
    }
    if (reason != null && reason.isNotEmpty) {
      return _systemMessageText(
        zhCN: '${meetingEnded.group(1)}已结束（$reason）',
        zhTW: '${meetingEnded.group(1)}已結束（$reason）',
        en: 'The $meetingType has ended ($reason)',
      );
    }
    return _systemMessageText(
      zhCN: '${meetingEnded.group(1)}已结束',
      zhTW: '${meetingEnded.group(1)}已結束',
      en: 'The $meetingType has ended',
    );
  }

  final meetingRenamed = RegExp(
    r'^(.+?)\s*更新了群会议名称(?:：(.+))?$',
  ).firstMatch(text);
  if (meetingRenamed != null) {
    final operator = meetingRenamed.group(1)!.trim();
    final title = meetingRenamed.group(2)?.trim();
    return title != null && title.isNotEmpty
        ? _systemMessageText(
            zhCN: '$operator 更新了群会议名称：$title',
            zhTW: '$operator 更新了群會議名稱：$title',
            en: '$operator updated the group meeting title: $title',
          )
        : _systemMessageText(
            zhCN: '$operator 更新了群会议名称',
            zhTW: '$operator 更新了群會議名稱',
            en: '$operator updated the group meeting title',
          );
  }

  return text;
}

String? _legacyEnglishMeetingEventText(String text) {
  final value = text.trim();
  final meetingEnded = RegExp(
    r'^(?:the\s+)?(?:voice|video)\s+group\s+meeting\s+(?:has\s+)?ended(?:\s*[:(]\s*([^)]+)\)?)?$',
    caseSensitive: false,
  ).firstMatch(value);
  if (meetingEnded != null) {
    final reason = (meetingEnded.group(1) ?? '').trim();
    final base = _systemMessageText(
      zhCN: '会议已经结束',
      zhTW: '會議已經結束',
      en: 'Meeting ended',
    );
    if (reason.isEmpty || reason == 'host_end') {
      return base;
    }
    return _systemMessageText(
      zhCN: '$base（$reason）',
      zhTW: '$base（$reason）',
      en: '$base ($reason)',
    );
  }

  return null;
}

String? _serverSystemEventText(String text) {
  switch (text) {
    case 'meeting_started':
      return _systemMessageText(
        zhCN: '会议已开始',
        zhTW: '會議已開始',
        en: 'Meeting started',
      );
    case 'meeting_invite':
      return _systemMessageText(
        zhCN: '收到会议邀请',
        zhTW: '收到會議邀請',
        en: 'Meeting invitation',
      );
    case 'meeting_ended':
      return _systemMessageText(
        zhCN: '会议已经结束',
        zhTW: '會議已經結束',
        en: 'Meeting ended',
      );
    case 'meeting_title_updated':
      return _systemMessageText(
        zhCN: '会议名称已更新',
        zhTW: '會議名稱已更新',
        en: 'Meeting title updated',
      );
    case 'meeting_member_joined':
      return _systemMessageText(
        zhCN: '有人加入了会议',
        zhTW: '有人加入了會議',
        en: 'Someone joined the meeting',
      );
    case 'meeting_member_left':
      return _systemMessageText(
        zhCN: '有人离开了会议',
        zhTW: '有人離開了會議',
        en: 'Someone left the meeting',
      );
    default:
      return null;
  }
}

String _localizeMuteDuration(String rawDuration) {
  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.zhCN:
      return rawDuration;
    case AppLanguage.zhTW:
      return rawDuration.replaceAll('小时', '小時').replaceAll('分钟', '分鐘');
    case AppLanguage.en:
      if (rawDuration == '永久') {
        return 'permanently';
      }
      final dayMatch = RegExp(r'^(\d+)\s*天$').firstMatch(rawDuration);
      if (dayMatch != null) {
        final count = int.parse(dayMatch.group(1)!);
        return count == 1 ? '1 day' : '$count days';
      }
      final hourMatch = RegExp(r'^(\d+)\s*(小时|小時)$').firstMatch(rawDuration);
      if (hourMatch != null) {
        final count = int.parse(hourMatch.group(1)!);
        return count == 1 ? '1 hour' : '$count hours';
      }
      final minuteMatch = RegExp(r'^(\d+)\s*(分钟|分鐘)$').firstMatch(rawDuration);
      if (minuteMatch != null) {
        final count = int.parse(minuteMatch.group(1)!);
        return count == 1 ? '1 minute' : '$count minutes';
      }
      return rawDuration;
  }
}

String _meetingTypeLabelFromCn(String rawType) {
  final isVoice = rawType.contains('语音') || rawType.contains('語音');
  return _meetingTypeLabel(isVoice);
}
