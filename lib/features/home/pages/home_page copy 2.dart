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

class HomePage extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const HomePage({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 🌟 【H5 移动端适配改造】
    // 无论是大屏 PC 还是手机，统一走移动端单页底座布局
    // 在电脑浏览器或宽屏打开时，限制最大 450 像素并居中，高仿真 H5 客户端效果
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
            child: _buildMobileLayout(context, ref),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final settings = ref.watch(systemSettingsProvider).valueOrNull;

    final portalLabel = settings?.portalTitle.isNotEmpty == true
        ? settings!.portalTitle
        : l10n.tabPortal;

    // 确保连接 WebSocket
    ref.read(webSocketServiceProvider);

    // 订阅未读聊天总数
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

    // 监听聊天编辑模式
    final isEditMode = ref.watch(chatEditModeProvider);
    
    // 固定的基础容器最大宽度
    const double navBarMaxWidth = 418.0;
    
    // 自适应安全底部，若在纯 Web 浏览器里 offset 为 0 则强制垫起 14 像素以保持精致
    final double rawBottomOffset = FloatingNavLayout.bottomOffset(context);
    final double navBarBottomOffset = rawBottomOffset > 0 ? rawBottomOffset : 14.0;

    final navBarColor = isDark ? const Color(0xCC11131A) : const Color(0xEAFDFDFD);
    final navBarBorderColor = isDark ? Colors.white.withOpacity(0.08) : Colors.white.withOpacity(0.72);

    // 🌟 外层剥离掉了统一的背景色与大框，改为各自完全独立的浮动 Row 结构
    final floatingNavBar = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: navBarMaxWidth),
        child: SizedBox(
          height: FloatingNavLayout.barHeight,
          child: Row(
            children: [
              // 🛠️ 【左侧 25%：完全独立的客服 UI 区域】
             SizedBox(
              width: FloatingNavLayout.barHeight, 
              height: FloatingNavLayout.barHeight, 
              child: _buildIsolatedCustomerSupport(context, portalLabel, navBarColor, navBarBorderColor, isDark),
            ),

              // 间距：两块胶囊之间的美化空气缝隙
              const SizedBox(width: 8),

              // 🛠️ 【右侧 75%：完全独立的 4 项常规导航大胶囊】
              Expanded(
                flex: 75,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      height: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      decoration: BoxDecoration(
                        color: navBarColor,
                        borderRadius: BorderRadius.circular(28),
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

  // 🌟 构建左侧纯独立的客服 UI 胶囊：上下垂直结构，配有大图标和独立背景
  Widget _buildIsolatedCustomerSupport(
    BuildContext context, 
    String label, 
    Color navBarColor, 
    Color navBarBorderColor,
    bool isDark,
  ) {
    final isSelected = navigationShell.currentIndex == 2;
    final activeColor = AppColors.primary;
    final inactiveColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

    final itemBackground = isSelected ? activeColor.withOpacity(isDark ? 0.11 : 0.08) : Colors.transparent;
    final iconBackground = isSelected ? activeColor.withOpacity(isDark ? 0.16 : 0.11) : Colors.transparent;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          height: double.infinity,
          decoration: BoxDecoration(
            color: navBarColor,
            borderRadius: BorderRadius.circular(24),
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
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              splashFactory: InkRipple.splashFactory,
              highlightColor: Colors.transparent,
              splashColor: activeColor.withOpacity(0.08),
              onTap: () {
                GlobalHaptics.selection();
                navigationShell.goBranch(2);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: itemBackground,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: iconBackground,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(
                        Icons.support_agent_rounded, // 🌟 统一为专属客服图标
                        size: 34, // 大图标高度尺寸
                        color: isSelected ? activeColor : inactiveColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10.0, // 大字体尺寸
                        height: 1.1,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
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
}

class _NavItem extends StatelessWidget {
  final String? iconPath; 
  final String? activeIconPath; 
  final String? imageUrl; 
  final IconData? iconData; 
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
    final inactiveColor = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    final itemBackground = isSelected ? activeColor.withOpacity(isDark ? 0.11 : 0.08) : Colors.transparent;
    final iconBackground = isSelected ? activeColor.withOpacity(isDark ? 0.16 : 0.11) : Colors.transparent;

    return Expanded(
      child: Center(
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
              padding: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                color: itemBackground,
                borderRadius: BorderRadius.circular(20),
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
                        // 🌟 右侧按需求放大复原：圆球直径从 21 恢复并升级到 26px
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: iconBackground,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: _buildIcon(
                          activeColor: activeColor,
                          inactiveColor: inactiveColor,
                        ),
                      ),
                      if (badge != null && badge! > 0)
                        Positioned(
                          right: -5,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                            decoration: BoxDecoration(
                              color: AppColors.error,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            constraints: const BoxConstraints(minWidth: 14),
                            child: Text(
                              badge! > 99 ? '99+' : badge.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w700,
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
                      // 🌟 右侧按需求放大复原：字号从 8.5px 放大至 10.0px，体验更细腻清晰
                      fontSize: 10.0,
                      height: 1.1,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? activeColor : inactiveColor,
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

  Widget _buildIcon({
    required Color activeColor,
    required Color inactiveColor,
  }) {
    final iconColor = isSelected ? activeColor : inactiveColor;
    // 🌟 右侧按需求放大：内部图标主体展示 Size 从 15.0px 大幅提振至 18.0px
    const double targetIconSize = 18.0;

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return Opacity(
        opacity: isSelected ? 1 : 0.78,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Image.network(
            imageUrl!,
            width: targetIconSize,
            height: targetIconSize,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Icon(
              isSelected ? (activeIconData ?? iconData) : iconData,
              size: targetIconSize,
              color: iconColor,
            ),
          ),
        ),
      );
    }

    if (iconData != null) {
      return Icon(
        isSelected ? (activeIconData ?? iconData) : iconData,
        size: targetIconSize,
        color: iconColor,
      );
    }

    return Image.asset(
      isSelected ? activeIconPath! : iconPath!,
      width: targetIconSize,
      height: targetIconSize,
      color: iconColor,
    );
  }
}