// 文件用途：实现 MeetingPage 页面及其交互流程，属于群组会议。
// 核心逻辑：维护 MeetingPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:async';
import 'dart:math' as math;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_io/io.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/chat_service.dart' as chat_api;
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/meeting_service.dart';
import '../../../core/services/meeting_session_service.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../chat/providers/chat_provider.dart';
import '../../../shared/widgets/avatar_widget.dart';

String _meetingText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 关键声明：meeting page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
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

/// 会议编排入口：HTTP/WS 维护控制面，Agora/LiveKit 维护媒体面，两者通过会议详情对齐。
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
  lk.Room? _liveKitRoom;
  lk.EventsListener<lk.RoomEvent>? _liveKitListener;
  lk.LocalVideoTrack? _liveKitLocalVideoTrack;
  final Set<String> _remoteLiveKitIdentities = <String>{};
  final Map<String, lk.RemoteVideoTrack> _liveKitRemoteVideoTracks =
      <String, lk.RemoteVideoTrack>{};
  String _rtcChannelName = '';
  String _rtcMeetingType = 'video';
  String _rtcProvider = 'agora';
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
  final Map<String, String> _identityNameMap = <String, String>{};
  final PageController _videoGridPageController = PageController();
  int _videoGridPageIndex = 0;
  bool _reviewingJoinRequest = false;
  final List<Map<String, dynamic>> _pendingJoinRequests = [];

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
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
    // WS 事件只作即时提示；除本机可确定的动作外，最终成员和角色状态仍回源会议详情。
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
            title: Text(
              _meetingText(
                ctx,
                zhCN: '入会申请',
                zhTW: '入會申請',
                en: 'Join Request',
              ),
            ),
            content: Text(
              _meetingText(
                ctx,
                zhCN: '$requestName 申请加入会议，是否同意？',
                zhTW: '$requestName 申請加入會議，是否同意？',
                en: '$requestName wants to join the meeting. Approve?',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text(
                  _meetingText(
                    ctx,
                    zhCN: '稍后处理',
                    zhTW: '稍後處理',
                    en: 'Later',
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(
                  _meetingText(
                    ctx,
                    zhCN: '拒绝',
                    zhTW: '拒絕',
                    en: 'Decline',
                  ),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  _meetingText(
                    ctx,
                    zhCN: '同意',
                    zhTW: '同意',
                    en: 'Approve',
                  ),
                ),
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
              _friendlyMeetingError(
                resp.message,
                fallback: _meetingText(
                  context,
                  zhCN: '处理申请失败',
                  zhTW: '處理申請失敗',
                  en: 'Failed to review the request',
                ),
              ),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approve
                  ? _meetingText(
                      context,
                      zhCN: '已同意入会申请',
                      zhTW: '已同意入會申請',
                      en: 'Join request approved',
                    )
                  : _meetingText(
                      context,
                      zhCN: '已拒绝入会申请',
                      zhTW: '已拒絕入會申請',
                      en: 'Join request rejected',
                    ),
            ),
          ),
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
          content: Text(
            reason.isNotEmpty
                ? reason
                : _meetingText(
                    context,
                    zhCN: '主持人已拒绝你的入会申请',
                    zhTW: '主持人已拒絕你的入會申請',
                    en: 'The host declined your join request',
                  ),
          ),
        ),
      );
      await _loadMeetingDetail(silent: true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _meetingText(
            context,
            zhCN: '主持人已同意，正在加入会议',
            zhTW: '主持人已同意，正在加入會議',
            en: 'The host approved your request. Joining the meeting now.',
          ),
        ),
      ),
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
    _rtcStatusHint = _meetingText(
      context,
      zhCN: '你已被主持人移出会议',
      zhTW: '你已被主持人移出會議',
      en: 'You were removed from the meeting by the host',
    );
    unawaited(_teardownRtc());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          _meetingText(
            context,
            zhCN: '你已被主持人移出会议',
            zhTW: '你已被主持人移出會議',
            en: 'You were removed from the meeting by the host',
          ),
        ),
      ),
    );
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
    if (_rtcProvider == 'livekit' && _rtcJoined) {
      unawaited(
        _liveKitRoom?.localParticipant?.setMicrophoneEnabled(!nextAudio) ??
            Future.value(),
      );
      if (_rtcMeetingType == 'video') {
        unawaited(_setLiveKitCameraEnabled(!nextVideo));
      }
    } else if (engine != null && _rtcJoined) {
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
        _error = _friendlyMeetingError(
          response.message,
          fallback: _meetingText(
            context,
            zhCN: '加载会议失败',
            zhTW: '載入會議失敗',
            en: 'Failed to load meeting',
          ),
        );
      });
      return;
    }

    // 详情是控制面权威快照：先更新成员/权限，再据其 joined 状态决定是否连接 RTC。
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
    _identityNameMap.clear();
    for (final p in participants) {
      final name = p.userName.isNotEmpty ? p.userName : p.userId;
      if (p.userId.isNotEmpty) {
        _identityNameMap[p.userId] = name;
      }
      if (p.agoraUid > 0) {
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
    if (_rtcProvider == 'livekit' && _rtcJoined) {
      if (me.mutedAudio) {
        unawaited(
          _liveKitRoom?.localParticipant?.setMicrophoneEnabled(false) ??
              Future.value(),
        );
      }
      if (_rtcMeetingType == 'video' && me.mutedVideo) {
        unawaited(_setLiveKitCameraEnabled(false));
      }
    } else if (engine != null && _rtcJoined) {
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

    // 服务端未确认 joined 时必须退出媒体房间，持有有效 token 也不能绕过成员状态。
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
            _friendlyMeetingError(
              response.message,
              fallback: _meetingText(
                context,
                zhCN: '加入会议失败',
                zhTW: '加入會議失敗',
                en: 'Failed to join meeting',
              ),
            ),
          ),
        ),
      );
      return;
    }

    if (response.data!.approvalRequired) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _meetingText(
              context,
              zhCN: '已提交申请，等待主持人确认',
              zhTW: '已提交申請，等待主持人確認',
              en: 'Request submitted. Waiting for host approval.',
            ),
          ),
        ),
      );
      await _loadMeetingDetail(silent: true);
      return;
    }

    final joined = await _joinRtc(response.data!);
    if (!mounted) return;
    if (!joined) {
      _allowRtcAutoReconnect = false;
      _rtcReconnectTimer?.cancel();
      _rtcReconnectTimer = null;
      await _teardownRtc();
      await _meetingService.leaveMeeting(widget.meetingId, reason: 'rtc_error');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _meetingText(
              context,
              zhCN: '音视频连接失败，已退出会议',
              zhTW: '音視訊連線失敗，已退出會議',
              en: 'Audio/video connection failed. Left the meeting.',
            ),
          ),
        ),
      );
      await _loadMeetingDetail(silent: true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          joined
              ? _meetingText(
                  context,
                  zhCN: '已加入会议',
                  zhTW: '已加入會議',
                  en: 'Joined the meeting',
                )
              : _meetingText(
                  context,
                  zhCN: '已加入会议（RTC 连接中）',
                  zhTW: '已加入會議（RTC 連線中）',
                  en: 'Joined the meeting (connecting RTC)',
                ),
        ),
      ),
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
            _friendlyMeetingError(
              response.message,
              fallback: _meetingText(
                context,
                zhCN: '离开会议失败',
                zhTW: '離開會議失敗',
                en: 'Failed to leave meeting',
              ),
            ),
          ),
        ),
      );
      return;
    }

    ref.read(meetingSessionProvider.notifier).clear();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          _meetingText(
            context,
            zhCN: '已离开会议',
            zhTW: '已離開會議',
            en: 'Left the meeting',
          ),
        ),
      ),
    );
    await _loadMeetingDetail(silent: true);
  }

  Future<void> _endMeeting() async {
    if (_isActioning) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            _meetingText(
              ctx,
              zhCN: '结束会议',
              zhTW: '結束會議',
              en: 'End Meeting',
            ),
          ),
          content: Text(
            _meetingText(
              ctx,
              zhCN: '确认结束当前会议吗？',
              zhTW: '確認結束目前會議嗎？',
              en: 'End this meeting now?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                _meetingText(
                  ctx,
                  zhCN: '取消',
                  zhTW: '取消',
                  en: 'Cancel',
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                _meetingText(
                  ctx,
                  zhCN: '结束',
                  zhTW: '結束',
                  en: 'End',
                ),
              ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _meetingText(
                  context,
                  zhCN: '会议已结束',
                  zhTW: '會議已結束',
                  en: 'Meeting ended',
                ),
              ),
            ),
          );
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
            _friendlyMeetingError(
              response.message,
              fallback: _meetingText(
                context,
                zhCN: '结束会议失败',
                zhTW: '結束會議失敗',
                en: 'Failed to end meeting',
              ),
            ),
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
    ).showSnackBar(
      SnackBar(
        content: Text(
          _meetingText(
            context,
            zhCN: '会议已结束',
            zhTW: '會議已結束',
            en: 'Meeting ended',
          ),
        ),
      ),
    );
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
        roomName: detail.roomName,
        rtcProvider: detail.rtcProvider,
        serverUrl: detail.serverUrl,
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
        SnackBar(
          content: Text(
            _meetingText(
              context,
              zhCN: '当前会议未绑定群聊，无法从成员列表邀请',
              zhTW: '目前會議未綁定群聊，無法從成員列表邀請',
              en: 'This meeting is not linked to a group chat, so members cannot be invited from the member list.',
            ),
          ),
        ),
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
      ).showSnackBar(
        SnackBar(
          content: Text(
            _meetingText(
              context,
              zhCN: '加载群成员失败，请稍后重试',
              zhTW: '載入群成員失敗，請稍後重試',
              en: 'Failed to load group members. Please try again later.',
            ),
          ),
        ),
      );
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
        SnackBar(
          content: Text(
            _meetingText(
              context,
              zhCN: '暂无可邀请成员（群成员已全部在会议中）',
              zhTW: '暫無可邀請成員（群成員已全部在會議中）',
              en: 'No members are available to invite. All group members are already in the meeting.',
            ),
          ),
        ),
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
            _friendlyMeetingError(
              response.message,
              fallback: _meetingText(
                context,
                zhCN: '邀请失败',
                zhTW: '邀請失敗',
                en: 'Failed to send invitations',
              ),
            ),
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          _meetingText(
            context,
            zhCN: '邀请已发送',
            zhTW: '邀請已發送',
            en: 'Invitations sent',
          ),
        ),
      ),
    );
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
                      _meetingText(
                        context,
                        zhCN: '邀请群成员',
                        zhTW: '邀請群成員',
                        en: 'Invite Group Members',
                      ),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _meetingText(
                        context,
                        zhCN: '从群成员里选择需要加入的人',
                        zhTW: '從群成員中選擇需要加入的人',
                        en: 'Choose members from the group to invite',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: _meetingText(
                          context,
                          zhCN: '搜索昵称 / 用户名 / UUID',
                          zhTW: '搜尋暱稱 / 用戶名 / UUID',
                          en: 'Search nickname / username / UUID',
                        ),
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
                          text: _meetingText(
                            context,
                            zhCN: '可选 ${members.length} 人',
                            zhTW: '可選 ${members.length} 人',
                            en: '${members.length} available',
                          ),
                          isDark: isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildSheetTag(
                          text: _meetingText(
                            context,
                            zhCN: '已选 ${selectedIds.length} 人',
                            zhTW: '已選 ${selectedIds.length} 人',
                            en: '${selectedIds.length} selected',
                          ),
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                _meetingText(
                                  context,
                                  zhCN: '未找到可邀请成员',
                                  zhTW: '找不到可邀請成員',
                                  en: 'No members available to invite',
                                ),
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
                            child: Text(
                              _meetingText(
                                sheetContext,
                                zhCN: '取消',
                                zhTW: '取消',
                                en: 'Cancel',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(<String>[]),
                            child: Text(
                              _meetingText(
                                sheetContext,
                                zhCN: '跳过',
                                zhTW: '跳過',
                                en: 'Skip',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(sheetContext).pop(
                              selectedIds.toList(),
                            ),
                            child: Text(
                              _meetingText(
                                sheetContext,
                                zhCN: '邀请(${selectedIds.length})',
                                zhTW: '邀請(${selectedIds.length})',
                                en: 'Invite (${selectedIds.length})',
                              ),
                            ),
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
        fallback: _meetingText(
          context,
          zhCN: '音视频凭证获取失败，正在重试',
          zhTW: '音訊與視訊憑證取得失敗，正在重試',
          en: 'Failed to get audio/video credentials. Retrying.',
        ),
      );
      if (mounted) setState(() {});
      _scheduleRtcReconnect();
      return;
    }
    final normalized = _normalizeJoinData(tokenResp.data!);
    if (normalized == null) {
      _rtcConnecting = false;
      _rtcStatusHint = _meetingText(
        context,
        zhCN: '音视频参数缺失，请稍后重试',
        zhTW: '音訊與視訊參數缺失，請稍後重試',
        en: 'Audio/video parameters are missing. Please try again later.',
      );
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
      _rtcStatusHint = _meetingText(
        context,
        zhCN: '音视频参数缺失，请稍后重试',
        zhTW: '音訊與視訊參數缺失，請稍後重試',
        en: 'Audio/video parameters are missing. Please try again later.',
      );
      if (mounted) setState(() {});
      return false;
    }
    _joiningRtc = true;
    _allowRtcAutoReconnect = true;
    _rtcMeetingType = normalized.meetingType;
    _rtcProvider = normalized.rtcProvider;
    _rtcChannelName = normalized.rtcProvider == 'livekit'
        ? normalized.roomName
        : normalized.channelName;
    _rtcConnecting = true;
    if (mounted) setState(() {});

    try {
      final allow = await _requestRtcPermissions(normalized.meetingType);
      if (!allow) {
        _rtcConnecting = false;
        _rtcStatusHint = _meetingText(
          context,
          zhCN: '缺少麦克风/摄像头权限，无法加入音视频',
          zhTW: '缺少麥克風／鏡頭權限，無法加入音訊與視訊',
          en: 'Microphone/camera permission is required to join audio and video.',
        );
        if (mounted) setState(() {});
        return false;
      }

      if (normalized.rtcProvider == 'livekit') {
        return await _joinLiveKitRtc(normalized);
      }

      await _ensureRtcEngine(
        appId: normalized.appId,
        meetingType: normalized.meetingType,
      );
      final engine = _rtcEngine;
      if (engine == null || _tearingDownRtc || !mounted) {
        _rtcConnecting = false;
        _rtcStatusHint = _meetingText(
          context,
          zhCN: '音视频引擎初始化失败',
          zhTW: '音訊與視訊引擎初始化失敗',
          en: 'Failed to initialize the audio/video engine.',
        );
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
      _rtcStatusHint = _meetingText(
        context,
        zhCN: '音视频连接失败，正在重试',
        zhTW: '音訊與視訊連線失敗，正在重試',
        en: 'Audio/video connection failed. Retrying.',
      );
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

  Future<bool> _joinLiveKitRtc(MeetingJoinResult data) async {
    await _disconnectLiveKitRoom();

    final room = lk.Room();
    final listener = room.createListener();
    _liveKitRoom = room;
    _liveKitListener = listener;
    _liveKitLocalVideoTrack = null;
    _remoteLiveKitIdentities.clear();
    _liveKitRemoteVideoTracks.clear();

    listener
      ..on<lk.RoomConnectedEvent>((event) {
        if (!mounted) return;
        _rtcJoined = true;
        _rtcConnecting = false;
        _rtcReconnectAttempts = 0;
        _rtcReconnectTimer?.cancel();
        _rtcReconnectTimer = null;
        _rtcStatusHint = null;
        setState(() {});
      })
      ..on<lk.TrackSubscribedEvent>((event) {
        _handleLiveKitTrackSubscribed(event);
      })
      ..on<lk.TrackUnsubscribedEvent>((event) {
        _handleLiveKitTrackUnsubscribed(event);
      })
      ..on<lk.ParticipantConnectedEvent>((event) {
        if (!mounted) return;
        _remoteLiveKitIdentities.add(event.participant.identity);
        setState(() {});
      })
      ..on<lk.ParticipantDisconnectedEvent>((event) {
        if (!mounted) return;
        final identity = event.participant.identity;
        _remoteLiveKitIdentities.remove(identity);
        _liveKitRemoteVideoTracks.remove(identity);
        setState(() {});
      })
      ..on<lk.RoomReconnectingEvent>((event) {
        if (!mounted) return;
        _rtcStatusHint = _meetingText(
          context,
          zhCN: '网络波动，音视频重连中',
          zhTW: '網路波動，音訊與視訊重新連線中',
          en: 'Network unstable. Reconnecting audio and video.',
        );
        setState(() {});
      })
      ..on<lk.RoomReconnectedEvent>((event) {
        if (!mounted) return;
        _rtcJoined = true;
        _rtcConnecting = false;
        _rtcReconnectAttempts = 0;
        _rtcReconnectTimer?.cancel();
        _rtcReconnectTimer = null;
        _rtcStatusHint = null;
        setState(() {});
      })
      ..on<lk.RoomDisconnectedEvent>((event) {
        if (!mounted || _tearingDownRtc) return;
        _rtcJoined = false;
        _rtcConnecting = false;
        _remoteLiveKitIdentities.clear();
        _liveKitRemoteVideoTracks.clear();
        setState(() {});
        if (_allowRtcAutoReconnect) {
          _scheduleRtcReconnect();
        }
      });

    final isVideo = data.meetingType == 'video';
    _videoMuted = !isVideo || _videoMutedByHost;
    _audioMuted = _audioMuted || _audioMutedByHost;

    try {
      await room.connect(data.serverUrl!, data.token);
      await room.localParticipant?.setMicrophoneEnabled(!_audioMuted);
      if (isVideo && !_videoMuted) {
        final publication = await room.localParticipant?.setCameraEnabled(true);
        final track = publication?.track;
        _liveKitLocalVideoTrack =
            track is lk.LocalVideoTrack ? track : _findLiveKitLocalVideoTrack();
      } else {
        await room.localParticipant?.setCameraEnabled(false);
        _liveKitLocalVideoTrack = null;
      }
      _syncLiveKitRemoteParticipants(room);

      _rtcJoined = true;
      _rtcConnecting = false;
      _rtcReconnectAttempts = 0;
      _rtcStatusHint = null;
      await WakelockPlus.enable();
      if (mounted) setState(() {});
      return true;
    } catch (e) {
      await _disconnectLiveKitRoom();
      rethrow;
    }
  }

  void _handleLiveKitTrackSubscribed(lk.TrackSubscribedEvent event) {
    if (!mounted) return;
    final identity = event.participant.identity;
    _remoteLiveKitIdentities.add(identity);
    if (event.track.kind == lk.TrackType.VIDEO &&
        event.track is lk.RemoteVideoTrack) {
      _liveKitRemoteVideoTracks[identity] = event.track as lk.RemoteVideoTrack;
    }
    setState(() {});
  }

  void _handleLiveKitTrackUnsubscribed(lk.TrackUnsubscribedEvent event) {
    if (!mounted) return;
    if (event.track.kind == lk.TrackType.VIDEO) {
      _liveKitRemoteVideoTracks.remove(event.participant.identity);
      setState(() {});
    }
  }

  void _syncLiveKitRemoteParticipants(lk.Room room) {
    for (final participant in room.remoteParticipants.values) {
      _remoteLiveKitIdentities.add(participant.identity);
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (track != null) {
          _liveKitRemoteVideoTracks[participant.identity] = track;
        }
      }
    }
  }

  lk.LocalVideoTrack? _findLiveKitLocalVideoTrack() {
    final publications = _liveKitRoom?.localParticipant?.videoTrackPublications;
    if (publications == null) return null;
    for (final publication in publications) {
      final track = publication.track;
      if (track != null && !publication.muted) {
        return track;
      }
    }
    return null;
  }

  Future<void> _disconnectLiveKitRoom() async {
    final listener = _liveKitListener;
    _liveKitListener = null;
    try {
      await listener?.dispose();
    } catch (e) {
      debugPrint('[Meeting] LiveKit listener dispose error: $e');
    }

    final room = _liveKitRoom;
    _liveKitRoom = null;
    _liveKitLocalVideoTrack = null;
    _remoteLiveKitIdentities.clear();
    _liveKitRemoteVideoTracks.clear();
    if (room == null) return;

    try {
      await room.disconnect();
      await room.dispose();
    } catch (e) {
      debugPrint('[Meeting] LiveKit disconnect error: $e');
    }
  }

  Future<void> _setLiveKitCameraEnabled(bool enabled) async {
    final participant = _liveKitRoom?.localParticipant;
    if (participant == null) return;
    final publication = await participant.setCameraEnabled(enabled);
    if (!enabled) {
      _liveKitLocalVideoTrack = null;
      return;
    }
    final track = publication?.track;
    _liveKitLocalVideoTrack =
        track is lk.LocalVideoTrack ? track : _findLiveKitLocalVideoTrack();
  }

  Future<void> _switchLiveKitCamera() async {
    final room = _liveKitRoom;
    if (room == null) return;
    final devices = await lk.Hardware.instance.videoInputs();
    if (devices.length < 2) return;
    final selectedId = room.selectedVideoInputDeviceId;
    lk.MediaDevice? nextDevice;
    for (final device in devices) {
      if (device.deviceId != selectedId) {
        nextDevice = device;
        break;
      }
    }
    if (nextDevice == null) return;
    await room.setVideoInputDevice(nextDevice);
    _liveKitLocalVideoTrack = _findLiveKitLocalVideoTrack();
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
          _rtcStatusHint = _meetingText(
            context,
            zhCN: '网络波动，音视频重连中',
            zhTW: '網路波動，音訊與視訊重新連線中',
            en: 'Network unstable. Reconnecting audio and video.',
          );
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
    _rtcStatusHint = _meetingText(
      context,
      zhCN: '网络波动，$delaySeconds 秒后第 $_rtcReconnectAttempts 次重连',
      zhTW: '網路波動，$delaySeconds 秒後第 $_rtcReconnectAttempts 次重新連線',
      en: 'Network unstable. Reconnecting in $delaySeconds seconds (attempt $_rtcReconnectAttempts).',
    );
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
    if (_rtcProvider == 'livekit') return;
    final engine = _rtcEngine;
    if (engine == null) return;
    final tokenResp = await _meetingService.getMeetingToken(widget.meetingId);
    if (!mounted) return;
    if (!tokenResp.isSuccess || tokenResp.data == null) {
      debugPrint('[Meeting] renew token failed: ${tokenResp.message}');
      _rtcStatusHint = _meetingText(
        context,
        zhCN: '音视频凭证续期失败，正在重试',
        zhTW: '音訊與視訊憑證續期失敗，正在重試',
        en: 'Failed to renew audio/video credentials. Retrying.',
      );
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
      _rtcStatusHint = _meetingText(
        context,
        zhCN: '音视频凭证续期失败，正在重试',
        zhTW: '音訊與視訊憑證續期失敗，正在重試',
        en: 'Failed to renew audio/video credentials. Retrying.',
      );
      if (mounted) setState(() {});
      _scheduleRtcReconnect();
    }
  }

  Future<bool> _requestRtcPermissions(String meetingType) async {
    if (kIsWeb) return true;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return true;
    }
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;
    if (meetingType == 'video') {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) return false;
    }
    return true;
  }

  Future<void> _teardownRtc({bool disableAutoReconnect = true}) async {
    // 主动离会/页面销毁会关闭自动重连；网络重连换房时则保留该能力。
    if (_tearingDownRtc) return;
    _tearingDownRtc = true;
    if (disableAutoReconnect) {
      _allowRtcAutoReconnect = false;
      _rtcReconnectTimer?.cancel();
      _rtcReconnectTimer = null;
      _rtcStatusHint = null;
    }
    final engine = _rtcEngine;
    try {
      await _disconnectLiveKitRoom();
      if (engine != null) {
        final eventHandler = _rtcEventHandler;
        if (eventHandler != null) {
          engine.unregisterEventHandler(eventHandler);
        }
        await engine.leaveChannel();
        await engine.stopPreview();
        await engine.release();
      }
    } catch (e) {
      debugPrint('[Meeting] teardown rtc error: $e');
    } finally {
      _rtcEngine = null;
      _rtcEventHandler = null;
      _rtcChannelName = '';
      _rtcProvider = 'agora';
      _rtcJoined = false;
      _rtcConnecting = false;
      _joiningRtc = false;
      _remoteUids.clear();
      _remoteLiveKitIdentities.clear();
      _liveKitRemoteVideoTracks.clear();
      _liveKitLocalVideoTrack = null;
      _tearingDownRtc = false;
      if (mounted) {
        setState(() {});
      }
      await WakelockPlus.disable();
    }
  }

  Future<void> _toggleMuteAudio() async {
    final engine = _rtcEngine;
    if (!_rtcJoined) return;
    if (_rtcProvider != 'livekit' && engine == null) return;
    final next = !_audioMuted;
    if (!next && _audioMutedByHost && !_isCurrentUserHost()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              _meetingText(
                context,
                zhCN: '你已被主持人静音，暂时不能自行解除',
                zhTW: '你已被主持人靜音，暫時無法自行解除',
                en: 'The host muted you. You cannot unmute yourself right now.',
              ),
            ),
          ),
        );
      }
      return;
    }
    try {
      if (_rtcProvider == 'livekit') {
        await _liveKitRoom?.localParticipant?.setMicrophoneEnabled(!next);
      } else {
        await engine!.muteLocalAudioStream(next);
      }
      if (!mounted) return;
      setState(() => _audioMuted = next);
    } catch (e) {
      debugPrint('[Meeting] mute audio error: $e');
    }
  }

  Future<void> _toggleMuteVideo() async {
    if (_rtcMeetingType != 'video') return;
    final engine = _rtcEngine;
    if (!_rtcJoined) return;
    if (_rtcProvider != 'livekit' && engine == null) return;
    final next = !_videoMuted;
    if (!next && _videoMutedByHost && !_isCurrentUserHost()) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              _meetingText(
                context,
                zhCN: '你已被主持人关闭视频，暂时不能自行开启',
                zhTW: '你已被主持人關閉視訊，暫時無法自行開啟',
                en: 'The host turned off your video. You cannot enable it right now.',
              ),
            ),
          ),
        );
      }
      return;
    }
    try {
      if (_rtcProvider == 'livekit') {
        await _setLiveKitCameraEnabled(!next);
      } else {
        await engine!.muteLocalVideoStream(next);
        if (!next) {
          await engine.enableVideo();
          await engine.startPreview();
        }
      }
      if (!mounted) return;
      setState(() => _videoMuted = next);
    } catch (e) {
      debugPrint('[Meeting] mute video error: $e');
    }
  }

  Future<void> _switchCamera() async {
    final engine = _rtcEngine;
    if (!_rtcJoined || _rtcMeetingType != 'video') return;
    try {
      if (_rtcProvider == 'livekit') {
        await _switchLiveKitCamera();
      } else {
        if (engine == null) return;
        await engine.switchCamera();
      }
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
          content: Text(
            _friendlyMeetingError(
              resp.message,
              fallback: _meetingText(
                context,
                zhCN: '操作失败',
                zhTW: '操作失敗',
                en: 'Operation failed',
              ),
            ),
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          _meetingText(
            context,
            zhCN: '成员状态已更新',
            zhTW: '成員狀態已更新',
            en: 'Member status updated',
          ),
        ),
      ),
    );
    await _loadMeetingDetail(silent: true);
  }

  Future<void> _kickMember(MeetingParticipant member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            _meetingText(
              ctx,
              zhCN: '移出成员',
              zhTW: '移出成員',
              en: 'Remove Member',
            ),
          ),
          content: Text(
            _meetingText(
              ctx,
              zhCN:
                  '确认移出 ${member.userName.isNotEmpty ? member.userName : member.userId} 吗？',
              zhTW:
                  '確認移出 ${member.userName.isNotEmpty ? member.userName : member.userId} 嗎？',
              en: 'Remove ${member.userName.isNotEmpty ? member.userName : member.userId} from the meeting?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                _meetingText(
                  ctx,
                  zhCN: '取消',
                  zhTW: '取消',
                  en: 'Cancel',
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                _meetingText(
                  ctx,
                  zhCN: '移出',
                  zhTW: '移出',
                  en: 'Remove',
                ),
              ),
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
          content: Text(
            _friendlyMeetingError(
              resp.message,
              fallback: _meetingText(
                context,
                zhCN: '移出失败',
                zhTW: '移出失敗',
                en: 'Failed to remove member',
              ),
            ),
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          _meetingText(
            context,
            zhCN: '成员已移出',
            zhTW: '成員已移出',
            en: 'Member removed',
          ),
        ),
      ),
    );
    await _loadMeetingDetail(silent: true);
  }

  Future<void> _transferHost(MeetingParticipant member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            _meetingText(
              ctx,
              zhCN: '转移主持人',
              zhTW: '轉移主持人',
              en: 'Transfer Host',
            ),
          ),
          content: Text(
            _meetingText(
              ctx,
              zhCN:
                  '确认将主持人转移给 ${member.userName.isNotEmpty ? member.userName : member.userId} 吗？',
              zhTW:
                  '確認將主持人轉移給 ${member.userName.isNotEmpty ? member.userName : member.userId} 嗎？',
              en: 'Transfer host privileges to ${member.userName.isNotEmpty ? member.userName : member.userId}?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                _meetingText(
                  ctx,
                  zhCN: '取消',
                  zhTW: '取消',
                  en: 'Cancel',
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                _meetingText(
                  ctx,
                  zhCN: '确认',
                  zhTW: '確認',
                  en: 'Confirm',
                ),
              ),
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
          content: Text(
            _friendlyMeetingError(
              resp.message,
              fallback: _meetingText(
                context,
                zhCN: '转移失败',
                zhTW: '轉移失敗',
                en: 'Failed to transfer host',
              ),
            ),
          ),
        ),
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(
        content: Text(
          _meetingText(
            context,
            zhCN: '主持人已转移',
            zhTW: '主持人已轉移',
            en: 'Host transferred',
          ),
        ),
      ),
    );
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
          title: Text(
            _meetingText(
              ctx,
              zhCN: '编辑会议名称',
              zhTW: '編輯會議名稱',
              en: 'Edit Meeting Title',
            ),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 40,
            decoration: InputDecoration(
              labelText: _meetingText(
                ctx,
                zhCN: '会议名称',
                zhTW: '會議名稱',
                en: 'Meeting Title',
              ),
              hintText: _meetingText(
                ctx,
                zhCN: '请输入会议名称',
                zhTW: '請輸入會議名稱',
                en: 'Enter a meeting title',
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                _meetingText(
                  ctx,
                  zhCN: '取消',
                  zhTW: '取消',
                  en: 'Cancel',
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                _meetingText(
                  ctx,
                  zhCN: '保存',
                  zhTW: '儲存',
                  en: 'Save',
                ),
              ),
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
            _friendlyMeetingError(
              resp.message,
              fallback: _meetingText(
                context,
                zhCN: '修改会议名称失败',
                zhTW: '修改會議名稱失敗',
                en: 'Failed to update meeting title',
              ),
            ),
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _meetingText(
            context,
            zhCN: '会议名称已更新',
            zhTW: '會議名稱已更新',
            en: 'Meeting title updated',
          ),
        ),
      ),
    );
    await _loadMeetingDetail(silent: true);
  }

  Future<void> _minimizeMeeting() async {
    if (_isActioning || _detail?.status != 'active') return;
    // 最小化只关闭页面并保留会话摘要，不退出服务端会议或 RTC 媒体房间。
    ref.read(meetingSessionProvider.notifier).setMinimized(true);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final title = detail?.title.isNotEmpty == true
        ? detail!.title
        : (widget.chatName?.isNotEmpty == true
            ? widget.chatName!
            : _meetingText(
                context,
                zhCN: '群会议',
                zhTW: '群會議',
                en: 'Group Meeting',
              ));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final meetingStatus =
        detail == null ? '' : _meetingStatusText(context, detail.status);

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
            tooltip: _meetingText(
              context,
              zhCN: '刷新',
              zhTW: '重新整理',
              en: 'Refresh',
            ),
            onPressed: _isLoading ? null : _loadMeetingDetail,
            icon: const Icon(Icons.refresh),
          ),
          if (detail != null && detail.status == 'active')
            IconButton(
              tooltip: _meetingText(
                context,
                zhCN: '悬浮',
                zhTW: '懸浮',
                en: 'Minimize',
              ),
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
                child: Text(
                  _meetingText(
                    context,
                    zhCN: '重试',
                    zhTW: '重試',
                    en: 'Retry',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (detail == null) {
      return Center(
        child: Text(
          _meetingText(
            context,
            zhCN: '会议不存在',
            zhTW: '會議不存在',
            en: 'Meeting not found',
          ),
        ),
      );
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
                    const SizedBox(height: 18),
                    _buildMeetingSafetyNote(),
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
    final remoteLiveKitIdentities = _remoteLiveKitIdentities.toList()..sort();
    final compact = MediaQuery.sizeOf(context).width < 720;
    final connectionText = _rtcJoined
        ? _meetingText(
            context,
            zhCN: '已连接',
            zhTW: '已連線',
            en: 'Connected',
          )
        : (_rtcConnecting
            ? _meetingText(
                context,
                zhCN: '连接中',
                zhTW: '連線中',
                en: 'Connecting',
              )
            : _meetingText(
                context,
                zhCN: '未连接',
                zhTW: '未連線',
                en: 'Disconnected',
              ));

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EDF5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F101828),
            blurRadius: 18,
            offset: Offset(0, 8),
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
                color: Color(0xFF3D5AFE),
              ),
              const SizedBox(width: 8),
              Text(
                isVideoMeeting
                    ? _meetingText(
                        context,
                        zhCN: '群视频',
                        zhTW: '群視訊',
                        en: 'Group Video',
                      )
                    : _meetingText(
                        context,
                        zhCN: '群音频',
                        zhTW: '群語音',
                        en: 'Group Audio',
                      ),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              _buildPill(
                icon: _rtcJoined
                    ? Icons.link
                    : (_rtcConnecting ? Icons.sync : Icons.link_off),
                text: connectionText,
                color: _rtcJoined
                    ? const Color(0xFFE8F8F0)
                    : const Color(0xFFF1F5F9),
                textColor: _rtcJoined
                    ? const Color(0xFF119C63)
                    : const Color(0xFF64748B),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildAudioStatusItem(
                  icon: _audioMuted || _audioMutedByHost
                      ? Icons.mic_off_outlined
                      : Icons.mic_none_rounded,
                  label: _meetingText(
                    context,
                    zhCN: '麦克风',
                    zhTW: '麥克風',
                    en: 'Mic',
                  ),
                  value: _audioMuted || _audioMutedByHost
                      ? _meetingText(
                          context,
                          zhCN: '已静音',
                          zhTW: '已靜音',
                          en: 'Muted',
                        )
                      : _meetingText(
                          context,
                          zhCN: '开启',
                          zhTW: '開啟',
                          en: 'On',
                        ),
                  color: _audioMuted || _audioMutedByHost
                      ? const Color(0xFF94A3B8)
                      : const Color(0xFF21B26F),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAudioStatusItem(
                  icon: Icons.volume_up_outlined,
                  label: _meetingText(
                    context,
                    zhCN: '扬声器',
                    zhTW: '揚聲器',
                    en: 'Speaker',
                  ),
                  value: isJoined
                      ? _meetingText(
                          context,
                          zhCN: '开启',
                          zhTW: '開啟',
                          en: 'On',
                        )
                      : _meetingText(
                          context,
                          zhCN: '待加入',
                          zhTW: '待加入',
                          en: 'Pending',
                        ),
                  color: isJoined
                      ? const Color(0xFF21B26F)
                      : const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAudioStatusItem(
                  icon: Icons.network_cell_outlined,
                  label: _meetingText(
                    context,
                    zhCN: '网络',
                    zhTW: '網路',
                    en: 'Network',
                  ),
                  value: _rtcJoined
                      ? _meetingText(
                          context,
                          zhCN: '良好',
                          zhTW: '良好',
                          en: 'Good',
                        )
                      : (_rtcConnecting
                          ? _meetingText(
                              context,
                              zhCN: '连接中',
                              zhTW: '連線中',
                              en: 'Connecting',
                            )
                          : _meetingText(
                              context,
                              zhCN: '离线',
                              zhTW: '離線',
                              en: 'Offline',
                            )),
                  color: _rtcJoined
                      ? const Color(0xFF21B26F)
                      : (_rtcConnecting
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF94A3B8)),
                ),
              ),
            ],
          ),
          if (!isJoined)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _meetingText(
                  context,
                  zhCN: '你尚未加入会议，加入后将自动连接音视频。',
                  zhTW: '你尚未加入會議，加入後將自動連線音訊與視訊。',
                  en: 'You have not joined the meeting yet. Audio and video will connect automatically after joining.',
                ),
                style: TextStyle(
                  color: Colors.blueGrey.shade700,
                  fontSize: compact ? 12 : 13,
                ),
              ),
            )
          else if (_rtcConnecting)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _meetingText(
                  context,
                  zhCN: '正在连接音视频...',
                  zhTW: '正在連線音訊與視訊...',
                  en: 'Connecting audio and video...',
                ),
                style: TextStyle(
                  color: Colors.blueGrey.shade700,
                  fontSize: compact ? 12 : 13,
                ),
              ),
            )
          else if (!_rtcJoined)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                _meetingText(
                  context,
                  zhCN: '音视频未连接，将自动重试。',
                  zhTW: '音訊與視訊未連線，將自動重試。',
                  en: 'Audio and video are not connected. The app will retry automatically.',
                ),
                style: TextStyle(
                  color: Colors.blueGrey.shade700,
                  fontSize: compact ? 12 : 13,
                ),
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
                    ? _meetingText(
                        context,
                        zhCN: '主持人已将你音频静音',
                        zhTW: '主持人已將你的音訊靜音',
                        en: 'The host muted your audio',
                      )
                    : (_videoMutedByHost && !_audioMutedByHost
                        ? _meetingText(
                            context,
                            zhCN: '主持人已关闭你的视频',
                            zhTW: '主持人已關閉你的視訊',
                            en: 'The host turned off your video',
                          )
                        : _meetingText(
                            context,
                            zhCN: '主持人已限制你的音视频',
                            zhTW: '主持人已限制你的音訊與視訊',
                            en: 'The host restricted your audio and video',
                          )),
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
            _buildVideoGrid(remoteUids, remoteLiveKitIdentities),
          ],
          if (isJoined) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _rtcJoined ? _toggleMuteAudio : null,
                    icon: Icon(
                      _audioMuted ? Icons.mic_off_outlined : Icons.mic_none,
                    ),
                    label: Text(
                      _audioMuted
                          ? _meetingText(
                              context,
                              zhCN: '取消静音',
                              zhTW: '取消靜音',
                              en: 'Unmute',
                            )
                          : _meetingText(
                              context,
                              zhCN: '静音',
                              zhTW: '靜音',
                              en: 'Mute',
                            ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF536DFE),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                if (isVideoMeeting) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _rtcJoined ? _toggleMuteVideo : null,
                    icon: Icon(
                      _videoMuted
                          ? Icons.videocam_off_outlined
                          : Icons.videocam_outlined,
                    ),
                    label: Text(
                      _videoMuted
                          ? _meetingText(
                              context,
                              zhCN: '开启视频',
                              zhTW: '開啟視訊',
                              en: 'Turn On Video',
                            )
                          : _meetingText(
                              context,
                              zhCN: '关闭视频',
                              zhTW: '關閉視訊',
                              en: 'Turn Off Video',
                            ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      side: const BorderSide(color: Color(0xFFD8E0EC)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _rtcJoined ? _switchCamera : null,
                    icon: const Icon(Icons.flip_camera_android_outlined),
                    label: Text(
                      _meetingText(
                        context,
                        zhCN: '切换摄像头',
                        zhTW: '切換鏡頭',
                        en: 'Switch Camera',
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      side: const BorderSide(color: Color(0xFFD8E0EC)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoGrid(
    List<int> remoteUids,
    List<String> remoteLiveKitIdentities,
  ) {
    final tiles = <Widget>[
      _buildLocalTile(),
      if (_rtcProvider == 'livekit')
        ...remoteLiveKitIdentities.map(_buildLiveKitRemoteTile)
      else
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
    final liveKitTrack =
        _liveKitLocalVideoTrack ?? _findLiveKitLocalVideoTrack();
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
            child: showVideo
                ? (_rtcProvider == 'livekit'
                    ? (liveKitTrack != null
                        ? lk.VideoTrackRenderer(liveKitTrack)
                        : const Center(
                            child: Icon(
                              Icons.person,
                              color: Colors.white54,
                              size: 44,
                            ),
                          ))
                    : (engine != null
                        ? AgoraVideoView(
                            controller: VideoViewController(
                              rtcEngine: engine,
                              canvas: const VideoCanvas(uid: 0),
                            ),
                          )
                        : const Center(
                            child: Icon(
                              Icons.person,
                              color: Colors.white54,
                              size: 44,
                            ),
                          )))
                : const Center(
                    child: Icon(Icons.person, color: Colors.white54, size: 44),
                  ),
          ),
          Positioned(
            left: 8,
            bottom: 8,
            child: _nameTag(
              _meetingText(
                context,
                zhCN: '本人',
                zhTW: '本人',
                en: 'You',
              ),
            ),
          ),
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

  Widget _buildLiveKitRemoteTile(String identity) {
    final track = _liveKitRemoteVideoTracks[identity];
    final label = _identityNameMap[identity] ?? identity;
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
            child: track != null
                ? lk.VideoTrackRenderer(track)
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

  String _meetingStatusText(BuildContext context, String status) {
    switch (status) {
      case 'active':
        return _meetingText(
          context,
          zhCN: '进行中',
          zhTW: '進行中',
          en: 'In Progress',
        );
      case 'ended':
        return _meetingText(
          context,
          zhCN: '已结束',
          zhTW: '已結束',
          en: 'Ended',
        );
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
    final provider = normalizeRtcProvider(
      data.rtcProvider.trim().isNotEmpty
          ? data.rtcProvider
          : (_detail?.rtcProvider ?? 'agora'),
    );
    final appId = data.appId.trim();
    final channelName = data.channelName.trim().isNotEmpty
        ? data.channelName.trim()
        : (_detail?.channelName.trim() ?? '');
    final roomName = data.roomName.trim().isNotEmpty
        ? data.roomName.trim()
        : (channelName.isNotEmpty ? channelName : (_detail?.roomName ?? ''));
    final serverUrl = (data.serverUrl?.trim().isNotEmpty == true
            ? data.serverUrl!.trim()
            : (_detail?.serverUrl?.trim() ?? ''))
        .trim();
    if (data.token.trim().isEmpty ||
        (provider == 'agora' && (appId.isEmpty || channelName.isEmpty)) ||
        (provider == 'livekit' && (serverUrl.isEmpty || roomName.isEmpty))) {
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
      channelName: channelName.isNotEmpty ? channelName : roomName,
      roomName: roomName.isNotEmpty ? roomName : channelName,
      meetingType: meetingType,
      token: data.token.trim(),
      appId: appId,
      agoraUid: data.agoraUid,
      rtcProvider: provider,
      serverUrl: serverUrl.isNotEmpty ? serverUrl : data.serverUrl,
      identity: data.identity,
      approvalRequired: data.approvalRequired,
    );
  }

  String _friendlyMeetingError(String? raw, {required String fallback}) {
    final message = (raw ?? '').trim();
    if (message.isEmpty) return fallback;
    final normalized = message.toLowerCase();
    if (normalized.contains('meeting is full') ||
        normalized.contains('meeting capacity reached') ||
        message.contains('会议人数已满')) {
      return _meetingText(
        context,
        zhCN: '会议人数已满',
        zhTW: '會議人數已滿',
        en: 'Meeting capacity reached',
      );
    }
    if (normalized.contains('approval required') ||
        normalized.contains('join approval') ||
        message.contains('等待')) {
      return _meetingText(
        context,
        zhCN: '已提交申请，等待主持人确认',
        zhTW: '已提交申請，等待主持人確認',
        en: 'Request submitted. Waiting for host approval.',
      );
    }
    final localized = localizeServerMessage(message);
    if (localized != message) {
      return localized;
    }
    if (containsHanText(message) &&
        AppLocalizations.of(context).language != AppLanguage.zhCN) {
      return fallback;
    }
    return message;
  }

  String _participantStatusText(MeetingParticipant p) {
    final base = switch (p.status) {
      'joined' => _meetingText(
          context,
          zhCN: '已加入',
          zhTW: '已加入',
          en: 'Joined',
        ),
      'invited' => _meetingText(
          context,
          zhCN: '已邀请',
          zhTW: '已邀請',
          en: 'Invited',
        ),
      'left' => _meetingText(
          context,
          zhCN: '已离开',
          zhTW: '已離開',
          en: 'Left',
        ),
      'kicked' => _meetingText(
          context,
          zhCN: '已移出',
          zhTW: '已移出',
          en: 'Removed',
        ),
      _ => p.status,
    };

    final tags = <String>[base];
    if (p.mutedAudio) {
      tags.add(
        _meetingText(
          context,
          zhCN: '音频静音',
          zhTW: '音訊靜音',
          en: 'Audio Muted',
        ),
      );
    }
    if (p.mutedVideo) {
      tags.add(
        _meetingText(
          context,
          zhCN: '视频关闭',
          zhTW: '視訊關閉',
          en: 'Video Off',
        ),
      );
    }
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
        : _meetingText(
            context,
            zhCN: '群会议',
            zhTW: '群會議',
            en: 'Group Meeting',
          );
    final rtcText = _rtcJoined
        ? _meetingText(
            context,
            zhCN: 'RTC 已连接',
            zhTW: 'RTC 已連線',
            en: 'RTC connected',
          )
        : (_rtcConnecting
            ? _meetingText(
                context,
                zhCN: 'RTC 连接中',
                zhTW: 'RTC 連線中',
                en: 'RTC connecting',
              )
            : _meetingText(
                context,
                zhCN: 'RTC 未连接',
                zhTW: 'RTC 未連線',
                en: 'RTC disconnected',
              ));
    final typeText = detail.meetingType == 'voice'
        ? _meetingText(
            context,
            zhCN: '语音会议',
            zhTW: '語音會議',
            en: 'Voice meeting',
          )
        : _meetingText(
            context,
            zhCN: '视频会议',
            zhTW: '視訊會議',
            en: 'Video meeting',
          );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF355DFF), Color(0xFF4F73F4)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A315BDA),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0x24FFFFFF),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              detail.meetingType == 'voice'
                  ? Icons.groups_rounded
                  : Icons.video_call_outlined,
              color: Colors.white,
              size: 27,
            ),
          ),
          const SizedBox(width: 12),
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
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (isHost) ...[
                      const SizedBox(width: 8),
                      _buildCompactIconTextButton(
                        icon: Icons.edit_outlined,
                        text: _meetingText(
                          context,
                          zhCN: '改名',
                          zhTW: '改名',
                          en: 'Rename',
                        ),
                        onPressed: _isActioning ? null : _editMeetingTitle,
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0x20FFFFFF),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _rtcJoined
                            ? const Color(0xFF54E48D)
                            : const Color(0xFFFFD166),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '$typeText · ${detail.participants.length}/${detail.maxParticipants} · $rtcText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFEAF0FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
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
            text: detail.meetingType == 'voice'
                ? _meetingText(
                    context,
                    zhCN: '语音',
                    zhTW: '語音',
                    en: 'Voice',
                  )
                : _meetingText(
                    context,
                    zhCN: '视频',
                    zhTW: '視訊',
                    en: 'Video',
                  ),
            color: const Color(0xFFEAF0FF),
            textColor: const Color(0xFF2446B8),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactIconTextButton({
    required IconData icon,
    required String text,
    required VoidCallback? onPressed,
    required Color foregroundColor,
    required Color backgroundColor,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: foregroundColor,
        disabledForegroundColor: foregroundColor.withOpacity(0.45),
        backgroundColor: backgroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      icon: Icon(icon, size: 15),
      label: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
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
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EDF5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0B101828),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          if (isActive && !isJoined)
            Expanded(
              child: FilledButton.icon(
                onPressed: _isActioning ? null : _joinMeeting,
                icon: const Icon(Icons.login, size: 18),
                label: Text(
                  _meetingText(
                    context,
                    zhCN: '加入会议',
                    zhTW: '加入會議',
                    en: 'Join',
                  ),
                ),
                style: _meetingPrimaryButtonStyle(),
              ),
            ),
          if (isActive && isJoined) ...[
            Expanded(
              flex: isHost ? 3 : 1,
              child: OutlinedButton.icon(
                onPressed: _isActioning ? null : _leaveMeeting,
                icon: const Icon(Icons.logout, size: 18),
                label: Text(
                  _meetingText(
                    context,
                    zhCN: '离开',
                    zhTW: '離開',
                    en: 'Leave',
                  ),
                ),
                style: _meetingSecondaryButtonStyle(),
              ),
            ),
            if (isHost) ...[
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: FilledButton.icon(
                  onPressed: _isActioning ? null : _inviteMembers,
                  icon: const Icon(Icons.group_add_rounded, size: 18),
                  label: Text(
                    _meetingText(
                      context,
                      zhCN: '邀请',
                      zhTW: '邀請',
                      en: 'Invite',
                    ),
                  ),
                  style: _meetingPrimaryButtonStyle(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: OutlinedButton.icon(
                  onPressed: _isActioning ? null : _endMeeting,
                  icon: const Icon(Icons.call_end_rounded, size: 18),
                  label: Text(
                    _meetingText(
                      context,
                      zhCN: '结束',
                      zhTW: '結束',
                      en: 'End',
                    ),
                  ),
                  style: _meetingDangerButtonStyle(),
                ),
              ),
            ],
          ],
          if (!isActive)
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isActioning ? null : _loadMeetingDetail,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(
                  _meetingText(
                    context,
                    zhCN: '刷新状态',
                    zhTW: '重新整理狀態',
                    en: 'Refresh',
                  ),
                ),
                style: _meetingSecondaryButtonStyle(),
              ),
            ),
        ],
      ),
    );
  }

  ButtonStyle _meetingPrimaryButtonStyle() {
    return FilledButton.styleFrom(
      backgroundColor: const Color(0xFF536DFE),
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 50),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  ButtonStyle _meetingSecondaryButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF344054),
      minimumSize: const Size(0, 50),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      side: const BorderSide(color: Color(0xFFD8E0EC)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  ButtonStyle _meetingDangerButtonStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFFE03131),
      minimumSize: const Size(0, 50),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
      side: const BorderSide(color: Color(0xFFFFCCD2)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildInfoChipCompact(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      constraints: const BoxConstraints(maxWidth: 220),
      child: Text(
        '$label：$value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Color(0xFF475467),
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildAudioStatusItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE8EDF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 7),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF344054),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _participantStatusColor(MeetingParticipant p) {
    return switch (p.status) {
      'joined' => const Color(0xFF21B26F),
      'invited' => const Color(0xFF536DFE),
      'left' => const Color(0xFF94A3B8),
      'kicked' => const Color(0xFFE03131),
      _ => const Color(0xFF94A3B8),
    };
  }

  Widget _buildMeetingSafetyNote() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 14,
            color: Color(0xFF98A2B3),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _meetingText(
                context,
                zhCN: '会议内容受端到端加密保护',
                zhTW: '會議內容受端到端加密保護',
                en: 'Meeting content is protected by end-to-end encryption',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF98A2B3),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EDF5)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F101828),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _meetingText(
                  context,
                  zhCN: '参会成员',
                  zhTW: '參會成員',
                  en: 'Participants',
                ),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              _buildPill(
                icon: Icons.people_alt_outlined,
                text: '${detail.participants.length}',
                color: const Color(0xFFF1F4FF),
                textColor: const Color(0xFF536DFE),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...detail.participants.map(
            (p) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFBFD),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE8EDF5)),
              ),
              child: Row(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AvatarWidget(
                        avatar: p.userAvatar,
                        name: p.userName,
                        size: 34,
                      ),
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: _participantStatusColor(p),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ],
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
                          style: const TextStyle(
                            color: Color(0xFF101828),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _participantStatusText(p),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF667085),
                            fontWeight: FontWeight.w500,
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
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.more_horiz,
                            color: Color(0xFF344054),
                          ),
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
                                  p.mutedAudio
                                      ? _meetingText(
                                          context,
                                          zhCN: '取消音频静音',
                                          zhTW: '取消音訊靜音',
                                          en: 'Unmute Audio',
                                        )
                                      : _meetingText(
                                          context,
                                          zhCN: '音频静音',
                                          zhTW: '音訊靜音',
                                          en: 'Mute Audio',
                                        ),
                                ),
                              ),
                            ];
                            if (detail.meetingType == 'video') {
                              items.add(
                                PopupMenuItem<String>(
                                  value: 'mute_video',
                                  child: Text(
                                    p.mutedVideo
                                        ? _meetingText(
                                            context,
                                            zhCN: '开启视频',
                                            zhTW: '開啟視訊',
                                            en: 'Turn On Video',
                                          )
                                        : _meetingText(
                                            context,
                                            zhCN: '关闭视频',
                                            zhTW: '關閉視訊',
                                            en: 'Turn Off Video',
                                          ),
                                  ),
                                ),
                              );
                            }
                            if (p.role != 'host' &&
                                p.status == 'joined' &&
                                p.userId != currentUserId) {
                              items.add(
                                PopupMenuItem<String>(
                                  value: 'transfer_host',
                                  child: Text(
                                    _meetingText(
                                      context,
                                      zhCN: '转移主持人',
                                      zhTW: '轉移主持人',
                                      en: 'Transfer Host',
                                    ),
                                  ),
                                ),
                              );
                            }
                            if (p.role != 'host' && p.status != 'kicked') {
                              items.add(
                                PopupMenuItem<String>(
                                  value: 'kick',
                                  child: Text(
                                    _meetingText(
                                      context,
                                      zhCN: '移出成员',
                                      zhTW: '移出成員',
                                      en: 'Remove Member',
                                    ),
                                  ),
                                ),
                              );
                            }
                            return items;
                          },
                        )
                      : _buildPill(
                          icon: p.role == 'host' ? Icons.shield : Icons.person,
                          text: p.role == 'host'
                              ? _meetingText(
                                  context,
                                  zhCN: '主持人',
                                  zhTW: '主持人',
                                  en: 'Host',
                                )
                              : _meetingText(
                                  context,
                                  zhCN: '成员',
                                  zhTW: '成員',
                                  en: 'Member',
                                ),
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
