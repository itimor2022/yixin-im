// 文件用途：实现 ChatPage 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 ChatPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:universal_io/io.dart';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import '../../../shared/widgets/web_safe_lottie.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/media_cache_manager.dart';
import '../../../core/utils/floating_nav_layout.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/performance_trace_service.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../core/services/time_zone_refresh_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/animated_gif_image.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/sticker_image.dart';
import '../../../shared/widgets/shimmer_loading.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../../shared/widgets/fancy_refresh_indicator.dart';
import '../widgets/chat_list_item.dart';
import '../widgets/create_sheets.dart';
import '../providers/chat_provider.dart';
import '../providers/folder_provider.dart';
import '../services/emoji_store_service.dart';
import '../utils/call_preview_formatter.dart';
import '../../contacts/providers/contact_provider.dart';
import '../../contacts/pages/friend_requests_page.dart';
import '../../settings/pages/chat_settings_page.dart';
import '../../home/pages/home_desktop_page.dart';
import 'chat_detail_page.dart' show ChatType;

String _chatPageText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 关键声明：chat page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class ChatPage extends ConsumerStatefulWidget {
  /// 是否作为桌面端侧边栏使用
  final bool isDesktopSidebar;

  const ChatPage({super.key, this.isDesktopSidebar = false});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageTitle extends ConsumerWidget {
  final bool isDark;

  const _ChatPageTitle({required this.isDark});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final isLoading = ref.watch(chatListProvider.select((s) => s.isLoading));
    final isSilentLoading = ref.watch(
      chatListProvider.select((s) => s.isSilentLoading),
    );

    if (isLoading || isSilentLoading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.textSecondaryFor(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.refreshing,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondaryFor(context),
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
        color: AppColors.textPrimaryFor(context),
      ),
    );
  }
}

class _MaybeGlassBlur extends StatelessWidget {
  final double sigma;
  final Widget child;

  const _MaybeGlassBlur({required this.sigma, required this.child});

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return child;
    }
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
      child: child,
    );
  }
}

class _ChatPageState extends ConsumerState<ChatPage>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  final Set<String> _selectedChatIds = {};

  @override
  bool get wantKeepAlive => true;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    // 监听应用生命周期
    WidgetsBinding.instance.addObserver(this);

    // 初始化时从服务器加载数据（仅在已登录时）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      PerformanceTraceService.mark('chat_page.first_post_frame');
      final authState = ref.read(authServiceProvider);
      if (authState.status == AuthStatus.authenticated) {
        PerformanceTraceService.mark('chat_page.initialize_chat_list');
        // 优先初始化聊天列表（用户首先看到的内容）
        // initialize() 内部会先读 Isar 缓存再请求服务器
        ref.read(chatListProvider.notifier).initialize();

        // 延迟初始化联系人，减少启动时的请求压力
        Future.delayed(const Duration(milliseconds: 3000), () {
          if (!mounted) return;
          ref.read(contactListProvider.notifier).initialize();
        });

        // 进一步延迟同步官方联系人，避免启动时请求过多
        Future.delayed(const Duration(milliseconds: 6500), () async {
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
      ref.read(pendingFriendRequestCountProvider.notifier).refresh();
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
                AppColors.textSecondaryFor(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.refreshing,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondaryFor(context),
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
                AppColors.textSecondaryFor(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            l10n.refreshing,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondaryFor(context),
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
        color: AppColors.textPrimaryFor(context),
      ),
    );
  }

  Widget _buildHeaderPill({
    required bool isDark,
    required Widget child,
    required VoidCallback onTap,
    double? width,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 16),
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: width,
        height: 38,
        padding: padding,
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkControlBackgroundStrong
              : const Color(0xFFF1F1F2),
          borderRadius: BorderRadius.circular(19),
          border: isDark
              ? Border.all(color: AppColors.darkDivider.withOpacity(0.85))
              : null,
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  Widget _buildHeaderIconAction({
    required bool isDark,
    required VoidCallback onTap,
    IconData? icon,
    Widget? child,
  }) {
    assert(icon != null || child != null);
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: child ??
              Icon(
                icon,
                size: 23,
                color: isDark
                    ? AppColors.primaryFor(context)
                    : const Color(0xFF1D1D1F),
              ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    ref.watch(timeZoneRefreshProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = ref.watch(chatEditModeProvider);
    final l10n = AppLocalizations(ref.watch(languageProvider));

    // 使用 select 只监听需要的字段，避免不必要的重建
    final pinnedChats = ref.watch(
      chatListProvider.select((s) => s.pinnedChats),
    );
    final regularChats = ref.watch(
      chatListProvider.select((s) => s.regularChats),
    );
    final chatListIsLoading = ref.watch(
      chatListProvider.select((s) => s.isLoading),
    );
    final chatListIsSilentLoading = ref.watch(
      chatListProvider.select((s) => s.isSilentLoading),
    );
    final chatListError = ref.watch(chatListProvider.select((s) => s.error));
    final chatListIsInitialized = ref.watch(
      chatListProvider.select((s) => s.isInitialized),
    );
    final pendingFriendRequestCount =
        ref.watch(pendingFriendRequestCountProvider);
    final chats = ChatListState(
      pinnedChats: pinnedChats,
      regularChats: regularChats,
      isLoading: chatListIsLoading,
      isSilentLoading: chatListIsSilentLoading,
      error: chatListError,
      isInitialized: chatListIsInitialized,
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

    final floatingBottomSpace = FloatingNavLayout.isEnabledForContext(context)
        ? FloatingNavLayout.reservedSpace(context, extra: 12)
        : 20.0;

    final filteredChats = chats;

    // 预先计算聊天列表，避免在 build 中重复调用
    final allChats = _getChatList(filteredChats);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
        body: FancyRefreshIndicator(
          topOffset: MediaQuery.of(context).padding.top + 52,
          onRefresh: () async {
            await Future.wait([
              ref.read(chatListProvider.notifier).refresh(),
              ref.read(pendingFriendRequestCountProvider.notifier).refresh(),
            ]);
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            cacheExtent: 900,
            slivers: [
              // 顶部标题栏
              SliverAppBar(
                floating: false,
                snap: false,
                pinned: true,
                toolbarHeight: 64,
                backgroundColor:
                    isDark ? AppColors.darkBackground : Colors.white,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                flexibleSpace: Container(
                  color: isDark ? AppColors.darkBackground : Colors.white,
                ),
                leadingWidth: widget.isDesktopSidebar ? 16 : 92,
                leading: widget.isDesktopSidebar
                    ? const SizedBox(width: 16) // 桌面端不显示编辑按钮
                    : Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Center(
                          child: _buildHeaderPill(
                            isDark: isDark,
                            onTap: () {
                              GlobalHaptics.selection();
                              if (isEditing) {
                                ref.read(chatEditModeProvider.notifier).state =
                                    false;
                                setState(() => _selectedChatIds.clear());
                              } else {
                                ref.read(chatEditModeProvider.notifier).state =
                                    true;
                                setState(() => _selectedChatIds.clear());
                              }
                            },
                            child: Text(
                              isEditing
                                  ? _chatPageText(
                                      context,
                                      zhCN: '完成',
                                      zhTW: '完成',
                                      en: 'Done',
                                    )
                                  : _chatPageText(
                                      context,
                                      zhCN: '编辑',
                                      zhTW: '編輯',
                                      en: 'Edit',
                                    ),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: isDark
                                    ? AppColors.primaryFor(context)
                                    : const Color(0xFF1D1D1F),
                              ),
                            ),
                          ),
                        ),
                      ),
                title: isEditing
                    ? Text(
                        _selectedChatIds.isEmpty
                            ? _chatPageText(
                                context,
                                zhCN: '选择聊天',
                                zhTW: '選擇聊天',
                                en: 'Select Chats',
                              )
                            : '${l10n.selectedCount} ${_selectedChatIds.length}',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryFor(context),
                        ),
                      )
                    : _ChatPageTitle(isDark: isDark),
                centerTitle: true,
                actions: [
                  if (!isEditing) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: _buildHeaderPill(
                        isDark: isDark,
                        width: 46,
                        padding: EdgeInsets.zero,
                        onTap: () {},
                        child: Row(
                          children: [
                            _buildHeaderIconAction(
                              isDark: isDark,
                              icon: Icons.add_circle_outline_rounded,
                              onTap: () {
                                GlobalHaptics.selection();
                                _showCreateOptions(context);
                              },
                            ),
                          ],
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
                            color: AppColors.primaryFor(context),
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
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
                      height: 48,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkInputBackground
                            : const Color(0xFFF1F1F2),
                        borderRadius: BorderRadius.circular(10),
                        border: isDark
                            ? Border.all(color: AppColors.darkDivider)
                            : null,
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : const Color(0xFF9A9A9D),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              _chatPageText(
                                context,
                                zhCN: '搜索',
                                zhTW: '搜尋',
                                en: 'Search',
                              ),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w400,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : const Color(0xFF9A9A9D),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              if (!isEditing && pendingFriendRequestCount > 0)
                SliverToBoxAdapter(
                  child: _buildFriendRequestNotice(
                    isDark: isDark,
                    count: pendingFriendRequestCount,
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
              else if (_normalizedChatListError(chats) != null &&
                  allChats.isEmpty)
                SliverFillRemaining(
                  child: _buildChatListErrorState(
                    l10n,
                    _normalizedChatListError(chats)!,
                  ),
                )
              else if (allChats.isEmpty && pendingFriendRequestCount == 0)
                SliverFillRemaining(child: _buildEmptyState(l10n))
              else if (allChats.isNotEmpty) ...[
                if (_normalizedChatListError(chats) != null)
                  SliverToBoxAdapter(
                    child: _buildChatListErrorBanner(
                      _normalizedChatListError(chats)!,
                      isDark,
                    ),
                  ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final chat = allChats[index];
                        final isSelected = _selectedChatIds.contains(chat.id);

                        if (isEditing) {
                          // 编辑模式 - 显示复选框
                          return RepaintBoundary(
                            key: ValueKey(chat.id),
                            child: Consumer(
                              builder: (context, ref, _) {
                                final typingText = ref.watch(
                                  chatListProvider.select(
                                    (s) => s.typingByChat[chat.id],
                                  ),
                                );
                                return _buildEditableChatItem(
                                  chat,
                                  isSelected,
                                  isDark,
                                  typingText: typingText,
                                );
                              },
                            ),
                          );
                        }

                        // 判断是否是官方用户/群组/频道
                        final isOfficial = chat.type == ChatItemType.private
                            ? officialUsers.contains(chat.targetUserUuid)
                            : officialChats.contains(chat.id);

                        // 桌面端：检查是否选中（用于高亮当前打开的聊天）
                        // RepaintBoundary + key 隔离每个列表项的重绘，优化滚动性能
                        return RepaintBoundary(
                          key: ValueKey(chat.id),
                          child: Consumer(
                            builder: (context, ref, _) {
                              final typingText = ref.watch(
                                chatListProvider.select(
                                  (s) => s.typingByChat[chat.id],
                                ),
                              );
                              final isChatActive = widget.isDesktopSidebar
                                  ? ref.watch(selectedChatIdProvider) == chat.id
                                  : false;
                              return ChatListItem(
                                chat: chat,
                                typingText: typingText,
                                isOfficial: isOfficial,
                                isSelected: isChatActive,
                                isDesktop: widget.isDesktopSidebar,
                                showPendingApprovalDot:
                                    chat.hasPendingJoinRequests,
                                onTap: () => _openChat(context, chat),
                                onLongPress: widget.isDesktopSidebar
                                    ? null
                                    : () =>
                                        _showChatPreview(context, ref, chat),
                                onSwipeAction: (action) => _handleSwipeAction(
                                  context,
                                  ref,
                                  chat,
                                  action,
                                ),
                              );
                            },
                          ),
                        );
                      },
                      childCount: allChats.length,
                      findChildIndexCallback: (key) {
                        final value =
                            key is ValueKey<String> ? key.value : null;
                        if (value == null) return null;
                        final index =
                            allChats.indexWhere((chat) => chat.id == value);
                        return index == -1 ? null : index;
                      },
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: false,
                      addSemanticIndexes: true),
                ),
              ],

              // 编辑模式下留出底部操作栏空间
              SliverToBoxAdapter(
                child: SizedBox(
                  height: isEditing ? 100 : floatingBottomSpace,
                ),
              ),
            ],
          ),
        ),
        // 编辑模式底部操作栏
        bottomNavigationBar:
            isEditing ? _buildEditBottomBar(isDark, l10n) : null,
      ),
    );
  }

  Widget _buildFriendRequestNotice({
    required bool isDark,
    required int count,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (_) => const FriendRequestsPage(),
                ),
              )
              .then(
                (_) => ref
                    .read(pendingFriendRequestCountProvider.notifier)
                    .refresh(),
              );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            border: Border(
              bottom: BorderSide(
                color: AppColors.dividerFor(context),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primaryWithOpacity(context, 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.person_add_alt_1_rounded,
                  color: AppColors.primaryFor(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _chatPageText(
                        context,
                        zhCN: '新的好友申请',
                        zhTW: '新的好友申請',
                        en: 'New friend requests',
                      ),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryFor(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _chatPageText(
                        context,
                        zhCN: '有 $count 条申请等待处理',
                        zhTW: '有 $count 則申請等待處理',
                        en: '$count request${count == 1 ? '' : 's'} awaiting review',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondaryFor(context),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                constraints: const BoxConstraints(minWidth: 24),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF453A),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  count > 99 ? '99+' : count.toString(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textTertiaryFor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomSpacing = FloatingNavLayout.isEnabledForContext(context)
        ? FloatingNavLayout.reservedSpace(context, extra: 8)
        : 8.0;
    // 保存外部 context 用于导航（底部弹窗 pop 后内部 context 会失效）
    final outerContext = context;

    if (FloatingNavLayout.isEnabledForContext(context)) {
      ref.read(floatingNavHiddenProvider.notifier).state = true;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final mediaQuery = MediaQuery.of(sheetContext);
        final maxHeight = mediaQuery.size.height - mediaQuery.padding.top - 12;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkDivider
                            : AppColors.lightDivider,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _CreateOption(
                      icon: Icons.search,
                      iconColor: AppColors.primaryFor(outerContext),
                      title: _chatPageText(
                        outerContext,
                        zhCN: '搜索用户',
                        zhTW: '搜尋用戶',
                        en: 'Search Users',
                      ),
                      subtitle: _chatPageText(
                        outerContext,
                        zhCN: '搜索用户开始聊天',
                        zhTW: '搜尋用戶開始聊天',
                        en: 'Find a user to start chatting',
                      ),
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
                      title: _chatPageText(
                        outerContext,
                        zhCN: '新建群组',
                        zhTW: '新建群組',
                        en: 'New Group',
                      ),
                      subtitle: _chatPageText(
                        outerContext,
                        zhCN: '创建一个群聊',
                        zhTW: '建立一個群聊',
                        en: 'Create a group chat',
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        Future<void>.delayed(const Duration(milliseconds: 80),
                            () {
                          if (!mounted || !outerContext.mounted) return;
                          _showCreateGroup(outerContext);
                        });
                      },
                    ),
                    _CreateOption(
                      icon: Icons.campaign_outlined,
                      iconColor: const Color(0xFFFF9800),
                      title: _chatPageText(
                        outerContext,
                        zhCN: '新建频道',
                        zhTW: '新建頻道',
                        en: 'New Channel',
                      ),
                      subtitle: _chatPageText(
                        outerContext,
                        zhCN: '创建一个频道发布消息',
                        zhTW: '建立一個頻道發佈消息',
                        en: 'Create a channel to publish messages',
                      ),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        Future<void>.delayed(const Duration(milliseconds: 80),
                            () {
                          if (!mounted || !outerContext.mounted) return;
                          _showCreateChannel(outerContext);
                        });
                      },
                    ),
                    _CreateOption(
                      icon: Icons.qr_code_scanner,
                      iconColor: const Color(0xFF9C27B0),
                      title: _chatPageText(
                        outerContext,
                        zhCN: '扫描二维码',
                        zhTW: '掃描二維碼',
                        en: 'Scan QR Code',
                      ),
                      subtitle: _chatPageText(
                        outerContext,
                        zhCN: '扫码添加好友或群组',
                        zhTW: '掃碼添加好友或群組',
                        en: 'Scan to add a friend or join a group',
                      ),
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
          ),
        );
      },
    ).whenComplete(() {
      if (!mounted) return;
      ref.read(floatingNavHiddenProvider.notifier).state = false;
    });
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
  String? _normalizedChatListError(ChatListState chats) {
    final error = chats.error?.trim();
    if (error == null || error.isEmpty) {
      return null;
    }
    return error;
  }

  Widget _buildChatListErrorBanner(String error, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(isDark ? 0.16 : 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.error.withOpacity(isDark ? 0.28 : 0.18),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              color: AppColors.error,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                error,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isDark
                      ? AppColors.textSecondaryFor(context)
                      : const Color(0xFF8A1F11),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ),
            TextButton(
              onPressed: () => ref.read(chatListProvider.notifier).refresh(),
              child: Text(
                _chatPageText(
                  context,
                  zhCN: '重试',
                  zhTW: '重試',
                  en: 'Retry',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatListErrorState(AppLocalizations l10n, String error) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 64,
              color: AppColors.textTertiaryFor(context),
            ),
            const SizedBox(height: 16),
            Text(
              _chatPageText(
                context,
                zhCN: '会话加载失败',
                zhTW: '會話載入失敗',
                en: 'Failed to load chats',
              ),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryFor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: AppColors.textSecondaryFor(context),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => ref.read(chatListProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }

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
                color: isSelected
                    ? AppColors.primaryFor(context)
                    : Colors.transparent,
                border: Border.all(
                  color: isSelected
                      ? AppColors.primaryFor(context)
                      : AppColors.textTertiaryFor(context),
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
            // 头像
            AvatarWidget(
              avatar: chat.avatar,
              name: chat.name,
              size: 52,
              borderRadius: 12,
            ),
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
                                defaultColor: AppColors.textPrimaryFor(context),
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
                          color: AppColors.textTertiaryFor(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  _buildLastMessagePreview(chat, typingText, isDark),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastMessagePreview(
    ChatItem chat,
    String? typingText,
    bool isDark,
  ) {
    final isTyping = typingText != null && typingText.isNotEmpty;
    final hasLastMessage = chat.lastMessage?.isNotEmpty == true;
    final text = isTyping
        ? typingText!
        : (hasLastMessage
            ? _chatPreviewText(chat)
            : _chatPageText(
                context,
                zhCN: '快来发送第一条消息吧～',
                zhTW: '快來傳送第一條訊息吧～',
                en: 'Send the first message',
              ));
    final style = TextStyle(
      fontSize: 15,
      color: isTyping
          ? Colors.blue
          : (hasLastMessage
              ? (AppColors.textSecondaryFor(context))
              : (AppColors.textTertiaryFor(context))),
      fontStyle: isTyping
          ? FontStyle.italic
          : (hasLastMessage ? FontStyle.normal : FontStyle.italic),
    );
    final thumbnailUrl = isTyping ? null : _lastMessageThumbnailUrl(chat);

    if (thumbnailUrl == null) {
      return Text(
        text,
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
    }

    return SizedBox(
      height: 24,
      child: Row(
        children: [
          _buildLastMessageThumbnail(
            thumbnailUrl,
            chat.lastMessageType,
            isDark,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _chatPreviewText(ChatItem chat) {
    if (chat.lastMessageType == MessageContentType.call) {
      return formatChatCallPreview(
        text: chat.lastMessage,
        language: AppLocalizations.of(context).language,
      ).summary;
    }
    final text = chat.lastMessage ?? '';
    if (text.startsWith(EmojiStoreService.builtInStickerSendPrefix)) {
      return _chatPageText(
        context,
        zhCN: '[贴纸]',
        zhTW: '[貼紙]',
        en: '[Sticker]',
      );
    }
    return text;
  }

  String? _lastMessageThumbnailUrl(ChatItem chat) {
    final isMedia = chat.lastMessageType == MessageContentType.photo ||
        chat.lastMessageType == MessageContentType.video ||
        chat.lastMessageType == MessageContentType.sticker;
    if (!isMedia) return null;
    final rawUrl = chat.lastMessageMediaUrl?.trim() ?? '';
    if (rawUrl.isEmpty) return null;
    final url = chat.lastMessageType == MessageContentType.sticker
        ? EmojiStoreService.resolveStickerDisplayPath(rawUrl)
        : _isLocalPreviewPath(rawUrl)
            ? rawUrl
            : ChatMediaCacheManager.normalizeUrl(rawUrl);
    return url.isEmpty ? null : url;
  }

  Widget _buildLastMessageThumbnail(
    String url,
    MessageContentType? type,
    bool isDark,
  ) {
    const size = 24.0;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        Icons.image_outlined,
        size: 15,
        color: AppColors.textTertiaryFor(context),
      ),
    );

    Widget image;
    if (type == MessageContentType.sticker) {
      image = StickerImage(
        source: url,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (_, __) => fallback,
      );
    } else if (_isLocalPreviewPath(url)) {
      final file = File(url);
      image = file.existsSync()
          ? Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            )
          : fallback;
    } else if (url.startsWith('http')) {
      image = CachedNetworkImage(
        imageUrl: url,
        cacheManager: ChatMediaCacheManager.instance,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: 96,
        memCacheHeight: 96,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      );
    } else {
      image = fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: image,
    );
  }

  bool _isLocalPreviewPath(String url) {
    return ChatMediaCacheManager.isLocalPath(url) ||
        RegExp(r'^[A-Za-z]:[\\/]').hasMatch(url);
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return _chatPageText(
        context,
        zhCN: '刚刚',
        zhTW: '剛剛',
        en: 'just now',
      );
    }
    if (diff.inHours < 1) {
      return _chatPageText(
        context,
        zhCN: '${diff.inMinutes}分钟前',
        zhTW: '${diff.inMinutes}分鐘前',
        en: '${diff.inMinutes} min ago',
      );
    }
    if (diff.inDays < 1) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) {
      return _chatPageText(
        context,
        zhCN: '${diff.inDays}天前',
        zhTW: '${diff.inDays}天前',
        en: '${diff.inDays} days ago',
      );
    }
    return '${time.month}/${time.day}';
  }

  /// 编辑模式底部操作栏（毛玻璃按钮）
  Widget _buildEditBottomBar(bool isDark, AppLocalizations l10n) {
    final hasSelection = _selectedChatIds.isNotEmpty;
    final chatState = ref.watch(chatListProvider);
    final allChats = _getChatList(chatState);
    final selectedChats =
        allChats.where((chat) => _selectedChatIds.contains(chat.id)).toList();
    final shouldMarkUnread = selectedChats.isNotEmpty &&
        selectedChats.every((chat) => chat.unreadCount == 0);

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
              onTap: hasSelection ? _toggleSelectedReadState : null,
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
                      shouldMarkUnread
                          ? _chatPageText(
                              context,
                              zhCN: '标记未读',
                              zhTW: '標記未讀',
                              en: 'Mark as Unread',
                            )
                          : l10n.markAsRead,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: hasSelection
                            ? AppColors.primaryFor(context)
                            : AppColors.textTertiaryFor(context),
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
                      _chatPageText(
                        context,
                        zhCN: '删除',
                        zhTW: '刪除',
                        en: 'Delete',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: hasSelection
                            ? AppColors.error
                            : AppColors.textTertiaryFor(context),
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

  void _toggleSelectedReadState() {
    GlobalHaptics.medium();
    final notifier = ref.read(chatListProvider.notifier);
    final chats = ref.read(chatListProvider);
    final allChats = _getChatList(chats);

    final selectedChats =
        allChats.where((chat) => _selectedChatIds.contains(chat.id)).toList();
    final shouldMarkUnread = selectedChats.isNotEmpty &&
        selectedChats.every((chat) => chat.unreadCount == 0);

    for (final chatId in _selectedChatIds) {
      final idx = allChats.indexWhere((c) => c.id == chatId);
      if (idx < 0) continue;
      final chat = allChats[idx];
      if ((shouldMarkUnread && chat.unreadCount == 0) ||
          (!shouldMarkUnread && chat.unreadCount > 0)) {
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
                      _chatPageText(
                        context,
                        zhCN: '删除 ${_selectedChatIds.length} 个聊天？',
                        zhTW: '刪除 ${_selectedChatIds.length} 個聊天？',
                        en: 'Delete ${_selectedChatIds.length} chats?',
                      ),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _chatPageText(
                        context,
                        zhCN: '聊天将从列表中移除，但不会删除聊天记录',
                        zhTW: '聊天將從清單中移除，但不會刪除聊天記錄',
                        en: 'These chats will be removed from the list, but the chat history will be kept',
                      ),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textSecondaryFor(context),
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
                                _chatPageText(
                                  context,
                                  zhCN: '取消',
                                  zhTW: '取消',
                                  en: 'Cancel',
                                ),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondaryFor(context),
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
                              child: Text(
                                _chatPageText(
                                  context,
                                  zhCN: '删除',
                                  zhTW: '刪除',
                                  en: 'Delete',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
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
            child: WebSafeLottie.asset(
              'assets/emoji/lottie/hatched_chick.json',
              repeat: true,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noChats,
            style: TextStyle(
                fontSize: 16, color: AppColors.textSecondaryFor(context)),
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
            content: Text(
              _chatPageText(
                context,
                zhCN: '已删除',
                zhTW: '已刪除',
                en: 'Deleted',
              ),
            ),
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
          _chatPageText(
            context,
            zhCN: '删除聊天',
            zhTW: '刪除聊天',
            en: 'Delete Chat',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryFor(context),
          ),
        ),
        content: Text(
          _chatPageText(
            context,
            zhCN: '确定要删除与"${chat.name}"的聊天记录吗？',
            zhTW: '確定要刪除與「${chat.name}」的聊天記錄嗎？',
            en: 'Delete the chat history with "${chat.name}"?',
          ),
          style: TextStyle(
            fontSize: 15,
            color: AppColors.textSecondaryFor(context),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _chatPageText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
              style: TextStyle(color: AppColors.textSecondaryFor(context)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(chatListProvider.notifier).deleteChat(chat.id);
            },
            child: Text(
              _chatPageText(
                context,
                zhCN: '删除',
                zhTW: '刪除',
                en: 'Delete',
              ),
              style: TextStyle(color: AppColors.error),
            ),
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
                color: AppColors.cardFor(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Text(
                      _chatPageText(
                        context,
                        zhCN: '删除与"${chat.name}"的聊天',
                        zhTW: '刪除與「${chat.name}」的聊天',
                        en: 'Delete chat with "${chat.name}"',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textTertiaryFor(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: AppColors.dividerFor(context),
                  ),
                  // 删除列表
                  _DeleteOptionItem(
                    title: _chatPageText(
                      context,
                      zhCN: '从列表中删除',
                      zhTW: '從列表中刪除',
                      en: 'Remove from List',
                    ),
                    subtitle: _chatPageText(
                      context,
                      zhCN: '仅从聊天列表移除，保留聊天记录',
                      zhTW: '僅從聊天列表移除，保留聊天記錄',
                      en: 'Remove it from the chat list only and keep the chat history',
                    ),
                    isDark: isDark,
                    onTap: () {
                      Navigator.pop(context);
                      ref
                          .read(chatListProvider.notifier)
                          .hideChatFromServer(chat.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _chatPageText(
                              context,
                              zhCN: '已从列表中移除',
                              zhTW: '已從列表中移除',
                              en: 'Removed from the list',
                            ),
                          ),
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
                    color: AppColors.dividerFor(context),
                  ),
                  // 删除聊天记录
                  _DeleteOptionItem(
                    title: _chatPageText(
                      context,
                      zhCN: '删除聊天记录',
                      zhTW: '刪除聊天記錄',
                      en: 'Delete Chat History',
                    ),
                    subtitle: _chatPageText(
                      context,
                      zhCN: '清空本地聊天记录，对方的记录不受影响',
                      zhTW: '清空本地聊天記錄，對方的記錄不受影響',
                      en: "Clear your local chat history only. The other person's history is not affected",
                    ),
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
                color: AppColors.cardFor(context),
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
                  _chatPageText(
                    context,
                    zhCN: '取消',
                    zhTW: '取消',
                    en: 'Cancel',
                  ),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: AppColors.linkFor(context),
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
          _chatPageText(
            context,
            zhCN: '确认删除',
            zhTW: '確認刪除',
            en: 'Confirm Delete',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryFor(context),
          ),
        ),
        content: Text(
          _chatPageText(
            context,
            zhCN:
                '确定要删除与"${chat.name}"的所有聊天记录吗？\n\n此操作仅删除您本地的记录，对方手机上的聊天记录不会被删除。',
            zhTW:
                '確定要刪除與「${chat.name}」的所有聊天記錄嗎？\n\n此操作僅刪除你本機的記錄，對方裝置上的聊天記錄不會被刪除。',
            en: 'Delete all chat history with "${chat.name}"?\n\nThis only deletes your local records. The other person\'s chat history will not be deleted.',
          ),
          style: TextStyle(
            fontSize: 15,
            color: AppColors.textSecondaryFor(context),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _chatPageText(
                context,
                zhCN: '取消',
                zhTW: '取消',
                en: 'Cancel',
              ),
              style: TextStyle(color: AppColors.textSecondaryFor(context)),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // 删除聊天记录
              ref.read(chatListProvider.notifier).deleteChat(chat.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _chatPageText(
                      context,
                      zhCN: '聊天记录已删除',
                      zhTW: '聊天記錄已刪除',
                      en: 'Chat history deleted',
                    ),
                  ),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              );
            },
            child: Text(
              _chatPageText(
                context,
                zhCN: '删除',
                zhTW: '刪除',
                en: 'Delete',
              ),
              style: TextStyle(color: AppColors.error),
            ),
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
                    : AppColors.textPrimaryFor(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textTertiaryFor(context),
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
                                                  color: AppColors.primaryFor(
                                                      context),
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
                                                            : AppColors
                                                                .textSecondaryFor(
                                                                    context),
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
                                title: chat.unreadCount > 0
                                    ? _chatPageText(
                                        context,
                                        zhCN: '标记为已读',
                                        zhTW: '標記為已讀',
                                        en: 'Mark as Read',
                                      )
                                    : _chatPageText(
                                        context,
                                        zhCN: '标记为未读',
                                        zhTW: '標記為未讀',
                                        en: 'Mark as Unread',
                                      ),
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
                                title: chat.isPinned
                                    ? _chatPageText(
                                        context,
                                        zhCN: '取消置顶',
                                        zhTW: '取消置頂',
                                        en: 'Unpin',
                                      )
                                    : _chatPageText(
                                        context,
                                        zhCN: '置顶',
                                        zhTW: '置頂',
                                        en: 'Pin',
                                      ),
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
                                title: chat.isMuted
                                    ? _chatPageText(
                                        context,
                                        zhCN: '取消静音',
                                        zhTW: '取消靜音',
                                        en: 'Unmute',
                                      )
                                    : _chatPageText(
                                        context,
                                        zhCN: '静音',
                                        zhTW: '靜音',
                                        en: 'Mute',
                                      ),
                                isDark: isDark,
                                onTap: () async {
                                  await _closeWithAnimation();
                                  widget.onMute();
                                },
                              ),
                              _TGMenuDivider(isDark: isDark),
                              _TGMenuItem(
                                icon: Icons.delete_outline,
                                title: _chatPageText(
                                  context,
                                  zhCN: '删除',
                                  zhTW: '刪除',
                                  en: 'Delete',
                                ),
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
            _chatPageText(
              context,
              zhCN: '暂无消息',
              zhTW: '暫無消息',
              en: 'No messages yet',
            ),
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
      if (_isOnline) {
        return _chatPageText(
          context,
          zhCN: '在线',
          zhTW: '在線',
          en: 'Online',
        );
      }
      if (_lastSeen != null) {
        return _chatPageText(
          context,
          zhCN: '最近上线于 ${_formatLastSeen(_lastSeen!)}',
          zhTW: '最近上線於 ${_formatLastSeen(_lastSeen!)}',
          en: 'Last seen ${_formatLastSeen(_lastSeen!)}',
        );
      }
    }
    if (widget.chat.type == ChatItemType.group) {
      return _chatPageText(
        context,
        zhCN: '${widget.chat.memberCount} 位成员',
        zhTW: '${widget.chat.memberCount} 位成員',
        en: '${widget.chat.memberCount} members',
      );
    }
    if (widget.chat.type == ChatItemType.channel) {
      return _chatPageText(
        context,
        zhCN: '${widget.chat.memberCount} 位订阅者',
        zhTW: '${widget.chat.memberCount} 位訂閱者',
        en: '${widget.chat.memberCount} subscribers',
      );
    }
    return _chatPageText(
      context,
      zhCN: '最近上线于 ${widget.chat.time}',
      zhTW: '最近上線於 ${widget.chat.time}',
      en: 'Last seen ${widget.chat.time}',
    );
  }

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (diff.inMinutes < 1) {
      return _chatPageText(
        context,
        zhCN: '刚刚',
        zhTW: '剛剛',
        en: 'just now',
      );
    }
    if (diff.inMinutes < 60) {
      return _chatPageText(
        context,
        zhCN: '${diff.inMinutes} 分钟前',
        zhTW: '${diff.inMinutes} 分鐘前',
        en: '${diff.inMinutes} min ago',
      );
    }
    if (diff.inHours < 24) {
      return _chatPageText(
        context,
        zhCN: '${diff.inHours} 小时前',
        zhTW: '${diff.inHours} 小時前',
        en: '${diff.inHours} hr ago',
      );
    }
    if (diff.inDays < 7) {
      return _chatPageText(
        context,
        zhCN: '${diff.inDays} 天前',
        zhTW: '${diff.inDays} 天前',
        en: '${diff.inDays} days ago',
      );
    }

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
                  text.isEmpty
                      ? _chatPageText(
                          context,
                          zhCN: '[媒体消息]',
                          zhTW: '[媒體消息]',
                          en: '[Media]',
                        )
                      : text,
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
                    ? WebSafeLottie.asset(
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
                      color: AppColors.textTertiaryFor(context),
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 3),
                    Icon(
                      Icons.done_all,
                      size: 13,
                      color: isDark
                          ? AppColors.textSecondaryFor(context)
                          : AppColors.primaryFor(context),
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
        : AppColors.textPrimaryFor(context);
    final iconColor = widget.isDestructive
        ? AppColors.error
        : AppColors.textSecondaryFor(context);

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

  String _getFolderName(
    BuildContext context,
    ChatFolder folder,
    AppLocalizations l10n,
  ) {
    // 翻译默认分组名称
    switch (folder.id) {
      case 'all':
        return l10n.get('all') ??
            _chatPageText(
              context,
              zhCN: '全部',
              zhTW: '全部',
              en: 'All',
            );
      case 'contacts':
        return l10n.tabContacts;
      case 'groups':
        return l10n.get('groups') ??
            _chatPageText(
              context,
              zhCN: '群组',
              zhTW: '群組',
              en: 'Groups',
            );
      case 'channels':
        return l10n.get('channels') ??
            _chatPageText(
              context,
              zhCN: '频道',
              zhTW: '頻道',
              en: 'Channels',
            );
      default:
        return folder.name;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));

    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 5, 16, 5),
        itemCount: folders.length,
        itemBuilder: (context, index) {
          final folder = folders[index];
          final isSelected = selectedIndex == index;
          final unreadCount =
              ref.read(folderProvider.notifier).getUnreadCount(folder, chats);

          return GestureDetector(
            onTap: () => onSelect(index),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 76),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark
                          ? AppColors.primaryWithOpacity(context, 0.20)
                          : AppColors.primaryWithOpacity(context, 0.10))
                      : AppColors.cardFor(context),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isDark
                        ? (isSelected
                            ? AppColors.primaryWithOpacity(context, 0.30)
                            : AppColors.dividerFor(context))
                        : (isSelected
                            ? AppColors.primaryWithOpacity(context, 0.18)
                            : Colors.black.withOpacity(0.05)),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getFolderName(context, folder, l10n),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected
                            ? AppColors.primaryFor(context)
                            : (isDark
                                ? AppColors.darkTextPrimary
                                : const Color(0xFF1D1D1F)),
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
                          color: isDark
                              ? Colors.white.withOpacity(0.10)
                              : const Color(0xFFE1E3E6),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : unreadCount.toString(),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? AppColors.darkTextPrimary
                                : const Color(0xFF63666A),
                          ),
                        ),
                      ),
                    ],
                  ],
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
        style:
            TextStyle(fontSize: 13, color: AppColors.textSecondaryFor(context)),
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
                  Expanded(
                    child: Text(
                      _chatPageText(
                        context,
                        zhCN: '新建私聊',
                        zhTW: '新增私聊',
                        en: 'New Private Chat',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
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
                    hintText: _chatPageText(
                      context,
                      zhCN: '搜索联系人',
                      zhTW: '搜尋聯絡人',
                      en: 'Search Contacts',
                    ),
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
                            color: AppColors.textTertiaryFor(context),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _chatPageText(
                              context,
                              zhCN: '未找到联系人',
                              zhTW: '找不到聯絡人',
                              en: 'No contacts found',
                            ),
                            style: TextStyle(
                              color: AppColors.textSecondaryFor(context),
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
                          ),
                          title: ColoredNameWidget(
                            name: contact.name,
                            nicknameColor: contact.nicknameColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            defaultColor: AppColors.textPrimaryFor(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            contact.isOnline
                                ? _chatPageText(
                                    context,
                                    zhCN: '在线',
                                    zhTW: '在線',
                                    en: 'Online',
                                  )
                                : _chatPageText(
                                    context,
                                    zhCN: '最近在线',
                                    zhTW: '最近在線',
                                    en: 'Last seen',
                                  ),
                            style: TextStyle(
                              fontSize: 13,
                              color: contact.isOnline
                                  ? AppColors.online
                                  : AppColors.textSecondaryFor(context),
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
      ).showSnackBar(
        SnackBar(
          content: Text(
            _chatPageText(
              context,
              zhCN: '打开聊天失败，请重试',
              zhTW: '打開聊天失敗，請重試',
              en: 'Failed to open chat. Please try again.',
            ),
          ),
        ),
      );
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
        ? AppColors.textTertiaryFor(context)
        : isDestructive
            ? AppColors.error
            : AppColors.primaryFor(context);

    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: enabled
              ? (isDestructive
                  ? AppColors.error.withOpacity(0.1)
                  : AppColors.primaryWithOpacity(context, 0.1))
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
