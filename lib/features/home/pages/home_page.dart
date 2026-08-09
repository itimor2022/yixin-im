// 文件用途：实现 HomePage 页面及其交互流程，属于应用首页。
// 核心逻辑：维护 HomePage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
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

// 关键声明：home page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class HomePage extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const HomePage({super.key, required this.navigationShell});

  // 流程逻辑：`build` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 桌面端使用独立的分栏布局
    if (PlatformUtils.useDesktopLayout(context)) {
      return const HomeDesktopPage();
    }

    return _buildMobileLayout(context, ref);
  }

  Widget _buildMobileLayout(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final settings = ref.watch(systemSettingsProvider).valueOrNull;
    final hasCustomPortal = settings?.hasCustomPortal == true &&
        (!PlatformUtils.isIOS || settings!.iosCompliance.allowsCustomPortal);

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
    // Preload the chat list from local cache even when the user lands on a
    // different tab. initialize() is idempotent and refreshes from server after
    // the cached list is rendered.
    final chatPreloadState = ref.read(chatListProvider);
    if (!chatPreloadState.isInitialized &&
        !chatPreloadState.isLoading &&
        !chatPreloadState.isSilentLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(chatListProvider.notifier).initialize();
      });
    }

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
    final pendingFriendRequestCount =
        ref.watch(pendingFriendRequestCountProvider);
    final messageMenuBadge = unreadChatCount + pendingFriendRequestCount;

    // 监听聊天编辑模式
    final isEditMode = ref.watch(chatEditModeProvider);
    final isFloatingNavHidden = ref.watch(floatingNavHiddenProvider);
    final currentPath = GoRouterState.of(context).uri.path;
    final isRootTabRoute = _isRootTabRoute(
      currentPath,
      hasCustomPortal: hasCustomPortal,
    );
    final navItemCount = hasCustomPortal ? 5 : 4;
    final navBarMaxWidth = navItemCount == 5 ? 468.0 : 420.0;
    final navBarHorizontalInset = navItemCount == 5 ? 18.0 : 22.0;
    final showFloatingNav = FloatingNavLayout.isEnabledForContext(context);
    final isPortalActive = hasCustomPortal && navigationShell.currentIndex == 2;
    final navBarBottomOffset = FloatingNavLayout.bottomOffset(context);
    final navBlurSigma = PlatformUtils.isAndroid ? 18.0 : 30.0;
    final navBarColor =
        isDark ? AppColors.darkSurface.withOpacity(0.88) : Colors.white;
    final navBarBorderColor = isDark
        ? Colors.white.withOpacity(0.18)
        : Colors.white.withOpacity(0.38);
    final floatingNavBar = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: navBarMaxWidth),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: BackdropFilter(
            filter:
                ImageFilter.blur(sigmaX: navBlurSigma, sigmaY: navBlurSigma),
            child: Container(
              height: FloatingNavLayout.barHeight,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: navBarColor,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [
                          AppColors.darkControlBackgroundStrong
                              .withOpacity(0.92),
                          AppColors.darkSurface.withOpacity(0.88),
                        ]
                      : [
                          Colors.white,
                          Colors.white,
                        ],
                ),
                borderRadius: BorderRadius.circular(34),
                border: Border.all(color: navBarBorderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.34 : 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(isDark ? 0.04 : 0.18),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _NavItem(
                    iconPath: 'assets/icons/tab_chat.png',
                    activeIconPath: 'assets/icons/tab_chat_active.png',
                    label: l10n.get('message'),
                    isSelected: navigationShell.currentIndex == 0,
                    badge: messageMenuBadge,
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
                    iconPath: 'assets/icons/tab_moments.png',
                    activeIconPath: 'assets/icons/tab_moments_active.png',
                    label: l10n.get('tab_discover'),
                    isSelected: navigationShell.currentIndex == 3,
                    onTap: () {
                      GlobalHaptics.selection();
                      navigationShell.goBranch(3);
                    },
                  ),
                  _NavItem(
                    iconPath: 'assets/icons/tab_settings.png',
                    activeIconPath: 'assets/icons/tab_settings_active.png',
                    label: l10n.get('settings'),
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
          if (showFloatingNav &&
              isRootTabRoute &&
              !isPortalActive &&
              !isEditMode &&
              !isFloatingNavHidden)
            Positioned(
              left: navBarHorizontalInset,
              right: navBarHorizontalInset,
              bottom: navBarBottomOffset,
              child: RepaintBoundary(child: floatingNavBar),
            ),
        ],
      ),
      // 编辑模式下隐藏底部导航栏
    );
  }

  bool _isRootTabRoute(String path, {required bool hasCustomPortal}) {
    final normalized = path == '/' ? '/home' : path;
    return normalized == '/home' ||
        normalized == '/contacts' ||
        normalized == '/discover' ||
        normalized == '/settings' ||
        (hasCustomPortal && normalized == '/portal');
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
    final activeColor = AppColors.primaryFor(context);
    final inactiveColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF1F2329);
    final itemBackground = isSelected
        ? (isDark
            ? activeColor.withOpacity(0.20)
            : activeColor.withOpacity(0.06))
        : Colors.transparent;
    final itemShadow = isSelected && !isDark
        ? [
            BoxShadow(
              color: Colors.black.withOpacity(0.035),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ]
        : null;

    return Expanded(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 112),
          child: _PressScaleInk(
            borderRadius: BorderRadius.circular(28),
            splashColor: activeColor.withOpacity(0.08),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: isSelected ? 86 : 72,
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: itemBackground,
                borderRadius: BorderRadius.circular(25),
                boxShadow: itemShadow,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        width: 25,
                        height: 25,
                        alignment: Alignment.center,
                        child: _buildIcon(
                          activeColor: activeColor,
                          inactiveColor: inactiveColor,
                        ),
                      ),
                      if (badge != null && badge! > 0)
                        Positioned(
                          right: -16,
                          top: -7,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5.5,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF453A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isDark
                                    ? AppColors.darkSurface
                                    : Colors.white.withOpacity(0.95),
                                width: 1.2,
                              ),
                            ),
                            constraints: const BoxConstraints(minWidth: 18),
                            child: Text(
                              badge! > 99 ? '99+' : badge.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                height: 1.0,
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
                      fontSize: 11.5,
                      height: 1.0,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
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

class _PressScaleInk extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final Color splashColor;
  final VoidCallback onTap;

  const _PressScaleInk({
    required this.child,
    required this.borderRadius,
    required this.splashColor,
    required this.onTap,
  });

  @override
  State<_PressScaleInk> createState() => _PressScaleInkState();
}

class _PressScaleInkState extends State<_PressScaleInk> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (_isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: widget.borderRadius,
        splashFactory: InkRipple.splashFactory,
        highlightColor: Colors.transparent,
        splashColor: widget.splashColor,
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: AnimatedScale(
          scale: _isPressed ? 0.96 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}
