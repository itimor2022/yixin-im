import 'dart:async';
import 'dart:math' as math;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_io/io.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/services/api/chat_service.dart' as chat_api;
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/meeting_service.dart';
import '../../../core/services/meeting_session_service.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../chat/providers/chat_provider.dart';
import '../../../shared/widgets/avatar_widget.dart';

class MeetingPage extends ConsumerStatefulWidget {
  final String meetingId;
  final String? chatId;
  final String? chatName;

  const MeetingPage({
    super.key,
    required this.meetingId,
    this.chatId,
    this.chatName,
  });

  @override
  ConsumerState<MeetingPage> createState() => _MeetingPageState();
}

class _MeetingPageState extends ConsumerState<MeetingPage> {
  MeetingDetail? _detail;
  bool _isLoading = true;
  bool _isActioning = false;
  bool _isEndingMeeting = false;
  String? _error;
  final List<String> _wsHandlerIds = [];
  late final WebSocketService _wsService;
  late final MeetingService _meetingService;
  late final String _currentUserId;

  RtcEngine? _rtcEngine;
  RtcEngineEventHandler? _rtcEventHandler;
  final Set<int> _remoteUids = <int>{};
  String _rtcChannelName = '';
  String _rtcMeetingType = 'video';
  bool _rtcConnecting = false;
  bool _rtcJoined = false;
  bool _joiningRtc = false;
  bool _audioMuted = false;
  bool _videoMuted = false;
  bool _allowRtcAutoReconnect = false;
  bool _tearingDownRtc = false;
  int _rtcReconnectAttempts = 0;
  Timer? _rtcReconnectTimer;
  String? _rtcStatusHint;
  bool _audioMutedByHost = false;
  bool _videoMutedByHost = false;
  final Map<int, String> _uidNameMap = <int, String>{};
  final PageController _videoGridPageController = PageController();
  int _videoGridPageIndex = 0;
  bool _reviewingJoinRequest = false;
  final List<Map<String, dynamic>> _pendingJoinRequests = [];

  @override
  void initState() {
    super.initState();
    _wsService = ref.read(webSocketServiceProvider.notifier);
    _meetingService = ref.read(meetingServiceProvider);
    _currentUserId = ref.read(authServiceProvider).user?.uuid ?? '';
    _bindMeetingWsEvents();
    _loadMeetingDetail();
  }

  @override
  void dispose() {
    final session = ref.read(meetingSessionProvider);
    if (session.meetingId == widget.meetingId && !session.isMinimized) {
      ref.read(meetingSessionProvider.notifier).clear();
    }
    for (final id in _wsHandlerIds) {
      _wsService.unregisterHandler(id);
    }
    _wsHandlerIds.clear();
    _rtcReconnectTimer?.cancel();
    _rtcReconnectTimer = null;
    _videoGridPageController.dispose();
    unawaited(_teardownRtc());
    super.dispose();
  }

  void _bindMeetingWsEvents() {
    _wsHandlerIds.add(
      _wsService.registerHandler(
          WSMessageType.meetingInvite, _onMeetingWsEvent),
    );
    _wsHandlerIds.add(
      _wsService.registerHandler(
        WSMessageType.meetingMemberJoined,
        _onMeetingWsEvent,
      ),
    );
    _wsHandlerIds.add(
      _wsService.registerHandler(
          WSMessageType.meetingMemberLeft, _onMeetingWsEvent),
    );
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.meetingEnded, _onMeetingWsEvent),
    );
    _wsHandlerIds.add(
      _wsService.registerHandler(
          WSMessageType.meetingMemberMuted, _onMeetingWsEvent),
    );
    _wsHandlerIds.add(
      _wsService.registerHandler(
          WSMessageType.meetingMemberKicked, _onMeetingWsEvent),
    );
    _wsHandlerIds.add(
      _wsService.registerHandler(
          WSMessageType.meetingHostChanged, _onMeetingWsEvent),
    );
    _wsHandlerIds.add(
      _wsService.registerHandler(
          WSMessageType.meetingTitleUpdated, _onMeetingWsEvent),
    );
    _wsHandlerIds.add(
      _wsService.registerHandler(
          WSMessageType.meetingJoinRequest, _onMeetingWsEvent),
    );
    _wsHandlerIds.add(
      _wsService.registerHandler(
          WSMessageType.meetingJoinRequestReviewed, _onMeetingWsEvent),
    );
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.reconnected, _onWsReconnected),
    );
  }

  void _onMeetingWsEvent(dynamic event) {
    final type = _extractEventType(event);
    final payload = _extractPayload(event);
    final meetingId = payload['meeting_id']?.toString() ?? '';
    if (meetingId != widget.meetingId) {
      return;
    }
    if (type == WSMessageType.meetingJoinRequest) {
      _enqueueMeetingJoinRequest(payload);
      return;
    }
    if (type == WSMessageType.meetingJoinRequestReviewed) {
      _handleJoinRequestReviewed(payload);
      return;
    }
    if (type == WSMessageType.meetingMemberKicked) {
      final currentUserId = _currentUserId;
      final kickedUserId = payload['target_user_id']?.toString() ??
          payload['user_id']?.toString() ??
          '';
      if (currentUserId.isNotEmpty &&
          (kickedUserId.isEmpty || kickedUserId == currentUserId)) {
        _handleSelfKickedEvent();
      } else {
        _loadMeetingDetail(silent: true);
      }
      return;
    }
    if (type == WSMessageType.meetingMemberMuted) {
      _applySelfMuteStatus(payload);
    }
    if (type == WSMessageType.meetingHostChanged) {
      final currentUserId = _currentUserId;
      final targetUserId = payload['target_user_id']?.toString() ?? '';
      if (currentUserId.isNotEmpty &&
          currentUserId == targetUserId &&
          mounted) {
        setState(() {
          _audioMutedByHost = false;
          _videoMutedByHost = false;
        });
      }
    }
    _loadMeetingDetail(silent: true);
  }

  void _onWsReconnected(dynamic _) {
    _loadMeetingDetail(silent: true);
  }

  void _enqueueMeetingJoinRequest(Map<String, dynamic> payload) {
    if (!mounted || !_isCurrentUserHost()) return;
    _pendingJoinRequests.add(payload);
    unawaited(_processJoinRequestQueue());
  }

  Future<void> _processJoinRequestQueue() async {
    if (!mounted || _reviewingJoinRequest || !_isCurrentUserHost()) return;
    while (
        mounted && !_reviewingJoinRequest && _pendingJoinRequests.isNotEmpty) {
      _reviewingJoinRequest = true;
      final payload = _pendingJoinRequests.removeAt(0);
      final requestUserId = payload['request_user_id']?.toString() ?? '';
      if (requestUserId.isEmpty) {
        _reviewingJoinRequest = false;
        continue;
      }
      final requestName =
          payload['request_name']?.toString().trim().isNotEmpty == true
              ? payload['request_name'].toString()
              : requestUserId;

      final approve = await showDialog<bool?>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('入会申请'),
            content: Text('$requestName 申请加入会议，是否同意？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('稍后处理'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('拒绝'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('同意'),
              ),
            ],
          );
        },
      );

      _reviewingJoinRequest = false;
      if (!mounted || approve == null) {
        continue;
      }

      final resp = await _meetingService.reviewJoinRequest(
        meetingId: widget.meetingId,
        targetUserId: requestUserId,
        approve: approve,
      );
      if (!mounted) return;
      if (!resp.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _friendlyMeetingError(resp.message, fallback: '处理申请失败'),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(approve ? '已同意入会申请' : '已拒绝入会申请')),
        );
      }
      await _loadMeetingDetail(silent: true);
    }
  }

  Future<void> _handleMeetingJoinRequest(Map<String, dynamic> payload) async {
    _enqueueMeetingJoinRequest(payload);
  }

  Future<void> _handleJoinRequestReviewed(Map<String, dynamic> payload) async {
    if (!mounted) return;
    final targetUserId = payload['target_user_id']?.toString() ??
        payload['request_user_id']?.toString() ??
        '';
    if (_currentUserId.isEmpty ||
        targetUserId.isEmpty ||
        targetUserId != _currentUserId) {
      return;
    }

    final approved = payload['approved'] == true;
    if (!approved) {
      final reason = payload['reason']?.toString().trim() ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason.isNotEmpty ? reason : '主持人已拒绝你的入会申请'),
        ),
      );
      await _loadMeetingDetail(silent: true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('主持人已同意，正在加入会议')),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await _loadMeetingDetail(silent: true);
  }

  Map<String, dynamic> _extractPayload(dynamic raw) {
    if (raw is! Map) return {};
    final map = Map<String, dynamic>.from(raw);
    final data = map['data'];
    if (data is Map) {
      return Map<String, dynamic>.from(data);
    }
    return map;
  }

  String _extractEventType(dynamic raw) {
    if (raw is! Map) return '';
    final map = Map<String, dynamic>.from(raw);
    return map['type']?.toString() ?? '';
  }

  void _handleSelfKickedEvent() {
    ref.read(meetingSessionProvider.notifier).clear();
    _allowRtcAutoReconnect = false;
    _rtcReconnectTimer?.cancel();
    _rtcReconnectTimer = null;
    _rtcStatusHint = '你已被主持人移出会议';
    unawaited(_teardownRtc());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('你已被主持人移出会议')));
    Future<void>.delayed(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      final nav = Navigator.of(context);
      if (nav.canPop()) {
        nav.pop();
      } else {
        await _loadMeetingDetail(silent: true);
      }
    });
  }

  void _applySelfMuteStatus(Map<String, dynamic> payload) {
    final currentUserId = _currentUserId;
    final targetUserId = payload['target_user_id']?.toString() ?? '';
    if (currentUserId.isEmpty || targetUserId != currentUserId) {
      return;
    }
    final nextAudio = payload['muted_audio'] == true;
    final nextVideo = payload['muted_video'] == true;
    if (!mounted) return;
    setState(() {
      _audioMutedByHost = nextAudio;
      _videoMutedByHost = nextVideo;
      _audioMuted = nextAudio;
      if (_rtcMeetingType == 'video') {
        _videoMuted = nextVideo;
      }
    });
    final engine = _rtcEngine;
    if (engine != null && _rtcJoined) {
      unawaited(engine.muteLocalAudioStream(nextAudio));
      if (_rtcMeetingType == 'video') {
        unawaited(engine.muteLocalVideoStream(nextVideo));
      }
    }
  }

  Future<void> _loadMeetingDetail({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    final response = await _meetingService.getMeetingDetail(widget.meetingId);

    if (!mounted) return;
    if (!response.isSuccess || response.data == null) {
      if (silent) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = _friendlyMeetingError(response.message, fallback: '加载会议失败');
      });
      return;
    }

    final nextDetail = response.data!;
    final me = _findMyParticipant(nextDetail);
    _rebuildUidNameMap(nextDetail.participants);
    _applyMyServerMuteState(me);
    setState(() {
      _detail = nextDetail;
      _isLoading = false;
      _error = null;
    });
    ref.read(meetingSessionProvider.notifier).syncFromDetail(
          nextDetail,
          chatId: widget.chatId ?? nextDetail.chatId ?? '',
          chatName: widget.chatName ?? '',
          isJoined: me?.status == 'joined',
          isHost: me?.role == 'host',
        );
    await _syncRtcByDetail(nextDetail);
  }

  MeetingParticipant? _findMyParticipant(MeetingDetail detail) {
    final currentUserId = _currentUserId;
    for (final p in detail.participants) {
      if (p.userId == currentUserId) return p;
    }
    return null;
  }

  void _rebuildUidNameMap(List<MeetingParticipant> participants) {
    _uidNameMap.clear();
    for (final p in participants) {
      if (p.agoraUid > 0) {
        final name = p.userName.isNotEmpty ? p.userName : p.userId;
        _uidNameMap[p.agoraUid] = name;
      }
    }
  }

  void _applyMyServerMuteState(MeetingParticipant? me) {
    if (me == null) {
      _audioMutedByHost = false;
      _videoMutedByHost = false;
      return;
    }

    _audioMutedByHost = me.mutedAudio;
    _videoMutedByHost = me.mutedVideo;
    if (me.mutedAudio) {
      _audioMuted = true;
    }
    if (_rtcMeetingType == 'video' && me.mutedVideo) {
      _videoMuted = true;
    }

    final engine = _rtcEngine;
    if (engine != null && _rtcJoined) {
      if (me.mutedAudio) {
        unawaited(engine.muteLocalAudioStream(true));
      }
      if (_rtcMeetingType == 'video' && me.mutedVideo) {
        unawaited(engine.muteLocalVideoStream(true));
      }
    }
  }

  Future<void> _syncRtcByDetail(MeetingDetail detail) async {
    final me = _findMyParticipant(detail);
    final shouldJoinRtc = detail.status == 'active' && me?.status == 'joined';

    if (!shouldJoinRtc) {
      _allowRtcAutoReconnect = false;
      _rtcReconnectTimer?.cancel();
      _rtcReconnectTimer = null;
      _rtcStatusHint = null;
      if (_rtcJoined || _rtcConnecting || _joiningRtc) {
        await _teardownRtc();
      }
      return;
    }

    _allowRtcAutoReconnect = true;
    if (_rtcJoined || _rtcConnecting || _joiningRtc) {
      return;
    }
    await _joinRtcByToken();
  }

  Future<void> _joinMeeting() async {
    if (_isActioning) return;
    setState(() => _isActioning = true);

    final response = await _meetingService.joinMeeting(widget.meetingId);
    if (!mounted) return;
    setState(() => _isActioning = false);

    if (!response.isSuccess || response.data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyMeetingError(response.message, fallback: '加入会议失败'),
          ),
        ),
      );
      return;
    }

    if (response.data!.approvalRequired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已提交申请，等待主持人确认')),
      );
      await _loadMeetingDetail(silent: true);
      return;
    }

    final joined = await _joinRtc(response.data!);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(joined ? '已加入会议' : '已加入会议（RTC 连接中）')),
    );
    await _loadMeetingDetail(silent: true);
  }

  Future<void> _leaveMeeting() async {
    if (_isActioning) return;
    setState(() => _isActioning = true);

    _allowRtcAutoReconnect = false;
    _rtcReconnectTimer?.cancel();
    _rtcReconnectTimer = null;
    await _teardownRtc();

    final response = await _meetingService.leaveMeeting(widget.meetingId);
    if (!mounted) return;
    setState(() => _isActioning = false);

    if (!response.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyMeetingError(response.message, fallback: '离开会议失败'),
          ),
        ),
      );
      return;
    }

    ref.read(meetingSessionProvider.notifier).clear();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('已离开会议')));
    await _loadMeetingDetail(silent: true);
  }

  Future<void> _endMeeting() async {
    if (_isActioning) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('结束会议'),
          content: const Text('确认结束当前会议吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('结束'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    setState(() => _isActioning = true);
    final response = await _meetingService.endMeeting(widget.meetingId);
    if (!mounted) return;
    setState(() => _isActioning = false);

    if (!response.isSuccess) {
      if ((response.message ?? '').contains('请求已取消')) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
        final retryResponse =
            await _meetingService.endMeeting(widget.meetingId);
        if (!mounted) return;
        if (retryResponse.isSuccess) {
          _applyMeetingEndedLocally(
              retryResponse.data?['end_reason']?.toString());
          ref.read(meetingSessionProvider.notifier).clear();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('会议已结束')));
          await Future<void>.delayed(const Duration(milliseconds: 600));
          if (mounted) {
            await _loadMeetingDetail(silent: true);
          }
          return;
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyMeetingError(response.message, fallback: '结束会议失败'),
          ),
        ),
      );
      return;
    }

    _applyMeetingEndedLocally(response.data?['end_reason']?.toString());
    ref.read(meetingSessionProvider.notifier).clear();
    _allowRtcAutoReconnect = false;
    _rtcReconnectTimer?.cancel();
    _rtcReconnectTimer = null;
    await _teardownRtc();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('会议已结束')));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      await _loadMeetingDetail(silent: true);
    }
  }

  void _applyMeetingEndedLocally(String? endReason) {
    final detail = _detail;
    if (detail == null) return;
    final now = DateTime.now();
    setState(() {
      _detail = MeetingDetail(
        meetingId: detail.meetingId,
        chatId: detail.chatId,
        title: detail.title,
        meetingType: detail.meetingType,
        status: 'ended',
        channelName: detail.channelName,
        maxParticipants: detail.maxParticipants,
        startTime: detail.startTime,
        endTime: now,
        duration: detail.duration,
        endReason: (endReason ?? detail.endReason).trim(),
        participants: detail.participants,
      );
      _isLoading = false;
      _error = null;
      _isEndingMeeting = true;
    });
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _isEndingMeeting = false;
    });
  }

  Future<void> _inviteMembers() async {
    if (_isActioning) return;
    final meetingDetail = _detail;
    final chatId = widget.chatId?.trim().isNotEmpty == true
        ? widget.chatId!.trim()
        : (meetingDetail?.chatId?.trim() ?? '');
    if (chatId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前会议未绑定群聊，无法从成员列表邀请')),
      );
      return;
    }

    List<chat_api.ChatMember> members;
    try {
      members = await ref.read(chatMembersProvider(chatId).future);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('加载群成员失败，请稍后重试')));
      return;
    }
    if (!mounted) return;

    final existed = <String>{
      for (final p
          in meetingDetail?.participants ?? const <MeetingParticipant>[])
        p.userId,
    };
    final candidates = members
        .where((m) => m.userId.isNotEmpty)
        .where((m) => m.userId != _currentUserId)
        .where((m) => !existed.contains(m.userId))
        .toList();

    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('暂无可邀请成员（群成员已全部在会议中）')),
      );
      return;
    }

    final invitees = await _showInviteMembersPickerCompact(candidates);
    if (!mounted || invitees == null || invitees.isEmpty) return;

    setState(() => _isActioning = true);
    final response = await _meetingService.inviteMembers(
      meetingId: widget.meetingId,
      inviteeUserIds: invitees,
    );
    if (!mounted) return;
    setState(() => _isActioning = false);

    if (!response.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyMeetingError(response.message, fallback: '邀请失败'),
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('邀请已发送')));
    await _loadMeetingDetail(silent: true);
  }

  Future<List<String>?> _showInviteMembersPickerCompact(
    List<chat_api.ChatMember> members,
  ) async {
    final selectedIds = <String>{};
    final searchController = TextEditingController();
    String keyword = '';

    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final query = keyword.trim().toLowerCase();
            final filtered = query.isEmpty
                ? members
                : members.where((m) {
                    final displayName = m.displayName.toLowerCase();
                    final username = m.username.toLowerCase();
                    final userId = m.userId.toLowerCase();
                    return displayName.contains(query) ||
                        username.contains(query) ||
                        userId.contains(query);
                  }).toList();

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
              child: Container(
                height: MediaQuery.of(ctx).size.height * 0.82,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111827) : Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '邀请群成员',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '从群成员里选择需要加入的人',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: '搜索昵称 / 用户名 / UUID',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1F2937)
                            : const Color(0xFFF6F8FC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) {
                        setSheetState(() {
                          keyword = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildSheetTag(
                          text: '可选 ${members.length} 人',
                          isDark: isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildSheetTag(
                          text: '已选 ${selectedIds.length} 人',
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                '未找到可邀请成员',
                                style: TextStyle(
                                  color:
                                      isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, index) {
                                final member = filtered[index];
                                final checked = selectedIds.contains(
                                  member.userId,
                                );
                                return InkWell(
                                  onTap: () {
                                    setSheetState(() {
                                      if (checked) {
                                        selectedIds.remove(member.userId);
                                      } else {
                                        selectedIds.add(member.userId);
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: checked
                                          ? (isDark
                                              ? const Color(0xFF1E2A45)
                                              : const Color(0xFFEAF1FF))
                                          : (isDark
                                              ? const Color(0xFF1F2937)
                                              : const Color(0xFFF7F9FC)),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: checked
                                            ? const Color(0xFF2E5BFF)
                                            : (isDark
                                                ? const Color(0xFF334155)
                                                : const Color(0xFFE2E8F0)),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        AvatarWidget(
                                          avatar: member.avatar,
                                          name: member.displayName,
                                          size: 34,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                member.displayName.isNotEmpty
                                                    ? member.displayName
                                                    : member.userId,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                member.username.isNotEmpty
                                                    ? member.username
                                                    : member.userId,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark
                                                      ? Colors.white70
                                                      : Colors.black54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Checkbox(
                                          value: checked,
                                          onChanged: (value) {
                                            setSheetState(() {
                                              if (value == true) {
                                                selectedIds.add(member.userId);
                                              } else {
                                                selectedIds.remove(
                                                  member.userId,
                                                );
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(null),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(<String>[]),
                            child: const Text('跳过'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(sheetContext).pop(
                              selectedIds.toList(),
                            ),
                            child: Text('邀请(${selectedIds.length})'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
    return result;
  }

  Future<void> _joinRtcByToken() async {
    if (!mounted || _tearingDownRtc) return;
    final tokenResp = await _meetingService.getMeetingToken(widget.meetingId);
    if (!mounted) return;
    if (!tokenResp.isSuccess || tokenResp.data == null) {
      debugPrint('[Meeting] get token failed: ${tokenResp.message}');
      _rtcConnecting = false;
      _rtcStatusHint = _friendlyMeetingError(
        tokenResp.message,
        fallback: '音视频凭证获取失败，正在重试',
      );
      if (mounted) setState(() {});
      _scheduleRtcReconnect();
      return;
    }
    final normalized = _normalizeJoinData(tokenResp.data!);
    if (normalized == null) {
      _rtcConnecting = false;
      _rtcStatusHint = '音视频参数缺失，请稍后重试';
      if (mounted) setState(() {});
      _scheduleRtcReconnect();
      return;
    }
    await _joinRtc(normalized);
  }

  Future<bool> _joinRtc(MeetingJoinResult data) async {
    if (_joiningRtc || _tearingDownRtc || !mounted) return false;
    final normalized = _normalizeJoinData(data);
    if (normalized == null) {
      _rtcConnecting = false;
      _rtcStatusHint = '音视频参数缺失，请稍后重试';
      if (mounted) setState(() {});
      return false;
    }
    _joiningRtc = true;
    _allowRtcAutoReconnect = true;
    _rtcMeetingType = normalized.meetingType;
    _rtcConnecting = true;
    if (mounted) setState(() {});

    try {
      final allow = await _requestRtcPermissions(normalized.meetingType);
      if (!allow) {
        _rtcConnecting = false;
        _rtcStatusHint = '缺少麦克风/摄像头权限，无法加入音视频';
        if (mounted) setState(() {});
        return false;
      }

      await _ensureRtcEngine(
        appId: normalized.appId,
        meetingType: normalized.meetingType,
      );
      final engine = _rtcEngine;
      if (engine == null || _tearingDownRtc || !mounted) {
        _rtcConnecting = false;
        _rtcStatusHint = '音视频引擎初始化失败';
        if (mounted) setState(() {});
        return false;
      }

      _rtcChannelName = normalized.channelName;
      final isVideo = normalized.meetingType == 'video';
      _videoMuted = !isVideo;

      await engine.enableAudio();
      await engine.enableLocalAudio(true);
      await engine.setAudioProfile(
        profile: AudioProfileType.audioProfileSpeechStandard,
        scenario: AudioScenarioType.audioScenarioMeeting,
      );
      await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

      if (isVideo) {
        await engine.enableVideo();
        await engine.startPreview();
      } else {
        await engine.disableVideo();
      }

      await engine.joinChannel(
        token: normalized.token,
        channelId: normalized.channelName,
        uid: normalized.agoraUid > 0
            ? normalized.agoraUid
            : _resolveLocalAgoraUid(),
        options: ChannelMediaOptions(
          autoSubscribeAudio: true,
          autoSubscribeVideo: isVideo,
          publishMicrophoneTrack: !_audioMuted,
          publishCameraTrack: isVideo && !_videoMuted,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      _rtcReconnectAttempts = 0;
      _rtcStatusHint = null;
      await WakelockPlus.enable();
      return true;
    } catch (e) {
      debugPrint('[Meeting] join rtc error: $e');
      _rtcConnecting = false;
      _rtcStatusHint = '音视频连接失败，正在重试';
      if (mounted) {
        setState(() {});
      }
      Future<void>.delayed(const Duration(milliseconds: 100), () {
        if (mounted) _scheduleRtcReconnect();
      });
      return false;
    } finally {
      _joiningRtc = false;
    }
  }

  Future<void> _ensureRtcEngine({
    required String appId,
    required String meetingType,
  }) async {
    final current = _rtcEngine;
    if (current != null) return;
    final normalizedAppId = appId.trim();
    if (normalizedAppId.isEmpty) {
      throw StateError('Agora appId is empty');
    }

    final engine = createAgoraRtcEngine();
    await engine.initialize(
      RtcEngineContext(
        appId: normalizedAppId,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    final eventHandler = RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        if (!mounted) return;
        _rtcJoined = true;
        _rtcConnecting = false;
        _rtcReconnectAttempts = 0;
        _rtcReconnectTimer?.cancel();
        _rtcReconnectTimer = null;
        _rtcChannelName = connection.channelId ?? _rtcChannelName;
        setState(() {});
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        if (!mounted) return;
        _remoteUids.add(remoteUid);
        setState(() {});
      },
      onUserOffline: (connection, remoteUid, reason) {
        if (!mounted) return;
        _remoteUids.remove(remoteUid);
        setState(() {});
      },
      onLeaveChannel: (connection, stats) {
        if (!mounted) return;
        _rtcJoined = false;
        _rtcConnecting = false;
        _remoteUids.clear();
        setState(() {});
      },
      onError: (code, msg) {
        debugPrint('[Meeting] Agora error: $code - $msg');
      },
      onConnectionStateChanged: (connection, state, reason) {
        if (!mounted) return;
        if (state == ConnectionStateType.connectionStateConnected) {
          _rtcConnecting = false;
          _rtcJoined = true;
          _rtcReconnectAttempts = 0;
          _rtcReconnectTimer?.cancel();
          _rtcReconnectTimer = null;
          _rtcStatusHint = null;
          setState(() {});
          return;
        }
        if (!_allowRtcAutoReconnect || _tearingDownRtc) {
          return;
        }
        if (state == ConnectionStateType.connectionStateDisconnected ||
            state == ConnectionStateType.connectionStateFailed) {
          _rtcStatusHint = '网络波动，音视频重连中';
          _scheduleRtcReconnect();
          setState(() {});
        }
      },
      onTokenPrivilegeWillExpire: (connection, token) {
        if (!_allowRtcAutoReconnect || _tearingDownRtc) return;
        unawaited(_renewRtcToken());
      },
      onRequestToken: (connection) {
        if (!_allowRtcAutoReconnect || _tearingDownRtc) return;
        unawaited(_renewRtcToken());
      },
    );
    _rtcEventHandler = eventHandler;
    engine.registerEventHandler(eventHandler);

    await engine.enableAudio();
    await engine.enableLocalAudio(true);
    await engine.setAudioProfile(
      profile: AudioProfileType.audioProfileSpeechStandard,
      scenario: AudioScenarioType.audioScenarioMeeting,
    );
    await engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      await engine.setDefaultAudioRouteToSpeakerphone(true);
    }
    if (meetingType == 'video') {
      await engine.enableVideo();
    } else {
      await engine.disableVideo();
    }

    _rtcEngine = engine;
  }

  void _scheduleRtcReconnect() {
    if (!_allowRtcAutoReconnect || _tearingDownRtc || _joiningRtc) return;
    if (_rtcReconnectTimer != null) return;

    _rtcReconnectAttempts++;
    final delaySeconds = _rtcReconnectAttempts <= 1
        ? 1
        : (_rtcReconnectAttempts <= 3
            ? 2
            : (_rtcReconnectAttempts <= 6 ? 4 : 8));
    _rtcStatusHint = '网络波动，$delaySeconds 秒后第 $_rtcReconnectAttempts 次重连';
    if (mounted) {
      setState(() {});
    }
    _rtcReconnectTimer = Timer(Duration(seconds: delaySeconds), () async {
      _rtcReconnectTimer = null;
      if (!_allowRtcAutoReconnect || _tearingDownRtc) return;
      await _reconnectRtcChannel();
    });
  }

  Future<void> _reconnectRtcChannel() async {
    if (!_allowRtcAutoReconnect || _tearingDownRtc) return;
    if (_joiningRtc) return;
    try {
      await _teardownRtc(disableAutoReconnect: false);
      await _joinRtcByToken();
    } catch (e) {
      debugPrint('[Meeting] reconnect rtc error: $e');
      _scheduleRtcReconnect();
    }
  }

  Future<void> _renewRtcToken() async {
    if (!_allowRtcAutoReconnect || _tearingDownRtc) return;
    final engine = _rtcEngine;
    if (engine == null) return;
    final tokenResp = await _meetingService.getMeetingToken(widget.meetingId);
    if (!mounted) return;
    if (!tokenResp.isSuccess || tokenResp.data == null) {
      debugPrint('[Meeting] renew token failed: ${tokenResp.message}');
      _rtcStatusHint = '音视频凭证续期失败，正在重试';
      if (mounted) setState(() {});
      _scheduleRtcReconnect();
      return;
    }
    try {
      await engine.renewToken(tokenResp.data!.token);
      _rtcStatusHint = null;
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('[Meeting] renew token error: $e');
      _rtcStatusHint = '音视频凭证续期失败，正在重试';
      if (mounted) setState(() {});
      _scheduleRtcReconnect();
    }
  }

  Future<bool> _requestRtcPermissions(String meetingType) async {
    if (kIsWeb) return true;
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;
    if (meetingType == 'video') {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) return false;
    }
    return true;
  }

  Future<void> _teardownRtc({bool disableAutoReconnect = true}) async {
    if (_tearingDownRtc) return;
    _tearingDownRtc = true;
    if (disableAutoReconnect) {
      _allowRtcAutoReconnect = false;
      _rtcReconnectTimer?.cancel();
      _rtcReconnectTimer = null;
      _rtcStatusHint = null;
    }
    final engine = _rtcEngine;
    if (engine == null) {
      _tearingDownRtc = false;
      return;
    }

    try {
      final eventHandler = _rtcEventHandler;
      if (eventHandler != null) {
        engine.unregisterEventHandler(eventHandler);
      }
      await engine.leaveChannel();
      await engine.stopPreview();
      await engine.release();
    } catch (e) {
      debugPrint('[Meeting] teardown rtc error: $e');
    } finally {
      _rtcEngine = null;
      _rtcEventHandler = null;
      _rtcChannelName = '';
      _rtcJoined = false;
      _rtcConnecting = false;
      _joiningRtc = false;
      _remoteUids.clear();
      _tearingDownRtc = false;
      if (mounted) {
        setState(() {});
      }
      await WakelockPlus.disable();
    }
  }

  Future<void> _toggleMuteAudio() async {
    final engine = _rtcEngine;
    if (engine == null || !_rtcJoined) return;
    final next = !_audioMuted;
    if (!next && _audioMutedByHost && !_isCurrentUserHost()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(content: Text('你已被主持人静音，暂时不能自行解除')),
        );
      }
      return;
    }
    try {
      await engine.muteLocalAudioStream(next);
      if (!mounted) return;
      setState(() => _audioMuted = next);
    } catch (e) {
      debugPrint('[Meeting] mute audio error: $e');
    }
  }

  Future<void> _toggleMuteVideo() async {
    if (_rtcMeetingType != 'video') return;
    final engine = _rtcEngine;
    if (engine == null || !_rtcJoined) return;
    final next = !_videoMuted;
    if (!next && _videoMutedByHost && !_isCurrentUserHost()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(content: Text('你已被主持人关闭视频，暂时不能自行开启')),
        );
      }
      return;
    }
    try {
      await engine.muteLocalVideoStream(next);
      if (!next) {
        await engine.enableVideo();
        await engine.startPreview();
      }
      if (!mounted) return;
      setState(() => _videoMuted = next);
    } catch (e) {
      debugPrint('[Meeting] mute video error: $e');
    }
  }

  Future<void> _switchCamera() async {
    final engine = _rtcEngine;
    if (engine == null || !_rtcJoined || _rtcMeetingType != 'video') return;
    try {
      await engine.switchCamera();
    } catch (e) {
      debugPrint('[Meeting] switch camera error: $e');
    }
  }

  Future<void> _toggleMemberMute(
    MeetingParticipant member, {
    bool? mutedAudio,
    bool? mutedVideo,
  }) async {
    final resp = await _meetingService.muteMember(
      meetingId: widget.meetingId,
      targetUserId: member.userId,
      mutedAudio: mutedAudio,
      mutedVideo: mutedVideo,
    );
    if (!mounted) return;
    if (!resp.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyMeetingError(resp.message, fallback: '操作失败')),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('成员状态已更新')));
    await _loadMeetingDetail(silent: true);
  }

  Future<void> _kickMember(MeetingParticipant member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('移出成员'),
          content: Text(
            '确认移出 ${member.userName.isNotEmpty ? member.userName : member.userId} 吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('移出'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final resp = await _meetingService.kickMember(
      meetingId: widget.meetingId,
      targetUserId: member.userId,
    );
    if (!mounted) return;
    if (!resp.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyMeetingError(resp.message, fallback: '移出失败')),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('成员已移出')));
    await _loadMeetingDetail(silent: true);
  }

  Future<void> _transferHost(MeetingParticipant member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('转移主持人'),
          content: Text(
            '确认将主持人转移给 ${member.userName.isNotEmpty ? member.userName : member.userId} 吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final resp = await _meetingService.transferHost(
      meetingId: widget.meetingId,
      targetUserId: member.userId,
    );
    if (!mounted) return;
    if (!resp.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyMeetingError(resp.message, fallback: '转移失败')),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('主持人已转移')));
    await _loadMeetingDetail(silent: true);
  }

  Future<void> _editMeetingTitle() async {
    final detail = _detail;
    if (detail == null || !_isCurrentUserHost()) return;

    final controller = TextEditingController(text: detail.title);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('编辑会议名称'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: '会议名称',
              hintText: '请输入会议名称',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      controller.dispose();
      return;
    }

    final nextTitle = controller.text.trim();
    controller.dispose();
    if (nextTitle.isEmpty || nextTitle == detail.title.trim()) return;

    setState(() => _isActioning = true);
    final resp = await _meetingService.updateMeetingTitle(
      meetingId: widget.meetingId,
      title: nextTitle,
    );
    if (!mounted) return;
    setState(() => _isActioning = false);

    if (!resp.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _friendlyMeetingError(resp.message, fallback: '修改会议名称失败'),
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('会议名称已更新')),
    );
    await _loadMeetingDetail(silent: true);
  }

  Future<void> _minimizeMeeting() async {
    if (_isActioning || _detail?.status != 'active') return;
    ref.read(meetingSessionProvider.notifier).setMinimized(true);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final title = detail?.title.isNotEmpty == true
        ? detail!.title
        : (widget.chatName?.isNotEmpty == true ? widget.chatName! : '群会议');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final meetingStatus =
        detail == null ? '' : _meetingStatusText(detail.status);

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0B1020) : const Color(0xFFF4F7FF),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (meetingStatus.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Center(
                child: _buildPill(
                  icon: Icons.info_outline,
                  text: meetingStatus,
                  color: isDark
                      ? const Color(0xFF1E2A45)
                      : const Color(0xFFEAF0FF),
                  textColor: isDark
                      ? const Color(0xFFB7C8FF)
                      : const Color(0xFF3557C4),
                ),
              ),
            ),
          IconButton(
            tooltip: '刷新',
            onPressed: _isLoading ? null : _loadMeetingDetail,
            icon: const Icon(Icons.refresh),
          ),
          if (detail != null && detail.status == 'active')
            IconButton(
              tooltip: '悬浮',
              onPressed: _isActioning ? null : _minimizeMeeting,
              icon: const Icon(Icons.picture_in_picture_alt_rounded),
            ),
        ],
      ),
      body: _buildBody(context, detail),
    );
  }

  Widget _buildBody(BuildContext context, MeetingDetail? detail) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadMeetingDetail,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (detail == null) {
      return const Center(child: Text('会议不存在'));
    }

    final myParticipant = _findMyParticipant(detail);
    final currentUserId = _currentUserId;
    final isHost = myParticipant?.role == 'host';
    final isJoined = myParticipant?.status == 'joined';
    final isActive = detail.status == 'active';
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isWideLayout = screenWidth >= 1080;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF4F7FF), Color(0xFFF8FAFF), Color(0xFFFFFFFF)],
        ),
      ),
      child: RefreshIndicator(
        onRefresh: () => _loadMeetingDetail(silent: true),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            isWideLayout ? 24 : 14,
            isWideLayout ? 20 : 14,
            isWideLayout ? 24 : 14,
            20,
          ),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isWideLayout ? 1340 : 860,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildOverviewCardCompact(detail),
                    const SizedBox(height: 14),
                    _buildActionBarCompact(
                      isActive: isActive,
                      isJoined: isJoined,
                      isHost: isHost,
                    ),
                    const SizedBox(height: 14),
                    if (isWideLayout)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: _buildRtcPanel(
                              isJoined: isJoined,
                              isActive: isActive,
                              isHost: isHost,
                              detail: detail,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            flex: 4,
                            child: _buildParticipantsPanel(
                              detail: detail,
                              isHost: isHost,
                              isActive: isActive,
                              currentUserId: currentUserId,
                            ),
                          ),
                        ],
                      )
                    else ...[
                      _buildRtcPanel(
                        isJoined: isJoined,
                        isActive: isActive,
                        isHost: isHost,
                        detail: detail,
                      ),
                      const SizedBox(height: 14),
                      _buildParticipantsPanel(
                        detail: detail,
                        isHost: isHost,
                        isActive: isActive,
                        currentUserId: currentUserId,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRtcPanel({
    required bool isJoined,
    required bool isActive,
    required bool isHost,
    required MeetingDetail detail,
  }) {
    if (!isActive) {
      return const SizedBox.shrink();
    }

    final isVideoMeeting = detail.meetingType == 'video';
    final remoteUids = _remoteUids.toList()..sort();
    final compact = MediaQuery.sizeOf(context).width < 720;

    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 16 : 18),
        border: Border.all(color: const Color(0xFFE6EBF8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x121F2A4D),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.graphic_eq_rounded,
                size: 20,
                color: Color(0xFF2E5BFF),
              ),
              const SizedBox(width: 8),
              Text(
                isVideoMeeting ? '群视频' : '群音频',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              _buildPill(
                icon: _rtcJoined
                    ? Icons.link
                    : (_rtcConnecting ? Icons.sync : Icons.link_off),
                text: _rtcJoined ? '已连接' : (_rtcConnecting ? '连接中' : '未连接'),
                color: _rtcJoined
                    ? const Color(0xFF12B886)
                    : const Color(0xFF7D8FB3),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!isJoined)
            Text(
              '你尚未加入会议，加入后将自动连接音视频。',
              style: TextStyle(
                color: Colors.blueGrey.shade700,
                fontSize: compact ? 12 : 13,
              ),
            )
          else if (_rtcConnecting)
            Text(
              '正在连接音视频...',
              style: TextStyle(
                color: Colors.blueGrey.shade700,
                fontSize: compact ? 12 : 13,
              ),
            )
          else if (!_rtcJoined)
            Text(
              '音视频未连接，将自动重试。',
              style: TextStyle(
                color: Colors.blueGrey.shade700,
                fontSize: compact ? 12 : 13,
              ),
            ),
          if (_rtcStatusHint != null && _rtcStatusHint!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFD9A8)),
              ),
              child: Text(
                _rtcStatusHint!,
                style: const TextStyle(
                  color: Color(0xFF9A5200),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (!isHost &&
              (_audioMutedByHost ||
                  (_rtcMeetingType == 'video' && _videoMutedByHost))) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFCCC7)),
              ),
              child: Text(
                _audioMutedByHost &&
                        (_rtcMeetingType != 'video' || !_videoMutedByHost)
                    ? '主持人已将你音频静音'
                    : (_videoMutedByHost && !_audioMutedByHost
                        ? '主持人已关闭你的视频'
                        : '主持人已限制你的音视频'),
                style: const TextStyle(
                  color: Color(0xFFCF1322),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (isJoined && isVideoMeeting) ...[
            const SizedBox(height: 12),
            _buildVideoGrid(remoteUids),
          ],
          if (isJoined) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _rtcJoined ? _toggleMuteAudio : null,
                  icon: Icon(
                    _audioMuted ? Icons.mic_off_outlined : Icons.mic_none,
                  ),
                  label: Text(_audioMuted ? '取消静音' : '静音'),
                ),
                if (isVideoMeeting)
                  FilledButton.tonalIcon(
                    onPressed: _rtcJoined ? _toggleMuteVideo : null,
                    icon: Icon(
                      _videoMuted
                          ? Icons.videocam_off_outlined
                          : Icons.videocam_outlined,
                    ),
                    label: Text(_videoMuted ? '开启视频' : '关闭视频'),
                  ),
                if (isVideoMeeting)
                  OutlinedButton.icon(
                    onPressed: _rtcJoined ? _switchCamera : null,
                    icon: const Icon(Icons.flip_camera_android_outlined),
                    label: const Text('切换摄像头'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoGrid(List<int> remoteUids) {
    final tiles = <Widget>[
      _buildLocalTile(),
      ...remoteUids.map(_buildRemoteTile),
    ];
    final screenWidth = MediaQuery.sizeOf(context).width;
    final crossAxisCount = screenWidth >= 900 ? 3 : 2;
    final pageSize = crossAxisCount * 3;
    final pageCount = (tiles.length / pageSize).ceil();
    final maxIndex = pageCount > 0 ? pageCount - 1 : 0;
    if (_videoGridPageIndex > maxIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _videoGridPageIndex = maxIndex;
        if (_videoGridPageController.hasClients) {
          _videoGridPageController.jumpToPage(maxIndex);
        }
        setState(() {});
      });
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final spacing = width < 600 ? 6.0 : 8.0;
        final tileWidth =
            (width - spacing * (crossAxisCount - 1)) / crossAxisCount;
        final tileHeight = tileWidth * (crossAxisCount == 2 ? 0.84 : 0.76);
        final gridHeight = tileHeight * 3 + spacing * 2;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF8FAFF), Color(0xFFF0F4FF)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDDE6FB)),
          ),
          child: Column(
            children: [
              SizedBox(
                height: gridHeight,
                child: PageView.builder(
                  controller: _videoGridPageController,
                  itemCount: math.max(pageCount, 1),
                  onPageChanged: (index) {
                    if (!mounted) return;
                    setState(() => _videoGridPageIndex = index);
                  },
                  itemBuilder: (context, pageIndex) {
                    final start = pageIndex * pageSize;
                    final end = math.min(start + pageSize, tiles.length);
                    final pageTiles = start < end
                        ? tiles.sublist(start, end)
                        : const <Widget>[];
                    return GridView.builder(
                      itemCount: pageSize,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                        childAspectRatio: tileWidth / tileHeight,
                      ),
                      itemBuilder: (context, index) {
                        if (index < pageTiles.length) {
                          return pageTiles[index];
                        }
                        return _buildEmptyVideoTile();
                      },
                    );
                  },
                ),
              ),
              if (pageCount > 1) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List<Widget>.generate(pageCount, (index) {
                    final selected = index == _videoGridPageIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: selected ? 16 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF2E5BFF)
                            : const Color(0xFFB7C7F2),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyVideoTile() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFFEFF3FE),
        border: Border.all(color: const Color(0xFFD6E0FA)),
      ),
      child: const Center(
        child: Icon(
          Icons.grid_view_rounded,
          color: Color(0xFFA4B3DD),
          size: 20,
        ),
      ),
    );
  }

  Widget _buildLocalTile() {
    final engine = _rtcEngine;
    final showVideo = _rtcJoined && !_videoMuted && _rtcMeetingType == 'video';
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C2745), Color(0xFF0E1528)],
        ),
        border: Border.all(color: const Color(0x33FFFFFF)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: showVideo && engine != null
                ? AgoraVideoView(
                    controller: VideoViewController(
                      rtcEngine: engine,
                      canvas: const VideoCanvas(uid: 0),
                    ),
                  )
                : const Center(
                    child: Icon(Icons.person, color: Colors.white54, size: 44),
                  ),
          ),
          Positioned(left: 8, bottom: 8, child: _nameTag('本人')),
        ],
      ),
    );
  }

  Widget _buildRemoteTile(int uid) {
    final engine = _rtcEngine;
    final canRender = engine != null && _rtcChannelName.isNotEmpty;
    final label = _uidNameMap[uid] ?? 'UID $uid';
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1C2745), Color(0xFF0E1528)],
        ),
        border: Border.all(color: const Color(0x33FFFFFF)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: canRender
                ? AgoraVideoView(
                    controller: VideoViewController.remote(
                      rtcEngine: engine,
                      canvas: VideoCanvas(uid: uid),
                      connection: RtcConnection(channelId: _rtcChannelName),
                    ),
                  )
                : const Center(
                    child: Icon(
                      Icons.person_2,
                      color: Colors.white54,
                      size: 44,
                    ),
                  ),
          ),
          Positioned(left: 8, bottom: 8, child: _nameTag(label)),
        ],
      ),
    );
  }

  Widget _nameTag(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xA30D172A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  String _meetingStatusText(String status) {
    switch (status) {
      case 'active':
        return '进行中';
      case 'ended':
        return '已结束';
      default:
        return status;
    }
  }

  bool _isCurrentUserHost() {
    final detail = _detail;
    if (detail == null) return false;
    final me = _findMyParticipant(detail);
    return me?.role == 'host';
  }

  int _resolveLocalAgoraUid() {
    final detail = _detail;
    if (detail == null) return 0;
    final me = _findMyParticipant(detail);
    if (me == null || me.agoraUid <= 0) return 0;
    return me.agoraUid;
  }

  MeetingJoinResult? _normalizeJoinData(MeetingJoinResult data) {
    final appId = data.appId.trim();
    final channelName = data.channelName.trim().isNotEmpty
        ? data.channelName.trim()
        : (_detail?.channelName.trim() ?? '');
    if (appId.isEmpty || channelName.isEmpty) {
      return null;
    }
    final rawMeetingType = data.meetingType.trim().toLowerCase();
    final fallbackMeetingType = _detail?.meetingType.trim().toLowerCase() ?? '';
    final meetingType = rawMeetingType == 'voice' ||
            (rawMeetingType.isEmpty && fallbackMeetingType == 'voice')
        ? 'voice'
        : 'video';
    return MeetingJoinResult(
      meetingId: data.meetingId,
      channelName: channelName,
      meetingType: meetingType,
      token: data.token.trim(),
      appId: appId,
      agoraUid: data.agoraUid,
    );
  }

  String _friendlyMeetingError(String? raw, {required String fallback}) {
    final message = (raw ?? '').trim();
    if (message.isEmpty) return fallback;
    final normalized = message.toLowerCase();
    if (normalized.contains('meeting is full') ||
        normalized.contains('meeting capacity reached') ||
        message.contains('会议人数已满')) {
      return '会议人数已满';
    }
    if (normalized.contains('approval required') ||
        normalized.contains('join approval') ||
        message.contains('等待')) {
      return '已提交申请，等待主持人确认';
    }
    return message;
  }

  String _participantStatusText(MeetingParticipant p) {
    final base = switch (p.status) {
      'joined' => '已加入',
      'invited' => '已邀请',
      'left' => '已离开',
      'kicked' => '已移出',
      _ => p.status,
    };

    final tags = <String>[base];
    if (p.mutedAudio) tags.add('音频静音');
    if (p.mutedVideo) tags.add('视频关闭');
    return tags.join(' / ');
  }

  String _compactMeetingTitle(String text, {int maxLen = 16}) {
    final value = text.trim();
    if (value.isEmpty || value.length <= maxLen) return value;
    return '${value.substring(0, maxLen)}...';
  }

  Widget _buildSheetTag({
    required String text,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF4F7FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white70 : const Color(0xFF3557C4),
        ),
      ),
    );
  }

  Widget _buildOverviewCardCompact(MeetingDetail detail) {
    final isHost = _isCurrentUserHost();
    final displayTitle = detail.title.isNotEmpty
        ? _compactMeetingTitle(detail.title, maxLen: 18)
        : '群会议';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E5BFF), Color(0xFF4A7BFF)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x243762FF),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.groups_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (isHost) ...[
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _isActioning ? null : _editMeetingTitle,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              backgroundColor: const Color(0x1FFFFFFF),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('改名'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _buildPill(
                icon: detail.meetingType == 'voice'
                    ? Icons.mic_outlined
                    : Icons.videocam_outlined,
                text: detail.meetingType == 'voice' ? '语音' : '视频',
                color: const Color(0xFFDDE6FF),
                textColor: const Color(0xFF17368A),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildInfoChipCompact('状态', _meetingStatusText(detail.status)),
              _buildInfoChipCompact(
                '成员',
                '${detail.participants.length}/${detail.maxParticipants}',
              ),
              _buildInfoChipCompact(
                'RTC',
                _rtcJoined ? '已连接' : (_rtcConnecting ? '连接中' : '未连接'),
              ),
              if (_remoteUids.isNotEmpty)
                _buildInfoChipCompact('远端', '${_remoteUids.length}'),
              if (detail.endReason.isNotEmpty)
                _buildInfoChipCompact('原因', detail.endReason),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionBarCompact({
    required bool isActive,
    required bool isJoined,
    required bool isHost,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EBF8)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive && !isJoined)
              FilledButton.icon(
                onPressed: _isActioning ? null : _joinMeeting,
                icon: const Icon(Icons.login, size: 16),
                label: const Text('加入'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            if (isActive && isJoined) ...[
              OutlinedButton.icon(
                onPressed: _isActioning ? null : _leaveMeeting,
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('离开'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
            ],
            if (isActive && isHost) ...[
              FilledButton.tonalIcon(
                onPressed: _isActioning ? null : _inviteMembers,
                icon: const Icon(Icons.group_add, size: 16),
                label: const Text('邀请'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE03131),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _isActioning ? null : _endMeeting,
                icon: const Icon(Icons.call_end, size: 16),
                label: const Text('结束'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChipCompact(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0x30FFFFFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x45FFFFFF)),
      ),
      constraints: const BoxConstraints(maxWidth: 220),
      child: Text(
        '$label：$value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildParticipantsPanel({
    required MeetingDetail detail,
    required bool isHost,
    required bool isActive,
    required String currentUserId,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EBF8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x121F2A4D),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '参会成员',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              _buildPill(
                icon: Icons.people_alt_outlined,
                text: '${detail.participants.length}',
                color: const Color(0xFFEEF2FF),
                textColor: const Color(0xFF2E5BFF),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...detail.participants.map(
            (p) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE8EEFF)),
              ),
              child: Row(
                children: [
                  AvatarWidget(
                    avatar: p.userAvatar,
                    name: p.userName,
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.userName.isNotEmpty ? p.userName : p.userId,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _participantStatusText(p),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  isHost &&
                          isActive &&
                          p.userId != currentUserId &&
                          p.status != 'kicked'
                      ? PopupMenuButton<String>(
                          onSelected: (value) async {
                            switch (value) {
                              case 'mute_audio':
                                await _toggleMemberMute(
                                  p,
                                  mutedAudio: !p.mutedAudio,
                                );
                                break;
                              case 'mute_video':
                                await _toggleMemberMute(
                                  p,
                                  mutedVideo: !p.mutedVideo,
                                );
                                break;
                              case 'kick':
                                await _kickMember(p);
                                break;
                              case 'transfer_host':
                                await _transferHost(p);
                                break;
                            }
                          },
                          itemBuilder: (_) {
                            final items = <PopupMenuEntry<String>>[
                              PopupMenuItem<String>(
                                value: 'mute_audio',
                                child: Text(
                                  p.mutedAudio ? '取消音频静音' : '音频静音',
                                ),
                              ),
                            ];
                            if (detail.meetingType == 'video') {
                              items.add(
                                PopupMenuItem<String>(
                                  value: 'mute_video',
                                  child: Text(
                                    p.mutedVideo ? '开启视频' : '关闭视频',
                                  ),
                                ),
                              );
                            }
                            if (p.role != 'host' &&
                                p.status == 'joined' &&
                                p.userId != currentUserId) {
                              items.add(
                                const PopupMenuItem<String>(
                                  value: 'transfer_host',
                                  child: Text('转移主持人'),
                                ),
                              );
                            }
                            if (p.role != 'host' && p.status != 'kicked') {
                              items.add(
                                const PopupMenuItem<String>(
                                  value: 'kick',
                                  child: Text('移出成员'),
                                ),
                              );
                            }
                            return items;
                          },
                          child: const Icon(Icons.more_horiz),
                        )
                      : _buildPill(
                          icon: p.role == 'host' ? Icons.shield : Icons.person,
                          text: p.role == 'host' ? '主持人' : '成员',
                          color: p.role == 'host'
                              ? const Color(0xFFFFF4E5)
                              : const Color(0xFFF1F5F9),
                          textColor: p.role == 'host'
                              ? const Color(0xFF9A5200)
                              : const Color(0xFF475569),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPill({
    required IconData icon,
    required String text,
    required Color color,
    Color? textColor,
  }) {
    final fg = textColor ?? Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: fg,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
