// 文件用途：封装 User 对应的后端 API 请求、响应模型与错误处理。
// 核心逻辑：封装登录、注册、刷新令牌和注销请求，将服务端凭证转换为本地会话并处理失效回退。
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../i18n/app_localizations.dart';
import '../../i18n/server_message_localizer.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../e2ee/e2ee_service.dart';
import '../account_session_coordinator.dart';
import '../account_data_cleanup_service.dart';
import 'system_settings_service.dart';
import '../push_notification_service.dart';
import '../device_service.dart';
import '../offline_message_queue.dart';
import '../performance_trace_service.dart';
import 'api_client.dart';

String _authText({
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

ApiResponse<T> _localizeAuthResponseMessage<T>(
  ApiResponse<T> response, {
  String? fallbackZhCN,
  String? fallbackZhTW,
  String? fallbackEn,
}) {
  final localizedMessage = localizeServerMessage(
    response.message,
    fallbackZhCN: fallbackZhCN,
    fallbackZhTW: fallbackZhTW,
    fallbackEn: fallbackEn,
  );
  if (localizedMessage == response.message) {
    return response;
  }
  return ApiResponse(
    code: response.code,
    message: localizedMessage,
    data: response.data,
  );
}

// 关键声明：auth service 负责请求参数和响应模型的转换，统一处理鉴权错误、分页边界和服务端字段兼容。
/// 用户模型
class User {
  final String id;
  final String uuid;
  final String username;
  final String nickname;
  final String? phone;
  final String? email;
  final String? avatar;
  final String? bio;
  final String? gender;
  final String registerSource;
  final bool credentialsInitialized;
  final int status;
  final DateTime? lastSeen;
  final DateTime createdAt;
  final String? emojiAvatar; // 表情头像
  final String? nicknameColor; // 昵称颜色
  final String? profileBackgroundUrl;
  final String? profileBackground;
  final String? profileCardBackground;
  final String inviteCode; // 用户个人邀请码（10 位数字）；空表示后端尚未下发

  User({
    required this.id,
    required this.uuid,
    required this.username,
    required this.nickname,
    this.phone,
    this.email,
    this.avatar,
    this.bio,
    this.gender,
    this.registerSource = 'manual',
    this.credentialsInitialized = true,
    required this.status,
    this.lastSeen,
    required this.createdAt,
    this.emojiAvatar,
    this.nicknameColor,
    this.profileBackgroundUrl,
    this.profileBackground,
    this.profileCardBackground,
    this.inviteCode = '',
  });

  // 流程逻辑：`fromJson` 集中处理输入规范化、空值和兼容字段，输出稳定的数据结构，避免调用方重复实现边界判断。
  factory User.fromJson(Map<String, dynamic> json) {
    // 处理头像 URL，确保是完整路径
    String? avatarUrl = json['avatar'];
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
    }

    return User(
      id: json['id']?.toString() ?? '',
      uuid: json['uuid'] ?? '',
      username: json['username'] ?? '',
      nickname: json['nickname'] ?? '',
      phone: json['phone'],
      email: json['email'],
      avatar: avatarUrl,
      bio: json['bio'],
      gender: json['gender']?.toString(),
      registerSource: json['register_source']?.toString() ?? 'manual',
      credentialsInitialized: json['credentials_initialized'] != false,
      status: json['status'] ?? 1,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen']).toLocal()
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at']).toLocal()
          : DateTime.now(),
      emojiAvatar: json['emoji_avatar'],
      nicknameColor: json['nickname_color'],
      profileBackgroundUrl: json['profile_background_url'],
      profileBackground: json['profile_background'],
      profileCardBackground: json['profile_card_background'],
      inviteCode: json['invite_code']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'username': username,
      'nickname': nickname,
      'phone': phone,
      'email': email,
      'avatar': avatar,
      'bio': bio,
      'gender': gender,
      'register_source': registerSource,
      'credentials_initialized': credentialsInitialized,
      'status': status,
      'emoji_avatar': emojiAvatar,
      'nickname_color': nicknameColor,
      'profile_background_url': profileBackgroundUrl,
      'profile_background': profileBackground,
      'profile_card_background': profileCardBackground,
      'invite_code': inviteCode,
      'last_seen': lastSeen?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// 认证状态
enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class MultiDeviceLoginNotice {
  const MultiDeviceLoginNotice({required this.otherActiveDeviceCount});

  final int otherActiveDeviceCount;
}

/// 认证状态
class AuthState {
  static const Object _unset = Object();

  final AuthStatus status;
  final User? user;
  final String? token;
  final String? error;
  final MultiDeviceLoginNotice? loginNotice;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.token,
    this.error,
    this.loginNotice,
  });

  AuthState copyWith({
    AuthStatus? status,
    Object? user = _unset,
    Object? token = _unset,
    String? error,
    bool clearError = false,
    Object? loginNotice = _unset,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: identical(user, _unset) ? this.user : user as User?,
      token: identical(token, _unset) ? this.token : token as String?,
      // 仅在明确传入 error 或 clearError=true 时才覆盖，否则保留原有 error
      error: clearError ? null : (error ?? this.error),
      loginNotice: identical(loginNotice, _unset)
          ? this.loginNotice
          : loginNotice as MultiDeviceLoginNotice?,
    );
  }
}

/// 认证状态的唯一写入入口，同时负责把 token、当前账号上下文和 API 客户端保持一致。
///
/// 业务 Provider 应读取 [AuthState] 或账号协调器，不要自行根据本地 token 推断已登录。
class AuthService extends StateNotifier<AuthState> {
  static const Duration _sessionRecoveryThrottle = Duration(minutes: 3);
  static const Duration _iosDeviceMigrationTimeout = Duration(seconds: 10);

  final ApiClient _api;
  final Ref _ref;

  // 认证版本号，用于防止竞态条件
  // 每次触发登出时递增，过期的响应会被忽略
  int _authVersion = 0;
  bool _isRecoveringSession = false;
  DateTime? _lastSessionRecoveryAt;

  // 标记是否正在初始化
  bool _isInitializing = false;

  AuthService(this._api, this._ref) : super(const AuthState()) {
    // 设置 API 客户端的登出回调
    _api.onLogout = _handleTokenExpired;
    _init();
  }

  /// 处理 Token 过期（由 API 客户端触发）
  void _handleTokenExpired() {
    unawaited(
      logout(
        reason: SessionExitReason.tokenExpired,
        notifyServer: false,
      ),
    );
  }

  void _syncActiveAccount(User user) {
    // 认证成功后先发布账号上下文，账号级 Provider 和离线队列才能使用同一身份命名空间。
    final accountId = user.uuid.trim();
    if (accountId.isEmpty) return;
    _ref.read(accountSessionCoordinatorProvider.notifier).activate(accountId);
    unawaited(OfflineMessageQueue().activateAccount(accountId));
  }

  void _kickoffE2EERegistration() {
    final session = _ref.read(accountSessionCoordinatorProvider);
    if (!session.isActive) return;
    // 捕获账号 epoch，防止设置请求返回时用户已经退出或切换账号却继续注册旧账号密钥。
    final account = session.context;
    unawaited(
      Future<void>(() async {
        try {
          final settings =
              await _ref.read(systemSettingsServiceProvider).getSettings();
          final coordinator =
              _ref.read(accountSessionCoordinatorProvider.notifier);
          if (!coordinator.isCurrent(account)) return;
          if (settings.messageCryptoMode.isPlain) {
            debugPrint('[Auth] Skip eager E2EE registration in plain mode');
            return;
          }
          if (PlatformUtils.isWeb) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            if (!coordinator.isCurrent(account)) return;
          }
          await _ref.read(e2eeServiceProvider).ensureDeviceKeyRegistered();
        } catch (e) {
          debugPrint('[Auth] E2EE device registration skipped: $e');
        }
      }),
    );
  }

  Map<String, dynamic>? _decodeJwtPayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalized = base64Url.normalize(parts[1]);
      final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (e) {
      debugPrint('[Auth] Failed to decode JWT device identity: $e');
    }
    return null;
  }

  Future<String?> _migrateIOSDeviceIdentityIfNeeded(String token) async {
    if (!PlatformUtils.isIOS) return token;

    final payload = _decodeJwtPayload(token);
    final oldDeviceId = payload?['device_id']?.toString().trim() ?? '';
    if (oldDeviceId.isEmpty) return token;

    final newDeviceId = await DeviceService.getDeviceId();
    if (oldDeviceId == newDeviceId) return token;

    _api.setToken(token);
    final response = await _api.post<Map<String, dynamic>>(
      '/user/device-identity/migrate',
      data: {
        'new_device_id': newDeviceId,
        'device_type': 'ios',
        'device_name': await DeviceService.getDeviceName(),
      },
      fromJson: (data) => Map<String, dynamic>.from(data as Map),
    );
    if (!response.isSuccess || response.data == null) {
      if (response.code == 1004 || response.code == 401) {
        debugPrint(
            '[Auth] Device identity conflict; a fresh login is required');
        await TokenStorage.clear();
        _api.clearToken();
        return null;
      }
      debugPrint(
        '[Auth] Device identity migration deferred: ${response.message}',
      );
      return token;
    }

    final newToken = response.data!['token']?.toString().trim() ?? '';
    if (newToken.isEmpty) {
      debugPrint('[Auth] Device identity migration returned no token');
      return token;
    }
    await TokenStorage.saveToken(newToken);
    _api.setToken(newToken);
    try {
      _api.onAccessTokenRefreshed?.call(newToken);
    } catch (e) {
      debugPrint('[Auth] WebSocket token migration callback failed: $e');
    }
    debugPrint('[Auth] iOS device identity migrated successfully');
    return newToken;
  }

  /// Do not block the first authenticated frame on a device-identity request.
  /// The cached user is already sufficient to render the app; migration can
  /// finish in the background and update the token for subsequent requests.
  Future<void> _migrateIOSDeviceIdentityInBackground(String token) async {
    try {
      final activeToken =
          await _migrateIOSDeviceIdentityIfNeeded(token).timeout(
        _iosDeviceMigrationTimeout,
        onTimeout: () {
          debugPrint('[Auth] iOS device identity migration timed out');
          return token;
        },
      );
      if (activeToken == null) {
        await logout(
          reason: SessionExitReason.tokenExpired,
          notifyServer: false,
        );
        return;
      }

      if (activeToken != token &&
          state.status == AuthStatus.authenticated &&
          state.token == token) {
        state = state.copyWith(token: activeToken, clearError: true);
      }
    } catch (e) {
      debugPrint('[Auth] Background iOS device identity migration skipped: $e');
    }
  }

  /// 初始化 - 检查本地 Token
  Future<void> _init() async {
    if (_isInitializing) return;
    _isInitializing = true;
    final span = PerformanceTraceService.start('auth.init');

    try {
      PerformanceTraceService.mark('auth.init_start');
      // 未完成的账号删除优先于自动登录，否则崩溃恢复可能短暂暴露待清理账号的数据。
      final purgeBlocksAuthentication = await _ref
          .read(accountDataCleanupServiceProvider)
          .resumePendingPurgeBeforeAuth();
      if (purgeBlocksAuthentication) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          user: null,
          token: null,
        );
        return;
      }
      // TokenStorage.getToken() migrates legacy SharedPreferences tokens on demand.
      final tokenSpan = PerformanceTraceService.start('auth.get_token');
      final token = await TokenStorage.getToken();
      tokenSpan.finish(token == null ? 'missing' : 'hit');
      if (token != null) {
        // 有完整缓存时先恢复可渲染状态，再后台校验用户和设备身份；网络不是首屏登录态的前置条件。
        // Restore local auth state before any network-dependent iOS device
        // migration. This keeps the first launch responsive when the app has
        // a valid cached session but the network is slow or unavailable.
        _api.setToken(token);
        if (await _restoreCachedUser(token)) {
          PerformanceTraceService.mark('auth.cached_user_restored');
          PerformanceTraceService.mark(
            'auth.cached_user_restored_before_device_migration',
          );
          unawaited(_migrateIOSDeviceIdentityInBackground(token));
          _refreshCurrentUserAfterCachedRestore(token);
        } else {
          final activeToken = await _migrateIOSDeviceIdentityIfNeeded(token)
              .timeout(_iosDeviceMigrationTimeout, onTimeout: () {
            debugPrint('[Auth] iOS device identity migration timed out');
            return token;
          });
          if (activeToken == null) {
            state = state.copyWith(
              status: AuthStatus.unauthenticated,
              user: null,
              token: null,
            );
            return;
          }
          _api.setToken(activeToken);
          PerformanceTraceService.mark('auth.cached_user_missing');
          await _getCurrentUserWithToken(activeToken);
          if (state.status == AuthStatus.authenticated) {
            _kickoffE2EERegistration();
          }
        }
      } else {
        state = state.copyWith(status: AuthStatus.unauthenticated);
      }
    } catch (e) {
      debugPrint('[Auth] Init error: $e');
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: _authText(
          zhCN: '初始化失败',
          zhTW: '初始化失敗',
          en: 'Initialization failed.',
        ),
      );
    } finally {
      _isInitializing = false;
      span.finish('status=${state.status.name}');
    }
  }

  void _refreshCurrentUserAfterCachedRestore(String token) {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 1500), () async {
        if (state.token != token || state.status != AuthStatus.authenticated) {
          return;
        }

        await _getCurrentUserWithToken(token);
        if (state.token == token && state.status == AuthStatus.authenticated) {
          _kickoffE2EERegistration();
        }
      }),
    );
  }

  Future<void> ensureSessionRecoveredOnResume() async {
    // 系统恢复可能重复派发生命周期事件，节流并串行化可避免刷新 token 和设备迁移互相覆盖。
    if (_isInitializing || _isRecoveringSession) return;

    final now = DateTime.now();
    final lastCheckAt = _lastSessionRecoveryAt;
    if (lastCheckAt != null &&
        now.difference(lastCheckAt) < _sessionRecoveryThrottle) {
      return;
    }

    _lastSessionRecoveryAt = now;
    _isRecoveringSession = true;

    try {
      if (!PlatformUtils.isWeb) {
        await TokenStorage.migrateFromSharedPreferences();
      }

      var storedToken = await TokenStorage.getToken();
      if (storedToken == null || storedToken.isEmpty) {
        return;
      }

      storedToken = await _migrateIOSDeviceIdentityIfNeeded(storedToken);
      if (storedToken == null || storedToken.isEmpty) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          user: null,
          token: null,
        );
        return;
      }

      if (_api.currentToken != storedToken) {
        _api.setToken(storedToken);
      }

      if (state.status != AuthStatus.authenticated ||
          state.user == null ||
          state.token == null) {
        await _getCurrentUserWithToken(storedToken);
        if (state.status == AuthStatus.authenticated) {
          _kickoffE2EERegistration();
        }
        return;
      }

      final refreshedToken = await _api.refreshTokenSilently();
      final activeToken = (refreshedToken != null && refreshedToken.isNotEmpty)
          ? refreshedToken
          : storedToken;

      if (state.token != activeToken || state.error != null) {
        state = state.copyWith(
          status: AuthStatus.authenticated,
          token: activeToken,
          clearError: true,
        );
      }
    } catch (e) {
      debugPrint('[Auth] Session recovery on resume failed: $e');
    } finally {
      _isRecoveringSession = false;
    }
  }

  /// 获取当前用户信息（带 token）
  Future<void> _getCurrentUserWithToken(String token) async {
    // 记录当前版本号，用于检测竞态条件
    // 返回值只在认证版本未变化时生效，登出期间完成的旧请求不能重新写回已认证状态。
    final versionBeforeRequest = _authVersion;

    try {
      final response = await _api.get(
        '/user/me',
        fromJson: (data) => User.fromJson(data),
      );

      // 如果版本号变化，说明在请求期间触发了登出，忽略此响应
      if (_authVersion != versionBeforeRequest) {
        return;
      }

      if (response.isSuccess && response.data != null) {
        final user = response.data!;
        if (user.avatar != null && user.avatar!.isNotEmpty) {
          AvatarCacheManager.prefetch(user.avatar!);
        }
        await TokenStorage.saveUserId(user.uuid);
        await TokenStorage.saveUserData(user.toJson());
        _syncActiveAccount(user);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          token: token, // 关键：保存 token 到 state
        );
      } else {
        // Token 无效（保持原有行为）
        if (response.code == -1 && await _restoreCachedUser(token)) {
          return;
        }
        await logout(
          reason: SessionExitReason.tokenExpired,
          notifyServer: false,
        );
      }
    } catch (e) {
      debugPrint('[Auth] Get user with token failed: $e');
      // 区分网络异常和其他异常
      // 网络异常时保持登录状态，等待网络恢复
      final isNetworkError = e.toString().contains('SocketException') ||
          e.toString().contains('Connection') ||
          e.toString().contains('timeout') ||
          e.toString().contains('网络');

      if (isNetworkError) {
        if (await _restoreCachedUser(token)) return;
        final existingUser = state.user;
        if (existingUser != null) {
          // 运行期短时断网：保留当前用户态，避免闪退回登录页
          state = state.copyWith(
            status: AuthStatus.authenticated,
            user: existingUser,
            token: token,
          );
        } else {
          // 冷启动且无法拉取用户信息时，不进入“无用户的已登录态”
          state = state.copyWith(
            status: AuthStatus.unauthenticated,
            token: null,
            error: _authText(
              zhCN: '网络异常，请检查网络后重试',
              zhTW: '網絡異常，請檢查網絡後重試',
              en: 'Network error. Check your connection and try again.',
            ),
          );
        }
      } else {
        // 其他异常（如 token 解析失败）则登出
        await logout(
          reason: SessionExitReason.tokenExpired,
          notifyServer: false,
        );
      }
    }
  }

  /// 登录
  Future<bool> _restoreCachedUser(String token) async {
    final span = PerformanceTraceService.start('auth.restore_cached_user');
    try {
      final cached = await TokenStorage.getUserData();
      if (cached != null) {
        final user = User.fromJson(cached);
        _api.setToken(token);
        _syncActiveAccount(user);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          token: token,
          clearError: true,
        );
        span.finish('userData');
        return true;
      }

      final userId = await TokenStorage.getUserId();
      if (userId != null && userId.isNotEmpty) {
        final restoredUser = User(
          id: '',
          uuid: userId,
          username: '',
          nickname: '',
          status: 1,
          createdAt: DateTime.now(),
        );
        _syncActiveAccount(restoredUser);
        _api.setToken(token);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: restoredUser,
          token: token,
          clearError: true,
        );
        span.finish('userId');
        return true;
      }
    } catch (e) {
      debugPrint('[Auth] Restore cached user failed: $e');
    }
    span.finish('miss');
    return false;
  }

  Future<ApiResponse> login({
    required String username,
    required String password,
    required String deviceId,
    String? deviceType,
    String? deviceName,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, clearError: true);

    final response = _localizeAuthResponseMessage(
      await _api.post(
        '/auth/login',
        data: {
          'username': username,
          'password': password,
          'device_id': deviceId,
          'device_type': deviceType ?? 'ios',
          'device_name': deviceName ?? 'iPhone',
        },
      ),
      fallbackZhCN: '登录失败，请稍后重试',
      fallbackZhTW: '登入失敗，請稍後重試',
      fallbackEn: 'Login failed. Please try again later.',
    );

    debugPrint('[Auth] Login response.code: ${response.code}');
    debugPrint('[Auth] Login response.isSuccess: ${response.isSuccess}');

    if (response.code == 1001 || response.code == 1007) {
      // Device-lock and two-step challenges must not transition the app into
      // an authenticated state before the final challenge has passed.
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        clearError: true,
      );
      return response;
    }

    if (response.isSuccess && response.data != null) {
      try {
        await _applySuccessfulAuthResponse(response);
      } catch (e) {
        debugPrint('[Auth] Login finalization failed: $e');
        _api.clearToken();
        try {
          await TokenStorage.clear();
        } catch (clearError) {
          debugPrint('[Auth] Failed to clean partial login state: $clearError');
        }
        final message = _authText(
          zhCN: '登录信息保存失败，请重试',
          zhTW: '登入資訊儲存失敗，請重試',
          en: 'Could not save login information. Please try again.',
        );
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          user: null,
          token: null,
          error: message,
        );
        // 不能把服务端的成功响应继续交给页面，否则页面会误跳转。
        return ApiResponse(code: -1, message: message);
      }
    } else {
      debugPrint('[Auth] Login failed: ${response.message}');
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: _localizeAuthResponseMessage(
          response,
          fallbackEn: 'Login failed. Please try again later.',
        ).message,
      );
    }

    return response;
  }

  Future<void> _applySuccessfulAuthResponse(ApiResponse response) async {
    final raw = response.data;
    if (raw is! Map) {
      throw const FormatException('Login response data is invalid');
    }
    final data = Map<String, dynamic>.from(raw);
    final token = data['token']?.toString() ?? '';
    final rawUser = data['user'];
    if (token.isEmpty || rawUser is! Map) {
      throw const FormatException('Login token or user is missing');
    }
    final user = User.fromJson(Map<String, dynamic>.from(rawUser));
    final policy = data['multi_device_policy']?.toString() ?? '';
    final otherActiveDeviceCount =
        int.tryParse(data['other_active_device_count']?.toString() ?? '') ?? 0;
    final loginNotice = policy == 'coexist' && otherActiveDeviceCount > 0
        ? MultiDeviceLoginNotice(
            otherActiveDeviceCount: otherActiveDeviceCount,
          )
        : null;
    if (user.avatar != null && user.avatar!.isNotEmpty) {
      AvatarCacheManager.prefetch(user.avatar!);
    }
    await TokenStorage.saveToken(token);
    await TokenStorage.saveUserId(user.uuid);
    await TokenStorage.saveUserData(user.toJson());
    _api.setToken(token);
    _syncActiveAccount(user);
    state = state.copyWith(
      status: AuthStatus.authenticated,
      user: user,
      token: token,
      clearError: true,
      loginNotice: loginNotice,
    );
    _kickoffE2EERegistration();
  }

  void clearLoginNotice() {
    if (state.loginNotice == null) return;
    state = state.copyWith(loginNotice: null);
  }

  void clearError() {
    if (state.error == null) return;
    state = state.copyWith(clearError: true);
  }

  /// 使用已有 token 完成登录（二维码登录场景）
  Future<bool> loginWithToken(String token) async {
    state = state.copyWith(status: AuthStatus.loading, error: null);

    try {
      await TokenStorage.saveToken(token);
      _api.setToken(token);
      await _getCurrentUserWithToken(token);
      return state.status == AuthStatus.authenticated;
    } catch (e) {
      debugPrint('[Auth] QR login failed: $e');
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        token: null,
        user: null,
        error: _authText(
          zhCN: '二维码登录失败',
          zhTW: '二維碼登入失敗',
          en: 'QR login failed.',
        ),
      );
      return false;
    }
  }

  /// 注册
  Future<ApiResponse> register({
    required String username,
    required String password,
    required String nickname,
    String? gender,
    required String deviceId,
    String? deviceType,
    String? deviceName,
    String? inviteCode,
    String? phone,
    String? smsCode,
    String? email,
    String? emailCode,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, clearError: true);

    try {
      final data = <String, dynamic>{
        'username': username,
        'password': password,
        'nickname': nickname,
        'device_id': deviceId,
        'device_type': deviceType ?? 'ios',
        'device_name': deviceName ?? 'iPhone',
      };
      if (gender != null && gender.isNotEmpty) {
        data['gender'] = gender;
      }
      if (inviteCode != null && inviteCode.isNotEmpty) {
        data['invite_code'] = inviteCode;
      }
      if (phone != null && phone.isNotEmpty) {
        data['phone'] = phone;
        data['sms_code'] = smsCode;
      }
      if (email != null && email.isNotEmpty) {
        data['email'] = email;
        data['email_code'] = emailCode;
      }
      final response = _localizeAuthResponseMessage(
        await _api.post('/auth/register', data: data),
        fallbackZhCN: '注册失败，请稍后重试',
        fallbackZhTW: '註冊失敗，請稍後重試',
        fallbackEn: 'Registration failed. Please try again later.',
      );

      if (response.isSuccess) {
        // Registration and login return the same authentication payload.
        // Using one finalization path prevents a partially persisted session
        // from publishing an authenticated route on iOS.
        await _applySuccessfulAuthResponse(response);
      } else {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          error: _localizeAuthResponseMessage(
            response,
            fallbackEn: 'Registration failed. Please try again later.',
          ).message,
        );
      }

      return response;
    } catch (e) {
      debugPrint('[Auth] Register error: $e');
      _api.clearToken();
      try {
        await TokenStorage.clear();
      } catch (clearError) {
        debugPrint(
          '[Auth] Failed to clean partial registration state: $clearError',
        );
      }
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        user: null,
        token: null,
        error: _authText(
          zhCN: '注册失败，请稍后重试',
          zhTW: '註冊失敗，請稍後重試',
          en: 'Registration failed. Please try again later.',
        ),
      );
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '注册失败',
          zhTW: '註冊失敗',
          en: 'Registration failed.',
        ),
      );
    }
  }

  Future<ApiResponse> sendRegistrationCode(String phone) async {
    try {
      return _localizeAuthResponseMessage(
        await _api.post(
          '/auth/register/send-code',
          data: {'phone': phone},
        ),
        fallbackZhCN: '验证码发送失败，请稍后重试',
        fallbackZhTW: '驗證碼傳送失敗，請稍後重試',
        fallbackEn: 'Failed to send the verification code.',
      );
    } catch (e) {
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '验证码发送失败，请稍后重试',
          zhTW: '驗證碼傳送失敗，請稍後重試',
          en: 'Failed to send the verification code.',
        ),
      );
    }
  }

  Future<ApiResponse> verifyRegistrationCode({
    required String phone,
    required String smsCode,
  }) async {
    try {
      return _localizeAuthResponseMessage(
        await _api.post(
          '/auth/register/verify-code',
          data: {
            'phone': phone,
            'sms_code': smsCode,
          },
        ),
        fallbackZhCN: '验证码校验失败，请重试',
        fallbackZhTW: '驗證碼校驗失敗，請重試',
        fallbackEn: 'Could not verify the code. Please try again.',
      );
    } catch (_) {
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '验证码校验失败，请重试',
          zhTW: '驗證碼校驗失敗，請重試',
          en: 'Could not verify the code. Please try again.',
        ),
      );
    }
  }

  Future<ApiResponse> sendRegistrationEmailCode(String email) async {
    try {
      return _localizeAuthResponseMessage(
        await _api.post(
          '/auth/register/send-email-code',
          data: {'email': email},
        ),
        fallbackZhCN: '验证码发送失败，请稍后重试',
        fallbackZhTW: '驗證碼傳送失敗，請稍後重試',
        fallbackEn: 'Failed to send the verification code.',
      );
    } catch (_) {
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '验证码发送失败，请稍后重试',
          zhTW: '驗證碼傳送失敗，請稍後重試',
          en: 'Failed to send the verification code.',
        ),
      );
    }
  }

  /// 一键创建正式账号并直接登录
  Future<ApiResponse> quickRegister({
    required String deviceId,
    required String requestId,
    String? deviceType,
    String? deviceName,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, clearError: true);
    try {
      final response = _localizeAuthResponseMessage(
        await _api.post(
          '/auth/quick-register',
          data: {
            'device_id': deviceId,
            'device_type': deviceType ?? 'unknown',
            'device_name': deviceName ?? '',
            'request_id': requestId,
          },
        ),
        fallbackZhCN: '一键注册失败，请稍后重试',
        fallbackZhTW: '一鍵註冊失敗，請稍後重試',
        fallbackEn: 'Quick registration failed. Please try again later.',
      );
      if (response.isSuccess && response.data != null) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : Map<String, dynamic>.from(response.data as Map);
        final token = data['token']?.toString() ?? '';
        final userRaw = data['user'];
        if (token.isEmpty || userRaw == null) {
          throw const FormatException('invalid quick registration response');
        }
        final userData = userRaw is Map<String, dynamic>
            ? userRaw
            : Map<String, dynamic>.from(userRaw as Map);
        final user = User.fromJson(userData);
        await TokenStorage.saveToken(token);
        await TokenStorage.saveUserId(user.uuid);
        await TokenStorage.saveUserData(user.toJson());
        _api.setToken(token);
        _syncActiveAccount(user);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          token: token,
        );
        _kickoffE2EERegistration();
      } else {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          error: response.message,
        );
      }
      return response;
    } catch (e) {
      debugPrint('[Auth] Quick register error: $e');
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: _authText(
          zhCN: '一键注册失败，请稍后重试',
          zhTW: '一鍵註冊失敗，請稍後重試',
          en: 'Quick registration failed. Please try again later.',
        ),
      );
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '一键注册失败',
          zhTW: '一鍵註冊失敗',
          en: 'Quick registration failed.',
        ),
      );
    }
  }

  /// 发送绑定手机号验证码
  Future<ApiResponse> sendPhoneBindCode(String phone) async {
    try {
      return _localizeAuthResponseMessage(
        await _api.post(
          '/user/phone/send-bind-code',
          data: {'phone': phone},
        ),
        fallbackZhCN: '发送失败',
        fallbackZhTW: '發送失敗',
        fallbackEn: 'Send failed.',
      );
    } catch (e) {
      debugPrint('[Auth] sendPhoneBindCode: $e');
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '发送失败',
          zhTW: '發送失敗',
          en: 'Send failed.',
        ),
      );
    }
  }

  /// 绑定手机号
  Future<ApiResponse> bindPhone(String phone, {String? code}) async {
    try {
      final response = _localizeAuthResponseMessage(
        await _api.post(
          '/user/phone/bind',
          data: {'phone': phone, if (code != null) 'code': code},
        ),
        fallbackZhCN: '绑定失败',
        fallbackZhTW: '綁定失敗',
        fallbackEn: 'Binding failed.',
      );
      if (response.isSuccess) {
        await getCurrentUser();
      }
      return response;
    } catch (e) {
      debugPrint('[Auth] bindPhone: $e');
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '绑定失败',
          zhTW: '綁定失敗',
          en: 'Binding failed.',
        ),
      );
    }
  }

  Future<ApiResponse> verifyDeviceLockLogin({
    required String ticket,
    required String code,
  }) async {
    try {
      final response = _localizeAuthResponseMessage(
        await _api.post(
          '/auth/device-lock/verify',
          data: {'ticket': ticket, 'code': code},
        ),
        fallbackZhCN: '验证失败',
        fallbackZhTW: '驗證失敗',
        fallbackEn: 'Verification failed.',
      );

      if (response.code == 1007) {
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          clearError: true,
        );
        return response;
      }

      if (response.isSuccess && response.data != null) {
        await _applySuccessfulAuthResponse(response);
      }
      return response;
    } catch (e) {
      debugPrint('[Auth] verifyDeviceLockLogin: $e');
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '验证失败',
          zhTW: '驗證失敗',
          en: 'Verification failed.',
        ),
      );
    }
  }

  Future<ApiResponse> verifyTwoStepLogin({
    required String ticket,
    required String password,
  }) async {
    try {
      final response = _localizeAuthResponseMessage(
        await _api.post(
          '/auth/two-step/verify',
          data: {'ticket': ticket, 'password': password},
        ),
        fallbackZhCN: '两步验证失败',
        fallbackZhTW: '兩步驗證失敗',
        fallbackEn: 'Two-step verification failed.',
      );
      if (response.isSuccess && response.data != null) {
        await _applySuccessfulAuthResponse(response);
      } else {
        state = state.copyWith(status: AuthStatus.unauthenticated);
      }
      return response;
    } catch (e) {
      debugPrint('[Auth] verifyTwoStepLogin: $e');
      state = state.copyWith(status: AuthStatus.unauthenticated);
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '两步验证失败，请稍后重试',
          zhTW: '兩步驗證失敗，請稍後重試',
          en: 'Two-step verification failed. Please try again.',
        ),
      );
    }
  }

  Future<ApiResponse> sendPasswordChangeCode() async {
    try {
      return _localizeAuthResponseMessage(
        await _api.post('/user/password/send-change-code'),
        fallbackZhCN: '发送失败',
        fallbackZhTW: '發送失敗',
        fallbackEn: 'Send failed.',
      );
    } catch (e) {
      debugPrint('[Auth] sendPasswordChangeCode: $e');
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '发送失败',
          zhTW: '發送失敗',
          en: 'Send failed.',
        ),
      );
    }
  }

  Future<ApiResponse> changePasswordByCode({
    required String code,
    required String newPassword,
  }) async {
    try {
      return _localizeAuthResponseMessage(
        await _api.post(
          '/user/password/change-by-code',
          data: {'code': code, 'new_password': newPassword},
        ),
        fallbackZhCN: '修改失败',
        fallbackZhTW: '修改失敗',
        fallbackEn: 'Update failed.',
      );
    } catch (e) {
      debugPrint('[Auth] changePasswordByCode: $e');
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '修改失败',
          zhTW: '修改失敗',
          en: 'Update failed.',
        ),
      );
    }
  }

  Future<ApiResponse> sendPasswordResetCode(String phone) async {
    try {
      return _localizeAuthResponseMessage(
        await _api.post(
          '/auth/password/send-reset-code',
          data: {'phone': phone},
        ),
        fallbackZhCN: '发送失败',
        fallbackZhTW: '發送失敗',
        fallbackEn: 'Send failed.',
      );
    } catch (e) {
      debugPrint('[Auth] sendPasswordResetCode: $e');
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '发送失败',
          zhTW: '發送失敗',
          en: 'Send failed.',
        ),
      );
    }
  }

  Future<ApiResponse> resetPasswordByCode({
    required String phone,
    required String code,
    required String newPassword,
  }) async {
    try {
      return _localizeAuthResponseMessage(
        await _api.post(
          '/auth/password/reset-by-code',
          data: {'phone': phone, 'code': code, 'new_password': newPassword},
        ),
        fallbackZhCN: '重置失败',
        fallbackZhTW: '重置失敗',
        fallbackEn: 'Reset failed.',
      );
    } catch (e) {
      debugPrint('[Auth] resetPasswordByCode: $e');
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '重置失败',
          zhTW: '重置失敗',
          en: 'Reset failed.',
        ),
      );
    }
  }

  Future<ApiResponse> sendDeleteAccountCode() async {
    try {
      return _localizeAuthResponseMessage(
        await _api.post('/user/account/send-delete-code'),
        fallbackZhCN: '发送失败',
        fallbackZhTW: '發送失敗',
        fallbackEn: 'Send failed.',
      );
    } catch (e) {
      debugPrint('[Auth] sendDeleteAccountCode: $e');
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '发送失败',
          zhTW: '發送失敗',
          en: 'Send failed.',
        ),
      );
    }
  }

  /// 获取当前用户
  Future<void> getCurrentUser() async {
    try {
      final response = await _api.get(
        '/user/me',
        fromJson: (data) => User.fromJson(data),
      );

      if (response.isSuccess && response.data != null) {
        final user = response.data!;
        if (user.avatar != null && user.avatar!.isNotEmpty) {
          AvatarCacheManager.prefetch(user.avatar!);
        }
        await TokenStorage.saveUserId(user.uuid);
        await TokenStorage.saveUserData(user.toJson());
        _syncActiveAccount(user);
        state = state.copyWith(status: AuthStatus.authenticated, user: user);
      }
      // 不再在失败时登出，保持当前状态
    } catch (e) {
      debugPrint('[Auth] Get current user failed: $e');
      // 保持当前状态，不更新
    }
  }

  /// 修改密码
  Future<ApiResponse> changePassword({
    required String oldPassword,
    required String newPassword,
  }) async {
    try {
      final response = await _api.post(
        '/auth/change-password',
        data: {'old_password': oldPassword, 'new_password': newPassword},
      );

      return response;
    } catch (e) {
      debugPrint('[Auth] Change password failed: $e');
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '修改密码失败',
          zhTW: '修改密碼失敗',
          en: 'Failed to change password.',
        ),
      );
    }
  }

  /// 为一键注册账号设置正式登录账号和密码
  Future<ApiResponse> initializeCredentials({
    required String username,
    required String password,
  }) async {
    try {
      final response = _localizeAuthResponseMessage(
        await _api.put(
          '/auth/initialize-credentials',
          data: {'username': username, 'password': password},
        ),
        fallbackZhCN: '设置账号密码失败',
        fallbackZhTW: '設定帳號密碼失敗',
        fallbackEn: 'Failed to set sign-in credentials.',
      );
      if (response.isSuccess && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        final userRaw = data['user'];
        if (userRaw is Map) {
          final user = User.fromJson(Map<String, dynamic>.from(userRaw));
          await TokenStorage.saveUserData(user.toJson());
          _syncActiveAccount(user);
          state = state.copyWith(user: user, status: AuthStatus.authenticated);
        } else {
          await getCurrentUser();
        }
      }
      return response;
    } catch (e) {
      debugPrint('[Auth] Initialize credentials failed: $e');
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '设置账号密码失败',
          zhTW: '設定帳號密碼失敗',
          en: 'Failed to set sign-in credentials.',
        ),
      );
    }
  }

  /// 更新用户信息
  Future<ApiResponse> updateProfile({
    String? nickname,
    String? username,
    String? avatar,
    String? bio,
    String? gender,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (nickname != null) data['nickname'] = nickname;
      if (username != null) data['username'] = username;
      if (avatar != null) data['avatar'] = avatar;
      if (bio != null) data['bio'] = bio;
      if (gender != null) data['gender'] = gender;

      final response = await _api.put('/user/me', data: data);

      if (response.isSuccess && state.user != null) {
        final currentUser = state.user!;
        String? newAvatarUrl = avatar;
        if (newAvatarUrl != null && newAvatarUrl.isNotEmpty) {
          newAvatarUrl = ApiConfig.getMediaUrl(newAvatarUrl);
        }
        final finalAvatarUrl =
            avatar != null ? newAvatarUrl : currentUser.avatar;

        // 更换头像时：移除旧缓存、预取新头像，设置/个人资料等实时刷新
        if (avatar != null) {
          if (currentUser.avatar != null && currentUser.avatar!.isNotEmpty) {
            AvatarCacheManager.removeFile(currentUser.avatar!);
          }
          if (finalAvatarUrl != null && finalAvatarUrl.isNotEmpty) {
            AvatarCacheManager.prefetch(finalAvatarUrl);
          }
        }

        final updatedUser = User(
          id: currentUser.id,
          uuid: currentUser.uuid,
          username: username ?? currentUser.username,
          nickname: nickname ?? currentUser.nickname,
          phone: currentUser.phone,
          avatar: finalAvatarUrl,
          bio: bio ?? currentUser.bio,
          gender: gender ?? currentUser.gender,
          registerSource: currentUser.registerSource,
          credentialsInitialized: currentUser.credentialsInitialized,
          status: currentUser.status,
          lastSeen: currentUser.lastSeen,
          createdAt: currentUser.createdAt,
          emojiAvatar: currentUser.emojiAvatar,
          nicknameColor: currentUser.nicknameColor,
          profileBackgroundUrl: currentUser.profileBackgroundUrl,
          profileBackground: currentUser.profileBackground,
          profileCardBackground: currentUser.profileCardBackground,
        );

        state = state.copyWith(user: updatedUser);
      }

      return response;
    } catch (e) {
      debugPrint('[Auth] Update profile failed: $e');
      return ApiResponse(
        code: -1,
        message: _authText(
          zhCN: '更新资料失败',
          zhTW: '更新資料失敗',
          en: 'Failed to update profile.',
        ),
      );
    }
  }

  /// 登出。所有退出原因都通过账号协调器发布新 epoch 并执行相同的本地清理。
  Future<void> logout({
    SessionExitReason reason = SessionExitReason.manual,
    bool? notifyServer,
    String? errorMessage,
  }) async {
    // 递增版本号，使正在进行的请求响应失效
    _authVersion++;
    _isInitializing = false;
    final shouldNotifyServer =
        notifyServer ?? reason == SessionExitReason.manual;
    final coordinator = _ref.read(accountSessionCoordinatorProvider.notifier);

    // 退出顺序由协调器固定为：隔离账号任务 -> 尝试远端解绑 -> 清本地凭据 -> 发布未登录。
    await coordinator.exit(
      reason: reason,
      quarantine: (context) {
        unawaited(OfflineMessageQueue().freezeAccount(context.accountId));
      },
      remoteCleanup: shouldNotifyServer
          ? (context) async {
              final pushService = _ref.read(pushNotificationServiceProvider);
              final bindings = await pushService.buildLogoutBindings();
              final response = await _api.post<Map<String, dynamic>>(
                '/auth/logout',
                data: {'push_bindings': bindings},
                fromJson: (data) => Map<String, dynamic>.from(data as Map),
              );
              if (!response.isSuccess) {
                debugPrint('[Auth] Server logout failed: ${response.message}');
              }
            }
          : null,
      localCleanup: (context) async {
        try {
          await _ref.read(pushNotificationServiceProvider).clearToken();
        } catch (e) {
          debugPrint('[Auth] Failed to clear local push token: $e');
        }

        try {
          if (PlatformUtils.isWeb) {
            final prefs = await SharedPreferences.getInstance();
            await Future.wait([
              prefs.remove('auth_token'),
              prefs.remove('user_id'),
              prefs.remove('auth_user_data'),
              prefs.remove('moment_notification_last_read'),
            ]);
          } else {
            await TokenStorage.clear();
          }
        } catch (e) {
          debugPrint('[Auth] Failed to clear token storage: $e');
        } finally {
          _api.clearToken();
          state = AuthState(
            status: AuthStatus.unauthenticated,
            error: errorMessage ??
                (reason == SessionExitReason.tokenExpired
                    ? _authText(
                        zhCN: '登录已过期，请重新登录',
                        zhTW: '登入已過期，請重新登入',
                        en: 'Session expired. Please log in again.',
                      )
                    : null),
          );
        }
      },
    );
  }
}

/// Provider
final authServiceProvider = StateNotifierProvider<AuthService, AuthState>((
  ref,
) {
  final api = ref.watch(apiClientProvider);
  return AuthService(api, ref);
});
