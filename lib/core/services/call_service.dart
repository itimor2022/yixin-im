// 文件用途：封装 CallState 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：协调呼叫信令、Agora/LiveKit 会话、权限和音视频状态，在重连、降级和结束时同步本地与服务端状态。
import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:uuid/uuid.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';

import '../i18n/app_localizations.dart';
import '../i18n/server_message_localizer.dart';
import 'api/api_client.dart';
import 'api/system_settings_service.dart';
import 'api/websocket_service.dart';
import 'android_callkit_helper.dart';
import 'call_end_tone_service.dart';
import 'desktop_notification_service.dart';
import 'outgoing_call_tone_service.dart';

String _callServiceText({
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

String _genericCallFailureText() => _callServiceText(
      zhCN: '\u901a\u8bdd\u5931\u8d25\uff0c\u8bf7\u91cd\u8bd5',
      zhTW: '\u901a\u8a71\u5931\u6557\uff0c\u8acb\u91cd\u8a66',
      en: 'Call failed. Please try again.',
    );

String _callServerMessage(String? raw, {required String fallbackEn}) {
  return localizeServerMessage(raw, fallbackEn: fallbackEn);
}

String _blockedCallText() => _callServiceText(
      zhCN:
          '\u5df2\u5c4f\u853d\u8be5\u7528\u6237\uff0c\u65e0\u6cd5\u53d1\u8d77\u901a\u8bdd',
      zhTW:
          '\u5df2\u5c01\u9396\u8a72\u7528\u6236\uff0c\u7121\u6cd5\u767c\u8d77\u901a\u8a71',
      en: 'This user is blocked. Unable to start a call.',
    );

String _mediaServiceUnavailableText() => _callServiceText(
      zhCN: '\u97f3\u89c6\u9891\u670d\u52a1\u672a\u542f\u7528',
      zhTW: '\u97f3\u8a0a\u8207\u8996\u8a0a\u670d\u52d9\u672a\u555f\u7528',
      en: 'Audio and video service is not enabled',
    );

String _callConnectionNotReadyText() => _callServiceText(
      zhCN:
          '\u901a\u8bdd\u8fde\u63a5\u672a\u5c31\u7eea\uff0c\u8bf7\u7a0d\u540e\u91cd\u8bd5',
      zhTW:
          '\u901a\u8a71\u9023\u7dda\u672a\u5c31\u7dd2\uff0c\u8acb\u7a0d\u5f8c\u91cd\u8a66',
      en: 'Call connection is not ready. Please try again later.',
    );

String _callAlreadyInProgressText() => _callServiceText(
      zhCN: '\u5df2\u5728\u901a\u8bdd\u4e2d',
      zhTW: '\u5df2\u5728\u901a\u8a71\u4e2d',
      en: 'A call is already in progress.',
    );

String _callActionText(String actionKey) {
  switch (actionKey) {
    case 'answer':
      return _callServiceText(
        zhCN: '\u63a5\u542c',
        zhTW: '\u63a5\u807d',
        en: 'Answer',
      );
    case 'decline':
      return _callServiceText(
        zhCN: '\u62d2\u7edd',
        zhTW: '\u62d2\u7d55',
        en: 'Decline',
      );
    case 'call':
    default:
      return _callServiceText(
        zhCN: '\u901a\u8bdd',
        zhTW: '\u901a\u8a71',
        en: 'Call',
      );
  }
}

// 关键声明：call service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
enum CallState {
  idle,
  outgoing,
  incoming,
  connecting,
  connected,
  reconnecting,
  ended,
}

enum CallType { voice, video }

enum CallPermissionIssue {
  microphoneDenied,
  microphonePermanentlyDenied,
  cameraDenied,
  cameraPermanentlyDenied,
}

bool callPermissionSupportsVoiceFallback(CallPermissionIssue? issue) {
  return issue == CallPermissionIssue.cameraDenied ||
      issue == CallPermissionIssue.cameraPermanentlyDenied;
}

int callReconnectSecondsRemaining(DateTime deadline, DateTime now) {
  final milliseconds = deadline.difference(now).inMilliseconds;
  if (milliseconds <= 0) return 0;
  return (milliseconds / Duration.millisecondsPerSecond).ceil();
}

int callElapsedSeconds(DateTime? connectedAt, DateTime now) {
  if (connectedAt == null) return 0;
  final seconds = now.difference(connectedAt).inSeconds;
  return seconds < 0 ? 0 : seconds;
}

bool incomingCallIsExpired(String? rawExpiresAt, DateTime now) {
  return incomingCallExpiryPassed(rawExpiresAt, now);
}

String _normalizeRtcProvider(String? provider) {
  return provider?.trim().toLowerCase() == 'livekit' ? 'livekit' : 'agora';
}

String _stableIosCallKitUuid(int callId) {
  final digest = sha256.convert(utf8.encode('genericim-call-$callId')).bytes;
  String byteHex(int index) => digest[index].toRadixString(16).padLeft(2, '0');
  return '${byteHex(0)}${byteHex(1)}${byteHex(2)}${byteHex(3)}-'
      '${byteHex(4)}${byteHex(5)}-'
      '${byteHex(6)}${byteHex(7)}-'
      '${byteHex(8)}${byteHex(9)}-'
      '${byteHex(10)}${byteHex(11)}${byteHex(12)}'
      '${byteHex(13)}${byteHex(14)}${byteHex(15)}';
}

String _firstStringValue(Map<String, dynamic> data, List<String> keys) {
  for (final key in keys) {
    final value = data[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return '';
}

int? _intValue(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

bool _truthyValue(dynamic value) {
  if (value == true) return true;
  final normalized = value?.toString().trim().toLowerCase();
  return normalized == 'true' || normalized == '1' || normalized == 'yes';
}

class CallInfo {
  final int? callId;
  final String channelName;
  final String roomName;
  final String rtcProvider;
  final String? serverUrl;
  final String? identity;
  final String? remoteIdentity;
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
    String? roomName,
    this.rtcProvider = 'agora',
    this.serverUrl,
    this.identity,
    this.remoteIdentity,
    required this.remoteUserId,
    required this.remoteName,
    this.remoteAvatar,
    required this.type,
    required this.isOutgoing,
    DateTime? startTime,
    this.connectTime,
    this.remoteUid,
  })  : roomName = roomName ?? channelName,
        startTime = startTime ?? DateTime.now();

  CallInfo copyWith({
    int? callId,
    String? channelName,
    String? roomName,
    String? rtcProvider,
    String? serverUrl,
    String? identity,
    String? remoteIdentity,
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
      roomName: roomName ?? this.roomName,
      rtcProvider: rtcProvider ?? this.rtcProvider,
      serverUrl: serverUrl ?? this.serverUrl,
      identity: identity ?? this.identity,
      remoteIdentity: remoteIdentity ?? this.remoteIdentity,
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

/// 通话业务状态的页面投影；服务端信令状态与 RTC 媒体连接由 [CallService] 协调后写入。
class CallServiceState {
  final CallState state;
  final CallInfo? callInfo;
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isVideoEnabled;
  final bool isRemoteVideoEnabled;
  final bool isMinimized;
  final String? errorMessage;
  final int reconnectSecondsRemaining;
  final CallPermissionIssue? permissionIssue;

  const CallServiceState({
    this.state = CallState.idle,
    this.callInfo,
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isVideoEnabled = true,
    this.isRemoteVideoEnabled = true,
    this.isMinimized = false,
    this.errorMessage,
    this.reconnectSecondsRemaining = 0,
    this.permissionIssue,
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
    int? reconnectSecondsRemaining,
    CallPermissionIssue? permissionIssue,
    bool clearPermissionIssue = false,
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
      reconnectSecondsRemaining:
          reconnectSecondsRemaining ?? this.reconnectSecondsRemaining,
      permissionIssue: clearPermissionIssue
          ? null
          : (permissionIssue ?? this.permissionIssue),
    );
  }

  bool get isInCall =>
      state == CallState.outgoing ||
      state == CallState.incoming ||
      state == CallState.connecting ||
      state == CallState.connected ||
      state == CallState.reconnecting;
}

/// 单人通话状态机，统一协调 HTTP/WS 信令、Agora/LiveKit 媒体层和系统 CallKit。
///
/// 服务端 callId 是业务会话身份；RTC channel/room 只承载媒体，不能单独证明通话仍有效。
class CallService extends StateNotifier<CallServiceState> {
  final ApiClient _api;
  final WebSocketService _wsService;
  final CallEndToneService _callEndTone;
  final OutgoingCallToneService _outgoingCallTone;
  RtcEngine? _engine;
  Timer? _callTimer;
  Timer? _callHeartbeatTimer;
  Timer? _outgoingCallTimer;
  Timer? _reconnectTimer;
  DateTime? _reconnectDeadline;
  Future<void>? _localCleanupFuture;
  Future<void>? _leaveChannelFuture;
  String? _appId;
  String _rtcProvider = 'agora';
  String? _liveKitServerUrl;
  lk.Room? _liveKitRoom;
  lk.EventsListener<lk.RoomEvent>? _liveKitListener;
  lk.LocalVideoTrack? _liveKitLocalVideoTrack;
  lk.RemoteVideoTrack? _liveKitRemoteVideoTrack;
  String? _liveKitRemoteIdentity;
  bool _isEnabled = false;
  bool _isSimulator = false;

  // CallKit UUID
  String? _currentCallKitUuid;
  static const MethodChannel _iosNativeCallKitChannel =
      MethodChannel('com.genericim/push');

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

  bool _isDisposed = false;
  bool _restoreVideoAfterBackground = false;

  CallService(
    this._api,
    this._wsService, {
    CallEndToneService? callEndTone,
    OutgoingCallToneService? outgoingCallTone,
  })  : _callEndTone = callEndTone ?? CallEndToneService(),
        _outgoingCallTone = outgoingCallTone ?? OutgoingCallToneService(),
        super(const CallServiceState()) {
    _init();
  }

  Future<void> _init() async {
    try {
      await _checkSimulator();

      // 系统来电 UI 仅在移动真机启用；Web/桌面仍共享同一套 WS 信令状态机。
      if (!kIsWeb && !_isSimulator && (Platform.isIOS || Platform.isAndroid)) {
        _setupCallKit();
      }

      _setupWebSocketListeners();
    } catch (e) {
      debugPrint('[CallService] Init error: $e');
    }
  }

  Future<void> ensureConfigLoaded() async {
    if (_configLoaded || _isDisposed) return;
    try {
      await _loadConfig();
      _configLoaded = true;
    } catch (e) {
      debugPrint('[CallService] Load config error: $e');
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
        debugPrint('[CallService] Running on simulator');
      }
    } catch (e) {
      debugPrint('[CallService] Check simulator error: $e');
    }
  }

  void _setupWebSocketListeners() {
    debugPrint('[CallService] Setting up WebSocket listeners');

    for (final id in _wsHandlerIds) {
      _wsService.unregisterHandler(id);
    }
    _wsHandlerIds.clear();

    final incomingId = _wsService.registerHandler(WSMessageType.incomingCall, (
      data,
    ) {
      debugPrint('[CallService] ========== INCOMING CALL ==========');
      debugPrint(
          '[CallService] Incoming call data: ${_sensitiveMapSummary(data)}');
      debugPrint(
        '[CallService] isSimulator: $_isSimulator, isEnabled: $_isEnabled',
      );
      final callData = data['data'] as Map<String, dynamic>?;
      if (callData != null) {
        handleIncomingCall(callData);
      } else {
        debugPrint('[CallService] ERROR: callData is null!');
      }
    });
    _wsHandlerIds.add(incomingId);

    final acceptedId = _wsService.registerHandler(WSMessageType.callAccepted, (
      data,
    ) {
      debugPrint('[CallService] Call accepted');
      final payload = _asStringKeyMap(data['data']);
      handleCallAccepted(payload);
    });
    _wsHandlerIds.add(acceptedId);

    final rejectedId = _wsService.registerHandler(WSMessageType.callRejected, (
      data,
    ) {
      debugPrint('[CallService] Call rejected: ${_sensitiveMapSummary(data)}');
      final payload = _asStringKeyMap(data['data']);
      final reason = payload?['reason']?.toString() ?? 'decline';
      handleCallRejected(reason, payload);
    });
    _wsHandlerIds.add(rejectedId);

    final endedId = _wsService.registerHandler(WSMessageType.callEnded, (data) {
      debugPrint('[CallService] Call ended: ${_sensitiveMapSummary(data)}');
      final payload = _asStringKeyMap(data['data']);
      unawaited(_handleRemoteCallEnded(payload));
    });
    _wsHandlerIds.add(endedId);

    final releasedId = _wsService.registerHandler(
      WSMessageType.callReleased,
      (data) {
        debugPrint(
            '[CallService] Call released: ${_sensitiveMapSummary(data)}');
        final payload = _asStringKeyMap(data['data']);
        unawaited(_handleRemoteCallEnded(payload));
      },
    );
    _wsHandlerIds.add(releasedId);

    final cancelledId = _wsService.registerHandler(
      WSMessageType.callCancelled,
      (data) {
        debugPrint('[CallService] Call cancelled');
        final payload = _asStringKeyMap(data['data']);
        unawaited(handleCallCancelled(payload));
      },
    );
    _wsHandlerIds.add(cancelledId);

    final mediaChangedId = _wsService.registerHandler(
      WSMessageType.callMediaChanged,
      (data) {
        final payload = _asStringKeyMap(data['data']);
        if (payload != null) {
          unawaited(_handleRemoteMediaChanged(payload));
        }
      },
    );
    _wsHandlerIds.add(mediaChangedId);

    final reconnectedId = _wsService.registerHandler(
      WSMessageType.reconnected,
      (_) {
        // A terminal event can be lost while the socket is reconnecting. The
        // server remains authoritative, so reconcile local ringing/call state.
        unawaited(syncActiveCallStateWithServer());
      },
    );
    _wsHandlerIds.add(reconnectedId);
  }

  Future<void> _loadConfig() async {
    try {
      final response = await _api.get<Map<String, dynamic>>('/call/config');
      if (response.isSuccess && response.data != null) {
        final data = response.data!;
        _isEnabled = data['enabled'] == true;
        _appId = data['app_id']?.toString();
        _rtcProvider = _normalizeRtcProvider(
          _firstStringValue(data, ['rtc_provider', 'provider']),
        );
        _liveKitServerUrl = _firstStringValue(
          data,
          ['livekit_server_url', 'server_url'],
        );
        if (_liveKitServerUrl?.isEmpty == true) {
          _liveKitServerUrl = null;
        }
        final appIdPreview = (_appId == null || _appId!.isEmpty)
            ? '-'
            : (_appId!.length > 8 ? '${_appId!.substring(0, 8)}...' : _appId!);
        debugPrint(
          '[CallService] Enabled: $_isEnabled, provider=$_rtcProvider, AppId: $appIdPreview, LiveKit=${_liveKitServerUrl?.isNotEmpty == true}',
        );
      }
    } catch (e) {
      debugPrint('[CallService] Load config error: $e');
    }
  }

  bool _hasRtcConfig(String provider) {
    if (provider == 'livekit') {
      return _liveKitServerUrl != null && _liveKitServerUrl!.isNotEmpty;
    }
    return _appId != null && _appId!.isNotEmpty;
  }

  String _providerFromData(
    Map<String, dynamic> data, {
    String? fallback,
  }) {
    final provider = _firstStringValue(data, ['rtc_provider', 'provider']);
    if (provider.isNotEmpty) {
      return _normalizeRtcProvider(provider);
    }
    return _normalizeRtcProvider(fallback ?? _rtcProvider);
  }

  String? _serverUrlFromData(Map<String, dynamic> data) {
    final value = _firstStringValue(
      data,
      ['server_url', 'livekit_server_url'],
    );
    if (value.isNotEmpty) return value;
    return _liveKitServerUrl;
  }

  bool get isEnabled {
    if (!_isEnabled || !_hasRtcConfig(_rtcProvider)) {
      return false;
    }
    return true;
  }

  String? _callUnavailableReason() {
    if (!_isEnabled || !_hasRtcConfig(_rtcProvider)) {
      return _mediaServiceUnavailableText();
    }
    return null;
  }

  Future<void> syncActiveCallStateWithServer({
    bool releaseServerWhenLocalIdle = false,
  }) async {
    if (_isDisposed) return;
    try {
      final response = await _api.get<Map<String, dynamic>>('/call/active');
      if (!response.isSuccess || response.data == null) return;
      final data = response.data!;
      final active = data['active'] == true;
      if (!active && state.isInCall) {
        debugPrint(
            '[CallService] Server has no active call, clearing local state');
        await _finishCallLocally('server_inactive');
        return;
      }
      if (active && !state.isInCall) {
        final status = data['status']?.toString();
        final role = data['role']?.toString();
        final callId = _intValue(data['call_id']) ?? 0;
        final startTime =
            DateTime.tryParse(data['start_time']?.toString() ?? '');
        final age = startTime == null
            ? Duration.zero
            : DateTime.now().difference(startTime);
        if (releaseServerWhenLocalIdle && callId > 0) {
          if (status == 'calling' && role == 'caller') {
            debugPrint('[CallService] Cancelling stale outgoing call: $callId');
            await _cancelCallById(callId);
          } else {
            debugPrint('[CallService] Ending stale active call: $callId');
            await _endCallById(callId, 'client_reset');
          }
          return;
        }
        if (status == 'calling' &&
            role == 'caller' &&
            callId > 0 &&
            age > const Duration(seconds: 15)) {
          debugPrint('[CallService] Cancelling orphan outgoing call: $callId');
          await _cancelCallById(callId);
        }
      }
    } catch (e) {
      debugPrint('[CallService] Sync active call state error: $e');
    }
  }

  Future<CallType?> _requestPermissions(
    CallType type, {
    bool allowVideoDowngrade = false,
  }) async {
    try {
      if (kIsWeb) {
        debugPrint(
          '[CallService] Web platform, browser will handle media permissions',
        );
        return type;
      }
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        debugPrint(
          '[CallService] Desktop platform, system will handle permissions',
        );
        return type;
      }

      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) {
        debugPrint('[CallService] Microphone permission denied');
        state = state.copyWith(
          errorMessage: _callServiceText(
            zhCN: micStatus.isPermanentlyDenied
                ? '麦克风权限已被永久拒绝，请前往系统设置开启'
                : '需要麦克风权限才能通话',
            zhTW: micStatus.isPermanentlyDenied
                ? '麥克風權限已被永久拒絕，請前往系統設定開啟'
                : '需要麥克風權限才能通話',
            en: micStatus.isPermanentlyDenied
                ? 'Microphone access is permanently denied. Enable it in system settings.'
                : 'Microphone access is required for calls.',
          ),
          permissionIssue: micStatus.isPermanentlyDenied
              ? CallPermissionIssue.microphonePermanentlyDenied
              : CallPermissionIssue.microphoneDenied,
        );
        return null;
      }

      if (type == CallType.video) {
        final cameraStatus = await Permission.camera.request();
        if (!cameraStatus.isGranted) {
          debugPrint('[CallService] Camera permission denied');
          state = state.copyWith(
            errorMessage: _callServiceText(
              zhCN: cameraStatus.isPermanentlyDenied
                  ? '相机权限已被永久拒绝，可改用语音或前往系统设置开启'
                  : '相机权限未开启，可改用语音通话',
              zhTW: cameraStatus.isPermanentlyDenied
                  ? '相機權限已被永久拒絕，可改用語音或前往系統設定開啟'
                  : '相機權限未開啟，可改用語音通話',
              en: cameraStatus.isPermanentlyDenied
                  ? 'Camera access is permanently denied. Use voice or enable it in system settings.'
                  : 'Camera access is unavailable. You can continue with a voice call.',
            ),
            permissionIssue: cameraStatus.isPermanentlyDenied
                ? CallPermissionIssue.cameraPermanentlyDenied
                : CallPermissionIssue.cameraDenied,
            isVideoEnabled: false,
          );
          return allowVideoDowngrade ? CallType.voice : null;
        }
      }

      if (Platform.isAndroid) {
        await Permission.bluetoothConnect.request();
      }
    } catch (e) {
      debugPrint('[CallService] Permission request error: $e');
      state = state.copyWith(
        errorMessage: _callServiceText(
          zhCN: '无法确认通话权限，请重试或前往系统设置检查',
          zhTW: '無法確認通話權限，請重試或前往系統設定檢查',
          en: 'Unable to verify call permissions. Retry or check system settings.',
        ),
        permissionIssue: CallPermissionIssue.microphoneDenied,
      );
      return null;
    }

    state = state.copyWith(clearPermissionIssue: true, clearError: true);
    return type;
  }

  Future<bool> openCallPermissionSettings() => openAppSettings();

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

  Future<void> _initEngineWithWebRetry() async {
    const maxAttempts = kIsWeb ? 12 : 1;
    Object? lastError;
    StackTrace? lastStack;

    for (var attempt = 1; attempt <= maxAttempts; attempt += 1) {
      try {
        await _initEngine();
        return;
      } catch (error, stack) {
        lastError = error;
        lastStack = stack;
        _eventHandler = null;
        _engine = null;
        if (!kIsWeb || attempt == maxAttempts) {
          Error.throwWithStackTrace(error, stack);
        }
        debugPrint(
          '[CallService] Agora web engine init attempt $attempt failed: $error',
        );
        final delayMs = 250 * attempt > 1000 ? 1000 : 250 * attempt;
        await Future.delayed(Duration(milliseconds: delayMs));
      }
    }

    if (lastError != null && lastStack != null) {
      Error.throwWithStackTrace(lastError, lastStack);
    }
  }

  Future<void> _doInitEngine() async {
    if (_engine != null) return;
    if (_appId == null || _appId!.isEmpty) {
      throw Exception('App ID not configured');
    }

    _engine = createAgoraRtcEngine();
    await _engine!.initialize(
      RtcEngineContext(
        appId: _appId!,
        channelProfile: ChannelProfileType.channelProfileCommunication,
      ),
    );

    _eventHandler = RtcEngineEventHandler(
      onJoinChannelSuccess: (connection, elapsed) {
        debugPrint('[Agora] Join channel success: ${connection.channelId}');
      },
      onUserJoined: (connection, remoteUid, elapsed) {
        debugPrint('[Agora] User joined: $remoteUid');
        _markCallConnected(remoteUid: remoteUid, source: 'agora_user_joined');
      },
      onUserOffline: (connection, remoteUid, reason) {
        debugPrint('[Agora] User offline: $remoteUid, reason: $reason');
        if (_isDisposed) return;
        _beginReconnect('agora_remote_offline');
      },
      onRemoteVideoStateChanged:
          (connection, remoteUid, videoState, reason, elapsed) {
        debugPrint(
          '[Agora] Remote video state: $videoState, reason: $reason',
        );
        if (_isDisposed) return;
        if (state.state == CallState.connected ||
            state.state == CallState.connecting) {
          final isEnabled =
              videoState == RemoteVideoState.remoteVideoStateDecoding ||
                  videoState == RemoteVideoState.remoteVideoStateStarting;
          state = state.copyWith(isRemoteVideoEnabled: isEnabled);
        }
      },
      onError: (err, msg) {
        debugPrint('[Agora] Error: $err - $msg');
        if (_isDisposed) return;
        if (state.state != CallState.idle) {
          state = state.copyWith(errorMessage: msg);
        }
      },
      onConnectionStateChanged: (connection, stateType, reason) {
        debugPrint('[Agora] Connection state: $stateType, reason: $reason');
        if (_isDisposed) return;
        if (stateType == ConnectionStateType.connectionStateConnected) {
          _recoverReconnect('agora_connection_restored');
        } else if (stateType ==
                ConnectionStateType.connectionStateDisconnected ||
            stateType == ConnectionStateType.connectionStateFailed) {
          if (state.state == CallState.connected ||
              state.state == CallState.reconnecting) {
            _beginReconnect('agora_connection_lost');
          }
        }
      },
    );
    _engine!.registerEventHandler(_eventHandler!);

    await _engine!.enableAudio();

    if (Platform.isIOS || Platform.isAndroid) {
      final useSpeaker = state.callInfo?.type == CallType.video;
      await _setDefaultSpeakerphoneRoute(useSpeaker);
    }
  }

  Future<bool> startCall({
    required String targetUserId,
    required String targetName,
    String? targetAvatar,
    required CallType type,
  }) {
    // Browsers must start audio from the original tap while transient user
    // activation is still available. Native platforms start ringback only
    // after RTC has joined; otherwise Agora's audio-session initialization can
    // immediately silence the player on devices such as Huawei.
    if (!_isDisposed && !state.isInCall) {
      unawaited(_callEndTone.stop());
      if (kIsWeb) {
        unawaited(_outgoingCallTone.start());
      }
    }
    return _startCallInternal(
      targetUserId: targetUserId,
      targetName: targetName,
      targetAvatar: targetAvatar,
      type: type,
    ).whenComplete(() {
      if (state.state != CallState.outgoing) {
        unawaited(_outgoingCallTone.stop());
      }
    });
  }

  Future<bool> _startCallInternal({
    required String targetUserId,
    required String targetName,
    String? targetAvatar,
    required CallType type,
  }) async {
    if (_isDisposed) return false;

    await _checkSimulator();
    if (_isDisposed) return false;

    // 上一通 RTC 资源必须先释放，避免新旧引擎争用麦克风、摄像头和系统音频路由。
    await _waitForLocalCleanup();
    if (_isDisposed) return false;

    debugPrint(
      '[CallService] startCall: isWeb=$kIsWeb, isSimulator=$_isSimulator, isEnabled=$_isEnabled, provider=$_rtcProvider',
    );

    await _loadConfig();
    debugPrint(
      '[CallService] After loadConfig: isEnabled=$_isEnabled, provider=$_rtcProvider',
    );

    final unavailableReason = _callUnavailableReason();
    if (unavailableReason != null) {
      state = state.copyWith(errorMessage: unavailableReason);
      return false;
    }

    await syncActiveCallStateWithServer(releaseServerWhenLocalIdle: true);
    if (_isDisposed) return false;

    final isBlocked = await _isBlockedByCurrentUser(targetUserId);
    if (isBlocked) {
      state = state.copyWith(errorMessage: _blockedCallText());
      return false;
    }

    if (state.isInCall) {
      state = state.copyWith(errorMessage: _callAlreadyInProgressText());
      return false;
    }

    // 呼叫创建前要求实时通道可用，否则服务端虽创建成功，客户端也可能收不到接听/拒绝事件。
    final realtimeReady = await _wsService.ensureConnectedForRealtime(
      timeout: const Duration(seconds: 10),
    );
    if (!realtimeReady) {
      state = state.copyWith(errorMessage: _callConnectionNotReadyText());
      return false;
    }

    var createdCallId = 0;
    var rtcJoined = false;
    try {
      final permittedType = await _requestPermissions(type);
      if (permittedType == null) {
        return false;
      }

      final response = await _api.post<Map<String, dynamic>>(
        '/call/create',
        data: {
          'target_user_id': targetUserId,
          'call_type': type == CallType.voice ? 'voice' : 'video',
        },
      );

      if (!response.isSuccess || response.data == null) {
        state = state.copyWith(
          errorMessage: _callServerMessage(
            response.message,
            fallbackEn: 'Call failed. Please try again.',
          ),
        );
        return false;
      }

      final data = response.data!;
      final arbitrated = _truthyValue(data['arbitrated']);
      final rtcProvider = _providerFromData(data);
      final channelName =
          _firstStringValue(data, ['channel_name', 'room_name']);
      final roomName = _firstStringValue(data, ['room_name', 'channel_name']);
      final token = data['token']?.toString() ?? '';
      final callId = data['call_id'] is int
          ? data['call_id'] as int
          : int.tryParse(data['call_id']?.toString() ?? '') ?? 0;
      createdCallId = callId;
      final agoraUid = data['agora_uid'] is int
          ? data['agora_uid'] as int
          : int.tryParse(data['agora_uid']?.toString() ?? '') ?? 0;
      final serverUrl = _serverUrlFromData(data);

      if (channelName.isEmpty || token.isEmpty) {
        debugPrint(
          '[CallService] Invalid call data: channelName or token is empty',
        );
        await _cancelCallById(createdCallId);
        state = state.copyWith(errorMessage: _mediaServiceUnavailableText());
        return false;
      }
      if (rtcProvider == 'livekit' &&
          (serverUrl == null || serverUrl.isEmpty)) {
        debugPrint('[CallService] LiveKit server URL is empty');
        await _cancelCallById(createdCallId);
        state = state.copyWith(errorMessage: _mediaServiceUnavailableText());
        return false;
      }
      if (rtcProvider == 'agora' && (_appId == null || _appId!.isEmpty)) {
        debugPrint('[CallService] Agora App ID is empty');
        await _cancelCallById(createdCallId);
        state = state.copyWith(errorMessage: _mediaServiceUnavailableText());
        return false;
      }

      state = state.copyWith(
        state: arbitrated ? CallState.connecting : CallState.outgoing,
        callInfo: CallInfo(
          callId: callId,
          channelName: channelName,
          roomName: roomName.isNotEmpty ? roomName : channelName,
          rtcProvider: rtcProvider,
          serverUrl: serverUrl,
          identity: _firstStringValue(data, ['identity', 'livekit_identity']),
          remoteUserId: targetUserId,
          remoteName: targetName,
          remoteAvatar: targetAvatar,
          type: type,
          isOutgoing: !arbitrated,
        ),
        isVideoEnabled: type == CallType.video,
        isSpeakerOn: type == CallType.video,
        isRemoteVideoEnabled: type != CallType.video,
      );

      if (rtcProvider == 'livekit') {
        await _joinLiveKitRoom(
          serverUrl: serverUrl!,
          token: token,
          callType: type,
        );
      } else {
        await _initEngineWithWebRetry();

        if (type == CallType.video) {
          await _engine!.enableVideo();
          try {
            await _engine!.startPreview();
          } catch (previewError) {
            debugPrint('[CallService] startPreview error: $previewError');
            if (previewError is AgoraRtcException && previewError.code == -2) {
              if (Platform.isMacOS) {
                state = state.copyWith(errorMessage: _genericCallFailureText());
              } else {
                state = state.copyWith(errorMessage: _genericCallFailureText());
              }
            }
          }
        }

        final isVideo = type == CallType.video;
        await _engine!.joinChannel(
          token: token,
          channelId: channelName,
          uid: agoraUid > 0 ? agoraUid : 0,
          options: ChannelMediaOptions(
            autoSubscribeAudio: true,
            autoSubscribeVideo: isVideo ? true : null,
            publishMicrophoneTrack: true,
            publishCameraTrack: isVideo ? true : null,
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
          ),
        );
        await _applySpeakerphoneEnabled(isVideo);
        debugPrint(
          '[CallService] Caller joined Agora channel callId=$callId '
          'channel=$channelName uid=$agoraUid',
        );
      }

      rtcJoined = true;
      WakelockPlus.enable();
      if (arbitrated && state.callInfo?.callId == callId) {
        _markCallConnected(source: 'simultaneous_call_arbitration');
      }
      if (state.state == CallState.outgoing &&
          state.callInfo?.callId == callId) {
        if (!kIsWeb) {
          await _outgoingCallTone.start();
        }
        _startOutgoingCallTimeout(callId);
      }

      return true;
    } catch (e, stack) {
      debugPrint('[CallService] Start call error: $e\n$stack');

      await _outgoingCallTone.stop();
      await _leaveChannel();
      if (!rtcJoined) {
        await _cancelCallById(createdCallId);
      }

      final errorMessage = _classifyError(e, 'call');

      state = state.copyWith(state: CallState.idle, errorMessage: errorMessage);
      return false;
    }
  }

  int? _callIdFromPayload(Map<String, dynamic> data) {
    return _intValue(data['call_id'] ?? data['callId']);
  }

  bool _matchesCurrentCall(int? eventCallId) {
    final currentCallId = state.callInfo?.callId;
    if (eventCallId == null || currentCallId == null) {
      return true;
    }
    return eventCallId == currentCallId;
  }

  Future<void> _handleRemoteCallEnded(Map<String, dynamic>? payload) async {
    final eventCallId = payload == null ? null : _callIdFromPayload(payload);
    if (!_matchesCurrentCall(eventCallId)) {
      debugPrint(
        '[CallService] Ignoring call_ended for call_id=$eventCallId, '
        'current=${state.callInfo?.callId}',
      );
      return;
    }

    final reason = payload?['reason']?.toString();
    await _finishCallLocally(
      reason == null || reason.isEmpty ? 'remote_hangup' : reason,
    );
  }

  CallInfo? _incomingCallInfoFromPayload(Map<String, dynamic> data) {
    final callId = _callIdFromPayload(data);
    final channelName = _firstStringValue(data, ['channel_name', 'room_name']);
    final roomName = _firstStringValue(data, ['room_name', 'channel_name']);
    final rtcProvider = _providerFromData(data);
    final serverUrl = _serverUrlFromData(data);
    final callerId = data['caller_id']?.toString();
    final callerName = data['caller_name']?.toString();

    if (channelName.isEmpty ||
        callerId == null ||
        callerId.isEmpty ||
        callerName == null) {
      return null;
    }

    final callerAvatarRaw = data['caller_avatar']?.toString();
    final callerAvatar = (callerAvatarRaw != null && callerAvatarRaw.isNotEmpty)
        ? ApiConfig.getMediaUrl(callerAvatarRaw)
        : null;
    final callType =
        data['call_type'] == 'video' ? CallType.video : CallType.voice;

    return CallInfo(
      callId: callId,
      channelName: channelName,
      roomName: roomName.isNotEmpty ? roomName : channelName,
      rtcProvider: rtcProvider,
      serverUrl: serverUrl,
      identity: _firstStringValue(data, ['identity', 'livekit_identity']),
      remoteUserId: callerId,
      remoteName: callerName,
      remoteAvatar: callerAvatar,
      type: callType,
      isOutgoing: false,
    );
  }

  Future<Map<String, dynamic>> _hydrateIncomingCallPayload(
    Map<String, dynamic> payload,
  ) async {
    final callId = _callIdFromPayload(payload);
    if (callId == null || callId <= 0) return payload;
    try {
      final response = await _api.get<Map<String, dynamic>>('/call/active');
      final active = response.data;
      if (!response.isSuccess ||
          active == null ||
          active['active'] != true ||
          _intValue(active['call_id']) != callId) {
        return payload;
      }
      final hydrated = <String, dynamic>{...payload};
      void fill(String key, dynamic value) {
        final current = hydrated[key]?.toString().trim() ?? '';
        if (current.isEmpty && value != null) hydrated[key] = value;
      }

      fill('channel_name', active['channel_name'] ?? active['room_name']);
      fill('room_name', active['room_name'] ?? active['channel_name']);
      fill('provider', active['provider'] ?? active['rtc_provider']);
      fill('rtc_provider', active['rtc_provider'] ?? active['provider']);
      fill('server_url', active['server_url']);
      fill('caller_id', active['remote_id']);
      fill('caller_name', active['remote_name']);
      fill('caller_avatar', active['remote_avatar']);
      fill('call_type', active['call_type']);
      hydrated['_business_data_incomplete'] = false;
      debugPrint('[CallService] Hydrated incoming call payload: $callId');
      return hydrated;
    } catch (e) {
      debugPrint('[CallService] Hydrate incoming call payload failed: $e');
      return payload;
    }
  }

  void _setIncomingCallState(CallInfo callInfo) {
    state = state.copyWith(
      state: CallState.incoming,
      callInfo: callInfo,
      isVideoEnabled: callInfo.type == CallType.video,
      isSpeakerOn: callInfo.type == CallType.video,
      isRemoteVideoEnabled: callInfo.type != CallType.video,
    );

    _startIncomingCallTimeout(callInfo.callId);
    unawaited(_preloadForIncoming());
  }

  Future<void> handleIncomingCall(Map<String, dynamic> data) async {
    final callId = _callIdFromPayload(data);

    if (incomingCallIsExpired(
      data['expires_at']?.toString(),
      DateTime.now(),
    )) {
      debugPrint('[CallService] Ignoring expired incoming call: $callId');
      if (callId != null) {
        await _rejectCallById(callId, 'timeout');
      }
      return;
    }

    // 相同 callId 属于重复投递；不同 callId 在本地已有通话时必须明确回 busy。
    if (state.isInCall) {
      final currentCallId = state.callInfo?.callId;
      if (callId != null && currentCallId == callId) {
        debugPrint('[CallService] Duplicate incoming call ignored: $callId');
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

    var normalizedData = data;
    var callInfo = _incomingCallInfoFromPayload(normalizedData);
    if (callInfo == null ||
        _truthyValue(normalizedData['_business_data_incomplete'])) {
      normalizedData = await _hydrateIncomingCallPayload(normalizedData);
      callInfo = _incomingCallInfoFromPayload(normalizedData);
    }
    if (callInfo == null) {
      debugPrint(
        '[CallService] handleIncomingCall: invalid payload ${_sensitiveMapSummary(normalizedData)}',
      );
      return;
    }

    final isBlocked = await _isBlockedByCurrentUser(callInfo.remoteUserId);
    if (isBlocked) {
      debugPrint(
        '[CallService] Incoming call auto rejected due to block: ${callInfo.remoteUserId}',
      );
      if (callInfo.callId != null) {
        await _rejectCallById(callInfo.callId!, 'blocked');
      }
      return;
    }

    _setIncomingCallState(callInfo);

    if (kIsWeb) {
      debugPrint('[CallService] Web: showing in-app IncomingCallPage');
      onIncomingCall?.call(callInfo);
      return;
    }

    if (Platform.isIOS) {
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      final isForeground = lifecycleState == AppLifecycleState.resumed ||
          lifecycleState == AppLifecycleState.inactive;

      debugPrint(
        '[CallService] iOS lifecycleState: $lifecycleState, isForeground: $isForeground, isSimulator: $_isSimulator',
      );

      if (isForeground && onIncomingCall != null && !_isSimulator) {
        debugPrint(
          '[CallService] iOS foreground: showing in-app IncomingCallPage',
        );
        onIncomingCall?.call(callInfo);
      } else {
        debugPrint('[CallService] iOS background/locked: showing CallKit UI');
        try {
          await _showCallKit(callInfo);
          if (_isSimulator && onIncomingCall != null) {
            debugPrint(
              '[CallService] iOS simulator: also showing in-app IncomingCallPage',
            );
            onIncomingCall?.call(callInfo);
          }
        } catch (e) {
          debugPrint(
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

      debugPrint(
        '[CallService] Android lifecycleState: $lifecycleState, isForeground: $isForeground',
      );

      if (isForeground && onIncomingCall != null) {
        debugPrint(
          '[CallService] Android foreground: showing in-app IncomingCallPage',
        );
        onIncomingCall?.call(callInfo);
      } else {
        debugPrint(
          '[CallService] Android background/locked: showing system full-screen incoming',
        );
        try {
          await _showCallKit(callInfo);
        } catch (e) {
          debugPrint(
            '[CallService] Android CallKit failed: $e, trying in-app UI',
          );
          onIncomingCall?.call(callInfo);
        }
      }
      return;
    }

    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      debugPrint('[CallService] Desktop: showing in-app IncomingCallPage');
      onIncomingCall?.call(callInfo);
    }
  }

  Map<String, dynamic> _incomingPayloadFromCallInfo(CallInfo callInfo) {
    return <String, dynamic>{
      'type': 'incoming_call',
      'call_id': callInfo.callId,
      'callId': callInfo.callId,
      'channel_name': callInfo.channelName,
      'room_name': callInfo.roomName,
      'provider': callInfo.rtcProvider,
      'rtc_provider': callInfo.rtcProvider,
      'server_url': callInfo.serverUrl ?? '',
      'identity': callInfo.identity ?? '',
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

  String _sensitiveMapSummary(dynamic value) {
    final map = _asStringKeyMap(value);
    if (map == null || map.isEmpty) {
      return 'keys=-';
    }
    final nested = _asStringKeyMap(map['data']) ?? const <String, dynamic>{};
    final keys = {...map.keys, ...nested.keys}
        .map((key) => key.toString())
        .toList()
      ..sort();
    final type = map['type']?.toString() ?? nested['type']?.toString() ?? '-';
    return 'type=$type keys=${keys.join(',')}';
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
    payload['channel_name'] = payload['channel_name'] ??
        data['channel_name'] ??
        payload['room_name'] ??
        data['room_name'];
    payload['room_name'] =
        payload['room_name'] ?? data['room_name'] ?? payload['channel_name'];
    payload['provider'] = payload['provider'] ?? data['provider'];
    payload['rtc_provider'] = payload['rtc_provider'] ?? data['rtc_provider'];
    payload['server_url'] = payload['server_url'] ?? data['server_url'];
    payload['identity'] = payload['identity'] ?? data['identity'];
    payload['caller_id'] = payload['caller_id'] ?? data['caller_id'];
    payload['caller_name'] =
        payload['caller_name'] ?? data['nameCaller'] ?? data['caller_name'];
    payload['caller_avatar'] =
        payload['caller_avatar'] ?? data['avatar'] ?? data['caller_avatar'];

    final type = payload['call_type'] ?? data['call_type'];
    final isVideo =
        _truthyValue(payload['is_video']) || _intValue(data['type']) == 1;
    payload['call_type'] =
        type?.toString() == 'video' || isVideo ? 'video' : 'voice';
    payload['is_video'] = payload['call_type'] == 'video';

    final hasRequiredFields = payload['call_id'] != null &&
        payload['channel_name']?.toString().isNotEmpty == true &&
        payload['caller_id']?.toString().isNotEmpty == true &&
        payload['caller_name']?.toString().isNotEmpty == true;
    final canAttemptHydration = payload['call_id'] != null &&
        _truthyValue(payload['_business_data_incomplete']);
    return hasRequiredFields || canAttemptHydration ? payload : null;
  }

  void _rememberCallKitUuidFromData(dynamic rawData) {
    final data = _asStringKeyMap(rawData);
    if (data == null) return;
    final uuid = _firstStringValue(data, ['id', 'uuid']);
    if (uuid.isNotEmpty) {
      _currentCallKitUuid = uuid;
    }
  }

  int? _callKitEventCallId(dynamic rawData) {
    final data = _asStringKeyMap(rawData);
    if (data == null) return null;
    final extra = _asStringKeyMap(data['extra']) ?? <String, dynamic>{};
    return _intValue(
      extra['call_id'] ?? extra['callId'] ?? data['call_id'] ?? data['callId'],
    );
  }

  bool _callKitEventIsAccepted(dynamic rawData) {
    final data = _asStringKeyMap(rawData);
    if (data == null) return false;
    return _truthyValue(data['accepted']) || _truthyValue(data['isAccepted']);
  }

  Future<bool> _restoreIncomingCallFromCallKitEvent(dynamic rawData) async {
    _rememberCallKitUuidFromData(rawData);
    final eventCallId = _callKitEventCallId(rawData);

    if (state.state == CallState.incoming && state.callInfo != null) {
      if (eventCallId == null || eventCallId == state.callInfo?.callId) {
        return true;
      }
      await _rejectCallById(eventCallId, 'busy');
      return false;
    }
    if (state.state == CallState.connecting ||
        state.state == CallState.connected ||
        state.state == CallState.reconnecting) {
      if (eventCallId != null && eventCallId != state.callInfo?.callId) {
        await _rejectCallById(eventCallId, 'busy');
        return false;
      }
      return true;
    }

    var payload = _incomingPayloadFromCallKitData(rawData);
    if (payload == null) {
      debugPrint(
        '[CallService] Cannot restore incoming call event ${_sensitiveMapSummary(rawData)}',
      );
      return false;
    }

    var callInfo = _incomingCallInfoFromPayload(payload);
    if (callInfo == null ||
        _truthyValue(payload['_business_data_incomplete'])) {
      payload = await _hydrateIncomingCallPayload(payload);
      callInfo = _incomingCallInfoFromPayload(payload);
    }
    if (callInfo == null) {
      debugPrint(
        '[CallService] Invalid CallKit incoming payload ${_sensitiveMapSummary(payload)}',
      );
      return false;
    }

    if (state.isInCall) {
      if (state.callInfo?.callId == callInfo.callId) {
        return true;
      }
      if (callInfo.callId != null) {
        await _rejectCallById(callInfo.callId!, 'busy');
      }
      return false;
    }

    final isBlocked = await _isBlockedByCurrentUser(callInfo.remoteUserId);
    if (isBlocked) {
      if (callInfo.callId != null) {
        await _rejectCallById(callInfo.callId!, 'blocked');
      }
      return false;
    }

    _setIncomingCallState(callInfo);
    return true;
  }

  Future<void> handleNativeCallKitEvent(
    String event,
    Map<String, dynamic> body,
  ) async {
    debugPrint(
      '[CallService] Native CallKit event=$event ${_sensitiveMapSummary(body)}',
    );
    switch (event) {
      case 'incoming':
        await _restoreIncomingCallFromCallKitEvent(body);
        break;
      case 'accept':
        await _handleCallKitAccept(body);
        break;
      case 'decline':
        await _handleCallKitReject(body, 'decline');
        break;
      case 'timeout':
        await _handleCallKitReject(body, 'timeout');
        break;
      case 'ended':
        await _handleCallKitEnd(body);
        break;
      default:
        debugPrint('[CallService] Unknown native CallKit event: $event');
    }
  }

  Future<bool> restoreIncomingCallFromSystem() async {
    // 进程可能在系统来电界面展示期间被回收，恢复时以 CallKit 活跃列表重建 Dart 状态。
    if (_isDisposed || _isRestoringSystemIncomingCall) return false;
    if (kIsWeb || _isSimulator || !(Platform.isIOS || Platform.isAndroid)) {
      return false;
    }

    if (state.state == CallState.incoming && state.callInfo != null) {
      return true;
    }
    if (state.state == CallState.connecting ||
        state.state == CallState.connected ||
        state.state == CallState.reconnecting) {
      return true;
    }

    _isRestoringSystemIncomingCall = true;
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      final calls = activeCalls is List ? activeCalls : const [];
      debugPrint('[CallService] Active system calls: count=${calls.length}');

      for (final rawCall in calls) {
        final call = _asStringKeyMap(rawCall);
        if (call == null) continue;

        final isAccepted = _callKitEventIsAccepted(call);

        final payload = _incomingPayloadFromCallKitData(call);
        if (payload == null) {
          debugPrint(
            '[CallService] Cannot restore CallKit payload ${_sensitiveMapSummary(call)}',
          );
          continue;
        }

        _rememberCallKitUuidFromData(call);
        debugPrint('[CallService] Restoring incoming call from system UI');
        if (isAccepted) {
          final restored = await _restoreIncomingCallFromCallKitEvent(call);
          if (!restored) continue;
          debugPrint('[CallService] Restored accepted system call, joining');
          await _handleCallKitAccept(call);
          return state.state == CallState.connecting ||
              state.state == CallState.connected ||
              state.state == CallState.reconnecting;
        }
        await handleIncomingCall(payload);
        return state.state == CallState.incoming && state.callInfo != null;
      }
    } catch (e) {
      debugPrint('[CallService] restoreIncomingCallFromSystem error: $e');
    } finally {
      _isRestoringSystemIncomingCall = false;
    }

    return false;
  }

  Timer? _incomingCallTimer;

  void _startIncomingCallTimeout(int? callId) {
    _incomingCallTimer?.cancel();
    _incomingCallTimer = Timer(const Duration(seconds: 30), () {
      if (_isDisposed) return;
      if (state.state == CallState.incoming &&
          state.callInfo?.callId == callId) {
        debugPrint('[CallService] Incoming call timeout, auto rejecting');
        rejectCall(reason: 'timeout');
      }
    });
  }

  void _cancelIncomingCallTimeout() {
    _incomingCallTimer?.cancel();
    _incomingCallTimer = null;
  }

  Timer? _connectionTimer;

  void _startOutgoingCallTimeout(int? callId) {
    _outgoingCallTimer?.cancel();
    _outgoingCallTimer = Timer(const Duration(seconds: 30), () {
      if (_isDisposed) return;
      if (state.state != CallState.outgoing ||
          state.callInfo?.callId != callId) {
        return;
      }

      debugPrint('[CallService] Outgoing call timeout, cancelling call');
      state = state.copyWith(errorMessage: _genericCallFailureText());
      unawaited(cancelCall());
    });
  }

  void _cancelOutgoingCallTimeout() {
    _outgoingCallTimer?.cancel();
    _outgoingCallTimer = null;
  }

  void _startConnectionTimeout() {
    _connectionTimer?.cancel();
    _connectionTimer = Timer(const Duration(seconds: 20), () {
      if (_isDisposed) return;
      if (state.state == CallState.connecting ||
          state.state == CallState.outgoing) {
        debugPrint('[CallService] Connection timeout, ending call');
        state = state.copyWith(errorMessage: _genericCallFailureText());
        endCall(reason: 'connection_timeout');
      }
    });
  }

  void _cancelConnectionTimeout() {
    _connectionTimer?.cancel();
    _connectionTimer = null;
  }

  void _beginReconnect(String source) {
    if (_isDisposed || state.callInfo == null) return;
    if (state.state != CallState.connected &&
        state.state != CallState.reconnecting) {
      return;
    }
    _reconnectDeadline ??= DateTime.now().add(const Duration(seconds: 20));
    final remaining = callReconnectSecondsRemaining(
      _reconnectDeadline!,
      DateTime.now(),
    );
    if (remaining <= 0) {
      unawaited(endCall(reason: 'reconnect_timeout'));
      return;
    }
    state = state.copyWith(
      state: CallState.reconnecting,
      reconnectSecondsRemaining: remaining,
    );
    debugPrint(
      '[CallService] Reconnecting source=$source remaining=$remaining '
      'callId=${state.callInfo?.callId}',
    );
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_isDisposed || state.state != CallState.reconnecting) {
        _cancelReconnectTimer();
        return;
      }
      final seconds = callReconnectSecondsRemaining(
        _reconnectDeadline!,
        DateTime.now(),
      );
      if (seconds <= 0) {
        _cancelReconnectTimer();
        unawaited(endCall(reason: 'reconnect_timeout'));
        return;
      }
      state = state.copyWith(reconnectSecondsRemaining: seconds);
    });
  }

  void _recoverReconnect(String source) {
    if (_isDisposed || state.state != CallState.reconnecting) return;
    debugPrint('[CallService] Reconnected source=$source');
    _markCallConnected(source: source);
  }

  void _cancelReconnectTimer() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectDeadline = null;
  }

  void _markCallConnected({
    int? remoteUid,
    DateTime? connectedAt,
    String source = 'unknown',
  }) {
    if (_isDisposed || state.callInfo == null) return;

    final currentState = state.state;
    if (currentState != CallState.outgoing &&
        currentState != CallState.connecting &&
        currentState != CallState.connected &&
        currentState != CallState.reconnecting) {
      return;
    }

    final callInfo = state.callInfo!;
    final wasConnected = currentState == CallState.connected ||
        currentState == CallState.reconnecting;
    _cancelReconnectTimer();
    _cancelOutgoingCallTimeout();
    _cancelConnectionTimeout();

    final nextInfo = callInfo.copyWith(
      remoteUid: remoteUid ?? callInfo.remoteUid,
      connectTime: callInfo.connectTime ?? connectedAt ?? DateTime.now(),
    );

    state = state.copyWith(
      state: CallState.connected,
      reconnectSecondsRemaining: 0,
      isRemoteVideoEnabled:
          callInfo.type == CallType.video ? state.isRemoteVideoEnabled : true,
      callInfo: nextInfo,
    );

    unawaited(_stopRingbackAndRestoreConnectedRoute(nextInfo));

    debugPrint(
      '[CallService] Mark call connected source=$source '
      'callId=${nextInfo.callId} remoteUid=${remoteUid ?? nextInfo.remoteUid}',
    );

    if (!wasConnected) {
      onCallConnected?.call();
      _startCallTimer();
      _startCallHeartbeatTimer(nextInfo.callId);
    }
  }

  Future<void> _stopRingbackAndRestoreConnectedRoute(CallInfo callInfo) async {
    await _outgoingCallTone.stop();
    if (_isDisposed ||
        kIsWeb ||
        state.state != CallState.connected ||
        state.callInfo?.callId != callInfo.callId) {
      return;
    }

    // Ringback is intentionally sent to the loudspeaker. Restore the route the
    // active call expects as soon as the remote party connects.
    await _applySpeakerphoneEnabled(
      callInfo.type == CallType.video || state.isSpeakerOn,
    );
  }

  Future<bool> acceptCall() async {
    debugPrint(
      '[CallService] acceptCall called, state=${state.state}, callInfo=${state.callInfo != null}',
    );

    if (_isAcceptingCall) {
      debugPrint('[CallService] acceptCall already in progress');
      return false;
    }

    if (state.state != CallState.incoming || state.callInfo == null) {
      debugPrint(
        '[CallService] acceptCall failed: invalid state or no callInfo',
      );
      state = state.copyWith(errorMessage: _genericCallFailureText());
      return false;
    }

    _isAcceptingCall = true;

    // 接听流程包含服务端确认和 RTC 入会，整个过程只允许一个执行者，页面不得自行推断成功。
    await _waitForLocalCleanup();
    if (_isDisposed) return false;

    _cancelIncomingCallTimeout();

    final originalCallId = state.callInfo!.callId;
    var callType = state.callInfo!.type;
    var currentInfo = state.callInfo!;
    final acceptedCallId = currentInfo.callId ?? 0;
    final acceptedCallKitUuid = _currentCallKitUuid;
    var acceptedOnServer = false;
    var rtcJoined = false;
    var acceptedSuccessfully = false;

    state = state.copyWith(state: CallState.connecting);
    debugPrint('[CallService] State changed to connecting immediately');

    try {
      final permittedType = await _requestPermissions(
        callType,
        allowVideoDowngrade: true,
      );
      if (permittedType == null) {
        debugPrint('[CallService] Permission denied');
        await _rejectCallById(acceptedCallId, 'permission_denied');
        state = state.copyWith(state: CallState.idle);
        return false;
      }
      if (permittedType != callType) {
        callType = permittedType;
        currentInfo = currentInfo.copyWith(type: permittedType);
        state = state.copyWith(
          callInfo: currentInfo,
          isVideoEnabled: false,
        );
      }
      await _loadConfigIfNeeded(currentInfo.rtcProvider);
      debugPrint('[CallService] Permissions & config ready');

      if (_isCallCancelledDuringAccept(originalCallId)) {
        debugPrint('[CallService] Call was cancelled during permission/config');
        return false;
      }

      if (!_isEnabled) {
        await _rejectCallById(acceptedCallId, 'media_disabled');
        state = state.copyWith(
          state: CallState.idle,
          errorMessage: _mediaServiceUnavailableText(),
        );
        return false;
      }

      debugPrint('[CallService] Starting accept API...');

      final response = await _api.post<Map<String, dynamic>>(
        '/call/accept',
        data: {'call_id': originalCallId},
      );

      if (!response.isSuccess || response.data == null) {
        debugPrint('[CallService] Accept API failed: ${response.message}');
        final responseMessage = response.message?.toLowerCase() ?? '';
        if (responseMessage.contains('cancelled') ||
            responseMessage.contains('not found') ||
            responseMessage.contains('ended')) {
          state = state.copyWith(
            state: CallState.idle,
            errorMessage: _genericCallFailureText(),
          );
        } else {
          await _rejectCallById(acceptedCallId, 'answer_failed');
          state = state.copyWith(
            state: CallState.idle,
            errorMessage: _genericCallFailureText(),
          );
        }
        return false;
      }
      debugPrint('[CallService] Accept API success');
      acceptedOnServer = true;

      if (_isCallCancelledDuringAccept(originalCallId)) {
        debugPrint('[CallService] Call was cancelled after API/engine init');
        await _leaveChannel();
        return false;
      }

      if (acceptedCallKitUuid != null &&
          (Platform.isIOS || Platform.isAndroid)) {
        try {
          await FlutterCallkitIncoming.setCallConnected(
            acceptedCallKitUuid,
          );
        } catch (error) {
          debugPrint('[CallService] setCallConnected error: $error');
        }
      }

      final data = response.data!;
      final connectedAt =
          DateTime.tryParse(data['connected_at']?.toString() ?? '');
      final rtcProvider = _providerFromData(
        data,
        fallback: currentInfo.rtcProvider,
      );
      final responseChannel =
          _firstStringValue(data, ['channel_name', 'room_name']);
      final responseRoom =
          _firstStringValue(data, ['room_name', 'channel_name']);
      final channelName = responseChannel.isNotEmpty
          ? responseChannel
          : currentInfo.channelName;
      final roomName =
          responseRoom.isNotEmpty ? responseRoom : currentInfo.roomName;
      final token = data['token']?.toString() ?? '';
      final serverUrl = _serverUrlFromData(data) ?? currentInfo.serverUrl;
      final agoraUid = data['agora_uid'] is int
          ? data['agora_uid'] as int
          : int.tryParse(data['agora_uid']?.toString() ?? '') ?? 0;

      if (channelName.isEmpty || token.isEmpty) {
        debugPrint('[CallService] Accept call: channelName or token is empty');
        await _endCallById(acceptedCallId, 'rtc_error');
        state = state.copyWith(
          state: CallState.idle,
          errorMessage: _genericCallFailureText(),
        );
        return false;
      }
      if (rtcProvider == 'livekit' &&
          (serverUrl == null || serverUrl.isEmpty)) {
        debugPrint('[CallService] Accept call: LiveKit server URL is empty');
        await _endCallById(acceptedCallId, 'rtc_error');
        state = state.copyWith(
          state: CallState.idle,
          errorMessage: _genericCallFailureText(),
        );
        return false;
      }
      if (rtcProvider == 'agora' && (_appId == null || _appId!.isEmpty)) {
        debugPrint('[CallService] Accept call: Agora App ID is empty');
        await _endCallById(acceptedCallId, 'rtc_error');
        state = state.copyWith(
          state: CallState.idle,
          errorMessage: _genericCallFailureText(),
        );
        return false;
      }

      state = state.copyWith(
        callInfo: currentInfo.copyWith(
          channelName: channelName,
          roomName: roomName,
          rtcProvider: rtcProvider,
          serverUrl: serverUrl,
          identity: _firstStringValue(data, ['identity', 'livekit_identity']),
          connectTime: connectedAt,
        ),
      );

      _startConnectionTimeout();

      if (rtcProvider == 'livekit') {
        await _joinLiveKitRoom(
          serverUrl: serverUrl!,
          token: token,
          callType: callType,
        );
      } else {
        await _initEngineWithWebRetry();
        debugPrint('[CallService] Engine initialized');

        if (callType == CallType.video) {
          debugPrint('[CallService] Enabling video...');
          await _engine!.enableVideo();
          _engine!.startPreview().catchError((e) {
            debugPrint('[CallService] startPreview error: $e');
          });
        }

        debugPrint('[CallService] Joining RTC channel');
        final isVideoCall = callType == CallType.video;
        await _engine!.joinChannel(
          token: token,
          channelId: channelName,
          uid: agoraUid > 0 ? agoraUid : 0,
          options: ChannelMediaOptions(
            autoSubscribeAudio: true,
            autoSubscribeVideo: isVideoCall ? true : null,
            publishMicrophoneTrack: true,
            publishCameraTrack: isVideoCall ? true : null,
            clientRoleType: ClientRoleType.clientRoleBroadcaster,
          ),
        );
        await _applySpeakerphoneEnabled(isVideoCall);
        debugPrint('[CallService] Joined channel successfully');
        _markCallConnected(
          connectedAt: connectedAt,
          source: 'accept_join_success',
        );
      }

      rtcJoined = true;
      WakelockPlus.enable();

      acceptedSuccessfully = true;
      return true;
    } catch (e, stack) {
      debugPrint('[CallService] Accept call error: $e');
      debugPrint('[CallService] Stack: $stack');

      _cancelConnectionTimeout();
      await _leaveChannel();
      if (acceptedOnServer && !rtcJoined) {
        await _endCallById(acceptedCallId, 'rtc_error');
      } else if (!acceptedOnServer &&
          !_isCallCancelledDuringAccept(originalCallId)) {
        await _rejectCallById(acceptedCallId, 'answer_failed');
      }

      final errorMessage = _classifyError(e, 'answer');
      state = state.copyWith(state: CallState.idle, errorMessage: errorMessage);
      return false;
    } finally {
      if (!acceptedSuccessfully &&
          acceptedCallKitUuid != null &&
          (Platform.isIOS || Platform.isAndroid) &&
          state.state != CallState.connecting &&
          state.state != CallState.connected &&
          state.state != CallState.reconnecting) {
        try {
          await FlutterCallkitIncoming.endCall(acceptedCallKitUuid);
        } catch (error) {
          debugPrint('[CallService] accept failure endCall error: $error');
        }
      }
      _isAcceptingCall = false;
    }
  }

  Future<void> _loadConfigIfNeeded([String? provider]) async {
    final targetProvider = _normalizeRtcProvider(provider ?? _rtcProvider);
    if (_isEnabled && _hasRtcConfig(targetProvider)) {
      return;
    }
    await _loadConfig();
  }

  bool _isPreloading = false;
  Future<void> _preloadForIncoming() async {
    if (_isPreloading) return;
    _isPreloading = true;

    try {
      debugPrint('[CallService] Preloading for incoming call...');

      final provider = state.callInfo?.rtcProvider ?? _rtcProvider;
      await _loadConfigIfNeeded(provider);

      if (_isEnabled &&
          provider == 'agora' &&
          _appId != null &&
          _appId!.isNotEmpty &&
          _engine == null) {
        debugPrint('[CallService] Pre-initializing engine...');
        await _initEngineWithWebRetry();
        debugPrint('[CallService] Engine pre-initialized');
      }
    } catch (e) {
      debugPrint('[CallService] Preload error (non-fatal): $e');
    } finally {
      _isPreloading = false;
    }
  }

  Future<void> _joinLiveKitRoom({
    required String serverUrl,
    required String token,
    required CallType callType,
  }) async {
    await _disconnectLiveKitRoom();

    final room = lk.Room();
    final listener = room.createListener();
    _liveKitRoom = room;
    _liveKitListener = listener;
    _liveKitLocalVideoTrack = null;
    _liveKitRemoteVideoTrack = null;
    _liveKitRemoteIdentity = null;

    listener
      ..on<lk.TrackSubscribedEvent>((event) {
        _handleLiveKitTrackSubscribed(event);
      })
      ..on<lk.TrackUnsubscribedEvent>((event) {
        _handleLiveKitTrackUnsubscribed(event);
      })
      ..on<lk.ParticipantDisconnectedEvent>((event) {
        debugPrint(
          '[LiveKit] Participant disconnected: ${event.participant.identity}',
        );
        if (_isDisposed || _isEndingCall || _isCancellingCall) return;
        _beginReconnect('livekit_participant_disconnected');
      })
      ..on<lk.RoomReconnectingEvent>((event) {
        debugPrint('[LiveKit] Room reconnecting');
        _beginReconnect('livekit_room_reconnecting');
      })
      ..on<lk.RoomReconnectedEvent>((event) {
        debugPrint('[LiveKit] Room reconnected');
        _recoverReconnect('livekit_room_reconnected');
      })
      ..on<lk.RoomDisconnectedEvent>((event) {
        debugPrint('[LiveKit] Room disconnected: ${event.reason}');
        if (_isDisposed || _isEndingCall || _isCancellingCall) return;
        _beginReconnect('livekit_room_disconnected');
      });

    try {
      await room.connect(serverUrl, token);
      final localParticipant = room.localParticipant;
      await localParticipant?.setMicrophoneEnabled(!state.isMuted);

      if (callType == CallType.video && state.isVideoEnabled) {
        final publication = await localParticipant?.setCameraEnabled(true);
        final track = publication?.track;
        _liveKitLocalVideoTrack =
            track is lk.LocalVideoTrack ? track : _findLiveKitLocalVideoTrack();
      } else {
        await localParticipant?.setCameraEnabled(false);
        _liveKitLocalVideoTrack = null;
      }

      _syncLiveKitRemoteTracks(room);
      state = state.copyWith(isVideoEnabled: callType == CallType.video);
    } catch (e) {
      await _disconnectLiveKitRoom();
      rethrow;
    }
  }

  void _handleLiveKitTrackSubscribed(lk.TrackSubscribedEvent event) {
    final identity = event.participant.identity;
    final track = event.track;
    if (track.kind == lk.TrackType.VIDEO && track is lk.RemoteVideoTrack) {
      _liveKitRemoteVideoTrack = track;
      _markLiveKitRemoteActive(identity: identity, videoEnabled: true);
      return;
    }
    if (track.kind == lk.TrackType.AUDIO) {
      _markLiveKitRemoteActive(identity: identity);
    }
  }

  void _handleLiveKitTrackUnsubscribed(lk.TrackUnsubscribedEvent event) {
    if (event.track.kind != lk.TrackType.VIDEO) return;
    if (_liveKitRemoteIdentity != null &&
        event.participant.identity != _liveKitRemoteIdentity) {
      return;
    }
    _liveKitRemoteVideoTrack = null;
    if (_isDisposed || state.callInfo?.type != CallType.video) return;
    state = state.copyWith(isRemoteVideoEnabled: false);
  }

  void _syncLiveKitRemoteTracks(lk.Room room) {
    for (final participant in room.remoteParticipants.values) {
      for (final publication in participant.videoTrackPublications) {
        final track = publication.track;
        if (track != null) {
          _liveKitRemoteVideoTrack = track;
          _markLiveKitRemoteActive(
            identity: participant.identity,
            videoEnabled: true,
          );
          return;
        }
      }
      for (final publication in participant.audioTrackPublications) {
        if (publication.track != null || publication.subscribed) {
          _markLiveKitRemoteActive(identity: participant.identity);
          return;
        }
      }
      _markLiveKitRemoteActive(identity: participant.identity);
      return;
    }
  }

  void _markLiveKitRemoteActive({
    required String identity,
    bool videoEnabled = false,
  }) {
    if (_isDisposed || state.callInfo == null) return;
    final callInfo = state.callInfo!;
    unawaited(_outgoingCallTone.stop());
    _liveKitRemoteIdentity = identity;
    _cancelConnectionTimeout();

    state = state.copyWith(
      isRemoteVideoEnabled:
          callInfo.type == CallType.video ? videoEnabled : true,
      callInfo: callInfo.copyWith(
        remoteIdentity: identity,
        remoteUid: callInfo.remoteUid ?? identity.hashCode,
        connectTime: callInfo.connectTime ?? DateTime.now(),
      ),
    );
    _markCallConnected(source: 'livekit_remote_active');
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
      debugPrint('[LiveKit] listener dispose error: $e');
    }

    final room = _liveKitRoom;
    _liveKitRoom = null;
    _liveKitLocalVideoTrack = null;
    _liveKitRemoteVideoTrack = null;
    _liveKitRemoteIdentity = null;
    if (room == null) return;

    try {
      await room.disconnect();
      await room.dispose();
    } catch (e) {
      debugPrint('[LiveKit] disconnect error: $e');
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
    if (!_isDisposed) {
      state = state.copyWith(isVideoEnabled: true);
    }
  }

  Future<void> _switchLiveKitCamera() async {
    final room = _liveKitRoom;
    if (room == null || state.callInfo?.type != CallType.video) return;
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

  Future<void> _setDefaultSpeakerphoneRoute(bool enabled) async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return;
    }

    if (state.callInfo?.rtcProvider == 'livekit') {
      return;
    }

    final engine = _engine;
    if (engine == null) return;
    await engine.setDefaultAudioRouteToSpeakerphone(enabled);
  }

  Future<void> _setSpeakerphoneEnabled(bool enabled) async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return;
    }

    if (state.callInfo?.rtcProvider == 'livekit') {
      await _liveKitRoom?.setSpeakerOn(enabled);
      return;
    }

    final engine = _engine;
    if (engine == null) return;
    await engine.setEnableSpeakerphone(enabled);
  }

  Future<void> _applySpeakerphoneEnabled(bool enabled) async {
    try {
      await _setSpeakerphoneEnabled(enabled);
    } catch (e) {
      debugPrint('[CallService] Apply speakerphone route error: $e');
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

  String _classifyError(dynamic e, String actionKey) {
    final action = _callActionText(actionKey);
    if (e is TimeoutException) {
      return _callServiceText(
        zhCN: '$action超时，请重试',
        zhTW: '$action逾時，請重試',
        en: '$action timed out. Please try again.',
      );
    }

    if (e is AgoraRtcException) {
      switch (e.code) {
        case -2: // ERR_INVALID_ARGUMENT
          return _genericCallFailureText();
        case -7: // ERR_NOT_INITIALIZED
          return _genericCallFailureText();
        case -17: // ERR_JOIN_CHANNEL_REJECTED
          return _genericCallFailureText();
        case 110: // ERR_TOKEN_EXPIRED
          return _genericCallFailureText();
        default:
          return _callServiceText(
            zhCN: '$action失败（错误码: ${e.code}）',
            zhTW: '$action失敗（錯誤碼: ${e.code}）',
            en: '$action failed (error code: ${e.code})',
          );
      }
    }

    final errorStr = e.toString().toLowerCase();
    if (errorStr.contains('socket') ||
        errorStr.contains('network') ||
        errorStr.contains('connection')) {
      return _genericCallFailureText();
    }

    return _callServiceText(
      zhCN: '$action失败，请重试',
      zhTW: '$action失敗，請重試',
      en: '$action failed. Please try again.',
    );
  }

  Future<bool> _isBlockedByCurrentUser(String userId) async {
    final normalized = userId.trim();
    if (normalized.isEmpty) {
      return false;
    }

    try {
      final response = await _api.get<Map<String, dynamic>>(
        '/user/blocked/check?user_id=$normalized',
      );
      if (!response.isSuccess || response.data == null) {
        return false;
      }
      return response.data!['is_blocked'] == true;
    } catch (e) {
      debugPrint('[CallService] Block status check failed for $normalized: $e');
      return false;
    }
  }

  Future<void> rejectCall({String reason = 'decline'}) async {
    if (_isDisposed) return;
    if (_isRejectingCall) return;
    if (state.state != CallState.incoming || state.callInfo == null) {
      return;
    }
    _isRejectingCall = true;
    final callId = state.callInfo!.callId ?? 0;

    _cancelIncomingCallTimeout();

    _callTimer?.cancel();
    _callTimer = null;

    if (DesktopNotificationService.isDesktop) {
      DesktopNotificationService().cancelCallNotification();
    }

    if (callId > 0) {
      unawaited(_rejectCallById(callId, reason));
    }
    await _finishCallLocally(reason);
  }

  Future<void> endCall({
    String reason = 'hangup',
    bool notifyServer = true,
  }) async {
    if (_isDisposed) return;
    if (_isEndingCall) return;
    if (!state.isInCall) return;
    _isEndingCall = true;
    final callId = state.callInfo?.callId ?? 0;
    _callTimer?.cancel();
    _callTimer = null;

    if (DesktopNotificationService.isDesktop) {
      DesktopNotificationService().cancelCallNotification();
    }

    if (notifyServer && callId > 0) {
      unawaited(_endCallById(callId, reason));
    }

    await _finishCallLocally(reason);
  }

  Future<void> _finishCallLocally(String reason) async {
    if (_isDisposed) return;
    final callKitUuid = _currentCallKitUuid;
    final shouldPlayEndTone = state.state == CallState.connected ||
        state.state == CallState.reconnecting;

    // 先同步回到空闲态并关闭系统 UI，RTC 释放放到后台串行完成，避免结束按钮长时间无响应。
    await _outgoingCallTone.stop();
    onCallEnded?.call(reason);
    _resetState(immediate: true);

    if (callKitUuid != null && (Platform.isIOS || Platform.isAndroid)) {
      await _endSystemCall(callKitUuid);
    }

    final cleanup = _leaveChannel();
    _localCleanupFuture = cleanup;
    if (shouldPlayEndTone) {
      unawaited(_callEndTone.playAfter(cleanup));
    }
    unawaited(cleanup.whenComplete(() {
      if (identical(_localCleanupFuture, cleanup)) {
        _localCleanupFuture = null;
      }
    }));
  }

  Future<void> _endSystemCall(String uuid) async {
    try {
      await FlutterCallkitIncoming.endCall(uuid);
    } catch (e) {
      debugPrint('[CallService] plugin endCall error: $e');
    }
    if (Platform.isIOS) {
      try {
        await _iosNativeCallKitChannel.invokeMethod<void>(
          'endNativeCall',
          <String, dynamic>{'uuid': uuid},
        );
      } catch (e) {
        debugPrint('[CallService] native endCall error: $e');
      }
    }
  }

  Future<void> _waitForLocalCleanup() async {
    final cleanup = _localCleanupFuture;
    if (cleanup == null) return;
    try {
      await cleanup.timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[CallService] Local cleanup wait skipped: $e');
    }
  }

  Future<void> cancelCall() async {
    if (_isDisposed) return;
    if (_isCancellingCall) return;
    if (state.state != CallState.outgoing || state.callInfo == null) {
      return;
    }
    _isCancellingCall = true;
    final callId = state.callInfo!.callId ?? 0;

    if (callId > 0) {
      unawaited(_cancelCallById(callId));
    }

    if (_isDisposed) return;

    await _finishCallLocally('cancelled');
  }

  Future<void> _cancelCallById(int callId) async {
    if (callId <= 0) return;
    for (var attempt = 1; attempt <= 3; attempt += 1) {
      try {
        final response = await _api
            .delete('/call/$callId')
            .timeout(const Duration(seconds: 4));
        if (response.isSuccess) return;
        debugPrint(
          '[CallService] Cancel call by id failed attempt=$attempt '
          'call_id=$callId code=${response.code}',
        );
      } catch (e) {
        debugPrint(
          '[CallService] Cancel call by id error attempt=$attempt '
          'call_id=$callId: $e',
        );
      }
      if (attempt < 3) {
        await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
  }

  Future<void> _endCallById(int callId, String reason) async {
    if (callId <= 0) return;
    for (var attempt = 1; attempt <= 3; attempt += 1) {
      try {
        final response = await _api.post(
          '/call/end',
          data: {'call_id': callId, 'reason': reason},
        ).timeout(const Duration(seconds: 4));
        if (response.isSuccess) return;
        debugPrint(
          '[CallService] End call by id failed attempt=$attempt '
          'call_id=$callId code=${response.code}',
        );
      } catch (e) {
        debugPrint(
          '[CallService] End call by id error attempt=$attempt '
          'call_id=$callId: $e',
        );
      }
      if (attempt < 3) {
        await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
  }

  Future<void> _rejectCallById(int callId, String reason) async {
    if (callId <= 0) return;
    for (var attempt = 1; attempt <= 3; attempt += 1) {
      try {
        final response = await _api.post(
          '/call/reject',
          data: {'call_id': callId, 'reason': reason},
        ).timeout(const Duration(seconds: 4));
        if (response.isSuccess) return;
        debugPrint(
          '[CallService] Reject call by id failed attempt=$attempt '
          'call_id=$callId code=${response.code}',
        );
      } catch (e) {
        debugPrint(
          '[CallService] Reject call by id error attempt=$attempt '
          'call_id=$callId: $e',
        );
      }
      if (attempt < 3) {
        await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
      }
    }
  }

  void toggleMute() {
    if (_isDisposed) return;
    final newMuted = !state.isMuted;
    if (state.callInfo?.rtcProvider == 'livekit') {
      unawaited(
        _liveKitRoom?.localParticipant?.setMicrophoneEnabled(!newMuted) ??
            Future.value(),
      );
    } else {
      _engine?.muteLocalAudioStream(newMuted);
    }
    state = state.copyWith(isMuted: newMuted);
  }

  void toggleSpeaker() {
    unawaited(_toggleSpeaker());
  }

  Future<void> _toggleSpeaker() async {
    if (_isDisposed) return;
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return;
    }
    final newSpeaker = !state.isSpeakerOn;
    try {
      await _setSpeakerphoneEnabled(newSpeaker);
      if (_isDisposed) return;
      state = state.copyWith(isSpeakerOn: newSpeaker);
    } catch (e) {
      debugPrint('[CallService] Toggle speaker error: $e');
    }
  }

  void toggleVideo() {
    if (_isDisposed) return;
    if (state.callInfo?.type != CallType.video) return;

    unawaited(_setVideoEnabled(!state.isVideoEnabled));
  }

  Future<void> _setVideoEnabled(
    bool newEnabled, {
    bool notifyPeer = true,
  }) async {
    if (_isDisposed || state.callInfo?.type != CallType.video) return;
    if (state.isVideoEnabled == newEnabled) return;
    if (state.callInfo?.rtcProvider == 'livekit') {
      await _setLiveKitCameraEnabled(newEnabled);
    } else {
      if (newEnabled) {
        await _engine?.enableVideo();
        await _engine?.startPreview();
      } else {
        await _engine?.stopPreview();
        await _engine?.disableVideo();
      }
      await _engine?.muteLocalVideoStream(!newEnabled);
    }
    if (_isDisposed) return;
    state = state.copyWith(isVideoEnabled: newEnabled);
    if (notifyPeer) {
      await _sendMediaState(videoEnabled: newEnabled);
    }
  }

  Future<void> downgradeToVoice() async {
    final info = state.callInfo;
    if (_isDisposed || info == null || info.type != CallType.video) return;
    if (state.isVideoEnabled) {
      await _setVideoEnabled(false, notifyPeer: false);
    }
    if (_isDisposed || state.callInfo?.callId != info.callId) return;
    state = state.copyWith(
      callInfo: info.copyWith(type: CallType.voice),
      isVideoEnabled: false,
      isRemoteVideoEnabled: true,
    );
    await _applySpeakerphoneEnabled(state.isSpeakerOn);
    await _sendMediaState(callType: CallType.voice, videoEnabled: false);
  }

  Future<void> handleAppLifecycleState(AppLifecycleState lifecycleState) async {
    if (_isDisposed || state.callInfo?.type != CallType.video) return;
    if (lifecycleState == AppLifecycleState.paused ||
        lifecycleState == AppLifecycleState.hidden) {
      if (state.isVideoEnabled) {
        _restoreVideoAfterBackground = true;
        await _setVideoEnabled(false);
      }
    } else if (lifecycleState == AppLifecycleState.resumed &&
        _restoreVideoAfterBackground) {
      _restoreVideoAfterBackground = false;
      await _setVideoEnabled(true);
    }
  }

  Future<void> _sendMediaState({
    CallType? callType,
    required bool videoEnabled,
  }) async {
    final callId = state.callInfo?.callId;
    if (callId == null || callId <= 0 || state.state != CallState.connected) {
      return;
    }
    try {
      await _api.post<Map<String, dynamic>>(
        '/call/media-state',
        data: {
          'call_id': callId,
          if (callType != null)
            'call_type': callType == CallType.video ? 'video' : 'voice',
          'video_enabled': videoEnabled,
        },
      );
    } catch (e) {
      debugPrint('[CallService] Sync media state error: $e');
    }
  }

  Future<void> _handleRemoteMediaChanged(
    Map<String, dynamic> payload,
  ) async {
    final eventCallId = _callIdFromPayload(payload);
    if (!_matchesCurrentCall(eventCallId) || state.callInfo == null) return;
    final downgraded = payload['call_type']?.toString() == 'voice';
    final videoEnabled = _truthyValue(payload['video_enabled']);
    final info = state.callInfo!;
    if (downgraded && info.type == CallType.video && state.isVideoEnabled) {
      await _setVideoEnabled(false, notifyPeer: false);
      if (_isDisposed || state.callInfo?.callId != info.callId) return;
    }
    state = state.copyWith(
      callInfo: downgraded ? info.copyWith(type: CallType.voice) : info,
      isRemoteVideoEnabled: downgraded ? true : videoEnabled,
      isVideoEnabled: downgraded ? false : state.isVideoEnabled,
    );
  }

  Future<void> switchCamera() async {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      return;
    }
    if (state.callInfo?.rtcProvider == 'livekit') {
      await _switchLiveKitCamera();
      return;
    }
    await _engine?.switchCamera();
  }

  void toggleMinimize() {
    state = state.copyWith(isMinimized: !state.isMinimized);
  }

  Duration get callDuration {
    return Duration(
      seconds: callElapsedSeconds(state.callInfo?.connectTime, DateTime.now()),
    );
  }

  Widget getLocalView() {
    if (state.callInfo?.rtcProvider == 'livekit') {
      final track = _liveKitLocalVideoTrack ?? _findLiveKitLocalVideoTrack();
      if (track == null) return const SizedBox();
      return lk.VideoTrackRenderer(track);
    }
    if (_engine == null) return const SizedBox();
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engine!,
        canvas: const VideoCanvas(uid: 0),
      ),
    );
  }

  Widget getRemoteView() {
    if (state.callInfo?.rtcProvider == 'livekit') {
      final track = _liveKitRemoteVideoTrack;
      if (track == null) return const SizedBox();
      return lk.VideoTrackRenderer(track);
    }
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

  Future<void> _leaveChannel() {
    // 多个结束来源可能同时到达；按顺序释放可避免旧清理任务误关下一通刚创建的引擎。
    final previous = _leaveChannelFuture;
    final current = () async {
      if (previous != null) {
        try {
          await previous;
        } catch (e) {
          debugPrint('[CallService] Previous channel cleanup failed: $e');
        }
      }
      await _leaveChannelInternal();
    }();
    _leaveChannelFuture = current;
    return current.whenComplete(() {
      if (identical(_leaveChannelFuture, current)) {
        _leaveChannelFuture = null;
      }
    });
  }

  Future<void> _leaveChannelInternal() async {
    _callTimer?.cancel();
    _callTimer = null;
    _stopCallHeartbeatTimer();
    _cancelOutgoingCallTimeout();
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _cancelReconnectTimer();

    final engine = _engine;
    final eventHandler = _eventHandler;
    if (identical(_engine, engine)) {
      _engine = null;
    }
    if (identical(_eventHandler, eventHandler)) {
      _eventHandler = null;
    }

    await _disconnectLiveKitRoom();

    try {
      if (eventHandler != null && engine != null) {
        engine.unregisterEventHandler(eventHandler);
      }
      await engine?.leaveChannel();
      await engine?.stopPreview();
      await engine?.release();
    } catch (e) {
      debugPrint('[CallService] Leave channel error: $e');
    }

    WakelockPlus.disable();
  }

  void _resetState({bool immediate = false}) {
    unawaited(_outgoingCallTone.stop());
    _callTimer?.cancel();
    _callTimer = null;
    _stopCallHeartbeatTimer();
    _cancelOutgoingCallTimeout();
    _cancelReconnectTimer();
    _currentCallKitUuid = null;
    _isHandlingCallKitAccept = false;
    _isAcceptingCall = false;
    _isEndingCall = false;
    _isRejectingCall = false;
    _isCancellingCall = false;
    _isPreloading = false;
    WakelockPlus.disable();

    if (_isDisposed) return;

    if (immediate) {
      state = const CallServiceState();
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        state = const CallServiceState();
      }
    });
  }

  void _startCallTimer() {
    _callTimer?.cancel();
    _callTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isDisposed) {
        _callTimer?.cancel();
        _callTimer = null;
        return;
      }
      if (state.state != CallState.connected &&
          state.state != CallState.reconnecting) {
        _callTimer?.cancel();
        _callTimer = null;
      }
    });
  }

  void _startCallHeartbeatTimer(int? callId) {
    _stopCallHeartbeatTimer();
    if (callId == null || callId <= 0) return;
    _sendCallHeartbeat(callId);
    _callHeartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isDisposed) {
        _stopCallHeartbeatTimer();
        return;
      }
      if ((state.state != CallState.connected &&
              state.state != CallState.reconnecting) ||
          state.callInfo?.callId != callId) {
        _stopCallHeartbeatTimer();
        return;
      }
      _sendCallHeartbeat(callId);
    });
  }

  void _stopCallHeartbeatTimer() {
    _callHeartbeatTimer?.cancel();
    _callHeartbeatTimer = null;
  }

  void _sendCallHeartbeat(int callId) {
    // 心跳响应中的 active 是服务端对业务通话的最终判断，本地 RTC 连通不能覆盖该结论。
    unawaited(
      _api.post<Map<String, dynamic>>('/call/heartbeat',
          data: {'call_id': callId}).then((response) {
        if (!response.isSuccess || response.data == null) return;
        if (response.data!['active'] == false &&
            state.callInfo?.callId == callId) {
          debugPrint(
              '[CallService] Server marked call inactive from heartbeat');
          unawaited(_finishCallLocally('server_inactive'));
        }
      }).catchError((e) {
        debugPrint('[CallService] Call heartbeat error: $e');
      }),
    );
  }

  void _setupCallKit() {
    _callKitSubscription?.cancel();
    _callKitSubscription = FlutterCallkitIncoming.onEvent.listen((event) async {
      debugPrint(
        '[CallService] CallKit event: ${event?.event}, body=${_sensitiveMapSummary(event?.body)}',
      );
      switch (event?.event) {
        case Event.actionCallAccept:
          debugPrint('[CallService] CallKit: actionCallAccept');
          await _handleCallKitAccept(event?.body);
          break;
        case Event.actionCallDecline:
          debugPrint('[CallService] CallKit: actionCallDecline');
          await _handleCallKitReject(event?.body, 'decline');
          break;
        case Event.actionCallEnded:
          debugPrint(
            '[CallService] CallKit: actionCallEnded, currentState=${state.state}',
          );
          await _handleCallKitEnd(event?.body);
          break;
        case Event.actionCallStart:
          debugPrint('[CallService] CallKit: actionCallStart (outgoing)');
          break;
        case Event.actionCallIncoming:
          debugPrint('[CallService] CallKit: actionCallIncoming');
          await _restoreIncomingCallFromCallKitEvent(event?.body);
          break;
        case Event.actionCallTimeout:
          debugPrint('[CallService] CallKit: actionCallTimeout');
          await _handleCallKitReject(event?.body, 'timeout');
          break;
        case Event.actionCallToggleHold:
          debugPrint('[CallService] CallKit: actionCallToggleHold');
          break;
        case Event.actionCallToggleMute:
          debugPrint('[CallService] CallKit: actionCallToggleMute');
          toggleMute();
          break;
        case Event.actionCallToggleDmtf:
          debugPrint('[CallService] CallKit: actionCallToggleDmtf');
          break;
        case Event.actionCallToggleGroup:
          debugPrint('[CallService] CallKit: actionCallToggleGroup');
          break;
        case Event.actionCallToggleAudioSession:
          debugPrint('[CallService] CallKit: actionCallToggleAudioSession');
          break;
        case Event.actionDidUpdateDevicePushTokenVoip:
          debugPrint(
            '[CallService] CallKit: actionDidUpdateDevicePushTokenVoip',
          );
          break;
        default:
          debugPrint('[CallService] CallKit: unknown event ${event?.event}');
          break;
      }
    });
  }

  Future<void> _handleCallKitReject(dynamic eventBody, String reason) async {
    _rememberCallKitUuidFromData(eventBody);
    final callId = _callKitEventCallId(eventBody);
    if (state.state == CallState.incoming &&
        state.callInfo != null &&
        (callId == null || callId == state.callInfo?.callId)) {
      await rejectCall(reason: reason);
      return;
    }

    if (callId != null) {
      await _rejectCallById(callId, reason);
    }
    if (_currentCallKitUuid != null && (Platform.isIOS || Platform.isAndroid)) {
      await _endSystemCall(_currentCallKitUuid!);
    }
    if (!state.isInCall) {
      _resetState();
    }
  }

  Future<void> _handleCallKitEnd(dynamic eventBody) async {
    _rememberCallKitUuidFromData(eventBody);
    final callId = _callKitEventCallId(eventBody);
    if (state.state == CallState.incoming &&
        (callId == null || callId == state.callInfo?.callId)) {
      await rejectCall(reason: 'dismissed');
      return;
    }
    if (state.isInCall &&
        (callId == null || callId == state.callInfo?.callId)) {
      await endCall();
      return;
    }

    if (callId != null) {
      if (_callKitEventIsAccepted(eventBody)) {
        await _endCallById(callId, 'hangup');
      } else {
        await _rejectCallById(callId, 'dismissed');
      }
    }
    _resetState();
  }

  Future<void> _handleCallKitAccept([dynamic eventBody]) async {
    if (_isHandlingCallKitAccept) {
      debugPrint(
        '[CallService] CallKit accept already being handled, ignoring',
      );
      return;
    }
    _isHandlingCallKitAccept = true;

    try {
      await _restoreIncomingCallFromCallKitEvent(eventBody);

      if (_currentCallKitUuid != null) {
        try {
          await FlutterCallkitIncoming.setCallConnected(_currentCallKitUuid!);
        } catch (e) {
          debugPrint('[CallService] setCallConnected error: $e');
        }
      }

      await Future.delayed(const Duration(milliseconds: 200));

      if (state.state != CallState.incoming || state.callInfo == null) {
        debugPrint('[CallService] CallKit accept: call no longer incoming');
        final callId = _callKitEventCallId(eventBody);
        if (callId != null && state.state == CallState.idle) {
          await _rejectCallById(callId, 'answer_failed');
        }
        return;
      }

      final success = await acceptCall().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('[CallService] CallKit accept timeout');
          final callId =
              state.callInfo?.callId ?? _callKitEventCallId(eventBody);
          if (callId != null) {
            unawaited(_rejectCallById(callId, 'answer_timeout'));
          }
          state = state.copyWith(
            errorMessage: _callServiceText(
              zhCN: '接听超时，请重试',
              zhTW: '接聽逾時，請重試',
              en: 'Answer timed out. Please try again.',
            ),
          );
          return false;
        },
      );

      debugPrint('[CallService] CallKit acceptCall result: $success');

      if (success) {
        debugPrint(
          '[CallService] CallKit accept success, triggering onCallAccepted',
        );
        await Future.delayed(const Duration(milliseconds: 100));
        onCallAccepted?.call();
      } else {
        debugPrint('[CallService] CallKit accept failed');
        if (state.state == CallState.incoming ||
            state.state == CallState.idle) {
          if (_currentCallKitUuid != null) {
            await _endSystemCall(_currentCallKitUuid!);
          }
          onCallFailed?.call(
            state.errorMessage ??
                _callServiceText(
                  zhCN: '接听失败',
                  zhTW: '接聽失敗',
                  en: 'Failed to answer',
                ),
          );
        }
      }
    } catch (e) {
      debugPrint('[CallService] CallKit accept error: $e');
      if (_currentCallKitUuid != null &&
          state.state != CallState.connecting &&
          state.state != CallState.connected &&
          state.state != CallState.reconnecting) {
        await _endSystemCall(_currentCallKitUuid!);
      }
      state = state.copyWith(errorMessage: _genericCallFailureText());
      onCallFailed?.call(
        '${_callServiceText(
          zhCN: '接听通话失败',
          zhTW: '接聽通話失敗',
          en: 'Answer call failed',
        )}: $e',
      );
    } finally {
      _isHandlingCallKitAccept = false;
    }
  }

  VoidCallback? onCallAccepted;

  Future<void> _showCallKit(CallInfo callInfo) async {
    if (Platform.isAndroid && callInfo.callId != null) {
      _currentCallKitUuid = 'call-${callInfo.callId}';
    } else if (Platform.isIOS && callInfo.callId != null) {
      _currentCallKitUuid = _stableIosCallKitUuid(callInfo.callId!);
    } else {
      _currentCallKitUuid = const Uuid().v4();
    }

    final restored = await _useExistingSystemCallIfPresent(callInfo);
    if (restored) {
      return;
    }

    if (Platform.isAndroid) {
      await FlutterCallkitIncoming.showCallkitIncoming(
        buildAndroidIncomingCallParams(
          _incomingPayloadFromCallInfo(callInfo),
          uuid: _currentCallKitUuid!,
        ),
      );
      return;
    }

    final params = CallKitParams(
      id: _currentCallKitUuid!,
      nameCaller: callInfo.remoteName,
      appName: defaultAppDisplayName(),
      avatar: callInfo.remoteAvatar,
      handle: callInfo.remoteName,
      type: callInfo.type == CallType.video ? 1 : 0,
      duration: 30000,
      textAccept: _callActionText('answer'),
      textDecline: _callActionText('decline'),
      extra: _incomingPayloadFromCallInfo(callInfo),
      headers: <String, dynamic>{},
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#5865F2',
        backgroundUrl: '',
        actionColor: '#4CAF50',
        textColor: '#FFFFFF',
        isShowFullLockedScreen: true,
        isShowCallID: false,
        incomingCallNotificationChannelName: _callServiceText(
          zhCN: '\u6765\u7535\u901a\u77e5',
          zhTW: '\u4f86\u96fb\u901a\u77e5',
          en: 'Incoming call',
        ),
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

  Future<bool> _useExistingSystemCallIfPresent(CallInfo callInfo) async {
    if (_currentCallKitUuid == null ||
        !(Platform.isIOS || Platform.isAndroid)) {
      return false;
    }
    try {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      final calls = activeCalls is List ? activeCalls : const [];
      for (final rawCall in calls) {
        final call = _asStringKeyMap(rawCall);
        if (call == null) continue;
        final payload = _incomingPayloadFromCallKitData(call);
        if (payload == null) continue;
        final payloadCallId =
            int.tryParse(payload['call_id']?.toString() ?? '');
        if (payloadCallId == null || payloadCallId != callInfo.callId) {
          continue;
        }
        _currentCallKitUuid = call['id']?.toString() ??
            call['uuid']?.toString() ??
            _currentCallKitUuid;
        return true;
      }
    } catch (e) {
      debugPrint('[CallService] Check existing system call error: $e');
    }
    return false;
  }

  void handleCallAccepted([Map<String, dynamic>? payload]) {
    final eventCallId = payload == null ? null : _callIdFromPayload(payload);
    if (!_matchesCurrentCall(eventCallId)) {
      debugPrint(
        '[CallService] Ignoring call_accepted for call_id=$eventCallId, '
        'current=${state.callInfo?.callId}',
      );
      return;
    }
    if (state.state == CallState.outgoing) {
      _markCallConnected(
        connectedAt: DateTime.tryParse(
          payload?['connected_at']?.toString() ?? '',
        ),
        source: 'call_accepted_ws',
      );
    }
  }

  Future<void> handleCallRejected(
    String reason, [
    Map<String, dynamic>? payload,
  ]) async {
    final eventCallId = payload == null ? null : _callIdFromPayload(payload);
    if (!_matchesCurrentCall(eventCallId)) {
      debugPrint(
        '[CallService] Ignoring call_rejected for call_id=$eventCallId, '
        'current=${state.callInfo?.callId}',
      );
      return;
    }
    await _finishCallLocally(reason);
  }

  Future<void> handleCallCancelled([Map<String, dynamic>? payload]) async {
    final eventCallId = payload == null ? null : _callIdFromPayload(payload);
    if (!_matchesCurrentCall(eventCallId)) {
      debugPrint(
        '[CallService] Ignoring call_cancelled for call_id=$eventCallId, '
        'current=${state.callInfo?.callId}',
      );
      return;
    }
    _cancelIncomingCallTimeout();
    await _finishCallLocally('cancelled');
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  @override
  void dispose() {
    unawaited(_callEndTone.dispose());
    unawaited(_outgoingCallTone.dispose());
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
    _cancelOutgoingCallTimeout();
    _incomingCallTimer?.cancel();
    _incomingCallTimer = null;
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _cancelReconnectTimer();
    _stopCallHeartbeatTimer();

    if (_eventHandler != null && _engine != null) {
      _engine!.unregisterEventHandler(_eventHandler!);
      _eventHandler = null;
    }
    _engine?.release();
    _engine = null;
    unawaited(_disconnectLiveKitRoom());

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
