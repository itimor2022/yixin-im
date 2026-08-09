// 文件用途：实现 MessageDetailPage 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 MessageDetailPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/time_zone_refresh_service.dart';
import '../providers/message_provider.dart';
import '../services/message_detail_service.dart';

// 关键声明：message detail page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class MessageDetailPage extends StatefulWidget {
  final MessageItem message;
  final MessageDetailService service;

  const MessageDetailPage({
    super.key,
    required this.message,
    required this.service,
  });

  @override
  State<MessageDetailPage> createState() => _MessageDetailPageState();
}

class _MessageDetailPageState extends State<MessageDetailPage> {
  MessageDetailData? _detail;
  String? _error;
  bool _loading = true;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.service.fetch(
        chatId: widget.message.chatId,
        messageId: widget.message.id,
      );
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = _text(
            zhCN: '服务器详情暂不可用，以下仅显示本机已知信息',
            zhTW: '伺服器詳情暫不可用，以下僅顯示本機已知資訊',
            en: 'Server details are unavailable. Showing local data only.',
          ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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

  String _formatTime(DateTime value) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(toCurrentLocalTime(value));

  String _statusLabel(String status) {
    switch (status) {
      case 'read':
        return _text(zhCN: '已读', zhTW: '已讀', en: 'Read');
      case 'delivered':
        return _text(zhCN: '已送达', zhTW: '已送達', en: 'Delivered');
      case 'sending':
        return _text(zhCN: '发送中', zhTW: '傳送中', en: 'Sending');
      default:
        return _text(zhCN: '已发送', zhTW: '已傳送', en: 'Sent');
    }
  }

  String get _localStatus {
    switch (widget.message.status) {
      case MessageStatus.read:
        return 'read';
      case MessageStatus.delivered:
        return 'delivered';
      case MessageStatus.sending:
        return 'sending';
      case MessageStatus.failed:
        return 'failed';
      case MessageStatus.sent:
        return 'sent';
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    final receipts = detail?.receipts;
    return Scaffold(
      appBar: AppBar(
        title: Text(_text(zhCN: '消息详情', zhTW: '訊息詳情', en: 'Message details')),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: Text(_error!),
                  trailing: IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              ),
            _InfoCard(
              children: [
                _InfoRow(
                  label: _text(zhCN: '发送时间', zhTW: '傳送時間', en: 'Sent at'),
                  value: _formatTime(
                      detail?.createdAt ?? widget.message.createdAt),
                ),
                _InfoRow(
                  label: _text(zhCN: '消息状态', zhTW: '訊息狀態', en: 'Status'),
                  value: _statusLabel(detail?.status ?? _localStatus),
                ),
                _InfoRow(
                  label: _text(zhCN: '消息序号', zhTW: '訊息序號', en: 'Sequence'),
                  value: '${detail?.seq ?? widget.message.seq}',
                ),
                if ((detail?.editedAt ?? widget.message.editedAt) != null)
                  _InfoRow(
                    label: _text(zhCN: '编辑时间', zhTW: '編輯時間', en: 'Edited at'),
                    value: _formatTime(
                      detail?.editedAt ?? widget.message.editedAt!,
                    ),
                  ),
              ],
            ),
            if (receipts != null) ...[
              const SizedBox(height: 12),
              _InfoCard(
                children: [
                  _InfoRow(
                    label: _text(zhCN: '接收人数', zhTW: '接收人數', en: 'Recipients'),
                    value: '${receipts.recipientCount}',
                  ),
                  _InfoRow(
                    label: _text(zhCN: '已读', zhTW: '已讀', en: 'Read'),
                    value: '${receipts.readCount}',
                  ),
                  _InfoRow(
                    label: _text(zhCN: '未读', zhTW: '未讀', en: 'Unread'),
                    value: '${receipts.unreadCount}',
                  ),
                  _InfoRow(
                    label: _text(zhCN: '已送达', zhTW: '已送達', en: 'Delivered'),
                    value: receipts.deliveryCountKnown
                        ? '${receipts.deliveredCount}'
                        : _text(
                            zhCN: '群聊暂不提供精确人数',
                            zhTW: '群聊暫不提供精確人數',
                            en: 'Exact group count unavailable',
                          ),
                  ),
                ],
              ),
              if (!receipts.canViewMembers)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _text(
                      zhCN: '为保护成员隐私，你只能查看汇总数据。',
                      zhTW: '為保護成員隱私，你只能查看彙總資料。',
                      en: 'Member identities are hidden to protect privacy.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (receipts.canViewMembers && receipts.members.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  _text(zhCN: '成员状态', zhTW: '成員狀態', en: 'Member status'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                ...receipts.members.map(
                  (member) => Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(
                          member.nickname.isEmpty
                              ? '?'
                              : member.nickname.characters.first,
                        ),
                      ),
                      title: Text(member.nickname.isEmpty
                          ? member.userId
                          : member.nickname),
                      subtitle: Text(
                        member.isRead
                            ? _text(zhCN: '已读', zhTW: '已讀', en: 'Read')
                            : member.deliveredKnown && member.isDelivered
                                ? _text(
                                    zhCN: '已送达', zhTW: '已送達', en: 'Delivered')
                                : _text(zhCN: '未读', zhTW: '未讀', en: 'Unread'),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(children: children),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
