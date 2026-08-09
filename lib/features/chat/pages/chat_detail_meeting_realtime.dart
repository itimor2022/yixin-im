// 文件用途：实现 _ChatDetailMeetingRealtime 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailMeetingRealtime 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail meeting realtime 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMeetingRealtime on _ChatDetailPageState {
  // 流程逻辑：`_loadActiveMeeting` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Future<void> _loadActiveMeeting({bool silent = true}) async {
    if (widget.chatType != ChatType.group || _loadingActiveMeeting) return;
    _loadingActiveMeeting = true;
    try {
      final meetingService = ref.read(meetingServiceProvider);
      final response = await meetingService.getActiveMeeting(widget.chatId);
      if (!mounted) return;
      final info = response.isSuccess && response.data != null
          ? response.data!
          : MeetingActiveInfo(
              hasActive: false,
              meetingId: '',
              chatId: widget.chatId,
              title: '',
              meetingType: 'video',
              channelName: '',
              hostUserId: '',
              hostName: '',
            );
      _updateState(() {
        _activeMeetingInfo = info.hasActive ? info : null;
      });
    } catch (_) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(
              zhCN: '加载群会议状态失败',
              zhTW: '載入群會議狀態失敗',
              en: 'Failed to load group meeting status',
            ),
          ),
        ),
      );
    } finally {
      _loadingActiveMeeting = false;
    }
  }

  Map<String, dynamic> _extractWsPayload(dynamic raw) {
    if (raw is! Map) return {};
    final event = Map<String, dynamic>.from(raw);
    final nested = event['data'];
    if (nested is Map) {
      return Map<String, dynamic>.from(nested);
    }
    return event;
  }

  String _extractWsType(dynamic raw) {
    if (raw is! Map) return '';
    final event = Map<String, dynamic>.from(raw);
    return event['type']?.toString() ?? '';
  }

  void _handleMeetingWsChanged(dynamic raw) {
    if (!mounted || widget.chatType != ChatType.group) return;
    final type = _extractWsType(raw);
    final payload = _extractWsPayload(raw);
    final eventChatId = payload['chat_id']?.toString() ?? '';
    if (eventChatId.isNotEmpty && eventChatId != widget.chatId) return;
    if (type == WSMessageType.meetingStarted) {
      _handleMeetingStartedEvent(payload);
      unawaited(_loadActiveMeeting());
      return;
    }
    if (type == WSMessageType.meetingInvite) {
      _handleMeetingInviteEvent(payload);
      unawaited(_loadActiveMeeting());
      return;
    }
    if (type == WSMessageType.meetingTitleUpdated) {
      unawaited(_loadActiveMeeting());
      return;
    }
    if (type != WSMessageType.meetingEnded) return;
    unawaited(_loadActiveMeeting());
  }

  void _handleMeetingStartedEvent(Map<String, dynamic> payload) {
    // 会议开始会由后端落成系统消息，这里只保留占位，避免前端重复造消息。
  }

  void _handleMeetingInviteEvent(Map<String, dynamic> payload) {
    final meetingId = payload['meeting_id']?.toString() ?? '';
    if (meetingId.isEmpty) return;

    final inviterName = payload['inviter_name']?.toString() ??
        _localizedText(
          zhCN: '群成员',
          zhTW: '群成員',
          en: 'Group Member',
        );
    final inviteKey = '$meetingId:${payload['inviter_id']?.toString() ?? ''}';
    if (_shownMeetingInviteIds.add(inviteKey)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        this._showMeetingInvitePromptCompact(
          meetingId: meetingId,
          inviterName: inviterName,
          title: payload['title']?.toString() ?? widget.chatName,
          meetingType: payload['meeting_type']?.toString() ?? 'video',
        );
      });
    }
  }
}
