// 文件用途：实现 _ChatDetailRealtimeState 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailRealtimeState 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail realtime state 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailRealtimeState on _ChatDetailPageState {
  Future<void> _loadPinnedMessage() async {
    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.getPinnedMessage(widget.chatId);
      if (!mounted) return;
      if (!response.isSuccess) {
        debugPrint('[Pin] getPinnedMessage failed: ${response.message}');
        return;
      }

      final data = response.data;
      if (data is Map) {
        final pinnedData = Map<String, dynamic>.from(data);
        final id = _readPinnedMessageId(pinnedData);
        final text = _readPinnedMessageText(pinnedData);
        debugPrint('[Pin] Loaded pinned: id=$id, text=$text');
        _setPinnedMessage(messageId: id, messageText: text);
      } else if (data == null) {
        _clearPinnedMessage();
      }
    } catch (e) {
      debugPrint('[Pin] _loadPinnedMessage error: $e');
    }
  }

  void _setPinnedMessage({String? messageId, String? messageText}) {
    if (!mounted) return;

    final normalizedId = messageId?.trim();
    final normalizedText = messageText?.trim();
    final hasId = normalizedId != null && normalizedId.isNotEmpty;
    final hasText = normalizedText != null && normalizedText.isNotEmpty;

    _updateState(() {
      _pinnedMessageId = hasId ? normalizedId : null;
      _pinnedMessageText = hasId
          ? (hasText
              ? normalizedText
              : _localizedText(
                  zhCN: '[置顶消息]',
                  zhTW: '[置頂訊息]',
                  en: '[Pinned Message]',
                ))
          : null;
      _pinnedEntryIndex = 0;
      _pinnedStackDismissed = false;
    });
  }

  void _clearPinnedMessage() {
    if (!mounted) return;

    _updateState(() {
      _pinnedMessageId = null;
      _pinnedMessageText = null;
      _pinnedEntryIndex = 0;
    });
  }

  Future<void> _loadLatestAnnouncement() async {
    if (widget.chatType == ChatType.private) return;
    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.getAnnouncements(
        widget.chatId,
        page: 1,
        pageSize: 10,
      );
      if (!mounted) return;
      if (response.isSuccess && response.data != null) {
        final announcements = response.data!.list
            .where((item) => item.content.trim().isNotEmpty)
            .toList();
        _updateState(() {
          _announcements = announcements;
          _pinnedEntryIndex = 0;
          _pinnedStackDismissed = false;
        });
      }
    } catch (e) {
      debugPrint('[Announcement] _loadLatestAnnouncement error: $e');
    }
  }

  List<_PinnedEntry> get _pinnedEntries {
    final entries = <_PinnedEntry>[];
    final seen = <String>{};

    // 流程逻辑：`normalize` 集中处理输入规范化、空值和兼容字段，输出稳定的数据结构，避免调用方重复实现边界判断。
    String normalize(String value) =>
        value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

    for (final item in _announcements) {
      final content = item.content.trim();
      if (content.isEmpty) continue;
      final key = normalize(content);
      if (!seen.add(key)) continue;
      entries.add(
        _PinnedEntry(
          type: _PinnedEntryType.announcement,
          id: 'announcement:${item.id}',
          content: content,
        ),
      );
    }

    final pinnedText = _pinnedMessageText?.trim();
    if (pinnedText != null && pinnedText.isNotEmpty) {
      final key = normalize(pinnedText);
      if (seen.add(key)) {
        entries.add(
          _PinnedEntry(
            type: _PinnedEntryType.message,
            id: 'message:${_pinnedMessageId ?? pinnedText.hashCode}',
            content: pinnedText,
            messageId: _pinnedMessageId,
          ),
        );
      }
    }

    return entries;
  }

  _PinnedEntry? get _currentPinnedEntry {
    final entries = _pinnedEntries;
    if (entries.isEmpty) return null;
    final index = math.min(math.max(_pinnedEntryIndex, 0), entries.length - 1);
    return entries[index];
  }

  void _openPinnedEntry(_PinnedEntry entry) {
    if (entry.type == _PinnedEntryType.message && entry.messageId != null) {
      _scrollToMessage(entry.messageId!);
      return;
    }
    _showAnnouncementDetail(entry.content);
  }

  void _showAnnouncementDetail([String? explicitContent]) {
    final content = explicitContent ?? _currentPinnedEntry?.content;
    if (content == null || content.trim().isEmpty) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.push_pin_rounded,
                  size: 20,
                  color: Color(0xFF2481CC),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.chatType == ChatType.channel
                      ? _localizedText(
                          zhCN: '频道公告',
                          zhTW: '頻道公告',
                          en: 'Channel Announcement',
                        )
                      : _localizedText(
                          zhCN: '群公告',
                          zhTW: '群公告',
                          en: 'Group Announcement',
                        ),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SelectableText(
              content,
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPinnedEntryListSheet() {
    final entries = _pinnedEntries;
    if (entries.isEmpty) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final title = widget.chatType == ChatType.channel
            ? _localizedText(
                zhCN: '频道置顶消息',
                zhTW: '頻道置頂消息',
                en: 'Channel Pinned Messages',
              )
            : _localizedText(
                zhCN: '群置顶消息',
                zhTW: '群置頂消息',
                en: 'Group Pinned Messages',
              );
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.push_pin_rounded,
                      size: 18,
                      color: Color(0xFF2481CC),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.52,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 1,
                      color: isDark
                          ? Colors.white.withOpacity(0.08)
                          : const Color(0xFFE5E7EB),
                    ),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _AnnouncementSheetTile(
                        text: entry.content,
                        isSelected: index == _pinnedEntryIndex,
                        isDark: isDark,
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _updateState(() {
                            _pinnedEntryIndex = index;
                            _pinnedStackDismissed = false;
                          });
                          _openPinnedEntry(entry);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _readPinnedMessageId(Map<String, dynamic> data) {
    final raw = data['message_id'] ?? data['pinned_message_id'];
    final id = raw?.toString().trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  String? _readPinnedMessageText(Map<String, dynamic> data) {
    final raw = data['message_text'] ?? data['pinned_message_text'];
    final text = raw?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  String _buildPinnedMessagePreview(MessageItem message) {
    if (message.type == MessageItemType.forwardBundle) {
      return _localizedText(
        zhCN: '[聊天记录]',
        zhTW: '[聊天記錄]',
        en: '[Chat history]',
      );
    }
    final content = message.content.trim();
    if (content.isNotEmpty) {
      return content.length > 100 ? '${content.substring(0, 100)}...' : content;
    }

    switch (message.type) {
      case MessageItemType.image:
        return _localizedText(zhCN: '[图片]', zhTW: '[圖片]', en: '[Photo]');
      case MessageItemType.video:
        return _localizedText(zhCN: '[视频]', zhTW: '[影片]', en: '[Video]');
      case MessageItemType.voice:
      case MessageItemType.audio:
        return _localizedText(zhCN: '[语音]', zhTW: '[語音]', en: '[Voice]');
      case MessageItemType.file:
        final fileName = message.fileName?.trim();
        return (fileName != null && fileName.isNotEmpty)
            ? '${_localizedText(zhCN: '[文件]', zhTW: '[檔案]', en: '[File]')} $fileName'
            : _localizedText(zhCN: '[文件]', zhTW: '[檔案]', en: '[File]');
      case MessageItemType.sticker:
      case MessageItemType.gif:
        return _localizedText(zhCN: '[表情]', zhTW: '[表情]', en: '[Sticker]');
      case MessageItemType.location:
        return _localizedText(zhCN: '[位置]', zhTW: '[位置]', en: '[Location]');
      case MessageItemType.contact:
        return _localizedText(zhCN: '[名片]', zhTW: '[名片]', en: '[Contact]');
      case MessageItemType.poll:
        return _localizedText(zhCN: '[投票]', zhTW: '[投票]', en: '[Poll]');
      case MessageItemType.call:
        return _localizedText(zhCN: '[通话]', zhTW: '[通話]', en: '[Call]');
      case MessageItemType.redPacket:
        return _localizedText(zhCN: '[红包]', zhTW: '[紅包]', en: '[Red Packet]');
      case MessageItemType.transfer:
        return _localizedText(zhCN: '[转账]', zhTW: '[轉帳]', en: '[Transfer]');
      case MessageItemType.forwardBundle:
        return _localizedText(
          zhCN: '[聊天记录]',
          zhTW: '[聊天記錄]',
          en: '[Chat history]',
        );
      case MessageItemType.system:
        return _localizedText(
          zhCN: '[系统消息]',
          zhTW: '[系統訊息]',
          en: '[System Message]',
        );
      case MessageItemType.text:
        return _localizedText(zhCN: '[消息]', zhTW: '[訊息]', en: '[Message]');
    }
  }

  void _setupTypingListener() {
    _wsService = ref.read(webSocketServiceProvider.notifier);
    final myUserId = ref.read(authServiceProvider).user?.uuid;

    _typingHandlerId = _wsService!.registerHandler('typing', (data) {
      if (!mounted) return;

      final chatId = data['chat_id'] as String?;
      final userId = data['user_id'] as String?;
      final action = data['action'] as String?;

      // 只处理当前聊天的 typing 事件
      if (chatId != widget.chatId || userId == null) return;

      // 不处理自己的 typing 事件
      if (userId == myUserId) return;

      _updateState(() {
        if (action == 'start') {
          final userName = (data['user_name'] as String?)?.trim();
          final displayName =
              (userName != null && userName.isNotEmpty) ? userName : userId;
          // 重新插入以保证群聊里“最后输入的人”在 map 末尾。
          _typingUsers.remove(userId);
          _typingUsers[userId] = displayName;
          // 每个用户有独立的 8 秒超时 Timer，防止多人同时输入时互相取消
          _typingUserTimers[userId]?.cancel();
          _typingUserTimers[userId] = Timer(const Duration(seconds: 8), () {
            if (mounted) {
              _updateState(() {
                _typingUsers.remove(userId);
                _typingUserTimers.remove(userId);
              });
            }
          });
        } else {
          _typingUsers.remove(userId);
          _typingUserTimers[userId]?.cancel();
          _typingUserTimers.remove(userId);
        }
      });
    });

    _pinnedHandlerId = _wsService!.registerHandler(
      WSMessageType.messagePinned,
      (data) {
        if (!mounted || data is! Map) return;

        final event = Map<String, dynamic>.from(data);
        final chatId = event['chat_id']?.toString();
        if (chatId != widget.chatId) return;

        final id = _readPinnedMessageId(event);
        final text = _readPinnedMessageText(event);
        debugPrint('[Pin] WS message_pinned: id=$id, text=$text');

        if (id != null && id.isNotEmpty) {
          _setPinnedMessage(messageId: id, messageText: text);
        } else {
          _loadPinnedMessage();
        }
      },
    );

    _unpinnedHandlerId = _wsService!.registerHandler(
      WSMessageType.messageUnpinned,
      (data) {
        if (!mounted || data is! Map) return;

        final event = Map<String, dynamic>.from(data);
        final chatId = event['chat_id']?.toString();
        if (chatId != widget.chatId) return;

        _clearPinnedMessage();
      },
    );

    _reconnectedHandlerId = _wsService!.registerHandler(
      WSMessageType.reconnected,
      (_) {
        ref.invalidate(chatDetailProvider(widget.chatId));
        ref.invalidate(chatMembersProvider(widget.chatId));
        _loadPinnedMessage();
        _loadLatestAnnouncement();
        if (widget.chatType == ChatType.group) {
          _loadActiveMeeting();
        }
      },
    );

    _chatDissolvedHandlerId = _wsService!.registerHandler(
      'chat_dissolved',
      (data) {
        if (!mounted || data is! Map) return;
        final event = Map<String, dynamic>.from(data);
        if (event['chat_id']?.toString() != widget.chatId) return;

        unawaited(this._interruptVoiceRecording(reason: 'chat_dissolved'));
        _stopTyping();
        _inputController.clear();
        _pendingMentionIds.clear();
        ref.read(chatListProvider.notifier).updateDraft(widget.chatId, '');
        ref.invalidate(chatDetailProvider(widget.chatId));
        ref.invalidate(chatMembersProvider(widget.chatId));

        AppSnackBar.warning(
          context,
          _localizedText(
            zhCN: '该群聊已解散，已退出会话',
            zhTW: '該群聊已解散，已退出會話',
            en: 'This group was dissolved. The conversation has been closed.',
          ),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final navigator = Navigator.of(context);
          if (!widget.isDesktopMode && navigator.canPop()) {
            navigator.pop();
          } else {
            context.go('/home');
          }
        });
      },
    );

    _memberRoleChangedHandlerId = _wsService!.registerHandler(
      'member_role_changed',
      (data) {
        if (!mounted || data is! Map) return;
        final event = Map<String, dynamic>.from(data);
        if (event['chat_id']?.toString() != widget.chatId) return;
        ref.invalidate(chatDetailProvider(widget.chatId));
        ref.invalidate(chatMembersProvider(widget.chatId));
      },
    );

    _announcementHandlerId = _wsService!.registerHandler(
      WSMessageType.chatAnnouncement,
      (data) {
        if (!mounted || data is! Map) return;
        final event = Map<String, dynamic>.from(data);
        final chatId = event['chat_id']?.toString();
        if (chatId != widget.chatId) return;
        _loadLatestAnnouncement();
      },
    );

    _announcementUpdatedHandlerId = _wsService!.registerHandler(
      WSMessageType.chatAnnouncementUpdated,
      (data) {
        if (!mounted || data is! Map) return;
        final event = Map<String, dynamic>.from(data);
        final chatId = event['chat_id']?.toString();
        if (chatId != widget.chatId) return;
        _loadLatestAnnouncement();
      },
    );

    _announcementDeletedHandlerId = _wsService!.registerHandler(
      WSMessageType.chatAnnouncementDeleted,
      (data) {
        if (!mounted || data is! Map) return;
        final event = Map<String, dynamic>.from(data);
        final chatId = event['chat_id']?.toString();
        if (chatId != widget.chatId) return;
        _loadLatestAnnouncement();
      },
    );

    _meetingStartedHandlerId = _wsService!.registerHandler(
      WSMessageType.meetingStarted,
      _handleMeetingWsChanged,
    );
    _meetingEndedHandlerId = _wsService!.registerHandler(
      WSMessageType.meetingEnded,
      _handleMeetingWsChanged,
    );
    _meetingInviteHandlerId = _wsService!.registerHandler(
      WSMessageType.meetingInvite,
      _handleMeetingWsChanged,
    );
    _meetingTitleUpdatedHandlerId = _wsService!.registerHandler(
      WSMessageType.meetingTitleUpdated,
      _handleMeetingWsChanged,
    );
  }

  /// 输入变化时发送 typing 状态
}
