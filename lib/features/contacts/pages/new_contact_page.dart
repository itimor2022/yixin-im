import 'package:universal_io/io.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/api_client.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../../shared/widgets/premium_widgets.dart';
import '../providers/contact_provider.dart';
import '../../chat/providers/chat_provider.dart' show chatListProvider;
import '../../home/pages/home_desktop_page.dart';

/// 统一搜索结果
class SearchResult {
  final String id;
  final String name;
  final String? username;
  final String? avatar;
  final String? bio;
  final String type; // user, group, channel
  final int memberCount;
  final bool isMember; // 是否已加入/订阅
  final String? nicknameColor;
  final String? emojiAvatar;
  final String? premiumType;

  SearchResult({
    required this.id,
    required this.name,
    this.username,
    this.avatar,
    this.bio,
    required this.type,
    this.memberCount = 0,
    this.isMember = false,
    this.nicknameColor,
    this.emojiAvatar,
    this.premiumType,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    // 转换头像 URL
    String? avatarUrl = json['avatar'];
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
    }

    return SearchResult(
      id: json['id'] ?? '',
      name: json['name'] ?? json['nickname'] ?? '',
      username: json['username'],
      avatar: avatarUrl,
      bio: json['bio'],
      type: json['type'] ?? 'user',
      memberCount: json['member_count'] ?? 0,
      isMember: json['is_member'] ?? false,
      nicknameColor: json['nickname_color'],
      emojiAvatar: json['emoji_avatar'],
      premiumType: json['premium_type'],
    );
  }
}

class NewContactPage extends ConsumerStatefulWidget {
  final bool isDesktopPanel; // 是否作为桌面右侧面板显示

  const NewContactPage({super.key, this.isDesktopPanel = false});

  @override
  ConsumerState<NewContactPage> createState() => _NewContactPageState();
}

class _NewContactPageState extends ConsumerState<NewContactPage> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  bool _isSearching = false;
  bool _hasSearched = false;
  DateTime? _lastSearchTime;
  List<SearchResult> _allResults = [];
  String? _errorMessage;

  /// 允许搜索的最小字符数：防止空关键字或过短触发全表扫描。
  /// 后端 `/user/search-all` 会做同样校验（<2 直接 400），两边保持一致。
  static const int _minKeywordLength = 2;

  @override
  void initState() {
    super.initState();
    // 自动聚焦搜索框
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search(String keyword) async {
    final searchKeyword = keyword.trim();

    // 空关键字：清空结果回到初始态，不请求后端
    if (searchKeyword.isEmpty) {
      setState(() {
        _allResults = [];
        _errorMessage = null;
        _isSearching = false;
        _hasSearched = false;
      });
      return;
    }

    // 关键字过短：轻提示，不请求后端
    if (searchKeyword.length < _minKeywordLength) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请至少输入 $_minKeywordLength 个字符再搜索'),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    // 3 秒频控，防止误触 / 表单回车狂按
    final now = DateTime.now();
    if (_lastSearchTime != null) {
      final difference = now.difference(_lastSearchTime!).inSeconds;
      if (difference < 3) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('操作过于频繁，请在 ${3 - difference} 秒后重试'),
            duration: const Duration(seconds: 1),
            backgroundColor: AppColors.error,
          ),
        );
        return;
      }
    }
    _lastSearchTime = now;

    // 收起软键盘，聚焦搜索结果
    FocusScope.of(context).unfocus();

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _hasSearched = true;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.get(
        '/user/search-all',
        queryParameters: {'keyword': searchKeyword, 'type': 'all'},
      );

      if (!mounted) return;

      if (response.code == 0 && response.data != null) {
        final list = response.data['list'] as List? ?? [];
        setState(() {
          _allResults = list
              .map((json) => SearchResult.fromJson(json))
              .toList();
          _isSearching = false;
        });
      } else {
        setState(() {
          _errorMessage = response.message;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '搜索失败，请重试';
        _isSearching = false;
      });
    }
  }

  void _openResult(SearchResult result) {
    // 桌面端不触发震动
    if (Platform.isIOS || Platform.isAndroid) {
      HapticFeedback.selectionClick();
    }

    if (kDebugMode) debugPrint(
      '[NewContact] Opening result: ${result.name}, type: ${result.type}',
    );

    if (result.type == 'user') {
      context.push(
        '/user/${result.id}?name=${Uri.encodeComponent(result.name)}${result.avatar != null ? '&avatar=${Uri.encodeComponent(result.avatar!)}' : ''}',
      );
    } else {
      context.push(
        '/chat/${result.id}?name=${Uri.encodeComponent(result.name)}&type=group${result.avatar != null ? '&avatar=${Uri.encodeComponent(result.avatar!)}' : ''}',
      );
    }
  }

  Future<void> _startChat(SearchResult user) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post(
        '/chat/create',
        data: {
          'type': 1, // 私聊
          'member_ids': [user.id],
        },
      );

      if (!mounted) return;

      if (response.code == 0 && response.data != null) {
        final chatId = response.data['uuid'] as String?;
        if (chatId != null) {
          ref.read(chatListProvider.notifier).refresh();
          context.push(
            '/chat/$chatId?name=${Uri.encodeComponent(user.name)}&type=private${user.avatar != null ? '&avatar=${Uri.encodeComponent(user.avatar!)}' : ''}',
          );
          return;
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(response.message),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('打开聊天失败，请重试'),
        ),
      );
    }
  }

  void _addContact(SearchResult user) async {
    if (Platform.isIOS || Platform.isAndroid) {
      HapticFeedback.mediumImpact();
    }

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.post(
        '/contact/add',
        data: {'user_id': user.id},
      );

      if (!mounted) return;

      if (response.code == 0) {
        ref.read(contactListProvider.notifier).loadFromServer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('好友申请已发送，等待 ${user.name} 验证'),
            backgroundColor: AppColors.success,
          ),
        );
      } else if (response.message == '已经是联系人') {
        ref.read(contactListProvider.notifier).loadFromServer();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${user.name} 已在联系人中'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response.message),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('添加失败，请重试'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));

    final cleanKeyword = _searchController.text.trim();
    final canSearch = cleanKeyword.length >= _minKeywordLength && !_isSearching;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.darkBackground
          : AppColors.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark
            ? AppColors.darkBackground
            : AppColors.lightBackground,
        surfaceTintColor: Colors.transparent,
        leading: widget.isDesktopPanel
            ? IconButton(
                icon: Icon(
                  Icons.arrow_back_ios,
                  size: 20,
                  color: AppColors.primary,
                ),
                onPressed: () {
                  ref.read(desktopProfileProvider.notifier).state =
                      DesktopProfileInfo.none;
                },
              )
            : null,
        title: Text(l10n.search),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 搜索框 + 搜索按钮
          // ⚠️ 不再限制位数和字符类型：允许字母、数字、中文等任意关键字；
          //    也不再随输入自动触发；改由「搜索按钮」或键盘 Enter (onSubmitted) 手动触发。
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _focusNode,
                    keyboardType: TextInputType.text,
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText: l10n.get('search_user_group_channel') ??
                          '请输入手机号 / 用户名 / 昵称',
                      hintStyle: TextStyle(
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary,
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              tooltip: '清空',
                              onPressed: () {
                                _searchController.clear();
                                _search('');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withOpacity(0.08)
                          : Colors.black.withOpacity(0.04),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                    // 输入变化只用于刷新清空按钮 / 按钮 enable 状态；不再自动触发搜索
                    onChanged: (value) {
                      if (value.trim().isEmpty && _hasSearched) {
                        setState(() {
                          _allResults = [];
                          _errorMessage = null;
                          _hasSearched = false;
                        });
                      } else {
                        setState(() {});
                      }
                    },
                    // 键盘回车键触发搜索
                    onSubmitted: _search,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: canSearch
                      ? () => _search(_searchController.text)
                      : null,
                  icon: _isSearching
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.search, size: 18),
                  label: const Text('搜索'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 初始态：未搜索过时显示引导文案
          if (!_hasSearched && !_isSearching)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_search_rounded,
                      size: 80,
                      color: isDark ? Colors.white24 : Colors.black12,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.get('search_user_to_chat') ?? '搜索用户开始聊天',
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.get('no_need_add_friend') ?? '无需添加好友，直接发起私聊',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : AppColors.lightTextTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 加载中
          if (_isSearching)
            const Expanded(child: Center(child: CircularProgressIndicator())),

          // 错误信息
          if (_errorMessage != null && !_isSearching)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 60, color: AppColors.error),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        fontSize: 16,
                        color: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 搜索结果
          if (_hasSearched && !_isSearching && _errorMessage == null)
            Expanded(
              child: _allResults.isEmpty
                  ? _buildEmptyState(isDark)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _allResults.length,
                      itemBuilder: (context, index) {
                        final result = _allResults[index];
                        return _SearchResultTile(
                          result: result,
                          onTap: () => _openResult(result),
                          onAddContact: result.type == 'user'
                              ? () => _addContact(result)
                              : null,
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 60,
            color: isDark ? Colors.white24 : Colors.black12,
          ),
          const SizedBox(height: 16),
          Text(
            '未找到相关结果',
            style: TextStyle(
              fontSize: 16,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '请检查输入是否正确',
            style: TextStyle(
              fontSize: 14,
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
          ),
        ),
      ],
    ),
  );
}
}

class _SearchResultTile extends StatelessWidget {
  final SearchResult result;
  final VoidCallback onTap;
  final VoidCallback? onAddContact;

  const _SearchResultTile({
    required this.result,
    required this.onTap,
    this.onAddContact,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // 头像
            Stack(
              children: [
                AvatarWidget(
                  avatar: result.avatar,
                  name: result.name,
                  size: 52,
                  premiumType: result.premiumType,
                ),
                if (result.type != 'user')
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkBackground : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        result.type == 'group' ? Icons.group : Icons.campaign,
                        size: 14,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(width: 12),

            // 信息
            Expanded(
              child: PremiumContainer(
                premiumType: result.type == 'user' ? result.premiumType : null,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal:
                        result.type == 'user' &&
                            result.premiumType?.isNotEmpty == true
                        ? 8
                        : 0,
                    vertical:
                        result.type == 'user' &&
                            result.premiumType?.isNotEmpty == true
                        ? 6
                        : 0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: result.type == 'user'
                                ? ColoredNameWidget(
                                    name: result.name,
                                    nicknameColor: result.nicknameColor,
                                    premiumType: result.premiumType,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    defaultColor: isDark
                                        ? AppColors.darkTextPrimary
                                        : AppColors.lightTextPrimary,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : Text(
                                    result.name,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? AppColors.darkTextPrimary
                                          : AppColors.lightTextPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                          if (result.type == 'user' &&
                              result.emojiAvatar != null &&
                              result.emojiAvatar!.isNotEmpty) ...[
                            const SizedBox(width: 4),
                            EmojiStatusWidget(
                              emoji: result.emojiAvatar!,
                              size: 18,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      if (result.username != null &&
                          result.username!.isNotEmpty)
                        Text(
                          '@${result.username}',
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.primary,
                          ),
                        ),
                      if (result.type != 'user' && result.memberCount > 0)
                        Text(
                          result.type == 'group'
                              ? '${result.memberCount} 位成员'
                              : '${result.memberCount} 订阅者',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.lightTextTertiary,
                          ),
                        ),
                      if (result.bio != null && result.bio!.isNotEmpty)
                        Text(
                          result.bio!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.lightTextTertiary,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(width: 8),

            // 操作按钮
            if (result.type == 'user')
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: const Text('聊天'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  if (onAddContact != null) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: onAddContact,
                      icon: const Icon(Icons.person_add_outlined),
                      tooltip: '添加到通讯录',
                      style: IconButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.white.withOpacity(0.1)
                            : Colors.black.withOpacity(0.05),
                        foregroundColor: isDark
                            ? AppColors.darkTextSecondary
                            : AppColors.lightTextSecondary,
                      ),
                    ),
                  ],
                ],
              )
            else if (result.isMember)
              Icon(
                Icons.chevron_right,
                color: isDark
                    ? AppColors.darkTextTertiary
                    : AppColors.lightTextTertiary,
              )
            else
              FilledButton(
                onPressed: onTap,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(result.type == 'group' ? '加入' : '订阅'),
              ),
          ],
        ),
      ),
    );
  }
}