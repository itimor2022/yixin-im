import 'dart:async';

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../utils/platform_utils.dart';

/// 节点切换回调接口，解耦 ApiConfig 与 ApiClient 的循环依赖
abstract class BaseUrlUpdatable {
  void updateBaseUrl(String newServerUrl);
}

/// API 配置
class ApiConfig {
  // ── 编译期 Fallback（ServerDiscovery 未完成时使用） ──────
  //
  // 之前这里硬编码了测试服 URL，会导致：
  //   1. api.txt 拉不到时客户端仍能连上测试服，误以为一切正常；
  //   2. 泄露了生产测试服域名，安全审计不通过；
  //   3. 运维排查"服务发现是不是挂了"时被这条兜底路径掩盖真实症状。
  //
  // 现在留成空串。ServerDiscovery 成功之前所有 API/WS 调用都会立刻失败——
  // 这是我们**故意的**：让"服务发现没跑通"变成一个显性问题，用户看到
  // 网络错误 → 排查 CORS / S3 权限 / 节点存活，而不是被一个错误环境骗着继续用。
  //
  // 本地开发若确实要跳过 ServerDiscovery（例如没配 S3 时），可在此处
  // 临时改回一个 URL；提交前请务必还原为空串。
  static const String _defaultServerUrl = '';

  // ── 运行时可变节点（由 ServerDiscovery.updateServer 写入）──
  static String _serverUrl = _defaultServerUrl;

  /// 当前生效的 serverUrl（只读）
  static String get serverUrl => _serverUrl;

  /// 当前生效的 wsUrl（自动跟随 serverUrl）
  static String get wsUrl {
    if (_serverUrl.isEmpty) return 'ws://localhost/api/v1/ws';
    final base = _serverUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    return '\$base/api/v1/ws';
  }

  static String get baseUrl {
    if (_serverUrl.isEmpty) return 'http://localhost/api/v1';
    return '\$_serverUrl/api/v1';
  }

  /// 由 ServerDiscovery 调用，切换节点
  /// 同时通知已创建的 ApiClient 实例更新 baseUrl
  static void updateServer(String newServerUrl) {
    final url = newServerUrl.endsWith('/')
        ? newServerUrl.substring(0, newServerUrl.length - 1)
        : newServerUrl;
    if (url == _serverUrl) return;
    if (kDebugMode)
      debugPrint('[ApiConfig] Server switched: \$_serverUrl → \$url');
    _serverUrl = url;
    // 通知所有已注册的 ApiClient 实例更新
    for (final client in _registeredClients) {
      client.updateBaseUrl(url);
    }
  }

  // ── ApiClient 注册表（节点切换时批量更新）───────────────
  static final List<BaseUrlUpdatable> _registeredClients = [];
  static void registerClient(BaseUrlUpdatable c) => _registeredClients.add(c);
  static void unregisterClient(BaseUrlUpdatable c) =>
      _registeredClients.remove(c);

  /// 获取完整的媒体 URL（处理相对路径，支持 http/https）
  static String getMediaUrl(String? url) {
    if (url == null) return '';
    final value = url.trim().replaceAll('\\', '/');
    if (value.isEmpty) return '';
    final lowerValue = value.toLowerCase();
    if (lowerValue == 'null' || lowerValue == 'undefined') return '';

    if (value.startsWith('//')) {
      return 'https:$value';
    }

    if (value.startsWith('http://') || value.startsWith('https://')) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.host.isEmpty) return value;
      final serverUri = Uri.parse(serverUrl);
      final h = uri.host;
      final sameHost = h == serverUri.host;
      final isOwnUpload = uri.path.startsWith('/uploads/');
      if (sameHost ||
          h == 'localhost' ||
          h == '127.0.0.1' ||
          (isOwnUpload && _isPrivateHost(h))) {
        final path = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
        return '$serverUrl$path${uri.query.isEmpty ? '' : '?${uri.query}'}';
      }
      return value;
    }

    if (value.startsWith('/')) return '$serverUrl$value';
    return '$serverUrl/$value';
  }

  static bool _isPrivateHost(String host) {
    if (host.startsWith('192.168.') || host.startsWith('10.')) return true;
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    return first == 172 && second != null && second >= 16 && second <= 31;
  }

  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);
}

/// API 响应
class ApiResponse<T> {
  final int code;
  final String message;
  final T? data;

  ApiResponse({required this.code, required this.message, this.data});

  bool get isSuccess => code == 0;

  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic)? fromJson,
  ) {
    // 兼容后端返回数字或字符串 code（如 0 / "0" / 200 / "200"）
    final rawCode = json['code'];
    final code =
        rawCode is int ? rawCode : int.tryParse(rawCode?.toString() ?? '') ?? 0;
    return ApiResponse(
      code: code,
      message: json['message'] ?? '',
      data: json['data'] != null && fromJson != null
          ? fromJson(json['data'])
          : json['data'],
    );
  }
}

/// API 客户端 - 高级模式实现
///
/// 特性:
/// - 使用 Completer 解决 Token 刷新竞态条件
/// - 类型安全的错误处理
/// - 请求取消支持
/// - 自动重试机制
/// - 请求去重（避免重复的 GET 请求）
/// - 请求节流（避免频繁重复请求）
class ApiClient implements BaseUrlUpdatable {
  late final Dio _dio;
  String? _token;

  // 使用 Completer 协调并发的 Token 刷新请求
  Completer<String?>? _refreshCompleter;
  bool _lastRefreshFailureWasAuth = true;

  // 登出回调（由 AuthService 设置）
  VoidCallback? onLogout;

  // 全局手机号绑定拦截回调（由 App 绑定路由跳转）
  VoidCallback? onPhoneBindRequired;

  /// HTTP 401 刷新成功后回调（由 App 绑定 WebSocket，使 WS 与 REST 使用同一 JWT）
  void Function(String newAccessToken)? onAccessTokenRefreshed;

  // 是否已释放
  bool _isDisposed = false;
  DateTime? _lastPhoneBindRequiredAt;

  // 请求去重：正在进行中的请求
  final Map<String, Completer<Response>> _pendingRequests = {};

  // 请求节流：上次请求时间
  final Map<String, DateTime> _lastRequestTime = {};
  static const Duration _throttleDuration = Duration(milliseconds: 300);

  // 独立的 Dio 实例用于 Token 刷新，避免走拦截器导致问题
  late final Dio _authDio;

  ApiClient() {
    if (kDebugMode)
      debugPrint('[API] Initializing with baseUrl: ${ApiConfig.baseUrl}');
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        sendTimeout: const Duration(seconds: 60), // 添加发送超时
        headers: {'Content-Type': 'application/json'},
      ),
    );

    // 独立的 auth Dio，不添加拦截器，避免 Token 刷新时死循环
    _authDio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        headers: {'Content-Type': 'application/json'},
      ),
    );

    _setupInterceptors();
    // 注册到 ApiConfig，节点切换时自动更新 baseUrl
    ApiConfig.registerClient(this);
  }

  /// 设置拦截器
  void _setupInterceptors() {
    // 1. 请求去重拦截器（仅对 GET 请求生效）
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 仅对 GET 请求进行去重
          if (options.method == 'GET') {
            final key = '${options.method}:${options.uri}';

            // 检查是否有相同请求正在进行
            if (_pendingRequests.containsKey(key)) {
              if (kDebugMode)
                debugPrint('[API] Request dedup: waiting for $key');
              try {
                final response = await _pendingRequests[key]!.future;
                return handler.resolve(response);
              } catch (e) {
                return handler.reject(
                  DioException(requestOptions: options, error: e),
                );
              }
            }

            // 创建新的 Completer
            _pendingRequests[key] = Completer<Response>();
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          // 完成去重请求
          if (response.requestOptions.method == 'GET') {
            final key =
                '${response.requestOptions.method}:${response.requestOptions.uri}';
            final completer = _pendingRequests.remove(key);
            if (completer != null && !completer.isCompleted) {
              completer.complete(response);
            }
          }
          return handler.next(response);
        },
        onError: (error, handler) {
          // 失败时也要完成 Completer，防止等待方永久挂起
          if (error.requestOptions.method == 'GET') {
            final key =
                '${error.requestOptions.method}:${error.requestOptions.uri}';
            final completer = _pendingRequests.remove(key);
            if (completer != null && !completer.isCompleted) {
              completer.completeError(error);
            }
          }
          return handler.next(error);
        },
      ),
    );

    // 2. 请求节流拦截器（仅对 GET：避免短时间重复拉取；切勿对 POST 等同路径请求节流，
    // 否则如 /message/send 在 300ms 内连发多条会全部被 cancel，表现为发消息感叹号）
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.method != 'GET') {
            return handler.next(options);
          }
          // 必须用完整 URI（含 query），否则同 path 不同参数（如不同 chat_id 的 sync）会被误节流
          final key = '${options.method}:${options.uri}';
          final now = DateTime.now();
          final lastTime = _lastRequestTime[key];

          if (lastTime != null &&
              now.difference(lastTime) < _throttleDuration) {
            // 节流：请求太频繁，跳过
            if (kDebugMode) debugPrint('[API] Request throttled: $key');
            return handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.cancel,
                error: 'Request throttled',
              ),
            );
          }

          _lastRequestTime[key] = now;
          return handler.next(options);
        },
      ),
    );

    // 3. Token 和错误处理拦截器
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (_token != null) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          if (kDebugMode) debugPrint('[API] ${options.method} ${options.uri}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          if (kDebugMode)
            debugPrint(
              '[API] Response: ${response.statusCode} ${response.requestOptions.path}',
            );
          return handler.next(response);
        },
        onError: (error, handler) async {
          if (kDebugMode)
            debugPrint(
              '[API] Error: ${error.message} URL: ${error.requestOptions.uri}',
            );

          // 处理 401 错误 - 使用 Completer 模式避免竞态条件
          if (_shouldRefreshToken(error)) {
            try {
              final newToken = await _refreshTokenWithLock();
              if (newToken != null) {
                // 刷新成功，使用新 token 重试原请求
                final retryResponse = await _retryRequest(
                  error.requestOptions,
                  newToken,
                );
                return handler.resolve(retryResponse);
              }
            } catch (e) {
              if (kDebugMode) debugPrint('[API] Retry failed: $e');
            }
            // 刷新失败，触发登出
            if (_lastRefreshFailureWasAuth) {
              _triggerLogout();
            } else {
              return handler.reject(
                DioException(
                  requestOptions: error.requestOptions,
                  type: DioExceptionType.connectionError,
                  error: 'Token refresh temporarily unavailable',
                ),
              );
            }
          }

          // 网络错误自动重试（非 401）
          if (_shouldRetryOnError(error)) {
            final retryCount = error.requestOptions.extra['retryCount'] ?? 0;
            if (retryCount < 3) {
              if (kDebugMode)
                debugPrint(
                  '[API] Retrying request (attempt ${retryCount + 1}/3): ${error.requestOptions.path}',
                );

              // 指数退避延迟
              final retryNum = retryCount is int ? retryCount : 0;
              final delay = Duration(milliseconds: 500 * (retryNum + 1));
              await Future.delayed(delay);

              try {
                final options = error.requestOptions;
                options.extra['retryCount'] = retryCount + 1;

                final response = await _dio.request(
                  options.path,
                  data: options.data,
                  queryParameters: options.queryParameters,
                  options: Options(
                    method: options.method,
                    headers: options.headers,
                    extra: options.extra,
                  ),
                );
                return handler.resolve(response);
              } catch (e) {
                // 重试失败，继续传递错误
                if (kDebugMode) debugPrint('[API] Retry failed: $e');
              }
            }
          }

          return handler.next(error);
        },
      ),
    );
  }

  /// 判断是否应该重试请求（网络错误等可恢复错误）
  bool _shouldRetryOnError(DioException error) {
    // 不重试取消的请求
    if (error.type == DioExceptionType.cancel) return false;

    // 不重试 4xx 客户端错误（除了 408 超时和 429 限流）
    final statusCode = error.response?.statusCode;
    if (statusCode != null && statusCode >= 400 && statusCode < 500) {
      if (statusCode != 408 && statusCode != 429) return false;
    }

    // 重试网络错误、超时、连接错误
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown;
  }

  /// 判断是否应该刷新 Token
  bool _shouldRefreshToken(DioException error) {
    return error.response?.statusCode == 401 &&
        _token != null &&
        !error.requestOptions.path.contains('/auth/refresh') &&
        !error.requestOptions.path.contains('/auth/login');
  }

  String? get currentToken => _token;

  Future<String?> refreshTokenSilently() async {
    if (_isDisposed || _token == null || _token!.isEmpty) {
      return null;
    }
    return _refreshTokenWithLock();
  }

  /// 使用 Completer 锁定的 Token 刷新
  /// 多个并发的 401 错误只会触发一次刷新，其他请求等待结果
  Future<String?> _refreshTokenWithLock() async {
    // 如果正在刷新，等待现有刷新完成
    if (_refreshCompleter != null) {
      if (kDebugMode) debugPrint('[API] Waiting for existing token refresh...');
      return _refreshCompleter!.future;
    }

    if (_token == null || _isDisposed) {
      if (kDebugMode)
        debugPrint('[API] Cannot refresh: token is null or disposed');
      return null;
    }

    // 创建新的 Completer 并开始刷新
    _refreshCompleter = Completer<String?>();

    _lastRefreshFailureWasAuth = true;

    try {
      if (kDebugMode) debugPrint('[API] Starting token refresh...');

      // 使用独立的 _authDio 实例，避免走拦截器导致死循环
      final response = await _authDio.post(
        '/auth/refresh',
        options: Options(headers: {'Authorization': 'Bearer $_token'}),
      );

      if (kDebugMode)
        debugPrint('[API] Refresh response status: ${response.statusCode}');

      final newToken = _extractToken(response);
      if (newToken != null) {
        _token = newToken;
        await TokenStorage.saveToken(newToken);
        if (kDebugMode) debugPrint('[API] Token refreshed successfully');
        try {
          onAccessTokenRefreshed?.call(newToken);
        } catch (e) {
          if (kDebugMode) debugPrint('[API] onAccessTokenRefreshed error: $e');
        }
        _refreshCompleter!.complete(newToken);
        return newToken;
      }

      if (kDebugMode)
        debugPrint('[API] Token refresh failed: could not extract token');
      _lastRefreshFailureWasAuth = true;
      _refreshCompleter!.complete(null);
      return null;
    } on DioException catch (e, stackTrace) {
      final statusCode = e.response?.statusCode;
      _lastRefreshFailureWasAuth = e.type == DioExceptionType.badResponse &&
          statusCode != null &&
          statusCode >= 400 &&
          statusCode < 500;
      if (kDebugMode) debugPrint('[API] Token refresh error: $e');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 5);
      _refreshCompleter!.complete(null);
      return null;
    } catch (e, stackTrace) {
      _lastRefreshFailureWasAuth = false;
      if (kDebugMode) debugPrint('[API] Token refresh error: $e');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 5);
      _refreshCompleter!.complete(null);
      return null;
    } finally {
      _refreshCompleter = null;
    }
  }

  /// 类型安全地提取 Token
  String? _extractToken(Response response) {
    if (response.statusCode != 200 || response.data == null) return null;

    final data = response.data;
    if (data is! Map<String, dynamic>) return null;

    final code = data['code'];
    if (code != 0) return null;

    final tokenData = data['data'];
    if (tokenData is! Map<String, dynamic>) return null;

    final token = tokenData['token'];
    if (token is String && token.isNotEmpty) {
      return token;
    }
    return null;
  }

  /// 使用新 Token 重试请求
  Future<Response> _retryRequest(RequestOptions options, String newToken) {
    options.headers['Authorization'] = 'Bearer $newToken';
    return _dio.fetch(options);
  }

  /// 触发登出
  void _triggerLogout() {
    if (_isDisposed) return;
    if (kDebugMode) debugPrint('[API] Token expired, triggering logout');
    _token = null;
    if (PlatformUtils.isWeb) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.remove('auth_token');
        prefs.remove('user_id');
        prefs.remove('auth_user_data');
      });
    } else {
      TokenStorage.clear();
    }
    onLogout?.call();
  }

  /// 设置 Token
  void setToken(String token) {
    _token = token;
  }

  /// 清除 Token
  void clearToken() {
    _token = null;
  }

  /// 释放资源
  /// 节点切换时由 ApiConfig.updateServer 调用
  @override
  void updateBaseUrl(String newServerUrl) {
    final newBase = '$newServerUrl/api/v1';
    _dio.options.baseUrl = newBase;
    _authDio.options.baseUrl = newBase;
    if (kDebugMode) debugPrint('[ApiClient] baseUrl updated: $newBase');
  }

  void dispose() {
    _isDisposed = true;
    ApiConfig.unregisterClient(this);

    // 清理正在进行的 token 刷新
    if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
      _refreshCompleter!.complete(null);
    }
    _refreshCompleter = null;

    // 清理待处理的请求，防止内存泄漏
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          DioException(
            requestOptions: RequestOptions(),
            error: 'Client disposed',
            type: DioExceptionType.cancel,
          ),
        );
      }
    }
    _pendingRequests.clear();
    _lastRequestTime.clear();

    _dio.close(force: true);
    _authDio.close(force: true);
    onLogout = null;
    onPhoneBindRequired = null;
    onAccessTokenRefreshed = null;
  }

  /// GET 请求
  /// [cancelToken] 可选的取消令牌，用于取消请求
  Future<ApiResponse<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    CancelToken? cancelToken,
  }) async {
    if (_isDisposed) {
      return ApiResponse(code: -1, message: '客户端已释放');
    }
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
      );
      return _parseResponse(response, fromJson);
    } on DioException catch (e) {
      return _handleError(e);
    } catch (e) {
      if (kDebugMode) debugPrint('[API] Unexpected error in GET $path: $e');
      return ApiResponse(code: -1, message: '发生未知错误');
    }
  }

  /// POST 请求
  /// [data] 请求体，推荐使用 Map<String, dynamic> 或具体类型
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    T Function(dynamic)? fromJson,
    CancelToken? cancelToken,
  }) async {
    if (_isDisposed) {
      return ApiResponse(code: -1, message: '客户端已释放');
    }
    try {
      final response = await _dio.post(
        path,
        data: data,
        cancelToken: cancelToken,
      );
      return _parseResponse(response, fromJson);
    } on DioException catch (e) {
      return _handleError(e);
    } catch (e) {
      if (kDebugMode) debugPrint('[API] Unexpected error in POST $path: $e');
      return ApiResponse(code: -1, message: '发生未知错误');
    }
  }

  /// PUT 请求
  Future<ApiResponse<T>> put<T>(
    String path, {
    Object? data,
    T Function(dynamic)? fromJson,
    CancelToken? cancelToken,
  }) async {
    if (_isDisposed) {
      return ApiResponse(code: -1, message: '客户端已释放');
    }
    try {
      final response = await _dio.put(
        path,
        data: data,
        cancelToken: cancelToken,
      );
      return _parseResponse(response, fromJson);
    } on DioException catch (e) {
      return _handleError(e);
    } catch (e) {
      if (kDebugMode) debugPrint('[API] Unexpected error in PUT $path: $e');
      return ApiResponse(code: -1, message: '发生未知错误');
    }
  }

  /// DELETE 请求
  Future<ApiResponse<T>> delete<T>(
    String path, {
    Object? data, // 支持请求体
    T Function(dynamic)? fromJson,
    CancelToken? cancelToken,
  }) async {
    if (_isDisposed) {
      return ApiResponse(code: -1, message: '客户端已释放');
    }
    try {
      final response = await _dio.delete(
        path,
        data: data,
        cancelToken: cancelToken,
      );
      return _parseResponse(response, fromJson);
    } on DioException catch (e) {
      return _handleError(e);
    } catch (e) {
      if (kDebugMode) debugPrint('[API] Unexpected error in DELETE $path: $e');
      return ApiResponse(code: -1, message: '发生未知错误');
    }
  }

  /// 文件上传请求
  Future<ApiResponse<T>> upload<T>(
    String path,
    FormData formData, {
    T Function(dynamic)? fromJson,
    void Function(int, int)? onSendProgress,
    CancelToken? cancelToken,
    Duration? sendTimeout, // 可配置的上传超时
  }) async {
    if (_isDisposed) {
      return ApiResponse(code: -1, message: '客户端已释放');
    }
    try {
      final response = await _dio.post(
        path,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: sendTimeout ?? const Duration(minutes: 5), // 大文件上传需要更长时间
        ),
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );
      return _parseResponse(response, fromJson);
    } on DioException catch (e) {
      return _handleError(e);
    } catch (e) {
      if (kDebugMode) debugPrint('[API] Unexpected error in UPLOAD $path: $e');
      return ApiResponse(code: -1, message: '发生未知错误');
    }
  }

  /// 解析响应（类型安全）
  ApiResponse<T> _parseResponse<T>(
    Response response,
    T Function(dynamic)? fromJson,
  ) {
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      return ApiResponse(code: -1, message: '响应格式错误');
    }
    final sanitizedData = Map<String, dynamic>.from(data);
    sanitizedData['message'] = _sanitizeServerMessage(
      sanitizedData['message']?.toString() ?? '',
    );
    final result = ApiResponse.fromJson(sanitizedData, fromJson);
    _maybeNotifyPhoneBindRequired(result.code, result.message);
    return result;
  }

  /// 错误类型到消息的映射
  String _sanitizeServerMessage(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) {
      return normalized;
    }

    final lower = normalized.toLowerCase();
    const technicalMarkers = <String>[
      'not authorized on',
      'command {',
      '\$db:',
      'tbimimqq_messages',
      'messages_',
      'server selection timeout',
      'connection refused',
      'topology',
      'mongo',
    ];

    for (final marker in technicalMarkers) {
      if (lower.contains(marker)) {
        return '消息服务暂时不可用，请稍后重试';
      }
    }

    return normalized;
  }

  static const _errorMessages = <DioExceptionType, String>{
    DioExceptionType.connectionTimeout: '连接超时，请检查网络',
    DioExceptionType.sendTimeout: '发送超时，请检查网络',
    DioExceptionType.receiveTimeout: '服务器响应超时',
    DioExceptionType.badCertificate: '证书验证失败',
    DioExceptionType.connectionError: '网络连接失败，请检查网络设置',
    DioExceptionType.cancel: '请求已取消',
  };

  /// HTTP 状态码到消息的映射
  static const _httpStatusMessages = <int, String>{
    401: '登录已过期，请重新登录',
    403: '没有权限',
    404: '请求的资源不存在',
  };

  /// 错误处理（使用映射表简化代码）
  ApiResponse<T> _handleError<T>(DioException e) {
    // 优先使用映射表
    if (_errorMessages.containsKey(e.type)) {
      return ApiResponse(code: -1, message: _errorMessages[e.type]!);
    }

    // 处理 badResponse
    if (e.type == DioExceptionType.badResponse) {
      return _handleBadResponse(e);
    }

    // 处理 unknown
    if (e.type == DioExceptionType.unknown) {
      final isSocketError =
          e.error?.toString().contains('SocketException') ?? false;
      return ApiResponse(
        code: -1,
        message: isSocketError ? '无法连接服务器，请检查网络' : '网络异常，请稍后重试',
      );
    }

    return ApiResponse(code: -1, message: '未知错误');
  }

  /// 处理 HTTP 错误响应
  ApiResponse<T> _handleBadResponse<T>(DioException e) {
    final responseData = e.response?.data;
    if (responseData is Map<String, dynamic>) {
      final message = _sanitizeServerMessage(
        responseData['message']?.toString() ?? '服务器错误',
      );
      final rawCode = responseData['code'];
      final code = rawCode is int
          ? rawCode
          : int.tryParse(rawCode?.toString() ?? '') ??
              e.response?.statusCode ??
              -1;
      _maybeNotifyPhoneBindRequired(code, message);
      return ApiResponse(code: code, message: message);
    }

    final fallbackStatusCode = e.response?.statusCode ?? 0;
    final fallbackMessage = _httpStatusMessages[fallbackStatusCode] ??
        (fallbackStatusCode >= 500 ? '服务器繁忙，请稍后重试' : '请求失败');
    _maybeNotifyPhoneBindRequired(fallbackStatusCode, fallbackMessage);
    return ApiResponse(code: fallbackStatusCode, message: fallbackMessage);
  }

  void _maybeNotifyPhoneBindRequired(int code, String message) {
    if (code != 403 || !message.contains('绑定手机号')) return;
    final now = DateTime.now();
    final last = _lastPhoneBindRequiredAt;
    if (last != null && now.difference(last) < const Duration(seconds: 1)) {
      return;
    }
    _lastPhoneBindRequiredAt = now;
    onPhoneBindRequired?.call();
  }
}

/// Provider（带生命周期管理）
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(() => client.dispose());
  return client;
});

class AppCleanException implements Exception {
  final String message;
  AppCleanException(this.message);

  @override
  String toString() => message;
}

/// Token 安全存储（使用 flutter_secure_storage 加密存储敏感数据）
class TokenStorage {
  static const String _tokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const String _userDataKey = 'auth_user_data';

  static FlutterSecureStorage? _secureStorage;

  static Future<FlutterSecureStorage> _getSecureStorage() async {
    if (_secureStorage != null) return _secureStorage!;
    try {
      _secureStorage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
        ),
      );
      return _secureStorage!;
    } catch (e) {
      if (kDebugMode)
        debugPrint('[TokenStorage] secure storage init failed: $e');
      _secureStorage = const FlutterSecureStorage();
      return _secureStorage!;
    }
  }

  static Future<void> _writeSecureValue(String key, String? value) async {
    if (PlatformUtils.isWeb) {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value);
      }
      return;
    }

    try {
      final secureStorage = await _getSecureStorage();
      if (value == null) {
        await secureStorage.delete(key: key);
      } else {
        await secureStorage.write(key: key, value: value);
      }
    } catch (e) {
      if (kDebugMode)
        debugPrint(
            '[TokenStorage] secure write failed, falling back to prefs: $e');
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, value);
      }
    }
  }

  static Future<String?> _readSecureValue(String key) async {
    if (PlatformUtils.isWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }

    try {
      final secureStorage = await _getSecureStorage();
      return secureStorage.read(key: key);
    } catch (e) {
      if (kDebugMode)
        debugPrint(
            '[TokenStorage] secure read failed, falling back to prefs: $e');
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
  }

  static Future<void> saveToken(String token) async {
    await _writeSecureValue(_tokenKey, token);
  }

  static Future<String?> getToken() async {
    return _readSecureValue(_tokenKey);
  }

  static Future<void> saveUserId(String userId) async {
    await _writeSecureValue(_userIdKey, userId);
  }

  static Future<String?> getUserId() async {
    return _readSecureValue(_userIdKey);
  }

  static Future<void> saveUserData(Map<String, dynamic> userData) async {
    final value = jsonEncode(userData);
    if (PlatformUtils.isWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userDataKey, value);
      return;
    }
    final secureStorage = await _getSecureStorage();
    await secureStorage.write(key: _userDataKey, value: value);
  }

  static Future<Map<String, dynamic>?> getUserData() async {
    String? value;
    if (PlatformUtils.isWeb) {
      final prefs = await SharedPreferences.getInstance();
      value = prefs.getString(_userDataKey);
    } else {
      final secureStorage = await _getSecureStorage();
      value = await secureStorage.read(key: _userDataKey);
    }
    if (value == null || value.isEmpty) return null;

    final decoded = jsonDecode(value);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  /// 清除所有存储的凭证（使用 Future.wait 并行执行）
  static Future<void> clear() async {
    // 并行清除安全存储（非 Web 平台）
    final secureStorage = await _getSecureStorage();
    await Future.wait([
      secureStorage.delete(key: _tokenKey),
      secureStorage.delete(key: _userIdKey),
      secureStorage.delete(key: _userDataKey),
    ]);

    // 并行清除 SharedPreferences（Web 平台 token/userId 也存于此）
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_tokenKey), // Web 端 token
      prefs.remove(_userIdKey), // Web 端 userId
      prefs.remove(_userDataKey),
      prefs.remove('moment_notification_last_read'),
      prefs.remove('recent_emojis'),
      prefs.remove('emoji_store_cloud_updated_at'),
    ]);
  }

  /// 迁移旧的 SharedPreferences token 到安全存储
  static Future<void> migrateFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 并行迁移 token 和 userId
      await Future.wait([
        _migrateKey(prefs, _tokenKey),
        _migrateKey(prefs, _userIdKey),
        _migrateKey(prefs, _userDataKey),
      ]);
    } catch (e) {
      if (kDebugMode) debugPrint('[TokenStorage] Migration error: $e');
    }
  }

  /// 迁移单个 key
  static Future<void> _migrateKey(SharedPreferences prefs, String key) async {
    final oldValue = prefs.getString(key);
    if (oldValue == null || oldValue.isEmpty) return;

    final secureStorage = await _getSecureStorage();
    final secureValue = await secureStorage.read(key: key);
    if (secureValue == null || secureValue.isEmpty) {
      await secureStorage.write(key: key, value: oldValue);
      await prefs.remove(key);
    }
  }
}
