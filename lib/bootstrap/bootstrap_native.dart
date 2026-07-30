import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../app.dart';
import '../core/services/ip_tolerant_http_overrides.dart';
import '../core/services/server_discovery.dart';
import '../core/services/background_service.dart';
import '../core/services/desktop/hotkey_service.dart';
import '../core/services/desktop/tray_service.dart';
import '../core/services/desktop/window_service.dart';
import '../core/services/desktop_notification_service.dart';
import '../core/services/notification_sound_service.dart';
import '../core/services/offline_message_queue.dart';
import '../core/services/storage/isar_service.dart';
import '../core/services/storage/models/chat_model.dart';
import '../core/services/storage/models/message_model.dart';
import '../core/services/storage/models/user_model.dart';
import '../core/utils/platform_utils.dart';

@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  if (kDebugMode)
    debugPrint(
      '[FCM] Background message: ${message.messageId}, type: ${message.data['type']}',
    );
}

Isar? _isar;

Future<void> _cleanStaleIsarLock(String dirPath) async {
  try {
    final dir = Directory(dirPath);
    final files = dir.listSync();
    for (final f in files) {
      if (f is File && f.path.contains('.lock')) {
        try { await f.delete(); } catch (_) {}
      }
    }
  } catch (_) {}
}

Future<void> _deleteIsarFiles(String dirPath) async {
  try {
    final dir = Directory(dirPath);
    final files = dir.listSync();
    for (final f in files) {
      if (f is File && f.path.contains('isar')) {
        try { await f.delete(); } catch (_) {}
      }
    }
  } catch (_) {}
}

Future<void> bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ★ 立即 runApp，不做任何 await，确保第一帧马上渲染
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: _BootstrapLoadingPage(),
    ),
  );

  // ★ 所有初始化放到下一个事件循环，不阻塞渲染
  Future<void>.microtask(() async {
    await _initializeApp();
  });
}

Future<void> _initializeApp() async {
  // ⚠️ 必须在 ServerDiscovery / Firebase / 任何 HTTP-WebSocket 客户端构造之前设置。
  //   HttpOverrides.global 是通过拦截 `HttpClient()` 构造函数生效的，
  //   一旦下游 (Dio 的 IOHttpClientAdapter、WebSocket.connect) 已经拿到 client
  //   实例再改就没用了。native-only；web bootstrap 不装（dart:io 是 stub）。
  //   作用：允许 `https://IPv4` 线路在 APK/iOS 上绕开 TLS 证书校验，
  //   域名线路仍走系统 CA 严格校验，见 ip_tolerant_http_overrides.dart。
  HttpOverrides.global = IpTolerantHttpOverrides();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (kDebugMode) debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    if (kDebugMode) debugPrint('[Uncaught] $error\n$stack');
    return true;
  };

  if (PlatformUtils.isMobile) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // ★ Isar 本地数据库优先初始化
  try {
    final dir = await getApplicationDocumentsDirectory();
    // 先尝试关闭已有实例
    try {
      final existing = Isar.getInstance();
      if (existing != null) await existing.close();
    } catch (_) {}
    await _cleanStaleIsarLock(dir.path);
    _isar = await Isar.open(
      [MessageModelSchema, ChatModelSchema, UserModelSchema],
      directory: dir.path,
      inspector: false,
    ).timeout(const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('Isar timed out'));
    IsarService.instance.setIsar(_isar!);
    if (kDebugMode) debugPrint('[Main] Isar ready');
  } catch (e) {
    if (kDebugMode) debugPrint('[Main] Isar failed: $e, cleanup...');
    try {
      // 强制关闭并删除所有 isar 文件
      try {
        final existing = Isar.getInstance();
        if (existing != null) await existing.close(deleteFromDisk: true);
      } catch (_) {}
      final dir = await getApplicationDocumentsDirectory();
      await _deleteIsarFiles(dir.path);
      _isar = await Isar.open(
        [MessageModelSchema, ChatModelSchema, UserModelSchema],
        directory: dir.path,
        inspector: false,
      );
      IsarService.instance.setIsar(_isar!);
      if (kDebugMode) debugPrint('[Main] Isar reopened after cleanup');
    } catch (retryError) {
      if (kDebugMode) debugPrint('[Main] Isar retry failed: $retryError');
    }
  }

  // ★ ServerDiscovery 后台异步跑，不阻塞 UI
  ServerDiscovery.instance.initialize().catchError((e) {
    if (kDebugMode) debugPrint('[Main] ServerDiscovery error: $e');
  });

  // ★ Isar 就绪后启动 GaoRanIMApp，立刻读缓存渲染列表
  final container = ProviderContainer();
  GlobalHaptics.init(container);

  try {
    runApp(
      UncontrolledProviderScope(
        container: container,
        child: const GaoRanIMApp(),
      ),
    );
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('[Bootstrap] runApp failed: $e');
      FlutterError.dumpErrorToConsole(
        FlutterErrorDetails(exception: e, stack: st),
      );
    }
  }

  // ★ Firebase 和其他后台服务继续异步，不阻塞 UI
  Future<void>.microtask(() async {
    if (Platform.isAndroid) {
      try {
        await Firebase.initializeApp().timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw TimeoutException('Firebase init timed out'),
        );
        FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
      } catch (e) {
        if (kDebugMode) debugPrint('[Main] Firebase init error: $e');
      }
    }

    if (PlatformUtils.isPhysicalDesktop) {
      try {
        await WindowService.instance.initialize();
      } catch (e) {
        if (kDebugMode) debugPrint('[Main] WindowService init error: $e');
      }
      try {
        await DesktopNotificationService().initialize();
      } catch (e) {
        if (kDebugMode) debugPrint('[Main] DesktopNotification init error: $e');
      }

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await TrayService.instance.initialize();
        await HotkeyService.instance.initialize();
      });
    }

    Future<void>.delayed(const Duration(milliseconds: 500), () {
      OfflineMessageQueue().initialize();
    });

    if (PlatformUtils.supportsBackgroundService) {
      Future<void>.delayed(const Duration(milliseconds: 1000), () {
        BackgroundService.instance.initialize();
      });
    }
  });
}

class _BootstrapLoadingPage extends StatelessWidget {
  const _BootstrapLoadingPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Colors.blue,
            ),
            const SizedBox(height: 20),
            const Text(
              '潮商会',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  Colors.blue.shade400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
