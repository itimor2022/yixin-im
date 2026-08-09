// 文件用途：实现 FriendRequestsPage 页面及其交互流程，属于联系人。
// 核心逻辑：维护 FriendRequestsPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../providers/contact_provider.dart';

// 关键声明：friend requests page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class FriendRequestsPage extends ConsumerStatefulWidget {
  const FriendRequestsPage({super.key});

  @override
  ConsumerState<FriendRequestsPage> createState() => _FriendRequestsPageState();
}

class _FriendRequestsPageState extends ConsumerState<FriendRequestsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  List<FriendRequestItem> _incoming = const [];
  List<FriendRequestItem> _outgoing = const [];

  String _text({required String zhCN, String? zhTW, required String en}) {
    switch (AppLocalizations.of(context).language) {
      case AppLanguage.en:
        return en;
      case AppLanguage.zhTW:
        return zhTW ?? zhCN;
      case AppLanguage.zhCN:
        return zhCN;
    }
  }

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final notifier = ref.read(contactListProvider.notifier);
    // 收件箱和发件箱并行回源；本页数据不依赖 WebSocket 事件缓存。
    final results = await Future.wait([
      notifier.loadFriendRequests(box: 'incoming'),
      notifier.loadFriendRequests(box: 'outgoing'),
    ]);
    if (!mounted) return;
    setState(() {
      _incoming = results[0];
      _outgoing = results[1];
      _loading = false;
    });
    ref
        .read(pendingFriendRequestCountProvider.notifier)
        .syncFromIncoming(_incoming);
  }

  Future<void> _review(FriendRequestItem request, bool accept) async {
    final success = await ref
        .read(contactListProvider.notifier)
        .reviewFriendRequest(request.id, accept: accept);
    if (!mounted) return;
    if (success) {
      // 审核时申请可能已过期或被其他端处理，成功后重新加载两侧列表和角标。
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? _text(
                    zhCN: '已接受好友申请',
                    zhTW: '已接受好友申請',
                    en: 'Friend request accepted',
                  )
                : _text(
                    zhCN: '已拒绝好友申请',
                    zhTW: '已拒絕好友申請',
                    en: 'Friend request rejected',
                  ),
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              zhCN: '操作失败，申请可能已处理或过期',
              zhTW: '操作失敗，申請可能已處理或過期',
              en: 'Action failed. The request may be processed or expired.',
            ),
          ),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  String _statusText(String status) {
    switch (status) {
      case 'accepted':
        return _text(zhCN: '已接受', zhTW: '已接受', en: 'Accepted');
      case 'rejected':
        return _text(zhCN: '已拒绝', zhTW: '已拒絕', en: 'Rejected');
      case 'expired':
        return _text(zhCN: '已过期', zhTW: '已過期', en: 'Expired');
      default:
        return _text(zhCN: '待处理', zhTW: '待處理', en: 'Pending');
    }
  }

  Widget _requestList(List<FriendRequestItem> requests,
      {required bool incoming}) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (requests.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.55,
              child: Center(
                child: Text(
                  _text(
                    zhCN: '暂无好友申请',
                    zhTW: '暫無好友申請',
                    en: 'No friend requests',
                  ),
                  style: TextStyle(color: AppColors.textSecondaryFor(context)),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: requests.length,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
        itemBuilder: (context, index) {
          final request = requests[index];
          return ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: AvatarWidget(
              avatar: request.user.avatar,
              name: request.user.name,
              size: 48,
              userId: request.user.uuid ?? request.user.id,
            ),
            title: Text(
              request.user.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              request.message.isNotEmpty
                  ? request.message
                  : _text(
                      zhCN: '请求添加你为好友',
                      zhTW: '請求加你為好友',
                      en: 'Wants to add you as a friend',
                    ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: incoming && request.isPending
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: _text(zhCN: '拒绝', zhTW: '拒絕', en: 'Reject'),
                        onPressed: () => _review(request, false),
                        icon: const Icon(Icons.close),
                      ),
                      IconButton.filled(
                        tooltip: _text(zhCN: '接受', zhTW: '接受', en: 'Accept'),
                        onPressed: () => _review(request, true),
                        icon: const Icon(Icons.check),
                      ),
                    ],
                  )
                : Text(
                    _statusText(request.status),
                    style: TextStyle(
                      color: request.status == 'accepted'
                          ? AppColors.success
                          : AppColors.textSecondaryFor(context),
                    ),
                  ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _text(zhCN: '新的朋友', zhTW: '新的朋友', en: 'Friend Requests'),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: _text(zhCN: '收到的', zhTW: '收到的', en: 'Incoming')),
            Tab(text: _text(zhCN: '发出的', zhTW: '發出的', en: 'Outgoing')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _requestList(_incoming, incoming: true),
          _requestList(_outgoing, incoming: false),
        ],
      ),
    );
  }
}
