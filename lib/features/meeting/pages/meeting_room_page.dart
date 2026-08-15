
// 文件用途：会议室 RTC 页面，对齐 kt_im MeetingRoomPage 全功能实现。
// 支持：Agora / LiveKit 双引擎、聊天、成员管理、屏幕共享、心跳、过期自动退出、最小化悬浮。
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/meeting_service.dart';
import '../../../core/services/meeting/meeting_rtc_engine.dart';
import '../../../core/services/meeting/agora_meeting_engine.dart';
import '../../../core/services/meeting/livekit_meeting_engine.dart';
import '../../../core/services/meeting_session_service.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/avatar_widget.dart';

// ─────────────────────────────────────────────
// i18n helper
// ─────────────────────────────────────────────
String _t(BuildContext context,
    {required String zhCN, String? zhTW, required String en}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// ─────────────────────────────────────────────
// 会议内聊天消息模型
// ─────────────────────────────────────────────
class MeetingChatMessage {
  final String senderId;
  final String senderName;
  final String content;
  final DateTime time;
  const MeetingChatMessage({
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.time,
  });
}

// ─────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────
class MeetingRoomPage extends ConsumerStatefulWidget {
  final String? meetingNo;   // 9位会议号，优先用
  final String? meetingId;   // 数据库ID，meetingNo 为空时用
  final String? chatId;
  final String? chatName;

  const MeetingRoomPage({
    super.key,
    this.meetingNo,
    this.meetingId,
    this.chatId,
    this.chatName,
  }) : assert(meetingNo != null || meetingId != null,
              'meetingNo 或 meetingId 必须提供一个');

  @override
  ConsumerState<MeetingRoomPage> createState() => _MeetingRoomPageState();
}

class _MeetingRoomPageState extends ConsumerState<MeetingRoomPage>
    with WidgetsBindingObserver {
  // ── 核心数据 ──────────────────────────────
  bool _loading = true;
  String? _error;
  MeetingRoomJoinResult? _joinData;
  List<MeetingParticipant> _participants = [];
  String _myUserId = '';

  // ── RTC ───────────────────────────────────
  MeetingRtcEngine? _rtc;
  RtcMediaState _rtcState = const RtcMediaState();
  StreamSubscription? _rtcEventSub;
  StreamSubscription? _rtcMediaSub;
  bool _audioToggling = false;
  bool _videoToggling = false;
  bool _speakerOn = true;
  bool _serverMutedAudio = false;
  bool _serverMutedVideo = false;

  // ── 心跳 & 过期 ───────────────────────────
  Timer? _heartbeatTimer;
  Timer? _expiryTimer;

  // ── 聊天 ──────────────────────────────────

  // ── WebSocket ─────────────────────────────
  StreamSubscription<WSMessage>? _wsSub;
  Timer? _refreshThrottle;
  final List<MeetingChatMessage> _chatMessages = [];
  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();
  bool _showChat = false;
  int _unreadChat = 0;

  // ── 成员面板 ──────────────────────────────
  bool _showMembers = false;

  // ── 屏幕共享 ──────────────────────────────
  bool _screenSharing = false;

  // ── Getters ───────────────────────────────
  bool get _isHost => _joinData?.isHost ?? false;
  bool get _isVideo => (_joinData?.meetingType ?? 'audio') == 'video';
  bool get _isLiveKit =>
      (_joinData?.provider ?? '').toLowerCase() == 'livekit';
  bool get _audioMuted => !_rtcState.audioEnabled;
  bool get _videoMuted => !_rtcState.videoEnabled;

  List<String> get _remoteIdentities {
    if (_isLiveKit && _rtc is LivekitMeetingEngine) {
      return (_rtc as LivekitMeetingEngine).remoteIdentities;
    }
    return _rtcState.remoteAudioUids.map((uid) => uid.toString()).toList();
  }

  // ── Lifecycle ─────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _heartbeatTimer?.cancel();
    _expiryTimer?.cancel();
    _rtcEventSub?.cancel();
    _rtcMediaSub?.cancel();
    _rtc?.dispose();
    _wsSub?.cancel();
    _refreshThrottle?.cancel();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  // ── 初始化 ────────────────────────────────
  Future<void> _init() async {
    setState(() { _loading = true; _error = null; });
    try {
      final svc = ref.read(meetingRoomServiceProvider);
      final no = widget.meetingNo;
      final id = widget.meetingId;
      debugPrint('[MEETING] join no=$no id=$id');
      final res = no != null && no.isNotEmpty
          ? await svc.joinRoom(no!)
          : await svc.joinRoomById(id!);
      if (!mounted) return;
      debugPrint('[MEETING] joinRoom res: isSuccess=${res.isSuccess} message=${res.message}');
      if (!res.isSuccess || res.data == null) {
        setState(() {
          _loading = false;
          _error = res.message ??
              _t(context, zhCN: '加入失败', en: 'Join failed');
        });
        return;
      }
      _joinData = res.data!;
      _myUserId = ref.read(authServiceProvider).user?.id ?? '';
      await _requestPermissions();
      await _startRtc(_joinData!);
      _listenWebSocket();
      unawaited(_refreshMembers());
      _startHeartbeat(_joinData!.heartbeatSec);
      _startExpiryWatch(_joinData!.expiresAt);
      _syncSession();
      setState(() { _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = e.toString(); });
    }
  }


  // ── WebSocket 监听 ────────────────────────
  void _listenWebSocket() {
    final ws = ref.read(webSocketServiceProvider.notifier);
    _wsSub = ws.messageStream.listen((msg) {
      if (!mounted) return;
      final frame = msg.data is Map
          ? Map<String, dynamic>.from(msg.data as Map)
          : <String, dynamic>{};
      final data = frame['data'] is Map
          ? Map<String, dynamic>.from(frame['data'] as Map)
          : frame;

      // 过滤掉其他会议的事件
      final eventMeetingId = data['meeting_id']?.toString() ?? '';
      final myMeetingId = _joinData?.meetingId ?? '';
      if (eventMeetingId.isNotEmpty &&
          myMeetingId.isNotEmpty &&
          eventMeetingId != myMeetingId) {
        return;
      }

      switch (msg.type) {
        case 'meeting_room_member_joined':
        case 'meeting_room_member_left':
          _scheduleRefreshMembers();
          break;

        case 'meeting_room_member_muted':
          final targetId = data['target_user_id']?.toString() ?? '';
          final mutedAudio = data['muted_audio'] == true;
          final mutedVideo = data['muted_video'] == true;
          setState(() {
            _participants = _participants.map<MeetingParticipant>((p) {
              if (p.userId != targetId) return p;
              return MeetingParticipant(
                userId: p.userId,
                agoraUid: p.agoraUid,
                userName: p.userName,
                userAvatar: p.userAvatar,
                role: p.role,
                status: p.status,
                mutedAudio: mutedAudio,
                mutedVideo: mutedVideo,
              );
            }).toList();
          });
          break;

        case 'meeting_room_mute_all':
          if (data['muted'] == true) {
            _rtc?.setAudioMuted(true);
          }
          _scheduleRefreshMembers();
          break;

        case 'meeting_room_member_kicked':
          final kicked = data['target_user_id']?.toString() ?? '';
          if (kicked.isNotEmpty && kicked == _myUserId) {
            _showToast(_t(context,
                zhCN: '你已被主持人移出会议', en: 'You were removed by host'));
            _leaveMeeting();
          } else {
            _scheduleRefreshMembers();
          }
          break;

        case 'meeting_room_ended':
          _showToast(_t(context,
              zhCN: '会议已结束', en: 'Meeting ended'));
          _leaveMeeting();
          break;

        case 'meeting_room_settings':
          if (data['settings'] is Map) {
            final s = MeetingRoomSettings.fromJson(
                Map<String, dynamic>.from(data['settings'] as Map));
            setState(() {
              if (_joinData != null) {
                _joinData = MeetingRoomJoinResult(
                  meetingId: _joinData!.meetingId,
                  meetingNo: _joinData!.meetingNo,
                  title: _joinData!.title,
                  meetingType: _joinData!.meetingType,
                  provider: _joinData!.provider,
                  token: _joinData!.token,
                  livekitURL: _joinData!.livekitURL,
                  agoraUid: _joinData!.agoraUid,
                  maxParticipants: _joinData!.maxParticipants,
                  isHost: _joinData!.isHost,
                  mutedAudio: _joinData!.mutedAudio,
                  mutedVideo: _joinData!.mutedVideo,
                  allowChat: _joinData!.allowChat,
                  expiresAt: _joinData!.expiresAt,
                  settings: s,
                  heartbeatSec: _joinData!.heartbeatSec,
                );
              }
            });
          }
          break;

        case 'meeting_room_chat':
          _onWsChatMessage(data);
          break;
      }
    });
  }

  void _scheduleRefreshMembers() {
    _refreshThrottle?.cancel();
    _refreshThrottle = Timer(const Duration(seconds: 2), _refreshMembers);
  }

  Future<void> _refreshMembers() async {
    if (_joinData == null || !mounted) return;
    final svc = ref.read(meetingRoomServiceProvider);
    final res = await svc.getState(_joinData!.meetingNo);
    if (!mounted || !res.isSuccess || res.data == null) return;
    final state = res.data!;
    setState(() {
      _participants = state.participants
          .where((m) => m.userId != _myUserId)
          .cast<MeetingRoomMember>()
          .map((m) => MeetingParticipant(
                userId: m.userId,
                agoraUid: m.agoraUid ?? 0,
                userName: m.userName,
                userAvatar: m.userAvatar,
                role: m.role,
                status: 'joined',
                mutedAudio: m.mutedAudio,
                mutedVideo: m.mutedVideo,
              ))
          .toList();
      // 同步自己的静音状态（state.mutedAudio 为服务端下发值）
      // _rtc?.setAudioMuted(state.mutedAudio);
    });
    debugPrint('[MEETING] refreshMembers: ${state.participantCount} 人, '
        'truncated=${state.participantsTruncated}');
  }

  void _onWsChatMessage(Map<String, dynamic> data) {
    final message = MeetingChatMessage(
      senderId: data['user_id']?.toString() ?? '',
      senderName: data['user_name']?.toString() ?? '',
      content: data['content']?.toString() ?? '',
      time: DateTime.tryParse(data['sent_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
    );
    setState(() {
      _chatMessages.add(message);
      if (_chatMessages.length > 200) _chatMessages.removeAt(0);
      if (!_showChat) _unreadChat++;
    });
    if (_showChat) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_chatScrollController.hasClients) return;
        _chatScrollController.jumpTo(
            _chatScrollController.position.maxScrollExtent);
      });
    }
  }

  // ── 同步悬浮会话（用 syncFromDetail 接口）────
  void _syncSession() {
    final d = _joinData;
    if (d == null) return;
    // 构造最小 MeetingDetail 复用 syncFromDetail
    final detail = MeetingDetail(
      meetingId: d.meetingId,
      chatId: widget.chatId,
      title: d.title,
      meetingType: d.meetingType,
      status: 'active',
      channelName: d.meetingNo,
      rtcProvider: d.provider,
      serverUrl: d.livekitURL,
      maxParticipants: d.maxParticipants,
      duration: 0,
      endReason: '',
      participants: _participants,
    );
    ref.read(meetingSessionProvider.notifier).syncFromDetail(
      detail,
      chatId: widget.chatId ?? '',
      chatName: widget.chatName ?? '',
      isJoined: true,
      isHost: d.isHost,
    );
  }

  // ── 权限 ──────────────────────────────────
  Future<void> _requestPermissions() async {
    final perms = [Permission.microphone];
    if (_isVideo) perms.add(Permission.camera);
    await perms.request();
  }

  // ── RTC 启动 ──────────────────────────────
  Future<void> _startRtc(MeetingRoomJoinResult d) async {
    final engine = _isLiveKit
        ? LivekitMeetingEngine() as MeetingRtcEngine
        : AgoraMeetingEngine();
    _rtc = engine;

    _rtcEventSub = engine.eventStream.listen(_onRtcEvent);
    _rtcMediaSub = engine.mediaStateStream.listen((s) {
      if (!mounted) return;
      setState(() => _rtcState = s);
    });

    await engine.join(
      appId: _isLiveKit ? (d.livekitURL ?? '') : '',
      token: d.token,
      channel: d.meetingNo,
      uid: d.agoraUid ?? 0,
      audioOnly: !_isVideo,
      livekitUrl: d.livekitURL,
    );

    if (d.mutedAudio) {
      _serverMutedAudio = true;
      await engine.setAudioMuted(true);
    }
    if (d.mutedVideo) {
      _serverMutedVideo = true;
      await engine.setVideoMuted(true);
    }
  }

  void _onRtcEvent(RtcEngineEvent event) {
    if (!mounted) return;
    switch (event) {
      case RtcEngineEvent.tokenExpired:
        _renewToken();
        break;
      case RtcEngineEvent.disconnected:
        _showToast(_t(context, zhCN: 'RTC 连接断开', en: 'RTC disconnected'));
        break;
      case RtcEngineEvent.reconnecting:
        _showToast(_t(context, zhCN: '重连中…', en: 'Reconnecting…'));
        break;
      case RtcEngineEvent.reconnected:
        _showToast(_t(context, zhCN: '重连成功', en: 'Reconnected'));
        break;
      default:
        break;
    }
  }

  Future<void> _renewToken() async {
    if (_joinData == null) return;
    final svc = ref.read(meetingRoomServiceProvider);
    final no = widget.meetingNo;
    final id = widget.meetingId;
    final res = no != null && no.isNotEmpty
        ? await svc.joinRoom(no)
        : await svc.joinRoomById(id!);
    if (res.isSuccess && res.data != null) {
      await _rtc?.renewToken(res.data!.token);
    }
  }

  // ── 心跳 ──────────────────────────────────
  void _startHeartbeat(int intervalSec) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: intervalSec.clamp(5, 60)),
      (_) async {
        if (_joinData == null) return;
        await ref
            .read(meetingRoomServiceProvider)
            .heartbeat(_joinData!.meetingId);
      },
    );
  }

  // ── 过期监控 ──────────────────────────────
  void _startExpiryWatch(DateTime? expiresAt) {
    _expiryTimer?.cancel();
    if (expiresAt == null) return;
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) {
      _handleMeetingEnded();
      return;
    }
    _expiryTimer = Timer(diff, _handleMeetingEnded);
  }

  // ── 媒体控制 ──────────────────────────────
  Future<void> _toggleAudio() async {
    if (_audioToggling) return;
    if (_serverMutedAudio && _audioMuted) {
      _showToast(
          _t(context, zhCN: '主持人已将您静音', en: 'Muted by host'));
      return;
    }
    _audioToggling = true;
    try {
      await _rtc?.setAudioMuted(!_audioMuted);
    } finally {
      _audioToggling = false;
    }
  }

  Future<void> _toggleVideo() async {
    if (_videoToggling || !_isVideo) return;
    if (_serverMutedVideo && _videoMuted) {
      _showToast(_t(
          context, zhCN: '主持人已关闭您的摄像头', en: 'Camera disabled by host'));
      return;
    }
    _videoToggling = true;
    try {
      await _rtc?.setVideoMuted(!_videoMuted);
    } finally {
      _videoToggling = false;
    }
  }

  Future<void> _switchCamera() async => _rtc?.switchCamera();

  Future<void> _toggleSpeaker() async {
    setState(() => _speakerOn = !_speakerOn);
    await _rtc?.setSpeakerOn(_speakerOn);
  }

  Future<void> _toggleScreenShare() async {
    setState(() => _screenSharing = !_screenSharing);
    await _rtc?.setScreenSharing(_screenSharing);
  }

  // ── 主持人：静音成员 ──────────────────────
  // MeetingService.muteMember 签名：muteMember({meetingId, userId, muted})
  Future<void> _muteMember(MeetingParticipant p, bool mute) async {
    final svc = ref.read(meetingServiceProvider);
    final res = await svc.muteMember(
      meetingId: _joinData!.meetingId,
      targetUserId: p.userId,
      mutedAudio: mute,
    );
    if (!mounted) return;
    if (!res.isSuccess) {
      _showToast(res.message ??
          _t(context, zhCN: '操作失败', en: 'Operation failed'));
    }
  }

  // ── 主持人：踢出成员 ──────────────────────
  Future<void> _kickMember(MeetingParticipant p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t(context, zhCN: '踢出成员', en: 'Remove Member')),
        content: Text(_t(context,
            zhCN: '确认将 ${p.userName} 移出会议？',
            en: 'Remove ${p.userName} from meeting?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t(context, zhCN: '取消', en: 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_t(context, zhCN: '踢出', en: 'Remove'))),
        ],
      ),
    );
    if (ok != true) return;
    final svc = ref.read(meetingServiceProvider);
    final res = await svc.kickMember(
      meetingId: _joinData!.meetingId,
      targetUserId: p.userId,
    );
    if (!mounted) return;
    if (!res.isSuccess) {
      _showToast(res.message ??
          _t(context, zhCN: '踢出失败', en: 'Remove failed'));
    }
  }

  // ── 主持人：全员静音 ──────────────────────
  Future<void> _muteAll() async {
    if (_joinData == null) return;
    final svc = ref.read(meetingRoomServiceProvider);
    // 检查当前是否所有人都已静音，决定是禁音还是解禁
    final allMuted = _participants.every((p) => p.mutedAudio);
    final mute = !allMuted; // 有人未静音则全体禁音，否则全体解禁
    final res = await svc.muteAll(
      meetingNo: (_joinData!.meetingNo.isNotEmpty
          ? _joinData!.meetingNo
          : _joinData!.meetingId),
      muted: mute,
    );
    if (!mounted) return;
    if (res.isSuccess) {
      _showToast(mute
          ? _t(context, zhCN: '已全体禁音', en: 'All muted')
          : _t(context, zhCN: '已解除全体禁音', en: 'All unmuted'));
      _scheduleRefreshMembers();
    } else {
      _showToast(res.message.isNotEmpty ? res.message : '操作失败');
    }
  }

  // ── 结束会议（主持人）────────────────────
  Future<void> _endMeeting() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t(context, zhCN: '结束会议', en: 'End Meeting')),
        content: Text(
            _t(context, zhCN: '确认结束当前会议？', en: 'End this meeting?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t(context, zhCN: '取消', en: 'Cancel'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t(context, zhCN: '结束', en: 'End')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final svc = ref.read(meetingServiceProvider);
    await svc.endMeeting(_joinData!.meetingId);
    if (!mounted) return;
    _handleMeetingEnded();
  }

  // ── 离开会议（成员）──────────────────────
  Future<void> _leaveMeeting() async {
    if (_joinData == null) return;

    // 主持人：提供"离开"和"结束会议"两个选项
    if (_isHost) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(_t(context, zhCN: '离开或结束会议', en: 'Leave or End Meeting')),
          content: Text(_t(
            context,
            zhCN: '您是主持人，离开后会议将继续。如需结束会议，请点击"结束会议"。',
            en: 'You are the host. The meeting will continue if you leave. Tap "End Meeting" to close it for everyone.',
          )),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: Text(_t(context, zhCN: '取消', en: 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'leave'),
              child: Text(_t(context, zhCN: '仅离开', en: 'Leave')),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, 'end'),
              child: Text(_t(context, zhCN: '结束会议', en: 'End Meeting')),
            ),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;
      if (choice == 'end') {
        final svc = ref.read(meetingServiceProvider);
        await svc.endMeeting(_joinData!.meetingId);
        if (!mounted) return;
        _handleMeetingEnded();
        return;
      }
      // choice == 'leave'：主持人仅离开，不结束
      final svc = ref.read(meetingRoomServiceProvider);
      await svc.leaveRoom(_joinData!.meetingId);
      if (!mounted) return;
      _cleanupAndPop();
      return;
    }

    // 普通成员：确认离开
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t(context, zhCN: '离开会议', en: 'Leave Meeting')),
        content: Text(
            _t(context, zhCN: '确认离开当前会议？', en: 'Leave this meeting?')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(_t(context, zhCN: '取消', en: 'Cancel'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(_t(context, zhCN: '离开', en: 'Leave'))),
        ],
      ),
    );
    if (ok != true) return;
    final svc = ref.read(meetingRoomServiceProvider);
    await svc.leaveRoom(_joinData!.meetingId);
    if (!mounted) return;
    _cleanupAndPop();
  }

  void _handleMeetingEnded() {
    _cleanupAndPop();
    _showToast(_t(context, zhCN: '会议已结束', en: 'Meeting ended'));
  }

  void _cleanupAndPop() {
    _heartbeatTimer?.cancel();
    _expiryTimer?.cancel();
    _rtc?.dispose();
    ref.read(meetingSessionProvider.notifier).clear();
    if (mounted) Navigator.of(context).pop();
  }

  // ── 最小化 ────────────────────────────────
  void _minimize() {
    ref.read(meetingSessionProvider.notifier).setMinimized(true);
    Navigator.of(context).pop();
  }

  // ── 聊天 ──────────────────────────────────
  void _sendChat() {
    final text = _chatController.text.trim();
    if (text.isEmpty || _joinData == null) return;
    _chatController.clear();
    // 本地先显示（乐观更新）
    final myName = ref.read(authServiceProvider).user?.nickname ?? '';
    setState(() {
      _chatMessages.add(MeetingChatMessage(
        senderId: _myUserId,
        senderName: myName,
        content: text,
        time: DateTime.now(),
      ));
    });
    if (_showChat) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_chatScrollController.hasClients) return;
        _chatScrollController.jumpTo(
            _chatScrollController.position.maxScrollExtent);
      });
    }
    // 发送到服务器
    final svc = ref.read(meetingRoomServiceProvider);
    svc.sendChat(
      meetingNo: (_joinData!.meetingNo.isNotEmpty
          ? _joinData!.meetingNo
          : _joinData!.meetingId),
      content: text,
    ).then((res) {
      if (!res.isSuccess) {
        _showToast(res.message.isNotEmpty ? res.message : '发送失败');
      }
    });
  }

  // ── Toast ─────────────────────────────────
  void _showToast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_loading) return _buildLoading();
    if (_error != null) return _buildError();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        body: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildLoading() => const Scaffold(
        backgroundColor: Color(0xFF0D1117),
        body: Center(
            child: CircularProgressIndicator(color: Colors.white54)),
      );

  Widget _buildError() => Scaffold(
        backgroundColor: const Color(0xFF0D1117),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline,
                  color: Colors.white38, size: 48),
              const SizedBox(height: 12),
              Text(_error!,
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _init,
                child: Text(_t(context, zhCN: '重试', en: 'Retry')),
              ),
            ]),
          ),
        ),
      );

  Widget _buildBody() {
    return Stack(children: [
      Column(children: [
        _buildTopBar(),
        Expanded(child: _buildStage()),
        if (_showChat) _buildChatPanel(),
        _buildControlBar(),
      ]),
      if (_showMembers) _buildMembersOverlay(),
    ]);
  }

  // ── 顶部栏 ────────────────────────────────
  Widget _buildTopBar() {
    final d = _joinData;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.white, size: 28),
          onPressed: _minimize,
          tooltip: _t(context, zhCN: '最小化', en: 'Minimize'),
        ),
        Expanded(
          child: Column(children: [
            Text(
              d?.title ?? '',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              '${_t(context, zhCN: '会议号', en: 'No.')} ${d?.meetingNo ?? ''}',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ]),
        ),
        IconButton(
          icon: const Icon(Icons.people_outline_rounded,
              color: Colors.white70, size: 24),
          onPressed: () => setState(() => _showMembers = !_showMembers),
          tooltip: _t(context, zhCN: '成员', en: 'Members'),
        ),
      ]),
    );
  }

  // ── 主舞台 ────────────────────────────────
  Widget _buildStage() {
    final screenSharing = _rtc?.screenSharingIdentity;
    if (screenSharing != null) return _buildScreenShareView(screenSharing);
    if (_isVideo) return _buildVideoGrid();
    return _buildAudioView();
  }

  // ── 视频网格 ──────────────────────────────
  Widget _buildVideoGrid() {
    final remotes = _remoteIdentities;
    final total = 1 + remotes.length;

    if (total == 1) {
      return Center(child: _buildLocalTile(large: true));
    }
    if (total == 2) {
      return Stack(children: [
        Positioned.fill(child: _buildRemoteTile(remotes[0], large: true)),
        Positioned(
          right: 16,
          top: 16,
          width: 100,
          height: 140,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _buildLocalTile(large: false),
          ),
        ),
      ]);
    }
    return GridView.builder(
      padding: const EdgeInsets.all(4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: total <= 4 ? 2 : 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 3 / 4,
      ),
      itemCount: total,
      itemBuilder: (_, i) {
        if (i == 0) return _buildLocalTile(large: false);
        return _buildRemoteTile(remotes[i - 1], large: false);
      },
    );
  }

  Widget _buildLocalTile({required bool large}) {
    return Container(
      color: const Color(0xFF1C2333),
      child: Stack(fit: StackFit.expand, children: [
        if (!_videoMuted && _isVideo)
          _rtc?.buildLocalView() ?? const SizedBox()
        else
          const Center(
              child: Icon(Icons.person, color: Colors.white24, size: 56)),
        Positioned(
          left: 8,
          bottom: 8,
          child: _nameTag(
            _t(context, zhCN: '我', en: 'Me'),
            muted: _audioMuted,
          ),
        ),
      ]),
    );
  }

  Widget _buildRemoteTile(String identity, {required bool large}) {
    // 在参与者列表里匹配：LiveKit 用 userId，Agora 用 agoraUid
    final member = _participants.cast<MeetingParticipant?>().firstWhere(
          (p) =>
              p!.userId == identity ||
              p.agoraUid.toString() == identity,
          orElse: () => null,
        );

    final hasVideo = _isLiveKit
        ? _rtcState.remoteVideoUids.contains(identity.hashCode)
        : _rtcState.remoteVideoUids.contains(int.tryParse(identity) ?? -1);

    return Container(
      color: const Color(0xFF1C2333),
      child: Stack(fit: StackFit.expand, children: [
        if (hasVideo && _isVideo)
          _rtc?.buildRemoteView(identity) ?? const SizedBox()
        else
          Center(
            child: AvatarWidget(
              name: member?.userName ?? identity,
              avatar: member?.userAvatar,
              size: large ? 80 : 48,
            ),
          ),
        Positioned(
          left: 8,
          bottom: 8,
          child: _nameTag(
            member?.userName ?? identity,
            muted: member?.mutedAudio ?? false,
          ),
        ),
        if (member?.role == 'host')
          const Positioned(
            right: 8,
            top: 8,
            child:
                Icon(Icons.star_rounded, color: Colors.amber, size: 18),
          ),
      ]),
    );
  }

  // ── 音频视图（仅语音会议）────────────────
  Widget _buildAudioView() {
    final allItems = <Widget>[
      // 本地自己
      _buildAudioAvatar(
        name: _t(context, zhCN: '我', en: 'Me'),
        avatarUrl: null,
        muted: _audioMuted,
        isHost: _isHost,
      ),
      // 远端成员
      ..._participants.map((p) => _buildAudioAvatar(
            name: p.userName,
            avatarUrl: p.userAvatar,
            muted: p.mutedAudio,
            isHost: p.role == 'host',
          )),
    ];

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: allItems.length,
      itemBuilder: (_, i) => allItems[i],
    );
  }

  Widget _buildAudioAvatar({
    required String name,
    required String? avatarUrl,
    required bool muted,
    required bool isHost,
  }) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Stack(children: [
        AvatarWidget(name: name, avatar: avatarUrl, size: 60),
        if (isHost)
          const Positioned(
            right: 0,
            bottom: 0,
            child: Icon(Icons.star_rounded, color: Colors.amber, size: 16),
          ),
      ]),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        if (muted)
          const Padding(
            padding: EdgeInsets.only(right: 2),
            child: Icon(Icons.mic_off, color: Colors.redAccent, size: 12),
          ),
        Flexible(
          child: Text(name,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
      ]),
    ]);
  }

  // ── 屏幕共享视图 ──────────────────────────
  Widget _buildScreenShareView(String identity) {
    return Column(children: [
      Expanded(
        child: Container(
          color: Colors.black,
          child: _rtc?.buildRemoteView(identity) ?? const SizedBox(),
        ),
      ),
      Container(
        height: 90,
        color: const Color(0xFF1C2333),
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          children: [
            SizedBox(width: 64, child: _buildLocalTile(large: false)),
            ..._remoteIdentities.map((id) =>
                SizedBox(width: 64, child: _buildRemoteTile(id, large: false))),
          ],
        ),
      ),
    ]);
  }

  // ── 控制栏 ────────────────────────────────
  Widget _buildControlBar() {
    return Container(
      color: const Color(0xFF161B27),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _controlBtn(
            icon: _audioMuted
                ? Icons.mic_off_rounded
                : Icons.mic_rounded,
            label: _audioMuted
                ? _t(context, zhCN: '解除静音', en: 'Unmute')
                : _t(context, zhCN: '静音', en: 'Mute'),
            active: _audioMuted,
            onTap: _toggleAudio,
          ),
          if (_isVideo)
            _controlBtn(
              icon: _videoMuted
                  ? Icons.videocam_off_rounded
                  : Icons.videocam_rounded,
              label: _videoMuted
                  ? _t(context, zhCN: '开启视频', en: 'Start Video')
                  : _t(context, zhCN: '停止视频', en: 'Stop Video'),
              active: _videoMuted,
              onTap: _toggleVideo,
            ),
          _controlBtn(
            icon: Icons.chat_bubble_outline_rounded,
            label: _t(context, zhCN: '聊天', en: 'Chat'),
            highlight: _showChat,
            badge: (!_showChat && _unreadChat > 0) ? _unreadChat : null,
            onTap: () => setState(() {
              _showChat = !_showChat;
              if (_showChat) _unreadChat = 0;
            }),
          ),
          _controlBtn(
            icon: Icons.more_horiz_rounded,
            label: _t(context, zhCN: '更多', en: 'More'),
            onTap: _showMoreSheet,
          ),
          _controlBtn(
            icon: Icons.call_end_rounded,
            label: _isHost
                ? _t(context, zhCN: '结束', en: 'End')
                : _t(context, zhCN: '离开', en: 'Leave'),
            danger: true,
            onTap: _isHost ? _endMeeting : _leaveMeeting,
          ),
        ],
      ),
    );
  }

  Widget _controlBtn({
    required IconData icon,
    required String label,
    bool active = false,
    bool highlight = false,
    bool danger = false,
    int? badge,
    required VoidCallback onTap,
  }) {
    final Color iconColor = danger
        ? Colors.white
        : active
            ? Colors.redAccent
            : highlight
                ? AppColors.primary
                : Colors.white;
    final Color bg = danger
        ? Colors.redAccent
        : Colors.white.withOpacity(0.10);

    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          if (badge != null && badge > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                    color: Colors.redAccent, shape: BoxShape.circle),
                child: Text('$badge',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 9)),
              ),
            ),
        ]),
        const SizedBox(height: 4),
        Text(label,
            style:
                const TextStyle(color: Colors.white70, fontSize: 10)),
      ]),
    );
  }

  // ── 更多菜单 ──────────────────────────────
  void _showMoreSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C2333),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 4),
          _sheetItem(
            icon: _speakerOn
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
            label: _speakerOn
                ? _t(context, zhCN: '切换听筒', en: 'Switch to Earpiece')
                : _t(context,
                    zhCN: '切换扬声器', en: 'Switch to Speaker'),
            onTap: () { Navigator.pop(ctx); _toggleSpeaker(); },
          ),
          if (_isVideo)
            _sheetItem(
              icon: Icons.flip_camera_ios_rounded,
              label: _t(context, zhCN: '翻转摄像头', en: 'Flip Camera'),
              onTap: () { Navigator.pop(ctx); _switchCamera(); },
            ),
          _sheetItem(
            icon: _screenSharing
                ? Icons.stop_screen_share_rounded
                : Icons.screen_share_rounded,
            label: _screenSharing
                ? _t(context, zhCN: '停止投屏', en: 'Stop Sharing')
                : _t(context, zhCN: '开始投屏', en: 'Share Screen'),
            onTap: () { Navigator.pop(ctx); _toggleScreenShare(); },
          ),
          if (_isHost) ...[
            _sheetItem(
              icon: Icons.mic_off_rounded,
              label: _t(context, zhCN: '全员静音', en: 'Mute All'),
              onTap: () { Navigator.pop(ctx); _muteAll(); },
            ),
            _sheetItem(
              icon: Icons.settings_outlined,
              label: _t(context, zhCN: '会议设置', en: 'Settings'),
              onTap: () { Navigator.pop(ctx); _showSettingsSheet(); },
            ),
          ],
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  Widget _sheetItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }

  // ── 会议设置（主持人）────────────────────
  void _showSettingsSheet() {
    if (_joinData == null) return;
    // 使用 MeetingRoomSettings 实际字段：allowSelfUnmute / allowMemberVideo / hostOnlyInvite
    bool allowSelfUnmute = _joinData!.settings.allowSelfUnmute;
    bool allowMemberVideo = _joinData!.settings.allowMemberVideo;
    bool hostOnlyInvite = _joinData!.settings.hostOnlyInvite;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C2333),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 16),
            Text(
              _t(context, zhCN: '会议设置', en: 'Meeting Settings'),
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: Text(
                _t(context,
                    zhCN: '允许成员自行解除静音',
                    en: 'Allow self unmute'),
                style: const TextStyle(color: Colors.white),
              ),
              value: allowSelfUnmute,
              onChanged: (v) => setModal(() => allowSelfUnmute = v),
              activeColor: AppColors.primary,
            ),
            SwitchListTile(
              title: Text(
                _t(context,
                    zhCN: '允许成员开启视频',
                    en: 'Allow member video'),
                style: const TextStyle(color: Colors.white),
              ),
              value: allowMemberVideo,
              onChanged: (v) => setModal(() => allowMemberVideo = v),
              activeColor: AppColors.primary,
            ),
            SwitchListTile(
              title: Text(
                _t(context,
                    zhCN: '仅主持人可邀请', en: 'Host only invite'),
                style: const TextStyle(color: Colors.white),
              ),
              value: hostOnlyInvite,
              onChanged: (v) => setModal(() => hostOnlyInvite = v),
              activeColor: AppColors.primary,
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                          Navigator.pop(ctx);
                          final svc = ref.read(meetingRoomServiceProvider);
                          final meetingNo = _joinData!.meetingNo.isNotEmpty
                              ? _joinData!.meetingNo
                              : _joinData!.meetingId;
                          final res = await svc.updateSettings(
                            meetingNo: meetingNo,
                            allowSelfUnmute: allowSelfUnmute,
                            allowMemberVideo: allowMemberVideo,
                            hostOnlyInvite: hostOnlyInvite,
                          );
                          if (!mounted) return;
                          if (res.isSuccess) {
                            setState(() {
                              _joinData = _joinData!.copyWith(
                                settings: res.data ?? _joinData!.settings,
                              );
                            });
                            _showToast(_t(context,
                                zhCN: '设置已保存', en: 'Settings saved'));
                          } else {
                            _showToast(res.message.isNotEmpty
                                ? res.message
                                : _t(context,
                                    zhCN: '保存失败', en: 'Save failed'));
                          }
                        },
                  child: Text(_t(context, zhCN: '保存', en: 'Save')),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── 聊天面板 ──────────────────────────────
  Widget _buildChatPanel() {
    return Container(
      height: 260,
      decoration: const BoxDecoration(
        color: Color(0xFF161B27),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Text(
              _t(context, zhCN: '会议聊天', en: 'Meeting Chat'),
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => setState(() => _showChat = false),
              child: const Icon(Icons.close, color: Colors.white38, size: 18),
            ),
          ]),
        ),
        Expanded(
          child: _chatMessages.isEmpty
              ? Center(
                  child: Text(
                    _t(context,
                        zhCN: '暂无消息', en: 'No messages yet'),
                    style: const TextStyle(color: Colors.white24),
                  ),
                )
              : ListView.builder(
                  controller: _chatScrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: _chatMessages.length,
                  itemBuilder: (_, i) {
                    final m = _chatMessages[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: RichText(
                        text: TextSpan(children: [
                          TextSpan(
                            text: '${m.senderName}：',
                            style: TextStyle(
                                color: AppColors.primary,
                                fontSize: 13,
                                fontWeight: FontWeight.w600),
                          ),
                          TextSpan(
                            text: m.content,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 13),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _chatController,
                style:
                    const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: _t(context,
                      zhCN: '发送消息…', en: 'Send a message…'),
                  hintStyle:
                      const TextStyle(color: Colors.white38),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (_) => _sendChat(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send_rounded,
                  color: Colors.white70, size: 22),
              onPressed: _sendChat,
            ),
          ]),
        ),
      ]),
    );
  }

  // ── 成员面板（右侧滑出）──────────────────
  Widget _buildMembersOverlay() {
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _showMembers = false),
        child: Container(
          color: Colors.black54,
          child: Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: MediaQuery.sizeOf(context).width * 0.78,
                height: double.infinity,
                color: const Color(0xFF1C2333),
                child: SafeArea(
                  child: Column(children: [
                    // 面板标题
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                      child: Row(children: [
                        Text(
                          '${_t(context, zhCN: '成员', en: 'Members')} (${_participants.length + 1})',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white54),
                          onPressed: () =>
                              setState(() => _showMembers = false),
                        ),
                      ]),
                    ),
                    // 主持人操作按钮
                    if (_isHost)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(
                                  color: Colors.white24),
                            ),
                            icon: const Icon(Icons.mic_off, size: 16),
                            label: Text(_t(context,
                                zhCN: '全员静音', en: 'Mute All')),
                            onPressed: _muteAll,
                          ),
                        ),
                      ),
                    const Divider(color: Colors.white12, height: 1),
                    // 成员列表
                    Expanded(
                      child: ListView(children: [
                        // 自己排第一
                        _buildMemberRow(
                          MeetingParticipant(
                            userId: 'me',
                            agoraUid: _joinData?.agoraUid ?? 0,
                            userName:
                                _t(context, zhCN: '我', en: 'Me'),
                            userAvatar: null,
                            role: _isHost ? 'host' : 'member',
                            status: 'joined',
                            mutedAudio: _audioMuted,
                            mutedVideo: _videoMuted,
                          ),
                          isSelf: true,
                        ),
                        ..._participants.map((p) =>
                            _buildMemberRow(p, isSelf: false)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemberRow(MeetingParticipant p, {required bool isSelf}) {
    return ListTile(
      leading: AvatarWidget(
          name: p.userName, avatar: p.userAvatar, size: 40),
      title: Row(children: [
        Flexible(
          child: Text(p.userName,
              style: const TextStyle(color: Colors.white),
              overflow: TextOverflow.ellipsis),
        ),
        if (p.role == 'host')
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.18),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _t(context, zhCN: '主持人', en: 'Host'),
              style:
                  const TextStyle(color: Colors.amber, fontSize: 10),
            ),
          ),
        if (isSelf)
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              _t(context, zhCN: '我', en: 'Me'),
              style: const TextStyle(
                  color: Colors.white54, fontSize: 10),
            ),
          ),
      ]),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          p.mutedAudio ? Icons.mic_off : Icons.mic,
          color:
              p.mutedAudio ? Colors.redAccent : Colors.greenAccent,
          size: 18,
        ),
        if (_isHost && !isSelf && p.role != 'host') ...[
          const SizedBox(width: 4),
          PopupMenuButton<String>(
            color: const Color(0xFF2D3748),
            icon: const Icon(Icons.more_vert,
                color: Colors.white38, size: 18),
            onSelected: (v) {
              if (v == 'mute') _muteMember(p, !p.mutedAudio);
              if (v == 'kick') _kickMember(p);
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'mute',
                child: Text(
                  p.mutedAudio
                      ? _t(context,
                          zhCN: '解除静音', en: 'Unmute')
                      : _t(context, zhCN: '静音', en: 'Mute'),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              PopupMenuItem(
                value: 'kick',
                child: Text(
                  _t(context, zhCN: '踢出', en: 'Remove'),
                  style:
                      const TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ],
      ]),
    );
  }

  // ── 名牌标签 ──────────────────────────────
  Widget _nameTag(String name, {required bool muted}) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (muted)
          const Padding(
            padding: EdgeInsets.only(right: 3),
            child: Icon(Icons.mic_off,
                color: Colors.redAccent, size: 12),
          ),
        Flexible(
          child: Text(name,
              style: const TextStyle(
                  color: Colors.white, fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}
