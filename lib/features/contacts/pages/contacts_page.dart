import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/utils/floating_nav_layout.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/top_gradient_backdrop.dart';
import '../../chat/widgets/create_sheets.dart';
import '../../chat/providers/chat_provider.dart';
import '../../chat/pages/chat_detail_page.dart' show ChatType;
import '../../home/pages/home_desktop_page.dart';
import '../providers/contact_provider.dart';
import '../providers/friend_request_provider.dart';

/// 顶部渐变区结构尺寸（与"聊天"页节奏保持一致）：
///   · header 视觉高度 = 10 (top pad) + 44 (content) + 6 (bottom pad) = 60
///   · search 视觉高度 = 2  (top pad) + 42 (content) + 10 (bottom pad) = 54
///   · 渐变尾巴高度 = 80 —— 延伸到快捷操作卡上方，视觉上"渐变穿过搜索栏、
///     淡入到快捷操作卡里"
const double _kContactsHeaderContentHeight = 60;
const double _kContactsSearchContentHeight = 54;
const double _kContactsGradientFadeTail = 80;

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

  @override
  void initState() {
    super.initState();
    // 初始化时从服务器加载数据（仅在已登录时）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authState = ref.read(authServiceProvider);
      if (authState.status == AuthStatus.authenticated) {
        ref.read(contactListProvider.notifier).initialize();
        ref.read(friendRequestProvider.notifier).load();
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
    final contacts = ref.watch(contactListProvider);
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

    // 浅灰底色，让白色卡片能"浮起来"，与「我的」页面风格一致
    final Color pageBg =
        isDark ? AppColors.darkBackground : const Color(0xFFF7F8FA);
    final Color cardBg = isDark ? const Color(0xFF14161E) : Colors.white;

    final double topPad = MediaQuery.of(context).padding.top;
    // 渐变**不透明**区域高度（status bar + header + 搜索栏）
    final double gradientOpaqueHeight = topPad +
        _kContactsHeaderContentHeight +
        _kContactsSearchContentHeight;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: pageBg,
        // 3 层 Stack 结构，与"聊天"页完全一致
        body: Stack(
          children: [
            // ==================== 底层：可滚动内容 ====================
            //
            // 顶部预留 gradientOpaqueHeight，让快捷操作卡刚好落到渐变尾巴中间，
            // 视觉上"渐变穿过搜索栏、淡入到快捷操作卡里"。
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(top: gradientOpaqueHeight),
                child: Column(
                  children: [
                    // 顶部快捷操作卡（一整张白卡 + 3 个按钮横向平分，图标+文字上下结构）
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Container(
                decoration: BoxDecoration(
                  color: cardBg,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                ),
                clipBehavior: Clip.antiAlias,
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _ContactQuickAction(
                          icon: Icons.person_add_alt_1_rounded,
                          iconColor: const Color(0xFFFF3B30),
                          label: '新的朋友',
                          badgeCount: ref.watch(friendRequestProvider),
                          isDark: isDark,
                          onTap: () => context.push('/friend-requests'),
                        ),
                      ),
                      _ContactActionDivider(isDark: isDark),
                      Expanded(
                        child: _ContactQuickAction(
                          icon: Icons.person_search_rounded,
                          iconColor: const Color(0xFF7C3AED),
                          label: '添加好友',
                          isDark: isDark,
                          onTap: () {
                            if (widget.isDesktopSidebar) {
                              ref
                                  .read(desktopProfileProvider.notifier)
                                  .state = const DesktopProfileInfo(
                                type: DesktopPanelType.searchUsers,
                                id: 'search_users',
                              );
                            } else {
                              context.push('/search-users');
                            }
                          },
                        ),
                      ),
                      _ContactActionDivider(isDark: isDark),
                      Expanded(
                        child: _ContactQuickAction(
                          icon: Icons.group_add_rounded,
                          iconColor: const Color(0xFF34C759),
                          label: l10n.createGroup,
                          isDark: isDark,
                          onTap: () => _showCreateGroup(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 联系人列表 - 可滚动区域 + 侧边字母索引
            Expanded(
              child: filteredContacts.isEmpty
                  ? _buildEmptyState(l10n)
                  : Stack(
                      children: [
                        // 主列表 - 白色背景覆盖整个区域
                        ListView.builder(
                          controller: _scrollController,
                          padding: EdgeInsets.only(bottom: floatingBottomSpace),
                          itemCount: groupedContacts.length,
                          itemBuilder: (context, index) {
                            final letter = groupedContacts.keys.elementAt(
                              index,
                            );
                            final contactsInGroup = groupedContacts[letter]!;

                            // 为每个字母创建 key
                            _letterKeys.putIfAbsent(letter, () => GlobalKey());

                            return Padding(
                              key: _letterKeys[letter],
                              padding:
                                  const EdgeInsets.fromLTRB(14, 0, 14, 10),
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  // 字母分隔头（放到卡片外侧）
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        6, 8, 6, 6),
                                    child: Text(
                                      letter == '★' ? '★' : letter,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        letterSpacing: 0.6,
                                        color: letter == '★'
                                            ? AppColors.primary
                                            : (isDark
                                                ? Colors.white54
                                                : const Color(0xFF8A94A6)),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: cardBg,
                                      borderRadius:
                                          BorderRadius.circular(16),
                                      boxShadow: isDark
                                          ? null
                                          : [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withOpacity(0.03),
                                                blurRadius: 10,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                    ),
                                    clipBehavior: Clip.antiAlias,
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
                                              isOfficial: contact.uuid !=
                                                      null &&
                                                  officialUsers.contains(
                                                    contact.uuid,
                                                  ),
                                            ),
                                            if (!isLast)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.only(
                                                        left: 78),
                                                child: Divider(
                                                  height: 0.5,
                                                  thickness: 0.5,
                                                  color: isDark
                                                      ? Colors.white10
                                                      : const Color(
                                                          0xFFF0F1F3),
                                                ),
                                              ),
                                          ],
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        // 侧边字母索引栏
                        if (groupedContacts.isNotEmpty)
                          Positioned(
                            right: 2,
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
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.9),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  _currentLetter!,
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.bold,
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
            ),

            // ==================== 中层：纯装饰渐变（IgnorePointer） ====================
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topPad +
                  _kContactsHeaderContentHeight +
                  _kContactsSearchContentHeight +
                  _kContactsGradientFadeTail,
              child: const IgnorePointer(
                child: TopGradientBackdrop(),
              ),
            ),

            // ==================== 顶层：交互式左对齐标题 + 搜索栏 ====================
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
                      _buildAppHeader(l10n),
                      _buildSearchBar(isDark, cardBg, l10n),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 左对齐白字标题栏 —— 与"聊天"页 header 保持视觉一致
  ///
  /// 视觉高度 = 10 (top pad) + 44 (content) + 6 (bottom pad) = [_kContactsHeaderContentHeight]
  Widget _buildAppHeader(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: SizedBox(
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l10n.tabContacts,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  /// 搜索栏 —— 白卡 + TextField，与"聊天"页搜索栏一致
  Widget _buildSearchBar(bool isDark, Color cardBg, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: cardBg,
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
            Expanded(
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: (value) => setState(() => _searchQuery = value),
                style: TextStyle(
                  fontSize: 14.5,
                  color: isDark ? Colors.white : const Color(0xFF111827),
                ),
                decoration: InputDecoration(
                  hintText: l10n.search,
                  hintStyle: TextStyle(
                    fontSize: 14.5,
                    color: isDark
                        ? Colors.white54
                        : const Color(0xFF9CA3AF),
                  ),
                  // 关键：显式关闭全局 InputDecorationTheme 的 filled + fillColor
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            if (_searchQuery.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                child: Icon(
                  Icons.cancel,
                  size: 18,
                  color: isDark ? Colors.white54 : const Color(0xFF9CA3AF),
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
            child: Lottie.asset(
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
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (_searchQuery.isEmpty)
            Text(
              l10n.clickToAddFriends,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.lightTextTertiary,
              ),
            ),
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
      // 会员单独放 ★ 分组，排在最前面
      if (contact.isMember) {
        grouped.putIfAbsent('★', () => []);
        grouped['★']!.add(contact);
        continue;
      }

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

    // ★ 会员分组排最前，A-Z 其次，# 放最后
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        if (a == '★') return -1;
        if (b == '★') return 1;
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
      ).showSnackBar(const SnackBar(content: Text('无法打开聊天')));
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

  void _showCreateGroup(BuildContext context) {
    showCreateGroupSheet(context);
  }
}

/// 顶部快捷操作按钮：图标 + 文字上下结构，右上角红点角标
class _ContactQuickAction extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final int badgeCount;
  final bool isDark;
  final VoidCallback onTap;

  const _ContactQuickAction({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        splashColor: iconColor.withOpacity(0.08),
        highlightColor: iconColor.withOpacity(0.04),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: iconColor, size: 28),
                  if (badgeCount > 0)
                    Positioned(
                      right: -8,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1.5),
                        constraints: const BoxConstraints(minWidth: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B30),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: isDark
                                ? const Color(0xFF14161E)
                                : Colors.white,
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          badgeCount > 99 ? '99+' : '$badgeCount',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color:
                      isDark ? Colors.white70 : const Color(0xFF374151),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 快捷操作卡内部的竖向分割线
class _ContactActionDivider extends StatelessWidget {
  final bool isDark;
  const _ContactActionDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.6,
      margin: const EdgeInsets.symmetric(vertical: 12),
      color: isDark
          ? Colors.white.withOpacity(0.06)
          : const Color(0xFFF0F1F3),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // 头像 - 独立点击区域，进入用户主页
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onAvatarTap?.call();
              },
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  AvatarWidget(
                    avatar: contact.avatar,
                    name: contact.name,
                    userId: contact.id,
                    size: 46,
                    borderRadius: 23,
                  ),
                  if (contact.isOnline)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 13,
                        height: 13,
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
            const SizedBox(width: 12),
            // 名字和状态 - 点击进入聊天
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    contact.name,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : const Color(0xFF111827),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    contact.isOnline
                        ? '在线'
                        : (contact.lastSeen != null
                            ? '最近在线 ${_formatLastSeen(contact.lastSeen!)}'
                            : (contact.bio ?? '')),
                    style: TextStyle(
                      fontSize: 13,
                      color: contact.isOnline
                          ? AppColors.online
                          : (isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary),
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

  String _formatLastSeen(DateTime lastSeen) {
    final now = DateTime.now();
    final diff = now.difference(lastSeen);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '很久以前';
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
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.primary
                      : (letter == '★'
                          ? AppColors.primary.withOpacity(0.15)
                          : Colors.transparent),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: letter == '★' ? 9 : 10,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (letter == '★'
                              ? AppColors.primary
                              : (widget.isDark ? Colors.white54 : Colors.black54)),
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
    final itemHeight = 16.0;
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
