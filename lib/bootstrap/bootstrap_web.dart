// 文件用途：实现 Web 端的应用启动、浏览器环境初始化与兼容处理。
// 核心逻辑：实现 bootstrap 的 Web 平台分支，适配浏览器 API 和资源生命周期，并保持与原生实现相同的调用契约。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/services/notification_sound_service.dart';
import '../core/services/offline_message_queue.dart';
import '../core/services/performance_trace_service.dart';

// 关键声明：bootstrap web 是 Web 平台实现，负责把浏览器资源和异步生命周期适配为跨平台接口。
void _configureReleaseLogging() {
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
}

// 流程逻辑：`bootstrapApp` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
Future<void> bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  _configureReleaseLogging();
  PerformanceTraceService.mark('web_bootstrap_start');

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    debugPrint('[Uncaught] $error\n$stack');
    return true;
  };
  BrowserContextMenu.disableContextMenu();

  final container = ProviderContainer();
  // 手工创建并托管唯一容器，让全局触感等非 Widget 服务与页面共享同一 Provider 状态。
  GlobalHaptics.init(container);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const GenericIMApp(),
    ),
  );

  WidgetsBinding.instance.addPostFrameCallback((_) {
    // Web 没有原生 Isar 启动门槛，离线队列仍延后到首帧之后恢复，避免阻塞页面渲染。
    PerformanceTraceService.mark('first_frame_web');
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      OfflineMessageQueue().initialize();
    });
  });
}
