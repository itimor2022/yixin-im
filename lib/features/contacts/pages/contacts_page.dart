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
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/official_badge.dart';
import '../../../shared/widgets/premium_widgets.dart';
import '../../../shared/widgets/premium_widgets.dart';
import '../../chat/widgets/create_sheets.dart';
import '../../chat/providers/chat_provider.dart';
import '../../chat/pages/chat_detail_page.dart' show ChatType;
import '../../home/pages/home_desktop_page.dart';
import '../providers/contact_provider.dart';

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

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        appBar: AppBar(
          backgroundColor:
              isDark ? AppColors.darkBackground : AppColors.lightBackground,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            l10n.tabContacts,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: Icon(
                  Icons.person_add_outlined,
                  color: AppColors.primary,
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
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkInputBackground
                      : const Color(0xFFEDEDED),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: (value) => setState(() => _searchQuery = value),
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: l10n.search,
                    hintStyle: TextStyle(
                      fontSize: 15,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : const Color(0xFF8E8E93),
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : const Color(0xFF8E8E93),
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
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),

            // 快捷操作 - 透明背景
            Column(
              children: [
                _TGActionTile(
                  icon: Icons.group_add_outlined,
                  title: l10n.createGroup,
                  isDark: isDark,
                  onTap: () => _showCreateGroup(context),
                ),
                _TGActionTile(
                  icon: Icons.campaign_outlined,
                  title: l10n.createChannel,
                  isDark: isDark,
                  onTap: () => _showCreateChannel(context),
                ),
                // 分割线
                Divider(
                  height: 1,
                  thickness: 0.5,
                  color:
                      isDark ? Colors.white12 : Colors.black.withOpacity(0.08),
                ),
              ],
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

                            return Column(
                              key: _letterKeys[letter],
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 字母分隔头
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    12,
                                    16,
                                    6,
                                  ),
                                  color: isDark
                                      ? AppColors.darkBackground
                                      : AppColors.lightBackground,
                                  child: Text(
                                    letter,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.white54
                                          : Colors.black54,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                // 该字母下的联系人
                                Container(
                                  color: isDark
                                      ? AppColors.darkBackground
                                      : AppColors.lightBackground,
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
                                            isOfficial: contact.uuid != null &&
                                                officialUsers.contains(
                                                  contact.uuid,
                                                ),
                                          ),
                                          if (!isLast)
                                            Divider(
                                              height: 1,
                                              indent: 74,
                                              color: isDark
                                                  ? Colors.white10
                                                  : Colors.black
                                                      .withOpacity(0.08),
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

  void _showCreateChannel(BuildContext context) {
    showCreateChannelSheet(context);
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
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // 蓝色图标 - 无背景，与联系人列表风格一致
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(width: 12),

            // 标题
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
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
                children: [
                  AvatarWidget(
                    avatar: contact.avatar,
                    name: contact.name,
                    userId: contact.id,
                    size: 46,
                    premiumType: contact.premiumType,
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
            const SizedBox(width: 12),
            // 名字和状态 - 点击进入聊天
            Expanded(
              child: PremiumContainer(
                premiumType: contact.premiumType,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: contact.premiumType?.isNotEmpty == true ? 8 : 0,
                    vertical: contact.premiumType?.isNotEmpty == true ? 6 : 0,
                  ),
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
                              premiumType: contact.premiumType,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              defaultColor: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary,
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
                            ? '在线'
                            : (contact.lastSeen != null
                                ? '最近在线 ${_formatLastSeen(contact.lastSeen!)}'
                                : (contact.bio ?? '')),
                        style: TextStyle(
                          fontSize: 14,
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
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    letter,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : (widget.isDark ? Colors.white54 : Colors.black54),
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
