import 'dart:async';
import 'web_document_stub.dart'
    if (dart.library.js_interop) 'web_document_web.dart';
import 'dart:convert';
import 'dart:math' show Random;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_io/io.dart' show HttpClient, Platform;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../background_service.dart';
import 'api_client.dart';
import 'auth_service.dart';

/// 获取当前设备类型
String _getDeviceType() {
  if (kIsWeb) return 'web';
  if (Platform.isAndroid) return 'android';
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  return 'unknown';
}

/// WebSocket 消息类型
class WSMessageType {
  static const String ping = 'ping';
  static const String pong = 'pong';
  static const String subscribe = 'subscribe';
  static const String unsubscribe = 'unsubscribe';
  static const String newMessage = 'new_message';
  static const String typing = 'typing';
  static const String read = 'read';
  static const String readReceipt = 'read_receipt';
  static const String messageRevoked = 'message_revoked';
  static const String messageEdited = 'message_edited';
  static const String onlineStatus = 'online_status';
  static const String reaction = 'reaction';
  static const String error = 'error';
  static const String memberMuteStatusChanged = 'member_mute_status_changed';
  static const String chatPermissionsUpdated = 'chat_permissions_updated';
  static const String systemAnnouncement = 'system_announcement';
  static const String chatAnnouncement = 'chat_announcement';
  static const String chatAnnouncementUpdated = 'chat_announcement_updated';
  static const String chatAnnouncementDeleted = 'chat_announcement_deleted';
  static const String messagePinned = 'message_pinned';
  static const String messageUnpinned = 'message_unpinned';
  static const String chatHistoryCleared = 'chat_history_cleared';
  static const String reconnected = 'reconnected'; // 客户端内部事件：重连成功
  static const String forceLogout = 'force_logout'; // 管理员强制下线本设备
  // 通话相关
  static const String online = 'online';
  static const String discoverItemsUpdated = 'discover_items_updated';
  static const String incomingCall = 'incoming_call';
  static const String callAccepted = 'call_accepted';
  static const String callRejected = 'call_rejected';
  static const String callEnded = 'call_ended';
  static const String callCancelled = 'call_cancelled';
  // 群会议相关
  static const String meetingInvite = 'meeting_invite';
  static const String meetingStarted = 'meeting_started';
  static const String meetingMemberJoined = 'meeting_member_joined';
  static const String meetingMemberLeft = 'meeting_member_left';
  static const String meetingEnded = 'meeting_ended';
  static const String meetingMemberMuted = 'meeting_member_muted';
  static const String meetingMemberKicked = 'meeting_member_kicked';
  static const String meetingHostChanged = 'meeting_host_changed';
  static const String meetingTitleUpdated = 'meeting_title_updated';
  static const String meetingJoinRequest = 'meeting_join_request';
  static const String meetingJoinRequestReviewed =
      'meeting_join_request_reviewed';
  // ── 会话相关 ──────────────────────────────────────────────────────────
  static const String newChat = 'new_chat';
  static const String chatUpdate = 'chat_update';
  static const String chatDeleted = 'chat_deleted';
  static const String chatLeft = 'chat_left';
  static const String chatHidden = 'chat_hidden';
  static const String userStatus = 'user_status';
  static const String readSync = 'read_sync';
  static const String joinApproved = 'join_approved';
  static const String joinRejected = 'join_rejected';
  static const String profileUpdated = 'profile_updated';
  // ── 朋友圈通知 ────────────────────────────────────────────────────────
  static const String momentLike = 'moment_like';
  static const String momentComment = 'moment_comment';
  static const String momentReply = 'moment_reply';
  // ── 钱包通知 ──────────────────────────────────────────────────────────
  static const String redPacketClaimed = 'red_packet_claimed';
  static const String transferAccepted = 'transfer_accepted';
}

/// WebSocket 消息
class WSMessage {
  final String type;
  final int? seq;
  final dynamic data;

  WSMessage({required this.type, this.seq, this.data});

  factory WSMessage.fromJson(Map<String, dynamic> json) {
    return WSMessage(
      type: json['type'] ?? '',
      seq: json['seq'],
      data: json['data'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      if (seq != null) 'seq': seq,
      if (data != null) 'data': data,
    };
  }

  String toJsonString() => jsonEncode(toJson());
}

/// 旧连接代际已失效
///
/// 用于快速中止旧连接的异步回调链路，避免污染当前有效连接状态。
class _StaleConnectionAttempt implements Exception {
  const _StaleConnectionAttempt();
}

/// WebSocket 连接状态
enum WSConnectionState { disconnected, connecting, connected, reconnecting }

/// WebSocket 服务 - 高级连接管理
///
/// 特性:
/// - 使用 Completer 防止并发连接
/// - 指数退避重连策略
/// - 消息队列和自动重发
/// - 生命周期感知
/// - 网络状态感知（自动重连）
class WebSocketService extends StateNotifier<WSConnectionState>
    with WidgetsBindingObserver {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _pongTimeoutTimer;
  Timer? _countdownTimer;
  Timer? _resumeRetryTimer;

  /// 网络能力变化防抖：避免 WiFi/蜂窝切换或「假连接」时频繁探测
  Timer? _connectivityHealDebounce;

  /// Android 常见：WiFi 一直显示「已连接」但曾无外网，能力流不经历 none；
  /// WS 已断或卡在退避时，任意一次有网能力抖动也应触发补连（防抖合并）。
  Timer? _networkUpReconnectDebounce;
  Timer? _reconnectMonitorTimer;
  // Web 端 visibilitychange 回调引用（用于 removeEventListener）
  dynamic _webVisibilityCallback;

  int _reconnectAttempts = 0;
  int _reconnectCountdown = 0; // 距下次重连的倒计时（秒）
  int _seq = 0;
  int _latencyMs = 0;
  int _pongTimeoutCount = 0;
  int _resumePingTimeoutCount = 0;
  int _connectionGeneration = 0;
  int _activeConnectionGeneration = 0;
  bool _hasConnectedOnce = false;

  bool _waitingForPong = false;
  // 是否已释放
  bool _isDisposed = false;
  bool _isNetworkAvailable = true;
  bool _handlingBackgroundKeepAlive = false;

  DateTime? _lastPongTime;
  DateTime? _lastPingTime;
  DateTime? _lastConnectedAt;
  DateTime? _lastForceReconnectAt;
  String? _token;
  String? _deviceType;
  VoidCallback? _removeBackgroundKeepAliveHandler;
  // 使用 Completer 防止并发连接
  Completer<void>? _connectCompleter;

  // 网络状态监听
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  // 消息处理器 (支持多个 handler)
  final Map<String, List<Function(dynamic)>> _handlers = {};
  // 消息流控制器
  final _messageController = StreamController<WSMessage>.broadcast();
  // 消息队列：断线时缓存待发送消息，重连后自动发送
  final List<WSMessage> _messageQueue = [];
  final Set<String> _subscribedChatIds = {};
  final Map<String, (String, Function(dynamic))> _handlerIdMap = {};

  static const int _maxQueueSize = 500;
  // Handler ID 计数器
  int _handlerIdCounter = 0;

  Stream<WSMessage> get messageStream => _messageController.stream;
  int get latencyMs => _latencyMs;
  WSConnectionState get connectionState => state;
  bool _isWithinWindow(DateTime? time, Duration window) {
    if (time == null) return false;
    return DateTime.now().difference(time) < window;
  }

  bool _shouldThrottleForceReconnect({
    Duration minInterval = const Duration(seconds: 12),
  }) {
    if (_isWithinWindow(_lastForceReconnectAt, minInterval)) {
      return true;
    }

    if (state == WSConnectionState.connected &&
        _isWithinWindow(_lastConnectedAt, const Duration(seconds: 6))) {
      return true;
    }

    return false;
  }

  Future<void> _forceReconnectIfAllowed(
    String reason, {
    Duration minInterval = const Duration(seconds: 12),
  }) async {
    if (_isDisposed || _token == null) return;

    if (_connectCompleter != null) {
      if (kDebugMode) debugPrint('[WS] Skip force reconnect ($reason), connect in progress');
      return;
    }

    if (_shouldThrottleForceReconnect(minInterval: minInterval)) {
      if (kDebugMode) debugPrint('[WS] Skip force reconnect ($reason), within cooldown');
      return;
    }

    _lastForceReconnectAt = DateTime.now();
    if (kDebugMode) debugPrint('[WS] Force reconnect: $reason');
    await _triggerForceReconnect();
  }

  /// 距下次重连的倒计时秒数（供 UI 展示）
  int get nextRetrySeconds => _reconnectCountdown;

  /// 当前重连次数（供 UI 展示）
  int get reconnectAttempts => _reconnectAttempts;

  /// 连接状态描述文字（供 UI 直接使用）
  String get connectionStatusMessage {
    switch (state) {
      case WSConnectionState.disconnected:
        return '网络连接已断开';
      case WSConnectionState.connecting:
        return '正在连接...';
      case WSConnectionState.reconnecting:
        if (!_isNetworkAvailable) {
          return _reconnectCountdown > 0
              ? '网络不可用，$_reconnectCountdown 秒后重试（第 $_reconnectAttempts 次）'
              : '网络不可用，正在重试...';
        }
        return _reconnectCountdown > 0
            ? '连接中断，$_reconnectCountdown 秒后重试（第 $_reconnectAttempts 次）'
            : '正在重连...';
      case WSConnectionState.connected:
        return '已连接';
    }
  }

  WebSocketService() : super(WSConnectionState.disconnected) {
    WidgetsBinding.instance.addObserver(this);
    _setupNetworkListener();
    if (!kIsWeb && Platform.isAndroid) {
      _removeBackgroundKeepAliveHandler = BackgroundService.instance
          .addKeepAliveHandler(_onBackgroundKeepAlive);
    }
    // Web 端：监听 document.visibilitychange 补偿 AppLifecycle 不可靠问题
    if (kIsWeb) {
      _setupWebVisibilityListener();
    }
  }

  /// Web 端页面可见性监听（补偿 AppLifecycleState 在浏览器中不可靠的问题）
  ///
  /// 切换 Tab / 最小化浏览器 → hidden；回到页面 → visible
  /// visible 时触发重连检查和心跳恢复，与原生 resumed 逻辑保持一致
  void _setupWebVisibilityListener() {
    // 使用 dart:js_interop 注册 visibilitychange 事件
    // 避免引入 dart:html，与项目已有的 package:web 迁移方向一致
    try {
      _webVisibilityCallback = () {
        _onWebVisibilityChanged();
      };
      webAddEventListener('visibilitychange', _webVisibilityCallback);
      if (kDebugMode) debugPrint('[WS] Web visibilitychange listener registered');
    } catch (e) {
      if (kDebugMode) debugPrint('[WS] Failed to register visibilitychange: $e');
    }
  }

  /// 页面可见性变化处理
  void _onWebVisibilityChanged() {
    if (_isDisposed || _token == null) return;
    try {
      final hidden = webDocumentHidden();
      if (kDebugMode) debugPrint('[WS] Web visibility changed: hidden=$hidden');
      if (!hidden) {
        // 页面重新可见：等同于 resumed，检查连接并恢复心跳
        if (kDebugMode) debugPrint('[WS] Web page visible again, checking connection...');
        _checkAndReconnect();
        unawaited(_nudgeReconnectIfConnectivityOnline());
      } else {
        // 页面隐藏：等同于 paused，切换为低频心跳
        _startBackgroundPing();
        if (state == WSConnectionState.connected) {
          _lastPongTime = DateTime.now();
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[WS] visibilitychange handler error: $e');
    }
  }

  /// 设置网络状态监听
  void _setupNetworkListener() {
    _networkSubscription = _connectivity.onConnectivityChanged.listen((
      results,
    ) {
      final wasAvailable = _isNetworkAvailable;
      _isNetworkAvailable =
          results.isNotEmpty && !results.contains(ConnectivityResult.none);

      if (kDebugMode) debugPrint(
        '[WS] Network status: available=$_isNetworkAvailable (was=$wasAvailable), results=$results',
      );

      if (_token == null) return;

      if (!_isNetworkAvailable) {
        if (_hasConnectedOnce && state != WSConnectionState.connecting) {
          if (kDebugMode) debugPrint('[WS] Network lost, entering reconnect mode...');
          unawaited(_enterReconnectMode());
        }
        return;
      }

      // 明确从无网恢复：立刻换新连接
      if (!wasAvailable) {
        if (kDebugMode) debugPrint('[WS] Network restored from offline, force reconnect...');
        _networkUpReconnectDebounce?.cancel();
        _networkUpReconnectDebounce = null;
        _reconnectAttempts = 0;
        unawaited(
          _forceReconnectIfAllowed(
            'network restored from offline',
            minInterval: const Duration(seconds: 5),
          ),
        );
        return;
      }

      // 一直显示「有网」但曾无外网时，能力流可能不经过 none；若 WS 未连上，
      // 任意 WiFi↔蜂窝等事件都应取消退避并再试（防抖，避免事件风暴）。
      if (state == WSConnectionState.disconnected ||
          state == WSConnectionState.reconnecting) {
        _debounceReconnectWhileDisconnected();
      } else if (state == WSConnectionState.connected) {
        _scheduleConnectivityHeal();
      }
    });
  }

  void _debounceReconnectWhileDisconnected() {
    _networkUpReconnectDebounce?.cancel();
    _networkUpReconnectDebounce = Timer(const Duration(milliseconds: 600), () {
      _networkUpReconnectDebounce = null;
      if (_isDisposed || _token == null || !_isNetworkAvailable) return;
      if (state == WSConnectionState.connected ||
          state == WSConnectionState.connecting) {
        return;
      }

      if (_connectCompleter != null) {
        if (kDebugMode) debugPrint(
          '[WS] Connectivity event while WS offline -> connect already in progress, skip',
        );
        return;
      }

      if (kDebugMode) debugPrint(
        '[WS] Connectivity event while WS offline -> debounced force reconnect',
      );
      _reconnectAttempts = 0;

      if (state == WSConnectionState.disconnected ||
          (state == WSConnectionState.reconnecting &&
              _reconnectTimer != null)) {
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _countdownTimer?.cancel();
        _countdownTimer = null;
        _reconnectCountdown = 0;
        unawaited(
          connect(_token!, deviceType: _deviceType, isReconnectAttempt: true),
        );
        return;
      }

      unawaited(
        _forceReconnectIfAllowed(
          'connectivity event while offline',
          minInterval: const Duration(seconds: 5),
        ),
      );
    });
  }

  /// 在「有网」前提下，根据当前 WS 状态做一次恢复尝试（防抖合并短时间内的多次事件）
  void _scheduleConnectivityHeal() {
    _connectivityHealDebounce?.cancel();
    _connectivityHealDebounce = Timer(const Duration(milliseconds: 400), () {
      _connectivityHealDebounce = null;
      if (_isDisposed || _token == null || !_isNetworkAvailable) return;

      if (state == WSConnectionState.connected) {
        if (kDebugMode) debugPrint(
          '[WS] Connectivity changed while connected, verify + resume ping',
        );
        unawaited(_verifyTransportAfterConnectivityChange());
      } else if (state == WSConnectionState.disconnected) {
        if (kDebugMode) debugPrint(
          '[WS] Connectivity event while disconnected, retrying connect',
        );
        _reconnectAttempts = 0;
        unawaited(
          connect(_token!, deviceType: _deviceType, isReconnectAttempt: true),
        );
      }
    });
  }

  /// WiFi 重连后系统仍可能把 WS 留在「已连接」僵尸态；先短时探测 API 是否可达再决定 ping 或强杀重连。
  Future<void> _verifyTransportAfterConnectivityChange() async {
    if (_isDisposed || state != WSConnectionState.connected) return;
    if (kIsWeb) {
      _sendResumePing();
      return;
    }

    final ok = await _quickProbeApiReachable();
    if (_isDisposed || state != WSConnectionState.connected) return;

    if (!ok) {
      if (kDebugMode) debugPrint(
        '[WS] API host unreachable while WS still connected -> force reconnect',
      );
      await _forceReconnectIfAllowed(
        'api probe failed after connectivity change',
      );
      return;
    }

    _sendResumePing();
  }

  Future<bool> _quickProbeApiReachable() async {
    HttpClient? client;
    try {
      client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 4);
      final uri = Uri.parse(ApiConfig.serverUrl);
      final req = await client.getUrl(uri);
      final res = await req.close().timeout(const Duration(seconds: 4));
      await res.drain();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[WS] quick API probe failed: $e');
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  /// 判断传入代际是否仍然是当前有效连接代际。
  bool _isCurrentConnectionGeneration(int generation) {
    return generation == _activeConnectionGeneration;
  }

  /// 开启新的连接代际
  ///
  /// 旧代际之后全部视为失效，只允许最新代际继续推进连接流程。
  int _startConnectionGeneration() {
    _activeConnectionGeneration = ++_connectionGeneration;
    return _activeConnectionGeneration;
  }

  /// 作废当前连接代际
  ///
  /// 用于 force reconnect / disconnect 时提前让旧连接回调失效，
  /// 同时释放仍在等待的 connect completer。
  void _invalidateActiveConnection() {
    _activeConnectionGeneration = ++_connectionGeneration;
    final completer = _connectCompleter;
    _connectCompleter = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  /// 关闭指定 channel。
  ///
  /// 用于安全收尾旧连接，避免关闭动作抛错中断重连链路。
  Future<void> _closeChannel(WebSocketChannel? channel) async {
    if (channel == null) return;
    try {
      await channel.sink.close().timeout(const Duration(seconds: 2));
    } catch (e) {
      if (kDebugMode) debugPrint('[WS] Error closing channel: $e');
    }
  }

  /// 取消所有重连相关计时器。
  void _cancelReconnectSchedule() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _reconnectCountdown = 0;
    _reconnectMonitorTimer?.cancel();
    _reconnectMonitorTimer = null;
  }

  /// 强制重连
  ///
  /// 与旧实现不同：这里会先让当前连接代际失效，再断开旧连接，
  /// 确保新的重连尝试不会被旧连接回调污染。
  Future<void> _triggerForceReconnect() async {
    if (_isDisposed) return;
    _invalidateActiveConnection();
    final token = _token;
    final deviceType = _deviceType;
    state = WSConnectionState.reconnecting;
    await _disconnectInternal(preserveRecoveringState: true);
    _reconnectAttempts = 0;
    if (token != null) {
      await connect(token, deviceType: deviceType, isReconnectAttempt: true);
    }
  }

  /// 进入重连模式，但不立即发起新连接。
  ///
  /// 主要用于“已知断网”场景：先断开旧连接，再走统一的指数退避调度。
  Future<void> _enterReconnectMode() async {
    if (_isDisposed || _token == null) return;
    if (state == WSConnectionState.reconnecting && _reconnectTimer != null) {
      return;
    }

    _invalidateActiveConnection();
    await _disconnectInternal(preserveRecoveringState: true);
    _scheduleReconnect();
  }

  /// 应用生命周期变化
  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (kDebugMode) debugPrint('[WS] App lifecycle changed: $lifecycleState');

    if (lifecycleState == AppLifecycleState.resumed) {
      if (state == WSConnectionState.connected) {
        // resumed 时立即发一次 ping，重置服务端 ReadDeadline
        send(WSMessage(type: WSMessageType.ping));
        _startPing();
      }
      _checkAndReconnect();
      unawaited(_nudgeReconnectIfConnectivityOnline());
    } else if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.hidden) {
      _startBackgroundPing();
      if (state == WSConnectionState.connected) {
        _lastPongTime = DateTime.now();
      }
    }
  }

  /// 检查并重新连接
  void _checkAndReconnect() {
    if (_token == null) return;

    // 正在连接中：跳过（已有进行中的连接尝试）
    if (state == WSConnectionState.connecting) return;

    // 正在退避重连：取消退避 timer，立即重连（用户已回到页面/前台）
    if (state == WSConnectionState.reconnecting) {
      if (_reconnectTimer != null) {
        if (kDebugMode) debugPrint('[WS] Visible/Resumed: cancel backoff timer, reconnect now');
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _reconnectCountdown = 0;
        _reconnectAttempts = 0;
        unawaited(
          connect(_token!, deviceType: _deviceType, isReconnectAttempt: true),
        );
      }
      return;
    }

    if (state == WSConnectionState.disconnected) {
      if (kDebugMode) debugPrint('[WS] Reconnecting after resume...');
      _reconnectAttempts = 0;
      unawaited(
        connect(_token!, deviceType: _deviceType, isReconnectAttempt: true),
      );
    } else if (state == WSConnectionState.connected && !_waitingForPong) {
      _sendResumePing();
    }
  }

  /// 回到前台时主动拉一次系统网络状态：后台已恢复网络但能力流未再推送时补连。
  Future<void> _nudgeReconnectIfConnectivityOnline() async {
    if (_isDisposed || _token == null) return;
    try {
      final results = await _connectivity.checkConnectivity();
      final ok =
          results.isNotEmpty && !results.contains(ConnectivityResult.none);
      if (!ok) return;
      if (state == WSConnectionState.disconnected) {
        if (kDebugMode) debugPrint(
          '[WS] Resume snapshot: online but WS disconnected -> reconnect',
        );
        _reconnectTimer?.cancel();
        _reconnectAttempts = 0;
        await connect(
          _token!,
          deviceType: _deviceType,
          isReconnectAttempt: true,
        );
      } else if (state == WSConnectionState.reconnecting &&
          _reconnectTimer == null &&
          _connectCompleter == null) {
        if (kDebugMode) debugPrint(
          '[WS] Resume snapshot: reconnecting without active timer -> retry connect',
        );
        _reconnectAttempts = 0;
        await connect(
          _token!,
          deviceType: _deviceType,
          isReconnectAttempt: true,
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[WS] checkConnectivity on resume failed: $e');
    }
  }

  /// Resume 时发送一次性探测 ping，单次超时即重连（比常规心跳更激进）
  void _sendResumePing() {
    if (_isDisposed || state != WSConnectionState.connected) return;
    if (_waitingForPong &&
        _lastPingTime != null &&
        DateTime.now().difference(_lastPingTime!) <
            const Duration(seconds: 8)) {
      if (kDebugMode) debugPrint('[WS] Resume ping skipped, ping already in flight');
      return;
    }

    _waitingForPong = true;
    _lastPingTime = DateTime.now();
    send(WSMessage(type: WSMessageType.ping));

    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = Timer(const Duration(seconds: 8), () {
      if (_isDisposed) return;
      if (_waitingForPong) {
        unawaited(_handleResumePingTimeout());
      }
    });
  }

  /// 发送带超时的 ping（常规心跳，连续 3 次超时才重连）
  Future<void> _handleResumePingTimeout() async {
    if (_isDisposed ||
        state != WSConnectionState.connected ||
        !_waitingForPong) {
      return;
    }

    _resumePingTimeoutCount++;
    if (_resumePingTimeoutCount == 1) {
      if (kDebugMode) debugPrint('[WS] Resume ping timed out once, retrying before reconnect');

      final apiReachable = kIsWeb ? true : await _quickProbeApiReachable();
      if (_isDisposed ||
          state != WSConnectionState.connected ||
          !_waitingForPong) {
        return;
      }

      if (!apiReachable) {
        _resumePingTimeoutCount = 0;
        await _forceReconnectIfAllowed(
          'resume ping timeout and api probe failed',
        );
        return;
      }

      _resumeRetryTimer?.cancel();
      _resumeRetryTimer = Timer(const Duration(seconds: 2), () {
        _resumeRetryTimer = null;
        if (_isDisposed ||
            state != WSConnectionState.connected ||
            !_waitingForPong) {
          return;
        }
        _sendResumePing();
      });
      return;
    }

    if (kDebugMode) debugPrint('[WS] Resume ping timed out twice, reconnecting');
    _resumePingTimeoutCount = 0;
    await _forceReconnectIfAllowed('resume ping timed out twice');
  }

  void _sendPingWithTimeout() {
    if (_isDisposed) return;
    _waitingForPong = true;
    _lastPingTime = DateTime.now();
    send(WSMessage(type: WSMessageType.ping));

    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (_isDisposed) return;
      if (_waitingForPong) {
        _pongTimeoutCount++;
        if (kDebugMode) debugPrint('[WS] Pong timeout (count: $_pongTimeoutCount/3)');

        if (_pongTimeoutCount >= 3) {
          if (kDebugMode) debugPrint('[WS] Too many pong timeouts, reconnecting...');
          _pongTimeoutCount = 0;
          unawaited(_forceReconnectIfAllowed('pong timeout limit reached'));
        }
      }
    });
  }

  /// HTTP 层刷新 JWT 后调用：WS URL 里的 token 必须同步，否则服务端可能仍校验旧 JWT 导致收不到推送。
  void applyRefreshedHttpToken(String token) {
    if (_isDisposed || token.isEmpty) return;
    if (kDebugMode) debugPrint('[WS] applyRefreshedHttpToken -> force reconnect');
    _token = token;
    _reconnectAttempts = 0;
    unawaited(_triggerForceReconnect());
  }

  /// 后台模式下的心跳（更频繁）
  void _startBackgroundPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isDisposed) {
        _pingTimer?.cancel();
        return;
      }
      if (state == WSConnectionState.connected) {
        send(WSMessage(type: WSMessageType.ping));
      }
    });
  }

  Future<void> _onBackgroundKeepAlive() async {
    if (_isDisposed || _token == null || _handlingBackgroundKeepAlive) return;
    _handlingBackgroundKeepAlive = true;

    try {
      if (state == WSConnectionState.connected) {
        final now = DateTime.now();
        final lastPong = _lastPongTime;
        final lastPing = _lastPingTime;

        if (_waitingForPong &&
            lastPing != null &&
            now.difference(lastPing).inSeconds > 20) {
          if (kDebugMode) debugPrint('[WS] Background keepAlive: pong timeout, reconnecting');
          _pongTimeoutCount = 0;
          await _forceReconnectIfAllowed('background keepalive pong timeout');
          return;
        }

        if (lastPong != null && now.difference(lastPong).inSeconds > 45) {
          if (kDebugMode) debugPrint(
            '[WS] Background keepAlive: stale connection, reconnecting',
          );
          await _forceReconnectIfAllowed(
            'background keepalive stale transport',
          );
          return;
        }

        if (!_waitingForPong) {
          if (kDebugMode) debugPrint('[WS] Background keepAlive: ping');
          _sendPingWithTimeout();
        }
        return;
      }

      if (state == WSConnectionState.disconnected) {
        if (kDebugMode) debugPrint('[WS] Background keepAlive: disconnected, reconnecting');
        _reconnectAttempts = 0;
        await connect(
          _token!,
          deviceType: _deviceType,
          isReconnectAttempt: true,
        );
        return;
      }

      if (state == WSConnectionState.reconnecting && _reconnectTimer == null) {
        if (kDebugMode) debugPrint(
          '[WS] Background keepAlive: reconnect timer missing, retrying',
        );
        _reconnectAttempts = 0;
        await _forceReconnectIfAllowed(
          'background keepalive missing reconnect timer',
          minInterval: const Duration(seconds: 5),
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[WS] Background keepAlive error: $e');
    } finally {
      _handlingBackgroundKeepAlive = false;
    }
  }

  /// 连接（使用 Completer 防止并发连接）
  ///
  /// 新增参数 `isReconnectAttempt`：
  /// - `false` 表示首次连接
  /// - `true` 表示重连流程，成功后派发 `reconnected`
  Future<void> connect(
    String token, {
    String? deviceType,
    bool isReconnectAttempt = false,
  }) async {
    if (_isDisposed) return;

    deviceType ??= _getDeviceType();
    final effectiveReconnectAttempt =
        isReconnectAttempt || state == WSConnectionState.reconnecting;
    if (kDebugMode) debugPrint('[WS] connect() called, current state: $state');

    _token = token;
    _deviceType = deviceType;

    if (_connectCompleter != null) {
      if (kDebugMode) debugPrint('[WS] Connection in progress, waiting...');
      return _connectCompleter!.future;
    }

    if (state == WSConnectionState.connected && _channel != null) {
      if (kDebugMode) debugPrint('[WS] Already connected');
      return;
    }

    final completer = Completer<void>();
    final generation = _startConnectionGeneration();
    _cancelReconnectSchedule();
    _waitingForPong = false;
    _lastPingTime = null;
    _pongTimeoutCount = 0;
    _connectCompleter = completer;
    state = effectiveReconnectAttempt
        ? WSConnectionState.reconnecting
        : WSConnectionState.connecting;

    try {
      await _doConnect(
        token,
        deviceType,
        generation: generation,
        isReconnectAttempt: effectiveReconnectAttempt,
      );
      if (_connectCompleter == completer && !completer.isCompleted) {
        completer.complete();
      }
    } on _StaleConnectionAttempt {
      if (_connectCompleter == completer && !completer.isCompleted) {
        completer.complete();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[WS] Connection error: $e');
      if (_isCurrentConnectionGeneration(generation)) {
        state = effectiveReconnectAttempt
            ? WSConnectionState.reconnecting
            : WSConnectionState.disconnected;
        if (_connectCompleter == completer && !completer.isCompleted) {
          completer.completeError(e);
        }
        _scheduleReconnect();
      } else if (_connectCompleter == completer && !completer.isCompleted) {
        completer.complete();
      }
    } finally {
      if (_connectCompleter == completer) {
        _connectCompleter = null;
      }
    }
  }

  /// 执行实际连接
  ///
  /// 与旧实现相比，这里把 onMessage / onError / onDone 全部绑定到当前连接代际，
  /// 旧连接的异步回调会被直接丢弃。
  Future<void> _doConnect(
    String token,
    String deviceType, {
    required int generation,
    required bool isReconnectAttempt,
  }) async {
    final encodedToken = Uri.encodeQueryComponent(token);
    final wsUrl =
        '${ApiConfig.wsUrl}?device_type=$deviceType&token=$encodedToken';
    if (kDebugMode) debugPrint('[WS] Connecting to: ${ApiConfig.wsUrl}');

    WebSocketChannel? channel;
    StreamSubscription? subscription;

    try {
      channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      if (!_isCurrentConnectionGeneration(generation)) {
        throw const _StaleConnectionAttempt();
      }
      _channel = channel;

      await channel.ready.timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('WebSocket connection timeout');
        },
      );

      if (!_isCurrentConnectionGeneration(generation) ||
          !identical(_channel, channel)) {
        throw const _StaleConnectionAttempt();
      }

      subscription = channel.stream.listen(
        (rawData) => _onMessage(rawData, generation),
        onError: (error) => _onError(error, generation),
        onDone: () => _onDone(generation),
        cancelOnError: false,
      );

      if (!_isCurrentConnectionGeneration(generation) ||
          !identical(_channel, channel)) {
        throw const _StaleConnectionAttempt();
      }
      _subscription = subscription;

      state = WSConnectionState.connected;
      _reconnectAttempts = 0;
      _reconnectCountdown = 0;
      _countdownTimer?.cancel();
      _countdownTimer = null;
      _lastPongTime = DateTime.now();
      _lastConnectedAt = _lastPongTime;
      _waitingForPong = false;
      _lastPingTime = null;
      _pongTimeoutCount = 0;
      _resumePingTimeoutCount = 0;

      _startPing();

      if (Platform.isAndroid) {
        BackgroundService.instance.start();
      }

      if (kDebugMode) debugPrint('[WS] Connected successfully');
      _networkUpReconnectDebounce?.cancel();
      _networkUpReconnectDebounce = null;
      _flushMessageQueue();
      if (_subscribedChatIds.isNotEmpty) {
        if (kDebugMode) debugPrint('[WS] Re-subscribing to ${_subscribedChatIds.length} chats');
        subscribeChats(_subscribedChatIds.toList());
      }
      if (isReconnectAttempt) {
        _hasConnectedOnce = true;
        _dispatchReconnected();
      } else {
        _hasConnectedOnce = true;
      }
    } on TimeoutException catch (e) {
      if (kDebugMode) debugPrint('[WS] Connection timeout: $e');
      if (_isCurrentConnectionGeneration(generation)) {
        if (identical(_channel, channel)) {
          _channel = null;
        }
        if (identical(_subscription, subscription)) {
          _subscription = null;
        }
      }
      await subscription?.cancel();
      await _closeChannel(channel);
      rethrow;
    } catch (e) {
      if (e is _StaleConnectionAttempt) {
        await subscription?.cancel();
        await _closeChannel(channel);
        rethrow;
      }
      if (kDebugMode) debugPrint('[WS] Connection error: $e');
      if (_isCurrentConnectionGeneration(generation)) {
        if (identical(_channel, channel)) {
          _channel = null;
        }
        if (identical(_subscription, subscription)) {
          _subscription = null;
        }
      }
      await subscription?.cancel();
      await _closeChannel(channel);
      rethrow;
    }
  }

  /// 断开连接
  ///
  /// logout 时调用，同时清除 token 防止旧连接关闭回调再次触发重连。
  Future<void> disconnect({bool clearToken = false}) async {
    await _disconnectInternal(
      clearToken: clearToken,
      invalidateActiveConnection: true,
    );
  }

  /// 内部断开实现
  ///
  /// `invalidateActiveConnection=true` 时，会先让当前连接代际失效，
  /// 这样旧连接的 onDone / onError 就不会再影响当前状态。
  Future<void> _disconnectInternal({
    bool clearToken = false,
    bool invalidateActiveConnection = false,
    bool preserveRecoveringState = false,
  }) async {
    if (invalidateActiveConnection) {
      _invalidateActiveConnection();
    }
    if (clearToken) {
      _token = null;
      _reconnectAttempts = 0;
      _hasConnectedOnce = false;
      _lastConnectedAt = null;
      _lastForceReconnectAt = null;
      _messageQueue.clear();
      _subscribedChatIds.clear();
    }

    _cancelAllTimers();
    _waitingForPong = false;
    _lastPingTime = null;
    _lastPongTime = null;
    _pongTimeoutCount = 0;
    _resumePingTimeoutCount = 0;

    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();

    final channel = _channel;
    _channel = null;
    await _closeChannel(channel);

    if (!_isDisposed) {
      if (preserveRecoveringState && _token != null) {
        state = WSConnectionState.reconnecting;
      } else {
        state = WSConnectionState.disconnected;
      }
    }
    if (kDebugMode) debugPrint('[WS] Disconnected (clearToken=$clearToken)');
  }

  /// 取消所有定时器
  void _cancelAllTimers() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = null;
    _resumeRetryTimer?.cancel();
    _resumeRetryTimer = null;
    _cancelReconnectSchedule();
    _connectivityHealDebounce?.cancel();
    _connectivityHealDebounce = null;
    _networkUpReconnectDebounce?.cancel();
    _networkUpReconnectDebounce = null;
  }

  /// 发送消息（断线时加入队列，重连后自动发送）
  /// 返回是否发送成功
  bool send(WSMessage message, {bool queueIfDisconnected = true}) {
    if (_isDisposed) return false;

    message = WSMessage(type: message.type, seq: ++_seq, data: message.data);

    if (state != WSConnectionState.connected) {
      if (queueIfDisconnected &&
          message.type != WSMessageType.ping &&
          message.type != WSMessageType.pong) {
        _enqueueMessage(message);
      }
      return false;
    }

    return _sendMessage(message);
  }

  /// 将消息加入队列
  void _enqueueMessage(WSMessage message) {
    if (_messageQueue.length < _maxQueueSize) {
      _messageQueue.add(message);
      if (kDebugMode) debugPrint(
        '[WS] Queued message: ${message.type} (queue: ${_messageQueue.length})',
      );
    } else {
      if (kDebugMode) debugPrint('[WS] Queue full, dropping: ${message.type}');
    }
  }

  /// 发送单条消息（带错误处理）
  bool _sendMessage(WSMessage message) {
    try {
      _channel?.sink.add(message.toJsonString());
      if (kDebugMode) debugPrint('[WS] Sent: ${message.type}');
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[WS] Send error: $e');
      _enqueueMessage(message);
      return false;
    }
  }

  /// 清空消息队列（重连成功后调用）
  void _flushMessageQueue() {
    if (_messageQueue.isEmpty) return;
    if (kDebugMode) debugPrint('[WS] Flushing ${_messageQueue.length} queued messages');

    final messages = List<WSMessage>.from(_messageQueue);
    _messageQueue.clear();

    for (int i = 0; i < messages.length; i++) {
      if (state != WSConnectionState.connected) {
        _messageQueue.addAll(messages.sublist(i));
        break;
      }
      _sendMessage(messages[i]);
    }
  }

  /// 广播重连事件（内部调用，触发增量同步）
  void _dispatchReconnected() {
    if (_handlers.containsKey(WSMessageType.reconnected)) {
      final handlerList = List<Function(dynamic)>.from(
        _handlers[WSMessageType.reconnected]!,
      );
      if (kDebugMode) debugPrint(
        '[WS] Dispatching reconnected to ${handlerList.length} handlers',
      );
      for (final handler in handlerList) {
        try {
          handler({});
        } catch (e) {
          if (kDebugMode) debugPrint('[WS] Reconnected handler error: $e');
        }
      }
    }
  }

  // 记录已订阅的 chatIds，重连后自动重订阅
  /// 订阅会话
  void subscribeChats(List<String> chatIds) {
    _subscribedChatIds.addAll(chatIds);
    send(WSMessage(type: WSMessageType.subscribe, data: {'chat_ids': chatIds}));
  }

  /// 取消订阅会话
  void unsubscribeChats(List<String> chatIds) {
    _subscribedChatIds.removeAll(chatIds);
    send(
      WSMessage(type: WSMessageType.unsubscribe, data: {'chat_ids': chatIds}),
    );
  }

  /// 发送正在输入状态
  void sendTyping(String chatId, {bool isTyping = true}) {
    send(
      WSMessage(
        type: WSMessageType.typing,
        data: {'chat_id': chatId, 'action': isTyping ? 'start' : 'stop'},
      ),
    );
  }

  /// 发送已读回执
  void sendReadReceipt(String chatId, int msgSeq) {
    send(
      WSMessage(
        type: WSMessageType.read,
        data: {'chat_id': chatId, 'msg_seq': msgSeq},
      ),
    );
  }

  /// 查询在线状态
  void queryOnlineStatus(List<String> userIds) {
    send(WSMessage(type: WSMessageType.online, data: {'user_ids': userIds}));
  }

  /// 注册消息处理器 (支持多个 handler)，返回唯一 ID 用于取消注册
  String registerHandler(String type, Function(dynamic) handler) {
    _handlers.putIfAbsent(type, () => []);
    _handlers[type]!.add(handler);

    final id = '${type}_${++_handlerIdCounter}';
    _handlerIdMap[id] = (type, handler);
    return id;
  }

  /// 通过 ID 取消注册处理器
  void unregisterHandler(String handlerId) {
    final entry = _handlerIdMap.remove(handlerId);
    if (entry != null) {
      final (type, handler) = entry;
      _handlers[type]?.remove(handler);
    }
  }

  /// 移除所有指定类型的处理器
  void removeHandler(String type) {
    _handlers.remove(type);
    // 清理 ID 映射
    _handlerIdMap.removeWhere((id, entry) => entry.$1 == type);
  }

  /// 检查是否有指定类型的处理器
  bool hasHandler(String type) {
    return _handlers.containsKey(type) && _handlers[type]!.isNotEmpty;
  }

  /// 移除特定处理器
  void removeSpecificHandler(String type, Function(dynamic) handler) {
    _handlers[type]?.remove(handler);
    // 清理 ID 映射
    _handlerIdMap.removeWhere(
      (id, entry) => entry.$1 == type && entry.$2 == handler,
    );
  }

  /// 处理收到的消息
  ///
  /// 仅处理当前有效连接代际的消息；旧连接到达的消息直接丢弃。
  void _onMessage(dynamic rawData, int generation) {
    if (_isDisposed || !_isCurrentConnectionGeneration(generation)) return;

    try {
      if (rawData is! String) {
        if (kDebugMode) debugPrint('[WS] Ignoring non-string message: ${rawData.runtimeType}');
        return;
      }

      final json = jsonDecode(rawData) as Map<String, dynamic>;
      final type = json['type'] as String? ?? '';

      if (kDebugMode) debugPrint('[WS] Received: $type');

      // 构建消息对象
      final message = WSMessage(
        type: type,
        seq: json['seq'] as int?,
        data: json, // 传递整个 json，让 handler 自己解析
      );

      // 触发流（检查控制器是否已关闭）
      if (!_messageController.isClosed) {
        _messageController.add(message);
      }

      // 调用所有处理器 - 传递整个 json
      // 注意：创建副本以防止遍历时被修改导致并发修改异常
      if (_handlers.containsKey(type)) {
        final handlerList = List<Function(dynamic)>.from(_handlers[type]!);
        if (kDebugMode) debugPrint('[WS] Dispatching $type to ${handlerList.length} handlers');
        for (final handler in handlerList) {
          try {
            handler(json);
          } catch (e) {
            if (kDebugMode) debugPrint('[WS] Handler error for $type: $e');
          }
        }
      } else {
        if (kDebugMode) debugPrint('[WS] No handlers registered for type: $type');
      }

      // 处理 pong
      if (type == WSMessageType.pong) {
        _waitingForPong = false;
        _lastPongTime = DateTime.now();
        if (_lastPingTime != null) {
          _latencyMs = _lastPongTime!.difference(_lastPingTime!).inMilliseconds;
        }
        _pongTimeoutCount = 0;
        _resumePingTimeoutCount = 0;
        _pongTimeoutTimer?.cancel();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[WS] Parse error: $e');
    }
  }

  /// 处理连接错误（onerror）
  ///
  /// 仅当前有效连接代际可以触发重连；旧连接错误直接丢弃。
  void _onError(dynamic error, int generation) {
    if (!_isCurrentConnectionGeneration(generation)) return;
    if (kDebugMode) debugPrint('[WS] Connection error: $error');
    if (_isDisposed) return;
    _cancelAllTimers();
    _subscription = null;
    _channel = null;
    _scheduleReconnect();
  }

  /// 处理连接关闭（onclose）
  ///
  /// 仅当前有效连接代际可以触发状态切换；旧连接关闭直接丢弃。
  void _onDone(int generation) {
    if (!_isCurrentConnectionGeneration(generation)) return;

    // 尝试读取 WebSocket 关闭码与原因，便于排查服务端主动断连
    final closeCode = _channel?.closeCode;
    final closeReason = _channel?.closeReason;
    if (kDebugMode) debugPrint(
      '[WS] Connection closed'
      '${closeCode != null ? ", code=$closeCode" : ""}'
      '${closeReason != null && closeReason.isNotEmpty ? ", reason=$closeReason" : ""}',
    );

    if (_isDisposed) return;
    _pingTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _subscription = null;
    _channel = null;

    _scheduleReconnect();
  }

  /// 启动心跳（前台模式）
  void _startPing() {
    _pingTimer?.cancel();
    _pongTimeoutCount = 0;
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (_isDisposed) {
        _pingTimer?.cancel();
        return;
      }
      if (state == WSConnectionState.connected) {
        _sendPingWithTimeout();
      }
    });
  }

  /// 计划重连（指数退避 + 随机抖动，防止服务端重启后多设备同时砸连接）
  void _scheduleReconnect() {
    if (_isDisposed) return;
    if (_reconnectTimer != null) return;

    if (_reconnectAttempts >= 30) {
      if (kDebugMode) debugPrint(
        '[WS] Max reconnect attempts reached, switching to monitor mode',
      );
      state = WSConnectionState.disconnected;
      _startReconnectMonitor();
      return;
    }

    if (_token == null) return;

    state = WSConnectionState.reconnecting;

    // 第1次断线立即重连（1秒），后续指数退避，最长60秒
    final base = _reconnectAttempts == 0
        ? 1
        : (2 << (_reconnectAttempts - 1)).clamp(2, 60);
    final jitter = _reconnectAttempts == 0 ? 0 : Random().nextInt(5);
    final delaySecs = base + jitter;
    _reconnectAttempts++;

    if (kDebugMode) debugPrint(
      '[WS] Reconnecting in ${delaySecs}s '
      '(attempt $_reconnectAttempts, base=${base}s, jitter=+${jitter}s)',
    );

    _startCountdown(delaySecs);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySecs), () {
      _reconnectTimer = null;
      if (_isDisposed) return;
      if (_token != null) {
        unawaited(
          connect(_token!, deviceType: _deviceType, isReconnectAttempt: true),
        );
      }
    });
  }

  /// 启动倒计时，每秒递减，供 UI 展示"X 秒后重试"
  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    _reconnectCountdown = seconds;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_isDisposed) {
        t.cancel();
        _reconnectCountdown = 0;
        return;
      }
      if (_reconnectCountdown <= 0) {
        t.cancel();
        return;
      }
      _reconnectCountdown--;
    });
  }

  /// 开启后台重连监控（当达到最大重连次数后，周期性再试，避免长时间假死）
  void _startReconnectMonitor() {
    _reconnectMonitorTimer?.cancel();
    _reconnectMonitorTimer = Timer.periodic(const Duration(seconds: 45), (
      timer,
    ) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }

      if (state == WSConnectionState.connected) {
        timer.cancel();
        return;
      }

      if (_token != null &&
          (state == WSConnectionState.disconnected ||
              state == WSConnectionState.reconnecting)) {
        if (kDebugMode) debugPrint('[WS] Reconnect monitor: attempting reconnect...');
        _reconnectAttempts = 0;
        unawaited(_triggerForceReconnect());
      }
    });
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    if (kDebugMode) debugPrint('[WS] Disposing WebSocket service');

    WidgetsBinding.instance.removeObserver(this);
    _removeBackgroundKeepAliveHandler?.call();
    _removeBackgroundKeepAliveHandler = null;
    _networkSubscription?.cancel();
    _networkSubscription = null;
    // Web 端：清理 visibilitychange 监听
    if (kIsWeb && _webVisibilityCallback != null) {
      try {
        // ignore: undefined_prefixed_name
        webRemoveEventListener(
          'visibilitychange',
          _webVisibilityCallback!,
        );
      } catch (_) {}
      _webVisibilityCallback = null;
    }

    _cancelAllTimers();
    disconnect();
    _messageController.close();
    _handlers.clear();
    _handlerIdMap.clear();
    _messageQueue.clear();

    super.dispose();
  }
}

/// Provider
final webSocketServiceProvider =
    StateNotifierProvider<WebSocketService, WSConnectionState>((ref) {
  final ws = WebSocketService();

  // 初始检查当前状态
  final initialState = ref.read(authServiceProvider);
  if (kDebugMode) debugPrint(
    '[WS Provider] Initial auth state: ${initialState.status}, hasToken: ${initialState.token != null}',
  );

  if (initialState.status == AuthStatus.authenticated &&
      initialState.token != null) {
    Future.microtask(() {
      if (kDebugMode) debugPrint('[WS Provider] Initial connect...');
      ws.connect(initialState.token!);
    });
  }

  // 监听后续认证状态变化
  ref.listen<AuthState>(authServiceProvider, (previous, next) {
    if (kDebugMode) debugPrint(
      '[WS Provider] Auth state changed: ${previous?.status} -> ${next.status}',
    );
    if (next.status == AuthStatus.authenticated && next.token != null) {
      if (ws.connectionState != WSConnectionState.connected &&
          ws.connectionState != WSConnectionState.connecting) {
        if (kDebugMode) debugPrint('[WS Provider] Connecting due to auth change...');
        ws.connect(next.token!);
      }
    } else if (previous?.status == AuthStatus.authenticated &&
        next.status != AuthStatus.authenticated) {
      // logout 时清除 token，防止 _onDone 用旧 token 重连
      ws.disconnect(clearToken: true);
    }
  });

  ref.onDispose(() {
    ws.dispose();
  });

  return ws;
});
