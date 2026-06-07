import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../providers/contact_provider.dart';
import '../providers/friend_request_provider.dart';

/// 新的朋友 — 待验证好友申请列表
class FriendRequestsPage extends ConsumerStatefulWidget {
  const FriendRequestsPage({super.key});

  @override
  ConsumerState<FriendRequestsPage> createState() => _FriendRequestsPageState();
}

class _FriendRequestsPageState extends ConsumerState<FriendRequestsPage> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;
  final Set<String> _processing = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list =
        await ref.read(contactListProvider.notifier).getFriendRequests();
    if (!mounted) return;
    setState(() {
      _requests = list;
      _loading = false;
    });
    // 看过申请后清掉红点
    ref.read(friendRequestProvider.notifier).clear();
  }

  Future<void> _accept(Map<String, dynamic> req) async {
    final id = req['request_id'].toString();
    if (_processing.contains(id)) return;
    setState(() => _processing.add(id));
    final ok =
        await ref.read(contactListProvider.notifier).acceptFriendRequest(id);
    if (!mounted) return;
    setState(() => _processing.remove(id));
    if (ok) {
      setState(() => _requests.removeWhere(
          (r) => r['request_id'].toString() == id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已通过好友申请')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('操作失败，请重试')),
      );
    }
  }

  Future<void> _reject(Map<String, dynamic> req) async {
    final id = req['request_id'].toString();
    if (_processing.contains(id)) return;
    setState(() => _processing.add(id));
    final ok =
        await ref.read(contactListProvider.notifier).rejectFriendRequest(id);
    if (!mounted) return;
    setState(() => _processing.remove(id));
    if (ok) {
      setState(() => _requests.removeWhere(
          (r) => r['request_id'].toString() == id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('新的朋友'),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _requests.isEmpty
              ? Center(
                  child: Text(
                    '暂无好友申请',
                    style: TextStyle(
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : const Color(0xFF8E8E93),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    itemCount: _requests.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, thickness: 0.5),
                    itemBuilder: (context, i) {
                      final r = _requests[i];
                      final id = r['request_id'].toString();
                      final name = (r['from_name'] ?? '') as String;
                      final avatar = r['from_avatar'] as String?;
                      final remark = (r['remark'] ?? '') as String;
                      final busy = _processing.contains(id);
                      return ListTile(
                        leading: AvatarWidget(
                          avatar: avatar,
                          name: name,
                          size: 44,
                        ),
                        title: Text(name,
                            style:
                                const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: remark.isNotEmpty
                            ? Text('备注：$remark',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)
                            : null,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: busy ? null : () => _reject(r),
                              child: const Text('拒绝',
                                  style: TextStyle(color: Color(0xFF8E8E93))),
                            ),
                            const SizedBox(width: 4),
                            ElevatedButton(
                              onPressed: busy ? null : () => _accept(r),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                visualDensity: VisualDensity.compact,
                              ),
                              child: const Text('同意'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
