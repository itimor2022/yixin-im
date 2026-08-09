// 文件用途：封装 MeetingSessionState 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 MeetingSessionState 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n/app_localizations.dart';
import 'api/meeting_service.dart';

String _meetingSessionText({
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

// 关键声明：meeting session service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 跨页面保留的会议摘要，仅用于悬浮入口和最小化状态，不持有 RTC 引擎或成员权威列表。
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
    return _meetingSessionText(
      zhCN: '群会议',
      zhTW: '群會議',
      en: 'Group meeting',
    );
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

/// 将服务端会议详情投影为全局最小化会话，完整会议状态仍以 [MeetingDetail] 为准。
class MeetingSessionService extends StateNotifier<MeetingSessionState> {
  MeetingSessionService() : super(const MeetingSessionState());

  // 流程逻辑：`syncFromDetail` 先校验账号、分页或连接状态，再读取远端/本地数据并合并结果；失败只更新错误状态，不覆盖已有可用数据。
  void syncFromDetail(
    MeetingDetail detail, {
    required String chatId,
    required String chatName,
    required bool isJoined,
    required bool isHost,
  }) {
    // 服务端结束状态立即清除同一会议摘要，不能因本地仍最小化而继续展示入口。
    if (detail.status != 'active') {
      if (state.meetingId == detail.meetingId) {
        clear();
      }
      return;
    }

    final keepMinimized =
        state.meetingId == detail.meetingId && state.isMinimized;
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
