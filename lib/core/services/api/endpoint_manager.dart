// 文件用途：封装 EndpointEntry 对应的后端 API 请求、响应模型与错误处理。
// 核心逻辑：把 EndpointEntry 相关请求集中到 API 层，负责参数编码、响应解析、鉴权错误和分页/游标边界。
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_io/io.dart';

import '../../utils/platform_utils.dart';

// 关键声明：endpoint manager 负责请求参数和响应模型的转换，统一处理鉴权错误、分页边界和服务端字段兼容。
class EndpointEntry {
  final String id;
  final String url;
  final int priority;
  final String healthPath;

  const EndpointEntry({
    required this.id,
    required this.url,
    required this.priority,
    this.healthPath = '',
  });

  // 流程逻辑：`fromJson` 集中处理输入规范化、空值和兼容字段，输出稳定的数据结构，避免调用方重复实现边界判断。
  factory EndpointEntry.fromJson(Map<String, dynamic> json, int index) {
    return EndpointEntry(
      id: (json['id']?.toString().trim().isNotEmpty ?? false)
          ? json['id'].toString().trim()
          : 'endpoint-${index + 1}',
      url: _trimTrailingSlash(json['url']?.toString() ?? ''),
      priority: int.tryParse(json['priority']?.toString() ?? '') ??
          ((index + 1) * 10),
      healthPath: json['health_path']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'priority': priority,
        if (healthPath.isNotEmpty) 'health_path': healthPath,
      };
}

class EndpointStrategy {
  final int connectTimeoutMs;
  final int healthTimeoutMs;
  final int failThreshold;
  final int cooldownSeconds;
  final bool preferLastSuccess;

  const EndpointStrategy({
    this.connectTimeoutMs = 5000,
    this.healthTimeoutMs = 3000,
    this.failThreshold = 1,
    this.cooldownSeconds = 60,
    this.preferLastSuccess = true,
  });

  factory EndpointStrategy.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const EndpointStrategy();
    return EndpointStrategy(
      connectTimeoutMs:
          int.tryParse(json['connect_timeout_ms']?.toString() ?? '') ?? 5000,
      healthTimeoutMs:
          int.tryParse(json['health_timeout_ms']?.toString() ?? '') ?? 3000,
      failThreshold:
          int.tryParse(json['fail_threshold']?.toString() ?? '') ?? 1,
      cooldownSeconds:
          int.tryParse(json['cooldown_seconds']?.toString() ?? '') ?? 60,
      preferLastSuccess: json['prefer_last_success'] != false,
    );
  }

  Map<String, dynamic> toJson() => {
        'connect_timeout_ms': connectTimeoutMs,
        'health_timeout_ms': healthTimeoutMs,
        'fail_threshold': failThreshold,
        'cooldown_seconds': cooldownSeconds,
        'prefer_last_success': preferLastSuccess,
      };
}

class EndpointBootstrapConfig {
  final int version;
  final int ttlSeconds;
  final List<EndpointEntry> apiEndpoints;
  final List<EndpointEntry> wsEndpoints;
  final List<String> mediaBaseUrls;
  final EndpointStrategy strategy;

  const EndpointBootstrapConfig({
    required this.version,
    required this.ttlSeconds,
    required this.apiEndpoints,
    required this.wsEndpoints,
    required this.mediaBaseUrls,
    required this.strategy,
  });

  factory EndpointBootstrapConfig.fallback() {
    return EndpointBootstrapConfig(
      version: 1,
      ttlSeconds: 300,
      apiEndpoints: [
        EndpointEntry(
          id: 'fallback-api',
          url: EndpointManager.fallbackServerUrl,
          priority: 10,
          healthPath: '/api/v1/ping',
        ),
      ],
      wsEndpoints: [
        EndpointEntry(
          id: 'fallback-ws',
          url: EndpointManager.fallbackWsUrl,
          priority: 10,
        ),
      ],
      mediaBaseUrls: [EndpointManager.fallbackServerUrl],
      strategy: const EndpointStrategy(),
    );
  }

  factory EndpointBootstrapConfig.fromJson(Map<String, dynamic> json) {
    final fallback = EndpointBootstrapConfig.fallback();
    final apiEndpoints = _normalizeEndpointsForPlatform(
      _endpointList(json['api_endpoints']),
      fallback.apiEndpoints,
    );
    final wsEndpoints = _normalizeEndpointsForPlatform(
      _endpointList(json['ws_endpoints']),
      fallback.wsEndpoints,
    );
    final mediaBaseUrls = _stringList(json['media_base_urls'])
        .map(_normalizeUrlForPlatform)
        .map(_trimTrailingSlash)
        .where((url) => url.isNotEmpty)
        .toList(growable: false);
    return EndpointBootstrapConfig(
      version: int.tryParse(json['version']?.toString() ?? '') ?? 1,
      ttlSeconds: int.tryParse(json['ttl_seconds']?.toString() ?? '') ?? 300,
      apiEndpoints: _mergeEndpoints(apiEndpoints, fallback.apiEndpoints),
      wsEndpoints: _mergeEndpoints(wsEndpoints, fallback.wsEndpoints),
      mediaBaseUrls:
          mediaBaseUrls.isEmpty ? fallback.mediaBaseUrls : mediaBaseUrls,
      strategy: EndpointStrategy.fromJson(
        json['strategy'] is Map<String, dynamic>
            ? json['strategy'] as Map<String, dynamic>
            : null,
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'ttl_seconds': ttlSeconds,
        'api_endpoints': apiEndpoints.map((e) => e.toJson()).toList(),
        'ws_endpoints': wsEndpoints.map((e) => e.toJson()).toList(),
        'media_base_urls': mediaBaseUrls,
        'strategy': strategy.toJson(),
      };
}

class EndpointManager {
  EndpointManager._();

  static final EndpointManager instance = EndpointManager._();

  static const String _configuredFallbackServerUrl = String.fromEnvironment(
    'GENERIC_IM_SERVER_URL',
    defaultValue: '',
  );
  static const String _configuredFallbackWsUrl = String.fromEnvironment(
    'GENERIC_IM_WS_URL',
    defaultValue: '',
  );
  static const String _androidLoopbackHost = String.fromEnvironment(
    'GENERIC_IM_ANDROID_LOOPBACK_HOST',
    defaultValue: '10.0.2.2',
  );

  static String get fallbackServerUrl {
    final configured = _configuredFallbackServerUrl.trim();
    if (configured.isNotEmpty) return configured;
    return '${_localHttpOrigin()}:8080';
  }

  static String get fallbackWsUrl {
    final configured = _configuredFallbackWsUrl.trim();
    if (configured.isNotEmpty) return configured;
    return '${_localWsOrigin()}:8080/api/v1/ws';
  }

  static String _localHttpOrigin() {
    if (kIsWeb) return 'http://127.0.0.1';
    if (Platform.isAndroid) return 'http://$_androidLoopbackHost';
    return 'http://127.0.0.1';
  }

  static String _localWsOrigin() {
    if (kIsWeb) return 'ws://127.0.0.1';
    if (Platform.isAndroid) return 'ws://$_androidLoopbackHost';
    return 'ws://127.0.0.1';
  }

  static const String bootstrapUrl = String.fromEnvironment(
    'GENERIC_IM_BOOTSTRAP_URL',
    defaultValue: '',
  );
  static const String bootstrapUrls = String.fromEnvironment(
    'GENERIC_IM_BOOTSTRAP_URLS',
    defaultValue: '',
  );

  static const _configKey = 'endpoint_bootstrap_config_local_v2';
  static const _fetchedAtKey = 'endpoint_bootstrap_fetched_at_local_v2';
  static const _lastApiKey = 'endpoint_last_api_url_local_v2';
  static const _lastWsKey = 'endpoint_last_ws_url_local_v2';

  final _changedController = StreamController<void>.broadcast();
  final Map<String, int> _apiFailures = {};
  final Map<String, int> _wsFailures = {};
  final Map<String, DateTime> _cooldowns = {};

  EndpointBootstrapConfig _config = EndpointBootstrapConfig.fallback();
  String _apiServerUrl = fallbackServerUrl;
  String _wsUrl = fallbackWsUrl;
  bool _discoveryApplied = false; // ServerDiscovery 已注入节点，bootstrap 不应覆盖
  bool _initialized = false;
  bool _initializing = false;
  Future<void>? _refreshFuture;

  Stream<void> get onChanged => _changedController.stream;
  String get apiServerUrl => _apiServerUrl;
  String get wsUrl => _wsUrl;
  String get mediaBaseUrl => _config.mediaBaseUrls.first;
  List<String> get mediaBaseUrls => _config.mediaBaseUrls;
  EndpointStrategy get strategy => _config.strategy;

  Future<void> initialize() async {
    if (_initialized || _initializing) return _refreshFuture ?? Future.value();
    _initializing = true;
    _refreshFuture = _initializeInternal();
    try {
      await _refreshFuture;
    } finally {
      _initialized = true;
      _initializing = false;
      _refreshFuture = null;
    }
  }

  void initializeInBackground() {
    unawaited(initialize());
  }
  /// ServerDiscovery 发现节点后调用，将该节点注入为当前活跃端点
  /// 不影响已缓存的 bootstrap 线路表，仅作为启动阶段的初始节点
  void setDiscoveredNode(String apiUrl, {String? wsUrl}) {
    final normalizedApi = _trimTrailingSlash(apiUrl);
    if (normalizedApi.isEmpty) return;
    _apiServerUrl = normalizedApi;
    _wsUrl = wsUrl != null
        ? _trimTrailingSlash(wsUrl)
        : '$normalizedApi/api/v1/ws'.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
    _discoveryApplied = true;
    debugPrint('[EndpointManager] setDiscoveredNode: api=$_apiServerUrl ws=$_wsUrl');
    _notifyChanged();
  }

  Future<void> _initializeInternal() async {
    await _loadCachedConfig();
    await refreshBootstrap();
  }

  Future<void> refreshBootstrap() async {
    final urls = _bootstrapCandidates();
    if (urls.isEmpty) return;

    for (final url in urls) {
      try {
        final dio = Dio(
          BaseOptions(
            connectTimeout: Duration(milliseconds: strategy.connectTimeoutMs),
            receiveTimeout: Duration(milliseconds: strategy.healthTimeoutMs),
            headers: {
              'X-Client-Platform': PlatformUtils.deviceType,
            },
          ),
        );
        final response = await dio.get(url);
        final payload = _extractPayload(response.data);
        if (payload == null) continue;
        _config = EndpointBootstrapConfig.fromJson(payload);
        await _saveConfig();
        await _restoreLastSuccess();
        _ensureCurrentEndpoints();
        _notifyChanged();
        debugPrint('[Endpoint] Bootstrap loaded from $url');
        return;
      } catch (e) {
        debugPrint('[Endpoint] Bootstrap failed $url: $e');
      }
    }
  }

  Future<bool> markApiFailure(String url) async {
    final normalized = _trimTrailingSlash(url);
    final count = (_apiFailures[normalized] ?? 0) + 1;
    _apiFailures[normalized] = count;
    if (count < strategy.failThreshold) return false;
    // Ignore a request that failed after another request already moved the
    // client to a different endpoint.
    if (normalized != _apiServerUrl) return false;
    _markCooldown(normalized);
    final changed = await _switchApiEndpoint(excludeUrl: normalized);
    return changed;
  }

  Future<bool> markWsFailure(String url) async {
    final normalized = _trimTrailingSlash(url);
    final count = (_wsFailures[normalized] ?? 0) + 1;
    _wsFailures[normalized] = count;
    if (count < strategy.failThreshold) return false;
    _markCooldown(normalized);
    final changed = await _switchWsEndpoint(excludeUrl: normalized);
    return changed;
  }

  Future<void> markApiSuccess(String url) async {
    final normalized = _trimTrailingSlash(url);
    _apiFailures.remove(normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastApiKey, normalized);
  }

  Future<void> markWsSuccess(String url) async {
    final normalized = _trimTrailingSlash(url);
    _wsFailures.remove(normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastWsKey, normalized);
  }

  Future<bool> _switchApiEndpoint({required String excludeUrl}) async {
    final next = _chooseNext(_config.apiEndpoints, _apiServerUrl, excludeUrl);
    if (next == null || next.url == _apiServerUrl) return false;
    _apiServerUrl = next.url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastApiKey, next.url);
    _notifyChanged();
    debugPrint('[Endpoint] API switched to ${next.url}');
    return true;
  }

  Future<bool> _switchWsEndpoint({required String excludeUrl}) async {
    final next = _chooseNext(_config.wsEndpoints, _wsUrl, excludeUrl);
    if (next == null || next.url == _wsUrl) return false;
    _wsUrl = next.url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastWsKey, next.url);
    _notifyChanged();
    debugPrint('[Endpoint] WS switched to ${next.url}');
    return true;
  }

  EndpointEntry? _chooseNext(
    List<EndpointEntry> endpoints,
    String current,
    String exclude,
  ) {
    final now = DateTime.now();
    final sorted = [...endpoints]..sort((a, b) => a.priority - b.priority);
    for (final endpoint in sorted) {
      if (endpoint.url == current || endpoint.url == exclude) continue;
      final until = _cooldowns[endpoint.url];
      if (until != null && until.isAfter(now)) continue;
      return endpoint;
    }
    for (final endpoint in sorted) {
      if (endpoint.url != exclude) return endpoint;
    }
    return null;
  }

  void _markCooldown(String url) {
    _cooldowns[url] = DateTime.now().add(
      Duration(seconds: strategy.cooldownSeconds),
    );
  }

  Future<void> _loadCachedConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_configKey);
      if (raw != null && raw.isNotEmpty) {
        final parsed = jsonDecode(raw);
        if (parsed is Map<String, dynamic>) {
          _config = EndpointBootstrapConfig.fromJson(parsed);
        }
      }
      await _restoreLastSuccess();
      _ensureCurrentEndpoints();
      _notifyChanged();
    } catch (e) {
      debugPrint('[Endpoint] Load cache failed: $e');
    }
  }

  Future<void> _restoreLastSuccess() async {
    final prefs = await SharedPreferences.getInstance();
    final lastApi = _trimTrailingSlash(prefs.getString(_lastApiKey) ?? '');
    final lastWs = _trimTrailingSlash(prefs.getString(_lastWsKey) ?? '');
    if (lastApi.isNotEmpty &&
        _containsEndpoint(_config.apiEndpoints, lastApi)) {
      _apiServerUrl = lastApi;
    }
    if (lastWs.isNotEmpty && _containsEndpoint(_config.wsEndpoints, lastWs)) {
      _wsUrl = lastWs;
    }
  }

  void _ensureCurrentEndpoints() {
    // Discovery 已选好节点，bootstrap 不覆盖
    if (_discoveryApplied) return;
    if (!_containsEndpoint(_config.apiEndpoints, _apiServerUrl)) {
      _apiServerUrl = _config.apiEndpoints.first.url;
    }
    if (!_containsEndpoint(_config.wsEndpoints, _wsUrl)) {
      _wsUrl = _config.wsEndpoints.first.url;
    }
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configKey, jsonEncode(_config.toJson()));
    await prefs.setInt(_fetchedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  List<String> _bootstrapCandidates() {
    final values = <String>[
      ..._splitUrls(bootstrapUrls),
      if (bootstrapUrl.trim().isNotEmpty) bootstrapUrl.trim(),
      _bootstrapPath(_apiServerUrl),
      _bootstrapPath(fallbackServerUrl),
    ];
    return _dedupeStrings(values.map(_normalizeBootstrapUrl));
  }

  void _notifyChanged() {
    if (!_changedController.isClosed) {
      _changedController.add(null);
    }
  }
}

Map<String, dynamic>? _extractPayload(dynamic data) {
  if (data is! Map<String, dynamic>) return null;
  final nested = data['data'];
  if (nested is Map<String, dynamic>) return nested;
  return data;
}

List<EndpointEntry> _endpointList(dynamic raw) {
  if (raw is! List) return const [];
  final out = <EndpointEntry>[];
  for (var i = 0; i < raw.length; i++) {
    final item = raw[i];
    if (item is Map<String, dynamic>) {
      final endpoint = EndpointEntry.fromJson(item, i);
      if (endpoint.url.isNotEmpty) out.add(endpoint);
    }
  }
  out.sort((a, b) => a.priority - b.priority);
  return out;
}

List<EndpointEntry> _normalizeEndpointsForPlatform(
  List<EndpointEntry> endpoints,
  List<EndpointEntry> fallback,
) {
  final fallbackByScheme = <String, String>{};
  for (final entry in fallback) {
    final uri = Uri.tryParse(entry.url);
    if (uri == null) continue;
    fallbackByScheme[uri.scheme] = entry.url;
  }

  return endpoints
      .map((entry) {
        final normalized = _normalizeUrlForPlatform(
          entry.url,
          fallbackByScheme: fallbackByScheme,
        );
        if (normalized == entry.url) return entry;
        return EndpointEntry(
          id: entry.id,
          url: normalized,
          priority: entry.priority,
          healthPath: entry.healthPath,
        );
      })
      .where((entry) => entry.url.isNotEmpty)
      .toList(growable: false);
}

String _normalizeUrlForPlatform(
  String raw, {
  Map<String, String> fallbackByScheme = const {},
}) {
  final value = _trimTrailingSlash(raw);
  if (value.isEmpty) return value;

  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return value;

  if (!kIsWeb &&
      Platform.isAndroid &&
      (_isLoopbackHost(uri.host) || _isAndroidEmulatorHost(uri.host))) {
    final normalized =
        uri.replace(host: EndpointManager._androidLoopbackHost).toString();
    debugPrint(
        '[Endpoint] Android replaced loopback URL $value -> $normalized');
    return _trimTrailingSlash(normalized);
  }

  if (!kIsWeb || uri.host != '10.0.2.2') return value;

  final fallback = fallbackByScheme[uri.scheme] ??
      (uri.scheme == 'ws' || uri.scheme == 'wss'
          ? EndpointManager.fallbackWsUrl
          : EndpointManager.fallbackServerUrl);
  debugPrint(
      '[Endpoint] Web replaced Android emulator URL $value -> $fallback');
  return _trimTrailingSlash(fallback);
}

bool _isLoopbackHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == '127.0.0.1' ||
      normalized == 'localhost' ||
      normalized == '::1' ||
      normalized == '[::1]';
}

bool _isAndroidEmulatorHost(String host) {
  return EndpointManager._androidLoopbackHost != '10.0.2.2' &&
      host == '10.0.2.2';
}

List<EndpointEntry> _mergeEndpoints(
  List<EndpointEntry> primary,
  List<EndpointEntry> fallback,
) {
  final primaryHasRemote = primary.any((entry) {
    final host = Uri.tryParse(entry.url)?.host ?? '';
    return host.isNotEmpty && !_isLoopbackHost(host);
  });
  final out = <EndpointEntry>[];
  final seen = <String>{};
  final usablePrimary = primaryHasRemote
      ? primary.where((entry) {
          final host = Uri.tryParse(entry.url)?.host ?? '';
          return host.isEmpty || !_isLoopbackHost(host);
        })
      : primary;
  // Once bootstrap provides at least one remote endpoint, it is authoritative.
  // Retaining compiled-in fallbacks here can resurrect an endpoint that the
  // backend intentionally removed.
  final usableFallback = primaryHasRemote ? const <EndpointEntry>[] : fallback;
  for (final endpoint in [...usablePrimary, ...usableFallback]) {
    if (endpoint.url.isEmpty || seen.contains(endpoint.url)) continue;
    seen.add(endpoint.url);
    out.add(endpoint);
  }
  out.sort((a, b) => a.priority - b.priority);
  return out;
}

List<String> _stringList(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((e) => e.toString()).toList(growable: false);
}

List<String> _splitUrls(String raw) {
  return raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

List<String> _dedupeStrings(Iterable<String> values) {
  final out = <String>[];
  final seen = <String>{};
  for (final value in values) {
    final normalized = value.trim();
    if (normalized.isEmpty || seen.contains(normalized)) continue;
    seen.add(normalized);
    out.add(normalized);
  }
  return out;
}

bool _containsEndpoint(List<EndpointEntry> endpoints, String url) {
  final normalized = _trimTrailingSlash(url);
  return endpoints.any((endpoint) => endpoint.url == normalized);
}

String _normalizeBootstrapUrl(String value) {
  value = value.trim();
  if (value.isEmpty) return '';
  final uri = Uri.tryParse(value);
  if (uri == null || uri.host.isEmpty) return '';
  if (uri.path.endsWith('/client/bootstrap')) return value;
  return _bootstrapPath(value);
}

String _bootstrapPath(String baseUrl) {
  return '${_trimTrailingSlash(baseUrl)}/api/v1/client/bootstrap';
}

String _trimTrailingSlash(String value) {
  value = value.trim();
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}
