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
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../moments/providers/moment_provider.dart';
import '../../moments/pages/moments_page.dart';
import 'profile_page.dart';
import 'personalization_page.dart';
import 'membership_page.dart';
import '../../wallet/pages/wallet_page.dart';
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
  return 1;
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
  final bool isDesktopSidebar;

  const SettingsPage({super.key, this.isDesktopSidebar = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final configuredName =
        ref.watch(systemSettingsProvider).valueOrNull?.displayName.trim() ?? '';
    final appName =
        configuredName.isNotEmpty ? configuredName : kDefaultAppDisplayName;
    final floatingBottomSpace = isDesktopSidebar
        ? 32.0
        : FloatingNavLayout.reservedSpace(context, extra: 24);

    final Color scaffoldBg =
        isDark ? const Color(0xFF0A0B10) : const Color(0xFFF3F4F8);
    final Color labelColor = isDark ? Colors.white54 : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            pinned: true,
            floating: false,
            elevation: 0,
            backgroundColor: scaffoldBg,
            surfaceTintColor: scaffoldBg,
            centerTitle: false,
            titleSpacing: 20,
            toolbarHeight: 56,
            leading: const SizedBox.shrink(),
            leadingWidth: 0,
            title: Text(
              l10n.tabMe,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            actions: [
              _CircleIconButton(
                icon: Icons.qr_code_scanner_rounded,
                isDark: isDark,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context, rootNavigator: true).pushNamed('/scan');
                },
              ),
              const SizedBox(width: 10),
              _CircleIconButton(
                icon: Icons.tune_rounded,
                isDark: isDark,
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      builder: (_) => PersonalizationPage(),
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: _HeroProfileCard(
                isDark: isDark,
                isDesktopSidebar: isDesktopSidebar,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverToBoxAdapter(
            child: _QuickActionsRow(isDark: isDark),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 22)),
          SliverToBoxAdapter(
            child: _SectionLabel(text: '账户与安全', color: labelColor),
          ),
          SliverToBoxAdapter(
            child: _SettingsGroup(
              isDark: isDark,
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final s = ref.watch(systemSettingsProvider).valueOrNull;
                    if (s == null || !s.checkinEnabled) {
                      return const SizedBox.shrink();
                    }
                    return _SettingsTile(
                      icon: Icons.local_fire_department_rounded,
                      iconGradient: const [
                        Color(0xFFFF9A3D),
                        Color(0xFFFF3B30),
                      ],
                      title: '每日签到',
                      description: '连签解锁积分、专属贴纸与奖励',
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
                  icon: Icons.notifications_active_outlined,
                  iconGradient: const [Color(0xFFFF375F), Color(0xFFFF2D55)],
                  title: l10n.notificationSettings,
                  description: '通知声、振动、免打扰与铃声偏好',
                  isDark: isDark,
                  onTap: () => _openPage(
                    context,
                    const NotificationSettingsPage(),
                    ref,
                    desktopPanelType: DesktopPanelType.settingsNotification,
                  ),
                ),
                _SettingsTile(
                  icon: Icons.lock_outline_rounded,
                  iconGradient: const [Color(0xFF34C759), Color(0xFF30D158)],
                  title: l10n.privacy,
                  description: '黑名单、可见性、密码与权限安全',
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
                  iconGradient: const [Color(0xFF8E8E93), Color(0xFF636366)],
                  title: l10n.dataStorage,
                  description: '缓存清理、云端空间、离线下载',
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
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 22)),
          SliverToBoxAdapter(
            child: _SectionLabel(text: '偏好设置', color: labelColor),
          ),
          SliverToBoxAdapter(
            child: _SettingsGroup(
              isDark: isDark,
              children: [
                _SettingsTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  iconGradient: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  title: l10n.chatSettings,
                  description: '气泡样式、字号、聊天背景',
                  isDark: isDark,
                  onTap: () => _openPage(
                    context,
                    const ChatSettingsPage(),
                    ref,
                    desktopPanelType: DesktopPanelType.settingsChatSettings,
                  ),
                ),
                _SettingsTile(
                  icon: Icons.devices_other_outlined,
                  iconGradient: const [Color(0xFF5856D6), Color(0xFF7C7BE8)],
                  title: l10n.devices,
                  description: '登录设备管理与远程下线',
                  isDark: isDark,
                  onTap: () => _openPage(
                    context,
                    const DevicesPage(),
                    ref,
                    desktopPanelType: DesktopPanelType.settingsDevices,
                  ),
                ),
                _SettingsTile(
                  icon: Icons.public_outlined,
                  iconGradient: const [Color(0xFF00C2A8), Color(0xFF06D6A0)],
                  title: '网络线路',
                  description: '切换节点、加速与连接诊断',
                  isDark: isDark,
                  onTap: () => _openPage(
                    context,
                    const NetworkSettingsPage(),
                    ref,
                  ),
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 22)),
          SliverToBoxAdapter(
            child: _SectionLabel(text: '其他', color: labelColor),
          ),
          SliverToBoxAdapter(
            child: _SettingsGroup(
              isDark: isDark,
              children: [
                _SettingsTile(
                  icon: Icons.emoji_emotions_outlined,
                  iconGradient: const [Color(0xFFFFCC00), Color(0xFFFF9F0A)],
                  title: l10n.stickersEmoji,
                  description: '收藏表情包与订阅贴纸',
                  isDark: isDark,
                  onTap: () => _openPage(
                    context,
                    const StickersPage(),
                    ref,
                    desktopPanelType: DesktopPanelType.settingsStickers,
                  ),
                ),
                _SettingsTile(
                  icon: Icons.help_outline_rounded,
                  iconGradient: const [Color(0xFF0A84FF), Color(0xFF5AC8FA)],
                  title: l10n.faq,
                  description: '常见问题与官方解答',
                  isDark: isDark,
                  onTap: () => _openPage(
                    context,
                    const FAQPage(),
                    ref,
                    desktopPanelType: DesktopPanelType.settingsFaq,
                  ),
                ),
                _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  iconGradient: const [Color(0xFF98A2B3), Color(0xFF667085)],
                  title: l10n.about,
                  description: '版本信息、服务协议与产品简介',
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
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
          SliverToBoxAdapter(
            child: Consumer(
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
                    return _VersionFooter(
                      text: '$appName · v$displayVersion',
                      isDark: isDark,
                    );
                  },
                  loading: () => _VersionFooter(text: appName, isDark: isDark),
                  error: (_, __) =>
                      _VersionFooter(text: appName, isDark: isDark),
                );
              },
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: floatingBottomSpace)),
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

  // 保留原代码其他辅助函数...
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
                        configuredName.isNotEmpty ? configuredName : '锦绣汇';
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
                        '锦绣汇',
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

/// 顶部圆形小按钮（扫码、个性化等）
class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  const _CircleIconButton({
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = isDark ? Colors.white.withOpacity(0.06) : Colors.white;
    final Color border = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.05);
    final Color fg = isDark ? Colors.white : const Color(0xFF0F172A);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: border, width: 1),
            boxShadow: isDark
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Icon(icon, size: 20, color: fg),
        ),
      ),
    );
  }
}

/// 大型渐变头卡：头像 + 昵称 + 手机 + 状态 chip + 编辑按钮
class _HeroProfileCard extends ConsumerStatefulWidget {
  final bool isDark;
  final bool isDesktopSidebar;
  const _HeroProfileCard({
    required this.isDark,
    this.isDesktopSidebar = false,
  });

  @override
  ConsumerState<_HeroProfileCard> createState() => _HeroProfileCardState();
}

class _HeroProfileCardState extends ConsumerState<_HeroProfileCard> {
  static const List<Color> _nameColors = [
    Color(0xFF3390EC),
    Color(0xFF4FAE4E),
    Color(0xFFF5A623),
    Color(0xFFE05656),
    Color(0xFF9B7CE0),
    Color(0xFF50B6C5),
    Color(0xFFFF7EB3),
    Color(0xFF7D8B99),
  ];

  Color? _getNameColor(String? nicknameColor) {
    if (nicknameColor == null || nicknameColor.isEmpty) return null;
    for (final part in nicknameColor.split(',')) {
      if (part.startsWith('name:')) {
        final index = int.tryParse(part.substring(5)) ?? 0;
        return _nameColors[index.clamp(0, _nameColors.length - 1)];
      }
    }
    return null;
  }

  String _formatPhone(String? phone) =>
      (phone == null || phone.isEmpty) ? '未绑定手机' : phone;

  void _openProfile() {
    HapticFeedback.selectionClick();
    if (widget.isDesktopSidebar) {
      ref.read(desktopProfileProvider.notifier).state =
          const DesktopProfileInfo(
        type: DesktopPanelType.settingsProfile,
        id: 'profile',
      );
    } else {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => ProfilePage()),
      );
    }
  }

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
    return Text(emoji, style: TextStyle(fontSize: size * 0.85));
  }

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
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                            final response = await ref
                                .read(apiClientProvider)
                                .put('/user/me', data: {'emoji_avatar': ''});
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
                Expanded(
                  child: TGEmojiPicker(
                    height: double.infinity,
                    onEmojiSelected: (emoji, {bool isAnimated = false}) async {
                      if (emoji == 'BACKSPACE') return;
                      Navigator.pop(ctx);
                      final response = await ref.read(apiClientProvider).put(
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

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authServiceProvider);
    final user = authState.user;
    final isDark = widget.isDark;

    final displayName = user?.nickname.isNotEmpty == true
        ? user!.nickname
        : (user?.username ?? '未登录');
    final phoneDisplay = _formatPhone(user?.phone);
    final avatar = user?.avatar;
    final nameColorOverride = _getNameColor(user?.nicknameColor);
    final emojiStatus = user?.emojiAvatar;

    return GestureDetector(
      onTap: _openProfile,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 16, 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6366F1),
              Color(0xFF8B5CF6),
              Color(0xFFA855F7),
            ],
            stops: [0.0, 0.55, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withOpacity(isDark ? 0.35 : 0.28),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              right: 40,
              bottom: -50,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.5),
                          width: 2,
                        ),
                      ),
                      child: AvatarWidget(
                        name: displayName,
                        avatar: avatar,
                        size: 60,
                      ),
                    ),
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: GestureDetector(
                        onTap: _showEmojiStatusPicker,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.15),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: emojiStatus != null && emojiStatus.isNotEmpty
                              ? _buildEmojiStatus(emojiStatus, size: 20)
                              : const Icon(
                                  Icons.add_reaction_outlined,
                                  size: 14,
                                  color: Color(0xFF6366F1),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: nameColorOverride ?? Colors.white,
                                letterSpacing: 0.2,
                                shadows: nameColorOverride == null
                                    ? [
                                        Shadow(
                                          color: Colors.black.withOpacity(0.15),
                                          blurRadius: 6,
                                          offset: const Offset(0, 1),
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.22),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.verified_rounded,
                                    color: Colors.white, size: 12),
                                SizedBox(width: 3),
                                Text(
                                  'PRO',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.phone_iphone_rounded,
                            size: 13,
                            color: Colors.white.withOpacity(0.85),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              phoneDisplay,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white.withOpacity(0.9),
                                letterSpacing: 0.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _StatusChip(
                            icon: Icons.circle,
                            iconColor: const Color(0xFF34D399),
                            text: '在线',
                          ),
                          const SizedBox(width: 6),
                          _StatusChip(
                            icon: Icons.qr_code_rounded,
                            iconColor: Colors.white,
                            text: '个人二维码',
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(context, rootNavigator: true)
                                  .pushNamed('/scan');
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _CircleIconButton(
                  icon: Icons.chevron_right_rounded,
                  isDark: false,
                  onTap: _openProfile,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 头卡内的半透明状态胶囊
class _StatusChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final VoidCallback? onTap;

  const _StatusChip({
    required this.icon,
    required this.iconColor,
    required this.text,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.22), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: iconColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11.5,
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: chip,
    );
  }
}

/// 4 宫格快捷入口：会员 / 钱包 / 我的动态 / 扫一扫
class _QuickActionsRow extends ConsumerWidget {
  final bool isDark;
  const _QuickActionsRow({required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = <_QuickActionItem>[
      _QuickActionItem(
        icon: Icons.workspace_premium_outlined,
        label: '会员中心',
        gradient: const [Color(0xFFFFB454), Color(0xFFF97316)],
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (_) => MembershipPage()),
          );
        },
      ),
      _QuickActionItem(
        icon: Icons.account_balance_wallet_outlined,
        label: '钱包',
        gradient: const [Color(0xFF10B981), Color(0xFF059669)],
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (_) => WalletPage()),
          );
        },
      ),
      _QuickActionItem(
        icon: Icons.dynamic_feed_outlined,
        label: '我的动态',
        gradient: const [Color(0xFF3B82F6), Color(0xFF6366F1)],
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(builder: (_) => MyMomentsPage()),
          );
        },
      ),
      _QuickActionItem(
        icon: Icons.qr_code_scanner_rounded,
        label: '扫一扫',
        gradient: const [Color(0xFFEC4899), Color(0xFFDB2777)],
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.of(context, rootNavigator: true).pushNamed('/scan');
        },
      ),
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF12141C) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.04),
          width: 1,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Row(
        children: items
            .map((item) => Expanded(
                  child: _QuickActionCell(item: item, isDark: isDark),
                ))
            .toList(),
      ),
    );
  }
}

class _QuickActionItem {
  final IconData icon;
  final String label;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _QuickActionItem({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });
}

class _QuickActionCell extends StatelessWidget {
  final _QuickActionItem item;
  final bool isDark;
  const _QuickActionCell({required this.item, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: item.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: item.gradient,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: item.gradient.last.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(item.icon, color: Colors.white, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 分组小标题
class _SectionLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _SectionLabel({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 4, 16, 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

/// 版本号页脚
class _VersionFooter extends StatelessWidget {
  final String text;
  final bool isDark;
  const _VersionFooter({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.03),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white38 : Colors.black45,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

/// 设置分组卡片
class _SettingsGroup extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;

  const _SettingsGroup({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    final visibleChildren = children.where((c) {
      if (c is SizedBox) {
        final w = c.width ?? 1;
        final h = c.height ?? 1;
        return !(w == 0 && h == 0);
      }
      return true;
    }).toList();

    if (visibleChildren.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF12141C) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.05)
              : Colors.black.withOpacity(0.04),
          width: 1,
        ),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.03),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          children: List.generate(
            visibleChildren.length * 2 - 1,
            (index) {
              if (index.isOdd) {
                return Padding(
                  padding: const EdgeInsets.only(left: 68, right: 16),
                  child: Divider(
                    height: 1,
                    thickness: 0.7,
                    color: isDark
                        ? Colors.white.withOpacity(0.06)
                        : const Color(0xFFEEF0F4),
                  ),
                );
              }
              return visibleChildren[index ~/ 2];
            },
          ),
        ),
      ),
    );
  }
}

/// 设置项：渐变胶囊图标 + 上下双行文字 + 右箭头
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final List<Color> iconGradient;
  final String title;
  final String description;
  final bool isDark;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconGradient,
    required this.title,
    required this.description,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: iconGradient,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: iconGradient.last.withOpacity(0.28),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            isDark ? Colors.white38 : const Color(0xFF94A3B8),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
              ),
            ],
          ),
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
