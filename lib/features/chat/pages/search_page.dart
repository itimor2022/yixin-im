// 文件用途：实现 SearchPage 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 SearchPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:isar/isar.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/chat_service.dart' as api;
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_preset.dart';
import '../../../core/theme/theme_provider.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/services/storage/models/message_model.dart'
    if (dart.library.js_interop) '../../../core/services/storage/models/message_model_web.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../providers/chat_provider.dart';
import '../../contacts/providers/contact_provider.dart';
import '../../home/pages/home_desktop_page.dart';
import '../../vip/widgets/vip_badge.dart';
import 'chat_detail_page.dart' show ChatType;
import '../../../core/services/storage/isar_service.dart';

String _searchText(
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

// 关键声明：search page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class SearchPage extends ConsumerStatefulWidget {
  final bool isDesktopPanel; // 是否作为桌面右侧面板显示
  final String? initialQuery;

  const SearchPage({
    super.key,
    this.isDesktopPanel = false,
    this.initialQuery,
  });

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<Map<String, dynamic>> _messageResults = [];
  List<api.GlobalSearchItem> _remoteContactResults = [];
  List<api.GlobalSearchItem> _remoteChatResults = [];
  List<api.GlobalSearchItem> _remoteMessageResults = [];
  List<api.GlobalSearchItem> _fileResults = [];
  String _lastSearchedQuery = '';
  int _remotePage = 1;
  bool _hasMoreRemoteContacts = false;
  bool _hasMoreRemoteChats = false;
  bool _hasMoreRemoteMessages = false;
  bool _hasMoreRemoteFiles = false;
  bool _isLoadingMoreRemote = false;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    final initialQuery = widget.initialQuery?.trim() ?? '';
    if (initialQuery.isNotEmpty) {
      _searchController.text = initialQuery;
      _searchQuery = initialQuery;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
      if (_searchQuery.isNotEmpty) {
        _searchMessages();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _searchMessages();
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _lastSearchedQuery = '';
      _messageResults = [];
      _remoteContactResults = [];
      _remoteChatResults = [];
      _remoteMessageResults = [];
      _fileResults = [];
      _remotePage = 1;
      _hasMoreRemoteContacts = false;
      _hasMoreRemoteChats = false;
      _hasMoreRemoteMessages = false;
      _hasMoreRemoteFiles = false;
    });
  }

  Future<void> _searchMessages() async {
    if (_searchQuery.isEmpty) {
      setState(() {
        _messageResults = [];
        _remoteContactResults = [];
        _remoteChatResults = [];
        _remoteMessageResults = [];
        _fileResults = [];
        _remotePage = 1;
        _hasMoreRemoteContacts = false;
        _hasMoreRemoteChats = false;
        _hasMoreRemoteMessages = false;
        _hasMoreRemoteFiles = false;
      });
      return;
    }

    if (_searchQuery == _lastSearchedQuery) return;
    _lastSearchedQuery = _searchQuery;

    final keyword = _searchQuery;
    final localResults = await _searchLocalMessages(keyword);

    if (keyword == _searchQuery) {
      setState(() {
        _messageResults = localResults;
      });
    }

    final chatService = ref.read(api.chatServiceProvider);
    final remote = await chatService.globalSearch(keyword, limit: 8, page: 1);
    if (!mounted || keyword != _searchQuery) return;
    if (remote.isSuccess && remote.data != null) {
      setState(() {
        _remotePage = remote.data!.page;
        _remoteContactResults = remote.data!.contacts;
        _remoteChatResults = remote.data!.chats;
        _remoteMessageResults = remote.data!.messages;
        _fileResults = remote.data!.files;
        _hasMoreRemoteContacts = remote.data!.hasMore['contacts'] ?? false;
        _hasMoreRemoteChats = remote.data!.hasMore['chats'] ?? false;
        _hasMoreRemoteMessages = remote.data!.hasMore['messages'] ?? false;
        _hasMoreRemoteFiles = remote.data!.hasMore['files'] ?? false;
      });
    }
  }

  Future<void> _loadMoreRemoteResults() async {
    final keyword = _searchQuery.trim();
    if (keyword.isEmpty || _isLoadingMoreRemote) return;
    if (!_hasMoreRemoteContacts &&
        !_hasMoreRemoteChats &&
        !_hasMoreRemoteMessages &&
        !_hasMoreRemoteFiles) {
      return;
    }

    setState(() => _isLoadingMoreRemote = true);
    try {
      final chatService = ref.read(api.chatServiceProvider);
      final nextPage = _remotePage + 1;
      final remote = await chatService.globalSearch(
        keyword,
        limit: 8,
        page: nextPage,
      );
      if (!mounted || keyword != _searchQuery) return;
      if (remote.isSuccess && remote.data != null) {
        setState(() {
          _remotePage = remote.data!.page;
          _remoteContactResults = _appendUniqueGlobalItems(
            _remoteContactResults,
            remote.data!.contacts,
          );
          _remoteChatResults = _appendUniqueGlobalItems(
            _remoteChatResults,
            remote.data!.chats,
          );
          _remoteMessageResults = _appendUniqueGlobalItems(
            _remoteMessageResults,
            remote.data!.messages,
          );
          _fileResults = _appendUniqueGlobalItems(
            _fileResults,
            remote.data!.files,
          );
          _hasMoreRemoteContacts = remote.data!.hasMore['contacts'] ?? false;
          _hasMoreRemoteChats = remote.data!.hasMore['chats'] ?? false;
          _hasMoreRemoteMessages = remote.data!.hasMore['messages'] ?? false;
          _hasMoreRemoteFiles = remote.data!.hasMore['files'] ?? false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMoreRemote = false);
      }
    }
  }

  List<api.GlobalSearchItem> _appendUniqueGlobalItems(
    List<api.GlobalSearchItem> current,
    List<api.GlobalSearchItem> incoming,
  ) {
    final seen = current.map((item) => item.messageId ?? item.id).toSet();
    final merged = [...current];
    for (final item in incoming) {
      final key = item.messageId ?? item.id;
      if (seen.add(key)) {
        merged.add(item);
      }
    }
    return merged;
  }

  Future<List<Map<String, dynamic>>> _searchLocalMessages(
      String keyword) async {
    final accountId = ref.read(authServiceProvider).user?.uuid ?? '';
    if (accountId.isEmpty) return [];

    if (PlatformUtils.isWeb) {
      return _searchWebCachedMessages(keyword, accountId);
    }
    if (!IsarService.instance.isAvailable) return [];

    try {
      final messages = await IsarService.instance.isar.messageModels
          .filter()
          .accountIdEqualTo(accountId)
          .contentContains(keyword, caseSensitive: false)
          .sortByCreatedAtDesc()
          .limit(50)
          .findAll();

      final chatState = ref.read(chatListProvider);
      final allChats = [...chatState.pinnedChats, ...chatState.regularChats];
      final chatMap = {for (var c in allChats) c.id: c};

      return messages.map((msg) {
        final chat = chatMap[msg.chatId];
        return {
          'chat_id': msg.chatId,
          'chat_uuid': msg.chatId,
          'chat_name': chat?.name ?? '',
          'chat_avatar': chat?.avatar ?? '',
          'chat_type': _chatTypeCode(chat),
          'message_id': msg.id,
          'content': {'text': msg.content},
          'sender_id': msg.senderId,
          'sender_name': msg.senderName,
          'created_at': msg.createdAt.toIso8601String(),
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  int _chatTypeCode(ChatItem? chat) {
    switch (chat?.type) {
      case ChatItemType.private:
        return 1;
      case ChatItemType.group:
        return 2;
      case ChatItemType.channel:
      case null:
        return 3;
    }
  }

  Future<List<Map<String, dynamic>>> _searchWebCachedMessages(
    String keyword,
    String accountId,
  ) async {
    try {
      final query = keyword.toLowerCase();
      final prefs = await SharedPreferences.getInstance();
      final prefix = 'message_window_${accountId}_';
      final chatState = ref.read(chatListProvider);
      final allChats = [...chatState.pinnedChats, ...chatState.regularChats];
      final chatMap = {for (var c in allChats) c.id: c};
      final results = <Map<String, dynamic>>[];

      for (final key in prefs.getKeys()) {
        if (!key.startsWith(prefix)) continue;
        final raw = prefs.getString(key);
        if (raw == null || raw.isEmpty) continue;
        final decoded = jsonDecode(raw);
        if (decoded is! List) continue;

        for (final item in decoded) {
          if (item is! Map) continue;
          final json = Map<String, dynamic>.from(item);
          final content = json['content']?.toString() ?? '';
          if (!content.toLowerCase().contains(query)) continue;

          final chatId =
              json['chat_id']?.toString() ?? key.substring(prefix.length);
          final chat = chatMap[chatId];
          results.add({
            'chat_id': chatId,
            'chat_uuid': chatId,
            'chat_name': chat?.name ?? '',
            'chat_avatar': chat?.avatar ?? '',
            'chat_type': _chatTypeCode(chat),
            'message_id': json['id']?.toString() ?? '',
            'content': {'text': content},
            'sender_id': json['sender_id']?.toString() ?? '',
            'sender_name': json['sender_name']?.toString() ?? '',
            'created_at': json['created_at']?.toString() ?? '',
          });
        }
      }

      results.sort(
        (a, b) => (b['created_at']?.toString() ?? '').compareTo(
          a['created_at']?.toString() ?? '',
        ),
      );
      return results.take(50).toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final _pc = AppThemePresets.of(ref.watch(appThemePresetProvider));
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final chatState = ref.watch(chatListProvider);
    final allChats = [...chatState.pinnedChats, ...chatState.regularChats];
    final contacts = ref.watch(contactListProvider);
    final localChatIds = allChats.map((chat) => chat.id).toSet();
    final localContactIds = contacts
        .map((contact) => contact.uuid?.trim().isNotEmpty == true
            ? contact.uuid!.trim()
            : contact.id)
        .toSet();
    final remoteChats = _remoteChatResults
        .where((item) => !localChatIds.contains(item.id))
        .toList();
    final remoteContacts = _remoteContactResults
        .where((item) => !localContactIds.contains(item.id))
        .toList();
    final remoteMessageMaps = _remoteMessageResults
        .where((item) => !_messageResults.any(
              (local) => local['message_id']?.toString() == item.messageId,
            ))
        .map(_globalMessageToMap)
        .toList();
    final allMessageResults = [..._messageResults, ...remoteMessageMaps];

    // 过滤聊天列表
    final filteredChats = _searchQuery.isEmpty
        ? <ChatItem>[]
        : allChats.where((c) {
            final query = _searchQuery.toLowerCase();
            final usernameQuery =
                query.startsWith('@') ? query.substring(1) : query;
            final nameLower = c.name.toLowerCase();
            final usernameLower = (c.username ?? '').toLowerCase();
            final pinyin =
                PinyinHelper.getPinyin(c.name, separator: '').toLowerCase();
            final firstLetters =
                PinyinHelper.getShortPinyin(c.name).toLowerCase();
            return nameLower.contains(query) ||
                usernameLower.contains(usernameQuery) ||
                pinyin.contains(query) ||
                firstLetters.contains(query);
          }).toList();

    // 过滤联系人
    final filteredContacts = _searchQuery.isEmpty
        ? <ContactItem>[]
        : contacts.where((c) {
            final query = _searchQuery.toLowerCase();
            final usernameQuery =
                query.startsWith('@') ? query.substring(1) : query;
            final nameLower = c.name.toLowerCase();
            final usernameLower = (c.username ?? '').toLowerCase();
            final bioLower = (c.bio ?? '').toLowerCase();
            final pinyin =
                PinyinHelper.getPinyin(c.name, separator: '').toLowerCase();
            final firstLetters =
                PinyinHelper.getShortPinyin(c.name).toLowerCase();
            return nameLower.contains(query) ||
                usernameLower.contains(usernameQuery) ||
                bioLower.contains(query) ||
                pinyin.contains(query) ||
                firstLetters.contains(query);
          }).toList();

    return Scaffold(
      backgroundColor: Color.lerp(
        AppColors.backgroundFor(context),
        Theme.of(context).colorScheme.primary,
        isDark ? 0.04 : 0.03,
      )!,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      _pc.primaryA.withOpacity(0.85),
                      _pc.primaryB.withOpacity(0.75)
                    ]
                  : [_pc.primaryA, _pc.primaryB],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leadingWidth: 0,
            leading: const SizedBox.shrink(),
            titleSpacing: 8, // ✅ 从 16 改为 8，让搜索框有更多空间
            title: Container(
              height: 44, // ✅ 从 40 改为 44，更接近标准输入框高度
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.15)
                    : Colors.white.withOpacity(0.85),
                borderRadius: BorderRadius.circular(18),
                // ✅ 添加边框，让搜索框边界更清晰
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.2)
                      : Colors.black.withOpacity(0.1),
                  width: 1.5,
                ),
              ),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _onSearchChanged,
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textPrimaryFor(context),
                ),
                decoration: InputDecoration(
                  hintText: l10n.search,
                  hintStyle: TextStyle(
                    color: isDark
                        ? Colors.white.withOpacity(0.4)
                        : _pc.primaryA.withOpacity(0.45),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: isDark
                        ? Colors.white.withOpacity(0.4)
                        : _pc.primaryA.withOpacity(0.5),
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? GestureDetector(
                          onTap: _clearSearch,
                          child: Icon(
                            Icons.cancel,
                            size: 18,
                            color: isDark
                                ? Colors.white.withOpacity(0.4)
                                : _pc.primaryA.withOpacity(0.5),
                          ),
                        )
                      : null,
                  border: InputBorder.none,
                  // ✅ 调整内边距，让内容更居中
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                  // ✅ 添加聚焦状态样式
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (widget.isDesktopPanel) {
                    ref.read(desktopProfileProvider.notifier).state =
                        DesktopProfileInfo.none;
                  } else {
                    context.pop();
                  }
                },
                child: Text(
                  l10n.cancel,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: _searchQuery.isEmpty
          ? _buildEmptyState(isDark, l10n)
          : ListView(
              children: [
                // 聊天
                if (filteredChats.isNotEmpty) ...[
                  _buildSectionHeader(l10n.tabChat, isDark),
                  ...filteredChats
                      .take(5)
                      .map((chat) => _buildChatItem(chat, isDark)),
                ],
                if (remoteChats.isNotEmpty) ...[
                  if (filteredChats.isEmpty)
                    _buildSectionHeader(l10n.tabChat, isDark),
                  ...remoteChats
                      .map((chat) => _buildRemoteChatItem(chat, isDark)),
                ],
                // 联系人
                if (filteredContacts.isNotEmpty) ...[
                  _buildSectionHeader(l10n.tabContacts, isDark),
                  ...filteredContacts
                      .take(5)
                      .map((contact) => _buildContactItem(contact, isDark)),
                ],
                if (remoteContacts.isNotEmpty) ...[
                  if (filteredContacts.isEmpty)
                    _buildSectionHeader(l10n.tabContacts, isDark),
                  ...remoteContacts.map(
                    (contact) => _buildRemoteContactItem(contact, isDark),
                  ),
                ],
                // 聊天记录
                if (allMessageResults.isNotEmpty) ...[
                  _buildSectionHeader(
                    l10n.get('chat_history') ??
                        _searchText(
                          context,
                          zhCN: '聊天记录',
                          zhTW: '聊天記錄',
                          en: 'Chat History',
                        ),
                    isDark,
                  ),
                  ...allMessageResults
                      .map((msg) => _buildMessageItem(msg, isDark)),
                ],
                if (_fileResults.isNotEmpty) ...[
                  _buildSectionHeader(
                    _searchText(
                      context,
                      zhCN: '文件',
                      zhTW: '檔案',
                      en: 'Files',
                    ),
                    isDark,
                  ),
                  ..._fileResults.map((file) => _buildFileItem(file, isDark)),
                ],
                if (_hasMoreRemoteContacts ||
                    _hasMoreRemoteChats ||
                    _hasMoreRemoteMessages ||
                    _hasMoreRemoteFiles)
                  _buildLoadMoreRemoteButton(isDark),
                // 无结果
                if (filteredChats.isEmpty &&
                    remoteChats.isEmpty &&
                    filteredContacts.isEmpty &&
                    remoteContacts.isEmpty &&
                    allMessageResults.isEmpty &&
                    _fileResults.isEmpty)
                  _buildNoResults(isDark, l10n),
              ],
            ),
    );
  }

  Map<String, dynamic> _globalMessageToMap(api.GlobalSearchItem item) {
    return {
      'chat_id': item.chatId,
      'chat_uuid': item.chatId,
      'chat_name': item.chatName ?? item.title,
      'chat_avatar': item.avatar ?? '',
      'chat_type': item.chatType ?? 1,
      'message_id': item.messageId ?? item.id,
      'content': item.content.isNotEmpty ? item.content : {'text': item.text},
      'highlight_text': item.highlightText,
      'highlight_start': item.highlightStart,
      'highlight_end': item.highlightEnd,
      'sender_name': item.subtitle,
      'created_at': item.createdAt?.toIso8601String(),
    };
  }

  Widget _buildEmptyState(bool isDark, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: AppColors.textTertiaryFor(context),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.get('search_chats_contacts_messages') ??
                _searchText(
                  context,
                  zhCN: '搜索聊天、联系人和消息',
                  zhTW: '搜尋聊天、聯絡人和訊息',
                  en: 'Search chats, contacts, and messages',
                ),
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textTertiaryFor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults(bool isDark, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: AppColors.textTertiaryFor(context),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.get('no_search_results') ??
                  _searchText(
                    context,
                    zhCN: '无搜索结果',
                    zhTW: '無搜尋結果',
                    en: 'No search results',
                  ),
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textTertiaryFor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondaryFor(context),
        ),
      ),
    );
  }

  Widget _buildLoadMoreRemoteButton(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Center(
        child: TextButton.icon(
          onPressed: _isLoadingMoreRemote ? null : _loadMoreRemoteResults,
          icon: _isLoadingMoreRemote
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primaryFor(context),
                  ),
                )
              : const Icon(Icons.expand_more, size: 18),
          label: Text(
            _searchText(
              context,
              zhCN: '加载更多',
              zhTW: '載入更多',
              en: 'Load more',
            ),
          ),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.linkFor(context),
            textStyle: const TextStyle(fontSize: 14),
          ),
        ),
      ),
    );
  }

  ChatType _chatItemDetailType(ChatItemType type) {
    switch (type) {
      case ChatItemType.group:
        return ChatType.group;
      case ChatItemType.channel:
        return ChatType.channel;
      case ChatItemType.private:
        return ChatType.private;
    }
  }

  String _chatItemRouteType(ChatItemType type) {
    switch (type) {
      case ChatItemType.group:
        return 'group';
      case ChatItemType.channel:
        return 'channel';
      case ChatItemType.private:
        return 'private';
    }
  }

  ChatType _globalChatDetailType(String type) {
    switch (type) {
      case 'group':
        return ChatType.group;
      case 'channel':
        return ChatType.channel;
      default:
        return ChatType.private;
    }
  }

  String _globalChatRouteType(String type) {
    switch (type) {
      case 'group':
      case 'channel':
        return type;
      default:
        return 'private';
    }
  }

  bool _isInternalEmojiValue(String? value) {
    final text = value?.trim() ?? '';
    return text.startsWith('__custom_emoji__:') ||
        text.startsWith('__custom_emoji_url__:');
  }

  String _safeSearchDisplayText(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty || _isInternalEmojiValue(text)) return '';
    return text;
  }

  String _safeSearchName({
    required String? primary,
    String? secondary,
    required String fallback,
    bool prefixSecondary = false,
  }) {
    final safePrimary = _safeSearchDisplayText(primary);
    if (safePrimary.isNotEmpty) return safePrimary;

    final safeSecondary =
        _safeSearchDisplayText(secondary).replaceFirst(RegExp(r'^@+'), '');
    if (safeSecondary.isNotEmpty) {
      return prefixSecondary ? '@$safeSecondary' : safeSecondary;
    }
    return fallback;
  }

  Widget _buildChatItem(ChatItem chat, bool isDark) {
    final displayName = _safeSearchName(
      primary: chat.name,
      secondary: chat.username,
      fallback: _searchText(
        context,
        zhCN: '未知聊天',
        zhTW: '未知聊天',
        en: 'Unknown Chat',
      ),
      prefixSecondary: true,
    );
    final username = _safeSearchDisplayText(chat.username);
    final shouldShowUsername = username.isNotEmpty &&
        _searchQuery.startsWith('@') &&
        displayName != '@$username';
    final subtitleText =
        shouldShowUsername ? '@$username' : (chat.lastMessage ?? '');

    return ListTile(
      leading: AvatarWidget(
        avatar: chat.avatar,
        name: displayName,
        userId: chat.type == ChatItemType.private
            ? (chat.targetUserId ?? chat.id)
            : chat.id,
        size: 44,
        borderRadius: 12,
      ),
      title: Row(
        children: [
          Expanded(
            child: ColoredNameWidget(
              name: displayName,
              nicknameColor: chat.nicknameColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              defaultColor: AppColors.textPrimaryFor(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (chat.emojiAvatar != null && chat.emojiAvatar!.isNotEmpty) ...[
            const SizedBox(width: 4),
            EmojiStatusWidget(
              emoji: chat.emojiAvatar!,
              size: 18,
            ),
          ],
        ],
      ),
      subtitle: subtitleText.isNotEmpty
          ? Text(
              subtitleText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: shouldShowUsername
                    ? AppColors.linkFor(context)
                    : AppColors.textSecondaryFor(context),
                fontSize: 14,
              ),
            )
          : null,
      onTap: () {
        if (widget.isDesktopPanel) {
          // 桌面端：关闭搜索面板，在右侧显示聊天
          ref.read(desktopProfileProvider.notifier).state =
              DesktopProfileInfo.none;
          // 设置选中的聊天
          ref.read(selectedChatInfoProvider.notifier).state = SelectedChatInfo(
            id: chat.id,
            name: displayName,
            avatar: chat.avatar,
            chatType: _chatItemDetailType(chat.type),
          );
          ref.read(selectedChatIdProvider.notifier).state = chat.id;
        } else {
          context.pop();
          context.push(
            '/chat/${chat.id}?name=${Uri.encodeComponent(displayName)}&type=${_chatItemRouteType(chat.type)}',
          );
        }
      },
    );
  }

  Widget _buildRemoteChatItem(api.GlobalSearchItem chat, bool isDark) {
    final routeType = _globalChatRouteType(chat.type);
    final detailType = _globalChatDetailType(chat.type);
    final displayTitle = _safeSearchName(
      primary: chat.title,
      secondary: chat.subtitle,
      fallback: _searchText(
        context,
        zhCN: '未知聊天',
        zhTW: '未知聊天',
        en: 'Unknown Chat',
      ),
    );
    final subtitle = _safeSearchDisplayText(chat.highlightText).isNotEmpty
        ? _safeSearchDisplayText(chat.highlightText)
        : _safeSearchDisplayText(chat.subtitle);

    return ListTile(
      leading: AvatarWidget(
        avatar: chat.avatar,
        name: displayTitle,
        userId: chat.id,
        size: 44,
        borderRadius: 12,
      ),
      title: RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: _highlightSpans(
            displayTitle,
            chat.highlightText == displayTitle ? chat.highlightStart : null,
            chat.highlightText == displayTitle ? chat.highlightEnd : null,
            TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
            TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.linkFor(context),
            ),
          ),
        ),
      ),
      subtitle: subtitle.isNotEmpty
          ? RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: _highlightSpans(
                  subtitle,
                  chat.highlightText == subtitle ? chat.highlightStart : null,
                  chat.highlightText == subtitle ? chat.highlightEnd : null,
                  TextStyle(
                    color: AppColors.textSecondaryFor(context),
                    fontSize: 14,
                  ),
                  TextStyle(
                    color: AppColors.linkFor(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          : null,
      onTap: () {
        if (widget.isDesktopPanel) {
          ref.read(desktopProfileProvider.notifier).state =
              DesktopProfileInfo.none;
          ref.read(selectedChatInfoProvider.notifier).state = SelectedChatInfo(
            id: chat.id,
            name: displayTitle,
            avatar: chat.avatar,
            chatType: detailType,
          );
          ref.read(selectedChatIdProvider.notifier).state = chat.id;
          return;
        }
        context.pop();
        context.push(
          '/chat/${chat.id}?name=${Uri.encodeComponent(displayTitle)}&type=$routeType',
        );
      },
    );
  }

  Widget _buildContactItem(ContactItem contact, bool isDark) {
    final displayName = _safeSearchName(
      primary: contact.name,
      secondary: contact.username,
      fallback: _searchText(
        context,
        zhCN: '未知用户',
        zhTW: '未知使用者',
        en: 'Unknown User',
      ),
      prefixSecondary: true,
    );
    final username = _safeSearchDisplayText(contact.username);
    return ListTile(
      leading: AvatarWidget(
        avatar: contact.avatar,
        name: displayName,
        userId: contact.id,
        size: 44,
        borderRadius: 12,
      ),
      title: Row(
        children: [
          Expanded(
            child: ColoredNameWidget(
              name: displayName,
              nicknameColor: contact.nicknameColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              defaultColor: AppColors.textPrimaryFor(context),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
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
        ],
      ),
      subtitle: username.isNotEmpty && displayName != '@$username'
          ? Text(
              '@$username',
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontSize: 14,
              ),
            )
          : null,
      onTap: () {
        if (widget.isDesktopPanel) {
          // 桌面端：关闭搜索面板，显示用户资料
          ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo(
            type: DesktopPanelType.user,
            id: contact.uuid ?? contact.id,
            name: displayName,
            avatar: contact.avatar,
          );
        } else {
          context.pop();
          context.push('/user/${contact.uuid ?? contact.id}');
        }
      },
    );
  }

  Widget _buildRemoteContactItem(api.GlobalSearchItem contact, bool isDark) {
    final displayTitle = _safeSearchName(
      primary: contact.title,
      secondary: contact.subtitle,
      fallback: _searchText(
        context,
        zhCN: '未知用户',
        zhTW: '未知使用者',
        en: 'Unknown User',
      ),
      prefixSecondary: true,
    );
    final safeHighlight = _safeSearchDisplayText(contact.highlightText);
    final safeUsername = _safeSearchDisplayText(contact.subtitle)
        .replaceFirst(RegExp(r'^@+'), '');
    final subtitle = safeHighlight.isNotEmpty && safeHighlight != displayTitle
        ? safeHighlight
        : (safeUsername.isNotEmpty && displayTitle != '@$safeUsername'
            ? '@$safeUsername'
            : '');

    return ListTile(
      leading: AvatarWidget(
        avatar: contact.avatar,
        name: displayTitle,
        userId: contact.id,
        size: 44,
        borderRadius: 12,
      ),
      title: Row(
        children: [
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: _highlightSpans(
                  displayTitle,
                  contact.highlightText == displayTitle
                      ? contact.highlightStart
                      : null,
                  contact.highlightText == displayTitle
                      ? contact.highlightEnd
                      : null,
                  TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.linkFor(context),
                  ),
                ),
              ),
            ),
          ),
          if (contact.emojiAvatar != null &&
              contact.emojiAvatar!.isNotEmpty) ...[
            const SizedBox(width: 4),
            EmojiStatusWidget(
              emoji: contact.emojiAvatar!,
              size: 18,
            ),
          ],
          if (contact.vipVisible) ...[
            const SizedBox(width: 5),
            VipBadge(
              level: contact.vipLevel,
              text: contact.vipBadge,
              iconUrl: contact.vipBadgeIcon,
              height: 18,
              compact: true,
            ),
          ],
        ],
      ),
      subtitle: subtitle.isNotEmpty
          ? RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: _highlightSpans(
                  subtitle,
                  contact.highlightText == subtitle
                      ? contact.highlightStart
                      : null,
                  contact.highlightText == subtitle
                      ? contact.highlightEnd
                      : null,
                  TextStyle(
                    color: AppColors.textSecondaryFor(context),
                    fontSize: 14,
                  ),
                  TextStyle(
                    color: AppColors.linkFor(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          : null,
      onTap: () {
        if (widget.isDesktopPanel) {
          ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo(
            type: DesktopPanelType.user,
            id: contact.id,
            name: displayTitle,
            avatar: contact.avatar,
          );
          return;
        }
        context.pop();
        context.push('/user/${contact.id}');
      },
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> msg, bool isDark) {
    final chatName = msg['chat_name'] as String? ??
        _searchText(
          context,
          zhCN: '未知聊天',
          zhTW: '未知聊天',
          en: 'Unknown Chat',
        );
    final chatAvatar = msg['chat_avatar'] as String? ?? '';
    final senderName = msg['sender_name'] as String? ?? '';
    final content = msg['content'] as Map<String, dynamic>? ?? {};
    final text = content['text'] as String? ?? '';
    final highlightText = msg['highlight_text'] as String?;
    final highlightStart = msg['highlight_start'] as int?;
    final highlightEnd = msg['highlight_end'] as int?;
    final displayText = highlightText != null && highlightText.isNotEmpty
        ? highlightText
        : text;
    final chatUuid = msg['chat_uuid'] as String?;
    final chatType = msg['chat_type'];
    final createdAt = msg['created_at'] as String?;
    final messageId = msg['message_id'] as String?;

    String typeStr = 'private';
    if (chatType == 2) typeStr = 'group';
    if (chatType == 3) typeStr = 'channel';

    String timeStr = '';
    if (createdAt != null) {
      try {
        final dt = DateTime.parse(createdAt).toLocal();
        final now = DateTime.now();
        if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
          timeStr =
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        } else {
          timeStr = '${dt.month}/${dt.day}';
        }
      } catch (_) {}
    }

    // 高亮搜索词
    final query = _searchQuery.toLowerCase();
    final textLower = displayText.toLowerCase();
    final matchIndex = textLower.indexOf(query);
    final effectiveStart = highlightStart != null && highlightStart >= 0
        ? highlightStart
        : matchIndex;
    final effectiveEnd = highlightEnd != null && highlightEnd > effectiveStart
        ? highlightEnd
        : effectiveStart + _searchQuery.length;

    return InkWell(
      onTap: () {
        if (chatUuid != null) {
          if (widget.isDesktopPanel) {
            // 桌面端：关闭搜索面板，在右侧显示聊天
            ref.read(desktopProfileProvider.notifier).state =
                DesktopProfileInfo.none;
            // 设置选中的聊天
            final chatType = typeStr == 'group'
                ? ChatType.group
                : (typeStr == 'channel' ? ChatType.channel : ChatType.private);
            ref.read(selectedChatInfoProvider.notifier).state =
                SelectedChatInfo(
              id: chatUuid,
              name: chatName,
              avatar: chatAvatar,
              chatType: chatType,
            );
            ref.read(selectedChatIdProvider.notifier).state = chatUuid;
            // TODO: 跳转到指定消息 (jump_to) 需要单独处理
          } else {
            context.pop();
            String url =
                '/chat/$chatUuid?name=${Uri.encodeComponent(chatName)}&type=$typeStr';
            if (messageId != null) {
              url += '&jump_to=$messageId';
            }
            context.push(url);
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            AvatarWidget(
              avatar: chatAvatar,
              name: chatName,
              size: 44,
              borderRadius: 12,
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
                          chatName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiaryFor(context),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                      children: [
                        if (senderName.isNotEmpty)
                          TextSpan(
                            text: '$senderName: ',
                            style: TextStyle(
                              color: AppColors.textSecondaryFor(context),
                            ),
                          ),
                        if (effectiveStart >= 0 &&
                            effectiveEnd <= displayText.length) ...[
                          TextSpan(
                              text: displayText.substring(0, effectiveStart)),
                          TextSpan(
                            text: displayText.substring(
                                effectiveStart, effectiveEnd),
                            style: TextStyle(
                              color: AppColors.linkFor(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(text: displayText.substring(effectiveEnd)),
                        ] else
                          TextSpan(text: displayText),
                      ],
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

  Widget _buildFileItem(api.GlobalSearchItem file, bool isDark) {
    final chatId = file.chatId;
    final chatName = file.chatName ?? file.subtitle;
    final messageId = file.messageId ?? file.id;
    final fileTitle =
        file.highlightText != null && file.highlightText!.isNotEmpty
            ? file.highlightText!
            : file.title;
    final chatTypeCode = file.chatType ?? 1;
    final selectedType = chatTypeCode == 2
        ? ChatType.group
        : (chatTypeCode == 3 ? ChatType.channel : ChatType.private);
    final routeType = chatTypeCode == 2
        ? 'group'
        : (chatTypeCode == 3 ? 'channel' : 'private');

    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.cardFor(context),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(
          Icons.insert_drive_file_outlined,
          color: AppColors.primaryFor(context),
        ),
      ),
      title: RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: _highlightSpans(
            fileTitle,
            file.highlightStart,
            file.highlightEnd,
            TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
            TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.linkFor(context),
            ),
          ),
        ),
      ),
      subtitle: Text(
        chatName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: AppColors.textSecondaryFor(context),
          fontSize: 14,
        ),
      ),
      onTap: () {
        if (chatId == null || chatId.isEmpty) return;
        if (widget.isDesktopPanel) {
          ref.read(desktopProfileProvider.notifier).state =
              DesktopProfileInfo.none;
          ref.read(selectedChatInfoProvider.notifier).state = SelectedChatInfo(
            id: chatId,
            name: chatName,
            avatar: null,
            chatType: selectedType,
          );
          ref.read(selectedChatIdProvider.notifier).state = chatId;
          return;
        }
        context.pop();
        var url =
            '/chat/$chatId?name=${Uri.encodeComponent(chatName)}&type=$routeType';
        if (messageId.isNotEmpty) {
          url += '&jump_to=$messageId';
        }
        context.push(url);
      },
    );
  }

  List<TextSpan> _highlightSpans(
    String text,
    int? start,
    int? end,
    TextStyle normalStyle,
    TextStyle highlightStyle,
  ) {
    if (start == null ||
        end == null ||
        start < 0 ||
        end <= start ||
        start >= text.length ||
        end > text.length) {
      return [TextSpan(text: text, style: normalStyle)];
    }
    return [
      TextSpan(text: text.substring(0, start), style: normalStyle),
      TextSpan(text: text.substring(start, end), style: highlightStyle),
      TextSpan(text: text.substring(end), style: normalStyle),
    ];
  }
}
