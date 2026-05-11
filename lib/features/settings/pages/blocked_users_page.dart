import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/api_client.dart';
import '../../../shared/widgets/avatar_widget.dart';

/// 已屏蔽用户页面
class BlockedUsersPage extends ConsumerStatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  ConsumerState<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends ConsumerState<BlockedUsersPage> {
  List<BlockedUser> _blockedUsers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    try {
      final api = ref.read(apiClientProvider);
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
            '${l10n.get('confirm_unblock') ?? '确定要解除对'} "${user.nickname}" ${l10n.get('unblock_suffix') ?? '的屏蔽吗？'}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child:
                Text(l10n.unblock, style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.delete('/user/blocked/${user.userId}');

      if (response.isSuccess) {
        setState(() {
          _blockedUsers.removeWhere((u) => u.userId == user.userId);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已解除对 "${user.nickname}" 的屏蔽')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(response.message)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('操作失败，请重试')),
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
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.get('blocked_users') ?? '已屏蔽用户',
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
            color: isDark ? Colors.white24 : Colors.black26,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.get('no_blocked_users') ?? '没有已屏蔽的用户',
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.get('blocked_users_hint') ?? '被屏蔽的用户将无法向你发送消息',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.white38 : Colors.black38,
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
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
            trailing: TextButton(
              onPressed: () => _unblockUser(user, l10n),
              child: Text(
                l10n.unblock,
                style: TextStyle(color: AppColors.primary),
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
