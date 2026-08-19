// 文件用途：管理 WebSocket 连接、重连、心跳以及实时事件分发。
// 核心逻辑：维护实时连接、心跳和指数退避重连，把服务端事件去重后分发给聊天、通知和会话同步模块。
import 'dart:async';
import 'dart:convert';
import 'dart:math' show Random;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:universal_io/io.dart' show HttpClient, Platform;
import 'package:web_socket_channel/web_socket_channel.dart';

import '../background_service.dart';
import '../background_keep_alive_policy.dart';
import '../account_session_coordinator.dart';
import '../../i18n/app_localizations.dart';
import '../../utils/platform_utils.dart';
import 'api_client.dart';
import 'auth_service.dart';
import 'endpoint_manager.dart';

String _websocketText({
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

// 关键声明：WebSocket 服务以连接代际和状态机保护并发连接，旧连接回调不得修改当前连接状态。
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
  static const String delivered = 'delivered';
  static const String messageDelivered = 'message_delivered';
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
  static const String newDeviceLogin = 'new_device_login';
  // 通话相关
  static const String online = 'online';
  static const String discoverItemsUpdated = 'discover_items_updated';
  static const String systemSettingsUpdated = 'system_settings_updated';
  static const String incomingCall = 'incoming_call';
  static const String callAccepted = 'call_accepted';
  static const String callRejected = 'call_rejected';
  static const String callEnded = 'call_ended';
  static const String callCancelled = 'call_cancelled';
  static const String callReleased = 'call_released';
  static const String callMediaChanged = 'call_media_changed';
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

typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);
typedef WebSocketReadyWaiter = Future<void> Function(
  WebSocketChannel channel,
);

/// WebSocket 服务 - 高级连接管理
///
/// 特性:
/// - 使用 Completer 防止并发连接
/// - 指数退避重连策略
/// - 消息队列和自动重发
/// - 生命周期感知
/// - 网络状态感知（自动重连）
///
/// 此服务只保证连接与事件分发，不保存聊天业务真相；消息缺口最终由 HTTP 增量同步补齐。
class WebSocketService extends StateNotifier<WSConnectionState>
    with WidgetsBindingObserver {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  Timer? _pongTimeoutTimer;
  // 后台保活自持检查器：主 isolate 自己周期触发 _onBackgroundKeepAlive。
  // 不依赖 flutter_background_service 的跨 isolate keepAlive 事件（该事件在
  // 系统调度暂停、后台服务被部分回收时可能丢失），提高息屏/短后台的保活可靠性。
  Timer? _backgroundKeepAliveTimer;
  Timer? _countdownTimer;
  Timer? _resumeRetryTimer;

  /// 网络能力变化防抖：避免 WiFi/蜂窝切换或「假连接」时频繁探测
  Timer? _connectivityHealDebounce;

  /// Android 常见：WiFi 一直显示「已连接」但曾无外网，能力流不经历 none；
  /// WS 已断或卡在退避时，任意一次有网能力抖动也应触发补连（防抖合并）。
  Timer? _networkUpReconnectDebounce;
  Timer? _reconnectMonitorTimer;

  int _reconnectAttempts = 0;
  int _reconnectCountdown = 0; // 距下次重连的倒计时（秒）
  int _seq = 0;
  int _latencyMs = 0;
  int _pongTimeoutCount = 0;
  int _resumePingTimeoutCount = 0;
  // 每次建立或强制断开都会推进代次，只有当前代次可以更新连接状态或派发业务事件。
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
  DateTime? _enteredBackgroundAt;
  DateTime? _lastBackgroundPingAt;
  DateTime? _lastBackgroundReconnectAt;
  String? _token;
  String? _deviceType;
  VoidCallback? _removeBackgroundKeepAliveHandler;
  int _backgroundFastReconnects = 0;
  // 使用 Completer 防止并发连接
  Completer<void>? _connectCompleter;
  // 强制重连断开旧传输期间，阻止认证监听并发创建新连接。
  Completer<void>? _reconnectTransitionCompleter;

  final WebSocketChannelFactory _channelFactory;
  final WebSocketReadyWaiter _readyWaiter;

  // 网络状态监听
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  // 消息处理器 (支持多个 handler)
  final Map<String, List<Function(dynamic)>> _handlers = {};
  // 消息流控制器
  final _messageController = StreamController<WSMessage>.broadcast();
  // 消息队列：仅缓存可丢弃的实时控制消息；业务消息可靠发送仍由 HTTP/离线队列负责。
  // 断线时缓存待发送消息，重连后自动发送
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

  BackgroundKeepAliveProfile get _keepAliveProfile =>
      BackgroundKeepAlivePolicyStore.instance.profile;

  bool get _isInBackground => _enteredBackgroundAt != null;

  Duration get _backgroundElapsed {
    final entered = _enteredBackgroundAt;
    if (entered == null) return Duration.zero;
    return DateTime.now().difference(entered);
  }

  bool get _isLongBackground =>
      _isInBackground &&
      _backgroundElapsed >= _keepAliveProfile.shortBackgroundWindow;

  Duration get _effectiveBackgroundPingInterval {
    final profile = _keepAliveProfile;
    return _isLongBackground
        ? profile.longBackgroundPingInterval
        : profile.backgroundPingInterval;
  }

  Duration get _backgroundReconnectCooldown {
    if (!_isInBackground) return Duration.zero;
    final profile = _keepAliveProfile;
    if (_isLongBackground ||
        _backgroundFastReconnects >= profile.maxBackgroundFastReconnects) {
      return profile.longBackgroundReconnectMinInterval;
    }
    return profile.backgroundReconnectMinInterval;
  }

  bool _markBackgroundReconnectAllowed(String reason) {
    if (!_isInBackground) return true;
    final cooldown = _backgroundReconnectCooldown;
    final now = DateTime.now();
    final last = _lastBackgroundReconnectAt;
    if (last != null && now.difference(last) < cooldown) {
      debugPrint(
        '[WS] Background reconnect skipped ($reason), cooldown=${cooldown.inSeconds}s',
      );
      return false;
    }

    _lastBackgroundReconnectAt = now;
    _backgroundFastReconnects++;
    return true;
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
      debugPrint('[WS] Skip force reconnect ($reason), connect in progress');
      return;
    }

    if (_shouldThrottleForceReconnect(minInterval: minInterval)) {
      debugPrint('[WS] Skip force reconnect ($reason), within cooldown');
      return;
    }

    _lastForceReconnectAt = DateTime.now();
    debugPrint('[WS] Force reconnect: $reason');
    await _triggerForceReconnect();
  }

  /// 距下次重连的倒计时秒数（供 UI 展示）
  int get nextRetrySeconds => _reconnectCountdown;

  /// 当前重连次数（供 UI 展示）
  int get reconnectAttempts => _reconnectAttempts;

  Future<bool> ensureConnectedForRealtime({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_isDisposed) return false;
    if (state == WSConnectionState.connected) return true;

    final token = _token;
    if (token == null || token.isEmpty) return false;

    if (_connectCompleter == null) {
      if (state == WSConnectionState.disconnected) {
        unawaited(connect(token, deviceType: _deviceType));
      } else if (state == WSConnectionState.reconnecting) {
        _cancelReconnectSchedule();
        _reconnectAttempts = 0;
        unawaited(
          connect(token, deviceType: _deviceType, isReconnectAttempt: true),
        );
      }
    }

    final deadline = DateTime.now().add(timeout);
    while (!_isDisposed && DateTime.now().isBefore(deadline)) {
      if (state == WSConnectionState.connected) return true;
      await Future.delayed(const Duration(milliseconds: 120));
      if (_connectCompleter == null &&
          state == WSConnectionState.reconnecting &&
          _reconnectTimer != null) {
        _cancelReconnectSchedule();
        _reconnectAttempts = 0;
        unawaited(
          connect(token, deviceType: _deviceType, isReconnectAttempt: true),
        );
      }
    }
    return state == WSConnectionState.connected;
  }

  /// 连接状态描述文字（供 UI 直接使用）
  String get connectionStatusMessage {
    switch (state) {
      case WSConnectionState.disconnected:
        return _websocketText(
          zhCN: '网络连接已断开',
          zhTW: '網路連線已中斷',
          en: 'Network connection lost',
        );
      case WSConnectionState.connecting:
        return _websocketText(
          zhCN: '正在连接...',
          zhTW: '正在連線...',
          en: 'Connecting...',
        );
      case WSConnectionState.reconnecting:
        if (!_isNetworkAvailable) {
          return _reconnectCountdown > 0
              ? _websocketText(
                  zhCN:
                      '网络不可用，$_reconnectCountdown 秒后重试（第 $_reconnectAttempts 次）',
                  zhTW:
                      '網路不可用，$_reconnectCountdown 秒後重試（第 $_reconnectAttempts 次）',
                  en: 'Network unavailable. Retrying in $_reconnectCountdown s (attempt $_reconnectAttempts)',
                )
              : _websocketText(
                  zhCN: '网络不可用，正在重试...',
                  zhTW: '網路不可用，正在重試...',
                  en: 'Network unavailable. Retrying...',
                );
        }
        return _reconnectCountdown > 0
            ? _websocketText(
                zhCN: '连接中断，$_reconnectCountdown 秒后重试（第 $_reconnectAttempts 次）',
                zhTW: '連線中斷，$_reconnectCountdown 秒後重試（第 $_reconnectAttempts 次）',
                en: 'Connection interrupted. Retrying in $_reconnectCountdown s (attempt $_reconnectAttempts)',
              )
            : _websocketText(
                zhCN: '正在重连...',
                zhTW: '正在重新連線...',
                en: 'Reconnecting...',
              );
      case WSConnectionState.connected:
        return _websocketText(
          zhCN: '已连接',
          zhTW: '已連線',
          en: 'Connected',
        );
    }
  }

  WebSocketService({
    WebSocketChannelFactory? channelFactory,
    WebSocketReadyWaiter? readyWaiter,
  })  : _channelFactory = channelFactory ?? WebSocketChannel.connect,
        _readyWaiter = readyWaiter ?? ((channel) => channel.ready),
        super(WSConnectionState.disconnected) {
    WidgetsBinding.instance.addObserver(this);
    _setupNetworkListener();
    if (!kIsWeb && Platform.isAndroid) {
      _removeBackgroundKeepAliveHandler = BackgroundService.instance
          .addKeepAliveHandler(_onBackgroundKeepAlive);
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

      debugPrint(
        '[WS] Network status: available=$_isNetworkAvailable (was=$wasAvailable), results=$results',
      );

      if (_token == null) return;

      if (!_isNetworkAvailable) {
        if (_hasConnectedOnce && state != WSConnectionState.connecting) {
          debugPrint('[WS] Network lost, entering reconnect mode...');
          unawaited(_enterReconnectMode());
        }
        return;
      }

      // 明确从无网恢复：立刻换新连接
      if (!wasAvailable) {
        debugPrint('[WS] Network restored from offline, force reconnect...');
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
        debugPrint(
          '[WS] Connectivity event while WS offline -> connect already in progress, skip',
        );
        return;
      }

      debugPrint(
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
        debugPrint(
          '[WS] Connectivity changed while connected, verify + resume ping',
        );
        unawaited(_verifyTransportAfterConnectivityChange());
      } else if (state == WSConnectionState.disconnected) {
        debugPrint(
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
      debugPrint(
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
      debugPrint('[WS] quick API probe failed: $e');
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
      debugPrint('[WS] Error closing channel: $e');
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

    final activeTransition = _reconnectTransitionCompleter;
    if (activeTransition != null) {
      await activeTransition.future;
      return;
    }

    final transition = Completer<void>();
    _reconnectTransitionCompleter = transition;
    final deviceType = _deviceType;
    try {
      _invalidateActiveConnection();
      state = WSConnectionState.reconnecting;
      await _disconnectInternal(preserveRecoveringState: true);
    } finally {
      if (_reconnectTransitionCompleter == transition) {
        _reconnectTransitionCompleter = null;
      }
      if (!transition.isCompleted) {
        transition.complete();
      }
    }

    _reconnectAttempts = 0;
    final token = _token;
    if (!_isDisposed && token != null) {
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
    debugPrint('[WS] App lifecycle changed: $lifecycleState');

    if (lifecycleState == AppLifecycleState.resumed) {
      _enteredBackgroundAt = null;
      _lastBackgroundPingAt = null;
      _lastBackgroundReconnectAt = null;
      _backgroundFastReconnects = 0;
      _backgroundKeepAliveTimer?.cancel();
      _backgroundKeepAliveTimer = null;
      unawaited(BackgroundKeepAlivePolicyStore.instance.load().then((mode) {
        BackgroundService.instance.applyPolicy(mode);
      }));
      if (state == WSConnectionState.connected) {
        _startPing();
      }
      _checkAndReconnect();
      unawaited(_nudgeReconnectIfConnectivityOnline());
    } else if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.hidden) {
      _enteredBackgroundAt ??= DateTime.now();
      if (!kIsWeb && Platform.isIOS) {
        _pingTimer?.cancel();
        _pingTimer = null;
        _pongTimeoutTimer?.cancel();
        _pongTimeoutTimer = null;
        debugPrint('[WS] iOS background: pause websocket heartbeat');
        return;
      }
      BackgroundService.instance.applyPolicy(
        BackgroundKeepAlivePolicyStore.instance.mode,
      );
      _startBackgroundPing();
      // 主 isolate 自持后台保活：WebSocket 在息屏/短后台自行周期性检查并重连，
      // 不依赖 flutter_background_service 的 keepAlive 事件桥。
      _startBackgroundKeepAliveSelfCheck();
      if (state == WSConnectionState.connected) {
        _lastPongTime = DateTime.now();
      }
    }
  }

  /// 检查并重新连接
  void _checkAndReconnect() {
    if (_token == null) return;
    if (state == WSConnectionState.reconnecting ||
        state == WSConnectionState.connecting) {
      return;
    }

    if (state == WSConnectionState.disconnected) {
      debugPrint('[WS] Reconnecting after resume...');
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
        debugPrint(
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
        debugPrint(
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
      debugPrint('[WS] checkConnectivity on resume failed: $e');
    }
  }

  /// Resume 时发送一次性探测 ping，单次超时即重连（比常规心跳更激进）
  void _sendResumePing() {
    if (_isDisposed || state != WSConnectionState.connected) return;
    if (_waitingForPong &&
        _lastPingTime != null &&
        DateTime.now().difference(_lastPingTime!) <
            const Duration(seconds: 8)) {
      debugPrint('[WS] Resume ping skipped, ping already in flight');
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
      debugPrint('[WS] Resume ping timed out once, retrying before reconnect');

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

    debugPrint('[WS] Resume ping timed out twice, reconnecting');
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
        debugPrint('[WS] Pong timeout (count: $_pongTimeoutCount/3)');

        if (_pongTimeoutCount >= 3) {
          debugPrint('[WS] Too many pong timeouts, reconnecting...');
          _pongTimeoutCount = 0;
          unawaited(_forceReconnectIfAllowed('pong timeout limit reached'));
        }
      }
    });
  }

  /// HTTP 层刷新 JWT 后调用：WS URL 里的 token 必须同步，否则服务端可能仍校验旧 JWT 导致收不到推送。
  void applyRefreshedHttpToken(String token) {
    if (_isDisposed || token.isEmpty) return;
    debugPrint('[WS] applyRefreshedHttpToken -> force reconnect');
    _token = token;
    _reconnectAttempts = 0;
    unawaited(_triggerForceReconnect());
  }

  /// 后台模式下的心跳（更频繁）
  void _startBackgroundPing() {
    _pingTimer?.cancel();
    final tickInterval = _keepAliveProfile.backgroundPingInterval;
    _pingTimer = Timer.periodic(tickInterval, (_) {
      if (_isDisposed) {
        _pingTimer?.cancel();
        return;
      }
      _maybeSendBackgroundPing('background timer');
    });
  }

  /// 主 isolate 自持后台保活自检：息屏/短后台由本 isolate 自己周期触发
  /// [_onBackgroundKeepAlive]，用它内部既有的 stale/pong 超时、断连重连与冷却
  /// 逻辑。这与 flutter_background_service 的跨 isolate `keepAlive` 事件互为
  /// 兜底 —— 即使后台服务心跳因系统调度暂停、进程调度异常没有派发事件，只要
  /// App 进程还在，WebSocket 也会按增强策略自行维持连接。
  void _startBackgroundKeepAliveSelfCheck() {
    _backgroundKeepAliveTimer?.cancel();
    _backgroundKeepAliveTimer = Timer.periodic(
      _keepAliveProfile.backgroundPingInterval,
      (_) {
        if (_isDisposed) {
          _backgroundKeepAliveTimer?.cancel();
          _backgroundKeepAliveTimer = null;
          return;
        }
        unawaited(_onBackgroundKeepAlive());
      },
    );
  }

  void _maybeSendBackgroundPing(String reason) {
    if (_isDisposed || state != WSConnectionState.connected) return;

    final now = DateTime.now();
    final interval = _effectiveBackgroundPingInterval;
    final lastPing = _lastBackgroundPingAt;
    if (lastPing != null && now.difference(lastPing) < interval) {
      return;
    }

    _lastBackgroundPingAt = now;
    debugPrint(
      '[WS] Background ping ($reason), interval=${interval.inSeconds}s, '
      'elapsed=${_backgroundElapsed.inSeconds}s',
    );
    _sendPingWithTimeout();
  }

  Future<void> _forceBackgroundReconnect(String reason) async {
    final minInterval = _backgroundReconnectCooldown;
    if (!_markBackgroundReconnectAllowed(reason)) return;
    await _forceReconnectIfAllowed(
      reason,
      minInterval: minInterval == Duration.zero
          ? const Duration(seconds: 12)
          : minInterval,
    );
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
            now.difference(lastPing) > _keepAliveProfile.pongTimeoutThreshold) {
          debugPrint('[WS] Background keepAlive: pong timeout, reconnecting');
          _pongTimeoutCount = 0;
          await _forceBackgroundReconnect('background keepalive pong timeout');
          return;
        }

        final staleThreshold = _isLongBackground
            ? _keepAliveProfile.longBackgroundStaleTransportThreshold
            : _keepAliveProfile.staleTransportThreshold;
        if (lastPong != null && now.difference(lastPong) > staleThreshold) {
          debugPrint(
            '[WS] Background keepAlive: stale connection, reconnecting',
          );
          await _forceBackgroundReconnect(
            'background keepalive stale transport',
          );
          return;
        }

        if (!_waitingForPong) {
          _maybeSendBackgroundPing('foreground service keepAlive');
        }
        return;
      }

      if (state == WSConnectionState.disconnected) {
        if (!_markBackgroundReconnectAllowed('background disconnected')) {
          return;
        }
        debugPrint('[WS] Background keepAlive: disconnected, reconnecting');
        await connect(
          _token!,
          deviceType: _deviceType,
          isReconnectAttempt: true,
        );
        return;
      }

      if (state == WSConnectionState.reconnecting && _reconnectTimer == null) {
        debugPrint(
          '[WS] Background keepAlive: reconnect timer missing, retrying',
        );
        await _forceBackgroundReconnect(
          'background keepalive missing reconnect timer',
        );
      }
    } catch (e) {
      debugPrint('[WS] Background keepAlive error: $e');
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

    final reconnectTransition = _reconnectTransitionCompleter;
    if (reconnectTransition != null) {
      debugPrint('[WS] Waiting for force reconnect transition...');
      await reconnectTransition.future;
      if (_isDisposed) return;
      token = _token ?? token;
      deviceType ??= _deviceType;
    }

    deviceType ??= _getDeviceType();
    final effectiveReconnectAttempt =
        isReconnectAttempt || state == WSConnectionState.reconnecting;
    debugPrint('[WS] connect() called, current state: $state');

    _token = token;
    _deviceType = deviceType;

    // 并发调用者复用同一个 Future，避免认证监听、网络监听和生命周期恢复各建一条连接。
    if (_connectCompleter != null) {
      debugPrint('[WS] Connection in progress, waiting...');
      return _connectCompleter!.future;
    }

    if (state == WSConnectionState.connected && _channel != null) {
      debugPrint('[WS] Already connected');
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
      // 连接建立期间所有回调都绑定 generation；旧连接晚到的 onDone/onError
      // 不能覆盖当前连接状态，也不能清空新连接的订阅集合。
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
      debugPrint('[WS] Connection error: $e');
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
    final endpointWsUrl = ApiConfig.wsUrl;
    final wsUrl = '$endpointWsUrl?device_type=$deviceType&token=$encodedToken';
    debugPrint('[WS] Connecting to: $endpointWsUrl');

    WebSocketChannel? channel;
    StreamSubscription? subscription;

    try {
      channel = _channelFactory(Uri.parse(wsUrl));
      if (!_isCurrentConnectionGeneration(generation)) {
        throw const _StaleConnectionAttempt();
      }
      _channel = channel;

      await _readyWaiter(channel).timeout(
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

      if (PlatformUtils.isAndroid) {
        BackgroundService.instance.start();
      }

      unawaited(EndpointManager.instance.markWsSuccess(endpointWsUrl));
      debugPrint('[WS] Connected successfully');
      _networkUpReconnectDebounce?.cancel();
      _networkUpReconnectDebounce = null;
      _flushMessageQueue();
      if (_subscribedChatIds.isNotEmpty) {
        // 订阅集合是客户端期望状态；新传输建立后必须重放，服务端不会继承旧连接订阅。
        debugPrint('[WS] Re-subscribing to ${_subscribedChatIds.length} chats');
        subscribeChats(_subscribedChatIds.toList(), force: true);
      }
      if (isReconnectAttempt) {
        _hasConnectedOnce = true;
        _dispatchReconnected();
      } else {
        _hasConnectedOnce = true;
      }
    } on TimeoutException catch (e) {
      debugPrint('[WS] Connection timeout: $e');
      await EndpointManager.instance.markWsFailure(endpointWsUrl);
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
      debugPrint('[WS] Connection error: $e');
      await EndpointManager.instance.markWsFailure(endpointWsUrl);
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

    // 必须在第一个 await 之前同时取走旧 subscription 和旧 channel。
    // 否则并发重连可能在 cancel() 等待期间替换 _channel，导致这里误关新连接。
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    await subscription?.cancel();
    await _closeChannel(channel);

    if (!_isDisposed) {
      if (preserveRecoveringState && _token != null) {
        state = WSConnectionState.reconnecting;
      } else {
        state = WSConnectionState.disconnected;
      }
    }
    debugPrint('[WS] Disconnected (clearToken=$clearToken)');
  }

  /// 取消所有定时器
  void _cancelAllTimers() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _pongTimeoutTimer?.cancel();
    _pongTimeoutTimer = null;
    _backgroundKeepAliveTimer?.cancel();
    _backgroundKeepAliveTimer = null;
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

    // 返回 false 只表示本次没有写入传输层；调用方不能把入队等同于服务端已接收。
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
      debugPrint(
        '[WS] Queued message: ${message.type} (queue: ${_messageQueue.length})',
      );
    } else {
      debugPrint('[WS] Queue full, dropping: ${message.type}');
    }
  }

  /// 发送单条消息（带错误处理）
  bool _sendMessage(WSMessage message) {
    try {
      _channel?.sink.add(message.toJsonString());
      debugPrint('[WS] Sent: ${message.type}');
      return true;
    } catch (e) {
      debugPrint('[WS] Send error: $e');
      _enqueueMessage(message);
      return false;
    }
  }

  /// 清空消息队列（重连成功后调用）
  void _flushMessageQueue() {
    if (_messageQueue.isEmpty) return;
    debugPrint('[WS] Flushing ${_messageQueue.length} queued messages');

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
    // “已重连”只表示传输恢复，业务层收到事件后仍需按 seq 主动补齐断线窗口。
    if (_handlers.containsKey(WSMessageType.reconnected)) {
      final handlerList = List<Function(dynamic)>.from(
        _handlers[WSMessageType.reconnected]!,
      );
      debugPrint(
        '[WS] Dispatching reconnected to ${handlerList.length} handlers',
      );
      for (final handler in handlerList) {
        try {
          handler({});
        } catch (e) {
          debugPrint('[WS] Reconnected handler error: $e');
        }
      }
    }
  }

  // 记录已订阅的 chatIds，重连后自动重订阅
  /// 订阅会话
  void subscribeChats(List<String> chatIds, {bool force = false}) {
    final nextIds = chatIds
        .map((id) => id.trim())
        .where((id) =>
            id.isNotEmpty && (force || !_subscribedChatIds.contains(id)))
        .toList();
    if (nextIds.isEmpty) return;

    _subscribedChatIds.addAll(nextIds);
    send(WSMessage(type: WSMessageType.subscribe, data: {'chat_ids': nextIds}));
  }

  /// 取消订阅会话
  void unsubscribeChats(List<String> chatIds) {
    final nextIds =
        chatIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toList();
    if (nextIds.isEmpty) return;

    _subscribedChatIds.removeAll(nextIds);
    send(
      WSMessage(type: WSMessageType.unsubscribe, data: {'chat_ids': nextIds}),
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
        debugPrint('[WS] Ignoring non-string message: ${rawData.runtimeType}');
        return;
      }

      final json = jsonDecode(rawData) as Map<String, dynamic>;
      final type = json['type'] as String? ?? '';

      debugPrint('[WS] Received: $type');

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
        debugPrint('[WS] Dispatching $type to ${handlerList.length} handlers');
        for (final handler in handlerList) {
          try {
            handler(json);
          } catch (e) {
            debugPrint('[WS] Handler error for $type: $e');
          }
        }
      } else {
        debugPrint('[WS] No handlers registered for type: $type');
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
      debugPrint('[WS] Parse error: $e');
    }
  }

  /// 处理连接错误（onerror）
  ///
  /// 仅当前有效连接代际可以触发重连；旧连接错误直接丢弃。
  void _onError(dynamic error, int generation) {
    if (!_isCurrentConnectionGeneration(generation)) return;
    debugPrint('[WS] Connection error: $error');
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
    debugPrint(
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
      debugPrint(
        '[WS] Max reconnect attempts reached, switching to monitor mode',
      );
      state = WSConnectionState.disconnected;
      _startReconnectMonitor();
      return;
    }

    if (_token == null) return;

    state = WSConnectionState.reconnecting;

    final base = (2 << _reconnectAttempts).clamp(2, 60);
    final jitter = Random().nextInt(5);
    var delaySecs = base + jitter;
    if (_isInBackground) {
      final cooldown = _backgroundReconnectCooldown;
      final now = DateTime.now();
      final last = _lastBackgroundReconnectAt;
      final remaining =
          last == null ? cooldown : cooldown - now.difference(last);
      final floor = remaining.isNegative ? cooldown : remaining;
      if (floor > Duration.zero) {
        delaySecs = delaySecs.clamp(floor.inSeconds, 300);
      }
      _lastBackgroundReconnectAt = now;
      _backgroundFastReconnects++;
    }
    _reconnectAttempts++;

    debugPrint(
      '[WS] Reconnecting in ${delaySecs}s '
      '(attempt $_reconnectAttempts, base=${base}s, jitter=+${jitter}s, '
      'background=${_isInBackground}, longBackground=${_isLongBackground})',
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
        debugPrint('[WS] Reconnect monitor: attempting reconnect...');
        _reconnectAttempts = 0;
        unawaited(_triggerForceReconnect());
      }
    });
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    debugPrint('[WS] Disposing WebSocket service');

    WidgetsBinding.instance.removeObserver(this);
    _removeBackgroundKeepAliveHandler?.call();
    _removeBackgroundKeepAliveHandler = null;
    _networkSubscription?.cancel();
    _networkSubscription = null;

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
  debugPrint(
    '[WS Provider] Initial auth state: ${initialState.status}, hasToken: ${initialState.token != null}',
  );

  if (initialState.status == AuthStatus.authenticated &&
      initialState.token != null) {
    Future.microtask(() {
      if (!ref.read(accountSessionCoordinatorProvider).isActive) return;
      debugPrint('[WS Provider] Initial connect...');
      ws.connect(initialState.token!);
    });
  }

  // 监听后续认证状态变化
  ref.listen<AuthState>(authServiceProvider, (previous, next) {
    debugPrint(
      '[WS Provider] Auth state changed: ${previous?.status} -> ${next.status}',
    );
    if (next.status == AuthStatus.authenticated && next.token != null) {
      Future.microtask(() {
        final session = ref.read(accountSessionCoordinatorProvider);
        if (!session.isActive) return;
        if (ws.connectionState != WSConnectionState.connected &&
            ws.connectionState != WSConnectionState.connecting) {
          debugPrint('[WS Provider] Connecting due to auth change...');
          ws.connect(next.token!);
        }
      });
    } else if (previous?.status == AuthStatus.authenticated &&
        next.status != AuthStatus.authenticated) {
      // logout 时清除 token，防止 _onDone 用旧 token 重连
      ws.disconnect(clearToken: true);
    }
  });

  ref.listen<AccountSessionState>(accountSessionCoordinatorProvider, (
    previous,
    next,
  ) {
    if (!next.isActive && previous?.isActive == true) {
      // Publish the account boundary before remote logout. Clearing the token
      // here prevents the old account from reconnecting during teardown.
      unawaited(ws.disconnect(clearToken: true));
    }
  });

  ref.onDispose(() {
    ws.dispose();
  });

  return ws;
});
