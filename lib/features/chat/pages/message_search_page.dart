// 文件用途：实现 MessageSearchPage 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 MessageSearchPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/chat_service.dart' as api;
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/avatar_widget.dart';

// 关键声明：message search page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class MessageSearchPage extends ConsumerStatefulWidget {
  final String? chatId;
  final String? targetUserId;
  final String chatName;
  final String chatType;
  final bool returnSelection;

  const MessageSearchPage({
    super.key,
    this.chatId,
    this.targetUserId,
    required this.chatName,
    required this.chatType,
    this.returnSelection = false,
  }) : assert(chatId != null || targetUserId != null);

  @override
  ConsumerState<MessageSearchPage> createState() => _MessageSearchPageState();
}

class _MessageSearchPageState extends ConsumerState<MessageSearchPage> {
  final _searchController = TextEditingController();
  List<api.SearchMessageItem> _results = [];
  List<api.ChatMember> _members = [];
  String? _resolvedChatId;
  String? _senderId;
  int? _messageType;
  DateTimeRange? _dateRange;
  bool _isSearching = false;
  String _lastQuery = '';
  int _searchRequest = 0;

  bool get _hasFilters =>
      _senderId != null || _messageType != null || _dateRange != null;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _resolveChat();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _resolveChat() async {
    var chatId = widget.chatId;
    if (chatId == null || chatId.isEmpty) {
      final targetUserId = widget.targetUserId;
      if (targetUserId == null || targetUserId.isEmpty) return;
      try {
        final response = await ref.read(apiClientProvider).post(
          '/chat/create',
          data: {
            'type': 1,
            'member_ids': [targetUserId],
          },
        );
        chatId = response.data?['uuid']?.toString();
      } catch (_) {
        return;
      }
    }
    if (!mounted || chatId == null || chatId.isEmpty) return;
    setState(() => _resolvedChatId = chatId);
    await _loadMembers(chatId);
  }

  Future<void> _loadMembers(String chatId) async {
    try {
      final response =
          await ref.read(api.chatServiceProvider).getMembers(chatId);
      if (!mounted) return;
      setState(() => _members = response.data ?? []);
    } catch (_) {}
  }

  Future<void> _search(String rawQuery) async {
    final chatId = _resolvedChatId;
    final query = rawQuery.trim();
    final request = ++_searchRequest;
    if (chatId == null || (query.isEmpty && !_hasFilters)) {
      if (!mounted) return;
      setState(() {
        _results = [];
        _lastQuery = '';
        _isSearching = false;
      });
      return;
    }

    _lastQuery = query;
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted || _lastQuery != query || request != _searchRequest) return;
    setState(() => _isSearching = true);

    try {
      final range = _dateRange;
      final response = await ref.read(api.chatServiceProvider).searchMessages(
            chatId,
            query,
            senderId: _senderId,
            messageType: _messageType,
            startAt: range == null
                ? null
                : DateTime(
                    range.start.year, range.start.month, range.start.day),
            endAt: range == null
                ? null
                : DateTime(range.end.year, range.end.month, range.end.day)
                    .add(const Duration(days: 1)),
          );
      if (!mounted || _lastQuery != query || request != _searchRequest) return;
      setState(() {
        _isSearching = false;
        _results = response.data?.list ?? [];
      });
    } catch (_) {
      if (!mounted || request != _searchRequest) return;
      setState(() {
        _isSearching = false;
        _results = [];
      });
    }
  }

  String _memberLabel() {
    if (_senderId == null) {
      return _text(zhCN: '联系人', zhTW: '聯絡人', en: 'Sender');
    }
    for (final member in _members) {
      if (member.userId == _senderId) return member.displayName;
    }
    return _text(zhCN: '联系人', zhTW: '聯絡人', en: 'Sender');
  }

  String _messageTypeLabel(int? type) {
    switch (type) {
      case 1:
        return _text(zhCN: '文字', en: 'Text');
      case 2:
        return _text(zhCN: '图片', zhTW: '圖片', en: 'Image');
      case 3:
        return _text(zhCN: '视频', zhTW: '影片', en: 'Video');
      case 4:
        return _text(zhCN: '语音', zhTW: '語音', en: 'Voice');
      case 5:
        return _text(zhCN: '文件', zhTW: '檔案', en: 'File');
      default:
        return _text(zhCN: '类型', zhTW: '類型', en: 'Type');
    }
  }

  String _dateLabel() {
    final range = _dateRange;
    if (range == null) return _text(zhCN: '日期', en: 'Date');
    String format(DateTime value) =>
        '${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    return '${format(range.start)} - ${format(range.end)}';
  }

  Future<void> _selectSender() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: Text(_text(
                zhCN: '全部联系人',
                zhTW: '全部聯絡人',
                en: 'All senders',
              )),
              trailing: _senderId == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, '__all__'),
            ),
            for (final member in _members)
              ListTile(
                leading: AvatarWidget(
                  avatar: member.avatar,
                  name: member.displayName,
                  size: 36,
                ),
                title: Text(member.displayName),
                trailing:
                    _senderId == member.userId ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, member.userId),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _senderId = selected == '__all__' ? null : selected);
    await _search(_searchController.text);
  }

  Future<void> _selectMessageType() async {
    const types = <int>[1, 2, 3, 4, 5];
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.category_outlined),
              title: Text(_text(zhCN: '全部类型', zhTW: '全部類型', en: 'All types')),
              trailing: _messageType == null ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(context, 0),
            ),
            for (final type in types)
              ListTile(
                title: Text(_messageTypeLabel(type)),
                trailing: _messageType == type ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, type),
              ),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    setState(() => _messageType = selected == 0 ? null : selected);
    await _search(_searchController.text);
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange: _dateRange,
    );
    if (!mounted || selected == null) return;
    setState(() => _dateRange = selected);
    await _search(_searchController.text);
  }

  Future<void> _clearFilters() async {
    setState(() {
      _senderId = null;
      _messageType = null;
      _dateRange = null;
    });
    await _search(_searchController.text);
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    if (date.year == now.year) {
      return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    }
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _openMessage(api.SearchMessageItem result) {
    if (widget.returnSelection) {
      Navigator.pop(context, result);
      return;
    }
    final chatId = _resolvedChatId;
    if (chatId == null) return;
    context.push(
      '/chat/$chatId?name=${Uri.encodeComponent(widget.chatName)}&type=${widget.chatType}&messageId=${Uri.encodeComponent(result.id)}&messageSeq=${result.seq}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = AppColors.surfaceFor(context);
    final cardColor = AppColors.cardFor(context);

    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            size: 20,
            color: AppColors.primaryFor(context),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _text(zhCN: '搜索消息', zhTW: '搜尋訊息', en: 'Search Messages'),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimaryFor(context),
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            color: surface,
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.inputBackgroundFor(context),
                borderRadius: BorderRadius.circular(8),
              ),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: _text(
                    zhCN: '在 ${widget.chatName} 中搜索',
                    zhTW: '在 ${widget.chatName} 中搜尋',
                    en: 'Search in ${widget.chatName}',
                  ),
                  hintStyle: TextStyle(color: AppColors.inputHintFor(context)),
                  prefixIcon: Icon(Icons.search,
                      color: AppColors.inputIconFor(context)),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          tooltip: _text(zhCN: '清空', en: 'Clear'),
                          icon: Icon(Icons.clear,
                              color: AppColors.inputIconFor(context)),
                          onPressed: () {
                            _searchController.clear();
                            _search('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                style: TextStyle(
                    fontSize: 17, color: AppColors.textPrimaryFor(context)),
                onChanged: _search,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            color: surface,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    avatar: const Icon(Icons.person_outline, size: 18),
                    label: Text(_memberLabel()),
                    selected: _senderId != null,
                    onSelected: (_) => _selectSender(),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    avatar: const Icon(Icons.date_range_outlined, size: 18),
                    label: Text(_dateLabel()),
                    selected: _dateRange != null,
                    onSelected: (_) => _selectDateRange(),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    avatar: const Icon(Icons.filter_alt_outlined, size: 18),
                    label: Text(_messageTypeLabel(_messageType)),
                    selected: _messageType != null,
                    onSelected: (_) => _selectMessageType(),
                  ),
                  if (_hasFilters) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: _text(
                          zhCN: '清除筛选', zhTW: '清除篩選', en: 'Clear filters'),
                      onPressed: _clearFilters,
                      icon: const Icon(Icons.filter_alt_off_outlined),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Text(
                          _searchController.text.isEmpty && !_hasFilters
                              ? _text(
                                  zhCN: '输入关键词或选择筛选条件',
                                  zhTW: '輸入關鍵字或選擇篩選條件',
                                  en: 'Enter keywords or choose filters',
                                )
                              : _text(
                                  zhCN: '未找到相关消息',
                                  zhTW: '找不到相關訊息',
                                  en: 'No matching messages found',
                                ),
                          style: TextStyle(
                              color: AppColors.textSecondaryFor(context)),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          return Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 4),
                            decoration: BoxDecoration(
                              color: cardColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListTile(
                              leading: AvatarWidget(
                                avatar: result.senderAvatar,
                                name: result.senderName ?? '',
                                size: 40,
                              ),
                              title: Text(
                                result.senderName?.isNotEmpty == true
                                    ? result.senderName!
                                    : _text(
                                        zhCN: '未知用户',
                                        zhTW: '未知用戶',
                                        en: 'Unknown user'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                result.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                _formatDate(result.createdAt),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade600,
                                ),
                              ),
                              onTap: () => _openMessage(result),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
