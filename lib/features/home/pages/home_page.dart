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
    
    // 基础容器最大宽度
    const double navBarMaxWidth = 440.0;
    
    final double rawBottomOffset = FloatingNavLayout.bottomOffset(context);
    final double navBarBottomOffset = rawBottomOffset > 0 ? rawBottomOffset : 14.0;

    // 右侧大区域整体统一背景色
    const rightNavBarColor = Color(0xFF3A43B0);

    final floatingNavBar = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: navBarMaxWidth),
        child: SizedBox(
          height: FloatingNavLayout.barHeight + 12, // 确保高度包裹放大后的图标与字体
          child: Row(
            children: [
              // 🛠️ 【左侧：完全独立的客服】无任何边框背景，高度与右侧拉满一致
              SizedBox(
                width: FloatingNavLayout.barHeight + 24, 
                height: double.infinity, 
                child: _buildIsolatedCustomerSupport(context),
              ),

              const SizedBox(width: 6),

              // 🛠️ 【右侧：4 项常规导航大胶囊】
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(36), // 🌟 整体外层弧度加大到 36
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      height: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                      decoration: BoxDecoration(
                        color: rightNavBarColor,
                        borderRadius: BorderRadius.circular(36), // 🌟 整体外层弧度加大到 36
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

  // 🌟 客服模块：剥离所有滤镜、背景、阴影和边框，高度拉满
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
            height: double.infinity, // 🌟 放大图片，高度和右侧完全一样
            child: Image.asset(
              isSelected 
                  ? 'assets/icons/customer_service_active2.png' 
                  : 'assets/icons/customer_service2.png',
              fit: BoxFit.contain, // 确保在全高下等比例缩放
            ),
          ),
        ),
      ),
    );
  }
}

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

    // 图标依旧保持放大一倍后的 36px 尺寸
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
                borderRadius: BorderRadius.circular(24), // 🌟 选中后的容器边角也采用圆形/大圆角
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
                              borderRadius: BorderRadius.circular(10), // 保持正圆角
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 18, // 🌟 调大宽度，给数字留有足够空间
                              minHeight: 18,
                            ),
                            child: Center(
                              child: Text(
                                badge! > 99 ? '99+' : badge.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11.0, // 🌟 气泡数字放大
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
                      fontSize: isSelected ? 12.0 : 10.0, // 🌟 选中的字体再放大一点 (从 10 放大到 12)
                      height: 1.1,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      // 🌟 选中时的文字颜色对应修改为 3843b7
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