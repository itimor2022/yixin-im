import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../core/services/server_discovery.dart';
import '../core/services/notification_sound_service.dart';
import '../core/services/offline_message_queue.dart';

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
  BrowserContextMenu.disableContextMenu();

  // ── Web 端也走 ServerDiscovery（与 native 保持一致） ───────────────────
  //
  // 之前这里是「跳过服务发现，直接用 ApiConfig._defaultServerUrl 硬编码」的写法，
  // 导致运维在 admin 后台改数据库 api_txt_url 后 Web 版毫无响应，只能重新打包才能生效。
  // 现在改成主动去拉 [ServerDiscovery]，行为与 APK 一致：
  //   1. 冷启动从 `_ossUrls` 拉 api.txt（固定源码地址）；
  //   2. 拉到节点列表后依次 ping /api/v1/ping，挑最优活节点写入 ApiConfig。
  //
  // 前置条件（部署侧必须已经就绪，代码这边只负责发起请求）：
  //   - api.txt 所在域名（如 admin.aopwx.icu）的 Nginx 必须为 Web 站点的 origin
  //     配好 Access-Control-Allow-Origin，否则浏览器 CORS 直接拦掉；
  //   - 所有候选 API 节点的 /api/v1/ping 也要放行同样的 origin，否则 probe 全部失败。
  //
  // 失败兜底：任何异常都被吞掉，_serverUrl 保持 ApiConfig._defaultServerUrl（现已改为空串，
  // 不再硬编码任何测试服 URL），后续所有 API/WS 调用都会立刻报错——
  // 这是**故意**的：让"服务发现没跑通"变成显性错误，避免悄悄连错环境。
  //
  // 注意：这里 `await` 会为首屏加大几百毫秒的白屏时间，属于故意的取舍。
  //       如果之后想优化，可以把整个 ServerDiscovery 挪到 runApp 之后异步启动，
  //       但要在 ApiClient 处理 401/连接失败时能感知到 currentNode 变化。
  try {
    await ServerDiscovery.instance.initialize();
  } catch (e) {
    if (kDebugMode)
      debugPrint(
          '[Bootstrap] Web ServerDiscovery failed, using compile-time fallback: $e');
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
}
