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

  bool _isNumeric(String str) {
    return RegExp(r'^\d+$').hasMatch(str);
  }

  bool _isSearching = false;
  DateTime? _lastSearchTime;
  List<SearchResult> _allResults = [];
  String? _errorMessage;

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

    String searchKeyword = keyword.trim();

    // ★ 拦截控制：只有满 8 位及以上才发起真正的网络请求
    if (searchKeyword.length != 11) {
      setState(() {
        _allResults = [];
        _errorMessage = null;
        _isSearching = false;
      });
      return;
    }

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

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final response = await apiClient.get(
        '/user/search-all',
        queryParameters: {'keyword': searchKeyword, 'type': 'all'},
      );

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
      final chatType = result.type == 'group' ? 'group' : 'channel';
      context.push(
        '/chat/${result.id}?name=${Uri.encodeComponent(result.name)}&type=$chatType${result.avatar != null ? '&avatar=${Uri.encodeComponent(result.avatar!)}' : ''}',
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
          backgroundColor: AppColors.error,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('打开聊天失败，请重试'),
          backgroundColor: AppColors.error,
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
            backgroundColor: AppColors.error,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('添加失败，请重试'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));

    // ★ 提取并清洗当前的关键字长度，用于精细控制状态显隐
    String cleanKeyword = _searchController.text.trim();


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
          // 搜索框
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              focusNode: _focusNode,
              maxLength: 11,
              keyboardType: TextInputType.phone, 
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly
              ],
              decoration: InputDecoration(
                hintText: '请输入11位手机号',
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
              onChanged: (value) {
                String checkValue = value.trim();
                
                // ★ 如果用户退格删除导致长度不足 8 位，立即重置并刷新界面，移走旧列表
                if (checkValue.length < 11) {
                  setState(() {
                    _allResults = [];
                    _errorMessage = null;
                  });
                }
                
                // 防抖搜索
                if (checkValue.length == 11) {
                  Future.delayed(const Duration(milliseconds: 500), () {
                    if (_searchController.text == value) {
                      _search(_searchController.text);
                    }
                  });
                }
              },
              onSubmitted: _search,
            ),
          ),

          // 提示文字 (未输入，或输入的有效关键字数不足 8 位)
          if (cleanKeyword.length < 11)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.phone_android_rounded,
                      size: 80,
                      color: isDark ? Colors.white24 : Colors.black12,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      cleanKeyword.isEmpty
                          ? (l10n.get('search_user_to_chat') ?? '搜索用户手机号开始聊天')
                          : '请输入 11 位手机号 (${cleanKeyword.length}/11)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: cleanKeyword.isEmpty ? FontWeight.normal : FontWeight.w500,
                        color: cleanKeyword.isEmpty
                            ? (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary)
                            : AppColors.primary,
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
                    const SizedBox(height: 24),
                    // Text(
                    //   l10n.get('also_search_public_groups') ?? '也可搜索公开群组和频道',
                    //   style: TextStyle(
                    //     fontSize: 14,
                    //     color: isDark
                    //         ? AppColors.darkTextTertiary
                    //         : AppColors.lightTextTertiary,
                    //   ),
                    // ),
                  ],
                ),
              ),
            ),

          // 加载中 (满 8 位发起了异步请求时显示)
          if (_isSearching && cleanKeyword.length == 11)
            const Expanded(child: Center(child: CircularProgressIndicator())),

          // 错误信息 (满 8 位请求失败时显示)
          if (_errorMessage != null && !_isSearching && cleanKeyword.length == 11)
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

          // 搜索结果 - 只有满 8 位及以上才触发渲染
          if (!_isSearching &&
              _errorMessage == null && cleanKeyword.length == 11)
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