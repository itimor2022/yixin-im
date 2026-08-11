// 文件用途：实现 SettingsPage 页面及其交互流程，属于应用设置。
// 核心逻辑：维护 SettingsPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_preset.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/utils/floating_nav_layout.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/hot_update_sdk_adapter.dart';
import '../../chat/services/emoji_store_service.dart';
import '../../chat/providers/chat_provider.dart';
import '../../chat/widgets/emoji_picker.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/account_session_coordinator.dart';
import '../../../core/services/api/api_client.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/adaptive_settings_tile.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../moments/providers/moment_provider.dart';
import '../../moments/pages/moments_page.dart';
import 'profile_page.dart';
import 'notification_settings_page.dart';
import 'privacy_settings_page.dart';
import 'data_storage_page.dart';
import 'devices_page.dart';
import 'stickers_page.dart';
import 'faq_page.dart';
import 'chat_settings_page.dart';
import '../../auth/pages/agreement_page.dart';
import '../../home/pages/home_desktop_page.dart';
import 'theme_picker_page.dart';
import '../../vip/providers/vip_provider.dart';
import '../../vip/widgets/vip_avatar_frame.dart';
import '../../vip/widgets/vip_badge.dart';
import '../../../shared/widgets/themed_app_bar.dart';

/// 设备数量 Provider
final deviceCountProvider = FutureProvider<int>((ref) async {
  final accountId = ref.watch(currentAccountIdProvider);
  if (accountId.isEmpty) return 0;
  final api = ref.watch(apiClientProvider);
  try {
    // 使用 /user/devices API 与设备页面保持一致
    final response = await api.get<Map<String, dynamic>>('/user/devices');
    if (response.isSuccess && response.data != null) {
      final devices = response.data!['devices'] as List? ?? [];
      final activeDevices = devices.where((item) {
        final map = item as Map?;
        return map?['has_active_session'] != false;
      });
      final uniqueDeviceIds = activeDevices
          .map((item) => (item as Map?)?['device_id']?.toString().trim() ?? '')
          .where((deviceId) => deviceId.isNotEmpty)
          .toSet();
      if (uniqueDeviceIds.isNotEmpty) {
        return uniqueDeviceIds.length;
      }
      return activeDevices.length;
    }
  } catch (e) {
    debugPrint('[Settings] Get device count error: $e');
  }
  return ref.read(currentAccountIdProvider) == accountId ? 1 : 0;
});

/// 应用版本 Provider
final appVersionProvider = FutureProvider<PackageInfo>((ref) async {
  return await PackageInfo.fromPlatform();
});

/// 关于页显示信息
final aboutInfoProvider =
    FutureProvider<({PackageInfo packageInfo, SystemSettings settings})>((
  ref,
) async {
  final packageInfo = await PackageInfo.fromPlatform();
  final settings = await ref.watch(systemSettingsProvider.future);
  return (packageInfo: packageInfo, settings: settings);
});

String _settingsText(
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

String _settingsDeviceCountText(BuildContext context, int count) {
  final l10n = AppLocalizations.of(context);
  if (l10n.language == AppLanguage.en) {
    return count == 1 ? '1 device' : '$count devices';
  }
  return '$count ${l10n.get('devices_count')}';
}

String _settingsFormatDate(DateTime? date) {
  if (date == null) return '';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

String _settingsTimeAgoText(BuildContext context, String dateStr) {
  if (dateStr.isEmpty) return '';
  try {
    final date = DateTime.parse(dateStr).toLocal();
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) {
      return _settingsText(
        context,
        zhCN: '刚刚',
        zhTW: '剛剛',
        en: 'Just now',
      );
    }
    if (diff.inMinutes < 60) {
      return _settingsText(
        context,
        zhCN: '${diff.inMinutes}分钟前',
        zhTW: '${diff.inMinutes}分鐘前',
        en: '${diff.inMinutes}m ago',
      );
    }
    if (diff.inHours < 24) {
      return _settingsText(
        context,
        zhCN: '${diff.inHours}小时前',
        zhTW: '${diff.inHours}小時前',
        en: '${diff.inHours}h ago',
      );
    }
    if (diff.inDays < 7) {
      return _settingsText(
        context,
        zhCN: '${diff.inDays}天前',
        zhTW: '${diff.inDays}天前',
        en: '${diff.inDays}d ago',
      );
    }
    return '${date.month}-${date.day}';
  } catch (e) {
    return dateStr;
  }
}

String _settingsCommentTypeLabel(
  BuildContext context, {
  required String type,
  required String replyToName,
}) {
  switch (type) {
    case 'received_comment':
      return _settingsText(
        context,
        zhCN: '评论了你的动态',
        zhTW: '評論了你的動態',
        en: 'commented on your moment',
      );
    case 'received_reply':
      return _settingsText(
        context,
        zhCN: '回复了你',
        zhTW: '回覆了你',
        en: 'replied to you',
      );
    case 'sent':
      if (replyToName.isNotEmpty) {
        return _settingsText(
          context,
          zhCN: '回复 $replyToName',
          zhTW: '回覆 $replyToName',
          en: 'replied to $replyToName',
        );
      }
      return _settingsText(
        context,
        zhCN: '评论',
        zhTW: '評論',
        en: 'comment',
      );
    default:
      return '';
  }
}

// 关键声明：settings page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class SettingsPage extends ConsumerWidget {
  /// 是否作为桌面端侧边栏使用
  final bool isDesktopSidebar;

  const SettingsPage({super.key, this.isDesktopSidebar = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeMode = ref.watch(themeModeProvider);
    final deviceCountAsync = ref.watch(deviceCountProvider);
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final currentUser = ref.watch(authServiceProvider).user;
    final configuredName =
        ref.watch(systemSettingsProvider).valueOrNull?.displayName.trim() ?? '';
    final systemSettings = ref.watch(systemSettingsProvider).valueOrNull;
    final showWallet = !PlatformUtils.isIOS ||
        (systemSettings?.iosCompliance.allowsWallet ?? false);
    final showVIP = !PlatformUtils.isIOS ||
        (systemSettings?.iosCompliance.allowsVIP ?? false);
    final appName =
        configuredName.isNotEmpty ? configuredName : defaultAppDisplayName();
    final vipStatusAsync = ref.watch(vipStatusProvider);
    final isFloatingNavHidden = ref.watch(floatingNavHiddenProvider);
    final floatingBottomSpace = isDesktopSidebar
        ? 32.0
        : FloatingNavLayout.reservedSpace(context, extra: 24);

    if (!isDesktopSidebar && isFloatingNavHidden) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          ref.read(floatingNavHiddenProvider.notifier).state = false;
        }
      });
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              children: [
                _SettingsTopHeader(
                  isDark: isDark,
                  isDesktopSidebar: isDesktopSidebar,
                ),

                // 账号设置
                Transform.translate(
                  offset: const Offset(0, -2),
                  child: _SettingsGroup(
                    isDark: isDark,
                    children: [
                      if (currentUser?.credentialsInitialized == false)
                        _SettingsTile(
                          icon: Icons.warning_amber_rounded,
                          iconBgColor: const Color(0xFFFF3B30),
                          title: _settingsText(
                            context,
                            zhCN: '完善登录账号',
                            zhTW: '完善登入帳號',
                            en: 'Complete Sign-in Setup',
                          ),
                          subtitle: _settingsText(
                            context,
                            zhCN: '设置账号密码，避免更换设备后无法找回',
                            zhTW: '設定帳號密碼，避免更換裝置後無法找回',
                            en: 'Set credentials to keep access on other devices',
                          ),
                          isDark: isDark,
                          onTap: () => _openPage(
                            context,
                            const PrivacySettingsPage(),
                            ref,
                            desktopPanelType: DesktopPanelType.settingsPrivacy,
                          ),
                        ),
                      if (showWallet)
                        _SettingsTile(
                          icon: Icons.account_balance_wallet_outlined,
                          iconBgColor: const Color(0xFFFF9500),
                          title: _settingsText(
                            context,
                            zhCN: '钱包',
                            zhTW: '錢包',
                            en: 'Wallet',
                          ),
                          isDark: isDark,
                          onTap: () => context.push('/wallet'),
                        ),
                      if (showVIP)
                        _SettingsTile(
                          icon: Icons.workspace_premium_outlined,
                          iconBgColor: const Color(0xFF5856D6),
                          title: _settingsText(
                            context,
                            zhCN: 'VIP会员',
                            zhTW: 'VIP會員',
                            en: 'VIP',
                          ),
                          subtitle: vipStatusAsync.maybeWhen(
                            data: (status) => status.isActive
                                ? '${status.levelName} · ${_settingsFormatDate(status.expiredAt)}'
                                : _settingsText(
                                    context,
                                    zhCN: '未开通',
                                    zhTW: '未開通',
                                    en: 'Not active',
                                  ),
                            orElse: () => null,
                          ),
                          isDark: isDark,
                          onTap: () => context.push('/vip'),
                        ),
                      _SettingsTile(
                        icon: Icons.notifications_outlined,
                        iconBgColor: const Color(0xFFFF3B30),
                        title: l10n.notificationSettings,
                        isDark: isDark,
                        onTap: () => _openPage(
                          context,
                          const NotificationSettingsPage(),
                          ref,
                          desktopPanelType:
                              DesktopPanelType.settingsNotification,
                        ),
                      ),
                      _SettingsTile(
                        icon: Icons.lock_outline,
                        iconBgColor: const Color(0xFF8E8E93),
                        title: l10n.privacy,
                        isDark: isDark,
                        onTap: () => _openPage(
                          context,
                          const PrivacySettingsPage(),
                          ref,
                          desktopPanelType: DesktopPanelType.settingsPrivacy,
                        ),
                      ),
                      _SettingsTile(
                        icon: Icons.cloud_outlined,
                        iconBgColor: const Color(0xFF34C759),
                        title: l10n.dataStorage,
                        isDark: isDark,
                        onTap: () => _openPage(
                          context,
                          const DataStoragePage(),
                          ref,
                          desktopPanelType:
                              DesktopPanelType.settingsDataStorage,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 应用设置
                _SettingsGroup(
                  isDark: isDark,
                  children: [
                    _SettingsTile(
                      icon: Icons.chat_bubble_outline,
                      iconBgColor: AppColors.primaryFor(context),
                      title: l10n.chatSettings,
                      isDark: isDark,
                      onTap: () => _openPage(
                        context,
                        const ChatSettingsPage(),
                        ref,
                        desktopPanelType: DesktopPanelType.settingsChatSettings,
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.devices_outlined,
                      iconBgColor: const Color(0xFFFF9500),
                      title: l10n.devices,
                      subtitle: deviceCountAsync.when(
                        data: (count) => _settingsDeviceCountText(
                          context,
                          count,
                        ),
                        loading: () => '...',
                        error: (_, __) => _settingsDeviceCountText(context, 1),
                      ),
                      isDark: isDark,
                      onTap: () => _openPage(
                        context,
                        const DevicesPage(),
                        ref,
                        desktopPanelType: DesktopPanelType.settingsDevices,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 外观设置
                _SettingsGroup(
                  isDark: isDark,
                  children: [
                    Consumer(
                      builder: (context, ref, _) {
                        final language = ref.watch(languageProvider);
                        return _SettingsTile(
                          icon: Icons.language_outlined,
                          iconBgColor: const Color(0xFFAF52DE),
                          title: l10n.languageText,
                          subtitle: language.displayName,
                          isDark: isDark,
                          onTap: () => _showLanguageSheet(context, ref),
                        );
                      },
                    ),
                    _SettingsTile(
                      icon: Icons.brightness_6_outlined,
                      iconBgColor: const Color(0xFF007AFF),
                      title: l10n.appearance,
                      subtitle: _getThemeModeText(themeMode, l10n),
                      isDark: isDark,
                      onTap: () => _showThemeSheet(context, ref, l10n),
                    ),
                    _SettingsTile(
                      icon: Icons.palette_outlined,
                      iconBgColor: const Color(0xFFFF6B6B),
                      title: '主题风格',
                      subtitle: '切换主题色彩与显示模式',
                      isDark: isDark,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ThemePickerPage(),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 其他
                _SettingsGroup(
                  isDark: isDark,
                  children: [
                    _SettingsTile(
                      icon: Icons.emoji_emotions_outlined,
                      iconBgColor: const Color(0xFFFFCC00),
                      title: l10n.stickersEmoji,
                      isDark: isDark,
                      onTap: () => _openPage(
                        context,
                        const StickersPage(),
                        ref,
                        desktopPanelType: DesktopPanelType.settingsStickers,
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.help_outline,
                      iconBgColor: AppColors.primaryFor(context),
                      title: l10n.faq,
                      isDark: isDark,
                      onTap: () => _openPage(
                        context,
                        const FAQPage(),
                        ref,
                        desktopPanelType: DesktopPanelType.settingsFaq,
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.info_outline,
                      iconBgColor: const Color(0xFF8E8E93),
                      title: l10n.about,
                      isDark: isDark,
                      onTap: () {
                        if (isDesktopSidebar) {
                          HapticFeedback.selectionClick();
                          ref.read(desktopProfileProvider.notifier).state =
                              const DesktopProfileInfo(
                            type: DesktopPanelType.settingsAbout,
                            id: 'about',
                          );
                        } else {
                          _showAboutSheet(context, isDark);
                        }
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // 版本信息
                Consumer(
                  builder: (context, ref, _) {
                    final versionAsync = ref.watch(appVersionProvider);
                    return versionAsync.when(
                      data: (info) {
                        final settings =
                            ref.watch(systemSettingsProvider).valueOrNull;
                        final patchNumber = ref
                            .watch(shorebirdCurrentPatchNumberProvider)
                            .valueOrNull;
                        final displayVersion =
                            settings?.systemVersion.trim().isNotEmpty == true
                                ? settings!.systemVersion.trim()
                                : info.version;
                        final patchLabel = patchNumber == null
                            ? ''
                            : _settingsText(
                                context,
                                zhCN: ' · 热更新 Patch #$patchNumber',
                                zhTW: ' · 熱更新 Patch #$patchNumber',
                                en: ' · Hot update Patch #$patchNumber',
                              );
                        return Text(
                          '$appName v$displayVersion (Build ${info.buildNumber})$patchLabel',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiaryFor(context),
                          ),
                        );
                      },
                      loading: () => Text(
                        appName,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiaryFor(context),
                        ),
                      ),
                      error: (_, __) => Text(
                        appName,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiaryFor(context),
                        ),
                      ),
                    );
                  },
                ),

                SizedBox(height: floatingBottomSpace),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _openPage(
    BuildContext context,
    Widget page,
    WidgetRef ref, {
    DesktopPanelType? desktopPanelType,
  }) {
    HapticFeedback.selectionClick();

    // 桌面端侧边栏模式：使用右侧面板显示
    if (isDesktopSidebar && desktopPanelType != null) {
      ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo(
        type: desktopPanelType,
        id: desktopPanelType.name,
      );
      return;
    }

    Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => page));
  }

  String _getThemeModeText(ThemeMode mode, AppLocalizations l10n) {
    switch (mode) {
      case ThemeMode.system:
        return l10n.systemMode;
      case ThemeMode.light:
        return l10n.lightMode;
      case ThemeMode.dark:
        return l10n.darkMode;
    }
  }

  void _showThemeSheet(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final themeMode = ref.read(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      builder: (context) => _SelectionSheet(
        title: l10n.appearance,
        isDark: isDark,
        options: [
          _SelectionOption(
            title: l10n.systemMode,
            subtitle: _settingsText(
              context,
              zhCN: '自动切换深色/浅色',
              zhTW: '自動切換深色/淺色',
              en: 'Auto switch dark/light',
            ),
            isSelected: themeMode == ThemeMode.system,
            onTap: () {
              ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(ThemeMode.system);
              Navigator.pop(context);
            },
          ),
          _SelectionOption(
            title: l10n.lightMode,
            isSelected: themeMode == ThemeMode.light,
            onTap: () {
              ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(ThemeMode.light);
              Navigator.pop(context);
            },
          ),
          _SelectionOption(
            title: l10n.darkMode,
            isSelected: themeMode == ThemeMode.dark,
            onTap: () {
              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showLanguageSheet(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentLanguage = ref.read(languageProvider);
    final l10n = AppLocalizations(currentLanguage);

    showModalBottomSheet(
      context: context,
      builder: (context) => _SelectionSheet(
        title: l10n.languageText,
        isDark: isDark,
        options: AppLanguage.values
            .map(
              (lang) => _SelectionOption(
                title: lang.displayName,
                isSelected: lang == currentLanguage,
                onTap: () {
                  ref.read(languageProvider.notifier).setLanguage(lang);
                  Navigator.pop(context);
                },
              ),
            )
            .toList(),
      ),
    );
  }

  void _showAboutSheet(BuildContext context, bool isDark) {
    final bottomSpacing = FloatingNavLayout.reservedSpace(context, extra: 20);

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardFor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, bottomSpacing),
            child: Consumer(
              builder: (context, ref, _) {
                final aboutInfoAsync = ref.watch(aboutInfoProvider);
                return aboutInfoAsync.when(
                  data: (aboutInfo) {
                    final packageInfo = aboutInfo.packageInfo;
                    final settings = aboutInfo.settings;
                    final configuredName = settings.systemName.trim();
                    final configuredVersion = settings.systemVersion.trim();
                    final patchNumber = ref
                        .watch(shorebirdCurrentPatchNumberProvider)
                        .valueOrNull;
                    final appName = configuredName.isNotEmpty
                        ? configuredName
                        : defaultAppDisplayName();
                    final versionText = configuredVersion.isNotEmpty
                        ? configuredVersion
                        : packageInfo.version;
                    final patchLabel = patchNumber == null
                        ? ''
                        : _settingsText(
                            context,
                            zhCN: ' · 热更新 Patch #$patchNumber',
                            zhTW: ' · 熱更新 Patch #$patchNumber',
                            en: ' · Hot update Patch #$patchNumber',
                          );
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Logo
                        ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            'assets/logo.png',
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          appName,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimaryFor(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'v$versionText (Build ${packageInfo.buildNumber})$patchLabel',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondaryFor(context),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          _settingsText(
                            context,
                            zhCN: '一款简洁、快速、安全的即时通讯应用',
                            zhTW: '一款簡潔、快速、安全的即時通訊應用',
                            en: 'A clean, fast, and secure instant messaging app',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondaryFor(context),
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _AboutAction(
                              icon: Icons.star_border,
                              label: _settingsText(
                                context,
                                zhCN: '评分',
                                zhTW: '評分',
                                en: 'Rate',
                              ),
                              onTap: () {},
                            ),
                            _AboutAction(
                              icon: Icons.share_outlined,
                              label: _settingsText(
                                context,
                                zhCN: '分享',
                                zhTW: '分享',
                                en: 'Share',
                              ),
                              onTap: () {},
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // 协议链接
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute(
                                    builder: (_) => const AgreementPage(
                                      type: AgreementType.userAgreement,
                                    ),
                                  ),
                                );
                              },
                              child: Text(
                                _settingsText(
                                  context,
                                  zhCN: '用户协议',
                                  zhTW: '使用者協議',
                                  en: 'User Agreement',
                                ),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.linkFor(context),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                '|',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textTertiaryFor(context),
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute(
                                    builder: (_) => const AgreementPage(
                                      type: AgreementType.privacyPolicy,
                                    ),
                                  ),
                                );
                              },
                              child: Text(
                                _settingsText(
                                  context,
                                  zhCN: '隐私政策',
                                  zhTW: '隱私政策',
                                  en: 'Privacy Policy',
                                ),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.linkFor(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                  loading: () => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 24),
                      const CircularProgressIndicator(strokeWidth: 2),
                      const SizedBox(height: 16),
                      Text(
                        _settingsText(
                          context,
                          zhCN: '加载中...',
                          zhTW: '載入中...',
                          en: 'Loading...',
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondaryFor(context),
                        ),
                      ),
                    ],
                  ),
                  error: (_, __) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Logo
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          'assets/logo.png',
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        defaultAppDisplayName(),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _settingsText(
                          context,
                          zhCN: '版本未知',
                          zhTW: '版本未知',
                          en: 'Unknown version',
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondaryFor(context),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsTopHeader extends StatelessWidget {
  final bool isDark;
  final bool isDesktopSidebar;

  const _SettingsTopHeader({
    required this.isDark,
    required this.isDesktopSidebar,
  });

  @override
  Widget build(BuildContext context) {
    return _UserProfileCard(
      isDark: isDark,
      isDesktopSidebar: isDesktopSidebar,
    );
  }
}

class _ProfileHeaderBackground {
  const _ProfileHeaderBackground({
    required this.gradient,
    this.imageUrl,
    this.lightForeground = false,
    this.patternOpacity = 0.16,
  });

  final List<Color> gradient;
  final String? imageUrl;
  final bool lightForeground;
  final double patternOpacity;
}

const List<List<Color>> _settingsProfileBgGradients = [
  [Color(0xFF74BDF5), Color(0xFF4EA5E8)],
  [Color(0xFF43C6AC), Color(0xFF1D976C)],
  [Color(0xFFFFB347), Color(0xFFFF8008)],
  [Color(0xFFFF6B6B), Color(0xFFEE0979)],
  [Color(0xFFA18CD1), Color(0xFF6A3093)],
  [Color(0xFF4ECDC4), Color(0xFF009688)],
  [Color(0xFFFF9A9E), Color(0xFFFECFEF)],
  [Color(0xFF8E9AAF), Color(0xFF5C6B7A)],
];

String? _settingsNormalizeMediaUrl(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  if (text.startsWith('http://') || text.startsWith('https://')) return text;
  return ApiConfig.getMediaUrl(text);
}

String? _settingsReadProfileBackgroundImage(User? user) {
  final values = <String?>[
    user?.profileBackgroundUrl,
    user?.profileBackground,
    user?.profileCardBackground,
  ];
  for (final value in values) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) continue;
    if (text.startsWith('http://') ||
        text.startsWith('https://') ||
        text.startsWith('/') ||
        text.contains('.jpg') ||
        text.contains('.jpeg') ||
        text.contains('.png') ||
        text.contains('.webp')) {
      return _settingsNormalizeMediaUrl(text);
    }
  }
  return null;
}

int? _settingsReadProfileBackgroundIndex(String? nicknameColor) {
  final text = nicknameColor?.trim() ?? '';
  if (text.isEmpty) return null;
  for (final part in text.split(',')) {
    if (part.startsWith('bg:')) {
      return int.tryParse(part.substring(3));
    }
  }
  return null;
}

_ProfileHeaderBackground _settingsResolveProfileHeaderBackground({
  required User? user,
  required int vipLevel,
}) {
  final imageUrl = _settingsReadProfileBackgroundImage(user);
  final bgIndex = _settingsReadProfileBackgroundIndex(user?.nicknameColor);
  if (imageUrl != null) {
    final fallbackIndex = (bgIndex ?? 0).clamp(
      0,
      _settingsProfileBgGradients.length - 1,
    );
    return _ProfileHeaderBackground(
      imageUrl: imageUrl,
      gradient: _settingsProfileBgGradients[fallbackIndex],
      patternOpacity: 0,
    );
  }

  if (bgIndex != null) {
    final clamped = bgIndex.clamp(0, _settingsProfileBgGradients.length - 1);
    return _ProfileHeaderBackground(
      gradient: _settingsProfileBgGradients[clamped],
      patternOpacity: 0.18,
    );
  }

  if (vipLevel >= 2) {
    return const _ProfileHeaderBackground(
      gradient: [Color(0xFF18130C), Color(0xFF5B4521), Color(0xFFD2B06A)],
      patternOpacity: 0.10,
    );
  }

  if (vipLevel == 1) {
    return const _ProfileHeaderBackground(
      gradient: [Color(0xFFDDE7F2), Color(0xFFA9BCD2), Color(0xFF7F9BB9)],
      lightForeground: true,
      patternOpacity: 0.10,
    );
  }

  return const _ProfileHeaderBackground(
    gradient: [Color(0xFF74BDF5), Color(0xFF4EA5E8)],
    patternOpacity: 0.18,
  );
}

class _ProfileHeaderIconButton extends StatelessWidget {
  final IconData icon;
  final Color foreground;
  final VoidCallback onTap;

  const _ProfileHeaderIconButton({
    required this.icon,
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.92),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, size: 21, color: foreground),
        ),
      ),
    );
  }
}

class _ProfileHeaderEditButton extends StatelessWidget {
  final Color foreground;
  final VoidCallback onTap;

  const _ProfileHeaderEditButton({
    required this.foreground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.92),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Text(
            AppLocalizations.of(context).edit,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}

/// 用户信息卡片
class _UserProfileCard extends ConsumerStatefulWidget {
  final bool isDark;
  final bool isDesktopSidebar;

  const _UserProfileCard({required this.isDark, this.isDesktopSidebar = false});

  @override
  ConsumerState<_UserProfileCard> createState() => _UserProfileCardState();
}

class _UserProfileCardState extends ConsumerState<_UserProfileCard> {
  /// 格式化手机号（隐藏中间4位）
  String _formatPhone(String? phone) {
    if (phone == null || phone.isEmpty) {
      return _settingsText(
        context,
        zhCN: '未绑定手机',
        zhTW: '未綁定手機',
        en: 'No phone',
      );
    }
    if (phone.length >= 11) {
      return '${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
    }
    return phone;
  }

  /// 显示表情状态选择器（毛玻璃效果）
  void _showEmojiStatusPicker() {
    HapticFeedback.selectionClick();
    final currentEmoji = ref.read(authServiceProvider).user?.emojiAvatar;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.5,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1C1C1E).withOpacity(0.9)
                  : const Color(0xFFF2F2F7).withOpacity(0.9),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Column(
              children: [
                // 拖动条
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.dividerFor(context),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 顶部标题栏
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Text(
                        _settingsText(
                          context,
                          zhCN: '设置表情状态',
                          zhTW: '設定表情狀態',
                          en: 'Set Emoji Status',
                        ),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const Spacer(),
                      if (currentEmoji != null && currentEmoji.isNotEmpty)
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            final api = ref.read(apiClientProvider);
                            final response = await api.put(
                              '/user/me',
                              data: {'emoji_avatar': ''},
                            );
                            if (response.isSuccess) {
                              await ref
                                  .read(authServiceProvider.notifier)
                                  .getCurrentUser();
                            }
                          },
                          child: Text(
                            _settingsText(
                              context,
                              zhCN: '清除',
                              zhTW: '清除',
                              en: 'Clear',
                            ),
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 15,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // 表情选择器
                Expanded(
                  child: TGEmojiPicker(
                    height: double.infinity,
                    onEmojiSelected: (emoji, {bool isAnimated = false}) async {
                      if (emoji == 'BACKSPACE') return;
                      Navigator.pop(ctx);
                      final profileEmoji = await _profileEmojiValue(emoji);
                      final api = ref.read(apiClientProvider);
                      final response = await api.put(
                        '/user/me',
                        data: {'emoji_avatar': profileEmoji},
                      );
                      if (response.isSuccess) {
                        await ref
                            .read(authServiceProvider.notifier)
                            .getCurrentUser();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<String> _profileEmojiValue(String emoji) async {
    final value = emoji.trim();
    if (value.isEmpty || value == 'BACKSPACE') return '';

    if (value.startsWith(EmojiStoreService.remoteStickerSendPrefix)) {
      return EmojiStoreService.decodeRemoteStickerSend(value)?.url ?? '';
    }

    if (value.startsWith(EmojiStoreService.builtInStickerSendPrefix)) {
      return value.substring(EmojiStoreService.builtInStickerSendPrefix.length);
    }

    if (value.startsWith(EmojiStoreService.customEmojiSendUrlPrefix)) {
      return _compactOwnUploadUrl(
        value.substring(EmojiStoreService.customEmojiSendUrlPrefix.length),
      );
    }

    if (!value.startsWith(EmojiStoreService.customEmojiSendPrefix)) {
      return _compactOwnUploadUrl(value);
    }

    final localPath =
        value.substring(EmojiStoreService.customEmojiSendPrefix.length);
    final items = await EmojiStoreService.loadCustomEmojis();
    for (final item in items) {
      if (item.path == localPath && item.remoteUrl?.isNotEmpty == true) {
        return _compactOwnUploadUrl(item.remoteUrl!);
      }
    }
    return value;
  }

  String _compactOwnUploadUrl(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) return '';
    if (normalized.startsWith('/uploads/')) return normalized;
    if (normalized.startsWith('uploads/')) return '/$normalized';
    final uri = Uri.tryParse(normalized);
    if (uri != null && uri.path.startsWith('/uploads/')) {
      return uri.path;
    }
    return normalized;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authServiceProvider);
    final user = authState.user;
    final isDark = widget.isDark;

    // 用户显示名称
    final displayName = user?.nickname.isNotEmpty == true
        ? user!.nickname
        : (user?.username ??
            _settingsText(
              context,
              zhCN: '未登录',
              zhTW: '未登入',
              en: 'Not signed in',
            ));

    // 用户名 @xxx
    final username = user?.username ?? '';

    // 手机号
    final phoneDisplay = _formatPhone(user?.phone);

    // 头像
    final avatar = user?.avatar;

    return _ImmersiveProfileHeader(
      user: user,
      displayName: displayName,
      username: username,
      phoneDisplay: phoneDisplay,
      avatar: avatar,
      isDark: isDark,
      isDesktopSidebar: widget.isDesktopSidebar,
      onEmojiTap: _showEmojiStatusPicker,
    );
  }
}

/// 设置分组
class _ImmersiveProfileHeader extends ConsumerWidget {
  final User? user;
  final String displayName;
  final String username;
  final String phoneDisplay;
  final String? avatar;
  final bool isDark;
  final bool isDesktopSidebar;
  final VoidCallback onEmojiTap;

  const _ImmersiveProfileHeader({
    required this.user,
    required this.displayName,
    required this.username,
    required this.phoneDisplay,
    required this.avatar,
    required this.isDark,
    required this.isDesktopSidebar,
    required this.onEmojiTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topInset = MediaQuery.paddingOf(context).top;
    final vipStatus = ref.watch(vipStatusProvider).valueOrNull;
    final vipLevel = vipStatus?.isActive == true && (vipStatus?.level ?? 0) > 0
        ? vipStatus!.level
        : 0;
    // The desktop header needs a little more vertical breathing room than the
    // phone layout. Windows font metrics used to leave the account line almost
    // flush with the curved content transition, so it was partially covered.
    final headerHeight = isDesktopSidebar ? 300.0 : topInset + 296.0;
    final background = _settingsResolveProfileHeaderBackground(
      user: user,
      vipLevel: vipLevel,
    );
    final hasImage = background.imageUrl?.isNotEmpty == true;
    final headerForeground = background.lightForeground && !hasImage
        ? const Color(0xFF24394F)
        : Colors.white;
    final headerMutedForeground = background.lightForeground && !hasImage
        ? const Color(0xB324394F)
        : Colors.white.withOpacity(0.80);
    final contentBg =
        isDark ? AppColors.darkBackground : AppColors.lightBackground;
    final buttonForeground = background.lightForeground && !hasImage
        ? const Color(0xFF24394F)
        : const Color(0xFF1D3557);
    final emojiStatus = user?.emojiAvatar;
    final accountLine = [
      if (phoneDisplay.trim().isNotEmpty) phoneDisplay.trim(),
      if (username.trim().isNotEmpty) '@${username.trim()}',
    ].join(' · ');

    void openProfile() {
      HapticFeedback.selectionClick();
      if (isDesktopSidebar) {
        ref.read(desktopProfileProvider.notifier).state =
            const DesktopProfileInfo(
          type: DesktopPanelType.settingsProfile,
          id: 'profile',
        );
      } else {
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute(builder: (_) => const ProfilePage()),
        );
      }
    }

    void openProfileEditor() {
      HapticFeedback.selectionClick();
      if (isDesktopSidebar) {
        ref.read(desktopProfileProvider.notifier).state =
            const DesktopProfileInfo(
          type: DesktopPanelType.settingsProfile,
          id: 'profile',
        );
      } else {
        context.push('/settings/profile');
      }
    }

    void openQrCode() {
      HapticFeedback.selectionClick();
      Navigator.of(context, rootNavigator: true).push(
        PageRouteBuilder(
          opaque: true,
          pageBuilder: (context, animation, _) =>
              ProfileQRCodePage(animation: animation),
          transitionsBuilder: (context, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    }

    return Semantics(
      button: true,
      label: _settingsText(
        context,
        zhCN: '个人资料',
        zhTW: '個人資料',
        en: 'Profile',
      ),
      child: SizedBox(
        height: headerHeight,
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: background.gradient,
                  ),
                ),
              ),
            ),
            if (hasImage)
              Positioned.fill(
                child: CachedNetworkImage(
                  imageUrl: background.imageUrl!,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const SizedBox.shrink(),
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withOpacity(hasImage ? 0.18 : 0.00),
                      Colors.black.withOpacity(hasImage ? 0.22 : 0.04),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: background.patternOpacity,
                child: SvgPicture.asset(
                  'assets/images/backgrounds/bg5.svg',
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    headerForeground,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
            Positioned(
              top: isDesktopSidebar ? 18 : topInset + 12,
              left: 22,
              child: _ProfileHeaderIconButton(
                icon: Icons.qr_code_2_rounded,
                foreground: buttonForeground,
                onTap: openQrCode,
              ),
            ),
            Positioned(
              top: isDesktopSidebar ? 20 : topInset + 14,
              right: 22,
              child: _ProfileHeaderEditButton(
                foreground: buttonForeground,
                onTap: openProfileEditor,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: isDesktopSidebar ? 52 : topInset + 56,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: openProfile,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VipAvatarFrame(
                      level: vipLevel,
                      size: 104,
                      isCircle: true,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(
                              vipLevel > 0 ? 0.94 : 1,
                            ),
                            width: vipLevel > 0 ? 2 : 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: AvatarWidget(
                          name: displayName,
                          avatar: avatar,
                          size: 104,
                          isCircle: true,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 38),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 26,
                                height: 1.08,
                                fontWeight: FontWeight.w800,
                                color: headerForeground,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onEmojiTap,
                            child: Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.22),
                                shape: BoxShape.circle,
                              ),
                              child:
                                  emojiStatus != null && emojiStatus.isNotEmpty
                                      ? EmojiStatusWidget(
                                          emoji: emojiStatus,
                                          size: 24,
                                        )
                                      : Icon(
                                          Icons.emoji_emotions_rounded,
                                          size: 18,
                                          color: headerForeground,
                                        ),
                            ),
                          ),
                          if (vipLevel > 0) ...[
                            const SizedBox(width: 8),
                            VipProfileBadge(
                              level: vipLevel,
                              height: 21,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: Text(
                        accountLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          height: 1.15,
                          color: headerMutedForeground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: -8,
              child: Container(
                height: 42,
                decoration: BoxDecoration(
                  color: contentBg,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    if (!isDark)
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 18,
                        offset: const Offset(0, -6),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;

  const _SettingsGroup({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    final cardColor = AppColors.cardFor(context);
    final borderColor =
        isDark ? AppColors.dividerFor(context).withOpacity(0.75) : null;
    final dividerColor = AppColors.dividerFor(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: borderColor == null ? null : Border.all(color: borderColor),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.025),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: List.generate(children.length * 2 - 1, (index) {
            if (index.isOdd) {
              return Divider(height: 1, indent: 62, color: dividerColor);
            }
            return children[index ~/ 2];
          }),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconBgColor;
  final String title;
  final String? subtitle;
  final bool isDark;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconBgColor,
    required this.title,
    this.subtitle,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      splashColor: iconBgColor.withOpacity(0.06),
      highlightColor: iconBgColor.withOpacity(0.04),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(9),
                boxShadow: [
                  BoxShadow(
                    color: iconBgColor.withOpacity(isDark ? 0.18 : 0.16),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 19),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimaryFor(context),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.2,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textTertiaryFor(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 20,
              child: Icon(
                Icons.chevron_right_rounded,
                size: 21,
                color: AppColors.textTertiaryFor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectionSheet extends StatelessWidget {
  final String title;
  final bool isDark;
  final List<_SelectionOption> options;

  const _SelectionSheet({
    required this.title,
    required this.isDark,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    final bottomSpacing = FloatingNavLayout.reservedSpace(context, extra: 8);

    return Material(
      color: AppColors.cardFor(context),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryFor(context),
              ),
            ),
            const SizedBox(height: 16),
            ...options.map(
              (option) => ListTile(
                title: Text(
                  option.title,
                  style: TextStyle(color: AppColors.textPrimaryFor(context)),
                ),
                subtitle: option.subtitle != null
                    ? Text(
                        option.subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textTertiaryFor(context),
                        ),
                      )
                    : null,
                trailing: option.isSelected
                    ? Icon(
                        Icons.check,
                        color: AppColors.controlActiveFor(context),
                      )
                    : null,
                onTap: option.onTap,
              ),
            ),
            SizedBox(height: bottomSpacing),
          ],
        ),
      ),
    );
  }
}

class _SelectionOption {
  final String title;
  final String? subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  _SelectionOption({
    required this.title,
    this.subtitle,
    required this.isSelected,
    required this.onTap,
  });
}

/// 关于页操作
class _AboutAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _AboutAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, size: 28, color: AppColors.linkFor(context)),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textSecondaryFor(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 聊天设置完整页面
class ChatSettingsFullPage extends StatelessWidget {
  const ChatSettingsFullPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: ThemedAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _settingsText(
            context,
            zhCN: '聊天设置',
            zhTW: '聊天設定',
            en: 'Chat Settings',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryFor(context),
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 24),

          // 消息设置
          _SectionTitle(
            title: _settingsText(
              context,
              zhCN: '消息',
              zhTW: '訊息',
              en: 'Messages',
            ),
            isDark: isDark,
          ),
          _SettingsGroup(
            isDark: isDark,
            children: [
              _SwitchTile(
                title: _settingsText(
                  context,
                  zhCN: '消息预览',
                  zhTW: '訊息預覽',
                  en: 'Message Preview',
                ),
                subtitle: _settingsText(
                  context,
                  zhCN: '在通知中显示消息内容',
                  zhTW: '在通知中顯示訊息內容',
                  en: 'Show message content in notifications',
                ),
                value: true,
                isDark: isDark,
                onChanged: (_) {},
              ),
              _SwitchTile(
                title: _settingsText(
                  context,
                  zhCN: '链接预览',
                  zhTW: '連結預覽',
                  en: 'Link Preview',
                ),
                subtitle: _settingsText(
                  context,
                  zhCN: '在消息中显示网页预览',
                  zhTW: '在訊息中顯示網頁預覽',
                  en: 'Show webpage previews in messages',
                ),
                value: true,
                isDark: isDark,
                onChanged: (_) {},
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 外观
          _SectionTitle(
            title: _settingsText(
              context,
              zhCN: '外观',
              zhTW: '外觀',
              en: 'Appearance',
            ),
            isDark: isDark,
          ),
          _SettingsGroup(
            isDark: isDark,
            children: [
              _TapTile(
                title: _settingsText(
                  context,
                  zhCN: '主题风格',
                  zhTW: '主題風格',
                  en: 'Theme Style',
                ),
                subtitle: _settingsText(
                  context,
                  zhCN: '切换主题色彩与显示模式',
                  zhTW: '切換主題色彩與顯示模式',
                  en: 'Switch theme color and display mode',
                ),
                isDark: isDark,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ThemePickerPage(),
                  ),
                ),
              ),
              _TapTile(
                title: _settingsText(
                  context,
                  zhCN: '聊天背景',
                  zhTW: '聊天背景',
                  en: 'Chat Background',
                ),
                subtitle: _settingsText(
                  context,
                  zhCN: '自定义聊天背景',
                  zhTW: '自訂聊天背景',
                  en: 'Customize chat background',
                ),
                isDark: isDark,
                onTap: () {},
              ),
              _TapTile(
                title: _settingsText(
                  context,
                  zhCN: '气泡颜色',
                  zhTW: '氣泡顏色',
                  en: 'Bubble Color',
                ),
                subtitle: _settingsText(
                  context,
                  zhCN: '默认',
                  zhTW: '預設',
                  en: 'Default',
                ),
                isDark: isDark,
                onTap: () {},
              ),
              _SliderTile(
                title: _settingsText(
                  context,
                  zhCN: '字体大小',
                  zhTW: '字體大小',
                  en: 'Font Size',
                ),
                value: 16,
                min: 12,
                max: 24,
                isDark: isDark,
                onChanged: (_) {},
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 媒体
          _SectionTitle(
            title: _settingsText(
              context,
              zhCN: '媒体',
              zhTW: '媒體',
              en: 'Media',
            ),
            isDark: isDark,
          ),
          _SettingsGroup(
            isDark: isDark,
            children: [
              _SwitchTile(
                title: _settingsText(
                  context,
                  zhCN: '自动下载图片',
                  zhTW: '自動下載圖片',
                  en: 'Auto-Download Images',
                ),
                value: true,
                isDark: isDark,
                onChanged: (_) {},
              ),
              _SwitchTile(
                title: _settingsText(
                  context,
                  zhCN: '自动下载视频',
                  zhTW: '自動下載影片',
                  en: 'Auto-Download Videos',
                ),
                value: false,
                isDark: isDark,
                onChanged: (_) {},
              ),
              _SwitchTile(
                title: _settingsText(
                  context,
                  zhCN: '自动播放GIF',
                  zhTW: '自動播放 GIF',
                  en: 'Auto-Play GIFs',
                ),
                value: true,
                isDark: isDark,
                onChanged: (_) {},
              ),
            ],
          ),

          const SizedBox(height: 100),
        ],
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
  final bool isDark;
  final VoidCallback onTap;

  const _TapTile({
    required this.title,
    this.subtitle,
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
        color: isDark ? Colors.white : Colors.black,
      ),
      subtitleStyle: TextStyle(
        fontSize: 14,
        height: 1.3,
        color: AppColors.textTertiaryFor(context),
      ),
      chevronColor: AppColors.textTertiaryFor(context),
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }
}

class _SliderTile extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final bool isDark;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
          Row(
            children: [
              Text(
                _settingsText(
                  context,
                  zhCN: '小',
                  zhTW: '小',
                  en: 'Small',
                ),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiaryFor(context),
                ),
              ),
              Expanded(
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  activeColor: AppColors.controlActiveFor(context),
                  onChanged: onChanged,
                ),
              ),
              Text(
                _settingsText(
                  context,
                  zhCN: '大',
                  zhTW: '大',
                  en: 'Large',
                ),
                style: TextStyle(
                  fontSize: 18,
                  color: AppColors.textTertiaryFor(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 我的动态页面
class MyMomentsPage extends ConsumerStatefulWidget {
  const MyMomentsPage({super.key});

  @override
  ConsumerState<MyMomentsPage> createState() => _MyMomentsPageState();
}

class _MyMomentsPageState extends ConsumerState<MyMomentsPage> {
  List<dynamic> _moments = [];
  bool _isLoading = true;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.get('/moment/my/moments');
      if (response.isSuccess && response.data != null) {
        setState(() => _moments = response.data['list'] ?? []);
      }
    } catch (e) {
      debugPrint('加载失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: ThemedAppBar(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _settingsText(
            context,
            zhCN: '我的动态',
            zhTW: '我的動態',
            en: 'My Moments',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _moments.isEmpty
              ? _buildEmptyState(
                  isDark,
                  Icons.article_outlined,
                  _settingsText(
                    context,
                    zhCN: '暂无动态',
                    zhTW: '暫無動態',
                    en: 'No moments yet',
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _moments.length,
                    itemBuilder: (context, index) =>
                        _MomentTile(moment: _moments[index], isDark: isDark),
                  ),
                ),
    );
  }

  Widget _buildEmptyState(bool isDark, IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: AppColors.textTertiaryFor(context).withOpacity(0.72),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondaryFor(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 我的点赞页面
class MyLikesPage extends ConsumerStatefulWidget {
  const MyLikesPage({super.key});

  @override
  ConsumerState<MyLikesPage> createState() => _MyLikesPageState();
}

class _MyLikesPageState extends ConsumerState<MyLikesPage> {
  List<dynamic> _moments = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.get('/moment/my/likes');
      if (response.isSuccess && response.data != null) {
        setState(() => _moments = response.data['list'] ?? []);
      }
    } catch (e) {
      debugPrint('加载失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: ThemedAppBar(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _settingsText(
            context,
            zhCN: '我的点赞',
            zhTW: '我的按讚',
            en: 'My Likes',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _moments.isEmpty
              ? _buildEmptyState(
                  isDark,
                  Icons.favorite_outline,
                  _settingsText(
                    context,
                    zhCN: '暂无点赞',
                    zhTW: '暫無按讚',
                    en: 'No likes yet',
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _moments.length,
                    itemBuilder: (context, index) =>
                        _MomentTile(moment: _moments[index], isDark: isDark),
                  ),
                ),
    );
  }

  Widget _buildEmptyState(bool isDark, IconData icon, String text) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: AppColors.textTertiaryFor(context).withOpacity(0.72),
          ),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondaryFor(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// 我的评论页面
class MyCommentsPage extends ConsumerStatefulWidget {
  const MyCommentsPage({super.key});

  @override
  ConsumerState<MyCommentsPage> createState() => _MyCommentsPageState();
}

class _MyCommentsPageState extends ConsumerState<MyCommentsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _receivedComments = []; // 收到的评论
  List<dynamic> _sentComments = []; // 我发出的评论
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiClientProvider);

      // 加载收到的评论（别人评论我的动态 + 别人回复我的评论）
      final receivedResponse = await api.get(
        '/moment/my/comments',
        queryParameters: {'type': 'all'},
      );
      if (receivedResponse.isSuccess && receivedResponse.data != null) {
        _receivedComments = receivedResponse.data['list'] ?? [];
      }

      // 加载我发出的评论
      final sentResponse = await api.get(
        '/moment/my/comments',
        queryParameters: {'type': 'sent'},
      );
      if (sentResponse.isSuccess && sentResponse.data != null) {
        _sentComments = sentResponse.data['list'] ?? [];
      }
    } catch (e) {
      debugPrint('加载失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: ThemedAppBar(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _settingsText(
            context,
            zhCN: '我的评论',
            zhTW: '我的評論',
            en: 'My Comments',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 自定义 Tab 切换
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelColor: isDark ? Colors.white : Colors.black,
              unselectedLabelColor: AppColors.textSecondaryFor(context),
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
              tabs: [
                Tab(
                  text: _settingsText(
                    context,
                    zhCN: '收到的',
                    zhTW: '收到的',
                    en: 'Received',
                  ),
                ),
                Tab(
                  text: _settingsText(
                    context,
                    zhCN: '发出的',
                    zhTW: '發出的',
                    en: 'Sent',
                  ),
                ),
              ],
            ),
          ),
          // 内容区域
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCommentList(
                        _receivedComments,
                        isDark,
                        _settingsText(
                          context,
                          zhCN: '暂无收到的评论',
                          zhTW: '暫無收到的評論',
                          en: 'No received comments yet',
                        ),
                      ),
                      _buildCommentList(
                        _sentComments,
                        isDark,
                        _settingsText(
                          context,
                          zhCN: '暂无发出的评论',
                          zhTW: '暫無發出的評論',
                          en: 'No sent comments yet',
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentList(
    List<dynamic> comments,
    bool isDark,
    String emptyText,
  ) {
    if (comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 64,
              color: AppColors.textTertiaryFor(context).withOpacity(0.72),
            ),
            const SizedBox(height: 16),
            Text(
              emptyText,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textSecondaryFor(context),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: comments.length,
        itemBuilder: (context, index) =>
            _CommentTile(comment: comments[index], isDark: isDark),
      ),
    );
  }
}

/// 动态列表项 - 包含发布者信息和媒体
class _MomentTile extends StatelessWidget {
  final dynamic moment;
  final bool isDark;

  const _MomentTile({required this.moment, required this.isDark});

  void _openDetail(BuildContext context) {
    HapticFeedback.selectionClick();

    // 将 JSON 数据转换为 Moment 对象
    final momentObj = Moment.fromJson(Map<String, dynamic>.from(moment));

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MomentDetailPage(moment: momentObj),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = moment['content'] ?? '';
    final userName = moment['user_name'] ??
        _settingsText(
          context,
          zhCN: '用户',
          zhTW: '使用者',
          en: 'User',
        );
    final rawAvatar = moment['user_avatar'] ?? '';
    final userAvatar = rawAvatar.isNotEmpty
        ? (ApiConfig.getMediaUrl(rawAvatar) ?? rawAvatar)
        : '';
    final likeCount = moment['like_count'] ?? 0;
    final commentCount = moment['comment_count'] ?? 0;
    final createdAt = moment['created_at'] ?? '';
    final rawMediaUrls = (moment['media_urls'] as List<dynamic>?) ?? [];
    final mediaUrls = rawMediaUrls
        .map((url) => ApiConfig.getMediaUrl(url.toString()) ?? url.toString())
        .toList();

    return GestureDetector(
      onTap: () => _openDetail(context),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 用户信息行
            Row(
              children: [
                // 头像
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.emphasisSoftFor(context),
                  ),
                  child: userAvatar.isNotEmpty
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: userAvatar,
                            fit: BoxFit.cover,
                            memCacheWidth: 84,
                            memCacheHeight: 84,
                            errorWidget: (_, __, ___) => Center(
                              child: Text(
                                userName.isNotEmpty
                                    ? userName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.linkFor(context),
                                ),
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            userName.isNotEmpty
                                ? userName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: AppColors.linkFor(context),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                // 用户名和时间
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatTime(context, createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiaryFor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 内容
            if (content.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                content,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // 媒体图片
            if (mediaUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildMediaGrid(mediaUrls),
            ],

            // 底部互动信息
            const SizedBox(height: 14),
            Row(
              children: [
                // 点赞
                Icon(
                  Icons.favorite,
                  size: 16,
                  color: Colors.red.withOpacity(0.7),
                ),
                const SizedBox(width: 4),
                Text(
                  '$likeCount',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
                const SizedBox(width: 20),
                // 评论
                Icon(
                  Icons.chat_bubble_outline,
                  size: 15,
                  color: AppColors.textTertiaryFor(context),
                ),
                const SizedBox(width: 4),
                Text(
                  '$commentCount',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaGrid(List<dynamic> urls) {
    if (urls.isEmpty) return const SizedBox.shrink();

    if (urls.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CachedNetworkImage(
          imageUrl: urls[0].toString(),
          height: 180,
          width: double.infinity,
          fit: BoxFit.cover,
          memCacheWidth: 400,
          memCacheHeight: 360,
          errorWidget: (_, __, ___) => Container(
            height: 180,
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
            child: Icon(
              Icons.image,
              size: 40,
              color: isDark ? AppColors.darkTextTertiary : Colors.black12,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: urls.length > 4 ? 4 : urls.length,
        itemBuilder: (context, index) {
          return Container(
            width: 100,
            margin: EdgeInsets.only(right: index < urls.length - 1 ? 8 : 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: urls[index].toString(),
                    fit: BoxFit.cover,
                    memCacheWidth: 200,
                    memCacheHeight: 200,
                    errorWidget: (_, __, ___) => Container(
                      color: isDark
                          ? Colors.white10
                          : Colors.black.withOpacity(0.05),
                      child: Icon(
                        Icons.image,
                        color: AppColors.textTertiaryFor(context)
                            .withOpacity(0.72),
                      ),
                    ),
                  ),
                  if (index == 3 && urls.length > 4)
                    Container(
                      color: Colors.black45,
                      child: Center(
                        child: Text(
                          '+${urls.length - 4}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatTime(BuildContext context, String dateStr) {
    return _settingsTimeAgoText(context, dateStr);
  }
}

/// 评论列表项 - 包含头像
class _CommentTile extends ConsumerWidget {
  final dynamic comment;
  final bool isDark;

  const _CommentTile({required this.comment, required this.isDark});

  Future<void> _openMomentDetail(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();

    final momentId = comment['moment_id'];
    if (momentId == null) return;

    // 加载动态详情
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.get('/moment/$momentId/detail');

      if (response.isSuccess && response.data != null) {
        final momentObj = Moment.fromJson(
          Map<String, dynamic>.from(response.data),
        );
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  MomentDetailPage(moment: momentObj, showComments: true),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('打开动态失败: $e');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = comment['content'] ?? '';
    final userName = comment['user_name'] ?? '';
    final rawAvatar = comment['user_avatar'] ?? '';
    final userAvatar = rawAvatar.isNotEmpty
        ? (ApiConfig.getMediaUrl(rawAvatar) ?? rawAvatar)
        : '';
    final momentBrief = comment['moment_brief'] ?? '';
    final createdAt = comment['created_at'] ?? '';
    final type = comment['type'] ?? '';
    final replyToName = comment['reply_to_name'] ?? '';

    String typeLabel = '';
    Color typeColor = AppColors.linkFor(context);
    if (type == 'received_comment') {
      typeLabel = _settingsCommentTypeLabel(
        context,
        type: type,
        replyToName: replyToName,
      );
      typeColor = const Color(0xFF34C759);
    } else if (type == 'received_reply') {
      typeLabel = _settingsCommentTypeLabel(
        context,
        type: type,
        replyToName: replyToName,
      );
      typeColor = const Color(0xFF5856D6);
    } else if (type == 'sent') {
      typeLabel = _settingsCommentTypeLabel(
        context,
        type: type,
        replyToName: replyToName,
      );
      typeColor = AppColors.linkFor(context);
    }

    return GestureDetector(
      onTap: () => _openMomentDetail(context, ref),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.15 : 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 用户信息行
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 头像
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: typeColor.withOpacity(0.15),
                  ),
                  child: userAvatar.isNotEmpty
                      ? ClipOval(
                          child: CachedNetworkImage(
                            imageUrl: userAvatar,
                            fit: BoxFit.cover,
                            memCacheWidth: 80,
                            memCacheHeight: 80,
                            errorWidget: (_, __, ___) => Center(
                              child: Text(
                                userName.isNotEmpty
                                    ? userName[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: typeColor,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            userName.isNotEmpty
                                ? userName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: typeColor,
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                // 用户名、类型标签、时间
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              userName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: typeColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              typeLabel,
                              style: TextStyle(
                                fontSize: 11,
                                color: typeColor,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatTime(context, createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textTertiaryFor(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            // 评论内容
            const SizedBox(height: 12),
            Text(
              content,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),

            // 原动态简介
            if (momentBrief.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.black.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left: BorderSide(
                      color: AppColors.linkFor(context).withOpacity(0.5),
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  momentBrief,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textSecondaryFor(context),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatTime(BuildContext context, String dateStr) {
    return _settingsTimeAgoText(context, dateStr);
  }
}
