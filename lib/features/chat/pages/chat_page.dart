import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
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
import '../../../shared/widgets/top_gradient_backdrop.dart';
import '../widgets/chat_list_item.dart';
import '../widgets/create_sheets.dart';
import '../providers/chat_provider.dart';
import '../providers/folder_provider.dart';
import '../../contacts/providers/contact_provider.dart';
import '../../settings/pages/chat_settings_page.dart';
import '../../home/pages/home_desktop_page.dart';
import 'chat_detail_page.dart' show ChatType;

/// ===== 聊天页面 UI Tokens =====
///
/// 主色跟 [AppColors.primary] 保持一致的海洋蓝 (#009CFF)。
/// 单独抽出常量让本文件的按钮/胶囊/徽章配色一目了然。
const Color _kChatPrimary = Color(0xFF1A3A6B);
const Color _kChatDivider = Color(0xFFEDEFF2);
const Color _kChatSubText = Color(0xFF9CA3AF);
const Color _kChatTitleText = Color(0xFF111827);

/// 顶部渐变区结构尺寸（用于把 CustomScrollView 顶部空白对齐到搜索栏底部）：
///   · header 视觉高度 = 10 (top pad) + 44 (content) + 6 (bottom pad) = 60
///   · search 视觉高度 = 2  (top pad) + 42 (content) + 10 (bottom pad) = 54
///   · 渐变尾巴高度   = 80 —— 这段是「浅主色 → 透明」的淡出，叠到第一条
///     列表项之上（≈ 第一条约 72~80px，因此 80px 恰好覆盖到中部再往下），
///     再配合主色 0.22 的中段颜色，视觉上让渐变**明显穿过搜索栏、延伸到
///     第一条列表项的一半**（而不是止步于搜索栏边缘）。
const double _kHeaderContentHeight = 60;
const double _kSearchContentHeight = 54;
const double _kGradientFadeTail = 80;

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
            if (kDebugMode) debugPrint(
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
  ///
  /// [onGradient] 表示标题会放在顶部主色渐变背景上，此时文字/加载圈需为白色。
  Widget _buildTitle(
    bool isDark,
    AppLocalizations l10n, {
    bool onGradient = false,
  }) {
    final isLoading = ref.watch(chatListProvider.select((s) => s.isLoading));
    final isSilentLoading = ref.watch(
      chatListProvider.select((s) => s.isSilentLoading),
    );
    final refreshing = isLoading || isSilentLoading;

    final Color titleColor = onGradient
        ? Colors.white
        : (isDark ? Colors.white : _kChatTitleText);
    final Color spinnerColor = onGradient
        ? Colors.white.withOpacity(0.9)
        : (isDark ? Colors.white70 : _kChatSubText);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          refreshing ? l10n.refreshing : l10n.tabChat,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: titleColor,
          ),
        ),
        if (refreshing) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(spinnerColor),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final isDark = Theme.of(context).brightness == Brightness.dark;
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

    // 顶部分组 tabs 已移除：始终展示全部聊天
    final floatingBottomSpace = FloatingNavLayout.isEnabled
        ? FloatingNavLayout.reservedSpace(context, extra: 12)
        : 20.0;

    final filteredChats = chats;
    final allChats = _getChatList(filteredChats);

    final Color bgColor = isDark ? const Color(0xFF0E1015) : Colors.white;
    final Color cardColor = isDark ? const Color(0xFF1B1D24) : Colors.white;

    // 顶部渐变区的**不透明**部分高度（status bar + header + 搜索栏）。
    // 列表在滚动视图中会预留这么多高度，让第一条聊天项的顶部正好落到
    // 渐变尾巴 (fade tail) 里 —— 这样视觉上"渐变延伸到第一条列表的一半"。
    final double topPad = MediaQuery.of(context).padding.top;
    final double gradientOpaqueHeight = topPad + _kHeaderContentHeight +
        _kSearchContentHeight; // ≈ topPad + 60 + 54

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: bgColor,
        // 用 Stack 让渐变尾巴叠在列表顶部，实现"渐变延伸到第一条项目一半"效果。
        // ─ 底层：可滚动的聊天列表（前面留出 `gradientOpaqueHeight` 空位）
        // ─ 顶层：主色渐变（含 header + 搜索栏 + 一段淡出到透明的尾巴）
        body: Stack(
          children: [
            // ==================== 底层：聊天列表 ====================
            Positioned.fill(
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // 顶部预留位置 = 渐变的不透明部分高度
                  // 渐变的尾巴 (fade tail) 会盖到下面第一条列表项的上半部分
                  SliverToBoxAdapter(
                    child: SizedBox(height: gradientOpaqueHeight),
                  ),
                  if (!chats.isInitialized && chats.isLoading)
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildSkeletonItem(
                          isDark,
                          showDivider: index != 7,
                        ),
                        childCount: 8,
                      ),
                    )
                  else if (allChats.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(l10n),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final chat = allChats[index];
                        final isSelected = _selectedChatIds.contains(chat.id);
                        final isLast = index == allChats.length - 1;

                        if (_isEditing) {
                          return _buildEditableChatItem(
                            chat,
                            isSelected,
                            isDark,
                            typingText: typingByChat[chat.id],
                            showDivider: !isLast,
                          );
                        }

                        final isOfficial = chat.type == ChatItemType.private
                            ? officialUsers.contains(chat.targetUserUuid)
                            : officialChats.contains(chat.id);
                        final isChatActive = widget.isDesktopSidebar
                            ? ref.watch(selectedChatIdProvider) == chat.id
                            : false;

                        return RepaintBoundary(
                          key: ValueKey(chat.id),
                          child: ChatListItem(
                            chat: chat,
                            typingText: typingByChat[chat.id],
                            isOfficial: isOfficial,
                            isSelected: isChatActive,
                            isDesktop: widget.isDesktopSidebar,
                            showPendingApprovalDot:
                                chat.hasPendingJoinRequests,
                            isMember: chat.isMember,
                            badgeText: chat.badgeText,
                            badgeColor: chat.badgeColor,
                            showDivider: !isLast,
                            onTap: () => _openChat(context, chat),
                            onLongPress: widget.isDesktopSidebar
                                ? null
                                : () => _showChatPreview(context, ref, chat),
                            onSwipeAction: (action) => _handleSwipeAction(
                                context, ref, chat, action),
                          ),
                        );
                      }, childCount: allChats.length),
                    ),
                  // 底部留白（编辑模式为底部操作栏预留空间）
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: _isEditing ? 100 : floatingBottomSpace,
                    ),
                  ),
                ],
              ),
            ),

            // ==================== 中层：纯装饰渐变（IgnorePointer） ====================
            //
            // 这一层只负责画渐变（从 `#009fff` → 浅主色 → 透明），
            // **必须**用 IgnorePointer 包起来 —— 它覆盖到第一条列表项之上，
            // 如果不忽略指针事件就会挡住列表项的点击 / 长按 / 左滑。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topPad + _kHeaderContentHeight +
                  _kSearchContentHeight + _kGradientFadeTail,
              child: const IgnorePointer(
                child: TopGradientBackdrop(),
              ),
            ),

            // ==================== 顶层：交互式 header + 搜索栏 ====================
            //
            // 只放**可交互**的控件（header 里的图标按钮 + 搜索栏），
            // 高度到搜索栏结束为止 —— 不覆盖下方渐变尾巴区，也不会挡列表。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle.light,
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAppHeader(
                        isDark: isDark,
                        l10n: l10n,
                        filteredChats: filteredChats,
                      ),
                      _buildSearchField(
                        isDark: isDark,
                        cardColor: cardColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar:
            _isEditing ? _buildEditBottomBar(isDark, l10n) : null,
      ),
    );
  }

  // ==============================================================
  // 顶部主色渐变区（含 status bar + header + 搜索框 + 微渐变尾巴）
  // ==============================================================

  // 顶部渐变背景现在由 [TopGradientBackdrop] 提供（纯装饰、被 IgnorePointer
  // 包裹，绝不会拦截手势）。交互式 header + search 是独立的一层，见 build()。

  /// 顶部标题栏
  ///   - 正常模式：左侧标题「聊天」，右侧两个圆形图标按钮（选择 / 加号）
  ///   - 编辑模式：左「完成」/ 中「已选 N」/ 右「全选」，全部白字
  ///   - 桌面侧边栏：只显示居左标题
  Widget _buildAppHeader({
    required bool isDark,
    required AppLocalizations l10n,
    required ChatListState filteredChats,
  }) {
    if (widget.isDesktopSidebar) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: SizedBox(
          height: 40,
          child: Align(
            alignment: Alignment.centerLeft,
            child: _buildTitle(isDark, l10n, onGradient: true),
          ),
        ),
      );
    }

    if (_isEditing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
        child: SizedBox(
          height: 44,
          child: Row(
            children: [
              SizedBox(
                width: 76,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _CircleActionButton(
                    isDark: isDark,
                    onGradient: true,
                    wide: true,
                    onTap: () {
                      GlobalHaptics.selection();
                      ref.read(chatEditModeProvider.notifier).state = false;
                      setState(() => _selectedChatIds.clear());
                    },
                    child: const Text(
                      '完成',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _selectedChatIds.isEmpty
                        ? '选择聊天'
                        : '${l10n.selectedCount} ${_selectedChatIds.length}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 76,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _CircleActionButton(
                    isDark: isDark,
                    onGradient: true,
                    wide: true,
                    onTap: () {
                      GlobalHaptics.selection();
                      final all = _getChatList(filteredChats);
                      setState(() {
                        if (_selectedChatIds.length == all.length) {
                          _selectedChatIds.clear();
                        } else {
                          _selectedChatIds
                            ..clear()
                            ..addAll(all.map((c) => c.id));
                        }
                      });
                    },
                    child: Builder(builder: (_) {
                      final all = _getChatList(filteredChats);
                      final allSelected = all.isNotEmpty &&
                          _selectedChatIds.length == all.length;
                      return Text(
                        allSelected ? l10n.deselectAll : l10n.selectAll,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ================== 正常模式：左标题 + 右两图标 ==================
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 14, 6),
      child: SizedBox(
        height: 44,
        child: Row(
          children: [
            // 左侧标题
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _buildTitle(isDark, l10n, onGradient: true),
              ),
            ),
            // 右侧两个圆形图标按钮
            _CircleActionButton(
              isDark: isDark,
              onGradient: true,
              onTap: () {
                GlobalHaptics.selection();
                ref.read(chatEditModeProvider.notifier).state = true;
                setState(() => _selectedChatIds.clear());
              },
              child: const Icon(
                Icons.check_circle_outline_rounded,
                size: 20,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            Builder(
              builder: (btnCtx) => _CircleActionButton(
                isDark: isDark,
                onGradient: true,
                onTap: () => _showCreateOptions(btnCtx),
                child: const Icon(
                  Icons.add_rounded,
                  size: 22,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 搜索框（圆角胶囊、扁平浅底 + 主色搜索图标）
  Widget _buildSearchField({
    required bool isDark,
    required Color cardColor,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
      child: GestureDetector(
        onTap: () {
          if (widget.isDesktopSidebar) {
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
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(14),
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.035),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Icon(
                Icons.search_rounded,
                size: 20,
                color: isDark ? Colors.white54 : const Color(0xFF9CA3AF),
              ),
              const SizedBox(width: 8),
              Text(
                '搜索',
                style: TextStyle(
                  fontSize: 14.5,
                  color: isDark ? Colors.white54 : const Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 微信风格：点击右上角"+"在按钮下方弹出小卡片菜单。
  ///
  /// [buttonContext] 需要传入 "+" 按钮所在的局部 context（用 Builder 包一层），
  /// 这样我们才能拿到按钮的全局位置，把菜单精准定位到按钮右下。
  void _showCreateOptions(BuildContext buttonContext) {
    final isDark = Theme.of(buttonContext).brightness == Brightness.dark;
    // 保存外部 context 用于弹窗关闭后的导航
    final outerContext = context;

    // 计算按钮在 overlay 中的位置
    final RenderBox? buttonBox =
        buttonContext.findRenderObject() as RenderBox?;
    final RenderBox? overlayBox = Overlay.of(buttonContext)
        .context
        .findRenderObject() as RenderBox?;
    if (buttonBox == null || overlayBox == null) return;

    final Offset topLeft =
        buttonBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    final Offset bottomRight = buttonBox.localToGlobal(
      buttonBox.size.bottomRight(Offset.zero),
      ancestor: overlayBox,
    );

    // 菜单靠右对齐到按钮右边缘，向下偏移 8dp
    const double menuWidth = 196;
    final double left = (bottomRight.dx - menuWidth).clamp(8.0, double.infinity);
    final double top = bottomRight.dy + 8;
    final RelativeRect position = RelativeRect.fromLTRB(
      left,
      top,
      overlayBox.size.width - bottomRight.dx,
      overlayBox.size.height - top,
    );

    // 采用聊天详情页的灰底色 #EDEDED（深色主题下沿用深灰卡片）
    final Color menuBg = isDark
        ? const Color(0xFF1F2937)
        : const Color(0xFFEDEDED);
    final Color itemText =
        isDark ? Colors.white : const Color(0xFF111827);
    final Color itemIcon =
        isDark ? Colors.white : const Color(0xFF111827);
    final Color dividerColor = isDark
        ? Colors.white.withOpacity(0.10)
        : Colors.black.withOpacity(0.06);

    Widget buildRow(IconData icon, String label) {
      return Row(
        children: [
          Icon(icon, size: 24, color: itemIcon),
          const SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(
              color: itemText,
              fontSize: 17,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );
    }

    PopupMenuItem<String> item(String value, IconData icon, String label) {
      return PopupMenuItem<String>(
        value: value,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        height: 52,
        child: buildRow(icon, label),
      );
    }

    // 用一个 0.5px 分割线代替标准 PopupMenuDivider（后者高度较大）
    PopupMenuItem<String> divider() {
      return PopupMenuItem<String>(
        enabled: false,
        padding: EdgeInsets.zero,
        height: 0,
        child: Container(
          height: 0.5,
          color: dividerColor,
          margin: const EdgeInsets.symmetric(horizontal: 12),
        ),
      );
    }

    showMenu<String>(
      context: buttonContext,
      position: position,
      color: menuBg,
      elevation: 10,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      constraints: const BoxConstraints(minWidth: menuWidth, maxWidth: menuWidth),
      items: [
        item('search', Icons.person_search_rounded, '搜索用户'),
        divider(),
        item('group', Icons.group_add_outlined, '新建群组'),
        divider(),
        item('scan', Icons.qr_code_scanner_rounded, '扫描二维码'),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'search':
          if (widget.isDesktopSidebar) {
            ref.read(desktopProfileProvider.notifier).state =
                const DesktopProfileInfo(
              type: DesktopPanelType.searchUsers,
              id: 'search_users',
            );
          } else {
            outerContext.push('/search-users');
          }
          break;
        case 'group':
          _showCreateGroup(outerContext);
          break;
        case 'scan':
          outerContext.push('/scan');
          break;
      }
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

  List<ChatItem> _getChatList(ChatListState chats) {
    // 已移除「频道」功能：从列表中过滤掉所有 channel 类型
    return [
      ...chats.pinnedChats.where((c) => c.type != ChatItemType.channel),
      ...chats.regularChats.where((c) => c.type != ChatItemType.channel),
    ];
  }

  /// 骨架屏加载项（带 shimmer 动画）—— 扁平样式，无分隔线
  Widget _buildSkeletonItem(
    bool isDark, {
    // ignore: unused_element_parameter
    bool showDivider = true,
  }) {
    return const ChatListSkeletonItem();
  }

  /// 编辑模式下的聊天项 —— 扁平样式（去卡片 / 去边框 / 去阴影）
  ///
  /// 仅选中态时给一层非常淡的主色背景色 + 左侧 3px 主色 accent bar。
  Widget _buildEditableChatItem(
    ChatItem chat,
    bool isSelected,
    bool isDark, {
    String? typingText,
    // ignore: unused_element_parameter
    bool showDivider = true,
  }) {
    final Color cardBg = isSelected
        ? (isDark ? const Color(0x1F009CFF) : const Color(0xFFF0F7FF))
        : Colors.transparent;
    return Material(
      color: cardBg,
      child: InkWell(
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
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 选中态左侧主色 accent bar
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: isSelected ? 3 : 0,
                color: _kChatPrimary,
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    isSelected ? 13 : 16,
                    12,
                    16,
                    12,
                  ),
                  child: Row(
                    children: [
                      // 复选框
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              isSelected ? _kChatPrimary : Colors.transparent,
                          border: Border.all(
                            color: isSelected
                                ? _kChatPrimary
                                : (isDark
                                    ? Colors.white38
                                    : const Color(0xFFCBD1D9)),
                            width: 1.8,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check,
                                size: 16, color: Colors.white)
                            : null,
                      ),
                      AvatarWidget(
                        avatar: chat.avatar,
                        name: chat.name,
                        size: 52,
                        borderRadius: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    chat.name,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? AppColors.darkTextPrimary
                                          : const Color(0xFF111827),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  _formatTime(chat.lastMessageTime),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark
                                        ? AppColors.darkTextTertiary
                                        : const Color(0xFF9CA3AF),
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
                                      : '快来发送第一条消息吧~'),
                              style: TextStyle(
                                fontSize: 14,
                                color: (typingText != null &&
                                        typingText.isNotEmpty)
                                    ? _kChatPrimary
                                    : (chat.lastMessage?.isNotEmpty == true
                                        ? (isDark
                                            ? AppColors.darkTextSecondary
                                            : const Color(0xFF6B7280))
                                        : (isDark
                                            ? AppColors.darkTextTertiary
                                            : const Color(0xFF9CA3AF))),
                                fontStyle: (typingText != null &&
                                        typingText.isNotEmpty)
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
              ),
            ],
          ),
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

  /// 编辑模式底部操作栏（扁平白底 + 主色/危险色按钮）
  Widget _buildEditBottomBar(bool isDark, AppLocalizations l10n) {
    final hasSelection = _selectedChatIds.isNotEmpty;
    final Color barColor = isDark ? const Color(0xFF14161E) : Colors.white;
    final Color divColor =
        isDark ? Colors.white.withOpacity(0.05) : _kChatDivider;

    return Container(
      decoration: BoxDecoration(
        color: barColor,
        border: Border(top: BorderSide(color: divColor, width: 0.5)),
      ),
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 10,
        bottom: MediaQuery.of(context).viewPadding.bottom + 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: _EditPillButton(
              label: l10n.markAsRead,
              icon: Icons.done_all_rounded,
              enabled: hasSelection,
              foreground: _kChatPrimary,
              background: _kChatPrimary.withOpacity(0.12),
              isDark: isDark,
              onTap: hasSelection ? _markSelectedAsRead : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _EditPillButton(
              label: '删除',
              icon: Icons.delete_outline_rounded,
              enabled: hasSelection,
              foreground: AppColors.error,
              background: AppColors.error.withOpacity(0.12),
              isDark: isDark,
              onTap: hasSelection ? _deleteSelected : null,
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
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Lottie.asset(
              'assets/emoji/lottie/hatched_chick.json',
              repeat: true,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.noChats,
            style: const TextStyle(
              fontSize: 15,
              color: _kChatSubText,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Builder(
            builder: (btnCtx) => GestureDetector(
              onTap: () => _showCreateOptions(btnCtx),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: _kChatPrimary,
                  borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: _kChatPrimary.withOpacity(0.28),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Text(
                l10n.startNewChat,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              ),
            ),
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
      if (kDebugMode) debugPrint('加载用户状态失败: $e');
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
      if (kDebugMode) debugPrint('加载消息失败: $e');
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
                                                borderRadius: 12,
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

// ==================== 文件夹 Tab（已停用，保留代码用于将来切换分组功能） ====================
// ignore: unused_element
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
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
        itemCount: folders.length,
        itemBuilder: (context, index) {
          final folder = folders[index];
          final isSelected = selectedIndex == index;
          final unreadCount =
              ref.read(folderProvider.notifier).getUnreadCount(folder, chats);

          final Color fg = isSelected
              ? (isDark ? Colors.white : const Color(0xFF111827))
              : (isDark ? Colors.white54 : const Color(0xFF8A94A6));

          return Padding(
            padding: EdgeInsets.only(right: index == folders.length - 1 ? 0 : 22),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onSelect(index),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _getFolderName(folder, l10n),
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: fg,
                            letterSpacing: 0.1,
                            height: 1.15,
                          ),
                        ),
                        if (unreadCount > 0) ...[
                          const SizedBox(width: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 0,
                            ),
                            constraints:
                                const BoxConstraints(minWidth: 16, minHeight: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3B30),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : unreadCount.toString(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      height: 3,
                      width: isSelected ? 22 : 0,
                      decoration: BoxDecoration(
                        color: _kChatPrimary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
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
                            borderRadius: 14,
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

// ==================== 新版聊天页顶部圆形按钮 ====================

/// 顶部圆形按钮（左右两侧的"编辑/完成/加号/全选"胶囊）
///
/// 视觉：浅灰底、圆角胶囊、Ink 高亮，不使用毛玻璃。
class _CircleActionButton extends StatelessWidget {
  final Widget child;
  final bool isDark;
  final bool wide;

  /// 当放置在渐变色（顶部主色渐变）背景之上时启用：
  /// 背景变为半透明白，边框加一层白色 hairline，让按钮在蓝色上依然清晰。
  final bool onGradient;
  final VoidCallback onTap;

  const _CircleActionButton({
    required this.child,
    required this.isDark,
    required this.onTap,
    this.wide = false,
    this.onGradient = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = onGradient
        ? Colors.white.withOpacity(0.22)
        : (isDark
            ? Colors.white.withOpacity(0.08)
            : const Color(0xFFF0F2F5));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 36,
          constraints: BoxConstraints(minWidth: wide ? 64 : 36),
          padding: EdgeInsets.symmetric(horizontal: wide ? 12 : 8),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: onGradient
                ? Border.all(
                    color: Colors.white.withOpacity(0.30),
                    width: 0.8,
                  )
                : null,
          ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }
}

/// 编辑模式底部胶囊按钮（主色/危险色，扁平白底 pill）
class _EditPillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final Color foreground;
  final Color background;
  final bool isDark;
  final VoidCallback? onTap;

  const _EditPillButton({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.foreground,
    required this.background,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = enabled
        ? foreground
        : (isDark ? Colors.white24 : const Color(0xFFBDC1C6));
    final Color bg = enabled
        ? background
        : (isDark
            ? Colors.white.withOpacity(0.04)
            : const Color(0xFFF0F2F5));

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 顶部主色渐变现由公共组件 [TopGradientBackdrop] 提供，
// 请参见 `lib/shared/widgets/top_gradient_backdrop.dart`。
