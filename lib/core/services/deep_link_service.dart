// 文件用途：封装 DeepLinkService 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 DeepLinkService 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:universal_io/io.dart';

import '../utils/qr_payload.dart';

String? appRouteFromExternalLink(String? rawValue) {
  final raw = rawValue?.trim() ?? '';
  final uri = Uri.tryParse(raw);
  final payload = parseOneChatQrPayload(raw);
  if (uri == null || payload == null || payload.type != OneChatQrType.user) {
    return null;
  }

  final query = <String, String>{};
  // name/avatar 仅用于目标页的首屏展示，用户身份仍由 payload.id 和服务端资料确认。
  for (final key in const ['name', 'avatar']) {
    final value = uri.queryParameters[key]?.trim() ?? '';
    if (value.isNotEmpty) query[key] = value;
  }

  final path = '/user/${Uri.encodeComponent(payload.id)}';
  if (query.isEmpty) return path;
  return '$path?${Uri(queryParameters: query).query}';
}

// 关键声明：deep link service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
class DeepLinkService {
  DeepLinkService._();

  static final DeepLinkService instance = DeepLinkService._();
  static const MethodChannel _channel = MethodChannel('com.genericim/deep_link');

  final StreamController<String> _links = StreamController<String>.broadcast();
  List<String> _launchArguments = const [];
  bool _initialized = false;

  Stream<String> get links => _links.stream;

  void setLaunchArguments(List<String> arguments) {
    _launchArguments = List<String>.unmodifiable(arguments);
  }

  Future<void> initialize() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;

    // 运行中链接由原生通道推送；冷启动链接按平台从启动参数或原生缓存读取。
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        _emit(call.arguments?.toString());
      }
    });

    if (Platform.isWindows) {
      for (final argument in _launchArguments) {
        if (appRouteFromExternalLink(argument) != null) {
          _emit(argument);
          break;
        }
      }
      return;
    }

    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final initial = await _channel.invokeMethod<String>('getInitialLink');
      _emit(initial);
    } on MissingPluginException {
      debugPrint('[DeepLink] Native channel is not registered');
    } catch (error) {
      debugPrint('[DeepLink] Initial link error: $error');
    }
  }

  void _emit(String? rawValue) {
    final value = rawValue?.trim() ?? '';
    // 所有入口共用同一解析器，只向路由层暴露已识别的应用内用户链接。
    if (value.isEmpty || appRouteFromExternalLink(value) == null) return;
    _links.add(value);
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  Future<void> dispose() async {
    if (!_initialized) return;
    _initialized = false;
    if (!kIsWeb) {
      _channel.setMethodCallHandler(null);
    }
  }
}
