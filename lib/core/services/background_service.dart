import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:universal_io/io.dart';

import 'api/system_settings_service.dart';

class BackgroundService {
  static final BackgroundService _instance = BackgroundService._();
  static BackgroundService get instance => _instance;
  BackgroundService._();

  final FlutterBackgroundService _service = FlutterBackgroundService();
  String _appDisplayName = kDefaultAppDisplayName;
  Timer? _watchdogTimer;
  StreamSubscription<Map<String, dynamic>?>? _keepAliveSubscription;
  final Set<FutureOr<void> Function()> _keepAliveHandlers = {};
  String? _lastMessageTitle;
  String? _lastMessageContent;
  int _lastUnreadCount = 0;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;

    final cachedSettings = await loadCachedSystemSettings();
    if (cachedSettings != null) {
      _appDisplayName = cachedSettings.displayName;
    }

    try {
      await _service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onStart,
          autoStart: true,
          autoStartOnBoot: true,
          isForegroundMode: true,
          notificationChannelId: 'gaoranim_background',
          initialNotificationTitle: _appDisplayName,
          initialNotificationContent: _notificationContent(_lastUnreadCount),
          foregroundServiceNotificationId: 888,
        ),
        iosConfiguration: IosConfiguration(
          autoStart: false,
          onForeground: _onStart,
          onBackground: _onIosBackground,
        ),
      );
      _isInitialized = true;
      _ensureKeepAliveListener();
      await start();
      startWatchdog();
    } catch (e) {
      debugPrint('[BackgroundService] initialize error: $e');
    }
  }

  VoidCallback addKeepAliveHandler(FutureOr<void> Function() handler) {
    _keepAliveHandlers.add(handler);
    if (Platform.isAndroid && _isInitialized) {
      _ensureKeepAliveListener();
    }
    return () {
      _keepAliveHandlers.remove(handler);
    };
  }

  void _ensureKeepAliveListener() {
    if (!Platform.isAndroid || _keepAliveSubscription != null) return;

    _keepAliveSubscription = _service.on('keepAlive').listen((_) {
      if (_keepAliveHandlers.isEmpty) return;

      final handlers = List<FutureOr<void> Function()>.from(_keepAliveHandlers);
      for (final handler in handlers) {
        try {
          final result = handler();
          if (result is Future<void>) {
            unawaited(result);
          }
        } catch (e) {
          debugPrint('[BackgroundService] keepAlive handler error: $e');
        }
      }
    });
  }

  void startWatchdog() {
    if (!Platform.isAndroid || !_isInitialized || _watchdogTimer != null) {
      return;
    }

    _watchdogTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      await ensureRunning(reason: 'watchdog');
    });
  }

  Future<void> ensureRunning({String reason = 'manual'}) async {
    if (!Platform.isAndroid) return;
    if (!_isInitialized) {
      await initialize();
      return;
    }

    try {
      final running = await _service.isRunning();
      if (!running) {
        await _service.startService();
        debugPrint('[BackgroundService] restarted by $reason');
      }
      updateNotification(unreadCount: _lastUnreadCount);
    } catch (e) {
      debugPrint('[BackgroundService] ensureRunning error: $e');
    }
  }

  Future<void> start() async {
    if (!Platform.isAndroid) return;
    if (!_isInitialized) {
      debugPrint('[BackgroundService] start ignored: not initialized');
      return;
    }

    try {
      final running = await _service.isRunning();
      if (!running) {
        await _service.startService();
        debugPrint('[BackgroundService] service started');
      }
      updateNotification(unreadCount: _lastUnreadCount);
    } catch (e) {
      debugPrint('[BackgroundService] start error: $e');
    }
  }

  Future<void> stop() async {
    if (!Platform.isAndroid) return;

    _watchdogTimer?.cancel();
    _watchdogTimer = null;

    final running = await _service.isRunning();
    if (running) {
      _service.invoke('stop');
      debugPrint('[BackgroundService] service stopped');
    }
  }

  Future<bool> isRunning() async {
    if (!Platform.isAndroid) return false;
    return _service.isRunning();
  }

  void updateNotification({
    String? title,
    String? content,
    int? unreadCount,
    bool rememberMessage = false,
  }) {
    if (!Platform.isAndroid) return;

    if (unreadCount != null) {
      _lastUnreadCount = unreadCount < 0 ? 0 : unreadCount;
      if (_lastUnreadCount == 0) {
        _lastMessageTitle = null;
        _lastMessageContent = null;
      }
    }

    if (rememberMessage) {
      _lastMessageTitle = title;
      _lastMessageContent = content;
    }

    final notificationTitle = title ??
        (_lastUnreadCount > 0 && _lastMessageTitle != null
            ? _lastMessageTitle!
            : _appDisplayName);
    final notificationContent = content ??
        _notificationContent(
          _lastUnreadCount,
          latestMessageContent: _lastMessageContent,
        );

    _service.invoke('update', {
      'title': notificationTitle,
      'content': notificationContent,
    });
  }

  void updateLatestMessage({
    required String title,
    required String content,
    int? unreadCount,
  }) {
    updateNotification(
      title: title,
      content: content,
      unreadCount: unreadCount,
      rememberMessage: true,
    );
  }
}

String _notificationContent(int unreadCount, {String? latestMessageContent}) {
  if (unreadCount > 0 &&
      latestMessageContent != null &&
      latestMessageContent.trim().isNotEmpty) {
    return latestMessageContent;
  }
  if (unreadCount > 0) {
    final label = unreadCount > 99 ? '99+' : unreadCount.toString();
    return '$label 条未读消息，后台消息服务运行中。';
  }
  return '后台消息服务运行中，正在保持消息连接。';
}

@pragma('vm:entry-point')
Future<void> _onStart(ServiceInstance service) async {
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (e) {
    debugPrint('[BackgroundService] plugin init warning: $e');
  }

  Timer? heartbeatTimer;
  heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
    try {
      if (service is AndroidServiceInstance &&
          await service.isForegroundService()) {
        service.invoke('keepAlive', {
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        debugPrint('[BackgroundService] heartbeat');
      }
    } catch (_) {}
  });

  if (service is AndroidServiceInstance) {
    service.on('stop').listen((_) {
      heartbeatTimer?.cancel();
      service.stopSelf();
    });

    service.on('update').listen((event) {
      if (event == null) return;
      try {
        service.setForegroundNotificationInfo(
          title: (event['title'] ?? kDefaultAppDisplayName).toString(),
          content: (event['content'] ?? _notificationContent(0)).toString(),
        );
      } catch (e) {
        debugPrint('[BackgroundService] update notification error: $e');
      }
    });

    try {
      await service.setAsForegroundService();
      service.setForegroundNotificationInfo(
        title: kDefaultAppDisplayName,
        content: _notificationContent(0),
      );
      service.invoke('keepAlive', {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (e) {
      debugPrint('[BackgroundService] set foreground error: $e');
    }
  }
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
  } catch (e) {
    debugPrint('[BackgroundService] iOS background init warning: $e');
  }
  return true;
}
