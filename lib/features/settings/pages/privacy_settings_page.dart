import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/notification_sound_service.dart';
import 'blocked_users_page.dart';
import 'devices_page.dart';
import 'settings_page.dart' show deviceCountProvider;

/// 隐私设置服务
class PrivacySettingsService extends StateNotifier<PrivacySettings> {
  final ApiClient _apiClient;

  PrivacySettingsService(this._apiClient) : super(const PrivacySettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final localSettings = PrivacySettings(
        lastSeenVisibility: prefs.getString('privacy_last_seen') ?? '所有人',
        phoneVisibility: prefs.getString('privacy_phone') ?? '联系人',
        groupInvitePermission: prefs.getString('privacy_groups') ?? '所有人',
        allowPhoneSearch: prefs.getBool('privacy_allow_phone_search') ?? true,
        allowShortIdSearch:
            prefs.getBool('privacy_allow_short_id_search') ?? true,
        deviceLockEnabled: prefs.getBool('privacy_device_lock') ?? false,
        twoStepEnabled: prefs.getBool('privacy_two_step') ?? false,
        biometricEnabled: prefs.getBool('privacy_biometric') ?? false,
        appLockEnabled: prefs.getBool('privacy_app_lock') ?? false,
        autoLockTime: prefs.getString('privacy_auto_lock') ?? '立即',
        autoDeleteAccount: prefs.getString('privacy_auto_delete') ?? '6 个月',
      );
      state = localSettings;

      final response = await _apiClient.get('/user/privacy');
      if (response.isSuccess && response.data is Map) {
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('privacy_last_seen', settings.lastSeenVisibility);
    await prefs.setString('privacy_phone', settings.phoneVisibility);
    await prefs.setString('privacy_groups', settings.groupInvitePermission);
    await prefs.setBool(
        'privacy_allow_phone_search', settings.allowPhoneSearch);
    await prefs.setBool(
      'privacy_allow_short_id_search',
      settings.allowShortIdSearch,
    );
    await prefs.setBool('privacy_device_lock', settings.deviceLockEnabled);
    await prefs.setBool('privacy_two_step', settings.twoStepEnabled);
    await prefs.setString('privacy_auto_delete', settings.autoDeleteAccount);
  }

  Future<void> updateLastSeenVisibility(String value) async {
    state = state.copyWith(lastSeenVisibility: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('privacy_last_seen', value);
    // 同步到服务器
    await _syncToServer('last_seen_visibility', value);
  }

  Future<void> updatePhoneVisibility(String value) async {
    state = state.copyWith(phoneVisibility: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('privacy_phone', value);
    await _syncToServer('phone_visibility', value);
  }

  Future<void> updateGroupInvitePermission(String value) async {
    state = state.copyWith(groupInvitePermission: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('privacy_groups', value);
    await _syncToServer('group_invite_permission', value);
  }

  Future<void> updateAllowPhoneSearch(bool value) async {
    final previous = state.allowPhoneSearch;
    state = state.copyWith(allowPhoneSearch: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_allow_phone_search', value);
    try {
      final response = await _apiClient
          .put('/user/privacy', data: {'allow_phone_search': value});
      if (!response.isSuccess) {
        state = state.copyWith(allowPhoneSearch: previous);
        await prefs.setBool('privacy_allow_phone_search', previous);
      }
    } catch (e) {
      state = state.copyWith(allowPhoneSearch: previous);
      await prefs.setBool('privacy_allow_phone_search', previous);
      debugPrint('[PrivacySettings] Sync allow_phone_search error: $e');
    }
  }

  Future<void> updateAllowShortIdSearch(bool value) async {
    final previous = state.allowShortIdSearch;
    state = state.copyWith(allowShortIdSearch: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_allow_short_id_search', value);
    try {
      final response = await _apiClient
          .put('/user/privacy', data: {'allow_short_id_search': value});
      if (!response.isSuccess) {
        state = state.copyWith(allowShortIdSearch: previous);
        await prefs.setBool('privacy_allow_short_id_search', previous);
      }
    } catch (e) {
      state = state.copyWith(allowShortIdSearch: previous);
      await prefs.setBool('privacy_allow_short_id_search', previous);
      debugPrint('[PrivacySettings] Sync allow_short_id_search error: $e');
    }
  }

  Future<void> updateDeviceLock(bool value) async {
    state = state.copyWith(deviceLockEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_device_lock', value);
    try {
      await _apiClient
          .put('/user/privacy', data: {'device_lock_enabled': value});
    } catch (e) {
      debugPrint('[PrivacySettings] Sync device_lock_enabled error: $e');
    }
  }

  Future<void> updateTwoStep(bool value) async {
    state = state.copyWith(twoStepEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_two_step', value);
  }

  Future<void> updateBiometric(bool value) async {
    state = state.copyWith(biometricEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_biometric', value);
  }

  Future<void> updateAppLock(bool value) async {
    state = state.copyWith(appLockEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('privacy_app_lock', value);
  }

  Future<void> updateAutoLockTime(String value) async {
    state = state.copyWith(autoLockTime: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('privacy_auto_lock', value);
  }

  Future<void> updateAutoDeleteAccount(String value) async {
    state = state.copyWith(autoDeleteAccount: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('privacy_auto_delete', value);
    await _syncToServer('auto_delete_account', value);
  }

  Future<void> _syncToServer(String key, String value) async {
    try {
      await _apiClient.put('/user/privacy', data: {key: value});
    } catch (e) {
      debugPrint('[PrivacySettings] Sync error: $e');
    }
  }
}

class PrivacySettings {
  final String lastSeenVisibility;
  final String phoneVisibility;
  final String groupInvitePermission;
  final bool allowPhoneSearch;
  final bool allowShortIdSearch;
  final bool deviceLockEnabled;
  final bool twoStepEnabled;
  final bool biometricEnabled;
  final bool appLockEnabled;
  final String autoLockTime;
  final String autoDeleteAccount;

  const PrivacySettings({
    this.lastSeenVisibility = '所有人',
    this.phoneVisibility = '联系人',
    this.groupInvitePermission = '所有人',
    this.allowPhoneSearch = true,
    this.allowShortIdSearch = true,
    this.deviceLockEnabled = false,
    this.twoStepEnabled = false,
    this.biometricEnabled = false,
    this.appLockEnabled = false,
    this.autoLockTime = '立即',
    this.autoDeleteAccount = '6 个月',
  });

  factory PrivacySettings.fromJson(
    Map<String, dynamic> json, {
    PrivacySettings fallback = const PrivacySettings(),
  }) {
    return PrivacySettings(
      lastSeenVisibility: json['last_seen_visibility']?.toString() ??
          fallback.lastSeenVisibility,
      phoneVisibility:
          json['phone_visibility']?.toString() ?? fallback.phoneVisibility,
      groupInvitePermission: json['group_invite_permission']?.toString() ??
          fallback.groupInvitePermission,
      allowPhoneSearch: json['allow_phone_search'] is bool
          ? json['allow_phone_search'] as bool
          : fallback.allowPhoneSearch,
      allowShortIdSearch: json['allow_short_id_search'] is bool
          ? json['allow_short_id_search'] as bool
          : fallback.allowShortIdSearch,
      deviceLockEnabled: json['device_lock_enabled'] is bool
          ? json['device_lock_enabled'] as bool
          : fallback.deviceLockEnabled,
      twoStepEnabled: json['two_step_enabled'] is bool
          ? json['two_step_enabled'] as bool
          : fallback.twoStepEnabled,
      biometricEnabled: fallback.biometricEnabled,
      appLockEnabled: fallback.appLockEnabled,
      autoLockTime: fallback.autoLockTime,
      autoDeleteAccount:
          json['auto_delete_account']?.toString() ?? fallback.autoDeleteAccount,
    );
  }

  PrivacySettings copyWith({
    String? lastSeenVisibility,
    String? phoneVisibility,
    String? groupInvitePermission,
    bool? allowPhoneSearch,
    bool? allowShortIdSearch,
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
  return PrivacySettingsService(apiClient);
});

/// 隐私和安全设置页面
class PrivacySettingsPage extends ConsumerStatefulWidget {
  final bool isDesktopPanel;

  const PrivacySettingsPage({
    super.key,
    this.isDesktopPanel = false,
  });

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

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    _loadData();
  }

  Future<void> _checkBiometrics() async {
    try {
      _canCheckBiometrics = await _localAuth.canCheckBiometrics;
    } catch (e) {
      _canCheckBiometrics = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadData() async {
    try {
      final api = ref.read(apiClientProvider);

      // 获取已屏蔽用户数量
      final blockedResponse =
          await api.get<Map<String, dynamic>>('/user/blocked');
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
      return _buildBody(isDark, settings, settingsService, activeSessionsCount,
          isLoadingDevices, l10n);
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D1117) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        surfaceTintColor: Colors.transparent,
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
      body: _buildBody(isDark, settings, settingsService, activeSessionsCount,
          isLoadingDevices, l10n),
    );
  }

  Widget _buildBody(
      bool isDark,
      PrivacySettings settings,
      PrivacySettingsService settingsService,
      int activeSessionsCount,
      bool isLoadingDevices,
      AppLocalizations l10n) {
    return ListView(
      children: [
        const SizedBox(height: 24),

        // 隐私设置
        _SectionTitle(title: l10n.privacy, isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            _TapTile(
              title: l10n.get('online_status') ?? '在线状态',
              subtitle: settings.lastSeenVisibility,
              isDark: isDark,
              onTap: () => _showPrivacyPicker(
                l10n.get('online_status') ?? '在线状态',
                settings.lastSeenVisibility,
                (v) => settingsService.updateLastSeenVisibility(v),
              ),
            ),
            _TapTile(
              title: l10n.get('phone_number') ?? '手机号',
              subtitle: settings.phoneVisibility,
              isDark: isDark,
              onTap: () => _showPrivacyPicker(
                l10n.get('phone_number') ?? '手机号',
                settings.phoneVisibility,
                (v) => settingsService.updatePhoneVisibility(v),
              ),
            ),
            _TapTile(
              title: l10n.get('groups') ?? '群组',
              subtitle: settings.groupInvitePermission,
              isDark: isDark,
              onTap: () => _showPrivacyPicker(
                l10n.get('groups') ?? '群组',
                settings.groupInvitePermission,
                (v) => settingsService.updateGroupInvitePermission(v),
                description: l10n.get('who_can_add_to_group') ?? '谁可以将你添加到群组',
              ),
            ),
            _SwitchTile(
              title: '允许手机号搜索',
              subtitle: '关闭后，其他用户无法通过手机号搜索到你',
              value: settings.allowPhoneSearch,
              isDark: isDark,
              onChanged: settingsService.updateAllowPhoneSearch,
            ),
            _SwitchTile(
              title: '允许平台短号搜索',
              subtitle: '关闭后，其他用户无法通过平台短号搜索到你',
              value: settings.allowShortIdSearch,
              isDark: isDark,
              onChanged: settingsService.updateAllowShortIdSearch,
            ),
          ],
        ),

        _SectionNote(
          text: l10n.get('privacy_hint') ?? '选择谁可以看到你的在线状态、手机号等信息',
          isDark: isDark,
        ),

        const SizedBox(height: 24),

        // 安全
        _SectionTitle(title: l10n.get('security') ?? '安全', isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            _SwitchTile(
              title: l10n.get('two_step_verification') ?? '两步验证',
              subtitle: l10n.get('add_extra_protection') ?? '为账号添加额外保护',
              value: settings.twoStepEnabled,
              isDark: isDark,
              onChanged: (v) => _handleTwoStepChange(v, settingsService),
            ),
            _SwitchTile(
              title: '设备锁',
              subtitle: '开启后，新设备登录需要短信验证手机号',
              value: settings.deviceLockEnabled,
              isDark: isDark,
              onChanged: settingsService.updateDeviceLock,
            ),
            if (_canCheckBiometrics)
              _SwitchTile(
                title: l10n.get('biometric_unlock') ?? '面容/指纹解锁',
                subtitle: l10n.get('use_biometric_to_unlock') ?? '使用生物识别解锁应用',
                value: settings.biometricEnabled,
                isDark: isDark,
                onChanged: (v) => _handleBiometricChange(v, settingsService),
              ),
            _TapTile(
              title: l10n.get('app_lock_password') ?? '应用锁定密码',
              subtitle: settings.appLockEnabled
                  ? (l10n.get('set') ?? '已设置')
                  : (l10n.get('not_set') ?? '未设置'),
              isDark: isDark,
              onTap: () => _showSetPasscodeDialog(settingsService),
            ),
            _TapTile(
              title: l10n.get('auto_lock') ?? '自动锁定',
              subtitle: settings.autoLockTime,
              isDark: isDark,
              onTap: () =>
                  _showAutoLockPicker(settings.autoLockTime, settingsService),
            ),
            _TapTile(
              title: '短信修改登录密码',
              subtitle: '通过短信验证码修改',
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
                  : '$activeSessionsCount ${l10n.get('devices_count') ?? '台设备'}',
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
        _SectionTitle(title: l10n.get('account') ?? '账号', isDark: isDark),
        _SettingsCard(
          isDark: isDark,
          children: [
            _TapTile(
              title: l10n.get('auto_delete_account') ?? '账号自动注销',
              subtitle: settings.autoDeleteAccount,
              isDark: isDark,
              onTap: () => _showAutoDeletePicker(
                  settings.autoDeleteAccount, settingsService),
            ),
          ],
        ),

        _SectionNote(
          text: l10n.get('auto_delete_hint') ?? '如果你在此期间未登录过，账号将被自动删除',
          isDark: isDark,
        ),

        const SizedBox(height: 24),

        // 黑名单
        _SettingsCard(
          isDark: isDark,
          children: [
            _TapTile(
              title: l10n.get('blocked_users') ?? '已屏蔽用户',
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
              title: l10n.get('delete_my_account') ?? '删除我的账号',
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
      String title, String current, Function(String) onSelect,
      {String? description}) {
    GlobalHaptics.selection();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final options = ['所有人', '联系人', '无'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
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
                description ?? '谁可以看到你的$title',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              ...options.map((option) => ListTile(
                    title: Text(option),
                    trailing: option == current
                        ? Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () {
                      GlobalHaptics.selection();
                      onSelect(option);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('已更新$title设置'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                  )),
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
      // 关闭需要确认
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('关闭两步验证'),
          content: const Text('确定要关闭两步验证吗？这将降低账号的安全性。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                service.updateTwoStep(false);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已关闭两步验证')),
                );
              },
              child: Text('关闭', style: TextStyle(color: AppColors.error)),
            ),
          ],
        ),
      );
    }
  }

  void _showSetTwoStepPasswordDialog(PrivacySettingsService service) {
    final passwordController = TextEditingController();
    final confirmController = TextEditingController();
    final hintController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          '设置两步验证密码',
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passwordController,
              obscureText: true,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: '密码',
                hintText: '输入两步验证密码',
                hintStyle:
                    TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                labelStyle:
                    TextStyle(color: isDark ? Colors.white54 : Colors.black54),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: confirmController,
              obscureText: true,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: '确认密码',
                hintText: '再次输入密码',
                hintStyle:
                    TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                labelStyle:
                    TextStyle(color: isDark ? Colors.white54 : Colors.black54),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: hintController,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: '密码提示（可选）',
                hintText: '帮助你记住密码',
                hintStyle:
                    TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                labelStyle:
                    TextStyle(color: isDark ? Colors.white54 : Colors.black54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消',
                style:
                    TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
          ),
          TextButton(
            onPressed: () async {
              if (passwordController.text.isEmpty ||
                  passwordController.text.length < 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('密码至少6位')),
                );
                return;
              }
              if (passwordController.text != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('两次密码不一致')),
                );
                return;
              }
              Navigator.pop(context);

              // 加密存储密码
              final hash = sha256
                  .convert(utf8.encode(passwordController.text))
                  .toString();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('two_step_password_hash', hash);
              if (hintController.text.isNotEmpty) {
                await prefs.setString(
                    'two_step_password_hint', hintController.text);
              }

              // 同步到服务器
              final api = ref.read(apiClientProvider);
              await api.post('/user/two-step', data: {
                'password_hash': hash,
                'hint': hintController.text,
              });

              service.updateTwoStep(true);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已开启两步验证')),
                );
              }
            },
            child: Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBiometricChange(
      bool value, PrivacySettingsService service) async {
    if (value) {
      try {
        final authenticated = await _localAuth.authenticate(
          localizedReason: '验证身份以启用生物识别解锁',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: true,
          ),
        );
        if (authenticated) {
          service.updateBiometric(true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('已启用生物识别解锁')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('生物识别验证失败')),
          );
        }
      }
    } else {
      service.updateBiometric(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已关闭生物识别解锁')),
      );
    }
  }

  void _showSetPasscodeDialog(PrivacySettingsService service) {
    final passcodeController = TextEditingController();
    final confirmController = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = ref.read(privacySettingsProvider).appLockEnabled;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          isEditing ? '修改锁定密码' : '设置应用锁定密码',
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: passcodeController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: '密码',
                hintText: '输入6位数字密码',
                counterStyle:
                    TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                hintStyle:
                    TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                labelStyle:
                    TextStyle(color: isDark ? Colors.white54 : Colors.black54),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: confirmController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: '确认密码',
                hintText: '再次输入密码',
                counterStyle:
                    TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                hintStyle:
                    TextStyle(color: isDark ? Colors.white38 : Colors.black38),
                labelStyle:
                    TextStyle(color: isDark ? Colors.white54 : Colors.black54),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消',
                style:
                    TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
          ),
          if (isEditing)
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final prefs = await SharedPreferences.getInstance();
                await prefs.remove('app_lock_passcode_hash');
                service.updateAppLock(false);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已移除锁定密码')),
                  );
                }
              },
              child: Text('移除密码', style: TextStyle(color: AppColors.error)),
            ),
          TextButton(
            onPressed: () async {
              if (passcodeController.text.length != 6) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('请输入6位数字密码')),
                );
                return;
              }
              if (passcodeController.text != confirmController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('两次密码不一致')),
                );
                return;
              }
              Navigator.pop(context);

              // 加密存储密码
              final hash = sha256
                  .convert(utf8.encode(passcodeController.text))
                  .toString();
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('app_lock_passcode_hash', hash);

              service.updateAppLock(true);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已设置锁定密码')),
                );
              }
            },
            child: Text('确定', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showAutoLockPicker(String current, PrivacySettingsService service) {
    GlobalHaptics.selection();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final options = ['立即', '1 分钟', '5 分钟', '1 小时', '5 小时'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
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
                '自动锁定时间',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              ...options.map((option) => ListTile(
                    title: Text(option),
                    trailing: option == current
                        ? Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () {
                      GlobalHaptics.selection();
                      service.updateAutoLockTime(option);
                      Navigator.pop(context);
                    },
                  )),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
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
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(
            '短信修改登录密码',
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
                          color: isDark ? Colors.white : Colors.black),
                      decoration: const InputDecoration(
                        labelText: '验证码',
                        hintText: '输入短信验证码',
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
                                SnackBar(content: Text(resp.message)),
                              );
                            }
                            setStateDialog(() => isSending = false);
                          },
                    child: Text(isSending ? '发送中...' : '发送验证码'),
                  ),
                ],
              ),
              TextField(
                controller: passwordController,
                obscureText: true,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: const InputDecoration(
                  labelText: '新密码',
                  hintText: '至少6位',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: confirmController,
                obscureText: true,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: const InputDecoration(
                  labelText: '确认新密码',
                  hintText: '再次输入新密码',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting ? null : () => Navigator.pop(context),
              child: const Text('取消'),
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
                          const SnackBar(content: Text('请完整填写验证码和新密码')),
                        );
                        return;
                      }
                      if (pwd != confirm) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('两次输入的新密码不一致')),
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
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(resp.message)),
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
                isSubmitting ? '提交中...' : '确认修改',
                style: const TextStyle(color: AppColors.primary),
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
    final options = ['1 个月', '3 个月', '6 个月', '12 个月'];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
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
                '账号自动注销时间',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              ...options.map((option) => ListTile(
                    title: Text(option),
                    trailing: option == current
                        ? Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () {
                      GlobalHaptics.selection();
                      service.updateAutoDeleteAccount(option);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('账号将在 $option 不活跃后自动注销')),
                      );
                    },
                  )),
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
        title: const Text('终止所有其他会话'),
        content: const Text('确定要登出其他所有设备吗？这将终止除当前设备外的所有登录会话。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final api = ref.read(apiClientProvider);
                final response =
                    await api.post('/user/sessions/terminate-others');
                if (response.isSuccess) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已终止所有其他会话')),
                  );
                  // 刷新设备数量 provider
                  ref.invalidate(deviceCountProvider);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(response.message)),
                  );
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('操作失败，请重试')),
                );
              }
            },
            child: Text('终止', style: TextStyle(color: AppColors.error)),
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
        title: const Text('删除账号'),
        content:
            const Text('⚠️ 警告：此操作不可逆！\n\n删除账号后，你的所有聊天记录、群组、频道等数据将被永久删除，无法恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // 显示二次确认
              _showFinalDeleteConfirm();
            },
            child: Text('继续', style: TextStyle(color: AppColors.error)),
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
          backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text(
            '确认删除',
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '请输入 "DELETE" 和短信验证码确认删除账号',
                style:
                    TextStyle(color: isDark ? Colors.white70 : Colors.black87),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: confirmController,
                style: TextStyle(color: isDark ? Colors.white : Colors.black),
                decoration: InputDecoration(
                  hintText: '输入 DELETE',
                  hintStyle: TextStyle(
                      color: isDark ? Colors.white38 : Colors.black38),
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
                          color: isDark ? Colors.white : Colors.black),
                      decoration: const InputDecoration(
                        hintText: '短信验证码',
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
                                SnackBar(content: Text(resp.message)),
                              );
                            }
                            setStateDialog(() => isSending = false);
                          },
                    child: Text(isSending ? '发送中...' : '发送验证码'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消',
                  style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54)),
            ),
            TextButton(
              onPressed: () async {
                if (confirmController.text != 'DELETE') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请正确输入 DELETE')),
                  );
                  return;
                }
                final code = codeController.text.trim();
                if (code.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('请输入短信验证码')),
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
                  final encodedCode = Uri.encodeQueryComponent(code);
                  final response =
                      await api.delete('/user/account?code=$encodedCode');

                  if (mounted) Navigator.pop(context);

                  if (response.isSuccess) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.clear();

                    await ref.read(authServiceProvider.notifier).logout();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('账号已删除')),
                      );
                      context.go('/login');
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(response.message)),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('删除失败，请重试')),
                    );
                  }
                }
              },
              child: Text('删除账号', style: TextStyle(color: AppColors.error)),
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
          color: isDark ? Colors.white38 : Colors.black38,
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
          color: isDark ? Colors.white38 : Colors.black38,
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
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

class _TapTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? titleColor;
  final bool isDark;
  final VoidCallback onTap;

  const _TapTile({
    required this.title,
    this.subtitle,
    this.titleColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        GlobalHaptics.selection();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: titleColor ?? (isDark ? Colors.white : Colors.black),
                ),
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            if (subtitle != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
