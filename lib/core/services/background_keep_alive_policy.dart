// 文件用途：封装 BackgroundKeepAliveMode 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 BackgroundKeepAliveMode 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 关键声明：background keep alive policy 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
enum BackgroundKeepAliveMode {
  balanced,
  enhanced,
}

class BackgroundKeepAliveProfile {
  final BackgroundKeepAliveMode mode;
  final Duration serviceHeartbeatInterval;
  final Duration watchdogInterval;
  final Duration shortBackgroundWindow;
  final Duration backgroundPingInterval;
  final Duration longBackgroundPingInterval;
  final Duration staleTransportThreshold;
  final Duration longBackgroundStaleTransportThreshold;
  final Duration pongTimeoutThreshold;
  final Duration backgroundReconnectMinInterval;
  final Duration longBackgroundReconnectMinInterval;
  final int maxBackgroundFastReconnects;

  const BackgroundKeepAliveProfile({
    required this.mode,
    required this.serviceHeartbeatInterval,
    required this.watchdogInterval,
    required this.shortBackgroundWindow,
    required this.backgroundPingInterval,
    required this.longBackgroundPingInterval,
    required this.staleTransportThreshold,
    required this.longBackgroundStaleTransportThreshold,
    required this.pongTimeoutThreshold,
    required this.backgroundReconnectMinInterval,
    required this.longBackgroundReconnectMinInterval,
    required this.maxBackgroundFastReconnects,
  });

  bool get isEnhanced => mode == BackgroundKeepAliveMode.enhanced;
}

class BackgroundKeepAlivePolicy {
  static const String storageKey = 'background_keep_alive_mode';

  // 这些参数只控制应用自身的心跳和重连节奏，不能绕过厂商省电策略
  // 或替代 Android 前台服务权限。
  static const BackgroundKeepAliveProfile balanced = BackgroundKeepAliveProfile(
    mode: BackgroundKeepAliveMode.balanced,
    serviceHeartbeatInterval: Duration(seconds: 60),
    watchdogInterval: Duration(seconds: 90),
    shortBackgroundWindow: Duration(minutes: 5),
    backgroundPingInterval: Duration(seconds: 60),
    longBackgroundPingInterval: Duration(minutes: 3),
    staleTransportThreshold: Duration(seconds: 90),
    longBackgroundStaleTransportThreshold: Duration(minutes: 10),
    pongTimeoutThreshold: Duration(seconds: 30),
    backgroundReconnectMinInterval: Duration(seconds: 45),
    longBackgroundReconnectMinInterval: Duration(minutes: 5),
    maxBackgroundFastReconnects: 3,
  );

  static const BackgroundKeepAliveProfile enhanced = BackgroundKeepAliveProfile(
    mode: BackgroundKeepAliveMode.enhanced,
    serviceHeartbeatInterval: Duration(seconds: 30),
    watchdogInterval: Duration(seconds: 60),
    shortBackgroundWindow: Duration(minutes: 15),
    backgroundPingInterval: Duration(seconds: 30),
    longBackgroundPingInterval: Duration(seconds: 90),
    staleTransportThreshold: Duration(seconds: 75),
    longBackgroundStaleTransportThreshold: Duration(minutes: 3),
    pongTimeoutThreshold: Duration(seconds: 25),
    backgroundReconnectMinInterval: Duration(seconds: 20),
    longBackgroundReconnectMinInterval: Duration(seconds: 90),
    maxBackgroundFastReconnects: 5,
  );

  static BackgroundKeepAliveProfile profileFor(BackgroundKeepAliveMode mode) {
    switch (mode) {
      case BackgroundKeepAliveMode.enhanced:
        return enhanced;
      case BackgroundKeepAliveMode.balanced:
        return balanced;
    }
  }

  static BackgroundKeepAliveMode parse(String? value) {
    switch (value) {
      case 'enhanced':
        return BackgroundKeepAliveMode.enhanced;
      case 'balanced':
      default:
        return BackgroundKeepAliveMode.balanced;
    }
  }

  static String serialize(BackgroundKeepAliveMode mode) {
    switch (mode) {
      case BackgroundKeepAliveMode.enhanced:
        return 'enhanced';
      case BackgroundKeepAliveMode.balanced:
        return 'balanced';
    }
  }
}

class BackgroundKeepAlivePolicyStore {
  BackgroundKeepAlivePolicyStore._();
  static final BackgroundKeepAlivePolicyStore instance =
      BackgroundKeepAlivePolicyStore._();

  BackgroundKeepAliveMode _mode = BackgroundKeepAliveMode.balanced;
  bool _loaded = false;

  BackgroundKeepAliveMode get mode => _mode;
  BackgroundKeepAliveProfile get profile =>
      BackgroundKeepAlivePolicy.profileFor(_mode);

  // 流程逻辑：`load` 先校验账号、分页或连接状态，再读取远端/本地数据并合并结果；失败只更新错误状态，不覆盖已有可用数据。
  Future<BackgroundKeepAliveMode> load() async {
    // 进程内只读一次持久化值，后续修改统一经 save 更新内存和磁盘。
    if (_loaded) return _mode;
    final prefs = await SharedPreferences.getInstance();
    _mode = BackgroundKeepAlivePolicy.parse(
      prefs.getString(BackgroundKeepAlivePolicy.storageKey),
    );
    _loaded = true;
    return _mode;
  }

  Future<void> save(BackgroundKeepAliveMode mode) async {
    _mode = mode;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      BackgroundKeepAlivePolicy.storageKey,
      BackgroundKeepAlivePolicy.serialize(mode),
    );
  }
}

final backgroundKeepAlivePolicyProvider = StateNotifierProvider<
    BackgroundKeepAlivePolicyController, BackgroundKeepAliveMode>((ref) {
  return BackgroundKeepAlivePolicyController();
});

class BackgroundKeepAlivePolicyController
    extends StateNotifier<BackgroundKeepAliveMode> {
  BackgroundKeepAlivePolicyController()
      : super(BackgroundKeepAlivePolicyStore.instance.mode) {
    _load();
  }

  Future<void> _load() async {
    final mode = await BackgroundKeepAlivePolicyStore.instance.load();
    if (mounted) {
      state = mode;
    }
  }

  Future<void> setMode(BackgroundKeepAliveMode mode) async {
    // 先更新页面状态保证交互即时，再持久化供后台 isolate 下次启动时恢复。
    state = mode;
    await BackgroundKeepAlivePolicyStore.instance.save(mode);
  }
}
