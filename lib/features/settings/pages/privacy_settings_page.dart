// 文件用途：实现 PrivacySettingsService 页面及其交互流程，属于应用设置。
// 核心逻辑：维护 PrivacySettingsService 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/account_session_coordinator.dart';
import '../../../core/services/account_data_cleanup_service.dart';
import '../../../core/services/app_lock_service.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../shared/widgets/adaptive_settings_tile.dart';
import 'blocked_users_page.dart';
import 'devices_page.dart';
import 'settings_page.dart' show deviceCountProvider;
import '../../../shared/widgets/themed_app_bar.dart';

const _privacyVisibilityEveryone = 'everyone';
const _privacyVisibilityContacts = 'contacts';
const _privacyVisibilityNobody = 'nobody';
const _privacyAutoLockImmediate = 'immediately';
const _privacyAutoLock1Minute = '1_minute';
const _privacyAutoLock5Minutes = '5_minutes';
const _privacyAutoLock1Hour = '1_hour';
const _privacyAutoLock5Hours = '5_hours';
const _privacyAutoDelete1Month = '1_month';
const _privacyAutoDelete3Months = '3_months';
const _privacyAutoDelete6Months = '6_months';
const _privacyAutoDelete12Months = '12_months';

// 关键声明：privacy settings page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// 隐私设置服务
class PrivacySettingsService extends StateNotifier<PrivacySettings> {
  final ApiClient _apiClient;
  final String _accountId;
  bool _isDisposed = false;

  PrivacySettingsService(this._apiClient, this._accountId)
      : super(const PrivacySettings()) {
    if (_accountId.isNotEmpty) {
      _loadSettings();
    }
  }

  String _key(String name) {
    // 服务端隐私缓存按账号哈希隔离，避免把原始账号 ID 暴露在本地键名中。
    final digest = sha256.convert(utf8.encode(_accountId));
    return 'acct_v1_${digest}_$name';
  }

  bool get _canUseAccount => !_isDisposed && _accountId.isNotEmpty;

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_canUseAccount) return;
      final localSettings = PrivacySettings(
        lastSeenVisibility: _normalizePrivacyVisibility(
          prefs.getString(_key('privacy_last_seen')) ??
              _privacyVisibilityEveryone,
        ),
        phoneVisibility: _normalizePrivacyVisibility(
          prefs.getString(_key('privacy_phone')) ?? _privacyVisibilityContacts,
        ),
        groupInvitePermission: _normalizePrivacyVisibility(
          prefs.getString(_key('privacy_groups')) ?? _privacyVisibilityEveryone,
        ),
        allowPhoneSearch:
            prefs.getBool(_key('privacy_allow_phone_search')) ?? true,
        allowShortIdSearch:
            prefs.getBool(_key('privacy_allow_short_id_search')) ?? true,
        sendReadReceipts:
            prefs.getBool(_key('privacy_send_read_receipts')) ?? true,
        showTypingStatus:
            prefs.getBool(_key('privacy_show_typing_status')) ?? true,
        deviceLockEnabled: prefs.getBool(_key('privacy_device_lock')) ?? false,
        twoStepEnabled: prefs.getBool(_key('privacy_two_step')) ?? false,
        // 生物识别和应用锁是设备本地能力，不使用账号前缀，也不由服务端覆盖。
        biometricEnabled: prefs.getBool('privacy_biometric') ?? false,
        appLockEnabled: prefs.getBool('privacy_app_lock') ?? false,
        autoLockTime: _normalizeAutoLockValue(
          prefs.getString('privacy_auto_lock') ?? _privacyAutoLockImmediate,
        ),
        autoDeleteAccount: _normalizeAutoDeleteValue(
          prefs.getString(_key('privacy_auto_delete')) ??
              _privacyAutoDelete6Months,
        ),
      );
      state = localSettings;

      final response = await _apiClient.get('/user/privacy');
      if (_isDisposed) return;
      if (response.isSuccess && response.data is Map) {
        // 账号隐私以服务端响应为准；设备本地字段通过 fallback 保持原值。
        final serverSettings = PrivacySettings.fromJson(
          Map<String, dynamic>.from(response.data as Map),
          fallback: localSettings,
        );
        state = serverSettings;
        await _saveSettingsToPrefs(serverSettings);
      }
    } catch (e) {
      debugPrint('[PrivacySettings] Error loading: $e');
    }
  }

  Future<void> _saveSettingsToPrefs(PrivacySettings settings) async {
    if (!_canUseAccount) return;
    final prefs = await SharedPreferences.getInstance();
    if (!_canUseAccount) return;
    await prefs.setString(
      _key('privacy_last_seen'),
      _normalizePrivacyVisibility(settings.lastSeenVisibility),
    );
    await prefs.setString(
      _key('privacy_phone'),
      _normalizePrivacyVisibility(settings.phoneVisibility),
    );
    await prefs.setString(
      _key('privacy_groups'),
      _normalizePrivacyVisibility(settings.groupInvitePermission),
    );
    await prefs.setBool(
      _key('privacy_allow_phone_search'),
      settings.allowPhoneSearch,
    );
    await prefs.setBool(
      _key('privacy_allow_short_id_search'),
      settings.allowShortIdSearch,
    );
    await prefs.setBool(
      _key('privacy_send_read_receipts'),
      settings.sendReadReceipts,
    );
    await prefs.setBool(
      _key('privacy_show_typing_status'),
      settings.showTypingStatus,
    );
    await prefs.setBool(
        _key('privacy_device_lock'), settings.deviceLockEnabled);
    await prefs.setBool(_key('privacy_two_step'), settings.twoStepEnabled);
    await prefs.setString(
      'privacy_auto_lock',
      _normalizeAutoLockValue(settings.autoLockTime),
    );
    await prefs.setString(
      _key('privacy_auto_delete'),
      _normalizeAutoDeleteValue(settings.autoDeleteAccount),
    );
  }

  Future<void> updateLastSeenVisibility(String value) async {
    if (!_canUseAccount) return;
    final normalized = _normalizePrivacyVisibility(value);
    state = state.copyWith(lastSeenVisibility: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key('privacy_last_seen'), normalized);
    // 同步到服务器
    await _syncToServer(
      'last_seen_visibility',
      _privacyVisibilityServerValue(normalized),
    );
  }

  Future<void> updatePhoneVisibility(String value) async {
    if (!_canUseAccount) return;
    final normalized = _normalizePrivacyVisibility(value);
    state = state.copyWith(phoneVisibility: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key('privacy_phone'), normalized);
    await _syncToServer(
      'phone_visibility',
      _privacyVisibilityServerValue(normalized),
    );
  }

  Future<void> updateGroupInvitePermission(String value) async {
    if (!_canUseAccount) return;
    final normalized = _normalizePrivacyVisibility(value);
    state = state.copyWith(groupInvitePermission: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key('privacy_groups'), normalized);
    await _syncToServer(
      'group_invite_permission',
      _privacyVisibilityServerValue(normalized),
    );
  }

  Future<void> updateAllowPhoneSearch(bool value) async {
    if (!_canUseAccount) return;
    // 开关先乐观更新界面和缓存，接口失败时再同时回滚两处状态。
    final previous = state.allowPhoneSearch;
    state = state.copyWith(allowPhoneSearch: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key('privacy_allow_phone_search'), value);
    try {
      final response = await _apiClient.put(
        '/user/privacy',
        data: {'allow_phone_search': value},
      );
      if (!_canUseAccount) return;
      if (!response.isSuccess) {
        state = state.copyWith(allowPhoneSearch: previous);
        await prefs.setBool(_key('privacy_allow_phone_search'), previous);
      }
    } catch (e) {
      if (!_canUseAccount) return;
      state = state.copyWith(allowPhoneSearch: previous);
      await prefs.setBool(_key('privacy_allow_phone_search'), previous);
      debugPrint('[PrivacySettings] Sync allow_phone_search error: $e');
    }
  }

  Future<void> updateAllowShortIdSearch(bool value) async {
    if (!_canUseAccount) return;
    final previous = state.allowShortIdSearch;
    state = state.copyWith(allowShortIdSearch: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key('privacy_allow_short_id_search'), value);
    try {
      final response = await _apiClient.put(
        '/user/privacy',
        data: {'allow_short_id_search': value},
      );
      if (!_canUseAccount) return;
      if (!response.isSuccess) {
        state = state.copyWith(allowShortIdSearch: previous);
        await prefs.setBool(_key('privacy_allow_short_id_search'), previous);
      }
    } catch (e) {
      if (!_canUseAccount) return;
      state = state.copyWith(allowShortIdSearch: previous);
      await prefs.setBool(_key('privacy_allow_short_id_search'), previous);
      debugPrint('[PrivacySettings] Sync allow_short_id_search error: $e');
    }
  }

  Future<void> updateSendReadReceipts(bool value) async {
    if (!_canUseAccount) return;
    final previous = state.sendReadReceipts;
    state = state.copyWith(sendReadReceipts: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key('privacy_send_read_receipts'), value);
    try {
      final response = await _apiClient.put(
        '/user/privacy',
        data: {'send_read_receipts': value},
      );
      if (!_canUseAccount) return;
      if (!response.isSuccess) {
        state = state.copyWith(sendReadReceipts: previous);
        await prefs.setBool(_key('privacy_send_read_receipts'), previous);
      }
    } catch (e) {
      if (!_canUseAccount) return;
      state = state.copyWith(sendReadReceipts: previous);
      await prefs.setBool(_key('privacy_send_read_receipts'), previous);
      debugPrint('[PrivacySettings] Sync send_read_receipts error: $e');
    }
  }

  Future<void> updateShowTypingStatus(bool value) async {
    if (!_canUseAccount) return;
    final previous = state.showTypingStatus;
    state = state.copyWith(showTypingStatus: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key('privacy_show_typing_status'), value);
    try {
      final response = await _apiClient.put(
        '/user/privacy',
        data: {'show_typing_status': value},
      );
      if (!_canUseAccount) return;
      if (!response.isSuccess) {
        state = state.copyWith(showTypingStatus: previous);
        await prefs.setBool(_key('privacy_show_typing_status'), previous);
      }
    } catch (e) {
      if (!_canUseAccount) return;
      state = state.copyWith(showTypingStatus: previous);
      await prefs.setBool(_key('privacy_show_typing_status'), previous);
      debugPrint('[PrivacySettings] Sync show_typing_status error: $e');
    }
  }

  Future<void> updateDeviceLock(bool value) async {
    if (!_canUseAccount) return;
    state = state.copyWith(deviceLockEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key('privacy_device_lock'), value);
    try {
      await _apiClient.put(
        '/user/privacy',
        data: {'device_lock_enabled': value},
      );
    } catch (e) {
      debugPrint('[PrivacySettings] Sync device_lock_enabled error: $e');
    }
  }

  Future<ApiResponse> enableTwoStep({
    required String currentPassword,
    required String password,
    required String hint,
  }) async {
    if (!_canUseAccount) {
      return ApiResponse(code: 401, message: '账号状态无效');
    }
    try {
      final response = await _apiClient.post(
        '/user/two-step/enable',
        data: {
          'current_password': currentPassword,
          'password': password,
          'hint': hint,
        },
      );
      if (response.isSuccess && _canUseAccount) {
        state = state.copyWith(twoStepEnabled: true);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_key('privacy_two_step'), true);
        // Remove the insecure legacy client-side credential material.
        await prefs.remove(_key('two_step_password_hash'));
        await prefs.remove(_key('two_step_password_hint'));
      }
      return response;
    } catch (e) {
      debugPrint('[PrivacySettings] Enable two-step error: $e');
      return ApiResponse(code: -1, message: '开启失败，请稍后重试');
    }
  }

  Future<ApiResponse> disableTwoStep(String password) async {
    if (!_canUseAccount) {
      return ApiResponse(code: 401, message: '账号状态无效');
    }
    try {
      final response = await _apiClient.post(
        '/user/two-step/disable',
        data: {'password': password},
      );
      if (response.isSuccess && _canUseAccount) {
        state = state.copyWith(twoStepEnabled: false);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_key('privacy_two_step'), false);
        await prefs.remove(_key('two_step_password_hash'));
        await prefs.remove(_key('two_step_password_hint'));
      }
      return response;
    } catch (e) {
      debugPrint('[PrivacySettings] Disable two-step error: $e');
      return ApiResponse(code: -1, message: '关闭失败，请稍后重试');
    }
  }

  Future<void> updateBiometric(bool value) async {
    if (_isDisposed) return;
    // 应用锁相关开关只影响本机，生命周期服务会重新读取这些固定键。
    state = state.copyWith(biometricEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_biometric', value);
  }

  Future<void> updateAppLock(bool value) async {
    if (_isDisposed) return;
    state = state.copyWith(appLockEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_app_lock', value);
  }

  Future<void> updateAutoLockTime(String value) async {
    if (_isDisposed) return;
    final normalized = _normalizeAutoLockValue(value);
    state = state.copyWith(autoLockTime: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('privacy_auto_lock', normalized);
  }

  Future<void> updateAutoDeleteAccount(String value) async {
    if (!_canUseAccount) return;
    final normalized = _normalizeAutoDeleteValue(value);
    state = state.copyWith(autoDeleteAccount: normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key('privacy_auto_delete'), normalized);
    await _syncToServer(
      'auto_delete_account',
      _autoDeleteServerValue(normalized),
    );
  }

  Future<void> _syncToServer(String key, String value) async {
    if (!_canUseAccount) return;
    try {
      await _apiClient.put('/user/privacy', data: {key: value});
    } catch (e) {
      debugPrint('[PrivacySettings] Sync error: $e');
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

class PrivacySettings {
  final String lastSeenVisibility;
  final String phoneVisibility;
  final String groupInvitePermission;
  final bool allowPhoneSearch;
  final bool allowShortIdSearch;
  final bool sendReadReceipts;
  final bool showTypingStatus;
  final bool deviceLockEnabled;
  final bool twoStepEnabled;
  final bool biometricEnabled;
  final bool appLockEnabled;
  final String autoLockTime;
  final String autoDeleteAccount;

  const PrivacySettings({
    this.lastSeenVisibility = _privacyVisibilityEveryone,
    this.phoneVisibility = _privacyVisibilityContacts,
    this.groupInvitePermission = _privacyVisibilityEveryone,
    this.allowPhoneSearch = true,
    this.allowShortIdSearch = true,
    this.sendReadReceipts = true,
    this.showTypingStatus = true,
    this.deviceLockEnabled = false,
    this.twoStepEnabled = false,
    this.biometricEnabled = false,
    this.appLockEnabled = false,
    this.autoLockTime = _privacyAutoLockImmediate,
    this.autoDeleteAccount = _privacyAutoDelete6Months,
  });

  factory PrivacySettings.fromJson(
    Map<String, dynamic> json, {
    PrivacySettings fallback = const PrivacySettings(),
  }) {
    return PrivacySettings(
      lastSeenVisibility: _normalizePrivacyVisibility(
        json['last_seen_visibility']?.toString() ?? fallback.lastSeenVisibility,
      ),
      phoneVisibility: _normalizePrivacyVisibility(
        json['phone_visibility']?.toString() ?? fallback.phoneVisibility,
      ),
      groupInvitePermission: _normalizePrivacyVisibility(
        json['group_invite_permission']?.toString() ??
            fallback.groupInvitePermission,
      ),
      allowPhoneSearch: json['allow_phone_search'] is bool
          ? json['allow_phone_search'] as bool
          : fallback.allowPhoneSearch,
      allowShortIdSearch: json['allow_short_id_search'] is bool
          ? json['allow_short_id_search'] as bool
          : fallback.allowShortIdSearch,
      sendReadReceipts: json['send_read_receipts'] is bool
          ? json['send_read_receipts'] as bool
          : fallback.sendReadReceipts,
      showTypingStatus: json['show_typing_status'] is bool
          ? json['show_typing_status'] as bool
          : fallback.showTypingStatus,
      deviceLockEnabled: json['device_lock_enabled'] is bool
          ? json['device_lock_enabled'] as bool
          : fallback.deviceLockEnabled,
      twoStepEnabled: json['two_step_enabled'] is bool
          ? json['two_step_enabled'] as bool
          : fallback.twoStepEnabled,
      biometricEnabled: fallback.biometricEnabled,
      appLockEnabled: fallback.appLockEnabled,
      autoLockTime: fallback.autoLockTime,
      autoDeleteAccount: _normalizeAutoDeleteValue(
        json['auto_delete_account']?.toString() ?? fallback.autoDeleteAccount,
      ),
    );
  }

  PrivacySettings copyWith({
    String? lastSeenVisibility,
    String? phoneVisibility,
    String? groupInvitePermission,
    bool? allowPhoneSearch,
    bool? allowShortIdSearch,
    bool? sendReadReceipts,
    bool? showTypingStatus,
    bool? deviceLockEnabled,
    bool? twoStepEnabled,
    bool? biometricEnabled,
    bool? appLockEnabled,
    String? autoLockTime,
    String? autoDeleteAccount,
  }) {
    return PrivacySettings(
      lastSeenVisibility: lastSeenVisibility ?? this.lastSeenVisibility,
      phoneVisibility: phoneVisibility ?? this.phoneVisibility,
      groupInvitePermission:
          groupInvitePermission ?? this.groupInvitePermission,
      allowPhoneSearch: allowPhoneSearch ?? this.allowPhoneSearch,
      allowShortIdSearch: allowShortIdSearch ?? this.allowShortIdSearch,
      sendReadReceipts: sendReadReceipts ?? this.sendReadReceipts,
      showTypingStatus: showTypingStatus ?? this.showTypingStatus,
      deviceLockEnabled: deviceLockEnabled ?? this.deviceLockEnabled,
      twoStepEnabled: twoStepEnabled ?? this.twoStepEnabled,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      appLockEnabled: appLockEnabled ?? this.appLockEnabled,
      autoLockTime: autoLockTime ?? this.autoLockTime,
      autoDeleteAccount: autoDeleteAccount ?? this.autoDeleteAccount,
    );
  }
}

final privacySettingsProvider =
    StateNotifierProvider<PrivacySettingsService, PrivacySettings>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final accountId = ref.watch(currentAccountIdProvider);
  return PrivacySettingsService(apiClient, accountId);
});

String _privacyText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

String _privacyServerMessage(
  String? raw, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  return localizeServerMessage(
    raw,
    fallbackZhCN: zhCN,
    fallbackZhTW: zhTW,
    fallbackEn: en,
  );
}

String _normalizePrivacyVisibility(String value) {
  switch (value.trim()) {
    case _privacyVisibilityEveryone:
    case 'Everyone':
    case 'Everybody':
    case '所有人':
      return _privacyVisibilityEveryone;
    case _privacyVisibilityContacts:
    case 'Contacts':
    case 'My Contacts':
    case '联系人':
    case '聯絡人':
      return _privacyVisibilityContacts;
    case _privacyVisibilityNobody:
    case 'Nobody':
    case '无':
    case '無':
      return _privacyVisibilityNobody;
    default:
      return value.trim();
  }
}

String _privacyVisibilityServerValue(String value) {
  switch (_normalizePrivacyVisibility(value)) {
    case _privacyVisibilityEveryone:
      return '所有人';
    case _privacyVisibilityContacts:
      return '联系人';
    case _privacyVisibilityNobody:
      return '无';
    default:
      return value;
  }
}

String _privacyVisibilityLabel(BuildContext context, String value) {
  switch (_normalizePrivacyVisibility(value)) {
    case _privacyVisibilityEveryone:
      return _privacyText(
        context,
        zhCN: '所有人',
        zhTW: '所有人',
        en: 'Everybody',
      );
    case _privacyVisibilityContacts:
      return _privacyText(
        context,
        zhCN: '联系人',
        zhTW: '聯絡人',
        en: 'My Contacts',
      );
    case _privacyVisibilityNobody:
      return _privacyText(context, zhCN: '无', zhTW: '無', en: 'Nobody');
    default:
      return value;
  }
}

String _normalizeAutoLockValue(String value) {
  switch (value.trim()) {
    case _privacyAutoLockImmediate:
    case 'Immediately':
    case '立即':
      return _privacyAutoLockImmediate;
    case _privacyAutoLock1Minute:
    case '1 minute':
    case '1 分钟':
    case '1 分鐘':
      return _privacyAutoLock1Minute;
    case _privacyAutoLock5Minutes:
    case '5 minutes':
    case '5 分钟':
    case '5 分鐘':
      return _privacyAutoLock5Minutes;
    case _privacyAutoLock1Hour:
    case '1 hour':
    case '1 小时':
    case '1 小時':
      return _privacyAutoLock1Hour;
    case _privacyAutoLock5Hours:
    case '5 hours':
    case '5 小时':
    case '5 小時':
      return _privacyAutoLock5Hours;
    default:
      return value.trim();
  }
}

String _autoLockLabel(BuildContext context, String value) {
  switch (_normalizeAutoLockValue(value)) {
    case _privacyAutoLockImmediate:
      return _privacyText(context, zhCN: '立即', zhTW: '立即', en: 'Immediately');
    case _privacyAutoLock1Minute:
      return _privacyText(context, zhCN: '1 分钟', zhTW: '1 分鐘', en: '1 minute');
    case _privacyAutoLock5Minutes:
      return _privacyText(context, zhCN: '5 分钟', zhTW: '5 分鐘', en: '5 minutes');
    case _privacyAutoLock1Hour:
      return _privacyText(context, zhCN: '1 小时', zhTW: '1 小時', en: '1 hour');
    case _privacyAutoLock5Hours:
      return _privacyText(context, zhCN: '5 小时', zhTW: '5 小時', en: '5 hours');
    default:
      return value;
  }
}

String _normalizeAutoDeleteValue(String value) {
  switch (value.trim()) {
    case _privacyAutoDelete1Month:
    case '1 month':
    case '1 个月':
    case '1 個月':
      return _privacyAutoDelete1Month;
    case _privacyAutoDelete3Months:
    case '3 months':
    case '3 个月':
    case '3 個月':
      return _privacyAutoDelete3Months;
    case _privacyAutoDelete6Months:
    case '6 months':
    case '6 个月':
    case '6 個月':
      return _privacyAutoDelete6Months;
    case _privacyAutoDelete12Months:
    case '12 months':
    case '12 个月':
    case '12 個月':
      return _privacyAutoDelete12Months;
    default:
      return value.trim();
  }
}

String _autoDeleteServerValue(String value) {
  switch (_normalizeAutoDeleteValue(value)) {
    case _privacyAutoDelete1Month:
      return '1 个月';
    case _privacyAutoDelete3Months:
      return '3 个月';
    case _privacyAutoDelete6Months:
      return '6 个月';
    case _privacyAutoDelete12Months:
      return '12 个月';
    default:
      return value;
  }
}

String _autoDeleteLabel(BuildContext context, String value) {
  switch (_normalizeAutoDeleteValue(value)) {
    case _privacyAutoDelete1Month:
      return _privacyText(context, zhCN: '1 个月', zhTW: '1 個月', en: '1 month');
    case _privacyAutoDelete3Months:
      return _privacyText(context, zhCN: '3 个月', zhTW: '3 個月', en: '3 months');
    case _privacyAutoDelete6Months:
      return _privacyText(context, zhCN: '6 个月', zhTW: '6 個月', en: '6 months');
    case _privacyAutoDelete12Months:
      return _privacyText(context,
          zhCN: '12 个月', zhTW: '12 個月', en: '12 months');
    default:
      return value;
  }
}

String _privacyDeviceCountText(BuildContext context, int count) {
  final l10n = AppLocalizations.of(context);
  if (l10n.language == AppLanguage.en) {
    return count == 1 ? '1 device' : '$count devices';
  }
  return '$count ${l10n.get('devices_count')}';
}

/// 隐私和安全设置页面
class PrivacySettingsPage extends ConsumerStatefulWidget {
  final bool isDesktopPanel;

  const PrivacySettingsPage({super.key, this.isDesktopPanel = false});

  @override
  ConsumerState<PrivacySettingsPage> createState() =>
      _PrivacySettingsPageState();
}

class _PrivacySettingsPageState extends ConsumerState<PrivacySettingsPage> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _canCheckBiometrics = false;
  int _blockedUsersCount = 0;
  int _activeSessionsCount = 1;
  bool _isLoading = true;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    _loadData();
  }

  Future<void> _checkBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      final biometrics = await _localAuth.getAvailableBiometrics();
      _canCheckBiometrics = supported && canCheck && biometrics.isNotEmpty;
    } catch (e) {
      _canCheckBiometrics = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    try {
      final api = ref.read(apiClientProvider);

      // 获取已屏蔽用户数量
      final blockedResponse = await api.get<Map<String, dynamic>>(
        '/user/blocked',
      );
      if (blockedResponse.isSuccess && blockedResponse.data != null) {
        final list = blockedResponse.data!['list'] as List? ?? [];
        _blockedUsersCount = list.length;
      }

      // 复用 deviceCountProvider，避免重复请求 /user/devices
      // 会话数量通过 provider 在 build 时获取
    } catch (e) {
      debugPrint('[PrivacySettings] Load error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final settings = ref.watch(privacySettingsProvider);
    final settingsService = ref.read(privacySettingsProvider.notifier);
    // 复用 deviceCountProvider 避免重复请求
    final deviceCountAsync = ref.watch(deviceCountProvider);
    final activeSessionsCount = deviceCountAsync.when(
      data: (count) => count,
      loading: () => _activeSessionsCount,
      error: (_, __) => _activeSessionsCount,
    );

    final isLoadingDevices = deviceCountAsync.isLoading;

    // 桌面面板模式：只返回内容
    if (widget.isDesktopPanel) {
      return _buildBody(
        isDark,
        settings,
        settingsService,
        activeSessionsCount,
        isLoadingDevices,
        l10n,
      );
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D1117) : const Color(0xFFF2F2F7),
      appBar: ThemedAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.privacy,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(
        isDark,
        settings,
        settingsService,
        activeSessionsCount,
        isLoadingDevices,
        l10n,
      ),
    );
  }

  Widget _buildBody(
    bool isDark,
    PrivacySettings settings,
    PrivacySettingsService settingsService,
    int activeSessionsCount,
    bool isLoadingDevices,
    AppLocalizations l10n,
  ) {
    final currentUser = ref.watch(authServiceProvider).user;
    final onlineStatusTitle = l10n.get('online_status') ??
        _privacyText(
          context,
          zhCN: '在线状态',
          zhTW: '在線狀態',
          en: 'Online Status',
        );
    final phoneNumberTitle = l10n.get('phone_number') ??
        _privacyText(
          context,
          zhCN: '手机号',
          zhTW: '手機號',
          en: 'Phone Number',
        );
    final groupsTitle = l10n.get('groups') ??
        _privacyText(context, zhCN: '群组', zhTW: '群組', en: 'Groups');
    final securityTitle = l10n.get('security') ??
        _privacyText(context, zhCN: '安全', zhTW: '安全', en: 'Security');
    final accountTitle = l10n.get('account') ??
        _privacyText(context, zhCN: '账号', zhTW: '帳號', en: 'Account');

    return ListView(
      children: [
        const SizedBox(height: 24),

        // 隐私设置
        _SectionTitle(title: l10n.privacy, isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            if (currentUser?.credentialsInitialized == false)
              _TapTile(
                title: _privacyText(
                  context,
                  zhCN: '设置登录账号和密码',
                  zhTW: '設定登入帳號和密碼',
                  en: 'Set Sign-in Credentials',
                ),
                subtitle: _privacyText(
                  context,
                  zhCN: '设置后可在其他设备登录，避免账号丢失',
                  zhTW: '設定後可在其他裝置登入，避免帳號遺失',
                  en: 'Enable sign-in on other devices and protect your account',
                ),
                subtitleBelowTitle: true,
                titleColor: AppColors.error,
                isDark: isDark,
                onTap: _showInitializeCredentialsDialog,
              ),
            _TapTile(
              title: onlineStatusTitle,
              subtitle: _privacyVisibilityLabel(
                context,
                settings.lastSeenVisibility,
              ),
              isDark: isDark,
              onTap: () => _showPrivacyPicker(
                onlineStatusTitle,
                settings.lastSeenVisibility,
                (v) => settingsService.updateLastSeenVisibility(v),
              ),
            ),
            _TapTile(
              title: phoneNumberTitle,
              subtitle:
                  _privacyVisibilityLabel(context, settings.phoneVisibility),
              isDark: isDark,
              onTap: () => _showPrivacyPicker(
                phoneNumberTitle,
                settings.phoneVisibility,
                (v) => settingsService.updatePhoneVisibility(v),
              ),
            ),
            _TapTile(
              title: groupsTitle,
              subtitle: _privacyVisibilityLabel(
                context,
                settings.groupInvitePermission,
              ),
              isDark: isDark,
              onTap: () => _showPrivacyPicker(
                groupsTitle,
                settings.groupInvitePermission,
                (v) => settingsService.updateGroupInvitePermission(v),
                description: l10n.get('who_can_add_to_group') ??
                    _privacyText(
                      context,
                      zhCN: '谁可以将你添加到群组',
                      zhTW: '誰可以將你加入群組',
                      en: 'Who can add you to groups',
                    ),
              ),
            ),
            _SwitchTile(
              title: _privacyText(
                context,
                zhCN: '允许手机号搜索',
                zhTW: '允許手機號搜尋',
                en: 'Allow phone search',
              ),
              subtitle: _privacyText(
                context,
                zhCN: '关闭后，其他用户无法通过手机号搜索到你',
                zhTW: '關閉後，其他使用者無法透過手機號搜尋到你',
                en: 'When off, others cannot find you by phone number',
              ),
              value: settings.allowPhoneSearch,
              isDark: isDark,
              onChanged: settingsService.updateAllowPhoneSearch,
            ),
            _SwitchTile(
              title: _privacyText(
                context,
                zhCN: '允许平台短号搜索',
                zhTW: '允許平台短號搜尋',
                en: 'Allow short ID search',
              ),
              subtitle: _privacyText(
                context,
                zhCN: '关闭后，其他用户无法通过平台短号搜索到你',
                zhTW: '關閉後，其他使用者無法透過平台短號搜尋到你',
                en: 'When off, others cannot find you by short ID',
              ),
              value: settings.allowShortIdSearch,
              isDark: isDark,
              onChanged: settingsService.updateAllowShortIdSearch,
            ),
            _SwitchTile(
              title: _privacyText(
                context,
                zhCN: '发送已读回执',
                zhTW: '傳送已讀回條',
                en: 'Send read receipts',
              ),
              subtitle: _privacyText(
                context,
                zhCN: '关闭后，对方不会看到你的已读状态',
                zhTW: '關閉後，對方不會看到你的已讀狀態',
                en: 'When off, others cannot see when you read messages',
              ),
              value: settings.sendReadReceipts,
              isDark: isDark,
              onChanged: settingsService.updateSendReadReceipts,
            ),
            _SwitchTile(
              title: _privacyText(
                context,
                zhCN: '显示输入状态',
                zhTW: '顯示輸入狀態',
                en: 'Show typing status',
              ),
              subtitle: _privacyText(
                context,
                zhCN: '关闭后，其他用户不会看到你正在输入',
                zhTW: '關閉後，其他使用者不會看到你正在輸入',
                en: 'When off, others cannot see when you are typing',
              ),
              value: settings.showTypingStatus,
              isDark: isDark,
              onChanged: settingsService.updateShowTypingStatus,
            ),
          ],
        ),

        _SectionNote(
          text: l10n.get('privacy_hint') ??
              _privacyText(
                context,
                zhCN: '选择谁可以看到你的在线状态、手机号等信息',
                zhTW: '選擇誰可以看到你的在線狀態、手機號等資訊',
                en: 'Choose who can see your online status, phone number, and other info',
              ),
          isDark: isDark,
        ),

        const SizedBox(height: 24),

        // 安全
        _SectionTitle(title: securityTitle, isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            _SwitchTile(
              title: l10n.get('two_step_verification') ??
                  _privacyText(
                    context,
                    zhCN: '两步验证',
                    zhTW: '兩步驗證',
                    en: 'Two-Step Verification',
                  ),
              subtitle: l10n.get('add_extra_protection') ??
                  _privacyText(
                    context,
                    zhCN: '为账号添加额外保护',
                    zhTW: '為帳號新增額外保護',
                    en: 'Add extra protection to your account',
                  ),
              value: settings.twoStepEnabled,
              isDark: isDark,
              onChanged: (v) => _handleTwoStepChange(v, settingsService),
            ),
            _SwitchTile(
              title: _privacyText(
                context,
                zhCN: '设备锁',
                zhTW: '裝置鎖',
                en: 'Device Lock',
              ),
              subtitle: _privacyText(
                context,
                zhCN: '开启后，新设备登录需要短信验证手机号',
                zhTW: '開啟後，新裝置登入需要簡訊驗證手機號',
                en: 'When enabled, new device sign-ins require SMS verification',
              ),
              value: settings.deviceLockEnabled,
              isDark: isDark,
              onChanged: settingsService.updateDeviceLock,
            ),
            if (_canCheckBiometrics)
              _SwitchTile(
                title: l10n.get('biometric_unlock') ??
                    _privacyText(
                      context,
                      zhCN: '面容/指纹解锁',
                      zhTW: 'Face ID/指紋解鎖',
                      en: 'Face ID / Fingerprint Unlock',
                    ),
                subtitle: l10n.get('use_biometric_to_unlock') ??
                    _privacyText(
                      context,
                      zhCN: '使用生物识别解锁应用',
                      zhTW: '使用生物辨識解鎖應用程式',
                      en: 'Use biometrics to unlock the app',
                    ),
                value: settings.biometricEnabled,
                isDark: isDark,
                onChanged: (v) => _handleBiometricChange(v, settingsService),
              ),
            _TapTile(
              title: l10n.get('app_lock_password') ??
                  _privacyText(
                    context,
                    zhCN: '应用锁定密码',
                    zhTW: '應用鎖定密碼',
                    en: 'App Lock Password',
                  ),
              subtitle: settings.appLockEnabled
                  ? (l10n.get('set') ??
                      _privacyText(
                        context,
                        zhCN: '已设置',
                        zhTW: '已設定',
                        en: 'Set',
                      ))
                  : (l10n.get('not_set') ??
                      _privacyText(
                        context,
                        zhCN: '未设置',
                        zhTW: '未設定',
                        en: 'Not set',
                      )),
              isDark: isDark,
              onTap: () => _showSetPasscodeDialog(settingsService),
            ),
            _TapTile(
              title: l10n.get('auto_lock') ??
                  _privacyText(
                    context,
                    zhCN: '自动锁定',
                    zhTW: '自動鎖定',
                    en: 'Auto-Lock',
                  ),
              subtitle: _autoLockLabel(context, settings.autoLockTime),
              isDark: isDark,
              onTap: () =>
                  _showAutoLockPicker(settings.autoLockTime, settingsService),
            ),
            _TapTile(
              title: _privacyText(
                context,
                zhCN: '短信修改登录密码',
                zhTW: '簡訊修改登入密碼',
                en: 'Reset Login Password by SMS',
              ),
              subtitle: _privacyText(
                context,
                zhCN: '通过短信验证码修改',
                zhTW: '透過簡訊驗證碼修改',
                en: 'Change it with an SMS verification code',
              ),
              isDark: isDark,
              onTap: _showChangePasswordByCodeDialog,
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 已登录设备
        _SectionTitle(title: l10n.activeSessions, isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            _TapTile(
              title: l10n.activeSessions,
              subtitle: isLoadingDevices
                  ? '...'
                  : _privacyDeviceCountText(context, activeSessionsCount),
              isDark: isDark,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DevicesPage()),
              ),
            ),
            _TapTile(
              title: l10n.terminateAllOtherDevices,
              titleColor: AppColors.error,
              isDark: isDark,
              onTap: () => _showTerminateConfirm(),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 账号
        _SectionTitle(title: accountTitle, isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            _TapTile(
              title: l10n.get('auto_delete_account') ??
                  _privacyText(
                    context,
                    zhCN: '账号自动注销',
                    zhTW: '帳號自動註銷',
                    en: 'Auto-Delete Account',
                  ),
              subtitle: _autoDeleteLabel(context, settings.autoDeleteAccount),
              isDark: isDark,
              onTap: () => _showAutoDeletePicker(
                settings.autoDeleteAccount,
                settingsService,
              ),
            ),
          ],
        ),

        _SectionNote(
          text: l10n.get('auto_delete_hint') ??
              _privacyText(
                context,
                zhCN: '如果你在此期间未登录过，账号将被自动删除',
                zhTW: '如果你在此期間未登入過，帳號將被自動刪除',
                en: 'If you do not sign in during this period, your account will be deleted automatically',
              ),
          isDark: isDark,
        ),

        const SizedBox(height: 24),

        // 黑名单
        _SettingsCard(
          isDark: isDark,
          children: [
            _TapTile(
              title: l10n.get('blocked_users') ??
                  _privacyText(
                    context,
                    zhCN: '已屏蔽用户',
                    zhTW: '已封鎖使用者',
                    en: 'Blocked Users',
                  ),
              subtitle: _isLoading ? '...' : '$_blockedUsersCount',
              isDark: isDark,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const BlockedUsersPage()),
                );
                // 返回后刷新数据
                _loadData();
              },
            ),
          ],
        ),

        const SizedBox(height: 24),

        // 删除账号
        _SettingsCard(
          isDark: isDark,
          children: [
            _TapTile(
              title: l10n.get('delete_my_account') ??
                  _privacyText(
                    context,
                    zhCN: '删除我的账号',
                    zhTW: '刪除我的帳號',
                    en: 'Delete My Account',
                  ),
              titleColor: AppColors.error,
              isDark: isDark,
              onTap: () => _showDeleteAccountConfirm(),
            ),
          ],
        ),

        const SizedBox(height: 100),
      ],
    );
  }

  void _showPrivacyPicker(
    String title,
    String current,
    Function(String) onSelect, {
    String? description,
  }) {
    GlobalHaptics.selection();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final options = [
      _privacyVisibilityEveryone,
      _privacyVisibilityContacts,
      _privacyVisibilityNobody,
    ];
    final normalizedCurrent = _normalizePrivacyVisibility(current);

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                description ??
                    _privacyText(
                      context,
                      zhCN: '谁可以看到你的$title',
                      zhTW: '誰可以看到你的$title',
                      en: 'Who can see your $title',
                    ),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              ...options.map(
                (option) => ListTile(
                  title: Text(_privacyVisibilityLabel(context, option)),
                  trailing: option == normalizedCurrent
                      ? Icon(
                          Icons.check,
                          color: AppColors.controlActiveFor(context),
                        )
                      : null,
                  onTap: () {
                    GlobalHaptics.selection();
                    onSelect(option);
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _privacyText(
                            context,
                            zhCN: '已更新$title设置',
                            zhTW: '已更新$title設定',
                            en: 'Updated $title settings',
                          ),
                        ),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _handleTwoStepChange(bool value, PrivacySettingsService service) {
    if (value) {
      // 开启两步验证需要设置密码
      _showSetTwoStepPasswordDialog(service);
    } else {
      _showDisableTwoStepDialog(service);
    }
  }

  void _showDisableTwoStepDialog(PrivacySettingsService service) {
    final passwordController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _privacyText(
            dialogContext,
            zhCN: '关闭两步验证',
            zhTW: '關閉兩步驗證',
            en: 'Turn Off Two-Step Verification',
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _privacyText(
                dialogContext,
                zhCN: '请输入当前二次登录密码。只有服务端验证成功后才会关闭。',
                zhTW: '請輸入目前二次登入密碼。只有伺服器驗證成功後才會關閉。',
                en: 'Enter the current secondary sign-in password. Protection is disabled only after server verification.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                hintText: _privacyText(
                  dialogContext,
                  zhCN: '二次登录密码',
                  zhTW: '二次登入密碼',
                  en: 'Secondary sign-in password',
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              _privacyText(
                dialogContext,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              if (passwordController.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _privacyText(
                        context,
                        zhCN: '请输入正确的二次登录密码',
                        zhTW: '請輸入正確的二次登入密碼',
                        en: 'Enter the correct secondary sign-in password.',
                      ),
                    ),
                  ),
                );
                return;
              }
              final result =
                  await service.disableTwoStep(passwordController.text);
              if (!mounted || !dialogContext.mounted) return;
              if (!result.isSuccess) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(result.message),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _privacyText(
                      context,
                      zhCN: '已关闭两步验证',
                      zhTW: '已關閉兩步驗證',
                      en: 'Two-step verification turned off',
                    ),
                  ),
                ),
              );
            },
            child: Text(
              _privacyText(
                dialogContext,
                zhCN: '验证并关闭',
                zhTW: '驗證並關閉',
                en: 'Verify and Turn Off',
              ),
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    ).whenComplete(passwordController.dispose);
  }

  void _showSetTwoStepPasswordDialog(PrivacySettingsService service) {
    final currentPasswordController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final hintController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          _privacyText(
            context,
            zhCN: '设置两步验证密码',
            zhTW: '設定兩步驗證密碼',
            en: 'Set Two-Step Verification Password',
          ),
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: currentPasswordController,
              obscureText: true,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: _privacyText(
                  context,
                  zhCN: '当前账号密码',
                  zhTW: '目前帳號密碼',
                  en: 'Current Account Password',
                ),
                hintText: _privacyText(
                  context,
                  zhCN: '先验证当前账号密码',
                  zhTW: '先驗證目前帳號密碼',
                  en: 'Verify your current account password',
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              obscureText: true,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: _privacyText(
                  context,
                  zhCN: '密码',
                  zhTW: '密碼',
                  en: 'Password',
                ),
                hintText: _privacyText(
                  context,
                  zhCN: '输入两步验证密码',
                  zhTW: '輸入兩步驗證密碼',
                  en: 'Enter a password for two-step verification',
                ),
                hintStyle: TextStyle(
                  color: AppColors.inputHintFor(context),
                ),
                labelStyle: TextStyle(
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmController,
              obscureText: true,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: _privacyText(
                  context,
                  zhCN: '确认密码',
                  zhTW: '確認密碼',
                  en: 'Confirm Password',
                ),
                hintText: _privacyText(
                  context,
                  zhCN: '再次输入密码',
                  zhTW: '再次輸入密碼',
                  en: 'Enter the password again',
                ),
                hintStyle: TextStyle(
                  color: AppColors.inputHintFor(context),
                ),
                labelStyle: TextStyle(
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: hintController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: _privacyText(
                  context,
                  zhCN: '密码提示（可选）',
                  zhTW: '密碼提示（選填）',
                  en: 'Password Hint (Optional)',
                ),
                hintText: _privacyText(
                  context,
                  zhCN: '帮助你记住密码',
                  zhTW: '幫助你記住密碼',
                  en: 'Add a hint to help you remember it',
                ),
                hintStyle: TextStyle(
                  color: AppColors.inputHintFor(context),
                ),
                labelStyle: TextStyle(
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _privacyText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
              style: TextStyle(color: AppColors.textSecondaryFor(context)),
            ),
          ),
          TextButton(
            onPressed: () async {
              if (currentPasswordController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _privacyText(
                        context,
                        zhCN: '请输入当前账号密码',
                        zhTW: '請輸入目前帳號密碼',
                        en: 'Enter your current account password.',
                      ),
                    ),
                  ),
                );
                return;
              }
              if (passwordController.text.isEmpty ||
                  passwordController.text.length < 6) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  SnackBar(
                    content: Text(
                      _privacyText(
                        context,
                        zhCN: '密码至少6位',
                        zhTW: '密碼至少 6 位',
                        en: 'Password must be at least 6 characters',
                      ),
                    ),
                  ),
                );
                return;
              }
              if (passwordController.text != confirmController.text) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  SnackBar(
                    content: Text(
                      _privacyText(
                        context,
                        zhCN: '两次密码不一致',
                        zhTW: '兩次密碼不一致',
                        en: 'Passwords do not match',
                      ),
                    ),
                  ),
                );
                return;
              }
              final result = await service.enableTwoStep(
                currentPassword: currentPasswordController.text,
                password: passwordController.text,
                hint: hintController.text,
              );
              if (!mounted || !context.mounted) return;
              if (!result.isSuccess) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(result.message),
                  ),
                );
                return;
              }
              Navigator.pop(context);
              if (mounted) {
                ScaffoldMessenger.of(
                  this.context,
                ).showSnackBar(
                  SnackBar(
                    content: Text(
                      _privacyText(
                        context,
                        zhCN: '已开启两步验证',
                        zhTW: '已開啟兩步驗證',
                        en: 'Two-step verification enabled',
                      ),
                    ),
                  ),
                );
              }
            },
            child: Text(
              _privacyText(
                context,
                zhCN: '确定',
                zhTW: '確定',
                en: 'Confirm',
              ),
              style: TextStyle(color: AppColors.linkFor(context)),
            ),
          ),
        ],
      ),
    ).whenComplete(() {
      currentPasswordController.dispose();
      passwordController.dispose();
      confirmController.dispose();
      hintController.dispose();
    });
  }

  Future<void> _handleBiometricChange(
    bool value,
    PrivacySettingsService service,
  ) async {
    if (value) {
      try {
        final supported = await _localAuth.isDeviceSupported();
        final canCheck = await _localAuth.canCheckBiometrics;
        final biometrics = await _localAuth.getAvailableBiometrics();
        if (!supported || !canCheck || biometrics.isEmpty) {
          await service.updateBiometric(false);
          await ref.read(appLockServiceProvider.notifier).refreshSettings();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(_biometricUnavailableText())),
            );
          }
          return;
        }

        final authenticated = await _localAuth.authenticate(
          localizedReason: _privacyText(
            context,
            zhCN: '验证身份以启用生物识别解锁',
            zhTW: '驗證身分以啟用生物辨識解鎖',
            en: 'Verify your identity to enable biometric unlock',
          ),
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: true,
          ),
        );
        if (authenticated) {
          await service.updateBiometric(true);
          await ref.read(appLockServiceProvider.notifier).refreshSettings();
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(
              SnackBar(
                content: Text(
                  _privacyText(
                    context,
                    zhCN: '已启用生物识别解锁',
                    zhTW: '已啟用生物辨識解鎖',
                    en: 'Biometric unlock enabled',
                  ),
                ),
              ),
            );
          }
        } else {
          await service.updateBiometric(false);
          await ref.read(appLockServiceProvider.notifier).refreshSettings();
        }
      } on PlatformException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            SnackBar(
              content: Text(
                _biometricErrorText(e.code),
              ),
            ),
          );
        }
        await service.updateBiometric(false);
        await ref.read(appLockServiceProvider.notifier).refreshSettings();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            SnackBar(
              content: Text(
                _privacyText(
                  context,
                  zhCN: '生物识别验证失败',
                  zhTW: '生物辨識驗證失敗',
                  en: 'Biometric verification failed',
                ),
              ),
            ),
          );
        }
        await service.updateBiometric(false);
        await ref.read(appLockServiceProvider.notifier).refreshSettings();
      }
    } else {
      await service.updateBiometric(false);
      await ref.read(appLockServiceProvider.notifier).refreshSettings();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            _privacyText(
              context,
              zhCN: '已关闭生物识别解锁',
              zhTW: '已關閉生物辨識解鎖',
              en: 'Biometric unlock turned off',
            ),
          ),
        ),
      );
    }
  }

  String _biometricUnavailableText() {
    return _privacyText(
      context,
      zhCN: '当前设备未启用面容或指纹，请先在系统设置中录入',
      zhTW: '目前裝置未啟用 Face ID 或指紋，請先在系統設定中錄入',
      en: 'Set up Face ID or fingerprint in system settings first',
    );
  }

  String _biometricErrorText(String code) {
    switch (code) {
      case auth_error.notAvailable:
        return _privacyText(
          context,
          zhCN: '当前设备不支持生物识别',
          zhTW: '目前裝置不支援生物辨識',
          en: 'This device does not support biometrics',
        );
      case auth_error.notEnrolled:
        return _biometricUnavailableText();
      case auth_error.passcodeNotSet:
        return _privacyText(
          context,
          zhCN: '请先设置系统锁屏密码',
          zhTW: '請先設定系統鎖屏密碼',
          en: 'Set a device passcode first',
        );
      case auth_error.lockedOut:
        return _privacyText(
          context,
          zhCN: '尝试次数过多，请稍后再试',
          zhTW: '嘗試次數過多，請稍後再試',
          en: 'Too many attempts. Try again later',
        );
      case auth_error.permanentlyLockedOut:
        return _privacyText(
          context,
          zhCN: '生物识别已被系统锁定，请先使用系统密码解锁',
          zhTW: '生物辨識已被系統鎖定，請先使用系統密碼解鎖',
          en: 'Biometrics are locked. Unlock with your device passcode first',
        );
      case auth_error.biometricOnlyNotSupported:
        return _privacyText(
          context,
          zhCN: '当前平台不支持仅使用生物识别',
          zhTW: '目前平台不支援僅使用生物辨識',
          en: 'This platform does not support biometric-only authentication',
        );
      default:
        return _privacyText(
          context,
          zhCN: '生物识别验证失败',
          zhTW: '生物辨識驗證失敗',
          en: 'Biometric verification failed',
        );
    }
  }

  void _showSetPasscodeDialog(PrivacySettingsService service) {
    final currentPasscodeController = TextEditingController();
    final passcodeController = TextEditingController();
    final confirmController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = ref.read(appLockServiceProvider).hasPasscode;

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          isEditing
              ? _privacyText(
                  context,
                  zhCN: '修改锁定密码',
                  zhTW: '修改鎖定密碼',
                  en: 'Change App Lock Password',
                )
              : _privacyText(
                  context,
                  zhCN: '设置应用锁定密码',
                  zhTW: '設定應用鎖定密碼',
                  en: 'Set App Lock Password',
                ),
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isEditing) ...[
              TextField(
                controller: currentPasscodeController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: _privacyText(
                    context,
                    zhCN: '当前密码',
                    zhTW: '目前密碼',
                    en: 'Current Password',
                  ),
                  hintText: _privacyText(
                    context,
                    zhCN: '输入当前6位密码',
                    zhTW: '輸入目前 6 位密碼',
                    en: 'Enter the current 6-digit password',
                  ),
                  counterStyle: TextStyle(
                    color: AppColors.textTertiaryFor(context),
                  ),
                  hintStyle: TextStyle(
                    color: AppColors.inputHintFor(context),
                  ),
                  labelStyle: TextStyle(
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: passcodeController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: _privacyText(
                  context,
                  zhCN: '密码',
                  zhTW: '密碼',
                  en: 'Password',
                ),
                hintText: _privacyText(
                  context,
                  zhCN: '输入6位数字密码',
                  zhTW: '輸入 6 位數字密碼',
                  en: 'Enter a 6-digit numeric password',
                ),
                counterStyle: TextStyle(
                  color: AppColors.textTertiaryFor(context),
                ),
                hintStyle: TextStyle(
                  color: AppColors.inputHintFor(context),
                ),
                labelStyle: TextStyle(
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: _privacyText(
                  context,
                  zhCN: '确认密码',
                  zhTW: '確認密碼',
                  en: 'Confirm Password',
                ),
                hintText: _privacyText(
                  context,
                  zhCN: '再次输入密码',
                  zhTW: '再次輸入密碼',
                  en: 'Enter the password again',
                ),
                counterStyle: TextStyle(
                  color: AppColors.textTertiaryFor(context),
                ),
                hintStyle: TextStyle(
                  color: AppColors.inputHintFor(context),
                ),
                labelStyle: TextStyle(
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _privacyText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
              style: TextStyle(color: AppColors.textSecondaryFor(context)),
            ),
          ),
          if (isEditing)
            TextButton(
              onPressed: () async {
                final currentMatches = await ref
                    .read(appLockServiceProvider.notifier)
                    .matchesStoredPasscode(currentPasscodeController.text);
                if (!currentMatches) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _privacyText(
                          context,
                          zhCN: '当前密码不正确',
                          zhTW: '目前密碼不正確',
                          en: 'Current password is incorrect',
                        ),
                      ),
                    ),
                  );
                  return;
                }
                if (!context.mounted) return;
                Navigator.pop(context);
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('app_lock_passcode_hash');
                await service.updateAppLock(false);
                await ref
                    .read(appLockServiceProvider.notifier)
                    .refreshSettings();
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        _privacyText(
                          context,
                          zhCN: '已移除锁定密码',
                          zhTW: '已移除鎖定密碼',
                          en: 'App lock password removed',
                        ),
                      ),
                    ),
                  );
                }
              },
              child: Text(
                _privacyText(
                  context,
                  zhCN: '移除密码',
                  zhTW: '移除密碼',
                  en: 'Remove Password',
                ),
                style: TextStyle(color: AppColors.error),
              ),
            ),
          TextButton(
            onPressed: () async {
              if (!isValidAppLockPasscode(passcodeController.text)) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  SnackBar(
                    content: Text(
                      _privacyText(
                        context,
                        zhCN: '请输入6位数字密码',
                        zhTW: '請輸入 6 位數字密碼',
                        en: 'Please enter a 6-digit numeric password',
                      ),
                    ),
                  ),
                );
                return;
              }
              if (isEditing) {
                final currentMatches = await ref
                    .read(appLockServiceProvider.notifier)
                    .matchesStoredPasscode(currentPasscodeController.text);
                if (!currentMatches) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _privacyText(
                          context,
                          zhCN: '当前密码不正确',
                          zhTW: '目前密碼不正確',
                          en: 'Current password is incorrect',
                        ),
                      ),
                    ),
                  );
                  return;
                }
              }
              if (passcodeController.text != confirmController.text) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  SnackBar(
                    content: Text(
                      _privacyText(
                        context,
                        zhCN: '两次密码不一致',
                        zhTW: '兩次密碼不一致',
                        en: 'Passwords do not match',
                      ),
                    ),
                  ),
                );
                return;
              }
              Navigator.pop(context);

              // 加密存储密码
              final hash = hashAppLockPasscode(passcodeController.text);
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('app_lock_passcode_hash', hash);

              await service.updateAppLock(true);
              await ref.read(appLockServiceProvider.notifier).refreshSettings();
              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  SnackBar(
                    content: Text(
                      _privacyText(
                        context,
                        zhCN: '已设置锁定密码',
                        zhTW: '已設定鎖定密碼',
                        en: 'App lock password set',
                      ),
                    ),
                  ),
                );
              }
            },
            child: Text(
              _privacyText(
                context,
                zhCN: '确定',
                zhTW: '確定',
                en: 'Confirm',
              ),
              style: TextStyle(color: AppColors.linkFor(context)),
            ),
          ),
        ],
      ),
    ).whenComplete(() {
      currentPasscodeController.dispose();
      passcodeController.dispose();
      confirmController.dispose();
    });
  }

  void _showAutoLockPicker(String current, PrivacySettingsService service) {
    GlobalHaptics.selection();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final options = [
      _privacyAutoLockImmediate,
      _privacyAutoLock1Minute,
      _privacyAutoLock5Minutes,
      _privacyAutoLock1Hour,
      _privacyAutoLock5Hours,
    ];
    final normalizedCurrent = _normalizeAutoLockValue(current);

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                _privacyText(
                  context,
                  zhCN: '自动锁定时间',
                  zhTW: '自動鎖定時間',
                  en: 'Auto-Lock Time',
                ),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              ...options.map(
                (option) => ListTile(
                  title: Text(_autoLockLabel(context, option)),
                  trailing: option == normalizedCurrent
                      ? Icon(
                          Icons.check,
                          color: AppColors.controlActiveFor(context),
                        )
                      : null,
                  onTap: () {
                    GlobalHaptics.selection();
                    service.updateAutoLockTime(option);
                    Navigator.pop(context);
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showInitializeCredentialsDialog() {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isSubmitting = false;
    String? errorText;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            _privacyText(
              context,
              zhCN: '设置登录账号和密码',
              zhTW: '設定登入帳號和密碼',
              en: 'Set Sign-in Credentials',
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameController,
                  enabled: !isSubmitting,
                  autocorrect: false,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
                    LengthLimitingTextInputFormatter(20),
                  ],
                  decoration: InputDecoration(
                    labelText: _privacyText(
                      context,
                      zhCN: '登录账号',
                      zhTW: '登入帳號',
                      en: 'Username',
                    ),
                    hintText: _privacyText(
                      context,
                      zhCN: '3-20位字母、数字或下划线',
                      zhTW: '3-20位字母、數字或底線',
                      en: '3-20 letters, numbers, or underscores',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  enabled: !isSubmitting,
                  obscureText: true,
                  inputFormatters: [LengthLimitingTextInputFormatter(20)],
                  decoration: InputDecoration(
                    labelText: _privacyText(
                      context,
                      zhCN: '登录密码',
                      zhTW: '登入密碼',
                      en: 'Password',
                    ),
                    hintText: _privacyText(
                      context,
                      zhCN: '6-20位',
                      zhTW: '6-20位',
                      en: '6-20 characters',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  enabled: !isSubmitting,
                  obscureText: true,
                  inputFormatters: [LengthLimitingTextInputFormatter(20)],
                  decoration: InputDecoration(
                    labelText: _privacyText(
                      context,
                      zhCN: '确认密码',
                      zhTW: '確認密碼',
                      en: 'Confirm Password',
                    ),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 12),
                  Text(errorText!,
                      style: const TextStyle(color: AppColors.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed:
                  isSubmitting ? null : () => Navigator.pop(dialogContext),
              child: Text(AppLocalizations.of(context).cancel),
            ),
            FilledButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final username = usernameController.text.trim();
                      final password = passwordController.text;
                      if (username.length < 3 ||
                          !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
                        setDialogState(() => errorText = _privacyText(
                              context,
                              zhCN: '账号需为3-20位字母、数字或下划线',
                              zhTW: '帳號需為3-20位字母、數字或底線',
                              en: 'Use 3-20 letters, numbers, or underscores',
                            ));
                        return;
                      }
                      if (password.length < 6 || password.length > 20) {
                        setDialogState(() => errorText = _privacyText(
                              context,
                              zhCN: '密码需为6-20位',
                              zhTW: '密碼需為6-20位',
                              en: 'Password must be 6-20 characters',
                            ));
                        return;
                      }
                      if (password != confirmController.text) {
                        setDialogState(() => errorText = _privacyText(
                              context,
                              zhCN: '两次输入的密码不一致',
                              zhTW: '兩次輸入的密碼不一致',
                              en: 'Passwords do not match',
                            ));
                        return;
                      }
                      setDialogState(() {
                        isSubmitting = true;
                        errorText = null;
                      });
                      final result = await ref
                          .read(authServiceProvider.notifier)
                          .initializeCredentials(
                              username: username, password: password);
                      if (!dialogContext.mounted) return;
                      if (result.isSuccess) {
                        Navigator.pop(dialogContext);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(_privacyText(
                              context,
                              zhCN: '登录账号和密码设置成功',
                              zhTW: '登入帳號和密碼設定成功',
                              en: 'Sign-in credentials saved',
                            )),
                          ),
                        );
                        return;
                      }
                      setDialogState(() {
                        isSubmitting = false;
                        errorText = result.message;
                      });
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_privacyText(
                      context,
                      zhCN: '保存',
                      zhTW: '儲存',
                      en: 'Save',
                    )),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      usernameController.dispose();
      passwordController.dispose();
      confirmController.dispose();
    });
  }

  void _showChangePasswordByCodeDialog() {
    final codeController = TextEditingController();
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isSending = false;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            _privacyText(
              context,
              zhCN: '短信修改登录密码',
              zhTW: '簡訊修改登入密碼',
              en: 'Reset Login Password by SMS',
            ),
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      decoration: InputDecoration(
                        labelText: _privacyText(
                          context,
                          zhCN: '验证码',
                          zhTW: '驗證碼',
                          en: 'Verification Code',
                        ),
                        hintText: _privacyText(
                          context,
                          zhCN: '输入短信验证码',
                          zhTW: '輸入簡訊驗證碼',
                          en: 'Enter the SMS verification code',
                        ),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: isSending
                        ? null
                        : () async {
                            setStateDialog(() => isSending = true);
                            final auth = ref.read(authServiceProvider.notifier);
                            final resp = await auth.sendPasswordChangeCode();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _privacyServerMessage(
                                      resp.message,
                                      zhCN: '验证码发送失败',
                                      zhTW: '驗證碼發送失敗',
                                      en: 'Failed to send the verification code',
                                    ),
                                  ),
                                ),
                              );
                            }
                            setStateDialog(() => isSending = false);
                          },
                    child: Text(
                      isSending
                          ? _privacyText(
                              context,
                              zhCN: '发送中...',
                              zhTW: '發送中...',
                              en: 'Sending...',
                            )
                          : _privacyText(
                              context,
                              zhCN: '发送验证码',
                              zhTW: '發送驗證碼',
                              en: 'Send Code',
                            ),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: passwordController,
                obscureText: true,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: _privacyText(
                    context,
                    zhCN: '新密码',
                    zhTW: '新密碼',
                    en: 'New Password',
                  ),
                  hintText: _privacyText(
                    context,
                    zhCN: '至少6位',
                    zhTW: '至少 6 位',
                    en: 'At least 6 characters',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmController,
                obscureText: true,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  labelText: _privacyText(
                    context,
                    zhCN: '确认新密码',
                    zhTW: '確認新密碼',
                    en: 'Confirm New Password',
                  ),
                  hintText: _privacyText(
                    context,
                    zhCN: '再次输入新密码',
                    zhTW: '再次輸入新密碼',
                    en: 'Enter the new password again',
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
              child: Text(
                _privacyText(
                  context,
                  zhCN: '取消',
                  zhTW: '取消',
                  en: 'Cancel',
                ),
              ),
            ),
            TextButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final code = codeController.text.trim();
                      final pwd = passwordController.text.trim();
                      final confirm = confirmController.text.trim();
                      if (code.isEmpty ||
                          pwd.length < 6 ||
                          confirm.length < 6) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _privacyText(
                                context,
                                zhCN: '请完整填写验证码和新密码',
                                zhTW: '請完整填寫驗證碼和新密碼',
                                en: 'Please complete the verification code and new password',
                              ),
                            ),
                          ),
                        );
                        return;
                      }
                      if (pwd != confirm) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              _privacyText(
                                context,
                                zhCN: '两次输入的新密码不一致',
                                zhTW: '兩次輸入的新密碼不一致',
                                en: 'The two new passwords do not match',
                              ),
                            ),
                          ),
                        );
                        return;
                      }
                      setStateDialog(() => isSubmitting = true);
                      final auth = ref.read(authServiceProvider.notifier);
                      final resp = await auth.changePasswordByCode(
                        code: code,
                        newPassword: pwd,
                      );
                      if (!mounted) return;
                      setStateDialog(() => isSubmitting = false);
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(
                        SnackBar(
                          content: Text(
                            _privacyServerMessage(
                              resp.message,
                              zhCN: '密码修改失败',
                              zhTW: '密碼修改失敗',
                              en: 'Failed to change the password',
                            ),
                          ),
                        ),
                      );
                      if (resp.isSuccess) {
                        Navigator.pop(context);
                        await ref.read(authServiceProvider.notifier).logout();
                        if (mounted) {
                          context.go('/login');
                        }
                      }
                    },
              child: Text(
                isSubmitting
                    ? _privacyText(
                        context,
                        zhCN: '提交中...',
                        zhTW: '提交中...',
                        en: 'Submitting...',
                      )
                    : _privacyText(
                        context,
                        zhCN: '确认修改',
                        zhTW: '確認修改',
                        en: 'Confirm Change',
                      ),
                style: TextStyle(color: AppColors.linkFor(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAutoDeletePicker(String current, PrivacySettingsService service) {
    GlobalHaptics.selection();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final options = [
      _privacyAutoDelete1Month,
      _privacyAutoDelete3Months,
      _privacyAutoDelete6Months,
      _privacyAutoDelete12Months,
    ];
    final normalizedCurrent = _normalizeAutoDeleteValue(current);

    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              Text(
                _privacyText(
                  context,
                  zhCN: '账号自动注销时间',
                  zhTW: '帳號自動註銷時間',
                  en: 'Auto-Delete Account Time',
                ),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              ...options.map(
                (option) => ListTile(
                  title: Text(_autoDeleteLabel(context, option)),
                  trailing: option == normalizedCurrent
                      ? Icon(
                          Icons.check,
                          color: AppColors.controlActiveFor(context),
                        )
                      : null,
                  onTap: () {
                    GlobalHaptics.selection();
                    service.updateAutoDeleteAccount(option);
                    Navigator.pop(context);
                    final optionLabel = _autoDeleteLabel(context, option);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          _privacyText(
                            context,
                            zhCN: '账号将在 $optionLabel 不活跃后自动注销',
                            zhTW: '帳號將在 $optionLabel 不活躍後自動註銷',
                            en: 'Your account will be auto-deleted after $optionLabel of inactivity',
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showTerminateConfirm() {
    GlobalHaptics.medium();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _privacyText(
            context,
            zhCN: '终止所有其他会话',
            zhTW: '終止所有其他工作階段',
            en: 'End All Other Sessions',
          ),
        ),
        content: Text(
          _privacyText(
            context,
            zhCN: '确定要登出其他所有设备吗？这将终止除当前设备外的所有登录会话。',
            zhTW: '確定要登出其他所有裝置嗎？這將終止目前裝置以外的所有登入工作階段。',
            en: 'Sign out all other devices? This will end every login session except the current one.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _privacyText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final api = ref.read(apiClientProvider);
                final response = await api.post(
                  '/user/sessions/terminate-others',
                );
                if (response.isSuccess) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        _privacyText(
                          context,
                          zhCN: '已终止所有其他会话',
                          zhTW: '已終止所有其他工作階段',
                          en: 'All other sessions ended',
                        ),
                      ),
                    ),
                  );
                  // 刷新设备数量 provider
                  ref.invalidate(deviceCountProvider);
                } else {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        _privacyServerMessage(
                          response.message,
                          zhCN: '操作失败，请重试',
                          zhTW: '操作失敗，請重試',
                          en: 'Operation failed. Please try again.',
                        ),
                      ),
                    ),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  SnackBar(
                    content: Text(
                      _privacyText(
                        context,
                        zhCN: '操作失败，请重试',
                        zhTW: '操作失敗，請重試',
                        en: 'Operation failed, please try again',
                      ),
                    ),
                  ),
                );
              }
            },
            child: Text(
              _privacyText(
                context,
                zhCN: '终止',
                zhTW: '終止',
                en: 'End',
              ),
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountConfirm() {
    GlobalHaptics.medium();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          _privacyText(
            context,
            zhCN: '删除账号',
            zhTW: '刪除帳號',
            en: 'Delete Account',
          ),
        ),
        content: Text(
          _privacyText(
            context,
            zhCN: '⚠️ 警告：此操作不可逆！\n\n删除账号后，你的所有聊天记录、群组、频道等数据将被永久删除，无法恢复。',
            zhTW: '⚠️ 警告：此操作不可逆！\n\n刪除帳號後，你的所有聊天記錄、群組、頻道等資料將被永久刪除，無法恢復。',
            en: '⚠️ Warning: This action cannot be undone!\n\nAfter deletion, all chats, groups, channels, and related data will be permanently removed and cannot be recovered.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _privacyText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // 显示二次确认
              _showFinalDeleteConfirm();
            },
            child: Text(
              _privacyText(
                context,
                zhCN: '继续',
                zhTW: '繼續',
                en: 'Continue',
              ),
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  void _showFinalDeleteConfirm() {
    final confirmController = TextEditingController();
    final codeController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isSending = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            _privacyText(
              context,
              zhCN: '确认删除',
              zhTW: '確認刪除',
              en: 'Confirm Deletion',
            ),
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _privacyText(
                  context,
                  zhCN: '请输入 "DELETE" 和短信验证码确认删除账号',
                  zhTW: '請輸入 "DELETE" 和簡訊驗證碼確認刪除帳號',
                  en: 'Enter "DELETE" and the SMS verification code to confirm account deletion',
                ),
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: _privacyText(
                    context,
                    zhCN: '输入 DELETE',
                    zhTW: '輸入 DELETE',
                    en: 'Type DELETE',
                  ),
                  hintStyle: TextStyle(
                    color: AppColors.inputHintFor(context),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: codeController,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      decoration: InputDecoration(
                        hintText: _privacyText(
                          context,
                          zhCN: '短信验证码',
                          zhTW: '簡訊驗證碼',
                          en: 'SMS verification code',
                        ),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: isSending
                        ? null
                        : () async {
                            setStateDialog(() => isSending = true);
                            final auth = ref.read(authServiceProvider.notifier);
                            final resp = await auth.sendDeleteAccountCode();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _privacyServerMessage(
                                      resp.message,
                                      zhCN: '验证码发送失败',
                                      zhTW: '驗證碼發送失敗',
                                      en: 'Failed to send the verification code',
                                    ),
                                  ),
                                ),
                              );
                            }
                            setStateDialog(() => isSending = false);
                          },
                    child: Text(
                      isSending
                          ? _privacyText(
                              context,
                              zhCN: '发送中...',
                              zhTW: '發送中...',
                              en: 'Sending...',
                            )
                          : _privacyText(
                              context,
                              zhCN: '发送验证码',
                              zhTW: '發送驗證碼',
                              en: 'Send Code',
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                _privacyText(
                  context,
                  zhCN: '取消',
                  zhTW: '取消',
                  en: 'Cancel',
                ),
                style: TextStyle(
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
            ),
            TextButton(
              onPressed: () async {
                if (confirmController.text != 'DELETE') {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        _privacyText(
                          context,
                          zhCN: '请正确输入 DELETE',
                          zhTW: '請正確輸入 DELETE',
                          en: 'Please enter DELETE exactly',
                        ),
                      ),
                    ),
                  );
                  return;
                }
                final code = codeController.text.trim();
                if (code.isEmpty) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(
                    SnackBar(
                      content: Text(
                        _privacyText(
                          context,
                          zhCN: '请输入短信验证码',
                          zhTW: '請輸入簡訊驗證碼',
                          en: 'Please enter the SMS verification code',
                        ),
                      ),
                    ),
                  );
                  return;
                }

                Navigator.pop(context);

                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) =>
                      const Center(child: CircularProgressIndicator()),
                );

                try {
                  final api = ref.read(apiClientProvider);
                  final deletingAccountId = ref.read(currentAccountIdProvider);
                  final encodedCode = Uri.encodeQueryComponent(code);
                  final response = await api.delete(
                    '/user/account?code=$encodedCode',
                  );

                  if (mounted) Navigator.pop(context);

                  if (response.isSuccess) {
                    final cleanup = ref.read(accountDataCleanupServiceProvider);
                    await cleanup.scheduleAccountPurge(deletingAccountId);

                    if (ref.read(currentAccountIdProvider) !=
                        deletingAccountId) {
                      return;
                    }
                    await ref.read(authServiceProvider.notifier).logout(
                          reason: SessionExitReason.accountDeleted,
                          notifyServer: false,
                        );
                    final purgeResult = await cleanup.resumePendingPurge();
                    if (!purgeResult.success) {
                      throw StateError(purgeResult.errors.join('; '));
                    }

                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(
                        SnackBar(
                          content: Text(
                            _privacyText(
                              context,
                              zhCN: '账号已删除',
                              zhTW: '帳號已刪除',
                              en: 'Account deleted',
                            ),
                          ),
                        ),
                      );
                      context.go('/login');
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(
                        SnackBar(
                          content: Text(
                            _privacyServerMessage(
                              response.message,
                              zhCN: '删除失败，请重试',
                              zhTW: '刪除失敗，請重試',
                              en: 'Deletion failed. Please try again.',
                            ),
                          ),
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(
                      SnackBar(
                        content: Text(
                          _privacyText(
                            context,
                            zhCN: '删除失败，请重试',
                            zhTW: '刪除失敗，請重試',
                            en: 'Deletion failed, please try again',
                          ),
                        ),
                      ),
                    );
                  }
                }
              },
              child: Text(
                _privacyText(
                  context,
                  zhCN: '删除账号',
                  zhTW: '刪除帳號',
                  en: 'Delete Account',
                ),
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionTitle({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textTertiaryFor(context),
        ),
      ),
    );
  }
}

class _SectionNote extends StatelessWidget {
  final String text;
  final bool isDark;

  const _SectionNote({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: AppColors.textTertiaryFor(context),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;

  const _SettingsCard({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: List.generate(children.length * 2 - 1, (index) {
          if (index.isOdd) {
            return Divider(
              height: 1,
              indent: 16,
              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
            );
          }
          return children[index ~/ 2];
        }),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool value;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.title,
    this.subtitle,
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiaryFor(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.controlActiveFor(context),
          ),
        ],
      ),
    );
  }
}

class _TapTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final bool subtitleBelowTitle;
  final Color? titleColor;
  final bool isDark;
  final VoidCallback onTap;

  const _TapTile({
    required this.title,
    this.subtitle,
    this.subtitleBelowTitle = false,
    this.titleColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveSettingsTapTile(
      title: title,
      subtitle: subtitle,
      titleStyle: TextStyle(
        fontSize: 16,
        color: titleColor ?? (isDark ? Colors.white : Colors.black),
      ),
      subtitleStyle: TextStyle(
        fontSize: 13,
        height: 1.25,
        color: AppColors.textTertiaryFor(context),
      ),
      chevronColor: isDark ? Colors.white24 : Colors.black26,
      onTap: onTap,
      showChevron: subtitle != null,
      forceSubtitleBelowTitle: subtitleBelowTitle,
    );
  }
}
