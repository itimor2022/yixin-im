// 文件用途：实现 Android、iOS 和桌面端的应用启动与原生服务初始化。
// 核心逻辑：实现 bootstrap 的原生平台分支，封装系统权限或文件能力，并保持跨平台调用契约一致。
import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import '../app.dart';
import '../core/services/android_callkit_helper.dart';
import '../core/services/android_message_notification_service.dart';
import '../core/services/background_keep_alive_policy.dart';
import '../core/services/desktop/hotkey_service.dart';
import '../core/services/desktop/tray_service.dart';
import '../core/services/desktop/window_service.dart';
import '../core/services/image_picker_diagnostics_service.dart';
import '../core/services/desktop_notification_service.dart';
import '../core/services/notification_sound_service.dart';
import '../core/services/offline_message_queue.dart';
import '../core/services/performance_trace_service.dart';
import '../core/services/storage/isar_service.dart';
import '../core/services/storage/models/chat_model.dart';
import '../core/services/storage/models/message_model.dart';
import '../core/services/storage/models/user_model.dart';
import '../core/utils/platform_utils.dart';

// 关键声明：bootstrap native 是原生平台实现，集中处理系统权限、文件或窗口能力，避免业务层散落平台判断。
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  // 该回调可能运行在独立 isolate 中，不能依赖主 isolate 的 Provider、Isar 实例或 UI 状态。
  _configureReleaseLogging();
  if (kDebugMode) {
    debugPrint(
      '[FCM] Background message: ${message.messageId}, type: ${message.data['type']}',
    );
  }
  try {
    await Firebase.initializeApp();
    final data = <String, dynamic>{...message.data};
    final notification = message.notification;
    if (notification != null) {
      data['title'] = data['title'] ?? notification.title ?? '';
      data['body'] = data['body'] ?? notification.body ?? '';
    }
    final revokedChatId = revokedMessageNotificationChatId(data);
    if (revokedChatId != null) {
      await AndroidMessageNotificationService.instance
          .cancelMessageNotification(
        chatId: revokedChatId,
        messageId: data['msg_id']?.toString(),
      );
      return;
    }
    if (data['type'] == 'incoming_call') {
      await showAndroidIncomingCallFromPayload(
        data,
        notificationMasterEnabled: readAndroidNotificationMasterMirror,
      );
      return;
    }
    if (isFcmBackgroundVisibleNotificationPayload(data)) {
      final type = data['type']?.toString().trim();
      final isAnnouncement = isAnnouncementNotificationType(type);
      final isMeeting = isMeetingNotificationType(type);
      await AndroidMessageNotificationService.instance.showMessageNotification(
        chatId: isMeeting
            ? data['meeting_id']?.toString() ?? ''
            : data['chat_id']?.toString() ?? '',
        messageId: (data['message_id'] ?? data['msg_id'])?.toString(),
        title: data['title']?.toString() ?? '新消息',
        body: data['body']?.toString() ?? '您收到一条新消息',
        unreadCount: int.tryParse(data['unread_count']?.toString() ?? ''),
        enforceMasterSwitch: true,
        tapData: data,
        notificationId: int.tryParse(data['notification_id']?.toString() ?? ''),
        channelId: isMeeting
            ? AndroidMessageNotificationService.meetingChannelId
            : isAnnouncement
                ? AndroidMessageNotificationService.announcementChannelId
                : AndroidMessageNotificationService.messageChannelId,
        channelName: isMeeting
            ? AndroidMessageNotificationService.meetingChannelName
            : isAnnouncement
                ? AndroidMessageNotificationService.announcementChannelName
                : AndroidMessageNotificationService.messageChannelName,
        channelDescription: isMeeting
            ? AndroidMessageNotificationService.meetingChannelDescription
            : isAnnouncement
                ? AndroidMessageNotificationService
                    .announcementChannelDescription
                : AndroidMessageNotificationService.messageChannelDescription,
        category: isMeeting
            ? AndroidNotificationCategory.event
            : AndroidNotificationCategory.message,
      );
    }
  } catch (e) {
    debugPrint('[FCM] Background incoming call handling failed: $e');
  }
}

Isar? _isar;

void _configureReleaseLogging() {
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
}

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

Future<void> _initializeFirebaseMessaging() async {
  if (!Platform.isAndroid) return;
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
    PerformanceTraceService.mark('firebase_messaging_ready');
  } catch (e) {
    debugPrint('[Main] Firebase init error: $e');
  }
}

Future<void> _runDeferredNativeStartupTasks() async {
  // 通知、托盘和保活均不影响首屏可用性，统一延后并彼此隔离失败，避免拖慢启动。
  PerformanceTraceService.mark('deferred_native_start');

  if (Platform.isAndroid) {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        return ImagePickerDiagnosticsService.instance
            .retrieveLostDataOnStartup();
      }).catchError((Object error) {
        debugPrint('[Main] Image picker lost data recovery error: $error');
      }),
    );
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 1800), () {
        return AndroidMessageNotificationService.instance.initialize();
      }).catchError((Object error) {
        debugPrint('[Main] Android message notification init error: $error');
      }),
    );
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 4500), () {
        return _initializeFirebaseMessaging();
      }),
    );
  }

  if (PlatformUtils.isPhysicalDesktop) {
    unawaited(
      DesktopNotificationService().initialize().catchError((Object error) {
        debugPrint('[Main] DesktopNotification init error: $error');
      }),
    );
    unawaited(
      TrayService.instance.initialize().catchError((Object error) {
        debugPrint('[Main] TrayService init error: $error');
      }),
    );
    unawaited(
      HotkeyService.instance.initialize().catchError((Object error) {
        debugPrint('[Main] HotkeyService init error: $error');
      }),
    );
  }

  unawaited(
    Future<void>.delayed(const Duration(milliseconds: 3500), () {
      OfflineMessageQueue().initialize();
    }),
  );

  if (PlatformUtils.supportsBackgroundService) {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 5000), () {
        BackgroundKeepAlivePolicyStore.instance.load();
      }),
    );
  }
}

// 流程逻辑：`bootstrapApp` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
Future<void> bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  _configureReleaseLogging();
  PerformanceTraceService.mark('native_bootstrap_start');

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('[Uncaught] $error\n$stack');
    return true;
  };

  try {
    // 本地数据库是原生端聊天缓存的权威持久层，必须在 Provider 树创建前完成注入。
    final isarSpan = PerformanceTraceService.start('isar_open');
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
    isarSpan.finish();
  } catch (e) {
    PerformanceTraceService.mark('isar_open_failed:$e');
    debugPrint('[Main] Isar initialization failed: $e, attempting cleanup...');
    try {
      // 首次打开失败通常来自异常退出遗留的锁或损坏缓存；缓存可重建，因此清理后仅重试一次。
      final retrySpan = PerformanceTraceService.start('isar_open_retry');
      final dir = await getApplicationDocumentsDirectory();
      await _deleteIsarFiles(dir.path);
      _isar = await Isar.open(
        [MessageModelSchema, ChatModelSchema, UserModelSchema],
        directory: dir.path,
      );
      IsarService.instance.setIsar(_isar!);
      retrySpan.finish();
      debugPrint('[Main] Isar reopened after cleanup');
    } catch (retryError) {
      PerformanceTraceService.mark('isar_open_retry_failed:$retryError');
      debugPrint('[Main] Isar retry also failed: $retryError');
    }
  }

  if (PlatformUtils.isPhysicalDesktop) {
    try {
      // 窗口尺寸和单实例行为需在 runApp 前就绪，否则首帧可能以错误窗口状态闪现。
      await WindowService.instance.initialize();
    } catch (e) {
      debugPrint('[Main] WindowService init error: $e');
    }
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

  final container = ProviderContainer();
  GlobalHaptics.init(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GenericIMApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    // 首帧完成后再启动非关键服务，确保冷启动耗时不被后台能力初始化放大。
    PerformanceTraceService.mark('first_frame_native');
    unawaited(_runDeferredNativeStartupTasks());
  });
}
