// 文件用途：实现 BlockedUsersPage 页面及其交互流程，属于应用设置。
// 核心逻辑：维护 BlockedUsersPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/api_client.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/themed_app_bar.dart';

String _blockedUsersText(
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

// 关键声明：blocked users page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// 已屏蔽用户页面
class BlockedUsersPage extends ConsumerStatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  ConsumerState<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends ConsumerState<BlockedUsersPage> {
  List<BlockedUser> _blockedUsers = [];
  bool _isLoading = true;

  String _serverMessage({
    required String? raw,
    required String zhCN,
    String? zhTW,
    required String en,
  }) {
    return localizeServerMessage(
      raw,
      fallbackZhCN: zhCN,
      fallbackZhTW: zhTW,
      fallbackEn: en,
    );
  }

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    try {
      final api = ref.read(apiClientProvider);
      // 屏蔽关系以服务端列表为准，页面不从联系人缓存推断关系状态。
      final response = await api.get<Map<String, dynamic>>('/user/blocked');

      if (response.isSuccess && response.data != null) {
        final list = response.data!['list'] as List? ?? [];
        _blockedUsers = list.map((e) => BlockedUser.fromJson(e)).toList();
      }
    } catch (e) {
      debugPrint('[BlockedUsers] Load error: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _unblockUser(BlockedUser user, AppLocalizations l10n) async {
    HapticFeedback.mediumImpact();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.unblock),
        content: Text(
          '${l10n.get('confirm_unblock') ?? _blockedUsersText(context, zhCN: '确定要解除对', zhTW: '確定要解除對', en: 'Unblock')} "${user.nickname}" ${l10n.get('unblock_suffix') ?? _blockedUsersText(context, zhCN: '的屏蔽吗？', zhTW: '的封鎖嗎？', en: '?')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              l10n.unblock,
              style: TextStyle(color: AppColors.linkFor(context)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.delete('/user/blocked/${user.userId}');

      if (response.isSuccess) {
        // 服务端确认解除后再移除本地条目，失败时保留原关系状态。
        setState(() {
          _blockedUsers.removeWhere((u) => u.userId == user.userId);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _blockedUsersText(
                  context,
                  zhCN: '已解除对 "${user.nickname}" 的屏蔽',
                  zhTW: '已解除對 "${user.nickname}" 的封鎖',
                  en: 'Unblocked "${user.nickname}"',
                ),
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _serverMessage(
                  raw: response.message,
                  zhCN: '操作失败，请重试',
                  zhTW: '操作失敗，請重試',
                  en: 'Operation failed. Please try again.',
                ),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _blockedUsersText(
                context,
                zhCN: '操作失败，请重试',
                zhTW: '操作失敗，請重試',
                en: 'Operation failed, please try again',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D1117) : const Color(0xFFF2F2F7),
      appBar: ThemedAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.get('blocked_users') ??
              _blockedUsersText(
                context,
                zhCN: '已屏蔽用户',
                zhTW: '已封鎖使用者',
                en: 'Blocked Users',
              ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _blockedUsers.isEmpty
              ? _buildEmptyState(isDark, l10n)
              : _buildList(isDark, l10n),
    );
  }

  Widget _buildEmptyState(bool isDark, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.block_outlined,
            size: 64,
            color: AppColors.textTertiaryFor(context).withOpacity(0.72),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.get('no_blocked_users') ??
                _blockedUsersText(
                  context,
                  zhCN: '没有已屏蔽的用户',
                  zhTW: '沒有已封鎖的使用者',
                  en: 'No blocked users',
                ),
            style: TextStyle(
              fontSize: 16,
              color: AppColors.textSecondaryFor(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.get('blocked_users_hint') ??
                _blockedUsersText(
                  context,
                  zhCN: '被屏蔽的用户将无法向你发送消息',
                  zhTW: '被封鎖的使用者將無法向你發送訊息',
                  en: 'Blocked users cannot send messages to you',
                ),
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiaryFor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(bool isDark, AppLocalizations l10n) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemCount: _blockedUsers.length,
      itemBuilder: (context, index) {
        final user = _blockedUsers[index];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: AvatarWidget(
              avatar: user.avatar,
              name: user.nickname,
              userId: user.id,
              size: 48,
            ),
            title: Text(
              user.nickname,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            subtitle: Text(
              '@${user.username}',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textTertiaryFor(context),
              ),
            ),
            trailing: TextButton(
              onPressed: () => _unblockUser(user, l10n),
              child: Text(
                l10n.unblock,
                style: TextStyle(color: AppColors.linkFor(context)),
              ),
            ),
          ),
        );
      },
    );
  }
}

class BlockedUser {
  final String id;
  final String userId;
  final String username;
  final String nickname;
  final String? avatar;

  BlockedUser({
    required this.id,
    required this.userId,
    required this.username,
    required this.nickname,
    this.avatar,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> json) {
    final avatar = ApiConfig.getMediaUrl(json['avatar']?.toString());
    return BlockedUser(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ??
          json['blocked_user_id']?.toString() ??
          '',
      username: json['username'] ?? '',
      nickname: json['nickname'] ?? json['username'] ?? '',
      avatar: avatar.isEmpty ? null : avatar,
    );
  }
}
