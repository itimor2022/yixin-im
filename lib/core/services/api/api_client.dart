// 文件用途：封装 HTTP 请求、鉴权、超时、上传下载、错误转换与通用响应解析。
// 核心逻辑：统一添加认证和设备请求头，执行超时/重试/取消处理，并把 Dio 异常转换为应用可识别的 ApiResponse。
import 'dart:async';

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../i18n/app_localizations.dart';
import '../../utils/platform_utils.dart';
import 'endpoint_manager.dart';

@visibleForTesting
Object? cloneRequestDataForRetry(Object? data) {
  // FormData and MultipartFile bodies are single-subscription streams. Dio
  // exposes deep clone support specifically so a retry can reopen each file.
  return data is FormData ? data.clone() : data;
}

String _apiText({
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 关键声明：API 客户端是网络错误和鉴权头的单一入口，调用方不应绕过它直接创建 Dio 请求。
/// API 配置
class ApiConfig {
  // 本地开发环境
  // 线上环境
  // 改这里即可切换：
  // `true`  -> 安卓模拟器 `10.0.2.2`
  static String get serverUrl => EndpointManager.instance.apiServerUrl;
  static String get wsUrl => EndpointManager.instance.wsUrl;
  static String get baseUrl => '$serverUrl/api/v1';

  /// Return the display URL for media, rewriting app-owned uploads to the
  /// active media base while preserving third-party absolute URLs.
  static String getMediaUrl(String? url) {
    final value = _cleanMediaUrl(url);
    if (value.isEmpty || value.startsWith('data:')) return value;

    if (value.startsWith('//')) {
      return getMediaUrl('https:$value');
    }

    if (_isHttpUrl(value)) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.host.isEmpty) return value;
      final host = uri.host.toLowerCase();
      final isOwnUpload = _isUploadPath(uri.path);
      final shouldRewrite = _isConfiguredMediaHost(host) ||
          _isLocalHost(host) ||
          (isOwnUpload &&
              (_isPrivateHost(host) || _isLegacyOwnMediaHost(host)));
      if (shouldRewrite) {
        final path = uri.path.startsWith('/') ? uri.path : '/${uri.path}';
        return '${_mediaBaseUrl()}$path${_uriSuffix(uri)}';
      }
      return value;
    }

    final mediaBaseUrl = _mediaBaseUrl();
    if (value.startsWith('/')) return '$mediaBaseUrl$value';
    return '$mediaBaseUrl/$value';
  }

  /// Normalize app-owned upload URLs before storing them in messages.
  ///
  /// Keeping `/uploads/...` in message content lets overseas clients resolve
  /// media through the current bootstrap media domain instead of a stale host.
  static String normalizeMediaUrlForMessage(String? url) {
    final value = _cleanMediaUrl(url);
    if (value.isEmpty || value.startsWith('data:')) return value;

    if (value.startsWith('//')) {
      return normalizeMediaUrlForMessage('https:$value');
    }

    if (value.startsWith('/uploads/')) return value;
    if (value.startsWith('uploads/')) return '/$value';

    if (_isHttpUrl(value)) {
      final uri = Uri.tryParse(value);
      if (uri == null || uri.host.isEmpty) return value;
      final host = uri.host.toLowerCase();
      if (_isUploadPath(uri.path) &&
          (_isConfiguredMediaHost(host) ||
              _isLocalHost(host) ||
              _isPrivateHost(host) ||
              _isLegacyOwnMediaHost(host))) {
        return '${uri.path}${_uriSuffix(uri)}';
      }
    }

    return value;
  }

  static String _cleanMediaUrl(String? url) {
    if (url == null) return '';
    final value = url.trim().replaceAll('\\', '/');
    if (value.isEmpty) return '';
    final lowerValue = value.toLowerCase();
    if (lowerValue == 'null' || lowerValue == 'undefined') return '';
    return value;
  }

  static bool _isHttpUrl(String value) =>
      value.startsWith('http://') || value.startsWith('https://');

  static bool _isUploadPath(String path) => path.startsWith('/uploads/');

  static String _mediaBaseUrl() =>
      EndpointManager.instance.mediaBaseUrl.replaceFirst(RegExp(r'/+$'), '');

  static String _uriSuffix(Uri uri) {
    final query = uri.hasQuery ? '?${uri.query}' : '';
    final fragment = uri.hasFragment ? '#${uri.fragment}' : '';
    return '$query$fragment';
  }

  static bool _isConfiguredMediaHost(String host) {
    final normalized = host.toLowerCase();
    for (final rawBase in [
      serverUrl,
      ...EndpointManager.instance.mediaBaseUrls,
    ]) {
      final uri = Uri.tryParse(rawBase);
      if (uri != null && uri.host.toLowerCase() == normalized) {
        return true;
      }
    }
    return _isLegacyOwnMediaHost(normalized);
  }

  static bool _isLegacyOwnMediaHost(String host) {
    switch (host.toLowerCase()) {
      case 'app.example.com':
        return true;
      default:
        return false;
    }
  }

  static bool _isPrivateHost(String host) {
    if (host.startsWith('192.168.') || host.startsWith('10.')) return true;
    final parts = host.split('.');
    if (parts.length != 4) return false;
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    return first == 172 && second != null && second >= 16 && second <= 31;
  }

  static bool _isLocalHost(String host) {
    final normalized = host.toLowerCase();
    return normalized ==
            String.fromCharCodes(
              const [108, 111, 99, 97, 108, 104, 111, 115, 116],
            ) ||
        normalized ==
            String.fromCharCodes(
              const [49, 50, 55, 46, 48, 46, 48, 46, 49],
            );
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
class ApiClient {
  late final Dio _dio;
  String? _token;
  StreamSubscription<void>? _endpointSubscription;

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

  // Token 刷新使用独立客户端，避免刷新请求再次触发 401 拦截形成递归。
  late final Dio _authDio;

  ApiClient() : this._(initializeEndpoints: true);

  @visibleForTesting
  ApiClient.forTesting() : this._(initializeEndpoints: false);

  ApiClient._({required bool initializeEndpoints}) {
    if (initializeEndpoints) {
      // EndpointManager 已在 bootstrap 阶段由 _runDiscoveryInBackground 统一初始化
      // EndpointManager.instance.initializeInBackground();
    }
    debugPrint('[API] Initializing with baseUrl: ${ApiConfig.baseUrl}');
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        sendTimeout: const Duration(seconds: 60), // 添加发送超时
        headers: {
          'Content-Type': 'application/json',
          'X-Client-Platform': PlatformUtils.deviceType,
        },
      ),
    );

    // 独立的 auth Dio，不添加拦截器，避免 Token 刷新时死循环
    _authDio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'X-Client-Platform': PlatformUtils.deviceType,
        },
      ),
    );

    if (initializeEndpoints) {
      _endpointSubscription = EndpointManager.instance.onChanged.listen((_) {
        _applyEndpointBaseUrl();
      });
    }

    _setupInterceptors();
  }

  void _applyEndpointBaseUrl() {
    final nextBaseUrl = ApiConfig.baseUrl;
    if (_dio.options.baseUrl == nextBaseUrl &&
        _authDio.options.baseUrl == nextBaseUrl) {
      return;
    }
    debugPrint('[API] Switching baseUrl to: $nextBaseUrl');
    _dio.options.baseUrl = nextBaseUrl;
    _authDio.options.baseUrl = nextBaseUrl;
  }

  /// 设置拦截器
  void _setupInterceptors() {
    // 1. GET 去重：相同完整 URI 的并发调用共享首个请求结果，
    // 不用于可能产生副作用的写请求。
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // 仅对 GET 请求进行去重
          if (options.method == 'GET') {
            final key = '${options.method}:${options.uri}';

            // 检查是否有相同请求正在进行
            if (_pendingRequests.containsKey(key)) {
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
            debugPrint('[API] Request throttled: $key');
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
          debugPrint('[API] ${options.method} ${options.uri}');
          return handler.next(options);
        },
        onResponse: (response, handler) {
          debugPrint(
            '[API] Response: ${response.statusCode} ${response.requestOptions.path}',
          );
          unawaited(EndpointManager.instance.markApiSuccess(
            _requestServerUrl(response.requestOptions),
          ));
          return handler.next(response);
        },
        onError: (error, handler) async {
          debugPrint(
            '[API] Error: ${error.message} URL: ${error.requestOptions.uri}',
          );

          // 并发 401 共用一次刷新；只有服务端明确拒绝刷新凭证才触发登出，
          // 临时网络失败保留当前会话并把可重试错误交给上层。
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
              debugPrint('[API] Retry failed: $e');
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

          // 网络错误自动重试（非 401）。超时前请求可能已经到达服务端，
          // 因此写接口仍需依赖业务侧 client_msg_id 等幂等机制防止重复执行。
          if (_shouldRetryOnError(error)) {
            final switched = await _maybeSwitchApiEndpoint(error);
            if (switched) {
              _applyEndpointBaseUrl();
            }
            final retryCount = error.requestOptions.extra['retryCount'] ?? 0;
            if (retryCount < 3) {
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
                  data: cloneRequestDataForRetry(options.data),
                  queryParameters: options.queryParameters,
                  options: Options(
                    method: options.method,
                    headers: options.headers,
                    extra: options.extra,
                    sendTimeout: options.sendTimeout,
                    receiveTimeout: options.receiveTimeout,
                  ),
                );
                return handler.resolve(response);
              } catch (e) {
                // 重试失败，继续传递错误
                debugPrint('[API] Retry failed: $e');
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
    if (statusCode == 502 || statusCode == 503 || statusCode == 504) {
      return error.requestOptions.extra['retryServerErrors'] == true;
    }

    // 重试网络错误、超时、连接错误
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown;
  }

  /// 判断是否应该刷新 Token
  Future<bool> _maybeSwitchApiEndpoint(DioException error) async {
    if (error.type == DioExceptionType.badCertificate ||
        error.type == DioExceptionType.cancel) {
      return false;
    }
    try {
      // 请求在途期间端点可能已切换，必须把失败归因到实际请求 URL；
      // 否则旧请求会误伤新的健康端点并触发错误回退。
      return await EndpointManager.instance.markApiFailure(
        _requestServerUrl(error.requestOptions),
      );
    } catch (e) {
      debugPrint('[API] Endpoint switch failed: $e');
      return false;
    }
  }

  String _requestServerUrl(RequestOptions options) {
    final uri = options.uri;
    if (uri.hasScheme && uri.host.isNotEmpty) {
      return uri.replace(path: '', query: null, fragment: null).toString();
    }
    return ApiConfig.serverUrl;
  }

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
      debugPrint('[API] Waiting for existing token refresh...');
      return _refreshCompleter!.future;
    }

    if (_token == null || _isDisposed) {
      debugPrint('[API] Cannot refresh: token is null or disposed');
      return null;
    }

    // 创建新的 Completer 并开始刷新
    _refreshCompleter = Completer<String?>();

    _lastRefreshFailureWasAuth = true;

    try {
      debugPrint('[API] Starting token refresh...');

      // 使用独立的 _authDio 实例，避免走拦截器导致死循环
      final response = await _authDio.post(
        '/auth/refresh',
        options: Options(headers: {'Authorization': 'Bearer $_token'}),
      );

      debugPrint('[API] Refresh response status: ${response.statusCode}');

      final newToken = _extractToken(response);
      if (newToken != null) {
        _token = newToken;
        await TokenStorage.saveToken(newToken);
        debugPrint('[API] Token refreshed successfully');
        try {
          onAccessTokenRefreshed?.call(newToken);
        } catch (e) {
          debugPrint('[API] onAccessTokenRefreshed error: $e');
        }
        _refreshCompleter!.complete(newToken);
        return newToken;
      }

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
      debugPrint('[API] Token refresh error: $e');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 5);
      _refreshCompleter!.complete(null);
      return null;
    } catch (e, stackTrace) {
      _lastRefreshFailureWasAuth = false;
      debugPrint('[API] Token refresh error: $e');
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
    final retryOptions = options.copyWith(
      data: cloneRequestDataForRetry(options.data),
      headers: Map<String, dynamic>.from(options.headers)
        ..['Authorization'] = 'Bearer $newToken',
    );
    return _dio.fetch(retryOptions);
  }

  /// 触发登出
  void _triggerLogout() {
    if (_isDisposed) return;
    debugPrint('[API] Token expired, triggering logout');
    _token = null;
    // 此处只立即隔离内存 Token；账号工作器停用和持久化凭证清理由 AuthService
    // 统一编排，避免 ApiClient 越权清理到一半。
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

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  /// 释放资源
  void dispose() {
    _isDisposed = true;

    // 清理正在进行的 token 刷新
    if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
      _refreshCompleter!.complete(null);
    }
    _refreshCompleter = null;

    // 显式失败所有等待去重结果的调用，避免 Provider 销毁后 Future 永久悬挂。
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
    _endpointSubscription?.cancel();
    _endpointSubscription = null;
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
      return ApiResponse(
        code: -1,
        message: _apiText(
          zhCN: '客户端已释放',
          zhTW: '客戶端已釋放',
          en: 'Client unavailable.',
        ),
      );
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
      debugPrint('[API] Unexpected error in GET $path: $e');
      return ApiResponse(
        code: -1,
        message: _apiText(
          zhCN: '发生未知错误',
          zhTW: '發生未知錯誤',
          en: 'Unknown error occurred.',
        ),
      );
    }
  }

  /// POST 请求
  /// [data] 请求体，推荐使用 Map<String, dynamic> 或具体类型
  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    T Function(dynamic)? fromJson,
    CancelToken? cancelToken,
    Duration? receiveTimeout,
  }) async {
    if (_isDisposed) {
      return ApiResponse(
        code: -1,
        message: _apiText(
          zhCN: '客户端已释放',
          zhTW: '客戶端已釋放',
          en: 'Client unavailable.',
        ),
      );
    }
    try {
      final response = await _dio.post(
        path,
        data: data,
        cancelToken: cancelToken,
        options: receiveTimeout == null
            ? null
            : Options(receiveTimeout: receiveTimeout),
      );
      return _parseResponse(response, fromJson);
    } on DioException catch (e) {
      return _handleError(e);
    } catch (e) {
      debugPrint('[API] Unexpected error in POST $path: $e');
      return ApiResponse(
        code: -1,
        message: _apiText(
          zhCN: '发生未知错误',
          zhTW: '發生未知錯誤',
          en: 'Unknown error occurred.',
        ),
      );
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
      return ApiResponse(
        code: -1,
        message: _apiText(
          zhCN: '客户端已释放',
          zhTW: '客戶端已釋放',
          en: 'Client unavailable.',
        ),
      );
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
      debugPrint('[API] Unexpected error in PUT $path: $e');
      return ApiResponse(
        code: -1,
        message: _apiText(
          zhCN: '发生未知错误',
          zhTW: '發生未知錯誤',
          en: 'Unknown error occurred.',
        ),
      );
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
      return ApiResponse(
        code: -1,
        message: _apiText(
          zhCN: '客户端已释放',
          zhTW: '客戶端已釋放',
          en: 'Client unavailable.',
        ),
      );
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
      debugPrint('[API] Unexpected error in DELETE $path: $e');
      return ApiResponse(
        code: -1,
        message: _apiText(
          zhCN: '发生未知错误',
          zhTW: '發生未知錯誤',
          en: 'Unknown error occurred.',
        ),
      );
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
      return ApiResponse(
        code: -1,
        message: _apiText(
          zhCN: '客户端已释放',
          zhTW: '客戶端已釋放',
          en: 'Client unavailable.',
        ),
      );
    }
    try {
      final uploadTimeout = sendTimeout ?? const Duration(minutes: 5);
      final response = await _dio.post(
        path,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: uploadTimeout,
          receiveTimeout: uploadTimeout,
          extra: const <String, dynamic>{'retryServerErrors': true},
        ),
        onSendProgress: onSendProgress,
        cancelToken: cancelToken,
      );
      return _parseResponse(response, fromJson);
    } on DioException catch (e) {
      return _handleError(e);
    } catch (e) {
      debugPrint('[API] Unexpected error in UPLOAD $path: $e');
      return ApiResponse(
        code: -1,
        message: _apiText(
          zhCN: '发生未知错误',
          zhTW: '發生未知錯誤',
          en: 'Unknown error occurred.',
        ),
      );
    }
  }

  /// 解析响应（类型安全）
  ApiResponse<T> _parseResponse<T>(
    Response response,
    T Function(dynamic)? fromJson,
  ) {
    final data = response.data;
    if (data is! Map<String, dynamic>) {
      return ApiResponse(
        code: -1,
        message: _apiText(
          zhCN: '响应格式错误',
          zhTW: '響應格式錯誤',
          en: 'Invalid response format.',
        ),
      );
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
        return _apiText(
          zhCN: '消息服务暂时不可用，请稍后重试',
          zhTW: '消息服務暫時不可用，請稍後重試',
          en: 'Message service is temporarily unavailable. Please try again later.',
        );
      }
    }

    return normalized;
  }

  String? _localizedDioErrorMessage(DioExceptionType type) {
    switch (type) {
      case DioExceptionType.connectionTimeout:
        return _apiText(
          zhCN: '连接超时，请检查网络',
          zhTW: '連接超時，請檢查網絡',
          en: 'Connection timed out. Check your network.',
        );
      case DioExceptionType.sendTimeout:
        return _apiText(
          zhCN: '发送超时，请检查网络',
          zhTW: '發送超時，請檢查網絡',
          en: 'Request send timed out. Check your network.',
        );
      case DioExceptionType.receiveTimeout:
        return _apiText(
          zhCN: '服务器响应超时',
          zhTW: '服務器響應超時',
          en: 'Server response timed out.',
        );
      case DioExceptionType.badCertificate:
        return _apiText(
          zhCN: '证书验证失败',
          zhTW: '證書驗證失敗',
          en: 'Certificate validation failed.',
        );
      case DioExceptionType.connectionError:
        return _apiText(
          zhCN: '网络连接失败，请检查网络设置',
          zhTW: '網絡連接失敗，請檢查網絡設置',
          en: 'Network connection failed. Check your network settings.',
        );
      case DioExceptionType.cancel:
        return _apiText(
          zhCN: '请求已取消',
          zhTW: '請求已取消',
          en: 'Request was cancelled.',
        );
      default:
        return null;
    }
  }

  /// HTTP 状态码到消息的映射
  String? _localizedHttpStatusMessage(int statusCode) {
    switch (statusCode) {
      case 401:
        return _apiText(
          zhCN: '登录已过期，请重新登录',
          zhTW: '登入已過期，請重新登入',
          en: 'Session expired. Please log in again.',
        );
      case 403:
        return _apiText(
          zhCN: '没有权限',
          zhTW: '沒有權限',
          en: 'Permission denied.',
        );
      case 404:
        return _apiText(
          zhCN: '请求的资源不存在',
          zhTW: '請求的資源不存在',
          en: 'Requested resource not found.',
        );
      default:
        return null;
    }
  }

  /// 错误处理（使用映射表简化代码）
  ApiResponse<T> _handleError<T>(DioException e) {
    // 优先使用映射表
    final mappedMessage = _localizedDioErrorMessage(e.type);
    if (mappedMessage != null) {
      return ApiResponse(code: -1, message: mappedMessage);
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
        message: isSocketError
            ? _apiText(
                zhCN: '无法连接服务器，请检查网络',
                zhTW: '無法連接服務器，請檢查網絡',
                en: 'Unable to reach the server. Check your network.',
              )
            : _apiText(
                zhCN: '网络异常，请稍后重试',
                zhTW: '網絡異常，請稍後重試',
                en: 'Network error. Please try again later.',
              ),
      );
    }

    return ApiResponse(
      code: -1,
      message: _apiText(
        zhCN: '未知错误',
        zhTW: '未知錯誤',
        en: 'Unknown error.',
      ),
    );
  }

  /// 处理 HTTP 错误响应
  ApiResponse<T> _handleBadResponse<T>(DioException e) {
    final responseData = e.response?.data;
    if (responseData is Map<String, dynamic>) {
      final message = _sanitizeServerMessage(
        responseData['message']?.toString() ??
            _apiText(
              zhCN: '服务器错误',
              zhTW: '服務器錯誤',
              en: 'Server error.',
            ),
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
    final fallbackMessage = _localizedHttpStatusMessage(fallbackStatusCode) ??
        (fallbackStatusCode >= 500
            ? _apiText(
                zhCN: '服务器繁忙，请稍后重试',
                zhTW: '服務器繁忙，請稍後重試',
                en: 'Server is busy. Please try again later.',
              )
            : _apiText(
                zhCN: '请求失败',
                zhTW: '請求失敗',
                en: 'Request failed.',
              ));
    _maybeNotifyPhoneBindRequired(fallbackStatusCode, fallbackMessage);
    return ApiResponse(code: fallbackStatusCode, message: fallbackMessage);
  }

  void _maybeNotifyPhoneBindRequired(int code, String message) {
    final normalized = message.toLowerCase();
    if (code != 1002 &&
        (code != 403 ||
            (!message.contains('绑定手机号') &&
                !normalized.contains('bind phone') &&
                !normalized.contains('phone bind')))) {
      return;
    }
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

/// 认证信息持久化适配器。
///
/// 原生端 Token 使用系统安全存储；Web 无对应能力，只能回退到
/// SharedPreferences。用户资料另有偏好缓存供冷启动恢复，不能视为密钥材料。
class TokenStorage {
  static const String _tokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const String _userDataKey = 'auth_user_data';
  static const String _migrationCompleteKey =
      'token_storage_migration_complete_v2';
  static const bool _smokeTest = bool.fromEnvironment('GENERIC_IM_SMOKE_TEST');

  // Unsigned macOS integration-test bundles cannot access the Data Protection
  // keychain. Keep this fallback strictly scoped to compile-time smoke builds.
  static bool get _usesPreferencesOnly =>
      PlatformUtils.isWeb || (_smokeTest && PlatformUtils.isMacOS);

  // 使用安全存储来保存 token（加密）
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static Future<void> saveToken(String token) async {
    if (_usesPreferencesOnly) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      return;
    }
    await _secureStorage.write(key: _tokenKey, value: token);
  }

  static Future<String?> getToken() async {
    if (_usesPreferencesOnly) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_tokenKey);
    }
    final token = await _secureStorage.read(key: _tokenKey);
    if (token != null && token.isNotEmpty) return token;

    // 兼容旧版本：安全存储为空时才读取明文旧值，写入成功后立即删除旧副本。
    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(_tokenKey);
    if (legacyToken == null || legacyToken.isEmpty) return null;
    await _secureStorage.write(key: _tokenKey, value: legacyToken);
    await prefs.remove(_tokenKey);
    return legacyToken;
  }

  static Future<void> saveUserId(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
    if (_usesPreferencesOnly) {
      return;
    }
    await _secureStorage.write(key: _userIdKey, value: userId);
  }

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_userIdKey);
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    if (_usesPreferencesOnly) return null;
    return _secureStorage.read(key: _userIdKey);
  }

  static Future<void> saveUserData(Map<String, dynamic> userData) async {
    final value = jsonEncode(userData);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userDataKey, value);
    if (_usesPreferencesOnly) {
      return;
    }
    await _secureStorage.write(key: _userDataKey, value: value);
  }

  static Future<Map<String, dynamic>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    var value = prefs.getString(_userDataKey);
    if ((value == null || value.isEmpty) && !_usesPreferencesOnly) {
      // SharedPreferences 是启动缓存；缺失时以安全存储副本恢复并回填缓存。
      value = await _secureStorage.read(key: _userDataKey);
      if (value != null && value.isNotEmpty) {
        await prefs.setString(_userDataKey, value);
      }
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
    // 退出登录必须同时覆盖新旧存储位置，防止迁移中断后残留凭证被再次恢复。
    // 并行清除安全存储（非 Web 平台）
    if (!_usesPreferencesOnly) {
      await Future.wait([
        _secureStorage.delete(key: _tokenKey),
        _secureStorage.delete(key: _userIdKey),
        _secureStorage.delete(key: _userDataKey),
      ]);
    }

    // 并行清除 SharedPreferences（Web 平台 token/userId 也存于此）
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_tokenKey), // Web 端 token
      prefs.remove(_userIdKey), // Web 端 userId
      prefs.remove(_userDataKey),
      prefs.remove(_migrationCompleteKey),
      prefs.remove('moment_notification_last_read'),
    ]);
  }

  /// 迁移旧的 SharedPreferences token 到安全存储
  static Future<void> migrateFromSharedPreferences() async {
    if (_usesPreferencesOnly) return;
    try {
      final prefs = await SharedPreferences.getInstance();

      // 并行迁移 token 和 userId
      if (prefs.getBool(_migrationCompleteKey) == true) return;
      await Future.wait([
        _migrateKey(prefs, _tokenKey),
        _migrateKey(prefs, _userIdKey),
        _migrateKey(prefs, _userDataKey),
      ]);
      await prefs.setBool(_migrationCompleteKey, true);
    } catch (e) {
      debugPrint('[TokenStorage] Migration error: $e');
    }
  }

  /// 迁移单个 key
  static Future<void> _migrateKey(SharedPreferences prefs, String key) async {
    final oldValue = prefs.getString(key);
    if (oldValue == null || oldValue.isEmpty) return;

    final secureValue = await _secureStorage.read(key: key);
    if (secureValue == null || secureValue.isEmpty) {
      await _secureStorage.write(key: key, value: oldValue);
      await prefs.remove(key);
    }
  }
}
