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
  if (kDebugMode) debugPrint(
    '[FCM] Background message: ${message.messageId}, type: ${message.data['type']}',
  );
}

Isar? _isar;

Future<void> _cleanStaleIsarLock(String dirPath) async {
  try {
    final lockFile = File('$dirPath/default.isar.lock');
    if (await lockFile.exists()) {
      await lockFile.delete();
    }
  } catch (_) {}
}

Future<void> _deleteIsarFiles(String dirPath) async {
  for (final name in ['default.isar', 'default.isar.lock']) {
    try {
      final file = File('$dirPath/$name');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}

Future<void> bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (kDebugMode) debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    if (kDebugMode) debugPrint('[Uncaught] $error\n$stack');
    return true;
  };

  if (Platform.isAndroid) {
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
    } catch (e) {
      if (kDebugMode) debugPrint('[Main] Firebase init error: $e');
    }
  }

  try {
    final dir = await getApplicationDocumentsDirectory();
    await _cleanStaleIsarLock(dir.path);
    _isar = await Isar.open(
      [MessageModelSchema, ChatModelSchema, UserModelSchema],
      directory: dir.path,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw TimeoutException('Isar open timed out after 10s');
      },
    );
    IsarService.instance.setIsar(_isar!);
  } catch (e) {
    if (kDebugMode) debugPrint('[Main] Isar initialization failed: $e, attempting cleanup...');
    try {
      final dir = await getApplicationDocumentsDirectory();
      await _deleteIsarFiles(dir.path);
      _isar = await Isar.open(
        [MessageModelSchema, ChatModelSchema, UserModelSchema],
        directory: dir.path,
      );
      IsarService.instance.setIsar(_isar!);
      if (kDebugMode) debugPrint('[Main] Isar reopened after cleanup');
    } catch (retryError) {
      if (kDebugMode) debugPrint('[Main] Isar retry also failed: $retryError');
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

  // 服务发现：选出最快可用节点，写入 ApiConfig
  try {
    await ServerDiscovery.instance.initialize();
  } catch (e) {
    if (kDebugMode) debugPrint('[Bootstrap] ServerDiscovery failed, using default: \$e');
  }

  final container = ProviderContainer();
  GlobalHaptics.init(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GaoRanIMApp(),
    ),
  );

  Future<void>.delayed(const Duration(milliseconds: 500), () {
    OfflineMessageQueue().initialize();
  });

  if (PlatformUtils.supportsBackgroundService) {
    Future<void>.delayed(const Duration(milliseconds: 1000), () {
      BackgroundService.instance.initialize();
    });
  }
}
