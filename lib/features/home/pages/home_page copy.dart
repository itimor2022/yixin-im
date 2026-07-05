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
import 'home_desktop_page.dart';

class HomePage extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const HomePage({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 桌面端使用独立的分栏布局
    if (PlatformUtils.isDesktop) {
      return const HomeDesktopPage();
    }

    return _buildMobileLayout(context, ref);
  }

  Widget _buildMobileLayout(BuildContext context, WidgetRef ref) {
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

    // 使用 select 只订阅需要的状态，减少不必要的重建
    // WebSocket: 只在首次确保连接，不需要监听状态变化
    ref.read(webSocketServiceProvider);

    // 使用 select 只订阅未读数，而不是整个 chatState
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

    // 监听聊天编辑模式
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
                  _NavItem(
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
                  _NavItem(
                    iconPath: 'assets/icons/tab_contacts.png',
                    activeIconPath: 'assets/icons/tab_contacts_active.png',
                    label: l10n.tabContacts,
                    isSelected: navigationShell.currentIndex == 1,
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
                    _NavItem(
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
                  _NavItem(
                    label: l10n.get('tab_discover'),
                    isSelected: navigationShell.currentIndex == 3,
                    iconData: Icons.explore_outlined,
                    activeIconData: Icons.explore,
                    onTap: () {
                      GlobalHaptics.selection();
                      navigationShell.goBranch(3);
                    },
                  ),
                  _NavItem(
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
      // 编辑模式下隐藏底部导航栏
    );
  }
}

class _NavItem extends StatelessWidget {
  final String? iconPath; // 未选中图标路径
  final String? activeIconPath; // 选中图标路径
  final String? imageUrl; // 远程图标
  final IconData? iconData; // 可选：使用 Material 图标
  final IconData? activeIconData;
  final String label;
  final bool isSelected;
  final int? badge;
  final VoidCallback onTap;

  const _NavItem({
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
