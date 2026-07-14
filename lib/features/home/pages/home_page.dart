import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/utils/floating_nav_layout.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../chat/providers/chat_provider.dart';
import '../../contacts/providers/contact_provider.dart';
import '../../contacts/providers/friend_request_provider.dart';
import 'home_desktop_page.dart';

// =====================================================================
// 🎨 底部导航样式切换开关
// ---------------------------------------------------------------------
// true  → 使用【原版】yixin-im-4.1 2 的玻璃胶囊导航
//         · 客服/portal 与其它 tab 融合在同一条胶囊里
//         · 亮/暗色自适应半透明磨砂
//         · 桌面端走独立的 HomeDesktopPage 分栏布局
//
// false → 使用【二开版】yixin-im-4.1 的深蓝胶囊导航
//         · 左侧独立放大客服图标 (customer_service2.png)
//         · 右侧深蓝色 (#3A43B0) 胶囊 + 4 个 tab
//         · 外壳固定 450px 宽居中，模拟 H5 手机端
//
// 想切回二开样式，直接改成 false 即可，其它任何地方都不用动。
// =====================================================================
const bool _kUseOriginalNavStyle = true;

class HomePage extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const HomePage({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_kUseOriginalNavStyle) {
      // 原版：桌面端使用独立的分栏布局
      if (PlatformUtils.isDesktop) {
        return const HomeDesktopPage();
      }
      return _buildOriginalMobileLayout(context, ref);
    }
    return _buildCustomHomeShell(context, ref);
  }

  // =====================================================================
  // 【原版】yixin-im-4.1 2 玻璃胶囊导航
  // =====================================================================
  Widget _buildOriginalMobileLayout(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final settings = ref.watch(systemSettingsProvider).valueOrNull;
    final hasCustomPortal = settings?.hasCustomPortal == true;

    if (settings != null &&
        !hasCustomPortal &&
        navigationShell.currentIndex == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          navigationShell.goBranch(3);
        }
      });
    }

    final portalLabel = settings?.portalTitle.isNotEmpty == true
        ? settings!.portalTitle
        : l10n.tabPortal;

    ref.read(webSocketServiceProvider);

    final unreadChatCount = ref.watch(
      chatListProvider.select((state) {
        return state.pinnedChats
                .where((c) => c.unreadCount > 0)
                .fold<int>(0, (sum, c) => sum + c.unreadCount) +
            state.regularChats
                .where((c) => c.unreadCount > 0)
                .fold<int>(0, (sum, c) => sum + c.unreadCount);
      }),
    );

    final friendRequestCount = ref.watch(friendRequestProvider);
    final isEditMode = ref.watch(chatEditModeProvider);
    final navItemCount = hasCustomPortal ? 5 : 4;
    final navBarMaxWidth = navItemCount == 5 ? 520.0 : 440.0;
    final navBarBottomOffset = FloatingNavLayout.bottomOffset(context);
    final navBarColor =
        isDark ? const Color(0xCC11131A) : const Color(0xEAFDFDFD);
    final navBarBorderColor = isDark
        ? Colors.white.withOpacity(0.08)
        : Colors.white.withOpacity(0.72);

    final floatingNavBar = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: navBarMaxWidth),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: FloatingNavLayout.barHeight,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: navBarColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: navBarBorderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.26 : 0.10),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _OriginalNavItem(
                    iconPath: 'assets/icons/tab_chat.png',
                    activeIconPath: 'assets/icons/tab_chat_active.png',
                    label: l10n.tabChat,
                    isSelected: navigationShell.currentIndex == 0,
                    badge: unreadChatCount,
                    onTap: () {
                      GlobalHaptics.selection();
                      navigationShell.goBranch(0);
                    },
                  ),
                  _OriginalNavItem(
                    iconPath: 'assets/icons/tab_contacts.png',
                    activeIconPath: 'assets/icons/tab_contacts_active.png',
                    label: l10n.tabContacts,
                    isSelected: navigationShell.currentIndex == 1,
                    badge: friendRequestCount,
                    onTap: () {
                      GlobalHaptics.selection();
                      navigationShell.goBranch(1);
                      final notifier = ref.read(contactListProvider.notifier);
                      if (notifier.shouldRefresh) {
                        notifier.refresh();
                      }
                    },
                  ),
                  if (hasCustomPortal)
                    _OriginalNavItem(
                      label: portalLabel,
                      isSelected: navigationShell.currentIndex == 2,
                      imageUrl: settings?.portalIconUrl,
                      iconData: Icons.language_outlined,
                      activeIconData: Icons.language,
                      onTap: () {
                        GlobalHaptics.selection();
                        navigationShell.goBranch(2);
                      },
                    ),
                  _OriginalNavItem(
                    label: l10n.get('tab_discover'),
                    isSelected: navigationShell.currentIndex == 3,
                    iconData: Icons.explore_outlined,
                    activeIconData: Icons.explore,
                    onTap: () {
                      GlobalHaptics.selection();
                      navigationShell.goBranch(3);
                    },
                  ),
                  _OriginalNavItem(
                    iconPath: 'assets/icons/tab_settings.png',
                    activeIconPath: 'assets/icons/tab_settings_active.png',
                    label: l10n.tabMe,
                    isSelected: navigationShell.currentIndex == 4,
                    onTap: () {
                      GlobalHaptics.selection();
                      navigationShell.goBranch(4);
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          navigationShell,
          if (!isEditMode)
            Positioned(
              left: 18,
              right: 18,
              bottom: navBarBottomOffset,
              child: floatingNavBar,
            ),
        ],
      ),
    );
  }

  // =====================================================================
  // 【二开版】yixin-im-4.1 深蓝胶囊 + 独立客服图标
  // =====================================================================
  Widget _buildCustomHomeShell(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF11131A) : const Color(0xFFF5F7FA),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: Container(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 0),
                )
              ],
            ),
            child: _buildCustomMobileLayout(context, ref),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomMobileLayout(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));

    ref.read(webSocketServiceProvider);

    final unreadChatCount = ref.watch(
      chatListProvider.select((state) {
        return state.pinnedChats
                .where((c) => c.unreadCount > 0)
                .fold<int>(0, (sum, c) => sum + c.unreadCount) +
            state.regularChats
                .where((c) => c.unreadCount > 0)
                .fold<int>(0, (sum, c) => sum + c.unreadCount);
      }),
    );

    final friendRequestCount = ref.watch(friendRequestProvider);
    final isEditMode = ref.watch(chatEditModeProvider);

    const double navBarMaxWidth = 440.0;

    final double rawBottomOffset = FloatingNavLayout.bottomOffset(context);
    final double navBarBottomOffset = rawBottomOffset > 0 ? rawBottomOffset : 14.0;

    const rightNavBarColor = Color(0xFF3A43B0);

    final floatingNavBar = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: navBarMaxWidth),
        child: SizedBox(
          height: FloatingNavLayout.barHeight + 12,
          child: Row(
            children: [
              SizedBox(
                width: FloatingNavLayout.barHeight + 24,
                height: double.infinity,
                child: _buildIsolatedCustomerSupport(context),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(36),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      height: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      decoration: BoxDecoration(
                        color: rightNavBarColor,
                        borderRadius: BorderRadius.circular(36),
                        border: Border.all(
                          color: const Color(0xFF7079FD),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(isDark ? 0.20 : 0.06),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          _NavItem(
                            iconPath: 'assets/icons/tab_chat1.png',
                            activeIconPath: 'assets/icons/tab_chat_active1.png',
                            label: l10n.tabChat,
                            isSelected: navigationShell.currentIndex == 0,
                            badge: unreadChatCount,
                            onTap: () {
                              GlobalHaptics.selection();
                              navigationShell.goBranch(0);
                            },
                          ),
                          _NavItem(
                            iconPath: 'assets/icons/tab_contacts1.png',
                            activeIconPath: 'assets/icons/tab_contacts_active1.png',
                            label: l10n.tabContacts,
                            isSelected: navigationShell.currentIndex == 1,
                            badge: friendRequestCount,
                            onTap: () {
                              GlobalHaptics.selection();
                              navigationShell.goBranch(1);
                              final notifier = ref.read(contactListProvider.notifier);
                              if (notifier.shouldRefresh) {
                                notifier.refresh();
                              }
                            },
                          ),
                          _NavItem(
                            iconPath: 'assets/icons/tab_explore1.png',
                            activeIconPath: 'assets/icons/tab_explore_active1.png',
                            label: l10n.get('tab_discover'),
                            isSelected: navigationShell.currentIndex == 3,
                            onTap: () {
                              GlobalHaptics.selection();
                              navigationShell.goBranch(3);
                            },
                          ),
                          _NavItem(
                            iconPath: 'assets/icons/tab_settings1.png',
                            activeIconPath: 'assets/icons/tab_settings_active1.png',
                            label: l10n.tabMe,
                            isSelected: navigationShell.currentIndex == 4,
                            onTap: () {
                              GlobalHaptics.selection();
                              navigationShell.goBranch(4);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          navigationShell,
          if (!isEditMode)
            Positioned(
              left: 12,
              right: 12,
              bottom: navBarBottomOffset,
              child: floatingNavBar,
            ),
        ],
      ),
    );
  }

  Widget _buildIsolatedCustomerSupport(BuildContext context) {
    final isSelected = navigationShell.currentIndex == 2;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        splashFactory: InkRipple.splashFactory,
        highlightColor: Colors.transparent,
        splashColor: Colors.white.withOpacity(0.1),
        onTap: () {
          GlobalHaptics.selection();
          navigationShell.goBranch(2);
        },
        child: Center(
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Image.asset(
              isSelected
                  ? 'assets/icons/customer_service_active2.png'
                  : 'assets/icons/customer_service2.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================================
// 【原版】NavItem — 支持 assets / 远程 imageUrl / Material 图标三种源
// =====================================================================
class _OriginalNavItem extends StatelessWidget {
  final String? iconPath;
  final String? activeIconPath;
  final String? imageUrl;
  final IconData? iconData;
  final IconData? activeIconData;
  final String label;
  final bool isSelected;
  final int? badge;
  final VoidCallback onTap;

  const _OriginalNavItem({
    this.iconPath,
    this.activeIconPath,
    this.imageUrl,
    this.iconData,
    this.activeIconData,
    required this.label,
    required this.isSelected,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = AppColors.primary;
    final inactiveColor =
        isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final itemBackground = isSelected
        ? activeColor.withOpacity(isDark ? 0.11 : 0.08)
        : Colors.transparent;
    final iconBackground = isSelected
        ? activeColor.withOpacity(isDark ? 0.16 : 0.11)
        : Colors.transparent;

    return Expanded(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 88),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              splashFactory: InkRipple.splashFactory,
              highlightColor: Colors.transparent,
              splashColor: activeColor.withOpacity(0.08),
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: itemBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          width: 30,
                          height: 30,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: iconBackground,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: _buildIcon(
                            activeColor: activeColor,
                            inactiveColor: inactiveColor,
                          ),
                        ),
                        if (badge != null && badge! > 0)
                          Positioned(
                            right: -7,
                            top: -3,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4.5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              constraints: const BoxConstraints(minWidth: 16),
                              child: Text(
                                badge! > 99 ? '99+' : badge.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.1,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? activeColor : inactiveColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon({
    required Color activeColor,
    required Color inactiveColor,
  }) {
    final iconColor = isSelected ? activeColor : inactiveColor;

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Opacity(
        opacity: isSelected ? 1 : 0.78,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.network(
            imageUrl!,
            width: 20,
            height: 20,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(
              isSelected ? (activeIconData ?? iconData) : iconData,
              size: 20,
              color: iconColor,
            ),
          ),
        ),
      );
    }

    if (iconData != null) {
      return Icon(
        isSelected ? (activeIconData ?? iconData) : iconData,
        size: 20,
        color: iconColor,
      );
    }

    return Image.asset(
      isSelected ? activeIconPath! : iconPath!,
      width: 20,
      height: 20,
      color: iconColor,
    );
  }
}

// =====================================================================
// 【二开版】NavItem — 固定使用本地 assets 图标，深蓝胶囊内的白字大图标
// =====================================================================
class _NavItem extends StatelessWidget {
  final String iconPath;
  final String activeIconPath;
  final String label;
  final bool isSelected;
  final int? badge;
  final VoidCallback onTap;

  const _NavItem({
    required this.iconPath,
    required this.activeIconPath,
    required this.label,
    required this.isSelected,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const selectedBgColor = Color(0xFFE4E4E4);
    final itemBackground = isSelected ? selectedBgColor : Colors.transparent;

    const double targetIconSize = 36.0;

    return Expanded(
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            splashFactory: InkRipple.splashFactory,
            highlightColor: Colors.transparent,
            splashColor: Colors.black.withOpacity(0.05),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
              decoration: BoxDecoration(
                color: itemBackground,
                borderRadius: BorderRadius.circular(24),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        )
                      ]
                    : [],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        width: targetIconSize + 4,
                        height: targetIconSize + 4,
                        alignment: Alignment.center,
                        child: Image.asset(
                          isSelected ? activeIconPath : iconPath,
                          width: targetIconSize,
                          height: targetIconSize,
                          fit: BoxFit.contain,
                        ),
                      ),
                      if (badge != null && badge! > 0)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 18,
                            ),
                            child: Center(
                              child: Text(
                                badge! > 99 ? '99+' : badge.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.0,
                                  fontWeight: FontWeight.w800,
                                  height: 1.0,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isSelected ? 12.0 : 10.0,
                      height: 1.1,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? const Color(0xFF3843B7) : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
