import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/constants/emoji_animations.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/utils/floating_nav_layout.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../chat/widgets/emoji_picker.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../moments/providers/moment_provider.dart';
import '../../moments/pages/moments_page.dart';
import 'profile_page.dart';
import 'membership_page.dart';
import 'notification_settings_page.dart';
import 'privacy_settings_page.dart';
import 'data_storage_page.dart';
import 'devices_page.dart';
import 'stickers_page.dart';
import 'faq_page.dart';
import 'chat_settings_page.dart';
import 'network_settings_page.dart';
import 'checkin_page.dart';
import '../../auth/pages/agreement_page.dart';
import '../../home/pages/home_desktop_page.dart';

/// 设备数量 Provider
final deviceCountProvider = FutureProvider<int>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    // 使用 /user/devices API 与设备页面保持一致
    final response = await api.get<Map<String, dynamic>>('/user/devices');
    if (response.isSuccess && response.data != null) {
      final devices = response.data!['devices'] as List? ?? [];
      final uniqueDeviceIds = devices
          .map((item) => (item as Map?)?['device_id']?.toString().trim() ?? '')
          .where((deviceId) => deviceId.isNotEmpty)
          .toSet();
      if (uniqueDeviceIds.isNotEmpty) {
        return uniqueDeviceIds.length;
      }
      return devices.length;
    }
  } catch (e) {
    if (kDebugMode) debugPrint('[Settings] Get device count error: $e');
  }
  return 1; // 默认至少有当前设备
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
    final configuredName =
        ref.watch(systemSettingsProvider).valueOrNull?.displayName.trim() ?? '';
    final appName =
        configuredName.isNotEmpty ? configuredName : kDefaultAppDisplayName;
    final floatingBottomSpace = isDesktopSidebar
        ? 32.0
        : FloatingNavLayout.reservedSpace(context, extra: 24);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          //  顶部栏
          SliverAppBar(
            expandedHeight: 0,
            floating: true,
            pinned: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            surfaceTintColor: Colors.transparent,
            title: Text(
              l10n.settings,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            centerTitle: true,
          ),

          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 16),

                // 用户信息卡片
                _UserProfileCard(
                  isDark: isDark,
                  isDesktopSidebar: isDesktopSidebar,
                ),

                const SizedBox(height: 24),

                // 账号设置
                _SettingsGroup(
                  isDark: isDark,
                  children: [
                    // Premium 会员入口已隐藏
                    _SettingsTile(
                      icon: Icons.account_balance_wallet_outlined,
                      iconBgColor: const Color(0xFFFF9500),
                      title: '钱包',
                      isDark: isDark,
                      onTap: () => context.push('/wallet'),
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        final s = ref.watch(systemSettingsProvider).valueOrNull;
                        if (s == null || !s.checkinEnabled) {
                          return const SizedBox.shrink();
                        }
                        return _SettingsTile(
                          icon: Icons.calendar_today_outlined,
                          iconBgColor: const Color(0xFF34C759),
                          title: '签到',
                          isDark: isDark,
                          onTap: () => _openPage(
                            context,
                            const CheckinPage(),
                            ref,
                          ),
                        );
                      },
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
                        desktopPanelType: DesktopPanelType.settingsNotification,
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
                        desktopPanelType: DesktopPanelType.settingsDataStorage,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 应用设置
                _SettingsGroup(
                  isDark: isDark,
                  children: [
                    _SettingsTile(
                      icon: Icons.chat_bubble_outline,
                      iconBgColor: AppColors.primary,
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
                      subtitle: null, // 隐藏设备数量
                      isDark: isDark,
                      onTap: () => _openPage(
                        context,
                        const DevicesPage(),
                        ref,
                        desktopPanelType: DesktopPanelType.settingsDevices,
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.network_check_rounded,
                      iconBgColor: const Color(0xFF007AFF),
                      title: '网络线路',
                      isDark: isDark,
                      onTap: () => _openPage(
                        context,
                        const NetworkSettingsPage(),
                        ref,
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
                      iconBgColor: AppColors.primary,
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
                        final displayVersion =
                            settings?.systemVersion.trim().isNotEmpty == true
                                ? settings!.systemVersion.trim()
                                : info.version;
                        return Text(
                          '$appName v$displayVersion',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        );
                      },
                      loading: () => Text(
                        appName,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      ),
                      error: (_, __) => Text(
                        appName,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white38 : Colors.black38,
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

  String _getThemeModeText(AppThemeMode mode, AppLocalizations l10n) {
    switch (mode) {
      case AppThemeMode.system:
        return l10n.systemMode;
      case AppThemeMode.light:
        return l10n.lightMode;
      case AppThemeMode.dark:
        return l10n.darkMode;
      case AppThemeMode.chineseRed:
        return l10n.chineseRedMode;
    }
  }

  void _showThemeSheet(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    final themeMode = ref.read(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEn = l10n.language.code == 'en';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _SelectionSheet(
        title: l10n.appearance,
        isDark: isDark,
        options: [
          _SelectionOption(
            title: l10n.systemMode,
            subtitle: isEn ? 'Auto switch dark/light' : '自动切换深色/浅色',
            isSelected: themeMode == AppThemeMode.system,
            onTap: () {
              ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(AppThemeMode.system);
              Navigator.pop(context);
            },
          ),
          _SelectionOption(
            title: l10n.lightMode,
            isSelected: themeMode == AppThemeMode.light,
            onTap: () {
              ref
                  .read(themeModeProvider.notifier)
                  .setThemeMode(AppThemeMode.light);
              Navigator.pop(context);
            },
          ),
          _SelectionOption(
            title: l10n.darkMode,
            isSelected: themeMode == AppThemeMode.dark,
            onTap: () {
              ref.read(themeModeProvider.notifier).setThemeMode(AppThemeMode.dark);
              Navigator.pop(context);
            },
          ),
          _SelectionOption(
            title: l10n.chineseRedMode,
            subtitle: isEn ? 'Classic Chinese red style' : '传统中国红，喜庆典雅',
            isSelected: themeMode == AppThemeMode.chineseRed,
            leading: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.chineseRedGradient,
              ),
            ),
            onTap: () {
              ref.read(themeModeProvider.notifier).setThemeMode(AppThemeMode.chineseRed);
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
      backgroundColor: Colors.transparent,
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
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
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
                    final appName =
                        configuredName.isNotEmpty ? configuredName : '壹信IM';
                    final versionText = configuredVersion.isNotEmpty
                        ? configuredVersion
                        : packageInfo.version;
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
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'v$versionText (Build ${packageInfo.buildNumber}) - 补丁测试 P3 2026-05-11',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '一款简洁、快速、安全的即时通讯应用',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _AboutAction(
                              icon: Icons.star_border,
                              label: '评分',
                              onTap: () {},
                            ),
                            _AboutAction(
                              icon: Icons.share_outlined,
                              label: '分享',
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
                                '用户协议',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.primary,
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
                                  color:
                                      isDark ? Colors.white24 : Colors.black26,
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
                                '隐私政策',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppColors.primary,
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
                        '加载中...',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white54 : Colors.black45,
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
                        '壹信IM',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '版本未知',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white54 : Colors.black45,
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

/// 用户信息卡片
class _UserProfileCard extends ConsumerStatefulWidget {
  final bool isDark;
  final bool isDesktopSidebar;

  const _UserProfileCard({required this.isDark, this.isDesktopSidebar = false});

  @override
  ConsumerState<_UserProfileCard> createState() => _UserProfileCardState();
}

class _UserProfileCardState extends ConsumerState<_UserProfileCard> {
  /// 格式化手机号（完整显示）
  String _formatPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '未绑定手机';
    return phone;
  }

  // 昵称颜色列表（与 personalization_page.dart 保持一致）
  static const List<dynamic> _nameColors = [
    Color(0xFF3390EC), // 蓝色
    Color(0xFF4FAE4E), // 绿色
    Color(0xFFF5A623), // 橙色
    Color(0xFFE05656), // 红色
    Color(0xFF9B7CE0), // 紫色
    Color(0xFF50B6C5), // 青色
    Color(0xFFFF7EB3), // 粉色
    Color(0xFF7D8B99), // 灰色
    // 双色渐变
    [Color(0xFF5B9EE1), Color(0xFF54C7A6)],
    [Color(0xFF54C7A6), Color(0xFFB8E986)],
    [Color(0xFFF5A623), Color(0xFFE05656)],
    [Color(0xFF9B7CE0), Color(0xFF50B6C5)],
    [Color(0xFF50B6C5), Color(0xFF5B9EE1)],
    [Color(0xFFFF7EB3), Color(0xFFF5A623)],
    [Color(0xFF5B9EE1), Color(0xFF9B7CE0)],
    [Color(0xFFE05656), Color(0xFF9B7CE0)],
  ];

  /// 获取用户昵称颜色
  dynamic _getNameColor(String? nicknameColor) {
    if (nicknameColor != null && nicknameColor.isNotEmpty) {
      final parts = nicknameColor.split(',');
      for (final part in parts) {
        if (part.startsWith('name:')) {
          final index = int.tryParse(part.substring(5)) ?? 0;
          final clampedIndex = index.clamp(0, _nameColors.length - 1);
          return _nameColors[clampedIndex];
        }
      }
    }
    return null;
  }

  /// 显示表情状态选择器（毛玻璃效果）
  void _showEmojiStatusPicker() {
    HapticFeedback.selectionClick();
    final currentEmoji = ref.read(authServiceProvider).user?.emojiAvatar;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                    color: isDark ? Colors.white24 : Colors.black12,
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
                        '设置表情状态',
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
                            '清除',
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
                      final api = ref.read(apiClientProvider);
                      final response = await api.put(
                        '/user/me',
                        data: {'emoji_avatar': emoji},
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

  /// 构建动态表情状态
  Widget _buildEmojiStatus(String emoji, {double size = 22}) {
    final animatedEmoji = EmojiAnimations.findByEmoji(emoji);
    if (animatedEmoji != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Lottie.asset(
          animatedEmoji.path,
          repeat: true,
          animate: true,
          fit: BoxFit.contain,
        ),
      );
    }
    return Text(emoji, style: TextStyle(fontSize: size * 0.8));
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authServiceProvider);
    final user = authState.user;
    final isDark = widget.isDark;

    // 用户显示名称
    final displayName = user?.nickname.isNotEmpty == true
        ? user!.nickname
        : (user?.username ?? '未登录');

    // 手机号
    final phoneDisplay = _formatPhone(user?.phone);

    // 头像
    final avatar = user?.avatar;

    // 昵称颜色
    final nameColor = _getNameColor(user?.nicknameColor);

    // 表情状态
    final emojiStatus = user?.emojiAvatar;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        if (widget.isDesktopSidebar) {
          ref.read(desktopProfileProvider.notifier).state =
              const DesktopProfileInfo(
            type: DesktopPanelType.settingsProfile,
            id: 'profile',
          );
        } else {
          Navigator.of(
            context,
            rootNavigator: true,
          ).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // 头像
            AvatarWidget(name: displayName, avatar: avatar, size: 64),
            const SizedBox(width: 16),

            // 信息
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 昵称 + 表情状态
                  Row(
                    children: [
                      Flexible(
                        child: _buildColoredName(
                          displayName,
                          nameColor,
                          isDark,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // 表情状态（点击可设置）
                      GestureDetector(
                        onTap: _showEmojiStatusPicker,
                        child: emojiStatus != null && emojiStatus.isNotEmpty
                            ? _buildEmojiStatus(emojiStatus, size: 24)
                            : Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.primary.withOpacity(0.2),
                                      AppColors.primary.withOpacity(0.1),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.emoji_emotions_rounded,
                                  size: 16,
                                  color: AppColors.primary,
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    phoneDisplay,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white54 : Colors.black45,
                    ),
                  ),
                ],
              ),
            ),

            Icon(
              Icons.chevron_right,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }

  /// 带颜色的昵称
  Widget _buildColoredName(String name, dynamic colorItem, bool isDark) {
    if (colorItem == null) {
      return Text(
        name,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white : Colors.black,
        ),
      );
    }

    if (colorItem is List) {
      final colors = colorItem.whereType<Color>().toList();
      if (colors.length >= 2) {
        return ShaderMask(
          shaderCallback: (bounds) =>
              LinearGradient(colors: colors).createShader(bounds),
          child: Text(
            name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        );
      }
    }
    if (colorItem is Color) {
      return Text(
        name,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: colorItem,
        ),
      );
    }
    return Text(
      name,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : Colors.black,
      ),
    );
  }
}

/// 设置分组
class _SettingsGroup extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;

  const _SettingsGroup({required this.isDark, required this.children});

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
              indent: 54,
              color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
            );
          }
          return children[index ~/ 2];
        }),
      ),
    );
  }
}

/// 设置项
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
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // 图标
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconBgColor,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),

            // 标题
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),

            // 副标题
            if (subtitle != null)
              Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),

            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }
}

/// 选择面板
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

    return Container(
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
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 16),
            ...options.map(
              (option) => ListTile(
                title: Text(
                  option.title,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                ),
                subtitle: option.subtitle != null
                    ? Text(
                        option.subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white38 : Colors.black38,
                        ),
                      )
                    : null,
                leading: option.leading,
                trailing: option.isSelected
                    ? Icon(Icons.check, color: AppColors.primary)
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
  final Widget? leading;

  _SelectionOption({
    required this.title,
    this.subtitle,
    required this.isSelected,
    required this.onTap,
    this.leading,
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
          Icon(icon, size: 28, color: AppColors.primary),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.black54,
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
          '聊天设置',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          const SizedBox(height: 24),

          // 消息设置
          _SectionTitle(title: '消息', isDark: isDark),
          _SettingsGroup(
            isDark: isDark,
            children: [
              _SwitchTile(
                title: '消息预览',
                subtitle: '在通知中显示消息内容',
                value: true,
                isDark: isDark,
                onChanged: (_) {},
              ),
              _SwitchTile(
                title: '链接预览',
                subtitle: '在消息中显示网页预览',
                value: true,
                isDark: isDark,
                onChanged: (_) {},
              ),
            ],
          ),

          const SizedBox(height: 24),

          // 外观
          _SectionTitle(title: '外观', isDark: isDark),
          _SettingsGroup(
            isDark: isDark,
            children: [
              _TapTile(
                title: '聊天背景',
                subtitle: '自定义聊天背景',
                isDark: isDark,
                onTap: () {},
              ),
              _TapTile(
                title: '气泡颜色',
                subtitle: '默认',
                isDark: isDark,
                onTap: () {},
              ),
              _SliderTile(
                title: '字体大小',
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
          _SectionTitle(title: '媒体', isDark: isDark),
          _SettingsGroup(
            isDark: isDark,
            children: [
              _SwitchTile(
                title: '自动下载图片',
                value: true,
                isDark: isDark,
                onChanged: (_) {},
              ),
              _SwitchTile(
                title: '自动下载视频',
                value: false,
                isDark: isDark,
                onChanged: (_) {},
              ),
              _SwitchTile(
                title: '自动播放GIF',
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
          color: isDark ? Colors.white38 : Colors.black38,
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
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: isDark ? Colors.white : Colors.black,
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
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
          ],
        ),
      ),
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
                '小',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              Expanded(
                child: Slider(
                  value: value,
                  min: min,
                  max: max,
                  activeColor: AppColors.primary,
                  onChanged: onChanged,
                ),
              ),
              Text(
                '大',
                style: TextStyle(
                  fontSize: 18,
                  color: isDark ? Colors.white38 : Colors.black38,
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
      if (kDebugMode) debugPrint('加载失败: $e');
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
      appBar: AppBar(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '我的动态',
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
              ? _buildEmptyState(isDark, Icons.article_outlined, '暂无动态')
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
          Icon(icon, size: 64, color: isDark ? Colors.white24 : Colors.black12),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white54 : Colors.black45,
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
      if (kDebugMode) debugPrint('加载失败: $e');
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
      appBar: AppBar(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '我的点赞',
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
              ? _buildEmptyState(isDark, Icons.favorite_outline, '暂无点赞')
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
          Icon(icon, size: 64, color: isDark ? Colors.white24 : Colors.black12),
          const SizedBox(height: 16),
          Text(
            text,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white54 : Colors.black45,
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
      if (kDebugMode) debugPrint('加载失败: $e');
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
      appBar: AppBar(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '我的评论',
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
              unselectedLabelColor: isDark ? Colors.white54 : Colors.black45,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
              tabs: const [
                Tab(text: '收到的'),
                Tab(text: '发出的'),
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
                      _buildCommentList(_receivedComments, isDark, '暂无收到的评论'),
                      _buildCommentList(_sentComments, isDark, '暂无发出的评论'),
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
              color: isDark ? Colors.white24 : Colors.black12,
            ),
            const SizedBox(height: 16),
            Text(
              emptyText,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white54 : Colors.black45,
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
    final userName = moment['user_name'] ?? '用户';
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
                    color: AppColors.primary.withOpacity(0.1),
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
                                  color: AppColors.primary,
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
                              color: AppColors.primary,
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
                        _formatTime(createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38,
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
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(width: 20),
                // 评论
                Icon(
                  Icons.chat_bubble_outline,
                  size: 15,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                const SizedBox(width: 4),
                Text(
                  '$commentCount',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white60 : Colors.black54,
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
              color: isDark ? Colors.white24 : Colors.black12,
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
                        color: isDark ? Colors.white24 : Colors.black12,
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

  String _formatTime(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${date.month}-${date.day}';
    } catch (e) {
      return dateStr;
    }
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
      if (kDebugMode) debugPrint('打开动态失败: $e');
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
    Color typeColor = AppColors.primary;
    if (type == 'received_comment') {
      typeLabel = '评论了你的动态';
      typeColor = const Color(0xFF34C759);
    } else if (type == 'received_reply') {
      typeLabel = '回复了你';
      typeColor = const Color(0xFF5856D6);
    } else if (type == 'sent') {
      typeLabel = replyToName.isNotEmpty ? '回复 $replyToName' : '评论';
      typeColor = AppColors.primary;
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
                        _formatTime(createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white38 : Colors.black38,
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
                      color: AppColors.primary.withOpacity(0.5),
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  momentBrief,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: isDark ? Colors.white54 : Colors.black54,
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

  String _formatTime(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${date.month}-${date.day}';
    } catch (e) {
      return dateStr;
    }
  }
}
