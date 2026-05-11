import 'dart:convert';

String resolveSystemMessageText(String rawText, {String? currentUserId}) {
  if (rawText.isEmpty) return '[系统消息]';

  try {
    final data = jsonDecode(rawText) as Map<String, dynamic>;
    final type = data['type'] as String?;

    if (type == 'red_packet_claimed') {
      final claimerName = (data['claimer_name'] ?? '对方').toString();
      return '$claimerName 领取了红包';
    }

    if (type == 'transfer_accepted') {
      final receiverName = (data['receiver_name'] ?? '对方').toString();
      return '$receiverName 已收款';
    }

    if (type == 'contact_added_system_message') {
      final adderId = (data['adder_id'] ?? '').toString();
      final adderName = (data['adder_name'] ?? '对方').toString();
      final targetId = (data['target_id'] ?? '').toString();
      final targetName = (data['target_name'] ?? '对方').toString();

      if (currentUserId != null && currentUserId.isNotEmpty) {
        if (currentUserId == adderId) {
          return '您刚刚把$targetName添加到通讯录，现在可以开始聊天了';
        }
        if (currentUserId == targetId) {
          return '$adderName刚刚把您添加到通讯录，现在可以开始聊天了';
        }
      }

      return '$adderName刚刚把$targetName添加到通讯录，现在可以开始聊天了';
    }

    if (type == 'meeting_started') {
      final hostId = (data['host_user_id'] ?? '').toString();
      final hostName = (data['host_name'] ?? '对方').toString();
      final title = _shortenMeetingTitle(data['title']?.toString().trim() ?? '');
      final meetingType =
          (data['meeting_type'] ?? 'video').toString() == 'voice'
              ? '语音群会议'
              : '视频群会议';
      final prefix = currentUserId != null && currentUserId == hostId
          ? '您发起了'
          : '$hostName发起了';
      if (title.isNotEmpty) {
        return '$prefix$meetingType：$title';
      }
      return '$prefix$meetingType';
    }

    if (type == 'meeting_invite') {
      final inviterName = (data['inviter_name'] ?? '对方').toString();
      final title = _shortenMeetingTitle(data['title']?.toString().trim() ?? '');
      final meetingType =
          (data['meeting_type'] ?? 'video').toString() == 'voice'
              ? '语音群会议'
              : '视频群会议';
      if (title.isNotEmpty) {
        return '$inviterName 邀请您加入$meetingType：$title';
      }
      return '$inviterName 邀请您加入$meetingType';
    }

    if (type == 'meeting_ended') {
      final title = _shortenMeetingTitle(data['title']?.toString().trim() ?? '');
      final meetingType =
          (data['meeting_type'] ?? 'video').toString() == 'voice'
              ? '语音群会议'
              : '视频群会议';
      final reason = (data['end_reason'] ?? '').toString().trim();
      final base = '$meetingType已结束';
      if (title.isNotEmpty) {
        return '$base：$title';
      }
      if (reason.isNotEmpty && reason != 'host_end') {
        return '$base（$reason）';
      }
      return base;
    }

    if (type == 'meeting_title_updated') {
      final operatorName = (data['operator_name'] ?? '对方').toString();
      final title = _shortenMeetingTitle(data['title']?.toString().trim() ?? '');
      if (title.isNotEmpty) {
        return '$operatorName 更新了群会议名称：$title';
      }
      return '$operatorName 更新了群会议名称';
    }
  } catch (_) {
    // 不是 JSON，按普通系统消息文本显示
  }

  return rawText;
}

String _shortenMeetingTitle(String text, {int maxLen = 18}) {
  final value = text.trim();
  if (value.isEmpty || value.length <= maxLen) return value;
  return '${value.substring(0, maxLen)}...';
}
