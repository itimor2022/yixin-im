// 文件用途：封装 PushNotificationService 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 PushNotificationService 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'api/api_client.dart';
import 'account_session_coordinator.dart';
import 'android_message_notification_service.dart';
import 'device_service.dart';

void _log(String message) {
  debugPrint(message);
}

// 关键声明：push notification service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 推送通知服务 - iOS 使用 APNs，Android 使用 FCM
class PushNotificationService {
  // iOS APNs MethodChannel
  static const _channel = MethodChannel('com.genericim/push');
  // Android 厂商推送桥接 MethodChannel
  static const _androidVendorChannel = MethodChannel('com.genericim/push_vendor');
  static const _bindingStorageKey = 'current_push_binding_v1';
  static const _bindingStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  final Ref _ref;
  String? _deviceToken;
  String _pushChannel = '';
  String _deviceType = '';
  final Map<String, String> _tokensByChannel = <String, String>{};
  final Map<String, String> _deviceTypesByChannel = <String, String>{};
  String _preferredAndroidChannel = 'fcm';
  bool _preferredVendorSdkAvailable = false;
  bool _preferredVendorConfigReady = false;
  bool _vendorInitRequestedToken = false;
  int _vendorRegistrationFailCount = 0;
  bool _isRegistered = false;
  bool _isRegistering = false;
  bool _isUploadingToken = false;
  bool _hasPendingTokenSync = false;
  bool _androidFcmListenersReady = false;
  bool _androidInitialMessageChecked = false;
  int _uploadRetryCount = 0;
  DateTime? _lastTokenSyncAt;
  DateTime? _lastVendorTokenRequestAt;

  // 重试配置
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);
  static const Duration _uploadRetryInterval = Duration(seconds: 30);
  static const Duration _tokenSyncRefreshInterval = Duration(hours: 6);
  static const Duration _vendorTokenRefreshInterval = Duration(minutes: 30);

  // iOS token 获取超时重试
  Timer? _tokenTimeoutTimer;
  Timer? _uploadRetryTimer;
  int _registerAttempts = 0;
  static const int _maxRegisterAttempts = 3;
  static const Duration _tokenTimeout = Duration(seconds: 10);

  // 通知回调
  Function(Map<String, dynamic>)? onNotificationReceived;
  Function(Map<String, dynamic>)? _onNotificationTapped;
  // 流程逻辑：`Function` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
  Future<bool> Function(Map<String, dynamic>)? _onNotificationReply;
  Future<void> Function(String, Map<String, dynamic>)? _onNativeCallKitEvent;
  Map<String, dynamic>? _pendingNotificationTap;
  Map<String, dynamic>? _pendingNotificationReply;
  final List<Map<String, dynamic>> _pendingNativeCallKitEvents =
      <Map<String, dynamic>>[];
  Timer? _notificationReplyRetryTimer;
  int _notificationReplyRetryCount = 0;
  bool _notificationReplySending = false;
  final Set<String> _revokedNotificationChats = <String>{};
  String? _lastNotificationTapSignature;
  DateTime? _lastNotificationTapAt;

  Function(Map<String, dynamic>)? get onNotificationTapped =>
      _onNotificationTapped;

  set onNotificationTapped(Function(Map<String, dynamic>)? handler) {
    _onNotificationTapped = handler;
    if (handler != null) {
      _flushPendingNotificationTap();
    }
  }

  set onNotificationReply(
      Future<bool> Function(Map<String, dynamic>)? handler) {
    _onNotificationReply = handler;
    if (handler != null && _pendingNotificationReply != null) {
      unawaited(retryPendingNotificationReply());
    }
  }

  set onNativeCallKitEvent(
    Future<void> Function(String, Map<String, dynamic>)? handler,
  ) {
    _onNativeCallKitEvent = handler;
    if (handler != null && _pendingNativeCallKitEvents.isNotEmpty) {
      unawaited(_flushPendingNativeCallKitEvents());
    }
  }

  PushNotificationService(this._ref) {
    _log('[Push] PushNotificationService created');
    if (Platform.isIOS) {
      _setupIOSMethodChannel();
    } else if (Platform.isAndroid) {
      _setupAndroidVendorMethodChannel();
      AndroidMessageNotificationService.instance.onNotificationTap =
          _dispatchNotificationTap;
    }
  }

  String? get deviceToken => _deviceToken;
  bool get isRegistered => _isRegistered;

  String get pushChannel => _pushChannel;

  void quarantinePendingInteractions() {
    _pendingNotificationTap = null;
    _pendingNotificationReply = null;
    _pendingNativeCallKitEvents.clear();
    _notificationReplyRetryTimer?.cancel();
    _notificationReplyRetryTimer = null;
    _notificationReplyRetryCount = 0;
    _lastNotificationTapSignature = null;
    _lastNotificationTapAt = null;
    AndroidMessageNotificationService.instance.clearPendingNotificationTap();
  }

  AccountContext? _captureActiveAccount() {
    final session = _ref.read(accountSessionCoordinatorProvider);
    return session.isActive ? session.context : null;
  }

  bool _isCurrentAccount(AccountContext context) {
    return _ref
        .read(accountSessionCoordinatorProvider.notifier)
        .isCurrent(context);
  }

  // ─── iOS APNs ────────────────────────────────────────────────────────────

  void _setupIOSMethodChannel() {
    _channel.setMethodCallHandler((call) async {
      _log('[Push iOS] Received call: ${call.method}');
      try {
        switch (call.method) {
          case 'onToken':
            final token = call.arguments?.toString() ?? '';
            if (token.isNotEmpty) {
              _handleToken(token, deviceType: 'ios', pushChannel: 'apns');
            }
          case 'onVoipToken':
            final token = call.arguments?.toString() ?? '';
            if (token.isNotEmpty) {
              _handleToken(token, deviceType: 'ios', pushChannel: 'apns_voip');
            }
          case 'onVoipTokenInvalidated':
            _log('[Push iOS] VoIP token invalidated');
          case 'onNotification':
            final raw = call.arguments?.toString();
            if (raw != null) _handleNotification(raw);
          case 'onNotificationTap':
            final raw = call.arguments?.toString();
            if (raw != null) _handleNotificationTap(raw);
          case 'onNativeCallKitEvent':
            final event = _asMap(call.arguments);
            if (event.isNotEmpty) {
              await _dispatchNativeCallKitEvent(event);
            }
          case 'onRegistrationFailed':
            _handleRegistrationFailed(call.arguments?.toString() ?? 'Unknown');
          default:
            _log('[Push iOS] Unknown method: ${call.method}');
        }
      } catch (e) {
        _log('[Push iOS] Error handling ${call.method}: $e');
      }
    });
    unawaited(_channel.invokeMethod<void>('nativeCallKitEventsReady'));
  }

  // ─── Android Vendor Push Bridge ──────────────────────────────────────────

  void _setupAndroidVendorMethodChannel() {
    _androidVendorChannel.setMethodCallHandler((call) async {
      try {
        switch (call.method) {
          case 'onToken':
            final args = _asMap(call.arguments);
            final token = (args['token'] ?? '').toString();
            final channel = (args['channel'] ?? '').toString();
            if (token.isNotEmpty) {
              _handleToken(
                token,
                deviceType: 'android',
                pushChannel: _normalizePushChannel(channel, 'android'),
              );
            }
            break;
          case 'onNotification':
            final args = _asMap(call.arguments);
            if (args.isNotEmpty) {
              _handleNotificationData(args);
            }
            break;
          case 'onNotificationTap':
            final args = _asMap(call.arguments);
            if (args.isNotEmpty) {
              _dispatchNotificationTap(args);
            }
            break;
          case 'onRegistrationFailed':
            final args = _asMap(call.arguments);
            final channel = (args['channel'] ?? '').toString();
            final reason = (args['reason'] ?? 'unknown').toString();
            _handleVendorRegistrationFailed(channel, reason);
            break;
          default:
            _log('[Push Vendor] Unknown method: ${call.method}');
            break;
        }
      } catch (e) {
        _log('[Push Vendor] Method handler error: $e');
      }
    });
    unawaited(Future<void>.delayed(const Duration(milliseconds: 800), () {
      return _consumePendingAndroidNotificationTap();
    }));
  }

  Future<String> _initAndroidVendorPush() async {
    try {
      final result =
          await _androidVendorChannel.invokeMapMethod<String, dynamic>(
        'initializeVendorPush',
      );
      _log('[Push Vendor] init result: $result');
      final preferred = _normalizePushChannel(
          result?['preferred_channel']?.toString(), 'android');
      _preferredAndroidChannel = preferred;
      _preferredVendorSdkAvailable = _pickVendorBool(
        result?['sdk_available'],
        preferred,
      );
      _preferredVendorConfigReady = _pickVendorBool(
        result?['config_ready'],
        preferred,
      );
      _vendorInitRequestedToken = result?['integrated'] == true;
      await _consumePendingAndroidVendorToken();
      await _consumePendingAndroidNotificationTap();
      return preferred;
    } catch (e) {
      _log('[Push Vendor] init error: $e');
      _preferredAndroidChannel = 'fcm';
      _preferredVendorSdkAvailable = false;
      _preferredVendorConfigReady = false;
      _vendorInitRequestedToken = false;
      return 'fcm';
    }
  }

  Future<void> _requestAndroidVendorToken(String channel) async {
    final normalized = _normalizePushChannel(channel, 'android');
    if (normalized == 'fcm') {
      return;
    }
    _lastVendorTokenRequestAt = DateTime.now();
    try {
      final result =
          await _androidVendorChannel.invokeMapMethod<String, dynamic>(
        'requestVendorToken',
        <String, dynamic>{'channel': normalized},
      );
      _log('[Push Vendor] request token result: $result');
      await _consumePendingAndroidVendorToken();
      final started = result?['started'] == true;
      if (normalized == _preferredAndroidChannel && !started) {
        _log(
          '[Push Vendor] preferred vendor token request not started, fallback to FCM',
        );
        _preferredVendorSdkAvailable = false;
        _preferredVendorConfigReady = false;
        await _tryRegisterFcmFallbackToken();
      }
    } catch (e) {
      _log('[Push Vendor] request token error: $e');
      if (normalized == _preferredAndroidChannel) {
        _preferredVendorSdkAvailable = false;
        _preferredVendorConfigReady = false;
        await _tryRegisterFcmFallbackToken();
      }
    }
  }

  Future<void> _consumePendingAndroidVendorToken() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final pending =
          await _androidVendorChannel.invokeMapMethod<String, dynamic>(
        'consumePendingVendorToken',
      );
      final token = (pending?['token'] ?? '').toString();
      final channel = (pending?['channel'] ?? '').toString();
      if (token.isNotEmpty) {
        _log('[Push Vendor] consumed pending token, channel=$channel');
        _handleToken(
          token,
          deviceType: 'android',
          pushChannel: _normalizePushChannel(channel, 'android'),
        );
      }
    } catch (e) {
      _log('[Push Vendor] consume pending token failed: $e');
    }
  }

  Future<void> _consumePendingAndroidNotificationTap() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final pending =
          await _androidVendorChannel.invokeMapMethod<String, dynamic>(
        'consumePendingNotificationTap',
      );
      final data = _asMap(pending);
      if (data.isNotEmpty) {
        _log('[Push Vendor] consumed pending notification tap: $data');
        _dispatchNotificationTap(data);
      }
    } catch (e) {
      _log('[Push Vendor] consume pending notification tap failed: $e');
    }
  }

  Future<void> _maybeRefreshAndroidVendorToken() async {
    if (!Platform.isAndroid) {
      return;
    }
    final preferred = _preferredAndroidChannel;
    if (preferred == 'fcm') {
      return;
    }
    if (_deviceToken != null && _pushChannel == preferred) {
      return;
    }

    final now = DateTime.now();
    if (_lastVendorTokenRequestAt != null &&
        now.difference(_lastVendorTokenRequestAt!) <
            _vendorTokenRefreshInterval) {
      return;
    }

    _log('[Push Vendor] refreshing token for preferred channel: $preferred');
    await _requestAndroidVendorToken(preferred);
  }

  String _normalizePushChannel(String? channel, String deviceType) {
    final normalized = (channel ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'apns':
      case 'apns_voip':
      case 'apns-voip':
      case 'voip':
      case 'fcm':
      case 'hms':
      case 'jpush':
      case 'xiaomi':
      case 'oppo':
        return normalized == 'apns-voip' || normalized == 'voip'
            ? 'apns_voip'
            : normalized;
      case 'huawei':
        return 'hms';
      case 'jiguang':
      case 'aurora':
        return 'jpush';
      case 'mi':
      case 'mipush':
        return 'xiaomi';
      case 'opush':
      case 'heytap':
        return 'oppo';
      default:
        if (deviceType == 'ios') return 'apns';
        if (deviceType == 'android') return 'fcm';
        return 'unknown';
    }
  }

  Map<String, dynamic> _asMap(dynamic arguments) {
    if (arguments is Map) {
      return arguments.map((key, value) => MapEntry(key.toString(), value));
    }
    if (arguments is String && arguments.isNotEmpty) {
      try {
        final parsed = json.decode(arguments);
        if (parsed is Map<String, dynamic>) return parsed;
        if (parsed is Map) {
          return parsed.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  bool _pickVendorBool(dynamic raw, String channel) {
    if (channel == 'fcm') return false;
    if (raw is Map) {
      final value = raw[channel];
      if (value is bool) return value;
      if (value is String) return value.toLowerCase() == 'true';
      if (value is num) return value != 0;
    }
    return false;
  }

  bool _shouldAcceptFcmToken() {
    if (_preferredAndroidChannel == 'fcm') {
      return true;
    }
    // If preferred vendor is available and configured, keep vendor as source of truth.
    if (_preferredVendorSdkAvailable && _preferredVendorConfigReady) {
      return false;
    }
    return true;
  }

  Future<void> _tryRegisterFcmFallbackToken() async {
    if (!Platform.isAndroid) {
      return;
    }
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token.isNotEmpty) {
        _handleToken(token, deviceType: 'android', pushChannel: 'fcm');
      }
    } catch (e) {
      _log('[Push FCM] fallback getToken failed: $e');
    }
  }

  // ─── Android FCM ─────────────────────────────────────────────────────────

  Future<void> _setupAndroidFCM() async {
    final messaging = FirebaseMessaging.instance;

    // 请求通知权限（Android 13+）
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _log('[Push FCM] Permission status: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      _log('[Push FCM] Permission denied');
      return;
    }

    // 获取 FCM Token
    try {
      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        _log('[Push FCM] Got token, length: ${token.length}');
        if (_shouldAcceptFcmToken()) {
          _handleToken(token, deviceType: 'android', pushChannel: 'fcm');
        } else {
          _log('[Push FCM] Ignored token because vendor channel is preferred');
        }
      }
    } catch (e) {
      _log('[Push FCM] Failed to get token: $e');
    }

    // Token 刷新监听
    if (!_androidFcmListenersReady) {
      _androidFcmListenersReady = true;

      messaging.onTokenRefresh.listen((newToken) {
        _log('[Push FCM] Token refreshed');
        if (_shouldAcceptFcmToken()) {
          _handleToken(newToken, deviceType: 'android', pushChannel: 'fcm');
        } else {
          _log(
              '[Push FCM] Ignored refreshed token because vendor channel is preferred');
        }
      });

      // 前台消息监听
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _log('[Push FCM] Foreground message: ${message.messageId}');
        final data = {...message.data};
        if (message.notification != null) {
          data['title'] = message.notification!.title ?? '';
          data['body'] = message.notification!.body ?? '';
        }
        _handleNotificationData(data);
      });

      // 从通知栏点击打开（App 后台时）
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _log('[Push FCM] Notification tapped: ${message.messageId}');
        _dispatchNotificationTap(message.data);
      });
    }

    // App 完全关闭时点击通知启动（初始消息）
    if (!_androidInitialMessageChecked) {
      _androidInitialMessageChecked = true;
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _log('[Push FCM] Initial message: ${initialMessage.messageId}');
        Future.delayed(const Duration(milliseconds: 500), () {
          _dispatchNotificationTap(initialMessage.data);
        });
      }
    }
  }

  Future<void> _ensureAndroidCallNotificationPermissions() async {
    if (!Platform.isAndroid) return;

    try {
      await FlutterCallkitIncoming.requestNotificationPermission({
        'title': 'Notification permission',
        'rationaleMessagePermission':
            'Notification permission is required for incoming calls.',
        'postNotificationMessageRequired':
            'Please allow notifications to receive incoming calls.',
      });
    } catch (e) {
      _log('[Push] Call notification permission request failed: $e');
    }

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt < 34) return;

      final canUse = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (canUse != true) {
        await FlutterCallkitIncoming.requestFullIntentPermission();
      }
    } catch (e) {
      _log('[Push] Full-screen incoming call permission check failed: $e');
    }
  }

  // ─── 公共入口 ─────────────────────────────────────────────────────────────

  /// 请求推送权限并注册
  Future<void> register() async {
    // 捕获账号代次；每个异步步骤后复核，防止切号期间把旧账号 Token 上传给新账号。
    final account = _captureActiveAccount();
    if (account == null) {
      _log('[Push] register() skipped without an active account');
      return;
    }
    _log('[Push] register() called, platform: ${Platform.operatingSystem}');

    if (Platform.isAndroid) {
      await _ensureAndroidCallNotificationPermissions();
      if (!_isCurrentAccount(account)) return;
      final preferredChannel = await _initAndroidVendorPush();
      if (!_isCurrentAccount(account)) return;
      if (preferredChannel != 'fcm' && !_vendorInitRequestedToken) {
        await _requestAndroidVendorToken(preferredChannel);
      }
      await _setupAndroidFCM();
      if (!_isCurrentAccount(account)) return;
      await _consumePendingAndroidNotificationTap();
      if (_deviceToken == null && _preferredAndroidChannel != 'fcm') {
        Future.delayed(const Duration(seconds: 5), () {
          if (_deviceToken == null) {
            _requestAndroidVendorToken(_preferredAndroidChannel);
          }
        });
      }
      return;
    }

    if (!Platform.isIOS) return;

    // iOS 防重入
    if (_isRegistering) {
      _log('[Push iOS] Already registering, skipping');
      return;
    }
    if (_deviceToken != null) {
      _log('[Push iOS] Already have token, re-uploading');
      _deviceType = 'ios';
      _pushChannel = _normalizePushChannel(_pushChannel, 'ios');
      unawaited(_syncCurrentToken());
      return;
    }

    _isRegistering = true;
    _registerAttempts++;
    _log(
        '[Push iOS] Registration attempt $_registerAttempts/$_maxRegisterAttempts');

    try {
      await _channel.invokeMethod('registerForPush');

      _tokenTimeoutTimer?.cancel();
      _tokenTimeoutTimer = Timer(_tokenTimeout, () {
        _isRegistering = false;
        if (_deviceToken == null && _registerAttempts < _maxRegisterAttempts) {
          _log('[Push iOS] Token timeout, retrying...');
          register();
        } else if (_deviceToken == null) {
          _log('[Push iOS] Max attempts reached, giving up');
        }
      });
    } catch (e) {
      _log('[Push iOS] Registration failed: $e');
      _isRegistering = false;
      if (_registerAttempts < _maxRegisterAttempts) {
        Future.delayed(_retryDelay, () => register());
      }
    }
  }

  // ─── 内部处理 ─────────────────────────────────────────────────────────────

  void _handleToken(
    String token, {
    required String deviceType,
    String? pushChannel,
  }) {
    _tokenTimeoutTimer?.cancel();
    _isRegistering = false;
    _registerAttempts = 0;

    if (token.isEmpty || _captureActiveAccount() == null) return;
    // 同一设备可同时持有厂商推送和 FCM Token，按通道分别记录并同步。
    final normalizedChannel = _normalizePushChannel(pushChannel, deviceType);
    _tokensByChannel[normalizedChannel] = token;
    _deviceTypesByChannel[normalizedChannel] = deviceType;
    if (_deviceToken == token &&
        _pushChannel == normalizedChannel &&
        _isRegistered) {
      _log('[Push] Token unchanged, skipping upload');
      return;
    }

    _deviceToken = token;
    _deviceType = deviceType;
    _pushChannel = normalizedChannel;
    if (deviceType == 'android' &&
        normalizedChannel == _preferredAndroidChannel) {
      _vendorRegistrationFailCount = 0;
    }
    _isRegistered = false;
    unawaited(_syncCurrentToken());
  }

  Future<void> _syncCurrentToken() async {
    if (_captureActiveAccount() == null) return;
    final token = _deviceToken;
    final deviceType = _deviceType;
    final pushChannel = _pushChannel;
    if (token == null ||
        token.isEmpty ||
        deviceType.isEmpty ||
        pushChannel.isEmpty) {
      return;
    }
    if (_isUploadingToken) {
      _hasPendingTokenSync = true;
      return;
    }

    _isUploadingToken = true;
    try {
      final uploaded = await _uploadToken(
        token,
        deviceType: deviceType,
        pushChannel: pushChannel,
      );
      if (uploaded) {
        _isRegistered = true;
        _uploadRetryCount = 0;
        _lastTokenSyncAt = DateTime.now();
        _cancelUploadRetry();
      } else {
        _isRegistered = false;
        _uploadRetryCount += 1;
        _scheduleUploadRetry();
      }
    } finally {
      _isUploadingToken = false;
      if (_hasPendingTokenSync) {
        _hasPendingTokenSync = false;
        unawaited(_syncCurrentToken());
      }
    }
  }

  /// 前台保活同步：用于登录后长时间运行，确保服务端 token 状态不漂移。
  Future<void> ensureTokenSynced() async {
    final account = _captureActiveAccount();
    if (account == null) return;
    await _consumePendingAndroidVendorToken();
    if (!_isCurrentAccount(account)) return;
    await _maybeRefreshAndroidVendorToken();
    if (!_isCurrentAccount(account)) return;

    if (_tokensByChannel.isEmpty) {
      return;
    }
    if (_isUploadingToken) {
      return;
    }

    final now = DateTime.now();
    final recentlySynced = _lastTokenSyncAt != null &&
        now.difference(_lastTokenSyncAt!) < _tokenSyncRefreshInterval;
    if (_isRegistered && recentlySynced) {
      return;
    }

    _isUploadingToken = true;
    try {
      // “已注册”表示当前已知的所有通道 Token 都已绑定到服务端，而非仅获取到本地 Token。
      var allUploaded = true;
      for (final entry in Map<String, String>.from(_tokensByChannel).entries) {
        final deviceType = _deviceTypesByChannel[entry.key] ?? _deviceType;
        if (deviceType.isEmpty ||
            !await _uploadToken(
              entry.value,
              deviceType: deviceType,
              pushChannel: entry.key,
            )) {
          allUploaded = false;
        }
      }
      _isRegistered = allUploaded;
      if (allUploaded) {
        _lastTokenSyncAt = DateTime.now();
      }
    } finally {
      _isUploadingToken = false;
      if (_hasPendingTokenSync) {
        _hasPendingTokenSync = false;
        unawaited(_syncCurrentToken());
      }
    }
  }

  void _scheduleUploadRetry() {
    if (_uploadRetryTimer != null || _deviceToken == null) {
      return;
    }
    final delay = _currentUploadRetryDelay();
    _log(
      '[Push] Schedule token re-upload #${_uploadRetryCount + 1} in ${delay.inSeconds}s',
    );
    _uploadRetryTimer = Timer(delay, () {
      _uploadRetryTimer?.cancel();
      _uploadRetryTimer = null;
      unawaited(_syncCurrentToken());
    });
  }

  Duration _currentUploadRetryDelay() {
    final capped = _uploadRetryCount > 4 ? 4 : _uploadRetryCount;
    final seconds = _uploadRetryInterval.inSeconds * (1 << capped);
    return Duration(seconds: seconds);
  }

  void _cancelUploadRetry() {
    _uploadRetryTimer?.cancel();
    _uploadRetryTimer = null;
  }

  Future<bool> _uploadToken(
    String token, {
    required String deviceType,
    required String pushChannel,
    int retryCount = 0,
  }) async {
    // 推送绑定由账号、设备和通道共同确定，上传前后都要确认账号上下文未变化。
    final account = _captureActiveAccount();
    if (account == null) return false;
    try {
      _log(
        '[Push] Uploading token to server (deviceType: $deviceType, channel: $pushChannel)...',
      );
      final api = _ref.read(apiClientProvider);
      final metadata = await _buildPushDeviceMetadata(deviceType);
      final deviceId = await DeviceService.getDeviceId();
      if (!_isCurrentAccount(account)) return false;
      final response = await api.post('/user/push-token', data: {
        'device_id': deviceId,
        'push_token': token,
        'registration_id': token,
        'device_type': deviceType,
        'platform': deviceType,
        'push_channel': pushChannel,
        'push_provider': pushChannel,
        ...metadata,
      });

      if (!_isCurrentAccount(account)) return false;
      if (response.isSuccess) {
        final responseData = response.data;
        final bindingId = responseData is Map
            ? int.tryParse(responseData['binding_id']?.toString() ?? '')
            : null;
        await _saveCurrentBinding(
          bindingId: bindingId,
          deviceId: deviceId,
          token: token,
          deviceType: deviceType,
          pushChannel: pushChannel,
        );
        _log('[Push] Token uploaded successfully');
        return true;
      } else if (retryCount < _maxRetries) {
        await Future.delayed(_retryDelay);
        return _uploadToken(
          token,
          deviceType: deviceType,
          pushChannel: pushChannel,
          retryCount: retryCount + 1,
        );
      } else {
        _log('[Push] Upload failed after $_maxRetries retries');
        return false;
      }
    } catch (e) {
      _log('[Push] Failed to upload token: $e');
      if (retryCount < _maxRetries) {
        await Future.delayed(_retryDelay);
        return _uploadToken(
          token,
          deviceType: deviceType,
          pushChannel: pushChannel,
          retryCount: retryCount + 1,
        );
      }
      return false;
    }
  }

  Future<Map<String, dynamic>> _buildPushDeviceMetadata(
      String deviceType) async {
    final metadata = <String, dynamic>{};

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version.trim();
      final buildNumber = packageInfo.buildNumber.trim();
      metadata['app_version'] =
          buildNumber.isEmpty ? version : '$version+$buildNumber';
    } catch (e) {
      _log('[Push] Failed to read package info: $e');
    }

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (deviceType == 'android' && Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        final brand = android.manufacturer.trim().isNotEmpty
            ? android.manufacturer
            : android.brand;
        metadata['brand'] = brand;
        metadata['model'] = android.model;
        metadata['device_name'] = '$brand ${android.model}'.trim();
      } else if (deviceType == 'ios' && Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        metadata['brand'] = 'Apple';
        metadata['model'] = ios.utsname.machine;
        metadata['device_name'] = ios.name.isNotEmpty ? ios.name : ios.model;
      }
    } catch (e) {
      _log('[Push] Failed to read device info: $e');
    }

    metadata.removeWhere(
      (_, value) => value == null || value.toString().trim().isEmpty,
    );
    return metadata;
  }

  void _handleNotification(String jsonString) {
    try {
      final data = json.decode(jsonString) as Map<String, dynamic>;
      _log('[Push] Notification received: $data');
      _handleNotificationData(data);
    } catch (e) {
      _log('[Push] Failed to parse notification: $e');
    }
  }

  void _handleNotificationData(Map<String, dynamic> data) {
    final revokedChatId = revokedMessageNotificationChatId(data);
    if (revokedChatId != null) {
      _revokedNotificationChats.add(revokedChatId);
      if (_pendingNotificationTap?['chat_id']?.toString().trim() ==
          revokedChatId) {
        _pendingNotificationTap = null;
      }
      unawaited(
        AndroidMessageNotificationService.instance.cancelMessageNotification(
          chatId: revokedChatId,
          messageId: data['msg_id']?.toString(),
        ),
      );
      return;
    }
    if (data['type']?.toString().trim() == 'new_message') {
      final chatId = data['chat_id']?.toString().trim() ?? '';
      if (chatId.isNotEmpty) _revokedNotificationChats.remove(chatId);
    }
    onNotificationReceived?.call(data);
  }

  Future<void> _dispatchNativeCallKitEvent(
    Map<String, dynamic> event,
  ) async {
    final eventName = event['event']?.toString().trim() ?? '';
    final body = _asMap(event['body']);
    if (eventName.isEmpty || body.isEmpty) {
      _log('[Push iOS] Ignoring invalid native CallKit event');
      return;
    }
    final handler = _onNativeCallKitEvent;
    if (handler == null) {
      _pendingNativeCallKitEvents.add(
        <String, dynamic>{'event': eventName, 'body': body},
      );
      return;
    }
    await handler(eventName, body);
  }

  Future<void> _flushPendingNativeCallKitEvents() async {
    final handler = _onNativeCallKitEvent;
    if (handler == null || _pendingNativeCallKitEvents.isEmpty) return;
    final events = List<Map<String, dynamic>>.from(_pendingNativeCallKitEvents);
    _pendingNativeCallKitEvents.clear();
    for (final event in events) {
      final name = event['event']?.toString().trim() ?? '';
      final body = _asMap(event['body']);
      if (name.isEmpty || body.isEmpty) continue;
      await handler(name, body);
    }
  }

  void _handleNotificationTap(String jsonString) {
    try {
      final data = json.decode(jsonString) as Map<String, dynamic>;
      _log('[Push] Notification tapped: $data');
      _dispatchNotificationTap(data);
    } catch (e) {
      _log('[Push] Failed to parse notification tap: $e');
    }
  }

  void _dispatchNotificationTap(Map<String, dynamic> data) {
    if (data.isEmpty) {
      return;
    }
    // 冷启动时路由/回复处理器可能尚未注册，先暂存，处理器就绪后再投递。
    final normalized = Map<String, dynamic>.from(data);
    if (normalized['type']?.toString().trim() == 'notification_reply') {
      unawaited(recordNotificationReplyTrace(
        'dart_dispatch_received',
        data: normalized,
        fields: <String, Object?>{
          'handler_ready': _onNotificationReply != null,
          'reply_length': normalized['reply_text']?.toString().length ?? 0,
        },
      ));
      _pendingNotificationReply = normalized;
      _notificationReplyRetryTimer?.cancel();
      _notificationReplyRetryTimer = null;
      _notificationReplyRetryCount = 0;
      unawaited(retryPendingNotificationReply());
      return;
    }
    final chatId = normalized['chat_id']?.toString().trim() ?? '';
    if (chatId.isNotEmpty && _revokedNotificationChats.contains(chatId)) {
      _log('[Push] Revoked notification tap ignored chat=$chatId');
      return;
    }
    final handler = _onNotificationTapped;
    if (handler == null) {
      _pendingNotificationTap = normalized;
      return;
    }

    // 原生桥、FCM 和本地通知可能同时上报同一次点击，短窗口内按签名去重。
    if (_isDuplicateNotificationTap(normalized)) {
      _log('[Push] Duplicate notification tap ignored');
      return;
    }

    _markNotificationTapDispatched(normalized);
    handler(normalized);
  }

  Future<bool> retryPendingNotificationReply() async {
    final pending = _pendingNotificationReply;
    final handler = _onNotificationReply;
    if (pending == null) return false;
    if (handler == null) {
      await recordNotificationReplyTrace(
        'dart_retry_waiting_handler',
        data: pending,
        fields: const <String, Object?>{'handler_ready': false},
      );
      return false;
    }
    if (_notificationReplySending) return false;
    _notificationReplySending = true;
    var handled = false;
    try {
      await recordNotificationReplyTrace(
        'dart_handler_attempt',
        data: pending,
        fields: <String, Object?>{
          'attempt': _notificationReplyRetryCount + 1,
          'handler_ready': true,
        },
      );
      handled = await handler(Map<String, dynamic>.from(pending));
      await recordNotificationReplyTrace(
        'dart_handler_result',
        data: pending,
        fields: <String, Object?>{'result': handled ? 'handled' : 'retry'},
      );
      if (handled && identical(_pendingNotificationReply, pending)) {
        _pendingNotificationReply = null;
        _notificationReplyRetryTimer?.cancel();
        _notificationReplyRetryTimer = null;
        _notificationReplyRetryCount = 0;
      }
    } finally {
      _notificationReplySending = false;
    }
    if (!handled && identical(_pendingNotificationReply, pending)) {
      _scheduleNotificationReplyRetry();
    }
    return handled;
  }

  Future<void> recordNotificationReplyTrace(
    String stage, {
    Map<String, dynamic>? data,
    Map<String, Object?> fields = const <String, Object?>{},
  }) async {
    if (!Platform.isAndroid) return;
    final payload = <String, Object?>{
      'stage': stage,
      if (data != null) 'chat_id': data['chat_id']?.toString(),
      if (data != null) 'client_msg_id': data['client_msg_id']?.toString(),
      ...fields,
    };
    try {
      await _androidVendorChannel.invokeMapMethod<String, dynamic>(
        'recordNotificationReplyTrace',
        payload,
      );
    } catch (_) {
      // Reply delivery must never depend on diagnostic persistence.
    }
  }

  void _scheduleNotificationReplyRetry() {
    if (_notificationReplyRetryTimer?.isActive == true ||
        _notificationReplyRetryCount >= 12) {
      return;
    }
    _notificationReplyRetryCount++;
    _notificationReplyRetryTimer = Timer(const Duration(seconds: 2), () {
      _notificationReplyRetryTimer = null;
      unawaited(retryPendingNotificationReply());
    });
  }

  void _flushPendingNotificationTap() {
    final pending = _pendingNotificationTap;
    if (pending == null) {
      return;
    }
    _pendingNotificationTap = null;
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      _dispatchNotificationTap(pending);
    });
  }

  bool _isDuplicateNotificationTap(Map<String, dynamic> data) {
    final signature = debugNotificationTapSignature(data);
    if (signature.isEmpty || _lastNotificationTapSignature != signature) {
      return false;
    }
    final lastAt = _lastNotificationTapAt;
    return lastAt != null &&
        DateTime.now().difference(lastAt) < const Duration(seconds: 3);
  }

  void _markNotificationTapDispatched(Map<String, dynamic> data) {
    _lastNotificationTapSignature = debugNotificationTapSignature(data);
    _lastNotificationTapAt = DateTime.now();
  }

  void _handleRegistrationFailed(String errorMessage) {
    _log('[Push iOS] Registration failed: $errorMessage');
    _isRegistering = false;
    if (_registerAttempts < _maxRegisterAttempts) {
      Future.delayed(const Duration(seconds: 5), () => register());
    }
  }

  void _handleVendorRegistrationFailed(String channel, String reason) {
    final normalized = _normalizePushChannel(channel, 'android');
    _log(
        '[Push Vendor] registration failed, channel=$normalized reason=$reason');
    if (normalized == _preferredAndroidChannel) {
      _vendorRegistrationFailCount += 1;
      if (_vendorRegistrationFailCount >= 3 && _deviceToken == null) {
        _log('[Push Vendor] too many failures, fallback to FCM');
        unawaited(_tryRegisterFcmFallbackToken());
      }
    }
    if (_deviceToken == null && normalized != 'fcm') {
      Future.delayed(const Duration(seconds: 3), () {
        _requestAndroidVendorToken(normalized);
      });
    }
  }

  /// 返回当前客户端持有的精确推送绑定，供 /auth/logout 一次性解绑。
  Future<List<Map<String, dynamic>>> buildLogoutBindings() async {
    if (_tokensByChannel.isNotEmpty) {
      final deviceId = await DeviceService.getDeviceId();
      return _tokensByChannel.entries
          .where((entry) =>
              entry.key.trim().isNotEmpty && entry.value.trim().isNotEmpty)
          .map(
            (entry) => <String, dynamic>{
              'device_id': deviceId,
              'push_channel': entry.key,
              'push_token': entry.value,
            },
          )
          .toList(growable: false);
    }

    try {
      final raw = await _bindingStorage.read(key: _bindingStorageKey);
      if (raw == null || raw.trim().isEmpty) return const [];
      final decoded = jsonDecode(raw);
      final rawBindings = decoded is List
          ? decoded
          : decoded is Map
              ? [decoded]
              : const [];
      final currentDeviceId = await DeviceService.getDeviceId();
      return rawBindings
          .whereType<Map>()
          .map((value) => Map<String, dynamic>.from(value))
          .where((binding) =>
              binding['device_id']?.toString() == currentDeviceId &&
              !(binding['push_channel']?.toString().trim().isEmpty ?? true) &&
              !(binding['push_token']?.toString().trim().isEmpty ?? true))
          .toList(growable: false);
    } catch (e) {
      _log('[Push] Failed to restore current binding: $e');
      return const [];
    }
  }

  Future<void> _saveCurrentBinding({
    required int? bindingId,
    required String deviceId,
    required String token,
    required String deviceType,
    required String pushChannel,
  }) async {
    final binding = <String, dynamic>{
      if (bindingId != null) 'binding_id': bindingId,
      'device_id': deviceId,
      'device_type': deviceType,
      'push_channel': pushChannel,
      'push_token': token,
    };
    final existing = <Map<String, dynamic>>[];
    final raw = await _bindingStorage.read(key: _bindingStorageKey);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        final values = decoded is List
            ? decoded
            : decoded is Map
                ? [decoded]
                : const [];
        existing.addAll(
          values
              .whereType<Map>()
              .map((value) => Map<String, dynamic>.from(value)),
        );
      } catch (_) {
        // Replace an unreadable legacy value with the current binding.
      }
    }
    existing.removeWhere((value) =>
        value['device_id']?.toString() == deviceId &&
        value['push_channel']?.toString() == pushChannel);
    existing.add(binding);
    await _bindingStorage.write(
      key: _bindingStorageKey,
      value: jsonEncode(existing),
    );
  }

  /// 清除本地及厂商 token。服务端解绑由 /auth/logout 统一完成。
  Future<void> clearToken() async {
    _tokenTimeoutTimer?.cancel();
    _cancelUploadRetry();
    _isRegistering = false;
    _isUploadingToken = false;
    _registerAttempts = 0;
    _uploadRetryCount = 0;
    _lastTokenSyncAt = null;
    _lastVendorTokenRequestAt = null;
    _vendorRegistrationFailCount = 0;
    _vendorInitRequestedToken = false;
    _hasPendingTokenSync = false;
    quarantinePendingInteractions();

    // Android：从 FCM 取消订阅
    if (Platform.isAndroid) {
      try {
        await FirebaseMessaging.instance.deleteToken();
        _log('[Push FCM] Token deleted from FCM');
      } catch (e) {
        _log('[Push FCM] Failed to delete FCM token: $e');
      }
    }

    _deviceToken = null;
    _deviceType = '';
    _pushChannel = '';
    _tokensByChannel.clear();
    _deviceTypesByChannel.clear();
    _isRegistered = false;
    await _bindingStorage.delete(key: _bindingStorageKey);
  }

  /// 强制重新注册（用于诊断）
  Future<void> forceReregister() async {
    _tokenTimeoutTimer?.cancel();
    _cancelUploadRetry();
    _isRegistering = false;
    _isUploadingToken = false;
    _registerAttempts = 0;
    _uploadRetryCount = 0;
    _lastTokenSyncAt = null;
    _lastVendorTokenRequestAt = null;
    _vendorRegistrationFailCount = 0;
    _vendorInitRequestedToken = false;
    _deviceToken = null;
    _deviceType = '';
    _pushChannel = '';
    _tokensByChannel.clear();
    _deviceTypesByChannel.clear();
    _isRegistered = false;
    await register();
  }
}

/// Public for regression tests. Distinct announcements in the same chat must
/// not be collapsed into one tap while native and Flutter are both resuming.
String debugNotificationTapSignature(Map<String, dynamic> data) {
  final stableKeys = <String>[
    'type',
    'chat_id',
    'chat_type',
    'message_id',
    'notification_id',
    'announcement_id',
    'call_id',
    'meeting_id',
    'sender_id',
    'push_tap',
  ];
  final parts = <String>[];
  for (final key in stableKeys) {
    final value = data[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      parts.add('$key=$value');
    }
  }
  if (parts.isNotEmpty) {
    return parts.join('|');
  }

  final keys = data.keys.map((key) => key.toString()).toList()..sort();
  return keys.map((key) => '$key=${data[key]}').join('|');
}

/// Provider — 推送服务需要在整个应用生命周期内保持活跃
final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref);
});
