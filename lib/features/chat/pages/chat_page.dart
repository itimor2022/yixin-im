import 'package:universal_io/io.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/utils/floating_nav_layout.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/shimmer_loading.dart';
import '../../../shared/widgets/empty_state.dart';
import '../widgets/chat_list_item.dart';
import '../widgets/create_sheets.dart';
import '../providers/chat_provider.dart';
import '../providers/folder_provider.dart';
import '../../contacts/providers/contact_provider.dart';
import '../../settings/pages/chat_settings_page.dart';
import '../../home/pages/home_desktop_page.dart';
import 'chat_detail_page.dart' show ChatType;

class ChatPage extends ConsumerStatefulWidget {
  /// 是否作为桌面端侧边栏使用
  final bool isDesktopSidebar;

  const ChatPage({super.key, this.isDesktopSidebar = false});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final Set<String> _selectedChatIds = {};

  @override
  bool get wantKeepAlive => true;

  bool get _isEditing => ref.watch(chatEditModeProvider);

  @override
  void initState() {
    super.initState();
    // 监听应用生命周期
    WidgetsBinding.instance.addObserver(this);

    // 初始化时从服务器加载数据（仅在已登录时）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final authState = ref.read(authServiceProvider);
      if (authState.status == AuthStatus.authenticated) {
        // 优先初始化聊天列表（用户首先看到的内容）
        // initialize() 内部会先读 Isar 缓存再请求服务器
        ref.read(chatListProvider.notifier).initialize();

        // 延迟初始化联系人，减少启动时的请求压力
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!mounted) return;
          ref.read(contactListProvider.notifier).initialize();
        });

        // 进一步延迟同步官方联系人，避免启动时请求过多
        Future.delayed(const Duration(milliseconds: 2000), () async {
          if (!mounted) return;
          final settingsService = ref.read(systemSettingsServiceProvider);
          try {
            final settings =
                await settingsService.getSettings(forceRefresh: true);
            if (!mounted || !settings.newUserFollowOfficial) return;
          } catch (error) {
            debugPrint(
              '[ChatPage] Load settings before official sync failed: $error',
            );
            return;
          }

          final added = await settingsService.syncOfficialContacts();
          if (mounted && added > 0) {
            ref.read(contactListProvider.notifier).loadFromServer();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // 应用从后台恢复时自动刷新
    if (state == AppLifecycleState.resumed) {
      _refreshOnResume();
    }
  }

  /// 应用恢复时刷新数据（静默刷新，不显示加载状态）
  Future<void> _refreshOnResume() async {
    final authState = ref.read(authServiceProvider);
    if (authState.status == AuthStatus.authenticated) {
      // 静默刷新聊天列表（不显示loading，不重新排序）
      ref.read(chatListProvider.notifier).silentRefresh();
      // 静默刷新联系人列表
      ref.read(contactListProvider.notifier).silentRefresh();
    }
  }

  /// 构建标题（显示刷新状态）
  Widget _buildTitle(bool isDark, AppLocalizations l10n) {
    // 使用 select 只监听加载状态，避免不必要的重建
    final isLoading = ref.watch(chatListProvider.select((s) => s.isLoading));
    final isSilentLoading = ref.watch(
      chatListProvider.select((s) => s.isSilentLoading),
    );

    // 首次加载或手动刷新时显示"刷新中..."
    if (isLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.refreshing,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ],
      );
    }

    // 从后台恢复时静默刷新，使用相同的刷新中样式
    if (isSilentLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.refreshing,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ],
      );
    }

    return Text(
      l10n.tabChat,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final folderState = ref.watch(folderProvider);
    final l10n = AppLocalizations(ref.watch(languageProvider));

    // 使用 select 只监听需要的字段，避免不必要的重建
    final pinnedChats = ref.watch(
      chatListProvider.select((s) => s.pinnedChats),
    );
    final regularChats = ref.watch(
      chatListProvider.select((s) => s.regularChats),
    );
    final typingByChat = ref.watch(
      chatListProvider.select((s) => s.typingByChat),
    );
    final chats = ChatListState(
      pinnedChats: pinnedChats,
      regularChats: regularChats,
      isInitialized: true,
    );

    // 获取系统设置（官方用户/群组/频道列表）- 使用 select 只监听需要的字段
    final systemSettingsAsync = ref.watch(systemSettingsProvider);
    final officialUsers = systemSettingsAsync.maybeWhen(
      data: (settings) => settings.officialUsers.toSet(),
      orElse: () => <String>{},
    );
    final officialChats = systemSettingsAsync.maybeWhen(
      data: (settings) => {
        ...settings.officialGroups,
        ...settings.officialChannels,
      },
      orElse: () => <String>{},
    );

    // 当前选中的文件夹
    final currentFolder = folderState.folders.isNotEmpty &&
            folderState.selectedIndex < folderState.folders.length
        ? folderState.folders[folderState.selectedIndex]
        : null;
    final floatingBottomSpace = FloatingNavLayout.isEnabled
        ? FloatingNavLayout.reservedSpace(context, extra: 12)
        : 20.0;

    // 过滤后的聊天
    final filteredChats = currentFolder != null
        ? ref.read(folderProvider.notifier).filterChats(currentFolder, chats)
        : chats;

    // 预先计算聊天列表，避免在 build 中重复调用
    final allChats = _getChatList(filteredChats);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        body: CustomScrollView(
          slivers: [
            // 顶部标题栏 - 毛玻璃固定效果
            SliverAppBar(
              floating: false,
              snap: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              flexibleSpace: Platform.isAndroid
                  ? Container(
                      color: isDark
                          ? AppColors.darkBackground
                          : AppColors.lightBackground,
                    )
                  : ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: Container(
                          color: isDark
                              ? AppColors.darkBackground.withOpacity(0.85)
                              : AppColors.lightBackground.withOpacity(0.85),
                        ),
                      ),
                    ),
              leadingWidth: widget.isDesktopSidebar ? 16 : 76,
              leading: widget.isDesktopSidebar
                  ? const SizedBox(width: 16) // 桌面端不显示编辑按钮
                  : Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Center(
                        child: GestureDetector(
                          onTap: () {
                            GlobalHaptics.selection();
                            if (_isEditing) {
                              ref.read(chatEditModeProvider.notifier).state =
                                  false;
                              setState(() => _selectedChatIds.clear());
                            } else {
                              ref.read(chatEditModeProvider.notifier).state =
                                  true;
                              setState(() => _selectedChatIds.clear());
                            }
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.12)
                                      : Colors.white.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(20),
                                  border: isDark
                                      ? Border.all(
                                          color: Colors.white.withOpacity(0.1),
                                          width: 0.5,
                                        )
                                      : null,
                                  boxShadow: isDark
                                      ? null
                                      : [
                                          BoxShadow(
                                            color: Colors.black.withOpacity(
                                              0.06,
                                            ),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                ),
                                child: Text(
                                  _isEditing ? '完成' : '编辑',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
              title: _isEditing
                  ? Text(
                      _selectedChatIds.isEmpty
                          ? '选择聊天'
                          : '${l10n.selectedCount} ${_selectedChatIds.length}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                      ),
                    )
                  : _buildTitle(isDark, l10n),
              centerTitle: true,
              actions: [
                if (!_isEditing) ...[
                  // 右侧加号按钮
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () => _showCreateOptions(context),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.12)
                                  : Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(18),
                              border: isDark
                                  ? Border.all(
                                      color: Colors.white.withOpacity(0.1),
                                      width: 0.5,
                                    )
                                  : null,
                              boxShadow: isDark
                                  ? null
                                  : [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.06),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                            ),
                            child: Icon(
                              Icons.add,
                              size: 22,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  // 编辑模式下的全选按钮
                  GestureDetector(
                    onTap: () {
                      GlobalHaptics.selection();
                      final allChats = _getChatList(filteredChats);
                      setState(() {
                        if (_selectedChatIds.length == allChats.length) {
                          _selectedChatIds.clear();
                        } else {
                          _selectedChatIds.clear();
                          _selectedChatIds.addAll(allChats.map((c) => c.id));
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Text(
                        _selectedChatIds.length ==
                                _getChatList(filteredChats).length
                            ? l10n.deselectAll
                            : l10n.selectAll,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // 搜索框（滑动时隐藏）
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: GestureDetector(
                  onTap: () {
                    if (widget.isDesktopSidebar) {
                      // 桌面端：在右侧面板显示搜索
                      ref.read(desktopProfileProvider.notifier).state =
                          const DesktopProfileInfo(
                        type: DesktopPanelType.search,
                        id: 'search',
                      );
                    } else {
                      context.push('/search');
                    }
                  },
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkInputBackground
                          : const Color(0xFFEDEDED),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.search,
                          size: 18,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : const Color(0xFF8E8E93),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '搜索',
                          style: TextStyle(
                            fontSize: 15,
                            color: isDark
                                ? AppColors.darkTextTertiary
                                : const Color(0xFF8E8E93),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 分组 Tab（滑动时隐藏）
            SliverToBoxAdapter(
              child: _FolderTabs(
                folders: folderState.folders,
                selectedIndex: folderState.selectedIndex,
                chats: chats,
                onSelect: (index) {
                  GlobalHaptics.selection();
                  ref.read(folderProvider.notifier).selectFolder(index);
                },
              ),
            ),

            // 聊天列表
            if (!chats.isInitialized && chats.isLoading)
              // 首次加载显示骨架屏
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildSkeletonItem(isDark),
                  childCount: 8,
                ),
              )
            else if (allChats.isEmpty)
              SliverFillRemaining(child: _buildEmptyState(l10n))
            else
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final chat = allChats[index];
                  final isSelected = _selectedChatIds.contains(chat.id);

                  if (_isEditing) {
                    // 编辑模式 - 显示复选框
                    return _buildEditableChatItem(
                      chat,
                      isSelected,
                      isDark,
                      typingText: typingByChat[chat.id],
                    );
                  }

                  // 判断是否是官方用户/群组/频道
                  final isOfficial = chat.type == ChatItemType.private
                      ? officialUsers.contains(chat.targetUserUuid)
                      : officialChats.contains(chat.id);

                  // 桌面端：检查是否选中（用于高亮当前打开的聊天）
                  final isChatActive = widget.isDesktopSidebar
                      ? ref.watch(selectedChatIdProvider) == chat.id
                      : false;

                  // RepaintBoundary + key 隔离每个列表项的重绘，优化滚动性能
                  return RepaintBoundary(
                    key: ValueKey(chat.id),
                    child: ChatListItem(
                      chat: chat,
                      typingText: typingByChat[chat.id],
                      isOfficial: isOfficial,
                      isSelected: isChatActive,
                      isDesktop: widget.isDesktopSidebar,
                      showPendingApprovalDot: chat.hasPendingJoinRequests,
                      onTap: () => _openChat(context, chat),
                      onLongPress: widget.isDesktopSidebar
                          ? null
                          : () => _showChatPreview(context, ref, chat),
                      onSwipeAction: (action) =>
                          _handleSwipeAction(context, ref, chat, action),
                    ),
                  );
                }, childCount: allChats.length),
              ),

            // 编辑模式下留出底部操作栏空间
            SliverToBoxAdapter(
              child: SizedBox(
                height: _isEditing ? 100 : floatingBottomSpace,
              ),
            ),
          ],
        ),
        // 编辑模式底部操作栏
        bottomNavigationBar:
            _isEditing ? _buildEditBottomBar(isDark, l10n) : null,
      ),
    );
  }

  void _showCreateOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomSpacing = FloatingNavLayout.isEnabled
        ? FloatingNavLayout.reservedSpace(context, extra: 8)
        : 8.0;
    // 保存外部 context 用于导航（底部弹窗 pop 后内部 context 会失效）
    final outerContext = context;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color:
                      isDark ? AppColors.darkDivider : AppColors.lightDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              _CreateOption(
                icon: Icons.search,
                iconColor: AppColors.primary,
                title: '搜索用户',
                subtitle: '搜索用户开始聊天',
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (widget.isDesktopSidebar) {
                    // 桌面端：在右侧面板显示搜索用户
                    ref.read(desktopProfileProvider.notifier).state =
                        const DesktopProfileInfo(
                      type: DesktopPanelType.searchUsers,
                      id: 'search_users',
                    );
                  } else {
                    outerContext.push('/search-users');
                  }
                },
              ),
              _CreateOption(
                icon: Icons.group_outlined,
                iconColor: const Color(0xFF4CAF50),
                title: '新建群组',
                subtitle: '创建一个群聊',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCreateGroup(outerContext);
                },
              ),
              _CreateOption(
                icon: Icons.campaign_outlined,
                iconColor: const Color(0xFFFF9800),
                title: '新建频道',
                subtitle: '创建一个频道发布消息',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCreateChannel(outerContext);
                },
              ),
              _CreateOption(
                icon: Icons.qr_code_scanner,
                iconColor: const Color(0xFF9C27B0),
                title: '扫描二维码',
                subtitle: '扫码添加好友或群组',
                onTap: () {
                  Navigator.pop(sheetContext);
                  outerContext.push('/scan');
                },
              ),
              SizedBox(height: bottomSpacing),
            ],
          ),
        ),
      ),
    );
  }

  void _showNewChat(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _NewChatSheet(),
    );
  }

  void _showCreateGroup(BuildContext context) {
    showCreateGroupSheet(context);
  }

  void _showCreateChannel(BuildContext context) {
    showCreateChannelSheet(context);
  }

  List<ChatItem> _getChatList(ChatListState chats) {
    return [...chats.pinnedChats, ...chats.regularChats];
  }

  /// 骨架屏加载项（带 shimmer 动画）
  Widget _buildSkeletonItem(bool isDark) {
    return Column(
      children: [
        const ChatListSkeletonItem(),
        // 分割线
        Container(
          margin: const EdgeInsets.only(left: 82),
          height: 0.5,
          color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
        ),
      ],
    );
  }

  /// 编辑模式下的聊天项
  Widget _buildEditableChatItem(
    ChatItem chat,
    bool isSelected,
    bool isDark, {
    String? typingText,
  }) {
    return InkWell(
      onTap: () {
        GlobalHaptics.selection();
        setState(() {
          if (isSelected) {
            _selectedChatIds.remove(chat.id);
          } else {
            _selectedChatIds.add(chat.id);
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 复选框
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : (isDark ? Colors.white38 : Colors.black26),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            // 头像
            AvatarWidget(avatar: chat.avatar, name: chat.name, size: 52),
            const SizedBox(width: 12),
            // 内容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: ColoredNameWidget(
                                name: chat.name,
                                nicknameColor: chat.nicknameColor,
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                defaultColor: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.lightTextPrimary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // 表情状态
                            if (chat.emojiAvatar != null &&
                                chat.emojiAvatar!.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              EmojiStatusWidget(
                                emoji: chat.emojiAvatar!,
                                size: 20,
                              ),
                            ],
                          ],
                        ),
                      ),
                      Text(
                        _formatTime(chat.lastMessageTime),
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : AppColors.lightTextTertiary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    (typingText != null && typingText.isNotEmpty)
                        ? typingText
                        : (chat.lastMessage?.isNotEmpty == true
                            ? chat.lastMessage!
                            : '快来发送第一条消息吧～'),
                    style: TextStyle(
                      fontSize: 15,
                      color: (typingText != null && typingText.isNotEmpty)
                          ? Colors.blue
                          : (chat.lastMessage?.isNotEmpty == true
                              ? (isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary)
                              : (isDark
                                  ? AppColors.darkTextTertiary
                                  : AppColors.lightTextTertiary)),
                      fontStyle: (typingText != null && typingText.isNotEmpty)
                          ? FontStyle.italic
                          : (chat.lastMessage?.isNotEmpty == true
                              ? FontStyle.normal
                              : FontStyle.italic),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${time.month}/${time.day}';
  }

  /// 编辑模式底部操作栏（毛玻璃按钮）
  Widget _buildEditBottomBar(bool isDark, AppLocalizations l10n) {
    final hasSelection = _selectedChatIds.isNotEmpty;

    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.of(context).viewPadding.bottom + 12,
      ),
      child: Row(
        children: [
          // 标记已读
          Expanded(
            child: GestureDetector(
              onTap: hasSelection ? _markSelectedAsRead : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: hasSelection
                          ? (isDark
                              ? Colors.white.withOpacity(0.15)
                              : Colors.white.withOpacity(0.9))
                          : (isDark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      l10n.markAsRead,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: hasSelection
                            ? AppColors.primary
                            : (isDark ? Colors.white38 : Colors.grey),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 删除
          Expanded(
            child: GestureDetector(
              onTap: hasSelection ? _deleteSelected : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: hasSelection
                          ? AppColors.error.withOpacity(0.15)
                          : (isDark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      '删除',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: hasSelection
                            ? AppColors.error
                            : (isDark ? Colors.white38 : Colors.grey),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _markSelectedAsRead() {
    GlobalHaptics.medium();
    final notifier = ref.read(chatListProvider.notifier);
    final chats = ref.read(chatListProvider);
    final allChats = _getChatList(chats);

    for (final chatId in _selectedChatIds) {
      final idx = allChats.indexWhere((c) => c.id == chatId);
      if (idx < 0) continue;
      final chat = allChats[idx];
      if (chat.unreadCount > 0) {
        notifier.toggleUnread(chatId);
      }
    }
    ref.read(chatEditModeProvider.notifier).state = false;
    setState(() => _selectedChatIds.clear());
  }

  void _muteSelected() {
    GlobalHaptics.medium();
    final notifier = ref.read(chatListProvider.notifier);
    final chats = ref.read(chatListProvider);
    final allChats = _getChatList(chats);

    for (final chatId in _selectedChatIds) {
      final idx = allChats.indexWhere((c) => c.id == chatId);
      if (idx < 0) continue;
      final chat = allChats[idx];
      if (!chat.isMuted) {
        notifier.toggleMute(chatId);
      }
    }
    ref.read(chatEditModeProvider.notifier).state = false;
    setState(() => _selectedChatIds.clear());
  }

  void _pinSelected() {
    GlobalHaptics.medium();
    final notifier = ref.read(chatListProvider.notifier);
    final chats = ref.read(chatListProvider);
    final allChats = _getChatList(chats);

    for (final chatId in _selectedChatIds) {
      final idx = allChats.indexWhere((c) => c.id == chatId);
      if (idx < 0) continue;
      final chat = allChats[idx];
      if (!chat.isPinned) {
        notifier.togglePin(chatId);
      }
    }
    ref.read(chatEditModeProvider.notifier).state = false;
    setState(() => _selectedChatIds.clear());
  }

  void _deleteSelected() {
    GlobalHaptics.medium();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) {
        return Center(
          child: ScaleTransition(
            scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                width: 280,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.black.withOpacity(0.7)
                      : Colors.white.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 0.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 48,
                      color: AppColors.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '删除 ${_selectedChatIds.length} 个聊天？',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '聊天将从列表中移除，但不会删除聊天记录',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withOpacity(0.1)
                                    : Colors.grey.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '取消',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color:
                                      isDark ? Colors.white70 : Colors.black54,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              Navigator.pop(context);
                              _performDelete();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.error,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text(
                                '删除',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _performDelete() {
    final notifier = ref.read(chatListProvider.notifier);
    for (final chatId in _selectedChatIds) {
      notifier.hideChatFromServer(chatId);
    }
    ref.read(chatEditModeProvider.notifier).state = false;
    setState(() => _selectedChatIds.clear());
  }

  Widget _buildEmptyState(AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: Lottie.asset(
              'assets/emoji/lottie/hatched_chick.json',
              repeat: true,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noChats,
            style: TextStyle(fontSize: 16, color: AppColors.lightTextSecondary),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _showCreateOptions(context),
            child: Text(l10n.startNewChat),
          ),
        ],
      ),
    );
  }

  void _openChat(BuildContext context, ChatItem chat) {
    if (PlatformUtils.isMobile) {
      GlobalHaptics.selection();
    }

    // 桌面端：更新右侧面板
    if (widget.isDesktopSidebar) {
      // 切换聊天时重置右侧资料面板（避免残留上一个聊天的资料栏）
      ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo.none;
      // 设置完整的聊天信息
      ref.read(selectedChatInfoProvider.notifier).state = SelectedChatInfo(
        id: chat.id,
        name: chat.name,
        avatar: chat.avatar,
        chatType: _convertChatItemType(chat.type),
      );
      ref.read(selectedChatIdProvider.notifier).state = chat.id;
      return;
    }

    // 移动端：导航到聊天详情页
    final typeStr = chat.type.name;
    context.push(
      '/chat/${chat.id}?name=${Uri.encodeComponent(chat.name)}&type=$typeStr${chat.avatar != null ? '&avatar=${Uri.encodeComponent(chat.avatar!)}' : ''}',
    );
  }

  /// 转换 ChatItemType 到 ChatType
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

  /// 长按预览 - TG 风格
  void _showChatPreview(BuildContext context, WidgetRef ref, ChatItem chat) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 保存外部 context，用于 pop 后的操作
    final outerContext = context;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      useSafeArea: false,
      builder: (dialogContext) => _ChatPreviewDialog(
        chat: chat,
        isDark: isDark,
        // 注意：_ChatPreviewDialog 内部已经调用了 Navigator.pop，这里不需要再调用
        onOpen: () {
          _openChat(outerContext, chat);
        },
        onPin: () {
          _handleSwipeAction(outerContext, ref, chat, SwipeAction.pin);
        },
        onMute: () {
          _handleSwipeAction(outerContext, ref, chat, SwipeAction.mute);
        },
        onRead: () {
          _handleSwipeAction(outerContext, ref, chat, SwipeAction.read);
        },
        onDelete: () {
          _handleSwipeAction(outerContext, ref, chat, SwipeAction.delete);
        },
      ),
    );
  }

  /// 处理左滑操作
  void _handleSwipeAction(
    BuildContext context,
    WidgetRef ref,
    ChatItem chat,
    SwipeAction action,
  ) {
    final notifier = ref.read(chatListProvider.notifier);

    switch (action) {
      case SwipeAction.pin:
        notifier.togglePin(chat.id);
        break;

      case SwipeAction.mute:
        notifier.toggleMute(chat.id);
        break;

      case SwipeAction.read:
        notifier.toggleUnread(chat.id);
        break;

      case SwipeAction.delete:
        // 直接删除聊天记录并从列表移除
        notifier.deleteChat(chat.id);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('已删除'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        break;
    }
  }

  void _showDeleteConfirmDialog(
    BuildContext context,
    WidgetRef ref,
    ChatItem chat,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          '删除聊天',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        content: Text(
          '确定要删除与"${chat.name}"的聊天记录吗？',
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(chatListProvider.notifier).deleteChat(chat.id);
            },
            child: Text('删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }

  /// 删除选项对话框 - iOS ActionSheet 风格
  void _showDeleteOptionsDialog(
    BuildContext context,
    WidgetRef ref,
    ChatItem chat,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 选项卡片
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Text(
                      '删除与"${chat.name}"的聊天',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  // 删除列表
                  _DeleteOptionItem(
                    title: '从列表中删除',
                    subtitle: '仅从聊天列表移除，保留聊天记录',
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(context);
                      ref
                          .read(chatListProvider.notifier)
                          .hideChatFromServer(chat.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('已从列表中移除'),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    },
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  // 删除聊天记录
                  _DeleteOptionItem(
                    title: '删除聊天记录',
                    subtitle: '清空本地聊天记录，对方的记录不受影响',
                    isDark: isDark,
                    isDestructive: true,
                    onTap: () {
                      Navigator.pop(context);
                      // 显示二次确认
                      _showFinalDeleteConfirm(context, ref, chat);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 取消按钮
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  '取消',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  /// 删除聊天记录的二次确认
  void _showFinalDeleteConfirm(
    BuildContext context,
    WidgetRef ref,
    ChatItem chat,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          '确认删除',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        content: Text(
          '确定要删除与"${chat.name}"的所有聊天记录吗？\n\n此操作仅删除您本地的记录，对方手机上的聊天记录不会被删除。',
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white70 : Colors.black87,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '取消',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // 删除聊天记录
              ref.read(chatListProvider.notifier).deleteChat(chat.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('聊天记录已删除'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
            child: Text('删除', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
  }
}

/// 删除选项项目
class _DeleteOptionItem extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isDark;
  final bool isDestructive;
  final VoidCallback onTap;

  const _DeleteOptionItem({
    required this.title,
    required this.subtitle,
    required this.isDark,
    this.isDestructive = false,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w400,
                color: isDestructive
                    ? AppColors.error
                    : (isDark ? Colors.white : Colors.black),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// 长按预览对话框
class _ChatPreviewDialog extends ConsumerStatefulWidget {
  final ChatItem chat;
  final bool isDark;
  final VoidCallback onOpen;
  final VoidCallback onPin;
  final VoidCallback onMute;
  final VoidCallback onRead;
  final VoidCallback onDelete;

  const _ChatPreviewDialog({
    required this.chat,
    required this.isDark,
    required this.onOpen,
    required this.onPin,
    required this.onMute,
    required this.onRead,
    required this.onDelete,
  });

  @override
  ConsumerState<_ChatPreviewDialog> createState() => _ChatPreviewDialogState();
}

class _ChatPreviewDialogState extends ConsumerState<_ChatPreviewDialog>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  String _currentUserId = '';
  bool _isOnline = false;
  DateTime? _lastSeen;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _blurAnimation;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 200), // 更快的动画
      vsync: this,
    );

    // 使用弹簧曲线让动画更自然
    _scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Cubic(0.34, 1.56, 0.64, 1), // 自定义弹簧曲线
      ),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animController,
        curve: const Interval(0, 0.6, curve: Curves.easeOut),
      ),
    );
    _blurAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    // 立即开始动画
    _animController.forward();

    // 获取当前用户 ID
    final authState = ref.read(authServiceProvider);
    _currentUserId = authState.user?.uuid ?? '';

    _loadMessages();
    _loadUserStatus();
  }

  /// 流畅关闭动画
  Future<void> _closeWithAnimation() async {
    if (_isClosing) return;
    _isClosing = true;

    // 反向播放动画
    await _animController.reverse();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 加载用户真实在线状态
  Future<void> _loadUserStatus() async {
    if (widget.chat.type != ChatItemType.private) return;

    try {
      final api = ref.read(apiClientProvider);
      final userId = widget.chat.targetUserId ?? widget.chat.id;
      final response = await api.get('/user/$userId');

      if (!mounted) return;
      if (response.isSuccess && response.data != null) {
        setState(() {
          _isOnline = response.data['status'] == 1;
          if (response.data['last_seen'] != null) {
            _lastSeen = DateTime.tryParse(
              response.data['last_seen'],
            )?.toLocal();
          }
        });
      }
    } catch (e) {
      debugPrint('加载用户状态失败: $e');
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final api = ref.read(apiClientProvider);
      // 修复 API 路径
      final response = await api.get(
        '/message/list',
        queryParameters: {'chat_id': widget.chat.id, 'limit': 15},
      );

      if (!mounted) return;
      if (response.isSuccess && response.data != null) {
        final rawList = response.data is List ? response.data as List : [];
        if (!mounted) return;
        setState(() {
          _messages = rawList
              .whereType<Map<String, dynamic>>()
              .toList()
              .reversed
              .toList();
          _isLoading = false;
        });

        // 滚动到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('加载消息失败: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final isDark = widget.isDark;
    final chat = widget.chat;

    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        final blurValue = 30 * _blurAnimation.value;

        return Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              // 全屏模糊背景 - 优化性能
              Positioned.fill(
                child: GestureDetector(
                  onTap: _closeWithAnimation,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 100),
                    color: Colors.black.withOpacity(0.4 * _fadeAnimation.value),
                    child: blurValue > 0.5
                        ? BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: blurValue,
                              sigmaY: blurValue,
                            ),
                            child: const SizedBox.expand(),
                          )
                        : const SizedBox.expand(),
                  ),
                ),
              ),

              // 主内容 - 使用 Transform 而非 Opacity 以获得更好的性能
              Center(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 聊天窗口预览卡片
                        GestureDetector(
                          onTap: () async {
                            await _closeWithAnimation();
                            widget.onOpen();
                          },
                          child: Container(
                            width: screenWidth * 0.9,
                            height: screenHeight * 0.52,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 40,
                                  spreadRadius: 0,
                                  offset: const Offset(0, 15),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: Stack(
                                children: [
                                  // 聊天背景 - 使用用户设置
                                  Consumer(
                                    builder: (context, ref, child) {
                                      final chatBackground = ref.watch(
                                        chatBackgroundProvider,
                                      );
                                      final gradientColors =
                                          chatBackground.gradient?.colors ??
                                              [
                                                const Color(0xFFE8D5E0),
                                                const Color(0xFFD4C5E0),
                                                const Color(0xFFC5D0E8),
                                              ];

                                      return Container(
                                        decoration: BoxDecoration(
                                          gradient: LinearGradient(
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                            colors: gradientColors,
                                          ),
                                        ),
                                      );
                                    },
                                  ),

                                  // SVG 背景图案
                                  Positioned.fill(
                                    child: Opacity(
                                      opacity: 0.2,
                                      child: SvgPicture.asset(
                                        'assets/images/backgrounds/bg5.svg',
                                        fit: BoxFit.cover,
                                        colorFilter: const ColorFilter.mode(
                                          Colors.white,
                                          BlendMode.srcIn,
                                        ),
                                      ),
                                    ),
                                  ),

                                  // 顶部导航栏
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: ClipRRect(
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(
                                          sigmaX: 20,
                                          sigmaY: 20,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.fromLTRB(
                                            12,
                                            10,
                                            14,
                                            10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isDark
                                                ? Colors.black.withOpacity(0.5)
                                                : Colors.white.withOpacity(
                                                    0.85,
                                                  ),
                                          ),
                                          child: Row(
                                            children: [
                                              // 返回按钮
                                              Container(
                                                width: 32,
                                                height: 32,
                                                decoration: BoxDecoration(
                                                  color: isDark
                                                      ? Colors.white
                                                          .withOpacity(0.1)
                                                      : Colors.black
                                                          .withOpacity(0.05),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  Icons
                                                      .arrow_back_ios_new_rounded,
                                                  size: 16,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              // 名称和状态
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Flexible(
                                                          child: Text(
                                                            chat.name,
                                                            style: TextStyle(
                                                              fontSize: 16,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: isDark
                                                                  ? Colors.white
                                                                  : Colors
                                                                      .black,
                                                            ),
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                        if (chat.isMuted)
                                                          Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .only(
                                                              left: 4,
                                                            ),
                                                            child: Icon(
                                                              Icons
                                                                  .volume_off_rounded,
                                                              size: 14,
                                                              color: isDark
                                                                  ? Colors
                                                                      .white38
                                                                  : Colors
                                                                      .black38,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                    const SizedBox(height: 1),
                                                    Text(
                                                      _getSubtitle(),
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: _isOnline
                                                            ? AppColors.online
                                                            : (isDark
                                                                ? Colors.white54
                                                                : Colors
                                                                    .black45),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              // 头像
                                              AvatarWidget(
                                                name: chat.name,
                                                avatar: chat.avatar,
                                                userId: chat.type ==
                                                        ChatItemType.private
                                                    ? (chat.targetUserId ??
                                                        chat.id)
                                                    : chat.id,
                                                size: 38,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),

                                  // 消息列表区域
                                  Positioned(
                                    top: 60,
                                    left: 0,
                                    right: 0,
                                    bottom: 0,
                                    child: _buildMessageArea(isDark, chat),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // 操作菜单 - TG 风格
                        Container(
                          width: screenWidth * 0.9,
                          decoration: BoxDecoration(
                            color:
                                isDark ? const Color(0xFF1C1C1E) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _TGMenuItem(
                                icon: chat.unreadCount > 0
                                    ? Icons.mark_chat_read_outlined
                                    : Icons.mark_chat_unread_outlined,
                                title: chat.unreadCount > 0 ? '标记为已读' : '标记为未读',
                                isDark: isDark,
                                onTap: () async {
                                  await _closeWithAnimation();
                                  widget.onRead();
                                },
                              ),
                              _TGMenuDivider(isDark: isDark),
                              _TGMenuItem(
                                icon: chat.isPinned
                                    ? Icons.push_pin_outlined
                                    : Icons.push_pin,
                                title: chat.isPinned ? '取消置顶' : '置顶',
                                isDark: isDark,
                                onTap: () async {
                                  await _closeWithAnimation();
                                  widget.onPin();
                                },
                              ),
                              _TGMenuDivider(isDark: isDark),
                              _TGMenuItem(
                                icon: chat.isMuted
                                    ? Icons.notifications_active_outlined
                                    : Icons.notifications_off_outlined,
                                title: chat.isMuted ? '取消静音' : '静音',
                                isDark: isDark,
                                onTap: () async {
                                  await _closeWithAnimation();
                                  widget.onMute();
                                },
                              ),
                              _TGMenuDivider(isDark: isDark),
                              _TGMenuItem(
                                icon: Icons.delete_outline,
                                title: '删除',
                                isDark: isDark,
                                isDestructive: true,
                                onTap: () async {
                                  await _closeWithAnimation();
                                  widget.onDelete();
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessageArea(bool isDark, ChatItem chat) {
    if (_isLoading) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation(Colors.white70),
            ),
          ),
        ),
      );
    }

    if (_messages.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '暂无消息',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white70 : Colors.white,
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return _PreviewBubble(
          message: msg,
          isDark: isDark,
          isPrivate: chat.type == ChatItemType.private,
          currentUserId: _currentUserId,
        );
      },
    );
  }

  String _getSubtitle() {
    // 使用实时获取的在线状态
    if (widget.chat.type == ChatItemType.private) {
      if (_isOnline) return '在线';
      if (_lastSeen != null) {
        return '最近上线于 ${_formatLastSeen(_lastSeen!)}';
      }
    }
    if (widget.chat.type == ChatItemType.group) {
      return '${widget.chat.memberCount} 位成员';
    }
    if (widget.chat.type == ChatItemType.channel) {
      return '${widget.chat.memberCount} 位订阅者';
    }
    return '最近上线于 ${widget.chat.time}';
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';

    return '${lastSeen.hour.toString().padLeft(2, '0')}:${lastSeen.minute.toString().padLeft(2, '0')}';
  }
}

/// 预览消息气泡 - 精致版（支持用户设置的气泡颜色和动图）
class _PreviewBubble extends ConsumerWidget {
  final Map<String, dynamic> message;
  final bool isDark;
  final bool isPrivate;
  final String currentUserId;

  const _PreviewBubble({
    required this.message,
    required this.isDark,
    required this.isPrivate,
    required this.currentUserId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = message['content'] as Map<String, dynamic>? ?? {};
    final text = content['text'] as String? ?? '';
    final msgType = message['type'] as int? ?? 1;
    final senderName = message['sender_name'] as String?;
    final senderId = message['sender_id'] as String? ?? '';
    final createdAt = message['created_at'] as String?;
    final isMine = senderId == currentUserId;

    // 获取用户设置的气泡颜色
    final bubbleColors = ref.watch(bubbleColorProvider);
    final outgoingColor = bubbleColors.outgoing;
    final incomingColor = bubbleColors.incoming;

    // 计算文字颜色
    final outgoingTextColor = _getTextColorForBg(outgoingColor);
    final incomingTextColor = _getTextColorForBg(incomingColor);

    String timeStr = '';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt).toLocal();
        timeStr =
            '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    // 检查是否是 Lottie 表情
    final isLottieEmoji =
        msgType == 8 || (text.isNotEmpty && _isLottieEmoji(text));

    // Lottie 表情单独渲染
    if (isLottieEmoji) {
      final emojiName = content['emoji_name'] as String? ?? text;
      return _buildLottieEmoji(context, emojiName, isMine, timeStr);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine && !isPrivate) ...[
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(right: 6, bottom: 2),
              decoration: BoxDecoration(
                color: _getSenderColor(senderName ?? ''),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  (senderName ?? '?').isNotEmpty
                      ? (senderName ?? '?')[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],

          // 消息气泡
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.55,
            ),
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 5),
            decoration: BoxDecoration(
              color: isMine ? outgoingColor : incomingColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!isPrivate && !isMine && senderName != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      senderName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _getSenderColor(senderName),
                      ),
                    ),
                  ),
                Text(
                  text.isEmpty ? '[媒体消息]' : text,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.25,
                    color: isMine ? outgoingTextColor : incomingTextColor,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr,
                      style: TextStyle(
                        fontSize: 10,
                        color: (isMine ? outgoingTextColor : incomingTextColor)
                            .withOpacity(0.5),
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 3),
                      Icon(
                        Icons.done_all,
                        size: 13,
                        color: outgoingTextColor.withOpacity(0.6),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建 Lottie 表情
  Widget _buildLottieEmoji(
    BuildContext context,
    String emojiName,
    bool isMine,
    String timeStr,
  ) {
    final lottieFile = _getLottieFile(emojiName);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 80,
                height: 80,
                child: lottieFile != null
                    ? Lottie.asset(
                        lottieFile,
                        fit: BoxFit.contain,
                        repeat: true,
                      )
                    : Text(emojiName, style: const TextStyle(fontSize: 48)),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: 10,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 3),
                    Icon(
                      Icons.done_all,
                      size: 13,
                      color: isDark ? Colors.white54 : AppColors.primary,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 检查是否是 Lottie 表情
  bool _isLottieEmoji(String text) {
    final lottieEmojis = [
      '👋',
      '😀',
      '😍',
      '🎉',
      '👍',
      '❤️',
      '🔥',
      '😂',
      '🤔',
      '😢',
      '🙏',
      '💪',
    ];
    return lottieEmojis.contains(text.trim());
  }

  /// 获取 Lottie 文件路径
  String? _getLottieFile(String emoji) {
    final emojiMap = {
      '👋': 'assets/emoji/lottie/waving_hand.json',
      '😀': 'assets/emoji/lottie/grinning_face.json',
      '😍': 'assets/emoji/lottie/heart_eyes.json',
      '🎉': 'assets/emoji/lottie/party.json',
      '👍': 'assets/emoji/lottie/thumbs_up.json',
      '❤️': 'assets/emoji/lottie/heart.json',
      '🔥': 'assets/emoji/lottie/fire.json',
      '😂': 'assets/emoji/lottie/joy.json',
      '🤔': 'assets/emoji/lottie/thinking.json',
      '😢': 'assets/emoji/lottie/sad.json',
      '🙏': 'assets/emoji/lottie/pray.json',
      '💪': 'assets/emoji/lottie/muscle.json',
    };
    return emojiMap[emoji.trim()];
  }

  Color _getTextColorForBg(Color bgColor) {
    final luminance = bgColor.computeLuminance();
    return luminance > 0.5 ? Colors.black87 : Colors.white;
  }

  Color _getSenderColor(String name) {
    final colors = [
      const Color(0xFFE17076),
      const Color(0xFF7BC862),
      const Color(0xFF65AADD),
      const Color(0xFFEE7AE9),
      const Color(0xFFFAA05A),
      const Color(0xFF6EC9CB),
      const Color(0xFFE9B44C),
      const Color(0xFF9B59B6),
    ];
    return colors[name.hashCode.abs() % colors.length];
  }
}

/// TG 壁纸图案画家
class _TGWallpaperPainter extends CustomPainter {
  final bool isDark;

  _TGWallpaperPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = (isDark ? Colors.white : Colors.white).withOpacity(
        isDark ? 0.04 : 0.25,
      )
      ..style = PaintingStyle.fill;

    // 绘制更多样的图案
    final positions = <Offset>[];
    final rng = [0.12, 0.28, 0.42, 0.58, 0.72, 0.88];

    for (var i = 0; i < 6; i++) {
      for (var j = 0; j < 8; j++) {
        final x = size.width * rng[(i + j) % rng.length];
        final y = size.height * rng[(i * 2 + j) % rng.length];
        positions.add(Offset(x, y));
      }
    }

    for (var i = 0; i < positions.length; i++) {
      final pos = positions[i];
      final radius = 4.0 + (i % 6) * 2.5;

      // 绘制不同形状
      if (i % 4 == 0) {
        // 圆形
        canvas.drawCircle(pos, radius, paint);
      } else if (i % 4 == 1) {
        // 小圆点
        canvas.drawCircle(pos, radius * 0.5, paint);
      } else if (i % 4 == 2) {
        // 空心圆
        paint.style = PaintingStyle.stroke;
        paint.strokeWidth = 1.5;
        canvas.drawCircle(pos, radius, paint);
        paint.style = PaintingStyle.fill;
      } else {
        // 小方块
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: pos,
              width: radius * 1.5,
              height: radius * 1.5,
            ),
            Radius.circular(radius * 0.3),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// TG 菜单项 - 精确复刻 TG 风格
class _TGMenuItem extends StatefulWidget {
  final IconData icon;
  final String title;
  final bool isDark;
  final bool isDestructive;
  final VoidCallback onTap;

  const _TGMenuItem({
    required this.icon,
    required this.title,
    required this.isDark,
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  State<_TGMenuItem> createState() => _TGMenuItemState();
}

class _TGMenuItemState extends State<_TGMenuItem> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDestructive
        ? AppColors.error
        : (widget.isDark ? Colors.white : Colors.black);
    final iconColor = widget.isDestructive
        ? AppColors.error
        : (widget.isDark ? Colors.white70 : Colors.black54);

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) => setState(() => _isPressed = false),
      onTapCancel: () => setState(() => _isPressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: _isPressed
            ? (widget.isDark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.05))
            : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w400,
                  color: textColor,
                ),
              ),
            ),
            Icon(widget.icon, size: 22, color: iconColor),
          ],
        ),
      ),
    );
  }
}

/// TG 菜单选项（旧版，兼容保留）
class _TGMenuOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isDark;
  final bool isDestructive;
  final VoidCallback onTap;

  const _TGMenuOption({
    required this.icon,
    required this.title,
    required this.isDark,
    this.isDestructive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive
        ? AppColors.error
        : (isDark ? Colors.white : Colors.black);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          GlobalHaptics.selection();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(fontSize: 17, color: color),
                ),
              ),
              Icon(icon, size: 22, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

/// TG 菜单分隔线
class _TGMenuDivider extends StatelessWidget {
  final bool isDark;

  const _TGMenuDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.5,
      color: isDark
          ? Colors.white.withOpacity(0.1)
          : Colors.black.withOpacity(0.08),
    );
  }
}

// ==================== 文件夹 Tab ====================

class _FolderTabs extends ConsumerWidget {
  final List<ChatFolder> folders;
  final int selectedIndex;
  final ChatListState chats;
  final Function(int) onSelect;

  const _FolderTabs({
    required this.folders,
    required this.selectedIndex,
    required this.chats,
    required this.onSelect,
  });

  String _getFolderName(ChatFolder folder, AppLocalizations l10n) {
    // 翻译默认分组名称
    switch (folder.id) {
      case 'all':
        return l10n.get('all') ?? '全部';
      case 'contacts':
        return l10n.tabContacts;
      case 'groups':
        return l10n.get('groups') ?? '群组';
      case 'channels':
        return l10n.get('channels') ?? '频道';
      default:
        return folder.name;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));

    return SizedBox(
      height: 48,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: folders.length,
        itemBuilder: (context, index) {
          final folder = folders[index];
          final isSelected = selectedIndex == index;
          final unreadCount =
              ref.read(folderProvider.notifier).getUnreadCount(folder, chats);

          return GestureDetector(
            onTap: () => onSelect(index),
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      // 选中渐变蓝色，未选中毛玻璃
                      gradient: isSelected
                          ? LinearGradient(
                              colors: [
                                AppColors.primary,
                                AppColors.primaryLight,
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: isSelected
                          ? null
                          : (isDark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.white.withOpacity(0.9)),
                      borderRadius: BorderRadius.circular(20),
                      border: !isSelected && isDark
                          ? Border.all(
                              color: Colors.white.withOpacity(0.08),
                              width: 0.5,
                            )
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: isSelected
                              ? AppColors.primary.withOpacity(0.3)
                              : (isDark
                                  ? Colors.black.withOpacity(0.2)
                                  : Colors.black.withOpacity(0.05)),
                          blurRadius: isSelected ? 12 : 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _getFolderName(folder, l10n),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : (isDark ? Colors.white : Colors.black87),
                          ),
                        ),
                        if (unreadCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.white.withOpacity(0.25)
                                  : (isDark
                                      ? AppColors.primary.withOpacity(0.3)
                                      : AppColors.primary.withOpacity(0.1)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : unreadCount.toString(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==================== 选项组件 ====================

class _CreateOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CreateOption({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 13, color: AppColors.lightTextSecondary),
      ),
      onTap: onTap,
    );
  }
}

// ==================== 新建私聊 ====================

class _NewChatSheet extends ConsumerStatefulWidget {
  const _NewChatSheet();

  @override
  ConsumerState<_NewChatSheet> createState() => _NewChatSheetState();
}

class _NewChatSheetState extends ConsumerState<_NewChatSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final contacts = ref.watch(contactListProvider);

    // 过滤联系人
    final filteredContacts = _searchQuery.isEmpty
        ? contacts
        : contacts
            .where(
              (c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase()),
            )
            .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // 顶部栏
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const Expanded(
                    child: Text(
                      '新建私聊',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            // 搜索框
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkInputBackground
                      : AppColors.lightInputBackground,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: _searchController,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    hintText: '搜索联系人',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 联系人列表
            Expanded(
              child: filteredContacts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.person_search,
                            size: 64,
                            color: AppColors.lightTextTertiary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '未找到联系人',
                            style: TextStyle(
                              color: AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: filteredContacts.length,
                      itemBuilder: (context, index) {
                        final contact = filteredContacts[index];
                        return ListTile(
                          leading: AvatarWidget(
                            avatar: contact.avatar,
                            name: contact.name,
                            userId: contact.id,
                            size: 44,
                            premiumType: contact.premiumType,
                          ),
                          title: ColoredNameWidget(
                            name: contact.name,
                            nicknameColor: contact.nicknameColor,
                            premiumType: contact.premiumType,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            defaultColor: Colors.black87,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            contact.isOnline ? '在线' : '最近在线',
                            style: TextStyle(
                              fontSize: 13,
                              color: contact.isOnline
                                  ? AppColors.online
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                          onTap: () => _startChat(contact),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _startChat(ContactItem contact) async {
    Navigator.pop(context);

    // 从服务器创建或获取私聊
    final chat =
        await ref.read(chatListProvider.notifier).createPrivateChatFromServer(
              targetUserId: contact.id,
              targetUserName: contact.name,
              avatar: contact.avatar,
            );

    if (!mounted) return;

    if (chat != null) {
      // 跳转到聊天页面
      context.push(
        '/chat/${chat.id}?name=${Uri.encodeComponent(chat.name)}&type=private${chat.avatar != null ? '&avatar=${Uri.encodeComponent(chat.avatar!)}' : ''}',
      );
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('打开聊天失败，请重试')));
    }
  }
}

/// 编辑模式操作按钮
class _EditActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final bool isDestructive;
  final VoidCallback? onTap;

  const _EditActionButton({
    required this.icon,
    required this.label,
    required this.enabled,
    this.isDestructive = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = !enabled
        ? (isDark ? Colors.white24 : Colors.black26)
        : isDestructive
            ? AppColors.error
            : AppColors.primary;

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: enabled
              ? (isDestructive
                  ? AppColors.error.withOpacity(0.1)
                  : AppColors.primary.withOpacity(0.1))
              : (isDark
                  ? Colors.white.withOpacity(0.05)
                  : Colors.black.withOpacity(0.03)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
