// 文件用途：实现 _ChatDetailPageFlow 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailPageFlow 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail page flow 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailPageFlow on _ChatDetailPageState {
  // 流程逻辑：`_cleanupOnExit` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  void _cleanupOnExit() {
    // 防止重复执行（back button 和 PopScope 会双重触发）
    if (_hasCleanedUp || !mounted) return;
    _hasCleanedUp = true;
    // 标记不再活跃，停止发送已读回执
    ref.read(messageListProvider(widget.chatId).notifier).setActive(false);
    // 清除活跃聊天 ID
    ref.read(chatListProvider.notifier).setActiveChatId(null);
    // 离开前再做一次幂等持久化，覆盖进入页面时短暂断网的情况。
    unawaited(_persistReadState());
  }

  /// 同时清除本地和服务端未读状态。
  ///
  /// 消息列表加载完成后还会携带精确 msg_seq 上报已读游标；这里不依赖
  /// 消息列表是否有内容，确保“手动标为未读”或本地历史为空的会话也能
  /// 在服务端清掉 unread_count，避免重新登录后旧的 1 再次出现。
  Future<void> _persistReadState() async {
    ref.read(chatListProvider.notifier).markAsRead(widget.chatId);
    try {
      final response =
          await ref.read(api.chatServiceProvider).markAsRead(widget.chatId);
      if (!response.isSuccess) {
        debugPrint(
          '[ChatDetail] Failed to persist read state: '
          'chatId=${widget.chatId} code=${response.code}',
        );
      }
    } catch (error) {
      debugPrint(
        '[ChatDetail] Persist read state error: '
        'chatId=${widget.chatId} error=$error',
      );
    }
  }

  /// 处理返回按钮点击
  void _handleBackButton() {
    _cleanupOnExit();
    Navigator.of(context).pop();
  }

  void _onScroll() {
    if (!mounted) return;

    final showButton = _scrollController.offset > 200;
    if (showButton != _showScrollToBottom) {
      _updateState(() => _showScrollToBottom = showButton);
    }

    // 键盘收起防抖：滚动 300ms 后才收起，避免频繁触发
    if (_inputFocusNode.hasFocus) {
      _keyboardDismissTimer?.cancel();
      _keyboardDismissTimer = Timer(const Duration(milliseconds: 300), () {
        if (_inputFocusNode.hasFocus && mounted) {
          _inputFocusNode.unfocus();
        }
      });
    }

    // 分页加载：接近顶部时加载更多（列表是 reverse 的，所以是 maxScrollExtent）
    if (_scrollController.hasClients && !_isLoadingMore) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      // 距离顶部 500 像素时开始加载
      if (maxScroll - currentScroll < 500) {
        _loadMoreMessages();
      }
    }
  }

  /// 加载更多历史消息
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    try {
      await ref
          .read(messageListProvider(widget.chatId).notifier)
          .loadMoreMessages();
    } finally {
      _isLoadingMore = false;
    }
  }

  /// 收起键盘和表情选择器
  void _dismissKeyboardAndEmoji() {
    // 收起键盘
    if (_inputFocusNode.hasFocus) {
      _inputFocusNode.unfocus();
    }
    // 收起表情选择器
    if (_showEmojiPickerState) {
      _updateState(() => _showEmojiPickerState = false);
    }
    if (_showAttachmentPickerState) {
      _updateState(() => _showAttachmentPickerState = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// 滚动到指定消息（用于点击回复预览时跳转）
  Future<void> _scrollToMessage(String messageId, {int? targetSeq}) async {
    final found = await ref
        .read(messageListProvider(widget.chatId).notifier)
        .ensureMessageLoaded(messageId, targetSeq: targetSeq);
    if (!mounted) return;

    final messages = ref.read(messageListProvider(widget.chatId));
    final index = messages.indexWhere((m) => m.id == messageId);

    if (!found || index == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _translate(
              context,
              'message_not_in_current_view',
              _localizedText(
                zhCN: '消息不在当前视图中',
                zhTW: '消息不在目前視圖中',
                en: 'The message is not in the current view',
              ),
            ),
          ),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    _scrollMessageIntoView(messageId);
  }

  void _scrollMessageIntoView(String messageId, {int retries = 8}) {
    if (!mounted) return;

    final key = _messageKeys[messageId];
    final targetContext = key?.currentContext;
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      _highlightMessage(messageId);
      return;
    }

    if (retries <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(
              zhCN: '暂时无法定位到这条消息',
              zhTW: '暫時無法定位到這則訊息',
              en: 'Unable to locate this message for now',
            ),
          ),
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 80), () {
        if (mounted) {
          _scrollMessageIntoView(messageId, retries: retries - 1);
        }
      });
    });
  }

  /// 高亮显示目标消息

  void _highlightMessage(String messageId) {
    _updateState(() => _highlightedMessageId = messageId);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _updateState(() => _highlightedMessageId = null);
      }
    });
  }
}
