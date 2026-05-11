import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/meeting_service.dart';

class MeetingSessionState {
  final String meetingId;
  final String chatId;
  final String chatName;
  final String title;
  final String meetingType;
  final String status;
  final int participantCount;
  final int maxParticipants;
  final bool isJoined;
  final bool isHost;
  final bool isMinimized;
  final DateTime? startTime;

  const MeetingSessionState({
    this.meetingId = '',
    this.chatId = '',
    this.chatName = '',
    this.title = '',
    this.meetingType = 'video',
    this.status = '',
    this.participantCount = 0,
    this.maxParticipants = 0,
    this.isJoined = false,
    this.isHost = false,
    this.isMinimized = false,
    this.startTime,
  });

  bool get hasMeeting => meetingId.isNotEmpty;

  bool get isVisible => hasMeeting && status == 'active' && isMinimized;

  String get displayTitle {
    final meetingTitle = title.trim();
    if (meetingTitle.isNotEmpty) return meetingTitle;
    final groupName = chatName.trim();
    if (groupName.isNotEmpty) return groupName;
    return '群会议';
  }

  MeetingSessionState copyWith({
    String? meetingId,
    String? chatId,
    String? chatName,
    String? title,
    String? meetingType,
    String? status,
    int? participantCount,
    int? maxParticipants,
    bool? isJoined,
    bool? isHost,
    bool? isMinimized,
    DateTime? startTime,
    bool clearStartTime = false,
  }) {
    return MeetingSessionState(
      meetingId: meetingId ?? this.meetingId,
      chatId: chatId ?? this.chatId,
      chatName: chatName ?? this.chatName,
      title: title ?? this.title,
      meetingType: meetingType ?? this.meetingType,
      status: status ?? this.status,
      participantCount: participantCount ?? this.participantCount,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      isJoined: isJoined ?? this.isJoined,
      isHost: isHost ?? this.isHost,
      isMinimized: isMinimized ?? this.isMinimized,
      startTime: clearStartTime ? null : (startTime ?? this.startTime),
    );
  }
}

class MeetingSessionService extends StateNotifier<MeetingSessionState> {
  MeetingSessionService() : super(const MeetingSessionState());

  void syncFromDetail(
    MeetingDetail detail, {
    required String chatId,
    required String chatName,
    required bool isJoined,
    required bool isHost,
  }) {
    if (detail.status != 'active') {
      if (state.meetingId == detail.meetingId) {
        clear();
      }
      return;
    }

    final keepMinimized = state.meetingId == detail.meetingId && state.isMinimized;
    state = state.copyWith(
      meetingId: detail.meetingId,
      chatId: chatId,
      chatName: chatName,
      title: detail.title,
      meetingType: detail.meetingType,
      status: detail.status,
      participantCount: detail.participants.length,
      maxParticipants: detail.maxParticipants,
      isJoined: isJoined,
      isHost: isHost,
      isMinimized: keepMinimized,
      startTime: detail.startTime,
    );
  }

  void updateTitle(String meetingId, String title) {
    if (state.meetingId != meetingId) return;
    state = state.copyWith(title: title.trim());
  }

  void updateStatus(String meetingId, String status) {
    if (state.meetingId != meetingId) return;
    state = state.copyWith(status: status.trim());
    if (status != 'active') {
      state = state.copyWith(isMinimized: false);
    }
  }

  void setMinimized(bool value) {
    if (state.meetingId.isEmpty) return;
    state = state.copyWith(isMinimized: value);
  }

  void toggleMinimize() {
    if (state.meetingId.isEmpty) return;
    state = state.copyWith(isMinimized: !state.isMinimized);
  }

  void clear() {
    state = const MeetingSessionState();
  }
}

final meetingSessionProvider =
    StateNotifierProvider<MeetingSessionService, MeetingSessionState>((ref) {
  return MeetingSessionService();
});
