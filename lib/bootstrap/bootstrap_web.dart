import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/services/notification_sound_service.dart';
import '../core/services/offline_message_queue.dart';

Future<void> bootstrapApp() async {
  WidgetsFlutterBinding.ensureInitialized();

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
}
