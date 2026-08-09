// 文件用途：封装 BackgroundService 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 BackgroundService 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:universal_io/io.dart';

import '../i18n/app_localizations.dart';
import 'api/system_settings_service.dart';
import 'background_keep_alive_policy.dart';

String _backgroundServiceText({
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

// 关键声明：background service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
class BackgroundService {
  static final BackgroundService _instance = BackgroundService._();
  static BackgroundService get instance => _instance;
  BackgroundService._();

  final FlutterBackgroundService _service = FlutterBackgroundService();
  String _appDisplayName = defaultAppDisplayName();
  Timer? _watchdogTimer;
  StreamSubscription<Map<String, dynamic>?>? _keepAliveSubscription;
  final Set<FutureOr<void> Function()> _keepAliveHandlers = {};
  String? _lastMessageTitle;
  String? _lastMessageContent;
  int _lastUnreadCount = 0;
  BackgroundKeepAliveMode _keepAliveMode = BackgroundKeepAliveMode.balanced;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  // 流程逻辑：`initialize` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  Future<void> initialize() async {
    if (!Platform.isAndroid) return;

    // 后台 isolate 启动时未必能访问在线配置，先用本地缓存恢复通知标题。
    final cachedSettings = await loadCachedSystemSettings();
    if (cachedSettings != null) {
      _appDisplayName = cachedSettings.displayName;
    }
    _keepAliveMode = await BackgroundKeepAlivePolicyStore.instance.load();

    try {
      await _service.configure(
        androidConfiguration: AndroidConfiguration(
          onStart: _onStart,
          autoStart: true,
          autoStartOnBoot: false,
          isForegroundMode: true,
          // Android 前台服务必须持续展示系统通知；它不是普通消息通知。
          notificationChannelId: 'genericim_background',
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
      applyPolicy(_keepAliveMode);
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

      // 复制快照，避免回调执行期间增删监听器破坏本轮遍历。
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

    _watchdogTimer = Timer.periodic(
        BackgroundKeepAlivePolicy.profileFor(_keepAliveMode).watchdogInterval,
        (_) async {
      await ensureRunning(reason: 'watchdog');
    });
  }

  void applyPolicy(BackgroundKeepAliveMode mode) {
    if (!Platform.isAndroid) return;
    _keepAliveMode = mode;
    if (_watchdogTimer != null) {
      _watchdogTimer?.cancel();
      _watchdogTimer = null;
      startWatchdog();
    }
    final profile = BackgroundKeepAlivePolicy.profileFor(mode);
    // 主 isolate 和后台 isolate 不共享内存，运行中的服务需通过事件显式接收新策略。
    _service.invoke('configurePolicy', {
      'mode': BackgroundKeepAlivePolicy.serialize(mode),
      'heartbeat_ms': profile.serviceHeartbeatInterval.inMilliseconds,
    });
    updateNotification(unreadCount: _lastUnreadCount);
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
          enhanced: _keepAliveMode == BackgroundKeepAliveMode.enhanced,
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

String _notificationContent(
  int unreadCount, {
  String? latestMessageContent,
  bool enhanced = false,
}) {
  if (unreadCount > 0 &&
      latestMessageContent != null &&
      latestMessageContent.trim().isNotEmpty) {
    return latestMessageContent;
  }
  if (unreadCount > 0) {
    final label = unreadCount > 99 ? '99+' : unreadCount.toString();
    return _backgroundServiceText(
      zhCN: '$label 条未读消息，后台消息服务运行中。',
      zhTW: '$label 則未讀消息，背景消息服務運行中。',
      en: '$label unread messages. Background message service is running.',
    );
  }
  if (enhanced) {
    return _backgroundServiceText(
      zhCN: '增强保活运行中，可能增加耗电。',
      zhTW: '增強保活運行中，可能增加耗電。',
      en: 'Enhanced keep-alive is running and may use more battery.',
    );
  }
  return _backgroundServiceText(
    zhCN: '后台消息服务运行中。',
    zhTW: '背景消息服務運行中。',
    en: 'Background message service is running.',
  );
}

@pragma('vm:entry-point')
Future<void> _onStart(ServiceInstance service) async {
  // 此入口运行在独立后台 isolate，只能通过 service 事件与主 isolate 通信。
  Timer? heartbeatTimer;
  var heartbeatInterval =
      BackgroundKeepAlivePolicy.profileFor(BackgroundKeepAliveMode.balanced)
          .serviceHeartbeatInterval;

  void startHeartbeatTimer() {
    heartbeatTimer?.cancel();
    heartbeatTimer = Timer.periodic(heartbeatInterval, (_) async {
      try {
        if (service is AndroidServiceInstance &&
            await service.isForegroundService()) {
          service.invoke('keepAlive', {
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'interval_ms': heartbeatInterval.inMilliseconds,
          });
          debugPrint(
            '[BackgroundService] heartbeat ${heartbeatInterval.inSeconds}s',
          );
        }
      } catch (_) {}
    });
  }

  startHeartbeatTimer();

  void applyServicePolicy(Map<String, dynamic>? event) {
    if (event == null) return;
    final heartbeatMs = (event['heartbeat_ms'] as num?)?.toInt();
    if (heartbeatMs != null && heartbeatMs > 0) {
      heartbeatInterval = Duration(milliseconds: heartbeatMs);
      startHeartbeatTimer();
    }
  }

  service.on('configurePolicy').listen((event) {
    try {
      applyServicePolicy(event);
    } catch (e) {
      debugPrint('[BackgroundService] configure policy error: $e');
    }
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
          title: (event['title'] ?? defaultAppDisplayName()).toString(),
          content: (event['content'] ?? _notificationContent(0)).toString(),
        );
      } catch (e) {
        debugPrint('[BackgroundService] update notification error: $e');
      }
    });

    try {
      await service.setAsForegroundService();
      service.setForegroundNotificationInfo(
        title: defaultAppDisplayName(),
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
