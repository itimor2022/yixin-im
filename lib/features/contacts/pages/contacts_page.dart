// 文件用途：实现 ContactsPage 页面及其交互流程，属于联系人。
// 核心逻辑：维护 ContactsPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import '../../../shared/widgets/web_safe_lottie.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_preset.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/utils/floating_nav_layout.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/fancy_refresh_indicator.dart';
import '../../../shared/widgets/official_badge.dart';
import '../../chat/providers/chat_provider.dart';
import '../../chat/pages/chat_detail_page.dart' show ChatType;
import '../../home/pages/home_desktop_page.dart';
import '../../vip/widgets/vip_badge.dart';
import '../providers/contact_provider.dart';
import 'friend_requests_page.dart';

String _contactsPageText(
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

// 关键声明：contacts page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class ContactsPage extends ConsumerStatefulWidget {
  /// 是否作为桌面端侧边栏使用
  final bool isDesktopSidebar;

  const ContactsPage({super.key, this.isDesktopSidebar = false});

  @override
  ConsumerState<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends ConsumerState<ContactsPage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _letterKeys = {};
  String _searchQuery = '';
  String? _currentLetter;
  Timer? _minuteTimer; // 每分钟重建以便「最近在线 x分钟前」实时更新
  bool _isVisible = true; // 当前页面是否可见

  @override
  bool get wantKeepAlive => true;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    // 初始化时从服务器加载数据（仅在已登录时）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = ref.read(authServiceProvider);
      if (authState.status == AuthStatus.authenticated) {
        // Provider 已按账号隔离；页面只负责触发当前账号的首次同步。
        ref.read(contactListProvider.notifier).initialize();
        ref.read(pendingFriendRequestCountProvider.notifier).refresh();
      }
    });
    // 每分钟触发一次重建，使「最近在线 x分钟前」随时间更新
    // 只在页面可见时执行，避免后台耗电
    _startMinuteTimer();
  }

  /// 启动分钟定时器
  void _startMinuteTimer() {
    _minuteTimer?.cancel();
    _minuteTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _isVisible) setState(() {});
    });
  }

  /// 停止分钟定时器
  void _stopMinuteTimer() {
    _minuteTimer?.cancel();
    _minuteTimer = null;
  }

  /// 设置页面可见性
  void setVisible(bool visible) {
    if (_isVisible == visible) return;
    _isVisible = visible;
    if (visible) {
      // 恢复可见时，立即刷新一次并启动定时器
      if (mounted) setState(() {});
      _startMinuteTimer();
    } else {
      // 不可见时停止定时器
      _stopMinuteTimer();
    }
  }

  @override
  void dispose() {
    _stopMinuteTimer();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    // 清理 _letterKeys 避免内存泄漏
    _letterKeys.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final _pc = AppThemePresets.of(ref.watch(appThemePresetProvider));
    final contacts = ref.watch(contactListProvider);
    final pendingFriendRequestCount =
        ref.watch(pendingFriendRequestCountProvider);
    final l10n = AppLocalizations(ref.watch(languageProvider));

    // 获取官方用户列表
    final officialUsersAsync = ref.watch(officialUsersProvider);
    final officialUsers = officialUsersAsync.valueOrNull ?? {};

    // 过滤联系人 - 支持搜索名称、用户名、简介
    final filteredContacts = _searchQuery.isEmpty
        ? contacts
        : contacts.where((c) {
            final query = _searchQuery.toLowerCase();
            return c.name.toLowerCase().contains(query) ||
                (c.username?.toLowerCase().contains(query) ?? false) ||
                (c.bio?.toLowerCase().contains(query) ?? false);
          }).toList();

    // 按首字母分组
    final groupedContacts = _groupContactsByFirstLetter(filteredContacts);
    final floatingBottomSpace = FloatingNavLayout.reservedSpace(
      context,
      extra: 12,
    );
    final pageBackground =
        isDark ? AppColors.darkBackground : const Color(0xFFF5F5F5);
    final rowBackground = AppColors.cardFor(context);
    final dividerColor = AppColors.dividerFor(context);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: pageBackground,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [_pc.primaryA.withOpacity(0.9), _pc.primaryB.withOpacity(0.7)]
                    : [_pc.primaryA, _pc.primaryB],
              ),
            ),
          ),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleSpacing: 16,
          title: Text(
            l10n.tabContacts,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: _pc.appBarForeground,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Icon(
                  Icons.person_add_outlined,
                  color: AppColors.primaryFor(context),
                  size: 26,
                ),
                onPressed: () {
                  if (widget.isDesktopSidebar) {
                    // 桌面端：在右侧面板显示搜索用户
                    ref.read(desktopProfileProvider.notifier).state =
                        const DesktopProfileInfo(
                      type: DesktopPanelType.searchUsers,
                      id: 'search_users',
                    );
                  } else {
                    debugPrint(
                      '[Contacts] Add button pressed, pushing /search-users',
                    );
                    context.push('/search-users');
                  }
                },
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // 微信风格搜索框
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withOpacity(0.09)
                          : Colors.white.withOpacity(0.58),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withOpacity(0.08)
                            : Colors.white.withOpacity(0.74),
                        width: 0.8,
                      ),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                      style: TextStyle(
                        fontSize: 15,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        filled: false,
                        hintText: l10n.search,
                        hintStyle: TextStyle(
                          fontSize: 15,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : const Color(0xFF8E8E93),
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 19,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : const Color(0xFF8E8E93),
                        ),
                        prefixIconConstraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 44,
                        ),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? GestureDetector(
                                onTap: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: Icon(
                                  Icons.cancel,
                                  size: 18,
                                  color: isDark
                                      ? AppColors.darkTextTertiary
                                      : const Color(0xFF8E8E93),
                                ),
                              )
                            : null,
                        suffixIconConstraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 44,
                        ),
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 联系人列表 - 可滚动区域 + 侧边字母索引
            Expanded(
              child: filteredContacts.isEmpty
                  ? FancyRefreshIndicator(
                      topOffset: 8,
                      onRefresh: () =>
                          ref.read(contactListProvider.notifier).refresh(),
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.only(bottom: floatingBottomSpace),
                        children: [
                          if (_searchQuery.isEmpty)
                            _buildContactsQuickActions(
                              context: context,
                              l10n: l10n,
                              isDark: isDark,
                              rowBackground: rowBackground,
                              dividerColor: dividerColor,
                              pendingFriendRequestCount:
                                  pendingFriendRequestCount,
                            ),
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.42,
                            child: _buildEmptyState(l10n),
                          ),
                        ],
                      ),
                    )
                  : Stack(
                      children: [
                        // 主列表 - 白色背景覆盖整个区域
                        FancyRefreshIndicator(
                          topOffset: 8,
                          onRefresh: () =>
                              ref.read(contactListProvider.notifier).refresh(),
                          child: ListView.builder(
                            controller: _scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding:
                                EdgeInsets.only(bottom: floatingBottomSpace),
                            itemCount: groupedContacts.length +
                                (_searchQuery.isEmpty ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (_searchQuery.isEmpty && index == 0) {
                                return _buildContactsQuickActions(
                                  context: context,
                                  l10n: l10n,
                                  isDark: isDark,
                                  rowBackground: rowBackground,
                                  dividerColor: dividerColor,
                                  pendingFriendRequestCount:
                                      pendingFriendRequestCount,
                                );
                              }
                              final groupIndex =
                                  _searchQuery.isEmpty ? index - 1 : index;
                              final letter = groupedContacts.keys.elementAt(
                                groupIndex,
                              );
                              final contactsInGroup = groupedContacts[letter]!;

                              // 为每个字母创建 key
                              _letterKeys.putIfAbsent(
                                letter,
                                () => GlobalKey(),
                              );

                              return Column(
                                key: _letterKeys[letter],
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 字母分隔头
                                  Container(
                                    width: double.infinity,
                                    height: 30,
                                    alignment: Alignment.centerLeft,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    color: pageBackground,
                                    child: Text(
                                      letter,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: isDark
                                            ? const Color(0xFF8E8E93)
                                            : const Color(0xFF7E7E7E),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  // 该字母下的联系人
                                  Container(
                                    color: rowBackground,
                                    child: Column(
                                      children: contactsInGroup
                                          .asMap()
                                          .entries
                                          .map((entry) {
                                        final contact = entry.value;
                                        final isLast = entry.key ==
                                            contactsInGroup.length - 1;
                                        return Column(
                                          children: [
                                            _ContactListItem(
                                              contact: contact,
                                              onTap: () => _openChat(contact),
                                              onAvatarTap: () =>
                                                  _openProfile(contact),
                                              isOfficial:
                                                  contact.uuid != null &&
                                                      officialUsers.contains(
                                                        contact.uuid,
                                                      ),
                                            ),
                                            if (!isLast)
                                              Divider(
                                                height: 1,
                                                thickness: 0.5,
                                                indent: 88,
                                                endIndent: 0,
                                                color: dividerColor,
                                              ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),

                        // 侧边字母索引栏
                        if (groupedContacts.isNotEmpty)
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: _AlphabetIndexBar(
                              letters: groupedContacts.keys.toList(),
                              isDark: isDark,
                              onLetterSelected: (letter) =>
                                  _scrollToLetter(letter),
                              onLetterChanged: (letter) {
                                setState(() => _currentLetter = letter);
                              },
                              onScrollEnd: () {
                                setState(() => _currentLetter = null);
                              },
                            ),
                          ),

                        // 当前字母提示
                        if (_currentLetter != null)
                          Center(
                            child: Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(
                                  isDark ? 0.55 : 0.42,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  _currentLetter!,
                                  style: const TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
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
              'assets/emoji/lottie/baby_chick.json',
              repeat: true,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty ? l10n.noContactsYet : l10n.noContactsFound,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondaryFor(context),
            ),
          ),
          const SizedBox(height: 8),
          if (_searchQuery.isEmpty)
            Text(
              l10n.clickToAddFriends,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textTertiaryFor(context),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContactsQuickActions({
    required BuildContext context,
    required AppLocalizations l10n,
    required bool isDark,
    required Color rowBackground,
    required Color dividerColor,
    required int pendingFriendRequestCount,
  }) {
    return Container(
      color: rowBackground,
      child: Column(
        children: [
          _TGActionTile(
            icon: Icons.person_add_alt_1_outlined,
            title: _contactsPageText(
              context,
              zhCN: pendingFriendRequestCount > 0
                  ? '新的朋友 ($pendingFriendRequestCount)'
                  : '新的朋友',
              zhTW: pendingFriendRequestCount > 0
                  ? '新的朋友 ($pendingFriendRequestCount)'
                  : '新的朋友',
              en: pendingFriendRequestCount > 0
                  ? 'Friend Requests ($pendingFriendRequestCount)'
                  : 'Friend Requests',
            ),
            isDark: isDark,
            onTap: () {
              Navigator.of(context)
                  .push(
                    MaterialPageRoute(
                        builder: (_) => const FriendRequestsPage()),
                  )
                  // 申请可能在子页面被处理，返回后重新向服务端校准角标。
                  .then((_) => ref
                      .read(pendingFriendRequestCountProvider.notifier)
                      .refresh());
            },
          ),
          Divider(height: 1, thickness: 0.5, indent: 56, color: dividerColor),
          _TGActionTile(
            icon: Icons.groups_outlined,
            title: _contactsPageText(context,
                zhCN: '群聊', zhTW: '群聊', en: 'Groups'),
            isDark: isDark,
            onTap: () => _openChatDirectory(context, ChatItemType.group),
          ),
          Divider(height: 1, thickness: 0.5, indent: 56, color: dividerColor),
          _TGActionTile(
            icon: Icons.campaign_outlined,
            title: _contactsPageText(context,
                zhCN: '频道', zhTW: '頻道', en: 'Channels'),
            isDark: isDark,
            onTap: () => _openChatDirectory(context, ChatItemType.channel),
          ),
          Divider(height: 1, thickness: 0.5, color: dividerColor),
        ],
      ),
    );
  }

  void _scrollToLetter(String letter) {
    final key = _letterKeys[letter];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
      HapticFeedback.selectionClick();
    }
  }

  Map<String, List<ContactItem>> _groupContactsByFirstLetter(
    List<ContactItem> contacts,
  ) {
    final grouped = <String, List<ContactItem>>{};

    for (final contact in contacts) {
      String firstLetter = '#';

      if (contact.name.isNotEmpty) {
        final firstChar = contact.name[0];

        // 如果是英文字母
        if (RegExp(r'[A-Za-z]').hasMatch(firstChar)) {
          firstLetter = firstChar.toUpperCase();
        }
        // 如果是中文，转换为拼音首字母
        else if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(firstChar)) {
          final pinyin = PinyinHelper.getFirstWordPinyin(firstChar);
          if (pinyin.isNotEmpty) {
            firstLetter = pinyin[0].toUpperCase();
          }
        }
      }

      grouped.putIfAbsent(firstLetter, () => []);
      grouped[firstLetter]!.add(contact);
    }

    // 按字母 A-Z 排序，# 放最后
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == '#') return 1;
        if (b == '#') return -1;
        return a.compareTo(b);
      });

    return Map.fromEntries(sortedKeys.map((k) => MapEntry(k, grouped[k]!)));
  }

  Future<void> _openChat(ContactItem contact) async {
    // 创建或获取私聊会话
    final chatNotifier = ref.read(chatListProvider.notifier);
    final chat = await chatNotifier.createPrivateChatFromServer(
      targetUserId: contact.id,
      targetUserName: contact.name,
      avatar: contact.avatar,
    );

    if (!mounted) return;

    if (chat != null) {
      // 桌面端：只更新右侧面板，不切换标签（TG 风格）
      if (widget.isDesktopSidebar) {
        // 设置完整的聊天信息
        ref.read(selectedChatInfoProvider.notifier).state = SelectedChatInfo(
          id: chat.id,
          name: contact.name,
          avatar: contact.avatar,
          chatType: ChatType.private, // 联系人点击总是私聊
        );
        ref.read(selectedChatIdProvider.notifier).state = chat.id;
        return;
      }

      // 移动端：使用会话 ID 跳转
      final params = <String, String>{'name': contact.name, 'type': 'private'};
      if (contact.avatar != null) {
        params['avatar'] = contact.avatar!;
      }
      final queryString = params.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');
      context.push('/chat/${chat.id}?$queryString');
    } else {
      // 如果创建失败，显示错误
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            _contactsPageText(
              context,
              zhCN: '无法打开聊天',
              zhTW: '無法打開聊天',
              en: 'Unable to open chat',
            ),
          ),
        ),
      );
    }
  }

  void _openProfile(ContactItem contact) {
    // 进入用户主页
    if (contact.uuid != null) {
      context.push('/user/${contact.uuid}');
    } else {
      context.push('/user/${contact.id}');
    }
  }

  void _openChatDirectory(BuildContext context, ChatItemType type) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ContactChatDirectoryPage(type: type),
      ),
    );
  }
}

///  的操作按钮 - 简洁无背景
class _TGActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isDark;
  final VoidCallback onTap;

  const _TGActionTile({
    required this.icon,
    required this.title,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: SizedBox(
        height: 54,
        child: Row(
          children: [
            const SizedBox(width: 18),
            Icon(icon, color: AppColors.primaryFor(context), size: 23),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.linkFor(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContactChatDirectoryPage extends ConsumerWidget {
  final ChatItemType type;

  const _ContactChatDirectoryPage({required this.type});

  String _title(BuildContext context) {
    return type == ChatItemType.group
        ? _contactsPageText(context, zhCN: '群聊', zhTW: '群聊', en: 'Groups')
        : _contactsPageText(context, zhCN: '频道', zhTW: '頻道', en: 'Channels');
  }

  String _emptyText(BuildContext context) {
    return type == ChatItemType.group
        ? _contactsPageText(
            context,
            zhCN: '暂无群聊',
            zhTW: '暫無群聊',
            en: 'No groups yet',
          )
        : _contactsPageText(
            context,
            zhCN: '暂无频道',
            zhTW: '暫無頻道',
            en: 'No channels yet',
          );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBackground =
        isDark ? AppColors.darkBackground : const Color(0xFFF5F5F5);
    final rowBackground = AppColors.cardFor(context);
    final dividerColor = AppColors.dividerFor(context);
    final chats = ref
        .watch(chatListProvider)
        .allChats
        .where((chat) => chat.type == type)
        .toList();

    return Scaffold(
      backgroundColor: pageBackground,
      appBar: AppBar(
        backgroundColor: pageBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          _title(context),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: chats.isEmpty
          ? Center(
              child: Text(
                _emptyText(context),
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
            )
          : ListView.separated(
              padding: EdgeInsets.only(
                top: 8,
                bottom: FloatingNavLayout.reservedSpace(context, extra: 12),
              ),
              itemCount: chats.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                thickness: 0.5,
                indent: 76,
                color: dividerColor,
              ),
              itemBuilder: (context, index) {
                final chat = chats[index];
                return ColoredBox(
                  color: rowBackground,
                  child: _DirectoryChatTile(
                    chat: chat,
                    onTap: () => _openChat(context, chat),
                  ),
                );
              },
            ),
    );
  }

  void _openChat(BuildContext context, ChatItem chat) {
    final params = <String, String>{
      'name': chat.name,
      'type': type.name,
    };
    if (chat.avatar != null) {
      params['avatar'] = chat.avatar!;
    }
    final queryString = params.entries
        .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    context.push('/chat/${chat.id}?$queryString');
  }
}

class _DirectoryChatTile extends StatelessWidget {
  final ChatItem chat;
  final VoidCallback onTap;

  const _DirectoryChatTile({
    required this.chat,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subtitle = chat.lastMessage?.trim().isNotEmpty == true
        ? chat.lastMessage!.trim()
        : chat.type == ChatItemType.group
            ? _contactsPageText(
                context,
                zhCN: '${chat.memberCount} 位成员',
                zhTW: '${chat.memberCount} 位成員',
                en: '${chat.memberCount} members',
              )
            : _contactsPageText(
                context,
                zhCN: '频道',
                zhTW: '頻道',
                en: 'Channel',
              );

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            const SizedBox(width: 16),
            AvatarWidget(
              avatar: chat.avatar,
              name: chat.name,
              userId: chat.id,
              size: 44,
              borderRadius: 10,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          chat.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimaryFor(context),
                          ),
                        ),
                      ),
                      if (chat.isVerified) ...[
                        const SizedBox(width: 4),
                        const OfficialBadge(size: 15),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondaryFor(context),
                    ),
                  ),
                ],
              ),
            ),
            if (chat.unreadCount > 0)
              Container(
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  chat.unreadCount > 99 ? '99+' : chat.unreadCount.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            if (chat.time.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(
                chat.time,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiaryFor(context),
                ),
              ),
            ],
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

class _ContactListItem extends StatelessWidget {
  final ContactItem contact;
  final VoidCallback? onTap;
  final VoidCallback? onAvatarTap;
  final bool isOfficial;

  const _ContactListItem({
    required this.contact,
    this.onTap,
    this.onAvatarTap,
    this.isOfficial = false,
  });

  String _text(
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            const SizedBox(width: 16),
            // 头像 - 独立点击区域，进入用户主页
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onAvatarTap?.call();
              },
              child: Stack(
                children: [
                  AvatarWidget(
                    avatar: contact.avatar,
                    name: contact.name,
                    userId: contact.id,
                    size: 44,
                    borderRadius: 8,
                  ),
                  if (contact.isOnline)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: AppColors.online,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark
                                ? AppColors.darkBackground
                                : AppColors.lightBackground,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            // 名字和状态 - 点击进入聊天
            Expanded(
              child: Padding(
                padding: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: ColoredNameWidget(
                            name: contact.name,
                            nicknameColor: contact.nicknameColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            defaultColor: AppColors.textPrimaryFor(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 表情状态
                        if (contact.emojiAvatar != null &&
                            contact.emojiAvatar!.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          EmojiStatusWidget(
                            emoji: contact.emojiAvatar!,
                            size: 18,
                          ),
                        ],
                        if (contact.vip.visible) ...[
                          const SizedBox(width: 5),
                          VipBadge(
                            level: contact.vip.level,
                            text: contact.vip.badge,
                            iconUrl: contact.vip.badgeIcon,
                            height: 18,
                            compact: true,
                          ),
                        ],
                        // 官方认证标识
                        if (isOfficial) ...[
                          const SizedBox(width: 4),
                          const OfficialBadge(size: 16),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      contact.isOnline
                          ? _text(
                              context,
                              zhCN: '在线',
                              zhTW: '在線',
                              en: 'Online',
                            )
                          : (contact.lastSeen != null
                              ? _text(
                                  context,
                                  zhCN:
                                      '最近在线 ${_formatLastSeen(context, contact.lastSeen!)}',
                                  zhTW:
                                      '最近在線 ${_formatLastSeen(context, contact.lastSeen!)}',
                                  en: 'Last seen ${_formatLastSeen(context, contact.lastSeen!)}',
                                )
                              : (contact.bio ?? '')),
                      style: TextStyle(
                        fontSize: 14,
                        color: contact.isOnline
                            ? AppColors.online
                            : (AppColors.textSecondaryFor(context)),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 24),
          ],
        ),
      ),
    );
  }

  String _formatLastSeen(BuildContext context, DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (diff.inMinutes < 1) {
      return _text(
        context,
        zhCN: '刚刚',
        zhTW: '剛剛',
        en: 'just now',
      );
    }
    if (diff.inMinutes < 60) {
      return _text(
        context,
        zhCN: '${diff.inMinutes}分钟前',
        zhTW: '${diff.inMinutes}分鐘前',
        en: '${diff.inMinutes} min ago',
      );
    }
    if (diff.inHours < 24) {
      return _text(
        context,
        zhCN: '${diff.inHours}小时前',
        zhTW: '${diff.inHours}小時前',
        en: '${diff.inHours} hr ago',
      );
    }
    if (diff.inDays < 7) {
      return _text(
        context,
        zhCN: '${diff.inDays}天前',
        zhTW: '${diff.inDays}天前',
        en: '${diff.inDays} days ago',
      );
    }
    return _text(
      context,
      zhCN: '很久以前',
      zhTW: '很久以前',
      en: 'a long time ago',
    );
  }
}

/// 侧边字母索引栏
class _AlphabetIndexBar extends StatefulWidget {
  final List<String> letters;
  final bool isDark;
  final Function(String) onLetterSelected;
  final Function(String) onLetterChanged;
  final VoidCallback onScrollEnd;

  const _AlphabetIndexBar({
    required this.letters,
    required this.isDark,
    required this.onLetterSelected,
    required this.onLetterChanged,
    required this.onScrollEnd,
  });

  @override
  State<_AlphabetIndexBar> createState() => _AlphabetIndexBarState();
}

class _AlphabetIndexBarState extends State<_AlphabetIndexBar> {
  String? _selectedLetter;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: (details) => _handleDrag(details.localPosition),
      onVerticalDragUpdate: (details) => _handleDrag(details.localPosition),
      onVerticalDragEnd: (_) {
        setState(() => _selectedLetter = null);
        widget.onScrollEnd();
      },
      child: Container(
        width: 18,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: widget.letters.map((letter) {
            final isSelected = _selectedLetter == letter;
            return GestureDetector(
              onTap: () {
                widget.onLetterSelected(letter);
                widget.onLetterChanged(letter);
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) widget.onScrollEnd();
                });
              },
              child: Container(
                width: 18,
                height: 15,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primaryFor(context)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(7.5),
                ),
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: isSelected
                          ? Colors.white
                          : (widget.isDark
                              ? const Color(0xFF8E8E93)
                              : const Color(0xFF6F6F6F)),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _handleDrag(Offset localPosition) {
    final itemHeight = 15.0;
    final index = (localPosition.dy / itemHeight).floor();

    if (index >= 0 && index < widget.letters.length) {
      final letter = widget.letters[index];
      if (letter != _selectedLetter) {
        setState(() => _selectedLetter = letter);
        widget.onLetterSelected(letter);
        widget.onLetterChanged(letter);
      }
    }
  }
}
