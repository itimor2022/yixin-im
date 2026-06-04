import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/utils/platform_utils.dart';
import '../storage/isar_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../features/moments/providers/moment_provider.dart';
import '../e2ee/e2ee_service.dart';
import 'system_settings_service.dart';
import '../push_notification_service.dart';
import '../offline_message_queue.dart';
import 'api_client.dart';

/// 用户模型
class User {
  final String id;
  final String uuid;
  final String username;
  final String nickname;
  final String? phone;
  final String? avatar;
  final String? bio;
  final int status;
  final DateTime? lastSeen;
  final DateTime createdAt;
  final String? emojiAvatar; // 表情头像
  final String? nicknameColor; // 昵称颜色
  final String? premiumType; // 会员类型

  User({
    required this.id,
    required this.uuid,
    required this.username,
    required this.nickname,
    this.phone,
    this.avatar,
    this.bio,
    required this.status,
    this.lastSeen,
    required this.createdAt,
    this.emojiAvatar,
    this.nicknameColor,
    this.premiumType,
  });

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
      avatar: avatarUrl,
      bio: json['bio'],
      status: json['status'] ?? 1,
      lastSeen: json['last_seen'] != null
          ? DateTime.parse(json['last_seen']).toLocal()
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at']).toLocal()
          : DateTime.now(),
      emojiAvatar: json['emoji_avatar'],
      nicknameColor: json['nickname_color'],
      premiumType: json['premium_type'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'uuid': uuid,
      'username': username,
      'nickname': nickname,
      'phone': phone,
      'avatar': avatar,
      'bio': bio,
      'status': status,
      'emoji_avatar': emojiAvatar,
      'nickname_color': nicknameColor,
      'premium_type': premiumType,
      'last_seen': lastSeen?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }
}

/// 认证状态
enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

/// 认证状态
class AuthState {
  static const Object _unset = Object();

  final AuthStatus status;
  final User? user;
  final String? token;
  final String? error;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.token,
    this.error,
  });

  AuthState copyWith({
    AuthStatus? status,
    Object? user = _unset,
    Object? token = _unset,
    String? error,
    bool clearError = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: identical(user, _unset) ? this.user : user as User?,
      token: identical(token, _unset) ? this.token : token as String?,
      // 仅在明确传入 error 或 clearError=true 时才覆盖，否则保留原有 error
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// 认证服务
class AuthService extends StateNotifier<AuthState> {
  static const Duration _sessionRecoveryThrottle = Duration(minutes: 3);

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
    // 递增版本号，使正在进行的请求响应失效
    _authVersion++;
    _isInitializing = false;

    state = state.copyWith(
      status: AuthStatus.unauthenticated,
      user: null,
      token: null,
      error: '登录已过期，请重新登录',
    );
  }

  void _kickoffE2EERegistration() {
    unawaited(
      Future<void>(() async {
        try {
          final settings = await _ref
              .read(systemSettingsServiceProvider)
              .getSettings();
          if (settings.messageCryptoMode.isPlain) {
            if (kDebugMode) debugPrint('[Auth] Skip eager E2EE registration in plain mode');
            return;
          }
          if (PlatformUtils.isWeb) {
            await Future<void>.delayed(const Duration(milliseconds: 300));
          }
          await _ref.read(e2eeServiceProvider).ensureDeviceKeyRegistered();
        } catch (e) {
          if (kDebugMode) debugPrint('[Auth] E2EE device registration skipped: $e');
        }
      }),
    );
  }

  /// 初始化 - 检查本地 Token
  Future<void> _init() async {
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      // 并行执行迁移和读取 token（迁移只在首次有效，后续是空操作）
      if (!PlatformUtils.isWeb) {
        await TokenStorage.migrateFromSharedPreferences();
      }

      final token = await TokenStorage.getToken();
      if (token != null) {
        _api.setToken(token);
        // 获取用户信息，同时保存 token 到 state
        await _getCurrentUserWithToken(token);
        if (state.status == AuthStatus.authenticated) {
          _kickoffE2EERegistration();
        }
      } else {
        state = state.copyWith(status: AuthStatus.unauthenticated);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] Init error: $e');
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: '初始化失败',
      );
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> ensureSessionRecoveredOnResume() async {
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

      final storedToken = await TokenStorage.getToken();
      if (storedToken == null || storedToken.isEmpty) {
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
      if (kDebugMode) debugPrint('[Auth] Session recovery on resume failed: $e');
    } finally {
      _isRecoveringSession = false;
    }
  }

  /// 获取当前用户信息（带 token）
  Future<void> _getCurrentUserWithToken(String token) async {
    // 记录当前版本号，用于检测竞态条件
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
        await logout();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] Get user with token failed: $e');
      // 区分网络异常和其他异常
      // 网络异常时保持登录状态，等待网络恢复
      final isNetworkError =
          e.toString().contains('SocketException') ||
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
            error: '网络异常，请检查网络后重试',
          );
        }
      } else {
        // 其他异常（如 token 解析失败）则登出
        await logout();
      }
    }
  }

  /// 登录
  Future<bool> _restoreCachedUser(String token) async {
    try {
      final cached = await TokenStorage.getUserData();
      if (cached != null) {
        final user = User.fromJson(cached);
        _api.setToken(token);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          token: token,
          clearError: true,
        );
        return true;
      }

      final userId = await TokenStorage.getUserId();
      if (userId != null && userId.isNotEmpty) {
        _api.setToken(token);
        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: User(
            id: '',
            uuid: userId,
            username: '',
            nickname: '',
            status: 1,
            createdAt: DateTime.now(),
          ),
          token: token,
          clearError: true,
        );
        return true;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] Restore cached user failed: $e');
    }
    return false;
  }

  Future<ApiResponse> login({
    required String phone,
    required String password,
    required String deviceId,
    String? deviceType,
    String? deviceName,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, clearError: true);

    final response = await _api.post(
      '/auth/login',
      data: {
        'phone': phone,
        'password': password,
        'device_id': deviceId,
        'device_type': deviceType ?? 'ios',
        'device_name': deviceName ?? 'iPhone',
      },
    );

    if (kDebugMode) debugPrint('[Auth] Login response.code: ${response.code}');
    if (kDebugMode) debugPrint('[Auth] Login response.isSuccess: ${response.isSuccess}');

    if (response.code == 1001) {
      // Device lock challenge. Keep response payload for UI to continue verify flow.
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        clearError: true,
      );
      return response;
    }

    if (response.isSuccess && response.data != null) {
      try {
        final data = response.data as Map<String, dynamic>;
        final token = data['token'] as String;
        final userData = data['user'] as Map<String, dynamic>;
        final user = User.fromJson(userData);

        if (kDebugMode) debugPrint('[Auth] Login success!');

        if (user.avatar != null && user.avatar!.isNotEmpty) {
          AvatarCacheManager.prefetch(user.avatar!);
        }

        // 保存 Token
        await TokenStorage.saveToken(token);
        await TokenStorage.saveUserId(user.uuid);
        await TokenStorage.saveUserData(user.toJson());
        _api.setToken(token);

        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          token: token,
        );
        _kickoffE2EERegistration();
      } catch (e) {
        if (kDebugMode) debugPrint('[Auth] Login parse error: $e');
        state = state.copyWith(
          status: AuthStatus.unauthenticated,
          error: 'Parse error: $e',
        );
      }
    } else {
      if (kDebugMode) debugPrint('[Auth] Login failed: ${response.message}');
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: response.message,
      );
    }

    return response;
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
      if (kDebugMode) debugPrint('[Auth] QR login failed: $e');
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        token: null,
        user: null,
        error: '二维码登录失败',
      );
      return false;
    }
  }

  /// 注册
  Future<ApiResponse> register({
    required String phone,
    required String password,
    required String nickname,
    required String deviceId,
    String? deviceType,
    String? deviceName,
    String? inviteCode,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, clearError: true);

    try {
      final data = {
        'phone': phone,
        'password': password,
        'nickname': nickname,
        'device_id': deviceId,
        'device_type': deviceType ?? 'ios',
        'device_name': deviceName ?? 'iPhone',
      };
      if (inviteCode != null && inviteCode.isNotEmpty) {
        data['invite_code'] = inviteCode;
      }
      final response = await _api.post('/auth/register', data: data);

      if (response.isSuccess && response.data != null) {
        final data = response.data is Map<String, dynamic>
            ? response.data as Map<String, dynamic>
            : Map<String, dynamic>.from(response.data as Map);
        final token = data['token']?.toString() ?? '';
        final userRaw = data['user'];
        if (token.isEmpty || userRaw == null) {
          state = state.copyWith(
            status: AuthStatus.unauthenticated,
            error: '注册响应格式错误',
          );
          return ApiResponse(code: -1, message: '注册响应格式错误');
        }
        final userData = userRaw is Map<String, dynamic>
            ? userRaw
            : Map<String, dynamic>.from(userRaw as Map);
        final user = User.fromJson(userData);

        // 保存 Token
        await TokenStorage.saveToken(token);
        await TokenStorage.saveUserId(user.uuid);
        await TokenStorage.saveUserData(user.toJson());
        _api.setToken(token);

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
      if (kDebugMode) debugPrint('[Auth] Register error: $e');
      state = state.copyWith(
        status: AuthStatus.unauthenticated,
        error: '注册失败，请稍后重试',
      );
      return ApiResponse(code: -1, message: '注册失败');
    }
  }

  /// 发送绑定手机号验证码
  Future<ApiResponse> sendPhoneBindCode(String phone) async {
    try {
      return await _api.post(
        '/user/phone/send-bind-code',
        data: {'phone': phone},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] sendPhoneBindCode: $e');
      return ApiResponse(code: -1, message: '发送失败');
    }
  }

  /// 验证码绑定手机号
  Future<ApiResponse> bindPhone(String phone, String code) async {
    try {
      final response = await _api.post(
        '/user/phone/bind',
        data: {'phone': phone, 'code': code},
      );
      if (response.isSuccess) {
        await getCurrentUser();
      }
      return response;
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] bindPhone: $e');
      return ApiResponse(code: -1, message: '绑定失败');
    }
  }

  Future<ApiResponse> verifyDeviceLockLogin({
    required String ticket,
    required String code,
  }) async {
    try {
      final response = await _api.post(
        '/auth/device-lock/verify',
        data: {'ticket': ticket, 'code': code},
      );

      if (response.isSuccess && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final token = data['token'] as String;
        final userData = data['user'] as Map<String, dynamic>;
        final user = User.fromJson(userData);

        await TokenStorage.saveToken(token);
        await TokenStorage.saveUserId(user.uuid);
        await TokenStorage.saveUserData(user.toJson());
        _api.setToken(token);

        state = state.copyWith(
          status: AuthStatus.authenticated,
          user: user,
          token: token,
          clearError: true,
        );
      }
      return response;
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] verifyDeviceLockLogin: $e');
      return ApiResponse(code: -1, message: '验证失败');
    }
  }

  Future<ApiResponse> sendPasswordChangeCode() async {
    try {
      return await _api.post('/user/password/send-change-code');
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] sendPasswordChangeCode: $e');
      return ApiResponse(code: -1, message: '发送失败');
    }
  }

  Future<ApiResponse> changePasswordByCode({
    required String code,
    required String newPassword,
  }) async {
    try {
      return await _api.post(
        '/user/password/change-by-code',
        data: {'code': code, 'new_password': newPassword},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] changePasswordByCode: $e');
      return ApiResponse(code: -1, message: '修改失败');
    }
  }

  Future<ApiResponse> sendPasswordResetCode(String phone) async {
    try {
      return await _api.post(
        '/auth/password/send-reset-code',
        data: {'phone': phone},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] sendPasswordResetCode: $e');
      return ApiResponse(code: -1, message: '发送失败');
    }
  }

  Future<ApiResponse> resetPasswordByCode({
    required String phone,
    required String code,
    required String newPassword,
  }) async {
    try {
      return await _api.post(
        '/auth/password/reset-by-code',
        data: {'phone': phone, 'code': code, 'new_password': newPassword},
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] resetPasswordByCode: $e');
      return ApiResponse(code: -1, message: '重置失败');
    }
  }

  Future<ApiResponse> sendDeleteAccountCode() async {
    try {
      return await _api.post('/user/account/send-delete-code');
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] sendDeleteAccountCode: $e');
      return ApiResponse(code: -1, message: '发送失败');
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
        state = state.copyWith(status: AuthStatus.authenticated, user: user);
      }
      // 不再在失败时登出，保持当前状态
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] Get current user failed: $e');
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
      if (kDebugMode) debugPrint('[Auth] Change password failed: $e');
      return ApiResponse(code: -1, message: '修改密码失败');
    }
  }

  /// 更新用户信息
  Future<ApiResponse> updateProfile({
    String? nickname,
    String? username,
    String? avatar,
    String? bio,
  }) async {
    try {
      final data = <String, dynamic>{};
      if (nickname != null) data['nickname'] = nickname;
      if (username != null) data['username'] = username;
      if (avatar != null) data['avatar'] = avatar;
      if (bio != null) data['bio'] = bio;

      final response = await _api.put('/user/me', data: data);

      if (response.isSuccess && state.user != null) {
        final currentUser = state.user!;
        String? newAvatarUrl = avatar;
        if (newAvatarUrl != null && newAvatarUrl.isNotEmpty) {
          newAvatarUrl = ApiConfig.getMediaUrl(newAvatarUrl);
        }
        final finalAvatarUrl = avatar != null
            ? newAvatarUrl
            : currentUser.avatar;

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
          status: currentUser.status,
          lastSeen: currentUser.lastSeen,
          createdAt: currentUser.createdAt,
          emojiAvatar: currentUser.emojiAvatar,
          nicknameColor: currentUser.nicknameColor,
        );

        state = state.copyWith(user: updatedUser);
      }

      return response;
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] Update profile failed: $e');
      return ApiResponse(code: -1, message: '更新资料失败');
    }
  }

  /// 登出
  Future<void> logout() async {
    // 递增版本号，使正在进行的请求响应失效
    _authVersion++;
    _isInitializing = false;

    // 清除推送 token（在清除 API token 之前执行）
    try {
      final pushService = _ref.read(pushNotificationServiceProvider);
      await pushService.clearToken();
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] Failed to clear push token: $e');
    }

    // 重置动态状态（清除旧账号的点赞等状态）
    try {
      _ref.read(momentProvider.notifier).reset();
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] Failed to reset moment provider: $e');
    }

    // 清除 Token 存储
    try {
      if (PlatformUtils.isWeb) {
        final prefs = await SharedPreferences.getInstance();
        await Future.wait([
          prefs.remove('auth_token'),
          prefs.remove('user_id'),
          prefs.remove('moment_notification_last_read'),
          prefs.remove('recent_emojis'),
        ]);
      } else {
        await TokenStorage.clear();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] Failed to clear token storage: $e');
    }
    _api.clearToken();

    // 离线发送队列按 chatId 存储，换号后不得用新 token 代发旧账号草稿
    try {
      await OfflineMessageQueue().clear();
    } catch (e) {
      if (kDebugMode) debugPrint('[Auth] Failed to clear offline message queue: $e');
    }

    // Web 端没有初始化 Isar，跳过本地缓存清理
    if (!PlatformUtils.isWeb && IsarService.instance.isAvailable) {
      try {
        await IsarService.instance.isar.writeTxn(() async {
          await IsarService.instance.isar.clear();
        });
      } catch (e) {
        if (kDebugMode) debugPrint('[Auth] Failed to clear Isar cache: $e');
      }
    }

    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

/// Provider
final authServiceProvider = StateNotifierProvider<AuthService, AuthState>((
  ref,
) {
  final api = ref.watch(apiClientProvider);
  return AuthService(api, ref);
});
