import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'api/api_client.dart';
import 'api/websocket_service.dart';
import 'desktop_notification_service.dart';
import 'agora_web_ready_stub.dart'
    if (dart.library.js_interop) 'agora_web_ready_web.dart';
import 'web_media_permission_stub.dart'
    if (dart.library.js_interop) 'web_media_permission_web.dart';
import 'web_audio_unlock_stub.dart'
    if (dart.library.js_interop) 'web_audio_unlock_web.dart';

enum CallState { idle, outgoing, incoming, connecting, connected, ended }

enum CallType { voice, video }

class CallInfo {
  final int? callId;
  final String channelName;
  final String remoteUserId;
  final String remoteName;
  final String? remoteAvatar;
  final CallType type;
  final bool isOutgoing;
  final DateTime startTime;
  DateTime? connectTime;
  int? remoteUid;

  CallInfo({
    this.callId,
    required this.channelName,
    required this.remoteUserId,
    required this.remoteName,
    this.remoteAvatar,
    required this.type,
    required this.isOutgoing,
    DateTime? startTime,
    this.connectTime,
    this.remoteUid,
  }) : startTime = startTime ?? DateTime.now();

  CallInfo copyWith({
    int? callId,
    String? channelName,
    String? remoteUserId,
    String? remoteName,
    String? remoteAvatar,
    CallType? type,
    bool? isOutgoing,
    DateTime? startTime,
    DateTime? connectTime,
    int? remoteUid,
  }) {
    return CallInfo(
      callId: callId ?? this.callId,
      channelName: channelName ?? this.channelName,
      remoteUserId: remoteUserId ?? this.remoteUserId,
      remoteName: remoteName ?? this.remoteName,
      remoteAvatar: remoteAvatar ?? this.remoteAvatar,
      type: type ?? this.type,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      startTime: startTime ?? this.startTime,
      connectTime: connectTime ?? this.connectTime,
      remoteUid: remoteUid ?? this.remoteUid,
    );
  }
}

class CallServiceState {
  final CallState state;
  final CallInfo? callInfo;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isVideoEnabled;
  final bool isRemoteVideoEnabled;
  final bool isMinimized;
  final String? errorMessage;

  const CallServiceState({
    this.state = CallState.idle,
    this.callInfo,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isVideoEnabled = true,
    this.isRemoteVideoEnabled = true,
    this.isMinimized = false,
    this.errorMessage,
  });

  CallServiceState copyWith({
    CallState? state,
    CallInfo? callInfo,
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isVideoEnabled,
    bool? isRemoteVideoEnabled,
    bool? isMinimized,
    String? errorMessage,
    bool clearError = false,
  }) {
    return CallServiceState(
      state: state ?? this.state,
      callInfo: callInfo ?? this.callInfo,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
      isRemoteVideoEnabled: isRemoteVideoEnabled ?? this.isRemoteVideoEnabled,
      isMinimized: isMinimized ?? this.isMinimized,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  bool get isInCall =>
      state == CallState.outgoing ||
      state == CallState.incoming ||
      state == CallState.connecting ||
      state == CallState.connected;
}

class CallService extends StateNotifier<CallServiceState> {
  final ApiClient _api;
  final WebSocketService _wsService;
  RtcEngine? _engine;
  Timer? _callTimer;
  String? _appId;
  bool _isEnabled = false;
  bool _isSimulator = false;

  // CallKit UUID
  String? _currentCallKitUuid;

  Function(CallInfo)? onIncomingCall;
  Function()? onCallConnected;
  Function(String reason)? onCallEnded;
  Function(String error)? onCallFailed;

  static GlobalKey<NavigatorState>? navigatorKey;

  Future<void>? _initEngineFuture;
  bool _isAcceptingCall = false;
  bool _isEndingCall = false;
  bool _isRejectingCall = false;
  bool _isCancellingCall = false;

  StreamSubscription? _callKitSubscription;

  bool _isHandlingCallKitAccept = false;
  bool _isRestoringSystemIncomingCall = false;

  final List<String> _wsHandlerIds = [];

  bool _configLoaded = false;

  RtcEngineEventHandler? _eventHandler;

  /// Web 专用：`enableAudio()` 在 Flutter 侧 await 完只是 iris_web 转发调用完成，
  /// 底层 createMicrophoneAudioTrack + setEnabled 状态机切换还要 200~400ms。
  /// 如果这中间就 joinChannel，就会撞出 "cannot set enabled while the track is muted"
  /// 之类的 TRACK_STATE_UNREACHABLE 偶发错误。
  /// 我们把这个 Completer 放到 `onLocalAudioStateChanged` 里，等到 SDK 明确回
  /// `recording` 才放行 joinChannel。原生端不用（native SDK 是同步就绪）。
  Completer<void>? _webAudioReadyCompleter;

  bool _isDisposed = false;

  CallService(this._api, this._wsService) : super(const CallServiceState()) {
    // ★ WS handler 必须在构造函数里同步注册！
    //   之前放在 async `_init()` 里，即使 web 上 `_checkSimulator` 立即返回，
    //   `await` 仍会引入一个微任务边界。如果 WebSocket 在这个边界之前已经收到
    //   `incoming_call`（例如离线队列在 WS 重连后立刻回放），事件会被 dispatch
    //   到一个空的 handler 列表并直接丢弃 —— 表现为"被叫方永远看不到来电"。
    //   放在同步阶段可以彻底消除这个竞态，代价可忽略。
    _setupWebSocketListeners();

    // 剩下的初始化仍可以异步做，不会影响接收信令
    _init();
  }

  Future<void> _init() async {
    try {
      await _checkSimulator();

      if (!kIsWeb && !_isSimulator && (Platform.isIOS || Platform.isAndroid)) {
        _setupCallKit();
      }

      // Web 端：一旦 config 拿到手，立刻 warm up Agora engine，避免 startCall
      // 时才第一次拉 iris_web / wasm，导致 `/call/create` 之前就卡几秒。
      // Native 端保持懒加载（避免不打电话就白白吃内存）。
      if (kIsWeb) {
        unawaited(_preloadEngineIfPossible());
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] Init error: $e');
    }
  }

  /// Web 专用：登录后台加载 config，让 startCall 时不用再等 `/agora/config`。
  ///
  /// ★ 早期版本这里还调了 `_initEngine()` 想把 iris_web wasm 也预热掉，
  ///   但 `_engine.enableAudio()` 在 web 上会**立刻 createMicrophoneAudioTrack**
  ///   → 触发 getUserMedia，登录时莫名弹麦克风权限、mic 全程被占，
  ///   还导致挂断后重拨时上一次 mic track 未释放，出现"隔一次成功一次"。
  ///   现在退化成只预取 config；iris_web 脚本已经在 index.html 里 defer 加载，
  ///   engine 一律走 startCall / acceptCall 里的懒加载，每通新电话都是全新
  ///   engine + 全新 mic track，避免复用带来的状态污染。
  Future<void> _preloadEngineIfPossible() async {
    if (_isDisposed) return;
    try {
      if (!_configLoaded) await ensureConfigLoaded();
      if (kDebugMode) debugPrint('[CallService] Web config preloaded (engine not initialized eagerly)');
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] Web config preload failed: $e');
    }
  }

  Future<void> ensureConfigLoaded() async {
    if (_configLoaded || _isDisposed) return;
    try {
      await _loadConfig();
      _configLoaded = true;
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] Load config error: $e');
    }
  }

  Future<void> _checkSimulator() async {
    try {
      if (kIsWeb) {
        _isSimulator = false;
        return;
      }
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _isSimulator = !iosInfo.isPhysicalDevice;
      } else if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _isSimulator = !androidInfo.isPhysicalDevice;
      } else {
        _isSimulator = false;
      }
      if (_isSimulator) {
        if (kDebugMode) debugPrint('[CallService] Running on simulator, Agora SDK disabled');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] Check simulator error: $e');
    }
  }

  void _setupWebSocketListeners() {
    if (kDebugMode) debugPrint('[CallService] Setting up WebSocket listeners');

    for (final id in _wsHandlerIds) {
      _wsService.unregisterHandler(id);
    }
    _wsHandlerIds.clear();

    final incomingId = _wsService.registerHandler(WSMessageType.incomingCall, (
      data,
    ) {
      if (kDebugMode) debugPrint('[CallService] ========== INCOMING CALL ==========');
      if (kDebugMode) debugPrint('[CallService] Incoming call data: $data');
      if (kDebugMode) debugPrint(
        '[CallService] isSimulator: $_isSimulator, isEnabled: $_isEnabled',
      );
      final callData = data['data'] as Map<String, dynamic>?;
      if (callData != null) {
        handleIncomingCall(callData);
      } else {
        if (kDebugMode) debugPrint('[CallService] ERROR: callData is null!');
      }
    });
    _wsHandlerIds.add(incomingId);

    final acceptedId = _wsService.registerHandler(WSMessageType.callAccepted, (
      data,
    ) {
      if (kDebugMode) debugPrint('[CallService] Call accepted');
      handleCallAccepted();
    });
    _wsHandlerIds.add(acceptedId);

    final rejectedId = _wsService.registerHandler(WSMessageType.callRejected, (
      data,
    ) {
      if (kDebugMode) debugPrint('[CallService] Call rejected: $data');
      final reason = data['data']?['reason'] as String? ?? 'decline';
      handleCallRejected(reason);
    });
    _wsHandlerIds.add(rejectedId);

    final endedId = _wsService.registerHandler(WSMessageType.callEnded, (data) {
      if (kDebugMode) debugPrint('[CallService] Call ended: $data');
      final reason = data['data']?['reason'] as String? ?? 'hangup';
      endCall(reason: reason, notifyServer: false);
    });
    _wsHandlerIds.add(endedId);

    final cancelledId = _wsService.registerHandler(
      WSMessageType.callCancelled,
      (data) {
        if (kDebugMode) debugPrint('[CallService] Call cancelled');
        handleCallCancelled();
      },
    );
    _wsHandlerIds.add(cancelledId);

    // ★ WS 重连后主动拉一次挂起中的通话。
    //   这是"WS 掉线错过 incoming_call"的补偿网 —— 主要针对 web：
    //   - 浏览器 tab 切后台被节流 / 网络抖动 → WS 短暂掉线
    //   - 重连回来时，服务端已经把 incoming_call 塞进离线队列
    //     甚至队列都过期了（若 >7d），前端主动查一次绝不会错过。
    final reconnectedId = _wsService.registerHandler(
      WSMessageType.reconnected,
      (_) {
        if (kDebugMode) debugPrint('[CallService] WS reconnected, polling pending call...');
        unawaited(pollPendingCall());
      },
    );
    _wsHandlerIds.add(reconnectedId);
  }

  /// 拉取"当前是否有未接的通话"。见 backend `GetPendingCall`。
  ///
  /// 谁调它？
  ///   1. WS reconnected 事件（内部自动触发）
  ///   2. 外部 app.dart 可以在 web 端 visibilitychange -> visible 时也调一次
  ///
  /// 只在当前 state.isInCall == false 时才响应，避免打断进行中的通话。
  Future<void> pollPendingCall() async {
    if (_isDisposed) return;
    if (state.isInCall) {
      if (kDebugMode) debugPrint('[CallService] pollPendingCall: already in call, skip');
      return;
    }

    try {
      final resp = await _api.get<Map<String, dynamic>>('/call/pending');
      if (!resp.isSuccess || resp.data == null) return;
      final data = resp.data!;
      if (data['has_pending'] != true) return;

      // 只处理 callee 角色下的活跃 calling —— caller 侧自己 UI 是自己发起的。
      final asRole = data['as_role']?.toString();
      final status = data['status']?.toString();
      if (asRole != 'callee' || status != 'calling') {
        if (kDebugMode) debugPrint(
          '[CallService] pollPendingCall: not a callable incoming (role=$asRole status=$status)',
        );
        return;
      }

      final other = data['other_user'] as Map<String, dynamic>?;
      if (other == null) return;

      // 复用 handleIncomingCall，走跟 WS 收到 incoming_call 完全一样的路径
      final synthesized = {
        'call_id': data['call_id'],
        'channel_name': data['channel_name'],
        'caller_id': other['id'],
        'caller_name': other['name'],
        'caller_avatar': other['avatar'],
        'call_type': data['call_type'],
      };
      if (kDebugMode) debugPrint(
        '[CallService] pollPendingCall: synthesized incoming call for callId=${data['call_id']}',
      );
      await handleIncomingCall(synthesized);
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] pollPendingCall error: $e');
    }
  }

  Future<void> _loadConfig() async {
    try {
      final response = await _api.get<Map<String, dynamic>>('/call/config');
      if (response.isSuccess && response.data != null) {
        _isEnabled = response.data!['enabled'] == true;
        _appId = response.data!['app_id'] as String?;
        if (kDebugMode) debugPrint(
          '[CallService] Enabled: $_isEnabled, AppId: ${_appId?.substring(0, 8)}...',
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] Load config error: $e');
    }
  }

  bool get isEnabled {
    if (kIsWeb) {
      return _isEnabled && _appId != null && _appId!.isNotEmpty;
    }
    return !_isSimulator && _isEnabled && _appId != null && _appId!.isNotEmpty;
  }

  Future<bool> _requestPermissions(CallType type) async {
    try {
      if (kIsWeb) {
        // ★ 之前这里直接 return true，把权限确认全甩给 Agora 自己去 getUserMedia。
        //   结果如果用户拒绝麦克风，Agora 抛 PERMISSION_DENIED 时主叫 UI 已经
        //   切到 outgoing、后端已经 create call、对方 APK 已经收到 incoming_call，
        //   然后又立刻被主叫超时/手动 cancel 掉——就是"10 次通 2 次"的直接原因。
        //   现在主动调 getUserMedia 前置授权，失败给出人话原因。
        final needCamera = type == CallType.video;
        final res = await ensureWebMediaPermission(needCamera: needCamera);
        if (res.ok) {
          if (kDebugMode) debugPrint(
            '[CallService] Web media permission granted (${needCamera ? "audio+video" : "audio"})',
          );
          return true;
        }
        if (kDebugMode) debugPrint(
          '[CallService] Web media permission failed: ${res.reason}',
        );
        state = state.copyWith(
          errorMessage: _webPermissionErrorMessage(res.reason, needCamera),
        );
        return false;
      }
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        if (kDebugMode) debugPrint(
          '[CallService] Desktop platform, system will handle permissions',
        );
        return true;
      }

      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        if (kDebugMode) debugPrint('[CallService] Microphone permission denied');
        if (micStatus.isPermanentlyDenied) {
          state = state.copyWith(errorMessage: '通话失败，请重试');
          await openAppSettings();
        } else {
          state = state.copyWith(errorMessage: '通话失败，请重试');
        }
        return false;
      }

      if (type == CallType.video) {
        final cameraStatus = await Permission.camera.request();
        if (!cameraStatus.isGranted) {
          if (kDebugMode) debugPrint('[CallService] Camera permission denied');
          if (cameraStatus.isPermanentlyDenied) {
            state = state.copyWith(errorMessage: '通话失败，请重试');
            await openAppSettings();
          } else {
            state = state.copyWith(errorMessage: '通话失败，请重试');
          }
          return false;
        }
      }

      if (Platform.isAndroid) {
        await Permission.bluetoothConnect.request();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] Permission request error: $e');
    }

    return true;
  }

  Future<void> _initEngine() async {
    if (_engine != null) return;

    if (_initEngineFuture != null) {
      return _initEngineFuture;
    }

    _initEngineFuture = _doInitEngine();
    try {
      await _initEngineFuture;
    } finally {
      _initEngineFuture = null;
    }
  }

  /// Web 麦克风/摄像头权限失败时给用户看的中文提示（覆盖各种浏览器错误类型）
  String _webPermissionErrorMessage(String reason, bool needCamera) {
    final device = needCamera ? '麦克风和摄像头' : '麦克风';
    switch (reason) {
      case 'denied':
        return '$device权限被拒绝，请在浏览器地址栏左侧允许后重试';
      case 'no_device':
        return '未检测到$device设备，请检查硬件后重试';
      case 'busy':
        return '$device已被其它应用占用（如腾讯会议/Zoom），请关闭后重试';
      case 'insecure_context':
        return '通话需要 HTTPS 环境，请通过 https:// 或 localhost 访问';
      case 'api_missing':
        return '当前浏览器不支持通话功能，请使用最新版 Chrome / Edge / Safari';
      case 'timeout':
        return '$device授权超时，请点击浏览器提示允许';
      default:
        return '$device权限获取失败 ($reason)，请刷新页面重试';
    }
  }

  Future<void> _doInitEngine() async {
    if (_engine != null) return;
    if (_appId == null || _appId!.isEmpty) {
      throw Exception('App ID not configured');
    }

    // ★ 全流程用局部 engine 变量装载，任何一步抛异常都要保证不把
    //   半初始化的引用留在 `_engine` 字段里，否则下一次 startCall/acceptCall
    //   会走 `if (_engine != null) return;` 直接复用一个坏掉的 engine，
    //   典型症状就是"隔一次成功一次"。
    RtcEngine? tempEngine;
    RtcEngineEventHandler? tempHandler;

    // Web 端：先确认 iris_web 脚本已经就绪，否则 createAgoraRtcEngine 会
    // 在内部访问 window.IrisWebRtc 时静默失败/hang，用户看到"点了通话没反应"。
    // 明确抛出 Exception → catch 里映射为友好的错误消息，UI 有感知。
    if (kIsWeb) {
      final ready = checkAgoraWebReady();
      if (!ready.ok) {
        if (kDebugMode) debugPrint(
          '[CallService] Web Agora SDK not ready: ${ready.reason}',
        );
        throw Exception('Agora Web SDK 未加载 (${ready.reason})，请刷新页面重试');
      }
    }

    try {
    tempEngine = createAgoraRtcEngine();
    await tempEngine.initialize(
      RtcEngineContext(
        appId: _appId!,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    tempHandler = RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        if (kDebugMode) debugPrint('[Agora] Join channel success: ${connection.channelId}');
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        if (kDebugMode) debugPrint('[Agora] User joined: $remoteUid');
        if (_isDisposed) return;

        _cancelConnectionTimeout();
        // 对端加入频道 = 通话真正接通，不需要 outgoing 超时了
        _cancelOutgoingCallTimeout();

        if (state.state == CallState.connecting ||
            state.state == CallState.outgoing) {
          state = state.copyWith(
            state: CallState.connected,
            isRemoteVideoEnabled: true,
            callInfo: state.callInfo?.copyWith(
              remoteUid: remoteUid,
              connectTime: DateTime.now(),
            ),
          );
          onCallConnected?.call();
          _startCallTimer();
        }
      },
      onUserOffline: (connection, remoteUid, reason) {
        if (kDebugMode) debugPrint('[Agora] User offline: $remoteUid, reason: $reason');
        if (_isDisposed) return;
        if (state.state == CallState.connected) {
          endCall(reason: 'remote_hangup');
        }
      },
      onRemoteVideoStateChanged:
          (connection, remoteUid, videoState, reason, elapsed) {
        if (kDebugMode) debugPrint(
          '[Agora] Remote video state: $videoState, reason: $reason',
        );
        if (_isDisposed) return;
        if (state.state != CallState.connected &&
            state.state != CallState.connecting) {
          return;
        }
        // ★ 只在**明确信号**下切换 isRemoteVideoEnabled，避免网络抖动/首帧
        //   到达前的 Stopped 中间态导致 UI 闪烁到"对方未开启摄像头"。
        //   - Decoding / Starting 或 remoteUnmuted → true
        //   - remoteMuted → false（仅原生生效；见下）
        //   - 其它 Stopped / Frozen / Failed / Offline 等一律不动状态。
        //     离线由 onUserOffline 直接 endCall，不会走到这里。
        if (videoState == RemoteVideoState.remoteVideoStateDecoding ||
            videoState == RemoteVideoState.remoteVideoStateStarting ||
            reason == RemoteVideoStateReason.remoteVideoStateReasonRemoteUnmuted) {
          if (!state.isRemoteVideoEnabled) {
            state = state.copyWith(isRemoteVideoEnabled: true);
          }
        } else if (reason ==
            RemoteVideoStateReason.remoteVideoStateReasonRemoteMuted) {
          // ★ Web 端专用：Iris Web 在对端订阅刚建立、首帧还没到之前，会**误报**
          //   `state=Stopped, reason=RemoteMuted` 一次，导致 UI 一接通就闪
          //   "对方未开启摄像头"。web 上真正的 mute/unmute 我们完全交给
          //   下面的 onUserMuteVideo 处理，这里跳过。原生 APK 保留原逻辑。
          if (!kIsWeb && state.isRemoteVideoEnabled) {
            state = state.copyWith(isRemoteVideoEnabled: false);
          }
        }
      },
      // ★ 更可靠的对端 mute/unmute 视频信号：对方调用 muteLocalVideoStream
      //   时会直接触发这个回调，Iris Web SDK 转发得也比 onRemoteVideoStateChanged
      //   干净，用来兜底 web 端偶发丢事件的情况。
      onUserMuteVideo: (connection, remoteUid, muted) {
        if (kDebugMode) debugPrint(
          '[Agora] onUserMuteVideo: remoteUid=$remoteUid, muted=$muted',
        );
        if (_isDisposed) return;
        if (state.state != CallState.connected &&
            state.state != CallState.connecting) {
          return;
        }
        if (state.isRemoteVideoEnabled == !muted) return;
        state = state.copyWith(isRemoteVideoEnabled: !muted);
      },
      onError: (err, msg) {
        if (kDebugMode) debugPrint('[Agora] Error: $err - $msg');
        if (_isDisposed) return;
        if (state.state != CallState.idle) {
          state = state.copyWith(errorMessage: msg);
        }
      },
      onLocalAudioStateChanged: (connection, audioState, reason) {
        if (kDebugMode) debugPrint(
          '[Agora] Local audio state: $audioState, reason: $reason',
        );
        if (_isDisposed) return;
        // ★ Web 专用：完成 `_webAudioReadyCompleter`，
        //   让 startCall/acceptCall 里 `_waitForWebAudioReady()` 能放行 joinChannel。
        //   `recording` 或 `encoding` 都算就绪；`failed` 立刻抛错走 UI 提示。
        final c = _webAudioReadyCompleter;
        if (c == null || c.isCompleted) return;
        if (audioState == LocalAudioStreamState.localAudioStreamStateRecording ||
            audioState == LocalAudioStreamState.localAudioStreamStateEncoding) {
          c.complete();
        } else if (audioState ==
            LocalAudioStreamState.localAudioStreamStateFailed) {
          c.completeError(
            StateError('Local audio setup failed (reason=$reason)'),
          );
        }
      },
      onConnectionStateChanged: (connection, stateType, reason) {
        if (kDebugMode) debugPrint('[Agora] Connection state: $stateType, reason: $reason');
        if (_isDisposed) return;
        if (stateType == ConnectionStateType.connectionStateDisconnected ||
            stateType == ConnectionStateType.connectionStateFailed) {
          if (state.state == CallState.connected ||
              state.state == CallState.connecting) {
            if (kDebugMode) debugPrint('[Agora] Network disconnected during call, ending call');
            endCall(reason: 'network_error');
          }
        }
      },
    );
    tempEngine.registerEventHandler(tempHandler);

    // ★ Web 上必须在 enableAudio **之前**就把 completer 准备好，
    //   否则 onLocalAudioStateChanged 回调可能在 await 之前就已经 fire。
    if (kIsWeb) {
      _webAudioReadyCompleter = Completer<void>();
    }

    await tempEngine.enableAudio();

    // ★ `setDefaultAudioRouteToSpeakerphone` 只在 iOS/Android 原生上有效。
    //   web 上 iris_web 会返回 -4 (not supported) 并被 agora_rtc_engine 抛成
    //   AgoraRtcException(-4)，直接导致"通话失败(错误码:-4)"。
    //   项目用的是 universal_io，在**手机浏览器**上 `Platform.isIOS/isAndroid`
    //   会按 userAgent 变成 true，因此必须显式排除 kIsWeb。
    if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
      await tempEngine.setDefaultAudioRouteToSpeakerphone(false);
    }

      // 全部成功才把引用交出去，避免半初始化 engine 被下一次调用复用
      _engine = tempEngine;
      _eventHandler = tempHandler;
    } catch (e) {
      // 任何一步失败：先解绑 handler、release 掉临时 engine，再把异常继续抛出去
      if (kDebugMode) debugPrint('[CallService] _doInitEngine failed: $e — cleaning up temp engine');
      try {
        if (tempEngine != null && tempHandler != null) {
          tempEngine.unregisterEventHandler(tempHandler);
        }
      } catch (_) {}
      try {
        await tempEngine?.release();
      } catch (_) {}
      _engine = null;
      _eventHandler = null;
      // 清掉 pending completer，避免下次 startCall 立刻 await 一个永远不会 complete
      // 的 future（因为对应的 engine 已经被 release，不会再 emit 事件了）
      final c = _webAudioReadyCompleter;
      if (c != null && !c.isCompleted) {
        c.completeError(e);
      }
      _webAudioReadyCompleter = null;
      rethrow;
    }
  }

  /// 判断当前 web 环境是不是 iOS 系 Safari / iPhone Chrome（内核也是 WebKit）。
  ///
  /// iris_web + WebKit 的组合上 PeerConnection / MediaStream 清理时间明显比 Blink 长，
  /// 需要用更保守的 settle 延迟 / 更谨慎的复用策略。仅 web 分支生效，
  /// native 侧 kIsWeb 为 false，直接短路，安卓 APK 完全不进这条路径。
  bool _isIosSafariLike() {
    if (!kIsWeb) return false;
    // universal_io 在 web 上是按 userAgent 判 OS 的，iPhone/iPad/iPod 都会
    // 返回 isIOS=true（macOS Safari 走 isMacOS，不在这个分支里）。
    return Platform.isIOS;
  }

  /// Web 专用：等 iris_web 内部 mic track 状态机稳定到 recording。
  /// - 收到 `localAudioStreamStateRecording` / `Encoding` → 立即返回
  /// - 收到 `Failed` → 抛错让上层做提示
  /// - 2s 都没等到 → 兜底放行（避免用户看到"点了没反应"），大多数场景这时也就绪了
  /// 原生端不用（native SDK 是同步的），startCall/acceptCall 里加 `if (kIsWeb)` 门槛。
  Future<void> _waitForWebAudioReady() async {
    final c = _webAudioReadyCompleter;
    if (c == null || c.isCompleted) return;
    try {
      await c.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          if (kDebugMode) debugPrint(
            '[CallService] Web audio not ready in 2s, joining anyway',
          );
        },
      );
    } finally {
      // 用完就清掉，下一次通话重新创建，避免 stale completer 拦截新事件
      _webAudioReadyCompleter = null;
    }
  }

  Future<bool> startCall({
    required String targetUserId,
    required String targetName,
    String? targetAvatar,
    required CallType type,
  }) async {
    if (_isDisposed) return false;

    // ★ iOS Safari 专用（无副作用其它平台）：必须在**任何 await 之前**同步
    //   触发 AudioContext.resume() —— 一旦跨了 async 边界，Safari 就把用户
    //   手势上下文扔了，之后 AudioContext 永远 suspended，通话没声音。
    //   这个函数在 native 上是 no-op，安卓 APK 完全不受影响。
    unlockWebAudio();

    await _checkSimulator();
    if (_isDisposed) return false;

    if (kDebugMode) debugPrint(
      '[CallService] startCall: isWeb=$kIsWeb, isSimulator=$_isSimulator, isEnabled=$_isEnabled, appId=${_appId?.isNotEmpty}',
    );

    if (!kIsWeb && _isSimulator) {
      state = state.copyWith(errorMessage: '通话失败，请重试');
      return false;
    }

    await _loadConfig();
    if (kDebugMode) debugPrint(
      '[CallService] After loadConfig: isEnabled=$_isEnabled, appId=$_appId',
    );

    if (!isEnabled) {
      state = state.copyWith(errorMessage: '通话失败，请重试');
      return false;
    }

    if (state.isInCall) {
      state = state.copyWith(errorMessage: '通话失败，请重试');
      return false;
    }

    // ★ 通话前主动探活 WebSocket。浏览器（尤其 Safari 后台 30s 就 kill、
    //   Chrome 也会在 tab 长时间不活跃后收紧）会**静默关闭 WS 底层 TCP**，
    //   但 Dart 里 state 仍显示 connected；如果直接 /call/create，后端 push
    //   的对方接听/拒绝信令永远回不来，主叫看到"点了通话没反应"。
    //   ensureAliveForCriticalAction 会 send ping、等 pong、失败就强制重连
    //   并等最多 6s 建连成功，全部走完才放行 create。原生 APK 走 kIsWeb 短路
    //   不进这条路径，保持原有的 fail-fast 行为。
    if (kIsWeb) {
      final wsAlive = await _wsService.ensureAliveForCriticalAction();
      if (!wsAlive) {
        state = state.copyWith(errorMessage: '网络连接异常，请检查网络后重试');
        return false;
      }
    } else if (_wsService.state != WSConnectionState.connected) {
      state = state.copyWith(errorMessage: '通话失败，请重试');
      return false;
    }

    try {
      final hasPermission = await _requestPermissions(type);
      if (!hasPermission) {
        return false;
      }

      await _initEngine();

      final response = await _api.post<Map<String, dynamic>>(
        '/call/create',
        data: {
          'target_user_id': targetUserId,
          'call_type': type == CallType.voice ? 'voice' : 'video',
        },
      );

      if (!response.isSuccess || response.data == null) {
        state = state.copyWith(errorMessage: response.message);
        return false;
      }

      final data = response.data!;
      final channelName = (data['channel_name'] as String?) ?? '';
      final token = (data['token'] as String?) ?? '';
      final callId = (data['call_id'] as int?) ?? 0;

      if (channelName.isEmpty || token.isEmpty) {
        if (kDebugMode) debugPrint(
          '[CallService] Invalid call data: channelName or token is empty',
        );
        state = state.copyWith(errorMessage: '通话失败，请重试');
        return false;
      }

      state = state.copyWith(
        state: CallState.outgoing,
        callInfo: CallInfo(
          callId: callId,
          channelName: channelName,
          remoteUserId: targetUserId,
          remoteName: targetName,
          remoteAvatar: targetAvatar,
          type: type,
          isOutgoing: true,
        ),
        isVideoEnabled: type == CallType.video,
      );

      if (type == CallType.video) {
        await _engine!.enableVideo();
        // ★ Web 上给 startPreview 一个较宽松的 5s 超时（同 acceptCall）。
        //   Iris Web 上这一步会触发 `createCameraVideoTrack + getUserMedia`，
        //   在权限已提前授权/慢速设备上真实完成时间 500ms~3s 都有可能；
        //   之前无限制 await 少数情况下会 hang 死用户"点了没反应"，
        //   3s 又偶尔切断导致 camera track 没建好就 joinChannel，对面看不到画面（问题 1）。
        //   原生 APK / iOS / 桌面：保留无 timeout 的 await——native SDK 本地起相机很快且稳。
        try {
          if (kIsWeb) {
            await _engine!.startPreview().timeout(const Duration(seconds: 5));
          } else {
            await _engine!.startPreview();
          }
        } catch (previewError) {
          if (kDebugMode) debugPrint('[CallService] startPreview error: $previewError');
          if (previewError is AgoraRtcException && previewError.code == -2) {
            if (Platform.isMacOS) {
              state = state.copyWith(errorMessage: '通话失败，请重试');
            } else {
              state = state.copyWith(errorMessage: '通话失败，请重试');
            }
          }
        }
      }

      final isVideo = type == CallType.video;

      // ★ Web 上等 iris_web 把 mic track 状态机跑稳，避免 joinChannel 里
      //   又触发 setEnabled 撞上刚跑到一半的 setMuted，报
      //   "TRACK_STATE_UNREACHABLE: cannot set enabled while the track is muted"。
      if (kIsWeb) {
        await _waitForWebAudioReady();
      }

      await _engine!.joinChannel(
        token: token,
        channelId: channelName,
        uid: 0,
        options: ChannelMediaOptions(
          autoSubscribeAudio: true,
          autoSubscribeVideo: isVideo,
          publishMicrophoneTrack: true,
          publishCameraTrack: isVideo,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );

      WakelockPlus.enable();

      // ★ Web + 视频通话防御性推流：joinChannel 已经带了 publishCameraTrack: true，
      //   但 Iris Web 上 camera track 建立时机跟 joinChannel 之间有偶发竞态——
      //   如果 startPreview 5s 超时耗尽而 camera track 才刚好起来，
      //   joinChannel 冻结的 publishOptions 里已经不带这个 track 了，
      //   对面就永远收不到画面（web-web 偶发一边黑屏，问题 1）。
      //   延迟 800ms 让 track 就绪，再 muteLocalVideoStream(false) 触发一次
      //   显式的 unmute + republish 事件，是 Agora 官方推荐的"补发"方式。
      //   完全不影响原生 APK：kIsWeb 门槛短路，不进这条路径。
      if (kIsWeb && isVideo) {
        unawaited(_defensiveRepublishVideoAfterJoin());
      }

      // ★ 主叫方也需要超时：以前只有被叫方 30s 自动 reject，主叫方无兜底，
      //   如果被叫的 WS 没收到 incoming_call、又没触发 reject，主叫会永远
      //   停在 "outgoing" 状态。给一个 45s 的自动 cancel，比对面 30s 长一点
      //   避免竞态，也能让"打不通"这个情况早点结束不用用户手动挂断。
      _startOutgoingCallTimeout(callId);

      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] Start call error: $e');

      final errorMessage = _classifyError(e, '通话');

      state = state.copyWith(state: CallState.idle, errorMessage: errorMessage);
      return false;
    }
  }

  Future<void> handleIncomingCall(Map<String, dynamic> data) async {
    final callId = data['call_id'] is int
        ? data['call_id'] as int
        : int.tryParse(data['call_id']?.toString() ?? '');

    if (state.isInCall) {
      final currentCallId = state.callInfo?.callId;
      if (callId != null && currentCallId == callId) {
        if (kDebugMode) debugPrint('[CallService] Duplicate incoming call ignored: $callId');
        return;
      }

      if (callId != null) {
        await _api.post(
          '/call/reject',
          data: {'call_id': callId, 'reason': 'busy'},
        );
      }
      return;
    }

    final channelName = data['channel_name']?.toString();
    final callerId = data['caller_id']?.toString();
    final callerName = data['caller_name']?.toString();

    if (channelName == null ||
        channelName.isEmpty ||
        callerId == null ||
        callerId.isEmpty ||
        callerName == null) {
      if (kDebugMode) debugPrint('[CallService] handleIncomingCall: invalid payload: $data');
      return;
    }

    final callerAvatarRaw = data['caller_avatar']?.toString();
    final callerAvatar = (callerAvatarRaw != null && callerAvatarRaw.isNotEmpty)
        ? ApiConfig.getMediaUrl(callerAvatarRaw)
        : null;
    final callType =
        data['call_type'] == 'video' ? CallType.video : CallType.voice;

    final callInfo = CallInfo(
      callId: callId,
      channelName: channelName,
      remoteUserId: callerId,
      remoteName: callerName,
      remoteAvatar: callerAvatar,
      type: callType,
      isOutgoing: false,
    );

    state = state.copyWith(
      state: CallState.incoming,
      callInfo: callInfo,
      isVideoEnabled: callType == CallType.video,
    );

    _startIncomingCallTimeout(callInfo.callId);

    _preloadForIncoming(callType);

    if (kIsWeb) {
      if (kDebugMode) debugPrint('[CallService] Web: showing in-app IncomingCallPage');
      onIncomingCall?.call(callInfo);
      return;
    }

    if (Platform.isIOS) {
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      final isForeground = lifecycleState == AppLifecycleState.resumed ||
          lifecycleState == AppLifecycleState.inactive;

      if (kDebugMode) debugPrint(
        '[CallService] iOS lifecycleState: $lifecycleState, isForeground: $isForeground, isSimulator: $_isSimulator',
      );

      if (isForeground && onIncomingCall != null && !_isSimulator) {
        if (kDebugMode) debugPrint(
          '[CallService] iOS foreground: showing in-app IncomingCallPage',
        );
        onIncomingCall?.call(callInfo);
      } else {
        if (kDebugMode) debugPrint('[CallService] iOS background/locked: showing CallKit UI');
        try {
          await _showCallKit(callInfo);
          if (_isSimulator && onIncomingCall != null) {
            if (kDebugMode) debugPrint(
              '[CallService] iOS simulator: also showing in-app IncomingCallPage',
            );
            onIncomingCall?.call(callInfo);
          }
        } catch (e) {
          if (kDebugMode) debugPrint(
            '[CallService] iOS CallKit failed: $e, falling back to in-app UI',
          );
          onIncomingCall?.call(callInfo);
        }
      }
      return;
    }

    if (Platform.isAndroid) {
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      final isForeground = lifecycleState == AppLifecycleState.resumed ||
          lifecycleState == AppLifecycleState.inactive;

      if (kDebugMode) debugPrint(
        '[CallService] Android lifecycleState: $lifecycleState, isForeground: $isForeground',
      );

      if (isForeground && onIncomingCall != null) {
        if (kDebugMode) debugPrint(
          '[CallService] Android foreground: showing in-app IncomingCallPage',
        );
        onIncomingCall?.call(callInfo);
      } else {
        if (kDebugMode) debugPrint(
          '[CallService] Android background/locked: showing system full-screen incoming',
        );
        try {
          await _showCallKit(callInfo);
        } catch (e) {
          if (kDebugMode) debugPrint(
            '[CallService] Android CallKit failed: $e, trying in-app UI',
          );
          onIncomingCall?.call(callInfo);
        }
      }
      return;
    }

    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      if (kDebugMode) debugPrint('[CallService] Desktop: showing in-app IncomingCallPage');
      onIncomingCall?.call(callInfo);
    }
  }

  Map<String, dynamic> _incomingPayloadFromCallInfo(CallInfo callInfo) {
    return <String, dynamic>{
      'type': 'incoming_call',
      'call_id': callInfo.callId,
      'callId': callInfo.callId,
      'channel_name': callInfo.channelName,
      'caller_id': callInfo.remoteUserId,
      'caller_name': callInfo.remoteName,
      'caller_avatar': callInfo.remoteAvatar ?? '',
      'call_type': callInfo.type == CallType.video ? 'video' : 'voice',
      'is_video': callInfo.type == CallType.video,
    };
  }

  Map<String, dynamic>? _asStringKeyMap(dynamic value) {
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        return _asStringKeyMap(decoded);
      } catch (_) {
        return null;
      }
    }
    if (value is! Map) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  Map<String, dynamic>? _incomingPayloadFromCallKitData(dynamic rawData) {
    final data = _asStringKeyMap(rawData);
    if (data == null) return null;

    final extra = _asStringKeyMap(data['extra']) ?? <String, dynamic>{};
    final payload = <String, dynamic>{...extra};

    payload['type'] = payload['type'] ?? 'incoming_call';
    payload['call_id'] = payload['call_id'] ??
        payload['callId'] ??
        data['call_id'] ??
        data['callId'];
    payload['channel_name'] = payload['channel_name'] ?? data['channel_name'];
    payload['caller_id'] = payload['caller_id'] ?? data['caller_id'];
    payload['caller_name'] =
        payload['caller_name'] ?? data['nameCaller'] ?? data['caller_name'];
    payload['caller_avatar'] =
        payload['caller_avatar'] ?? data['avatar'] ?? data['caller_avatar'];

    final type = payload['call_type'] ?? data['call_type'];
    final isVideo = payload['is_video'] == true ||
        payload['is_video'] == 'true' ||
        data['type'] == 1;
    payload['call_type'] =
        type?.toString() == 'video' || isVideo ? 'video' : 'voice';
    payload['is_video'] = payload['call_type'] == 'video';

    final hasRequiredFields = payload['call_id'] != null &&
        payload['channel_name']?.toString().isNotEmpty == true &&
        payload['caller_id']?.toString().isNotEmpty == true &&
        payload['caller_name']?.toString().isNotEmpty == true;
    return hasRequiredFields ? payload : null;
  }

  Future<bool> restoreIncomingCallFromSystem() async {
    if (_isDisposed || _isRestoringSystemIncomingCall) return false;
    if (kIsWeb || _isSimulator || !(Platform.isIOS || Platform.isAndroid)) {
      return false;
    }

    if (state.state == CallState.incoming && state.callInfo != null) {
      return true;
    }
    if (state.state == CallState.connecting ||
        state.state == CallState.connected) {
      return true;
    }

    _isRestoringSystemIncomingCall = true;
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      final calls = activeCalls is List ? activeCalls : const [];
      if (kDebugMode) debugPrint('[CallService] Active system calls: $calls');

      for (final rawCall in calls) {
        final call = _asStringKeyMap(rawCall);
        if (call == null) continue;

        final isAccepted = call['accepted'] == true ||
            call['isAccepted'] == true ||
            call['isAccepted'] == 'true';

        final payload = _incomingPayloadFromCallKitData(call);
        if (payload == null) {
          if (kDebugMode) debugPrint('[CallService] Cannot restore CallKit payload: $call');
          continue;
        }

        _currentCallKitUuid = call['id']?.toString() ??
            call['uuid']?.toString() ??
            _currentCallKitUuid;
        if (kDebugMode) debugPrint('[CallService] Restoring incoming call from system UI');
        await handleIncomingCall(payload);
        if (isAccepted) {
          if (kDebugMode) debugPrint('[CallService] Restored accepted system call, joining');
          await _handleCallKitAccept();
          return state.state == CallState.connecting ||
              state.state == CallState.connected;
        }
        return state.state == CallState.incoming && state.callInfo != null;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] restoreIncomingCallFromSystem error: $e');
    } finally {
      _isRestoringSystemIncomingCall = false;
    }

    return false;
  }

  Timer? _incomingCallTimer;
  Timer? _outgoingCallTimer;

  /// 主叫方 45s 超时，callee 未接则自动 cancel。
  /// 主要给 web 端兜底：如果 incoming_call 因 WS 掉线/浏览器节流没送达对面，
  /// 至少不会让主叫方一直挂在 outgoing 状态直到手动挂断。
  void _startOutgoingCallTimeout(int? callId) {
    _outgoingCallTimer?.cancel();
    _outgoingCallTimer = Timer(const Duration(seconds: 45), () {
      if (_isDisposed) return;
      // 只在仍是 outgoing 且是同一通电话时触发
      if (state.state == CallState.outgoing &&
          state.callInfo?.callId == callId) {
        if (kDebugMode) debugPrint('[CallService] Outgoing timeout, auto cancelling call');
        unawaited(cancelCall());
      }
    });
  }

  void _cancelOutgoingCallTimeout() {
    _outgoingCallTimer?.cancel();
    _outgoingCallTimer = null;
  }

  void _startIncomingCallTimeout(int? callId) {
    _incomingCallTimer?.cancel();
    _incomingCallTimer = Timer(const Duration(seconds: 30), () {
      if (_isDisposed) return;
      if (state.state == CallState.incoming &&
          state.callInfo?.callId == callId) {
        if (kDebugMode) debugPrint('[CallService] Incoming call timeout, auto rejecting');
        rejectCall(reason: 'timeout');
      }
    });
  }

  void _cancelIncomingCallTimeout() {
    _incomingCallTimer?.cancel();
    _incomingCallTimer = null;
  }

  Timer? _connectionTimer;

  void _startConnectionTimeout() {
    _connectionTimer?.cancel();
    _connectionTimer = Timer(const Duration(seconds: 20), () {
      if (_isDisposed) return;
      if (state.state == CallState.connecting ||
          state.state == CallState.outgoing) {
        if (kDebugMode) debugPrint('[CallService] Connection timeout, ending call');
        state = state.copyWith(errorMessage: '通话失败，请重试');
        endCall(reason: 'connection_timeout');
      }
    });
  }

  void _cancelConnectionTimeout() {
    _connectionTimer?.cancel();
    _connectionTimer = null;
  }

  Future<bool> acceptCall() async {
    // ★ iOS Safari：必须在**任何 await 之前**同步 resume AudioContext，
    //   否则 Safari 会把用户手势上下文丢掉，之后远端音频无法播放。
    //   Native 上是 no-op，不影响安卓 APK。
    unlockWebAudio();

    if (kDebugMode) debugPrint(
      '[CallService] acceptCall called, state=${state.state}, callInfo=${state.callInfo != null}',
    );

    if (_isAcceptingCall) {
      if (kDebugMode) debugPrint('[CallService] acceptCall already in progress');
      return false;
    }

    if (state.state != CallState.incoming || state.callInfo == null) {
      if (kDebugMode) debugPrint(
        '[CallService] acceptCall failed: invalid state or no callInfo',
      );
      state = state.copyWith(errorMessage: '通话失败，请重试');
      return false;
    }

    _isAcceptingCall = true;

    _cancelIncomingCallTimeout();

    final originalCallId = state.callInfo!.callId;
    final callType = state.callInfo!.type;
    final channelName = state.callInfo!.channelName;

    state = state.copyWith(state: CallState.connecting);
    if (kDebugMode) debugPrint('[CallService] State changed to connecting immediately');

    try {
      // ★ 接听前也要探活：incoming_call 收到时 WS 是活的，但用户可能过了几秒才点接听，
      //   这中间 Safari/后台 tab 可能已经把 WS kill 了。/call/accept 走 HTTP 能成功，
      //   但对方回来的信号（对端 join_channel 通知等）走 WS 就永远收不到，
      //   表现是"接听后卡在 connecting 一直无声音"。web 才需要，原生 APK 不受影响。
      if (kIsWeb) {
        final wsAlive = await _wsService.ensureAliveForCriticalAction();
        if (!wsAlive) {
          if (kDebugMode) debugPrint('[CallService] Accept: WS not alive, aborting');
          state = state.copyWith(
            state: CallState.idle,
            errorMessage: '网络连接异常，请检查网络后重试',
          );
          return false;
        }
      }
      // ★ Web 端也必须走 _requestPermissions，那里面会主动 getUserMedia 弹权限窗。
      //   之前 `kIsWeb ? false : ...` 直接跳过 → 浏览器权限没被 prompt →
      //   下面 joinChannel 时 Agora 的 createMicrophoneAudioTrack 才第一次拉起
      //   getUserMedia，用户拒绝就 PERMISSION_DENIED，通话失败。
      final needPermission =
          kIsWeb || !await Permission.microphone.isGranted;
      final needConfig = !_isEnabled || _appId == null || _appId!.isEmpty;
      final needEngine = _engine == null;

      if (kDebugMode) debugPrint(
        '[CallService] Accept: needPermission=$needPermission, needConfig=$needConfig, needEngine=$needEngine',
      );

      if (needPermission || needConfig) {
        if (kDebugMode) debugPrint('[CallService] Starting parallel permission & config...');
        final results = await Future.wait([
          needPermission ? _requestPermissions(callType) : Future.value(true),
          needConfig
              ? _loadConfigIfNeeded().then((_) => true)
              : Future.value(true),
        ]);

        if (needPermission && results[0] != true) {
          if (kDebugMode) debugPrint('[CallService] Permission denied');
          // _requestPermissions 在 web 分支已经把详细错误写进 state.errorMessage，
          // 这里不要覆盖；native 分支保持原有兜底消息。
          if (!kIsWeb) {
            state = state.copyWith(
              state: CallState.idle,
              errorMessage: '通话失败，请重试',
            );
          } else {
            state = state.copyWith(state: CallState.idle);
          }
          return false;
        }
      }
      if (kDebugMode) debugPrint('[CallService] Permissions & config ready');

      if (_isCallCancelledDuringAccept(originalCallId)) {
        if (kDebugMode) debugPrint('[CallService] Call was cancelled during permission/config');
        return false;
      }

      if (!_isEnabled || _appId == null || _appId!.isEmpty) {
        state = state.copyWith(
          state: CallState.idle,
          errorMessage: '音视频服务未启用',
        );
        return false;
      }

      if (kDebugMode) debugPrint('[CallService] Starting engine init & accept API...');

      final engineFuture = needEngine ? _initEngine() : Future.value();

      final response = await _api.post<Map<String, dynamic>>(
        '/call/accept',
        data: {'call_id': originalCallId},
      );

      if (!response.isSuccess || response.data == null) {
        if (kDebugMode) debugPrint('[CallService] Accept API failed: ${response.message}');
        if (response.message?.contains('cancelled') == true ||
            response.message?.contains('not found') == true) {
          state = state.copyWith(
            state: CallState.idle,
            errorMessage: '通话失败，请重试',
          );
        } else {
          state = state.copyWith(
            state: CallState.idle,
            errorMessage: '通话失败，请重试',
          );
        }
        return false;
      }
      if (kDebugMode) debugPrint('[CallService] Accept API success');

      await engineFuture;
      if (kDebugMode) debugPrint('[CallService] Engine initialized');

      if (_isCallCancelledDuringAccept(originalCallId)) {
        if (kDebugMode) debugPrint('[CallService] Call was cancelled after API/engine init');
        await _leaveChannel();
        return false;
      }

      if (_currentCallKitUuid != null &&
          (Platform.isIOS || Platform.isAndroid)) {
        FlutterCallkitIncoming.setCallConnected(
          _currentCallKitUuid!,
        );
      }

      final data = response.data!;
      final token = (data['token'] as String?) ?? '';

      if (token.isEmpty) {
        if (kDebugMode) debugPrint('[CallService] Accept call: token is empty');
        state = state.copyWith(errorMessage: '通话失败，请重试');
        return false;
      }

      _startConnectionTimeout();

      if (callType == CallType.video) {
        if (kDebugMode) debugPrint('[CallService] Enabling video...');
        await _engine!.enableVideo();
        // ★ Web 端**必须 await** startPreview：Iris Web 上这一步才真正调
        //   `createCameraVideoTrack()` + `getUserMedia({video})` 建立本地摄像头 track。
        //   如果不等它就 joinChannel(publishCameraTrack: true)，实际没有 track 可发
        //   ——对面（尤其 web-web）就收不到任何视频画面。5s 超时兜底避免 hang，
        //   慢速设备也基本够（跟 startCall 保持一致）。原生 APK 走 fire-and-forget
        //   保持原状，`AVCaptureSession` 打开延迟不阻塞主流程。
        if (kIsWeb) {
          try {
            await _engine!.startPreview().timeout(const Duration(seconds: 5));
          } catch (e) {
            if (kDebugMode) debugPrint('[CallService] web startPreview await error: $e');
          }
        } else {
          _engine!.startPreview().catchError((e) {
            if (kDebugMode) debugPrint('[CallService] startPreview error: $e');
          });
        }
      }

      // ★ Web 上等 iris_web 把 mic track 状态机跑稳（同 startCall）。
      if (kIsWeb) {
        await _waitForWebAudioReady();
      }

      if (kDebugMode) debugPrint('[CallService] Joining channel: $channelName');
      final isVideoCall = callType == CallType.video;
      await _engine!.joinChannel(
        token: token,
        channelId: channelName,
        uid: 0,
        options: ChannelMediaOptions(
          autoSubscribeAudio: true,
          autoSubscribeVideo: isVideoCall,
          publishMicrophoneTrack: true,
          publishCameraTrack: isVideoCall,
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
        ),
      );
      if (kDebugMode) debugPrint('[CallService] Joined channel successfully');

      WakelockPlus.enable();

      // ★ Web + 视频通话防御性推流：见 startCall 对应注释。
      if (kIsWeb && isVideoCall) {
        unawaited(_defensiveRepublishVideoAfterJoin());
      }

      return true;
    } catch (e, stack) {
      if (kDebugMode) debugPrint('[CallService] Accept call error: $e');
      if (kDebugMode) debugPrint('[CallService] Stack: $stack');

      final errorMessage = _classifyError(e, '接听');
      state = state.copyWith(state: CallState.idle, errorMessage: errorMessage);
      return false;
    } finally {
      _isAcceptingCall = false;
    }
  }

  Future<void> _loadConfigIfNeeded() async {
    if (_isEnabled && _appId != null && _appId!.isNotEmpty) {
      return;
    }
    await _loadConfig();
  }

  /// Web 视频通话专用：joinChannel 成功后 800ms 补一次显式 unmute，
  /// 兜住 startPreview 超时耗尽/camera track 建立晚于 joinChannel 的偶发竞态。
  /// 完全 web-only，native 不进这条路径。
  Future<void> _defensiveRepublishVideoAfterJoin() async {
    try {
      await Future<void>.delayed(const Duration(milliseconds: 800));
      if (_isDisposed || _engine == null) return;
      if (state.state != CallState.connecting &&
          state.state != CallState.connected) {
        return;
      }
      if (!state.isVideoEnabled) return; // 用户主动关了摄像头就不要偷偷打开

      if (kDebugMode) debugPrint('[CallService] Web: defensive republish video after join');
      // muteLocalVideoStream(false) 即使当前就是 unmute 也是安全的，
      // Agora Web SDK 内部会去比较状态，一致就 no-op；不一致就会触发一次
      // 显式的 unmute + republish 事件（对面能收到 onUserMuteVideo(false)）。
      try {
        await _engine!.muteLocalVideoStream(false);
      } catch (e) {
        if (kDebugMode) debugPrint('[CallService] defensive muteLocalVideoStream error: $e');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] defensive republish error: $e');
    }
  }

  bool _isPreloading = false;
  Future<void> _preloadForIncoming(CallType callType) async {
    if (_isPreloading) return;
    _isPreloading = true;

    try {
      if (kDebugMode) debugPrint('[CallService] Preloading for incoming call...');

      // ★ Web 端不能在被叫响铃前就调 getUserMedia——那会立刻弹权限窗，
      //   用户还没点"接听"就先被吓一跳。真正的授权推到 acceptCall 里再问。
      //   原生平台上 permission_handler 请求是走系统弹窗，可以提前预热。
      if (kIsWeb) {
        await _loadConfigIfNeeded();
      } else {
        await Future.wait([_loadConfigIfNeeded(), _requestPermissions(callType)]);
      }

      if (_isEnabled &&
          _appId != null &&
          _appId!.isNotEmpty &&
          _engine == null) {
        if (kDebugMode) debugPrint('[CallService] Pre-initializing engine...');
        await _initEngine();
        if (kDebugMode) debugPrint('[CallService] Engine pre-initialized');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] Preload error (non-fatal): $e');
    } finally {
      _isPreloading = false;
    }
  }

  bool _isCallCancelledDuringAccept(int? originalCallId) {
    if (state.state == CallState.connecting) {
      return state.callInfo?.callId != originalCallId;
    }
    if (state.state == CallState.idle) {
      return true;
    }
    return false;
  }

  bool _isCallCancelled(int? originalCallId) {
    if (state.state != CallState.incoming &&
        state.state != CallState.connecting) {
      return true;
    }
    if (state.callInfo?.callId != originalCallId) {
      return true;
    }
    return false;
  }

  String _classifyError(dynamic e, String action) {
    if (e is TimeoutException) {
      return '$action超时，请重试';
    }

    // Web 端专属：iris_web SDK 没加载好，前面 _doInitEngine 里抛的原始信息
    // 已经很清楚，直接透传给用户，比"通话失败，请重试"更有指向性。
    final rawMsg = e.toString();
    if (rawMsg.contains('Agora Web SDK 未加载')) {
      return rawMsg.replaceFirst('Exception: ', '');
    }

    if (e is AgoraRtcException) {
      switch (e.code) {
        case -2: // ERR_INVALID_ARGUMENT
          if (Platform.isMacOS) {
            return '通话失败，请重试';
          }
          return '通话失败，请重试';
        case -7: // ERR_NOT_INITIALIZED
          return '通话失败，请重试';
        case -17: // ERR_JOIN_CHANNEL_REJECTED
          return '通话失败，请重试';
        case 110: // ERR_TOKEN_EXPIRED
          return '通话失败，请重试';
        default:
          return '$action失败（错误码: ${e.code}）';
      }
    }

    final errorStr = e.toString().toLowerCase();
    if (errorStr.contains('socket') ||
        errorStr.contains('network') ||
        errorStr.contains('connection')) {
      return '通话失败，请重试';
    }

    return '$action失败，请重试';
  }

  Future<void> rejectCall({String reason = 'decline'}) async {
    if (_isDisposed) return;
    if (_isRejectingCall) return;
    if (state.state != CallState.incoming || state.callInfo == null) {
      return;
    }
    _isRejectingCall = true;

    _cancelIncomingCallTimeout();

    _callTimer?.cancel();
    _callTimer = null;

    if (DesktopNotificationService.isDesktop) {
      DesktopNotificationService().cancelCallNotification();
    }

    try {
      await _api.post(
        '/call/reject',
        data: {'call_id': state.callInfo!.callId, 'reason': reason},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] Reject call error: $e');
    }

    if (_isDisposed) return;

    if (_currentCallKitUuid != null && (Platform.isIOS || Platform.isAndroid)) {
      await FlutterCallkitIncoming.endCall(_currentCallKitUuid!);
    }

    _resetState();
  }

  Future<void> endCall({
    String reason = 'hangup',
    bool notifyServer = true,
  }) async {
    if (_isDisposed) return;
    if (_isEndingCall) return;
    if (!state.isInCall) return;
    _isEndingCall = true;
    _callTimer?.cancel();
    _callTimer = null;

    if (DesktopNotificationService.isDesktop) {
      DesktopNotificationService().cancelCallNotification();
    }

    try {
      if (notifyServer && state.callInfo?.callId != null) {
        await _api.post(
          '/call/end',
          data: {'call_id': state.callInfo!.callId, 'reason': reason},
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] End call error: $e');
    }

    if (_isDisposed) return;

    if (_currentCallKitUuid != null && (Platform.isIOS || Platform.isAndroid)) {
      await FlutterCallkitIncoming.endCall(_currentCallKitUuid!);
    }

    await _leaveChannel();
    onCallEnded?.call(reason);
    _resetState();
  }

  Future<void> cancelCall() async {
    if (_isDisposed) return;
    if (_isCancellingCall) return;
    if (state.state != CallState.outgoing || state.callInfo == null) {
      return;
    }
    _isCancellingCall = true;

    try {
      await _api.delete('/call/${state.callInfo!.callId}');
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] Cancel call error: $e');
    }

    if (_isDisposed) return;

    await _leaveChannel();
    _resetState();
  }

  void toggleMute() {
    if (_isDisposed) return;
    final newMuted = !state.isMuted;
    _engine?.muteLocalAudioStream(newMuted);
    state = state.copyWith(isMuted: newMuted);
  }

  void toggleSpeaker() {
    if (_isDisposed) return;
    // ★ setEnableSpeakerphone 只在 iOS/Android **原生**支持。
    //   web (含手机浏览器) 和桌面上 iris_web / native SDK 都会返回 -4，
    //   否则会抛未捕获的 AgoraRtcException，直接干扰其它逻辑。
    if (kIsWeb || Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return;
    }
    final newSpeaker = !state.isSpeakerOn;
    _engine?.setEnableSpeakerphone(newSpeaker);
    state = state.copyWith(isSpeakerOn: newSpeaker);
  }

  void toggleVideo() {
    if (_isDisposed) return;
    if (state.callInfo?.type != CallType.video) return;

    final newEnabled = !state.isVideoEnabled;

    // ★ Web 端专用路径：**绝对不能**在通话中调 enableVideo / disableVideo /
    //   startPreview / stopPreview。Iris Web SDK 上这些接口会真的**销毁并重建**
    //   camera track（`agora-rtc-sdk-ng` 的 `close()` + 重新 `createCameraVideoTrack()`），
    //   会引起：
    //     1) 本地/远端渲染错乱（HtmlElementView 的 <video> 元素被换掉，
    //        Positioned 位置失效 → 表现为"对面全屏了"）；
    //     2) unpublish/publish 状态机在竞态下卡死，出现"对面控制不了自己的页面"；
    //     3) 极端情况下再次 enableVideo 会 hang 住权限查询导致 -4。
    //   正确做法：track 保持存活，只用 muteLocalVideoStream 停止/恢复推流。
    //   本地预览是否显示由 UI 自己根据 isVideoEnabled 切占位图，跟 Agora 无关。
    if (kIsWeb) {
      _engine?.muteLocalVideoStream(!newEnabled);
      state = state.copyWith(isVideoEnabled: newEnabled);
      return;
    }

    // ★ 原生 iOS / Android / 桌面：改用 Agora 官方推荐的 **enableLocalVideo**，
    //   替代之前的 enableVideo / disableVideo。
    //   区别：
    //     - `disableVideo()` 会**重置整个 video 子系统**（包括接收），
    //       在对端上表现为奇怪的 remoteVideoState 变化，甚至导致对端画面被冻结/关闭
    //       ——这是问题 2「apk 开关摄像头把 web 端也给关闭」的根因。
    //     - `enableLocalVideo(false)` 只关本地摄像头**采集与推流**，
    //       不影响本地接收对端画面，也不重置 engine；对端只会看到干净的
    //       `onUserMuteVideo(true)` / `onRemoteVideoStateChanged(reason=RemoteMuted)`。
    //     - 关闭时释放摄像头硬件（Android 摄像头 LED 会熄灭，隐私 OK）。
    //   开启时按 Agora 文档要求，同时用 updateChannelMediaOptions 把
    //   `publishCameraTrack: true` 重新刷进 channel，否则重新 enable 后
    //   可能不会自动 republish。
    //   全部走 catchError 保证 fire-and-forget，UI 状态立刻反映。
    final engine = _engine;
    if (engine == null) {
      state = state.copyWith(isVideoEnabled: newEnabled);
      return;
    }

    if (newEnabled) {
      engine.enableLocalVideo(true).catchError((e) {
        if (kDebugMode) debugPrint('[CallService] enableLocalVideo(true) error: $e');
      });
      engine.updateChannelMediaOptions(const ChannelMediaOptions(
        publishCameraTrack: true,
      )).catchError((e) {
        if (kDebugMode) debugPrint('[CallService] updateChannelMediaOptions error: $e');
      });
      engine.muteLocalVideoStream(false).catchError((e) {
        if (kDebugMode) debugPrint('[CallService] muteLocalVideoStream(false) error: $e');
      });
    } else {
      engine.muteLocalVideoStream(true).catchError((e) {
        if (kDebugMode) debugPrint('[CallService] muteLocalVideoStream(true) error: $e');
      });
      engine.enableLocalVideo(false).catchError((e) {
        if (kDebugMode) debugPrint('[CallService] enableLocalVideo(false) error: $e');
      });
    }
    state = state.copyWith(isVideoEnabled: newEnabled);
  }

  Future<void> switchCamera() async {
    // ★ switchCamera 只在 iOS/Android 原生上有意义；
    //   web / 桌面上 iris_web 会返回 -4，这里同样短路避免抛异常。
    if (kIsWeb || Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return;
    }
    await _engine?.switchCamera();
  }

  void toggleMinimize() {
    state = state.copyWith(isMinimized: !state.isMinimized);
  }

  Duration get callDuration {
    if (state.callInfo?.connectTime == null) return Duration.zero;
    return DateTime.now().difference(state.callInfo!.connectTime!);
  }

  Widget getLocalView() {
    if (_engine == null) return const SizedBox();
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engine!,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }

  Widget getRemoteView() {
    if (_engine == null || state.callInfo?.remoteUid == null) {
      return const SizedBox();
    }
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine!,
        canvas: VideoCanvas(uid: state.callInfo!.remoteUid!),
        connection: RtcConnection(channelId: state.callInfo!.channelName),
      ),
    );
  }

  /// Web 上每个 Agora 调用最多等 800ms，超过就当它 hang 了直接放行。
  /// iOS Safari + iris_web 的 leaveChannel/release 底层 `RTCPeerConnection.close()`
  /// 有已知问题会**永远不 resolve**，之前的 `await` 就此挂住 → `_engine=null`
  /// 永远执行不到 → 下次 startCall 复用死引擎，唯一恢复方法就是刷页面。
  ///
  /// Native 端不需要，agora_rtc_engine 原生 SDK 是可靠同步的。
  Future<void> _webCallWithTimeout(
    Future<void> Function() op,
    String tag,
  ) async {
    try {
      await op().timeout(
        const Duration(milliseconds: 800),
        onTimeout: () {
          if (kDebugMode) debugPrint('[CallService] $tag timed out (web hang), skipping');
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] $tag failed: $e (ignored)');
    }
  }

  Future<void> _leaveChannel() async {
    _callTimer?.cancel();
    _callTimer = null;
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _cancelOutgoingCallTimeout();

    // ★ 关键：无论中间任何一步抛异常/hang，都必须走到 finally 里把 _engine 置 null。
    //   之前用普通 try/catch，任一 await hang 后面全部跳过、_engine 永远非空，
    //   下次 startCall 看到 _engine != null 直接复用死引擎，通话废了——这就是
    //   iOS Safari 上"第一次能用，之后必须刷新才能再打"的根因。
    final engineRef = _engine;
    final handlerRef = _eventHandler;
    _engine = null;
    _eventHandler = null;

    try {
      if (engineRef != null && handlerRef != null) {
        try {
          engineRef.unregisterEventHandler(handlerRef);
        } catch (_) {}
      }

      if (engineRef != null) {
        if (kIsWeb) {
          // web: 每个调用带 800ms 超时，防止 iris_web 单个 API hang 死主流程
          await _webCallWithTimeout(() => engineRef.leaveChannel(), 'leaveChannel');
          await _webCallWithTimeout(() => engineRef.stopPreview(), 'stopPreview');
          // ★ iris_web 的 release() 只 dispose client，不会主动关掉
          //   createMicrophoneAudioTrack 出来的 MediaStreamTrack。必须显式
          //   disableAudio/Video，否则下一通 enableAudio 拿到僵尸 track。
          await _webCallWithTimeout(() => engineRef.disableAudio(), 'disableAudio');
          await _webCallWithTimeout(() => engineRef.disableVideo(), 'disableVideo');
          await _webCallWithTimeout(() => engineRef.release(), 'release');
        } else {
          // native: 原生 SDK 可靠，正常 await 就行
          try { await engineRef.leaveChannel(); } catch (_) {}
          try { await engineRef.stopPreview(); } catch (_) {}
          try { await engineRef.release(); } catch (_) {}
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] Leave channel outer error: $e');
    } finally {
      // Pending 的 web-audio-ready completer 现在也没有对应 engine 会 emit 事件了，
      // 主动清掉，避免下一次 startCall 拿到 stale 引用。
      final c = _webAudioReadyCompleter;
      if (c != null && !c.isCompleted) {
        try { c.complete(); } catch (_) {}
      }
      _webAudioReadyCompleter = null;

      // ★ Web 上 release() 是异步的（iris_web 内部 client.dispose 走 microtask 队列），
      //   立刻新建 engine 会撞到还没散场的旧 client。给浏览器/iris_web 一个短暂
      //   settle 时间，让 mic track 真正 stop、client 真正 dispose。
      //
      //   iOS Safari 特别慢：WebKit 的 PeerConnection.close() 是异步的，
      //   MediaStreamTrack.stop() 之后浏览器要 ~1s 才真正释放硬件占用。
      if (kIsWeb) {
        final settleMs = _isIosSafariLike() ? 1200 : 300;
        try {
          await Future<void>.delayed(Duration(milliseconds: settleMs));
        } catch (_) {}
      }

      WakelockPlus.disable();
    }
  }

  void _resetState() {
    _callTimer?.cancel();
    _callTimer = null;
    _currentCallKitUuid = null;
    _isHandlingCallKitAccept = false;
    _isAcceptingCall = false;
    _isEndingCall = false;
    _isRejectingCall = false;
    _isCancellingCall = false;
    _isPreloading = false;
    WakelockPlus.disable();

    if (_isDisposed) return;

    // ★ Web (尤其 iOS Safari) 上不能靠 addPostFrameCallback：那底层是 rAF，
    //   Safari 在标签页失焦 / 低电模式 / 后台化时会**完全暂停** rAF，
    //   于是 `state = const CallServiceState()` 永远不 fire，state 卡在
    //   outgoing/connected，下次拨号会被 startCall 里的 `state.isInCall` 判成
    //   "忙线"直接失败，来电也被 handleIncomingCall 自动 reject。
    //   Web 改用 microtask，Native 保持原逻辑（避免 build 阶段改 state）。
    if (kIsWeb) {
      scheduleMicrotask(() {
        if (!_isDisposed) {
          state = const CallServiceState();
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed) {
          state = const CallServiceState();
        }
      });
    }
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isDisposed) {
        _callTimer?.cancel();
        _callTimer = null;
        return;
      }
      if (state.state != CallState.connected) {
        _callTimer?.cancel();
        _callTimer = null;
      }
    });
  }

  void _setupCallKit() {
    _callKitSubscription?.cancel();
    _callKitSubscription = FlutterCallkitIncoming.onEvent.listen((event) async {
      if (kDebugMode) debugPrint(
        '[CallService] CallKit event: ${event?.event}, body: ${event?.body}',
      );
      switch (event?.event) {
        case Event.actionCallAccept:
          if (kDebugMode) debugPrint('[CallService] CallKit: actionCallAccept');
          await _handleCallKitAccept();
          break;
        case Event.actionCallDecline:
          if (kDebugMode) debugPrint('[CallService] CallKit: actionCallDecline');
          await rejectCall();
          break;
        case Event.actionCallEnded:
          if (kDebugMode) debugPrint(
            '[CallService] CallKit: actionCallEnded, currentState=${state.state}',
          );
          if (state.state == CallState.incoming) {
            await rejectCall(reason: 'dismissed');
          } else if (state.isInCall) {
            await endCall();
          }
          break;
        case Event.actionCallStart:
          if (kDebugMode) debugPrint('[CallService] CallKit: actionCallStart (outgoing)');
          break;
        case Event.actionCallIncoming:
          if (kDebugMode) debugPrint('[CallService] CallKit: actionCallIncoming');
          final payload = _incomingPayloadFromCallKitData(event?.body);
          if (payload != null && !state.isInCall) {
            await handleIncomingCall(payload);
          }
          break;
        case Event.actionCallTimeout:
          if (kDebugMode) debugPrint('[CallService] CallKit: actionCallTimeout');
          await rejectCall(reason: 'timeout');
          break;
        case Event.actionCallToggleHold:
          if (kDebugMode) debugPrint('[CallService] CallKit: actionCallToggleHold');
          break;
        case Event.actionCallToggleMute:
          if (kDebugMode) debugPrint('[CallService] CallKit: actionCallToggleMute');
          toggleMute();
          break;
        case Event.actionCallToggleDmtf:
          if (kDebugMode) debugPrint('[CallService] CallKit: actionCallToggleDmtf');
          break;
        case Event.actionCallToggleGroup:
          if (kDebugMode) debugPrint('[CallService] CallKit: actionCallToggleGroup');
          break;
        case Event.actionCallToggleAudioSession:
          if (kDebugMode) debugPrint('[CallService] CallKit: actionCallToggleAudioSession');
          break;
        case Event.actionDidUpdateDevicePushTokenVoip:
          if (kDebugMode) debugPrint(
            '[CallService] CallKit: actionDidUpdateDevicePushTokenVoip',
          );
          break;
        default:
          if (kDebugMode) debugPrint('[CallService] CallKit: unknown event ${event?.event}');
          break;
      }
    });
  }

  Future<void> _handleCallKitAccept() async {
    if (_isHandlingCallKitAccept) {
      if (kDebugMode) debugPrint(
        '[CallService] CallKit accept already being handled, ignoring',
      );
      return;
    }
    _isHandlingCallKitAccept = true;

    try {
      if (_currentCallKitUuid != null) {
        try {
          await FlutterCallkitIncoming.setCallConnected(_currentCallKitUuid!);
        } catch (e) {
          if (kDebugMode) debugPrint('[CallService] setCallConnected error: $e');
        }
      }

      await Future.delayed(const Duration(milliseconds: 200));

      if (state.state != CallState.incoming || state.callInfo == null) {
        if (kDebugMode) debugPrint('[CallService] CallKit accept: call no longer incoming');
        return;
      }

      final success = await acceptCall().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          if (kDebugMode) debugPrint('[CallService] CallKit accept timeout');
          state = state.copyWith(errorMessage: '接听超时，请重试');
          return false;
        },
      );

      if (kDebugMode) debugPrint('[CallService] CallKit acceptCall result: $success');

      if (success) {
        if (kDebugMode) debugPrint(
          '[CallService] CallKit accept success, triggering onCallAccepted',
        );
        await Future.delayed(const Duration(milliseconds: 100));
        onCallAccepted?.call();
      } else {
        if (kDebugMode) debugPrint('[CallService] CallKit accept failed');
        if (state.state == CallState.incoming ||
            state.state == CallState.idle) {
          if (_currentCallKitUuid != null) {
            try {
              await FlutterCallkitIncoming.endCall(_currentCallKitUuid!);
            } catch (e) {
              if (kDebugMode) debugPrint('[CallService] endCall error: $e');
            }
          }
          onCallFailed?.call(state.errorMessage ?? '接听失败');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[CallService] CallKit accept error: $e');
      if (_currentCallKitUuid != null &&
          state.state != CallState.connecting &&
          state.state != CallState.connected) {
        try {
          await FlutterCallkitIncoming.endCall(_currentCallKitUuid!);
        } catch (endError) {
          if (kDebugMode) debugPrint('[CallService] endCall error: $endError');
        }
      }
      state = state.copyWith(errorMessage: '通话失败，请重试');
      onCallFailed?.call('接听通话失败: $e');
    } finally {
      _isHandlingCallKitAccept = false;
    }
  }

  VoidCallback? onCallAccepted;

  Future<void> _showCallKit(CallInfo callInfo) async {
    _currentCallKitUuid = const Uuid().v4();

    final params = CallKitParams(
      id: _currentCallKitUuid!,
      nameCaller: callInfo.remoteName,
      appName: '\u58f9\u8f6fIM',
      avatar: callInfo.remoteAvatar,
      handle: callInfo.remoteName,
      type: callInfo.type == CallType.video ? 1 : 0,
      duration: 30000,
      textAccept: '\u63a5\u542c',
      textDecline: '\u62d2\u7edd',
      extra: _incomingPayloadFromCallInfo(callInfo),
      headers: <String, dynamic>{},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#5865F2',
        backgroundUrl: '',
        actionColor: '#4CAF50',
        textColor: '#FFFFFF',
        isShowFullLockedScreen: true,
        isShowCallID: false,
        incomingCallNotificationChannelName: '\u6765\u7535\u901a\u77e5',
      ),
      ios: const IOSParams(
        iconName: 'CallKitLogo',
        handleType: 'generic',
        supportsVideo: true,
        maximumCallGroups: 2,
        maximumCallsPerCallGroup: 1,
        audioSessionMode: 'default',
        audioSessionActive: false,
        audioSessionPreferredSampleRate: 44100.0,
        audioSessionPreferredIOBufferDuration: 0.005,
        configureAudioSession: false,
        supportsDTMF: true,
        supportsHolding: true,
        supportsGrouping: false,
        supportsUngrouping: false,
        ringtonePath: '',
      ),
    );

    await FlutterCallkitIncoming.showCallkitIncoming(params);
  }

  void handleCallAccepted() {
    if (state.state == CallState.outgoing) {
      state = state.copyWith(state: CallState.connecting);
    }
  }

  Future<void> handleCallRejected(String reason) async {
    await _leaveChannel();
    onCallEnded?.call(reason);
    _resetState();
  }

  void handleCallCancelled() {
    _cancelIncomingCallTimeout();

    if (_currentCallKitUuid != null && (Platform.isIOS || Platform.isAndroid)) {
      FlutterCallkitIncoming.endCall(_currentCallKitUuid!);
    }
    onCallEnded?.call('cancelled');
    _resetState();
  }

  @override
  void dispose() {
    _isDisposed = true;

    if (state.isInCall) {
      endCall(reason: 'service_disposed');
    }

    _callKitSubscription?.cancel();
    _callKitSubscription = null;

    for (final id in _wsHandlerIds) {
      _wsService.unregisterHandler(id);
    }
    _wsHandlerIds.clear();

    _callTimer?.cancel();
    _callTimer = null;
    _incomingCallTimer?.cancel();
    _incomingCallTimer = null;
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _outgoingCallTimer?.cancel();
    _outgoingCallTimer = null;

    if (_eventHandler != null && _engine != null) {
      _engine!.unregisterEventHandler(_eventHandler!);
      _eventHandler = null;
    }
    _engine?.release();
    _engine = null;

    onIncomingCall = null;
    onCallConnected = null;
    onCallEnded = null;
    onCallFailed = null;
    onCallAccepted = null;

    WakelockPlus.disable();
    super.dispose();
  }
}

/// Provider
final callServiceProvider =
    StateNotifierProvider<CallService, CallServiceState>((ref) {
  final api = ref.watch(apiClientProvider);
  final wsService = ref.watch(webSocketServiceProvider.notifier);
  return CallService(api, wsService);
});
