import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../chat/providers/chat_provider.dart';
import '../../contacts/providers/contact_provider.dart';
import '../../contacts/providers/friend_request_provider.dart';

import '../../../core/utils/platform_utils.dart';
import 'home_desktop_page.dart';

/// 主色（海洋蓝，与全局 AppColors.primary 保持一致）
const Color _kNavPrimary = Color(0xFFC9A84C);

/// 未选中图标/文字颜色
const Color _kNavInactive = Color(0xFF9AA0A6);

/// 底部导航条固定高度（不含 SafeArea）
const double _kNavBarHeight = 56.0;

/// 主页容器 —— 底部导航条 5 个 tab 等宽平均分布，全部使用 Material 图标
/// + 主色高亮，风格保持白底极简。
///
/// 分支索引沿用原路由结构：
///   0 = 聊天（默认打开）
///   1 = 联系人
///   2 = 客服（自定义门户）
///   3 = 发现
///   4 = 我的
class HomePage extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const HomePage({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations(ref.watch(languageProvider));

    // if (PlatformUtils.isDesktop) {
    //   return const HomeDesktopPage();
    // }

    ref.read(webSocketServiceProvider);

    // 底部导航「聊天」角标 —— 只统计"用户实际能看到的会话"的未读数，
    // 排除已从聊天列表 UI 过滤掉的 channel 类型（见 chat_page._getChatList）。
    // 否则会出现："列表里都是已读，但角标仍显示 1"的 bug。
    final unreadChatCount = ref.watch(
      chatListProvider.select((state) => state.visibleUnreadCount),
    );

    final friendRequestCount = ref.watch(friendRequestProvider);
    final isEditMode = ref.watch(chatEditModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final int currentIndex = navigationShell.currentIndex;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF11131A) : const Color(0xFFF7F8FA),
      extendBody: false,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: navigationShell,
        ),
      ),
      bottomNavigationBar: isEditMode
          ? null
          : _BottomNavBar(
              isDark: isDark,
              items: [
                _BottomNavItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  activeIcon: Icons.chat_bubble_rounded,
                  label: l10n.tabChat,
                  isSelected: currentIndex == 0,
                  badge: unreadChatCount,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    navigationShell.goBranch(0);
                  },
                ),
                _BottomNavItem(
                  icon: Icons.people_alt_outlined,
                  activeIcon: Icons.people_alt_rounded,
                  label: l10n.tabContacts,
                  isSelected: currentIndex == 1,
                  badge: friendRequestCount,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    navigationShell.goBranch(1);
                    final notifier = ref.read(contactListProvider.notifier);
                    if (notifier.shouldRefresh) {
                      notifier.refresh();
                    }
                  },
                ),
                // _BottomNavItem(
                //   icon: Icons.headset_mic_outlined,
                //   activeIcon: Icons.headset_mic_rounded,
                //   label: '客服',
                //   isSelected: currentIndex == 2,
                //   onTap: () {
                //     HapticFeedback.selectionClick();
                //     navigationShell.goBranch(2);
                //   },
                // ),
                _BottomNavItem(
                  icon: Icons.explore_outlined,
                  activeIcon: Icons.explore_rounded,
                  label: l10n.tabDiscover,
                  isSelected: currentIndex == 3,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    navigationShell.goBranch(3);
                  },
                ),
                _BottomNavItem(
                  icon: Icons.person_outline_rounded,
                  activeIcon: Icons.person_rounded,
                  label: l10n.tabMe,
                  isSelected: currentIndex == 4,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    navigationShell.goBranch(4);
                  },
                ),
              ],
            ),
    );
  }
}

/// 底部导航条容器（白底、细顶部分隔线、SafeArea 撑到底）
///
/// 5 个 tab 等宽平均分布：消息 / 联系人 / 客服 / 发现 / 我的
class _BottomNavBar extends StatelessWidget {
  final bool isDark;
  final List<_BottomNavItem> items;

  const _BottomNavBar({
    required this.isDark,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final Color dividerColor =
        isDark ? Colors.white.withOpacity(0.06) : const Color(0xFFECEEF1);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14161E) : Colors.white,
        border: Border(
          top: BorderSide(color: dividerColor, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _kNavBarHeight,
          child: Row(
            children: items
                .map((item) => Expanded(child: item))
                .toList(growable: false),
          ),
        ),
      ),
    );
  }
}

/// 单个 tab 按钮（Material 图标 + 主色高亮）
class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool isSelected;
  final int? badge;
  final VoidCallback onTap;

  const _BottomNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.isSelected,
    this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = isSelected ? _kNavPrimary : _kNavInactive;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        highlightColor: Colors.transparent,
        splashColor: _kNavPrimary.withOpacity(0.08),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 140),
                    child: Icon(
                      isSelected ? activeIcon : icon,
                      key: ValueKey<bool>(isSelected),
                      size: 26,
                      color: color,
                    ),
                  ),
                  if (badge != null && badge! > 0)
                    Positioned(
                      right: -8,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.error,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white,
                            width: 1.5,
                          ),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 17,
                          minHeight: 17,
                        ),
                        child: Center(
                          child: Text(
                            badge! > 99 ? '99+' : badge.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              height: 1.0,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: color,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
