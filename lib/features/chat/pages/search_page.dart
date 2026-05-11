import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:isar/isar.dart';
import 'package:lpinyin/lpinyin.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/services/storage/models/message_model.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../../shared/widgets/premium_widgets.dart';
import '../providers/chat_provider.dart';
import '../../contacts/providers/contact_provider.dart';
import '../../home/pages/home_desktop_page.dart';
import 'chat_detail_page.dart' show ChatType;
import '../../../core/services/storage/isar_service.dart';

class SearchPage extends ConsumerStatefulWidget {
  final bool isDesktopPanel; // 是否作为桌面右侧面板显示
  
  const SearchPage({
    super.key,
    this.isDesktopPanel = false,
  });

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  List<Map<String, dynamic>> _messageResults = [];
  String _lastSearchedQuery = '';

  @override
  void initState() {
    super.initState();
    // 自动聚焦搜索框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _searchFocusNode.requestFocus();
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
    });
  }

  Future<void> _searchMessages() async {
    if (_searchQuery.isEmpty) {
      setState(() => _messageResults = []);
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
  }

  Future<List<Map<String, dynamic>>> _searchLocalMessages(String keyword) async {
    if (PlatformUtils.isWeb) return [];
    if (!IsarService.instance.isAvailable) return [];

    try {
      final messages = await IsarService.instance.isar.messageModels
          .filter()
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
          'chat_type': chat?.type == 'private' ? 1 : (chat?.type == 'group' ? 2 : 3),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final chatState = ref.watch(chatListProvider);
    final allChats = [...chatState.pinnedChats, ...chatState.regularChats];
    final contacts = ref.watch(contactListProvider);

    // 过滤聊天列表
    final filteredChats = _searchQuery.isEmpty
        ? <ChatItem>[]
        : allChats.where((c) {
            final query = _searchQuery.toLowerCase();
            final nameLower = c.name.toLowerCase();
            final pinyin = PinyinHelper.getPinyin(c.name, separator: '').toLowerCase();
            final firstLetters = PinyinHelper.getShortPinyin(c.name).toLowerCase();
            return nameLower.contains(query) ||
                pinyin.contains(query) ||
                firstLetters.contains(query);
          }).toList();

    // 过滤联系人
    final filteredContacts = _searchQuery.isEmpty
        ? <ContactItem>[]
        : contacts.where((c) {
            final query = _searchQuery.toLowerCase();
            final nameLower = c.name.toLowerCase();
            final usernameLower = (c.username ?? '').toLowerCase();
            final bioLower = (c.bio ?? '').toLowerCase();
            final pinyin = PinyinHelper.getPinyin(c.name, separator: '').toLowerCase();
            final firstLetters = PinyinHelper.getShortPinyin(c.name).toLowerCase();
            return nameLower.contains(query) ||
                usernameLower.contains(query) ||
                bioLower.contains(query) ||
                pinyin.contains(query) ||
                firstLetters.contains(query);
          }).toList();

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
        elevation: 0,
        leadingWidth: 0,
        leading: const SizedBox.shrink(),
        titleSpacing: 16,
        title: Container(
          height: 36,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.1) : const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(10),
          ),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: _onSearchChanged,
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black,
            ),
            decoration: InputDecoration(
              hintText: l10n.search,
              hintStyle: TextStyle(
                color: isDark ? AppColors.darkTextTertiary : const Color(0xFF8E8E93),
              ),
              prefixIcon: Icon(
                Icons.search,
                size: 20,
                color: isDark ? AppColors.darkTextTertiary : const Color(0xFF8E8E93),
              ),
              suffixIcon: _searchController.text.isNotEmpty
                  ? GestureDetector(
                      onTap: _clearSearch,
                      child: Icon(
                        Icons.cancel,
                        size: 18,
                        color: isDark ? AppColors.darkTextTertiary : const Color(0xFF8E8E93),
                      ),
                    )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (widget.isDesktopPanel) {
                ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo.none;
              } else {
                context.pop();
              }
            },
            child: Text(
              l10n.cancel,
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: _searchQuery.isEmpty
          ? _buildEmptyState(isDark, l10n)
          : ListView(
              children: [
                // 聊天
                if (filteredChats.isNotEmpty) ...[
                  _buildSectionHeader(l10n.tabChat, isDark),
                  ...filteredChats.take(5).map((chat) => _buildChatItem(chat, isDark)),
                ],
                // 联系人
                if (filteredContacts.isNotEmpty) ...[
                  _buildSectionHeader(l10n.tabContacts, isDark),
                  ...filteredContacts.take(5).map((contact) => _buildContactItem(contact, isDark)),
                ],
                // 聊天记录
                if (_messageResults.isNotEmpty) ...[
                  _buildSectionHeader(l10n.get('chat_history') ?? '聊天记录', isDark),
                  ..._messageResults.map((msg) => _buildMessageItem(msg, isDark)),
                ],
                // 无结果
                if (filteredChats.isEmpty && filteredContacts.isEmpty && _messageResults.isEmpty)
                  _buildNoResults(isDark, l10n),
              ],
            ),
    );
  }

  Widget _buildEmptyState(bool isDark, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: isDark ? Colors.white24 : Colors.black12,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.get('search_chats_contacts_messages') ?? '搜索聊天、联系人和消息',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white38 : Colors.black38,
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
              color: isDark ? Colors.white24 : Colors.black12,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.get('no_search_results') ?? '无搜索结果',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white38 : Colors.black38,
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
          color: isDark ? Colors.white54 : Colors.black54,
        ),
      ),
    );
  }

  Widget _buildChatItem(ChatItem chat, bool isDark) {
    return ListTile(
      leading: AvatarWidget(
        avatar: chat.avatar,
        name: chat.name,
        userId: chat.type == ChatItemType.private
            ? (chat.targetUserId ?? chat.id)
            : chat.id,
        size: 44,
        premiumType: chat.premiumType,
      ),
      title: Row(
        children: [
          Expanded(
            child: ColoredNameWidget(
              name: chat.name,
              nicknameColor: chat.nicknameColor,
              premiumType: chat.premiumType,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              defaultColor: isDark ? Colors.white : Colors.black87,
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
      subtitle: (chat.lastMessage ?? '').isNotEmpty
          ? Text(
              chat.lastMessage ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black54,
                fontSize: 14,
              ),
            )
          : null,
      onTap: () {
        if (widget.isDesktopPanel) {
          // 桌面端：关闭搜索面板，在右侧显示聊天
          ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo.none;
          // 设置选中的聊天
          final chatType = chat.type == 'group' 
              ? ChatType.group 
              : (chat.type == 'channel' ? ChatType.channel : ChatType.private);
          ref.read(selectedChatInfoProvider.notifier).state = SelectedChatInfo(
            id: chat.id,
            name: chat.name,
            avatar: chat.avatar,
            chatType: chatType,
          );
          ref.read(selectedChatIdProvider.notifier).state = chat.id;
        } else {
          context.pop();
          context.push('/chat/${chat.id}?name=${Uri.encodeComponent(chat.name)}&type=${chat.type}');
        }
      },
    );
  }

  Widget _buildContactItem(ContactItem contact, bool isDark) {
    return ListTile(
      leading: AvatarWidget(
        avatar: contact.avatar,
        name: contact.name,
        userId: contact.id,
        size: 44,
        premiumType: contact.premiumType,
      ),
      title: Row(
        children: [
          Expanded(
            child: ColoredNameWidget(
              name: contact.name,
              nicknameColor: contact.nicknameColor,
              premiumType: contact.premiumType,
              fontSize: 16,
              fontWeight: FontWeight.w500,
              defaultColor: isDark ? Colors.white : Colors.black87,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (contact.emojiAvatar != null && contact.emojiAvatar!.isNotEmpty) ...[
            const SizedBox(width: 4),
            EmojiStatusWidget(
              emoji: contact.emojiAvatar!,
              size: 18,
            ),
          ],
        ],
      ),
      subtitle: contact.username != null
          ? Text(
              '@${contact.username}',
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
            name: contact.name,
            avatar: contact.avatar,
          );
        } else {
          context.pop();
          context.push('/user/${contact.uuid ?? contact.id}');
        }
      },
    );
  }

  Widget _buildMessageItem(Map<String, dynamic> msg, bool isDark) {
    final chatName = msg['chat_name'] as String? ?? '未知聊天';
    final chatAvatar = msg['chat_avatar'] as String? ?? '';
    final senderName = msg['sender_name'] as String? ?? '';
    final content = msg['content'] as Map<String, dynamic>? ?? {};
    final text = content['text'] as String? ?? '';
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
          timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        } else {
          timeStr = '${dt.month}/${dt.day}';
        }
      } catch (_) {}
    }

    // 高亮搜索词
    final query = _searchQuery.toLowerCase();
    final textLower = text.toLowerCase();
    final matchIndex = textLower.indexOf(query);

    return InkWell(
      onTap: () {
        if (chatUuid != null) {
          if (widget.isDesktopPanel) {
            // 桌面端：关闭搜索面板，在右侧显示聊天
            ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo.none;
            // 设置选中的聊天
            final chatType = typeStr == 'group' 
                ? ChatType.group 
                : (typeStr == 'channel' ? ChatType.channel : ChatType.private);
            ref.read(selectedChatInfoProvider.notifier).state = SelectedChatInfo(
              id: chatUuid,
              name: chatName,
              avatar: chatAvatar,
              chatType: chatType,
            );
            ref.read(selectedChatIdProvider.notifier).state = chatUuid;
            // TODO: 跳转到指定消息 (jump_to) 需要单独处理
          } else {
            context.pop();
            String url = '/chat/$chatUuid?name=${Uri.encodeComponent(chatName)}&type=$typeStr';
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
                            color: isDark ? Colors.white38 : Colors.black38,
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
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        if (matchIndex >= 0) ...[
                          TextSpan(text: text.substring(0, matchIndex)),
                          TextSpan(
                            text: text.substring(matchIndex, matchIndex + _searchQuery.length),
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          TextSpan(text: text.substring(matchIndex + _searchQuery.length)),
                        ] else
                          TextSpan(text: text),
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
}
