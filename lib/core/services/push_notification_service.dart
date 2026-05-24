import 'dart:async';
import 'dart:convert';
import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'api/api_client.dart';

void _log(String message) {
  if (kDebugMode) debugPrint(message);
}

/// 推送通知服务 - iOS 使用 APNs，Android 使用 FCM
class PushNotificationService {
  // iOS APNs MethodChannel
  static const _channel = MethodChannel('com.gaoranim/push');
  // Android 厂商推送桥接 MethodChannel
  static const _androidVendorChannel =
      MethodChannel('com.gaoranim/push_vendor');

  final Ref _ref;
  String? _deviceToken;
  String _pushChannel = '';
  String _deviceType = '';
  String _preferredAndroidChannel = 'fcm';
  bool _preferredVendorSdkAvailable = false;
  bool _preferredVendorConfigReady = false;
  bool _vendorInitRequestedToken = false;
  int _vendorRegistrationFailCount = 0;
  bool _isRegistered = false;
  bool _isRegistering = false;
  bool _isUploadingToken = false;
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
  Function(Map<String, dynamic>)? onNotificationTapped;

  PushNotificationService(this._ref) {
    _log('[Push] PushNotificationService created');
    if (Platform.isIOS) {
      _setupIOSMethodChannel();
    } else if (Platform.isAndroid) {
      _setupAndroidVendorMethodChannel();
    }
  }

  String? get deviceToken => _deviceToken;
  bool get isRegistered => _isRegistered;

  String get pushChannel => _pushChannel;

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
          case 'onNotification':
            final raw = call.arguments?.toString();
            if (raw != null) _handleNotification(raw);
          case 'onNotificationTap':
            final raw = call.arguments?.toString();
            if (raw != null) _handleNotificationTap(raw);
          case 'onRegistrationFailed':
            _handleRegistrationFailed(call.arguments?.toString() ?? 'Unknown');
          default:
            _log('[Push iOS] Unknown method: ${call.method}');
        }
      } catch (e) {
        _log('[Push iOS] Error handling ${call.method}: $e');
      }
    });
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
              onNotificationReceived?.call(args);
            }
            break;
          case 'onNotificationTap':
            final args = _asMap(call.arguments);
            if (args.isNotEmpty) {
              onNotificationTapped?.call(args);
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
      case 'fcm':
      case 'hms':
      case 'xiaomi':
      case 'oppo':
        return normalized;
      case 'huawei':
        return 'hms';
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
        onNotificationReceived?.call(data);
      });

      // 从通知栏点击打开（App 后台时）
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _log('[Push FCM] Notification tapped: ${message.messageId}');
        onNotificationTapped?.call(message.data);
      });
    }

    // App 完全关闭时点击通知启动（初始消息）
    if (!_androidInitialMessageChecked) {
      _androidInitialMessageChecked = true;
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _log('[Push FCM] Initial message: ${initialMessage.messageId}');
        Future.delayed(const Duration(milliseconds: 500), () {
          onNotificationTapped?.call(initialMessage.data);
        });
      }
    }
  }

  // ─── 公共入口 ─────────────────────────────────────────────────────────────

  /// 请求推送权限并注册
  Future<void> register() async {
    _log('[Push] register() called, platform: ${Platform.operatingSystem}');

    if (Platform.isAndroid) {
      final preferredChannel = await _initAndroidVendorPush();
      if (preferredChannel != 'fcm' && !_vendorInitRequestedToken) {
        await _requestAndroidVendorToken(preferredChannel);
      }
      await _setupAndroidFCM();
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

    if (token.isEmpty) return;
    final normalizedChannel = _normalizePushChannel(pushChannel, deviceType);
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
    final token = _deviceToken;
    final deviceType = _deviceType;
    final pushChannel = _pushChannel;
    if (token == null ||
        token.isEmpty ||
        deviceType.isEmpty ||
        pushChannel.isEmpty ||
        _isUploadingToken) {
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
    }
  }

  /// 前台保活同步：用于登录后长时间运行，确保服务端 token 状态不漂移。
  Future<void> ensureTokenSynced() async {
    await _maybeRefreshAndroidVendorToken();

    final token = _deviceToken;
    if (token == null || token.isEmpty) {
      return;
    }
    if (_deviceType.isEmpty || _pushChannel.isEmpty) {
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

    await _syncCurrentToken();
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
    try {
      _log(
        '[Push] Uploading token to server (deviceType: $deviceType, channel: $pushChannel)...',
      );
      final api = _ref.read(apiClientProvider);
      final response = await api.post('/user/push-token', data: {
        'push_token': token,
        'device_type': deviceType,
        'push_channel': pushChannel,
      });

      if (response.isSuccess) {
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

  void _handleNotification(String jsonString) {
    try {
      final data = json.decode(jsonString) as Map<String, dynamic>;
      _log('[Push] Notification received: $data');
      onNotificationReceived?.call(data);
    } catch (e) {
      _log('[Push] Failed to parse notification: $e');
    }
  }

  void _handleNotificationTap(String jsonString) {
    try {
      final data = json.decode(jsonString) as Map<String, dynamic>;
      _log('[Push] Notification tapped: $data');
      onNotificationTapped?.call(data);
    } catch (e) {
      _log('[Push] Failed to parse notification tap: $e');
    }
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

  /// 清除 token（登出时调用）
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

    if (_deviceToken != null) {
      try {
        final api = _ref.read(apiClientProvider);
        await api.delete('/user/push-token');
        _log('[Push] Token cleared from server');
      } catch (e) {
        _log('[Push] Failed to clear token: $e');
      }
    }

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
    _isRegistered = false;
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
    _isRegistered = false;
    await register();
  }
}

/// Provider — 推送服务需要在整个应用生命周期内保持活跃
final pushNotificationServiceProvider =
    Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref);
});
