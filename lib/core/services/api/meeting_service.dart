import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

enum MeetingType {
  voice,
  video,
}

class MeetingParticipant {
  final String userId;
  final int agoraUid;
  final String userName;
  final String? userAvatar;
  final String role;
  final String status;
  final bool mutedAudio;
  final bool mutedVideo;
  final DateTime? joinedAt;
  final DateTime? leftAt;

  MeetingParticipant({
    required this.userId,
    required this.agoraUid,
    required this.userName,
    this.userAvatar,
    required this.role,
    required this.status,
    required this.mutedAudio,
    required this.mutedVideo,
    this.joinedAt,
    this.leftAt,
  });

  factory MeetingParticipant.fromJson(Map<String, dynamic> json) {
    final rawAvatar = json['user_avatar']?.toString();
    final normalizedAvatar = (rawAvatar != null && rawAvatar.isNotEmpty)
        ? ApiConfig.getMediaUrl(rawAvatar)
        : null;
    return MeetingParticipant(
      userId: json['user_id']?.toString() ?? '',
      agoraUid: json['agora_uid'] is int
          ? json['agora_uid'] as int
          : int.tryParse(json['agora_uid']?.toString() ?? '') ?? 0,
      userName: json['user_name']?.toString() ?? '',
      userAvatar: normalizedAvatar,
      role: json['role']?.toString() ?? 'member',
      status: json['status']?.toString() ?? 'invited',
      mutedAudio: json['muted_audio'] == true,
      mutedVideo: json['muted_video'] == true,
      joinedAt: json['joined_at'] != null
          ? DateTime.tryParse(json['joined_at'].toString())?.toLocal()
          : null,
      leftAt: json['left_at'] != null
          ? DateTime.tryParse(json['left_at'].toString())?.toLocal()
          : null,
    );
  }
}

class MeetingDetail {
  final String meetingId;
  final String? chatId;
  final String title;
  final String meetingType;
  final String status;
  final String channelName;
  final int maxParticipants;
  final DateTime? startTime;
  final DateTime? endTime;
  final int duration;
  final String endReason;
  final List<MeetingParticipant> participants;

  MeetingDetail({
    required this.meetingId,
    this.chatId,
    required this.title,
    required this.meetingType,
    required this.status,
    required this.channelName,
    required this.maxParticipants,
    this.startTime,
    this.endTime,
    required this.duration,
    required this.endReason,
    required this.participants,
  });

  factory MeetingDetail.fromJson(Map<String, dynamic> json) {
    final participantList =
        (json['participants'] as List?)?.whereType<Map>().map((item) {
              return MeetingParticipant.fromJson(
                Map<String, dynamic>.from(item),
              );
            }).toList() ??
            const <MeetingParticipant>[];

    return MeetingDetail(
      meetingId: json['meeting_id']?.toString() ?? '',
      chatId: json['chat_id']?.toString(),
      title: json['title']?.toString() ?? '',
      meetingType: json['meeting_type']?.toString() ?? 'video',
      status: json['status']?.toString() ?? 'active',
      channelName: json['channel_name']?.toString() ?? '',
      maxParticipants: json['max_participants'] is int
          ? json['max_participants'] as int
          : int.tryParse(json['max_participants']?.toString() ?? '') ?? 16,
      startTime: json['start_time'] != null
          ? DateTime.tryParse(json['start_time'].toString())?.toLocal()
          : null,
      endTime: json['end_time'] != null
          ? DateTime.tryParse(json['end_time'].toString())?.toLocal()
          : null,
      duration: json['duration'] is int
          ? json['duration'] as int
          : int.tryParse(json['duration']?.toString() ?? '') ?? 0,
      endReason: json['end_reason']?.toString() ?? '',
      participants: participantList,
    );
  }
}

class MeetingCreateResult {
  final String meetingId;
  final String channelName;
  final String meetingType;
  final String? chatId;
  final String title;
  final String token;
  final String appId;
  final int agoraUid;

  MeetingCreateResult({
    required this.meetingId,
    required this.channelName,
    required this.meetingType,
    this.chatId,
    required this.title,
    required this.token,
    required this.appId,
    required this.agoraUid,
  });

  factory MeetingCreateResult.fromJson(Map<String, dynamic> json) {
    return MeetingCreateResult(
      meetingId: json['meeting_id']?.toString() ?? '',
      channelName: json['channel_name']?.toString() ?? '',
      meetingType: json['meeting_type']?.toString() ?? '',
      chatId: json['chat_id']?.toString(),
      title: json['title']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      appId: json['app_id']?.toString() ?? '',
      agoraUid: json['agora_uid'] is int
          ? json['agora_uid'] as int
          : int.tryParse(json['agora_uid']?.toString() ?? '') ?? 0,
    );
  }
}

class MeetingJoinResult {
  final String meetingId;
  final String channelName;
  final String meetingType;
  final String token;
  final String appId;
  final int agoraUid;
  final bool approvalRequired;

  MeetingJoinResult({
    required this.meetingId,
    required this.channelName,
    required this.meetingType,
    required this.token,
    required this.appId,
    required this.agoraUid,
    this.approvalRequired = false,
  });

  factory MeetingJoinResult.fromJson(Map<String, dynamic> json) {
    return MeetingJoinResult(
      meetingId: json['meeting_id']?.toString() ?? '',
      channelName: json['channel_name']?.toString() ?? '',
      meetingType: json['meeting_type']?.toString() ?? 'video',
      token: json['token']?.toString() ?? '',
      appId: json['app_id']?.toString() ?? '',
      agoraUid: json['agora_uid'] is int
          ? json['agora_uid'] as int
          : int.tryParse(json['agora_uid']?.toString() ?? '') ?? 0,
      approvalRequired: json['approval_required'] == true ||
          json['approval_required']?.toString() == '1',
    );
  }
}

class MeetingActiveInfo {
  final bool hasActive;
  final String meetingId;
  final String chatId;
  final String title;
  final String meetingType;
  final String channelName;
  final DateTime? startTime;
  final String hostUserId;
  final String hostName;
  final String? hostAvatar;

  MeetingActiveInfo({
    required this.hasActive,
    required this.meetingId,
    required this.chatId,
    required this.title,
    required this.meetingType,
    required this.channelName,
    this.startTime,
    required this.hostUserId,
    required this.hostName,
    this.hostAvatar,
  });

  factory MeetingActiveInfo.fromJson(Map<String, dynamic> json) {
    final rawAvatar = json['host_avatar']?.toString() ?? '';
    final normalizedAvatar =
        rawAvatar.isEmpty ? null : ApiConfig.getMediaUrl(rawAvatar);
    return MeetingActiveInfo(
      hasActive:
          json['has_active'] == true || json['has_active']?.toString() == '1',
      meetingId: json['meeting_id']?.toString() ?? '',
      chatId: json['chat_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      meetingType: json['meeting_type']?.toString() ?? 'video',
      channelName: json['channel_name']?.toString() ?? '',
      startTime: json['start_time'] != null
          ? DateTime.tryParse(json['start_time'].toString())?.toLocal()
          : null,
      hostUserId: json['host_user_id']?.toString() ?? '',
      hostName: json['host_name']?.toString() ?? '',
      hostAvatar: normalizedAvatar,
    );
  }
}

class MeetingService {
  final ApiClient _api;

  MeetingService(this._api);

  Future<ApiResponse<MeetingCreateResult>> createMeeting({
    required String chatId,
    required MeetingType meetingType,
    String title = '',
    List<String> inviteeUserIds = const [],
    int maxParticipants = 16,
  }) {
    return _api.post(
      '/meeting/create',
      data: {
        'chat_id': chatId,
        'meeting_type': meetingType.name,
        'title': title,
        'invitee_user_ids': inviteeUserIds,
        'max_participants': maxParticipants,
      },
      fromJson: (data) => MeetingCreateResult.fromJson(
        Map<String, dynamic>.from(data as Map),
      ),
    );
  }

  Future<ApiResponse<MeetingJoinResult>> joinMeeting(String meetingId) {
    return _api.post(
      '/meeting/join',
      data: {'meeting_id': meetingId},
      fromJson: (data) => MeetingJoinResult.fromJson(
        Map<String, dynamic>.from(data as Map),
      ),
    );
  }

  Future<ApiResponse<MeetingActiveInfo>> getActiveMeeting(String chatId) {
    return _api.get(
      '/meeting/active',
      queryParameters: {'chat_id': chatId},
      fromJson: (data) => MeetingActiveInfo.fromJson(
        Map<String, dynamic>.from(data as Map),
      ),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> reviewJoinRequest({
    required String meetingId,
    required String targetUserId,
    required bool approve,
    String reason = '',
  }) {
    return _api.post(
      '/meeting/join-request/review',
      data: {
        'meeting_id': meetingId,
        'target_user_id': targetUserId,
        'approve': approve,
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> leaveMeeting(
    String meetingId, {
    String reason = '',
  }) {
    return _api.post(
      '/meeting/leave',
      data: {
        'meeting_id': meetingId,
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> inviteMembers({
    required String meetingId,
    required List<String> inviteeUserIds,
  }) {
    return _api.post(
      '/meeting/invite',
      data: {'meeting_id': meetingId, 'invitee_user_ids': inviteeUserIds},
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> endMeeting(
    String meetingId, {
    String reason = '',
  }) {
    return _api.post(
      '/meeting/end',
      data: {
        'meeting_id': meetingId,
        if (reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> updateMeetingTitle({
    required String meetingId,
    required String title,
  }) {
    return _api.post(
      '/meeting/title',
      data: {
        'meeting_id': meetingId,
        'title': title,
      },
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> muteMember({
    required String meetingId,
    required String targetUserId,
    bool? mutedAudio,
    bool? mutedVideo,
  }) {
    return _api.post(
      '/meeting/member/mute',
      data: {
        'meeting_id': meetingId,
        'target_user_id': targetUserId,
        if (mutedAudio != null) 'muted_audio': mutedAudio,
        if (mutedVideo != null) 'muted_video': mutedVideo,
      },
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> kickMember({
    required String meetingId,
    required String targetUserId,
  }) {
    return _api.post(
      '/meeting/member/kick',
      data: {
        'meeting_id': meetingId,
        'target_user_id': targetUserId,
      },
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> transferHost({
    required String meetingId,
    required String targetUserId,
  }) {
    return _api.post(
      '/meeting/host/transfer',
      data: {
        'meeting_id': meetingId,
        'target_user_id': targetUserId,
      },
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
  }

  Future<ApiResponse<MeetingJoinResult>> getMeetingToken(String meetingId) {
    return _api.get(
      '/meeting/token',
      queryParameters: {'meeting_id': meetingId},
      fromJson: (data) => MeetingJoinResult.fromJson(
        Map<String, dynamic>.from(data as Map),
      ),
    );
  }

  Future<ApiResponse<MeetingDetail>> getMeetingDetail(String meetingId) {
    return _api.get(
      '/meeting/detail',
      queryParameters: {'meeting_id': meetingId},
      fromJson: (data) => MeetingDetail.fromJson(
        Map<String, dynamic>.from(data as Map),
      ),
    );
  }
}

final meetingServiceProvider = Provider<MeetingService>((ref) {
  final api = ref.watch(apiClientProvider);
  return MeetingService(api);
});
