import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

import 'dart:async';
import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/desktop/window_service.dart';
import '../../../core/services/desktop/hotkey_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../chat/providers/chat_provider.dart';
import '../../chat/pages/chat_page.dart';
import '../../chat/pages/chat_detail_page.dart';
import '../../chat/pages/group_profile_page.dart';
import '../../chat/pages/user_profile_page.dart';
import '../../chat/pages/search_page.dart';
import '../../contacts/pages/new_contact_page.dart';
import '../../discover/pages/discover_page.dart';
import '../../portal/pages/custom_portal_page.dart';
import '../../contacts/pages/contacts_page.dart';
import '../../moments/pages/moments_page.dart'
    show
        MomentsPage,
        MomentDetailPage,
        MomentPublishPage,
        MomentNotificationsPage,
        MomentSearchPage;
import '../../moments/providers/moment_provider.dart' show Moment;
import '../../settings/pages/profile_page.dart';
import '../../me/pages/me_page.dart';
import '../../settings/pages/notification_settings_page.dart';
import '../../settings/pages/privacy_settings_page.dart';
import '../../settings/pages/data_storage_page.dart';
import '../../settings/pages/chat_settings_page.dart';
import '../../settings/pages/devices_page.dart';
import 'desktop_about_panel.dart';
import '../../settings/pages/stickers_page.dart';
import '../../settings/pages/faq_page.dart';
import '../../chat/pages/group_edit_page.dart';

/// 桌面端选中的聊天信息
class SelectedChatInfo {
  final String id;
  final String name;
  final String? avatar;
  final ChatType chatType;

  const SelectedChatInfo({
    required this.id,
    required this.name,
    this.avatar,
    required this.chatType,
  });
}

/// 桌面端右侧面板显示的页面类型
enum DesktopPanelType {
  none,
  user,
  group,
  channel,
  search,
  searchUsers,
  momentDetail,
  momentPublish,
  momentNotifications,
  momentSearch,
  // 设置相关
  settingsProfile,
  settingsNotification,
  settingsPrivacy,
  settingsDataStorage,
  settingsChatSettings,
  settingsDevices,
  settingsStickers,
  settingsFaq,
  settingsAbout,
  // 群组/频道编辑
  groupEdit,
  channelEdit,
}

/// 桌面端面板信息
class DesktopProfileInfo {
  final DesktopPanelType type;
  final String id;
  final String? name;
  final String? avatar;
  final String? chatId; // 用于用户资料页
  final dynamic momentData; // 用于动态详情

  const DesktopProfileInfo({
    required this.type,
    required this.id,
    this.name,
    this.avatar,
    this.chatId,
    this.momentData,
  });

  static const none = DesktopProfileInfo(type: DesktopPanelType.none, id: '');
}

// 兼容旧代码的别名
typedef DesktopProfileType = DesktopPanelType;

/// 桌面端选中的聊天 Provider（兼容旧代码）
final selectedChatIdProvider = StateProvider<String?>((ref) => null);

/// 桌面端选中的聊天完整信息 Provider
final selectedChatInfoProvider = StateProvider<SelectedChatInfo?>(
  (ref) => null,
);

/// 桌面端资料页 Provider
final desktopProfileProvider = StateProvider<DesktopProfileInfo>(
  (ref) => DesktopProfileInfo.none,
);

/// 桌面端当前导航索引
final desktopNavIndexProvider = StateProvider<int>((ref) => 0);

const int kDesktopNavChats = 0;
const int kDesktopNavContacts = 1;
const int kDesktopNavPortal = 2;
const int kDesktopNavDiscover = 3;
const int kDesktopNavMoments = 4;
const int kDesktopNavSettings = 5;

/// Telegram 风格桌面端主页
class HomeDesktopPage extends ConsumerStatefulWidget {
  const HomeDesktopPage({super.key});

  @override
  ConsumerState<HomeDesktopPage> createState() => _HomeDesktopPageState();
}

/// macOS 标题栏高度常量
const double kMacOSTitleBarHeight = 28.0;

class _HomeDesktopPageState extends ConsumerState<HomeDesktopPage> {
  double _sidebarWidth = PlatformUtils.desktopSidebarWidth;
  Timer? _sidebarSaveTimer; // 侧边栏宽度保存防抖

  @override
  void initState() {
    super.initState();
    _loadSidebarWidth();
    _setupHotkeyCallbacks();
  }

  @override
  void dispose() {
    _sidebarSaveTimer?.cancel();
    _cleanupHotkeyCallbacks();
    super.dispose();
  }

  /// 设置快捷键回调
  void _setupHotkeyCallbacks() {
    if (!PlatformUtils.isPhysicalDesktop) return;

    final hotkeyService = HotkeyService.instance;
    hotkeyService.onNewChat = _handleNewChat;
    hotkeyService.onSearch = _handleSearch;
    hotkeyService.onSettings = () => _switchNavIndex(kDesktopNavSettings);
    hotkeyService.onNextChat = _navigateToNextChat;
    hotkeyService.onPrevChat = _navigateToPrevChat;
    hotkeyService.onCloseChat = _closeCurrentChat;
  }

  /// 清理快捷键回调
  void _cleanupHotkeyCallbacks() {
    if (!PlatformUtils.isPhysicalDesktop) return;

    final hotkeyService = HotkeyService.instance;
    hotkeyService.onNewChat = null;
    hotkeyService.onSearch = null;
    hotkeyService.onSettings = null;
    hotkeyService.onNextChat = null;
    hotkeyService.onPrevChat = null;
    hotkeyService.onCloseChat = null;
  }

  /// 处理新建聊天快捷键
  void _handleNewChat() {
    // 切换到联系人页并打开搜索
    _switchNavIndex(kDesktopNavContacts);
    ref.read(desktopProfileProvider.notifier).state = const DesktopProfileInfo(
      type: DesktopPanelType.searchUsers,
      id: 'search_users',
    );
  }

  /// 处理搜索快捷键
  void _handleSearch() {
    ref.read(desktopProfileProvider.notifier).state = const DesktopProfileInfo(
      type: DesktopPanelType.search,
      id: 'search',
    );
  }

  /// 导航到下一个聊天
  void _navigateToNextChat() {
    final chatState = ref.read(chatListProvider);
    final allChats = [...chatState.pinnedChats, ...chatState.regularChats];
    if (allChats.isEmpty) return;

    final currentId = ref.read(selectedChatIdProvider);
    final currentIndex = allChats.indexWhere((c) => c.id == currentId);

    final nextIndex = currentIndex < allChats.length - 1 ? currentIndex + 1 : 0;
    final nextChat = allChats[nextIndex];

    ref.read(selectedChatIdProvider.notifier).state = nextChat.id;
    ref.read(selectedChatInfoProvider.notifier).state = SelectedChatInfo(
      id: nextChat.id,
      name: nextChat.name,
      avatar: nextChat.avatar,
      chatType: _convertChatItemType(nextChat.type),
    );
  }

  /// 导航到上一个聊天
  void _navigateToPrevChat() {
    final chatState = ref.read(chatListProvider);
    final allChats = [...chatState.pinnedChats, ...chatState.regularChats];
    if (allChats.isEmpty) return;

    final currentId = ref.read(selectedChatIdProvider);
    final currentIndex = allChats.indexWhere((c) => c.id == currentId);

    final prevIndex = currentIndex > 0 ? currentIndex - 1 : allChats.length - 1;
    final prevChat = allChats[prevIndex];

    ref.read(selectedChatIdProvider.notifier).state = prevChat.id;
    ref.read(selectedChatInfoProvider.notifier).state = SelectedChatInfo(
      id: prevChat.id,
      name: prevChat.name,
      avatar: prevChat.avatar,
      chatType: _convertChatItemType(prevChat.type),
    );
  }

  /// 将 ChatItemType 转换为 ChatType
  ChatType _convertChatItemType(ChatItemType type) {
    switch (type) {
      case ChatItemType.private:
        return ChatType.private;
      case ChatItemType.group:
        return ChatType.group;
      case ChatItemType.channel:
        return ChatType.channel;
    }
  }

  /// 关闭当前聊天
  void _closeCurrentChat() {
    ref.read(selectedChatIdProvider.notifier).state = null;
    ref.read(selectedChatInfoProvider.notifier).state = null;
    ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo.none;
  }

  Future<void> _loadSidebarWidth() async {
    final width = await WindowService.instance.getSidebarWidth();
    if (mounted) {
      setState(() => _sidebarWidth = width);
    }
  }

  /// 保存侧边栏宽度（带防抖，避免频繁写入）
  void _saveSidebarWidthDebounced() {
    _sidebarSaveTimer?.cancel();
    _sidebarSaveTimer = Timer(const Duration(milliseconds: 500), () {
      WindowService.instance.saveSidebarWidth(_sidebarWidth);
    });
  }

  /// 切换导航索引，并重置右侧面板
  void _switchNavIndex(int index) {
    final currentIndex = ref.read(desktopNavIndexProvider);
    if (currentIndex != index) {
      // 切换标签时重置右侧面板
      ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo.none;
      ref.read(selectedChatIdProvider.notifier).state = null;
    }
    ref.read(desktopNavIndexProvider.notifier).state = index;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));

    // 确保 WebSocket 连接
    ref.read(webSocketServiceProvider);

    // StateProvider 不随登出自动清空；否则新账号仍可能打开上一账号的 chatId
    ref.listen<AuthState>(
      authServiceProvider,
      (previous, next) {
        if (next.status == AuthStatus.unauthenticated) {
          ref.read(selectedChatIdProvider.notifier).state = null;
          ref.read(selectedChatInfoProvider.notifier).state = null;
          ref.read(desktopProfileProvider.notifier).state =
              DesktopProfileInfo.none;
          ref.read(desktopNavIndexProvider.notifier).state = kDesktopNavChats;
        }
      },
    );

    // 监听选中的聊天
    final selectedChatId = ref.watch(selectedChatIdProvider);
    final navIndex = ref.watch(desktopNavIndexProvider);
    final settings = ref.watch(systemSettingsProvider).valueOrNull;
    final hasCustomPortal = settings?.hasCustomPortal == true;
    final portalLabel = settings?.portalTitle.isNotEmpty == true
        ? settings!.portalTitle
        : l10n.tabPortal;

    if (settings != null && !hasCustomPortal && navIndex == kDesktopNavPortal) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(desktopNavIndexProvider) == kDesktopNavPortal) {
          _switchNavIndex(kDesktopNavDiscover);
        }
      });
    }

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      body: Row(
        children: [
          // 最左侧导航栏（垂直图标）
          _buildNavRail(
            isDark,
            navIndex,
            l10n,
            settings,
            hasCustomPortal,
            portalLabel,
          ),

          // 左侧内容区（聊天列表等）
          _buildSidebar(isDark, navIndex, hasCustomPortal),

          // 分隔条（可拖动）
          _buildDivider(isDark),

          // 右侧内容区域
          Expanded(
            child: _buildContent(isDark, selectedChatId, navIndex, l10n),
          ),
        ],
      ),
    );
  }

  /// 左侧垂直导航栏（Telegram 风格）
  Widget _buildNavRail(
    bool isDark,
    int navIndex,
    AppLocalizations l10n,
    SystemSettings? settings,
    bool hasCustomPortal,
    String portalLabel,
  ) {
    final authState = ref.watch(authServiceProvider);
    final user = authState.user;

    return Container(
      width: 68,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF0F0F0),
        border: Border(
          right: BorderSide(
            color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        children: [
          // macOS 标题栏占位
          if (PlatformUtils.isApple)
            const SizedBox(height: kMacOSTitleBarHeight),

          const SizedBox(height: 12),

          // 用户头像（点击进入设置/个人资料）
          if (user != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Tooltip(
                message: user.nickname ?? user.username,
                child: InkWell(
                  onTap: () => _switchNavIndex(kDesktopNavSettings), // 跳转到设置页
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: navIndex == kDesktopNavSettings
                            ? AppColors.primary
                            : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: AvatarWidget(
                      avatar: user.avatar,
                      name: user.nickname ?? user.username,
                      size: 36,
                    ),
                  ),
                ),
              ),
            ),

          // 导航按钮（使用自定义图标）
          _buildNavRailItem(
            iconPath: 'assets/icons/tab_chat.png',
            activeIconPath: 'assets/icons/tab_chat_active.png',
            label: l10n.tabChat,
            isSelected: navIndex == kDesktopNavChats,
            onTap: () => _switchNavIndex(kDesktopNavChats),
            isDark: isDark,
            badge: _getUnreadChatCount(),
          ),

          _buildNavRailItem(
            iconPath: 'assets/icons/tab_contacts.png',
            activeIconPath: 'assets/icons/tab_contacts_active.png',
            label: l10n.tabContacts,
            isSelected: navIndex == kDesktopNavContacts,
            onTap: () => _switchNavIndex(kDesktopNavContacts),
            isDark: isDark,
          ),

          if (hasCustomPortal)
            _buildNavRailItem(
              label: portalLabel,
              isSelected: navIndex == kDesktopNavPortal,
              onTap: () => _switchNavIndex(kDesktopNavPortal),
              isDark: isDark,
              imageUrl: settings?.portalIconUrl,
              iconData: Icons.language_outlined,
              activeIconData: Icons.language,
            ),

          _buildNavRailItem(
            label: l10n.get('tab_discover'),
            isSelected: navIndex == kDesktopNavDiscover ||
                navIndex == kDesktopNavMoments,
            onTap: () => _switchNavIndex(kDesktopNavDiscover),
            isDark: isDark,
            iconData: Icons.explore_outlined,
            activeIconData: Icons.explore,
          ),

          const Spacer(),

          // 心跳/连接状态+延迟显示
          Consumer(builder: (context, ref, _) {
            final wsState = ref.watch(webSocketServiceProvider);
            final wsService = ref.read(webSocketServiceProvider.notifier);
            final isConnected = wsState == WSConnectionState.connected;
            final latency = wsService.latencyMs;
            final latencyColor = latency < 100
                ? Colors.green
                : latency < 300
                    ? Colors.orange
                    : Colors.red;
            return Tooltip(
              message: isConnected ? '已连接 · 延迟 ${latency}ms' : '连接已断开',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isConnected ? latencyColor : Colors.red,
                      boxShadow: [
                        BoxShadow(
                          color: (isConnected ? latencyColor : Colors.red)
                              .withOpacity(0.4),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  if (isConnected)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${latency}ms',
                        style: TextStyle(
                          fontSize: 8,
                          color: latencyColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          }),

          _buildNavRailItem(
            iconPath: 'assets/icons/tab_settings.png',
            activeIconPath: 'assets/icons/tab_settings_active.png',
            label: l10n.tabMe,
            isSelected: navIndex == kDesktopNavSettings,
            onTap: () => _switchNavIndex(kDesktopNavSettings),
            isDark: isDark,
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 导航栏项目（使用自定义 PNG 图标）
  Widget _buildNavRailItem({
    String? iconPath,
    String? activeIconPath,
    String? imageUrl,
    IconData? iconData,
    IconData? activeIconData,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
    int? badge,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: label,
        preferBelow: false,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.primary.withOpacity(0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (imageUrl != null && imageUrl.isNotEmpty)
                  Opacity(
                    opacity: isSelected ? 1 : 0.78,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        imageUrl,
                        width: 24,
                        height: 24,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          isSelected ? (activeIconData ?? iconData) : iconData,
                          size: 24,
                          color: isSelected
                              ? AppColors.primary
                              : (isDark ? Colors.white54 : Colors.black54),
                        ),
                      ),
                    ),
                  )
                else if (iconData != null)
                  Icon(
                    isSelected ? (activeIconData ?? iconData) : iconData,
                    size: 24,
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? Colors.white54 : Colors.black54),
                  )
                else
                  Image.asset(
                    isSelected ? activeIconPath! : iconPath!,
                    width: 24,
                    height: 24,
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? Colors.white54 : Colors.black54),
                  ),
                if (badge != null && badge > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(minWidth: 18),
                      child: Text(
                        badge > 99 ? '99+' : badge.toString(),
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
          ),
        ),
      ),
    );
  }

  /// 左侧内容区（聊天列表等）
  Widget _buildSidebar(bool isDark, int navIndex, bool hasCustomPortal) {
    return Container(
      width: _sidebarWidth,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      ),
      child: Column(
        children: [
          // macOS 标题栏占位
          if (PlatformUtils.isApple)
            const SizedBox(height: kMacOSTitleBarHeight),

          // 内容区域（聊天页面已包含标题栏）
          Expanded(child: _buildSidebarContent(navIndex, hasCustomPortal)),
        ],
      ),
    );
  }

  int _getUnreadChatCount() {
    // 与移动端底部导航角标保持一致：排除已从聊天列表 UI 过滤掉的 channel 类型，
    // 避免不可见的 channel 未读干扰角标显示。
    return ref.watch(
      chatListProvider.select((state) => state.visibleUnreadCount),
    );
  }

  /// 侧边栏内容
  Widget _buildSidebarContent(int navIndex, bool hasCustomPortal) {
    switch (navIndex) {
      case kDesktopNavChats:
        return const ChatPage(isDesktopSidebar: true);
      case kDesktopNavContacts:
        return const ContactsPage(isDesktopSidebar: true);
      case kDesktopNavPortal:
        return hasCustomPortal
            ? const CustomPortalPage(isDesktopSidebar: true)
            : const DiscoverPage(isDesktopSidebar: true);
      case kDesktopNavDiscover:
        return const DiscoverPage(isDesktopSidebar: true);
      case kDesktopNavMoments:
        return MomentsPage(isDesktopSidebar: true);
      case kDesktopNavSettings:
        // 桌面端「我的」tab 与 H5 / 移动端保持一致，统一走新版 MePage —— 蓝色渐变
        // 顶部 + 扁平菜单卡片 + 退出登录卡片。二开时更新了 app_router 但漏掉了
        // 这里，导致 PC web 打包后「我的」是老版 SettingsPage 的样子。
        return const MePage();
      default:
        return const ChatPage(isDesktopSidebar: true);
    }
  }

  /// 分隔条
  Widget _buildDivider(bool isDark) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        onHorizontalDragUpdate: (details) {
          setState(() {
            _sidebarWidth += details.delta.dx;
            _sidebarWidth = _sidebarWidth.clamp(
              PlatformUtils.desktopSidebarMinWidth,
              PlatformUtils.desktopSidebarMaxWidth,
            );
          });
        },
        onHorizontalDragEnd: (_) {
          _saveSidebarWidthDebounced();
        },
        child: Container(
          width: 1,
          color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
        ),
      ),
    );
  }

  /// 右侧内容区域（支持聊天页 + 资料页并排显示）
  Widget _buildContent(
    bool isDark,
    String? selectedChatId,
    int navIndex,
    AppLocalizations l10n,
  ) {
    final profileInfo = ref.watch(desktopProfileProvider);
    final hasProfile = profileInfo.type != DesktopProfileType.none;
    final userUuid =
        ref.watch(authServiceProvider.select((s) => s.user?.uuid ?? ''));

    // 如果有选中的聊天，显示聊天详情
    if (selectedChatId != null &&
        (navIndex == kDesktopNavChats || navIndex == kDesktopNavContacts)) {
      final chatInfo = ref.watch(selectedChatInfoProvider);

      // 聊天页
      final chatPage = ChatDetailPage(
        key: ValueKey('chat_${selectedChatId}_$userUuid'),
        chatId: selectedChatId,
        chatName: chatInfo?.name ?? '',
        avatar: chatInfo?.avatar,
        chatType: chatInfo?.chatType ?? ChatType.private,
        isDesktopMode: true,
      );

      // 如果有资料页，并排显示（三栏布局）
      if (hasProfile) {
        return Row(
          children: [
            // 聊天页（占据剩余空间）
            Expanded(child: chatPage),
            // 分隔线
            Container(
              width: 1,
              color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
            ),
            // 资料页（右侧面板，固定宽度 360）
            SizedBox(
              width: 360,
              child: _buildProfilePanel(isDark, profileInfo),
            ),
          ],
        );
      }

      return chatPage;
    }

    // 没有选中聊天但有资料页（如从联系人直接查看资料、设置页等）
    if (hasProfile) {
      return _buildProfilePanel(isDark, profileInfo);
    }

    // 其他页面：显示空状态
    return _buildEmptyState(isDark, navIndex: navIndex, l10n: l10n);
  }

  /// 右侧面板
  Widget _buildProfilePanel(bool isDark, DesktopProfileInfo info) {
    Widget panelPage;

    switch (info.type) {
      case DesktopPanelType.user:
        panelPage = UserProfilePage(
          key: ValueKey('user_profile_${info.id}'),
          userId: info.id,
          name: info.name,
          avatar: info.avatar,
          chatId: info.chatId,
          isDesktopPanel: true,
        );
        break;
      case DesktopPanelType.group:
        panelPage = GroupProfilePage(
          key: ValueKey('group_profile_${info.id}'),
          groupId: info.id,
          name: info.name,
          avatar: info.avatar,
          isDesktopPanel: true,
        );
        break;
      case DesktopPanelType.channel:
        // 频道功能已移除，回退到空状态
        return _buildEmptyState(isDark);
      case DesktopPanelType.search:
        panelPage = const DesktopSearchPanel(key: ValueKey('search_panel'));
        break;
      case DesktopPanelType.searchUsers:
        panelPage = const DesktopSearchUsersPanel(
          key: ValueKey('search_users_panel'),
        );
        break;
      case DesktopPanelType.momentDetail:
        if (info.momentData != null && info.momentData is Moment) {
          panelPage = DesktopMomentDetailPanel(
            key: ValueKey('moment_detail_${info.id}'),
            moment: info.momentData as Moment,
          );
        } else {
          return _buildEmptyState(isDark);
        }
        break;
      case DesktopPanelType.momentPublish:
        panelPage = DesktopMomentPublishPanel(
          key: const ValueKey('moment_publish'),
        );
        break;
      case DesktopPanelType.momentNotifications:
        panelPage = DesktopMomentNotificationsPanel(
          key: const ValueKey('moment_notifications'),
        );
        break;
      case DesktopPanelType.momentSearch:
        panelPage = DesktopMomentSearchPanel(
          key: const ValueKey('moment_search'),
        );
        break;
      // 设置相关面板
      case DesktopPanelType.settingsProfile:
        panelPage = DesktopSettingsPanel(
          key: const ValueKey('settings_profile'),
          title: '个人资料',
          child: const ProfilePage(isDesktopPanel: true),
        );
        break;
      case DesktopPanelType.settingsNotification:
        panelPage = DesktopSettingsPanel(
          key: const ValueKey('settings_notification'),
          title: '通知和声音',
          child: const NotificationSettingsPage(isDesktopPanel: true),
        );
        break;
      case DesktopPanelType.settingsPrivacy:
        panelPage = DesktopSettingsPanel(
          key: const ValueKey('settings_privacy'),
          title: '隐私和安全',
          child: const PrivacySettingsPage(isDesktopPanel: true),
        );
        break;
      case DesktopPanelType.settingsDataStorage:
        panelPage = DesktopSettingsPanel(
          key: const ValueKey('settings_data'),
          title: '数据和存储',
          child: const DataStoragePage(isDesktopPanel: true),
        );
        break;
      case DesktopPanelType.settingsChatSettings:
        panelPage = DesktopSettingsPanel(
          key: const ValueKey('settings_chat'),
          title: '聊天设置',
          child: const ChatSettingsPage(isDesktopPanel: true),
        );
        break;
      case DesktopPanelType.settingsDevices:
        panelPage = DesktopSettingsPanel(
          key: const ValueKey('settings_devices'),
          title: '设备',
          child: const DevicesPage(isDesktopPanel: true),
        );
        break;
      case DesktopPanelType.settingsStickers:
        panelPage = DesktopSettingsPanel(
          key: const ValueKey('settings_stickers'),
          title: '贴纸和表情',
          child: const StickersPage(isDesktopPanel: true),
        );
        break;
      case DesktopPanelType.settingsFaq:
        panelPage = DesktopSettingsPanel(
          key: const ValueKey('settings_faq'),
          title: '常见问题',
          child: const FAQPage(isDesktopPanel: true),
        );
        break;
      case DesktopPanelType.settingsAbout:
        // 关于页面可以使用独立组件
        panelPage =
            const DesktopDynamicAboutPanel(key: ValueKey('settings_about'));
        break;
      case DesktopPanelType.groupEdit:
        panelPage = DesktopSettingsPanel(
          key: ValueKey('group_edit_${info.id}'),
          title: '编辑群组',
          child: GroupEditPage(chatId: info.id, isDesktopPanel: true),
        );
        break;
      case DesktopPanelType.channelEdit:
        // 频道功能已移除
        return _buildEmptyState(isDark);
      default:
        return _buildEmptyState(isDark);
    }

    return panelPage;
  }

  /// 空状态
  Widget _buildEmptyState(
    bool isDark, {
    int navIndex = 0,
    AppLocalizations? l10n,
  }) {
    // 根据当前标签显示不同的空状态
    String lottiePath;
    String title;
    String subtitle;

    // 根据语言获取文本
    final isEn = l10n?.language.code == 'en';
    final isZhTW = l10n?.language.code == 'zh_TW';

    switch (navIndex) {
      case kDesktopNavChats: // 聊天
        lottiePath = 'assets/emoji/lottie/hatched_chick.json';
        title = isEn
            ? 'Select a chat to start messaging'
            : isZhTW
                ? '選擇一個聊天開始對話'
                : '选择一个聊天开始对话';
        subtitle = isEn
            ? 'or press ⌘N to start a new chat'
            : isZhTW
                ? '或按 ⌘N 創建新聊天'
                : '或按 ⌘N 创建新聊天';
        break;
      case kDesktopNavContacts: // 联系人
        lottiePath = 'assets/emoji/lottie/baby_chick.json';
        title = isEn
            ? 'Select a contact to start chatting'
            : isZhTW
                ? '選擇聯絡人開始聊天'
                : '选择联系人开始聊天';
        subtitle = isEn
            ? 'or press ⌘N to add a new contact'
            : isZhTW
                ? '或按 ⌘N 添加新聯絡人'
                : '或按 ⌘N 添加新联系人';
        break;
      case kDesktopNavPortal: // 自定义网站
        lottiePath = 'assets/emoji/lottie/eyes.json';
        title = isEn
            ? 'Open the configured website'
            : isZhTW
                ? '打開後台配置的網站'
                : '打开后台配置的网站';
        subtitle = isEn
            ? 'The admin panel controls this portal title, icon, and target URL'
            : isZhTW
                ? '此欄目標題、圖示與網址由後台統一配置'
                : '该栏目标题、图标和网址由后台统一配置';
        break;
      case kDesktopNavDiscover: // 发现
        lottiePath = 'assets/emoji/lottie/eyes.json';
        title = isEn
            ? 'Select a portal to start browsing'
            : isZhTW
                ? '選擇一個入口開始瀏覽'
                : '选择一个入口开始浏览';
        subtitle = isEn
            ? 'The current content is frontend demo data and will later be replaced by backend configuration'
            : isZhTW
                ? '目前內容為前端演示資料，後續會切換為後台配置'
                : '当前内容为前端演示数据，后续会切换为后台配置';
        break;
      case kDesktopNavMoments: // 动态
        lottiePath = 'assets/emoji/lottie/angel.json';
        title = isEn
            ? 'Select a post to view details'
            : isZhTW
                ? '選擇一條動態查看詳情'
                : '选择一条动态查看详情';
        subtitle = isEn
            ? 'Click on a post card to view full content'
            : isZhTW
                ? '點擊動態卡片查看完整內容'
                : '点击动态卡片查看完整内容';
        break;
      case kDesktopNavSettings: // 设置
        lottiePath = 'assets/emoji/lottie/unicorn.json';
        title = isEn
            ? 'Select a setting to view details'
            : isZhTW
                ? '選擇設定項查看詳情'
                : '选择设置项查看详情';
        subtitle = isEn
            ? 'Click on a menu item to configure'
            : isZhTW
                ? '點擊左側選單項進行設定'
                : '点击左侧菜单项进行设置';
        break;
      default:
        lottiePath = 'assets/emoji/lottie/hatched_chick.json';
        title = isEn
            ? 'Select a chat to start messaging'
            : isZhTW
                ? '選擇一個聊天開始對話'
                : '选择一个聊天开始对话';
        subtitle = isEn
            ? 'or press ⌘N to start a new chat'
            : isZhTW
                ? '或按 ⌘N 創建新聊天'
                : '或按 ⌘N 创建新聊天';
    }

    return Container(
      color: isDark ? AppColors.darkBackground : const Color(0xFFF5F5F5),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 100,
              height: 100,
              child: Lottie.asset(lottiePath, repeat: true),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white24 : Colors.black26,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 桌面端搜索面板（聊天/联系人/消息搜索）
class DesktopSearchPanel extends ConsumerWidget {
  const DesktopSearchPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // SearchPage 已有自己的 Scaffold，直接使用并添加桌面面板支持
    return const SearchPage(isDesktopPanel: true);
  }
}

/// 桌面端搜索用户面板
class DesktopSearchUsersPanel extends ConsumerWidget {
  const DesktopSearchUsersPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // NewContactPage 已有自己的 Scaffold，直接使用并添加桌面面板支持
    return const NewContactPage(isDesktopPanel: true);
  }
}

/// 桌面端动态详情面板
class DesktopMomentDetailPanel extends ConsumerWidget {
  final Moment moment;

  const DesktopMomentDetailPanel({super.key, required this.moment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: AppColors.primary),
          onPressed: () {
            ref.read(desktopProfileProvider.notifier).state =
                DesktopProfileInfo.none;
          },
        ),
        title: Text(
          '动态详情',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: MomentDetailPage(moment: moment, isDesktopPanel: true),
    );
  }
}

/// 桌面端发布动态面板
class DesktopMomentPublishPanel extends ConsumerWidget {
  const DesktopMomentPublishPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // MomentPublishPage 有自己的标题栏，直接使用
    return MomentPublishPage(isDark: isDark, isDesktopPanel: true);
  }
}

/// 桌面端动态通知面板
class DesktopMomentNotificationsPanel extends ConsumerWidget {
  const DesktopMomentNotificationsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // MomentNotificationsPage 有自己的 AppBar，直接使用
    return MomentNotificationsPage(isDark: isDark, isDesktopPanel: true);
  }
}

/// 桌面端动态搜索面板
class DesktopMomentSearchPanel extends ConsumerWidget {
  const DesktopMomentSearchPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // MomentSearchPage 有自己的 AppBar，直接使用
    return MomentSearchPage(isDark: isDark, isDesktopPanel: true);
  }
}

/// 桌面端设置面板通用包装器
class DesktopSettingsPanel extends ConsumerWidget {
  final String title;
  final Widget child;
  final List<Widget>? actions;

  const DesktopSettingsPanel({
    super.key,
    required this.title,
    required this.child,
    this.actions,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: AppColors.primary),
          onPressed: () {
            ref.read(desktopProfileProvider.notifier).state =
                DesktopProfileInfo.none;
          },
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
        actions: actions,
      ),
      body: child,
    );
  }
}

/// 桌面端关于页面面板
class DesktopAboutPanel extends ConsumerWidget {
  const DesktopAboutPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: AppColors.primary),
          onPressed: () {
            ref.read(desktopProfileProvider.notifier).state =
                DesktopProfileInfo.none;
          },
        ),
        title: Text(
          '关于',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(
                Icons.info_outline_rounded,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '锦绣汇',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'v1.0.1',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              '© 锦绣汇',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
