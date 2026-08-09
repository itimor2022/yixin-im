// 文件用途：实现 _SelectedForwardMode 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _SelectedForwardMode 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail selection actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
enum _SelectedForwardMode { separate, bundle }

extension _ChatDetailSelectionActions on _ChatDetailPageState {
  /// 转发选中的消息
  void _forwardSelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;

    // 获取选中的消息
    final messages = ref.read(messageListProvider(widget.chatId));
    final selectedMessages = orderMessagesForForward(
      messages.where((m) => _selectedMessageIds.contains(m.id)),
    );

    if (selectedMessages.isEmpty) return;
    if (!_canForwardFromCurrentChat ||
        selectedMessages.any((message) => message.burnAfterRead)) {
      _showForwardBlockedHint();
      return;
    }

    _showForwardModeDialog(selectedMessages);
  }

  Future<void> _showForwardModeDialog(List<MessageItem> messages) async {
    final mode = await showModalBottomSheet<_SelectedForwardMode>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.call_split_rounded),
              title: Text(_localizedText(
                zhCN: '逐条转发',
                zhTW: '逐則轉發',
                en: 'Forward separately',
              )),
              subtitle: Text(_localizedText(
                zhCN: '在目标会话中发送 ${messages.length} 条独立消息',
                zhTW: '在目標會話中傳送 ${messages.length} 則獨立訊息',
                en: 'Send ${messages.length} individual messages',
              )),
              onTap: () => Navigator.pop(
                context,
                _SelectedForwardMode.separate,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.library_books_outlined),
              title: Text(_localizedText(
                zhCN: '合并转发',
                zhTW: '合併轉發',
                en: 'Forward as chat history',
              )),
              subtitle: Text(_localizedText(
                zhCN: '合并为一条可打开的聊天记录',
                zhTW: '合併為一則可開啟的聊天記錄',
                en: 'Combine into one openable chat record',
              )),
              onTap: () => Navigator.pop(
                context,
                _SelectedForwardMode.bundle,
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (mode != null && mounted) {
      _showForwardDialogForMultiple(messages, mode: mode);
    }
  }

  /// 显示转发对话框（多选）
  void _showForwardDialogForMultiple(
    List<MessageItem> messages, {
    required _SelectedForwardMode mode,
  }) {
    if (!_canForwardFromCurrentChat ||
        messages.any((message) => message.burnAfterRead)) {
      _showForwardBlockedHint();
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedTargetIds = <String>{};
    var isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.68,
          minChildSize: 0.45,
          maxChildSize: 0.9,
          builder: (sheetContext, scrollController) => Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Consumer(
              builder: (context, ref, _) {
                final chatState = ref.watch(chatListProvider);
                final chats = [
                  ...chatState.pinnedChats,
                  ...chatState.regularChats,
                ].where((chat) => chat.id != widget.chatId).toList();

                // 流程逻辑：`submit` 先校验输入和当前权限，进入操作中状态后执行副作用；成功同步服务端结果，失败恢复可重试状态并保留错误原因。
                Future<void> submit() async {
                  if (selectedTargetIds.isEmpty ||
                      isSubmitting ||
                      _isForwardingMessages) {
                    return;
                  }
                  setSheetState(() => isSubmitting = true);
                  _isForwardingMessages = true;
                  try {
                    final selectedChats = chats
                        .where((chat) => selectedTargetIds.contains(chat.id))
                        .toList(growable: false);
                    final allowedTargetIds = <String>[];
                    final blockedTargetNames = <String>[];

                    for (final chat in selectedChats) {
                      var allowed = true;
                      if (chat.type == ChatItemType.group ||
                          chat.type == ChatItemType.channel) {
                        final detail = await ref.read(
                          chatDetailProvider(chat.id).future,
                        );
                        if (detail != null) {
                          allowed = !(chat.type == ChatItemType.channel &&
                                  detail.myRole < 2) &&
                              !(chat.type == ChatItemType.group &&
                                  !detail.canSendMessage &&
                                  detail.myRole < 2);
                        }
                      }
                      if (allowed) {
                        allowedTargetIds.add(chat.id);
                      } else {
                        blockedTargetNames.add(chat.name);
                      }
                    }

                    if (allowedTargetIds.isEmpty) {
                      if (sheetContext.mounted) {
                        setSheetState(() => isSubmitting = false);
                      }
                      if (mounted) {
                        _showTopToast(
                          _localizedText(
                            zhCN: '所选目标均无转发权限',
                            zhTW: '所選目標均無轉發權限',
                            en: 'None of the selected chats allow forwarding',
                          ),
                        );
                      }
                      return;
                    }

                    final notifier = ref.read(
                      messageListProvider(widget.chatId).notifier,
                    );
                    if (sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                    }
                    if (mounted) _exitSelectionMode();

                    var completeTargets = 0;
                    var failedMessages = 0;
                    if (mode == _SelectedForwardMode.bundle) {
                      final results = await forwardBundleToTargetsReliably(
                        allowedTargetIds,
                        (targetId, clientMsgId) =>
                            notifier.forwardBundleMessages(
                          messages.map((message) => message.id).toList(),
                          targetId,
                          clientMsgId: clientMsgId,
                        ),
                      );
                      completeTargets =
                          results.where((result) => result.succeeded).length;
                      failedMessages = results.length - completeTargets;
                    } else {
                      final results = await forwardMessagesToTargetsReliably(
                        messages,
                        allowedTargetIds,
                        (targetId, message, clientMsgId) =>
                            notifier.forwardMessage(
                          message.id,
                          targetId,
                          clientMsgId: clientMsgId,
                          sourceMessage: message,
                        ),
                      );
                      completeTargets =
                          results.where((result) => result.isComplete).length;
                      failedMessages = results.fold<int>(
                        0,
                        (total, result) =>
                            total + result.messages.failedMessageIds.length,
                      );
                    }

                    if (mounted) {
                      _showTopToast(
                        _localizedText(
                          zhCN: failedMessages == 0 &&
                                  blockedTargetNames.isEmpty
                              ? '已转发到 $completeTargets 个会话'
                              : '完成 $completeTargets/${selectedChats.length} 个会话，失败 $failedMessages 条，受限 ${blockedTargetNames.length} 个',
                          zhTW: failedMessages == 0 &&
                                  blockedTargetNames.isEmpty
                              ? '已轉發到 $completeTargets 個會話'
                              : '完成 $completeTargets/${selectedChats.length} 個會話，失敗 $failedMessages 則，受限 ${blockedTargetNames.length} 個',
                          en: failedMessages == 0 && blockedTargetNames.isEmpty
                              ? 'Forwarded to $completeTargets chats'
                              : '$completeTargets/${selectedChats.length} chats completed; $failedMessages messages failed; ${blockedTargetNames.length} restricted',
                        ),
                      );
                    }
                  } finally {
                    _isForwardingMessages = false;
                  }
                }

                return Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _localizedText(
                                zhCN: mode == _SelectedForwardMode.bundle
                                    ? '合并转发 ${messages.length} 条消息'
                                    : '逐条转发 ${messages.length} 条消息',
                                zhTW: mode == _SelectedForwardMode.bundle
                                    ? '合併轉發 ${messages.length} 則訊息'
                                    : '逐則轉發 ${messages.length} 則訊息',
                                en: mode == _SelectedForwardMode.bundle
                                    ? 'Combine ${messages.length} messages'
                                    : 'Forward ${messages.length} messages',
                              ),
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                          ),
                          Text(
                            _localizedText(
                              zhCN: '已选 ${selectedTargetIds.length}',
                              zhTW: '已選 ${selectedTargetIds.length}',
                              en: '${selectedTargetIds.length} selected',
                            ),
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: chats.length,
                        itemBuilder: (context, index) {
                          final chat = chats[index];
                          final selected = selectedTargetIds.contains(chat.id);
                          return ListTile(
                            leading: AvatarWidget(
                              avatar: chat.avatar,
                              name: chat.name,
                              size: 48,
                            ),
                            title: Text(
                              chat.name,
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            trailing: Checkbox(
                              value: selected,
                              onChanged: isSubmitting
                                  ? null
                                  : (_) => setSheetState(() {
                                        if (selected) {
                                          selectedTargetIds.remove(chat.id);
                                        } else {
                                          selectedTargetIds.add(chat.id);
                                        }
                                      }),
                            ),
                            onTap: isSubmitting
                                ? null
                                : () => setSheetState(() {
                                      if (selected) {
                                        selectedTargetIds.remove(chat.id);
                                      } else {
                                        selectedTargetIds.add(chat.id);
                                      }
                                    }),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: selectedTargetIds.isEmpty || isSubmitting
                              ? null
                              : submit,
                          child: Text(
                            isSubmitting
                                ? _localizedText(
                                    zhCN: '正在转发...',
                                    zhTW: '正在轉發...',
                                    en: 'Forwarding...',
                                  )
                                : _localizedText(
                                    zhCN: '转发到 ${selectedTargetIds.length} 个会话',
                                    zhTW: '轉發到 ${selectedTargetIds.length} 個會話',
                                    en: 'Forward to ${selectedTargetIds.length} chats',
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// 撤回消息
  Future<void> _revokeMessage(MessageItem message) async {
    if (!_ensureChatWritable()) return;
    GlobalHaptics.medium();

    final error = await ref
        .read(messageListProvider(widget.chatId).notifier)
        .revokeMessage(message.id);

    if (error != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(
              zhCN: error,
              zhTW: error,
              en: containsHanText(error) ? 'Failed to recall message' : error,
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void _reactToMessage(MessageItem message) => GlobalHaptics.light();

  /// 构建可选择的消息项
  Widget _buildSelectableMessage(
    MessageItem message,
    List<MessageItem> albumMessages,
    bool isFirstInGroup,
    bool isLastInGroup,
    BubbleColors bubbleColors,
    double messageFontSize,
    bool isDark,
  ) {
    final isSelected = _selectedMessageIds.contains(message.id);

    return GestureDetector(
      onTap: () => _toggleMessageSelection(message.id),
      child: Container(
        color: isSelected
            ? AppColors.primaryWithOpacity(context, isDark ? 0.15 : 0.1)
            : Colors.transparent,
        child: Row(
          children: [
            // 左侧选择框
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected
                      ? AppColors.primaryFor(context)
                      : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primaryFor(context)
                        : (isDark ? Colors.white38 : Colors.black26),
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),

            // 消息气泡
            Expanded(
              child: IgnorePointer(
                child: MessageBubble(
                  message: message,
                  albumMessages: albumMessages,
                  isFirstInGroup: isFirstInGroup,
                  isLastInGroup: isLastInGroup,
                  showSenderName: widget.chatType != ChatType.private &&
                      !message.isOutgoing,
                  customOutgoingColor: bubbleColors.outgoing,
                  customIncomingColor: bubbleColors.incoming,
                  messageFontSize: messageFontSize,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
