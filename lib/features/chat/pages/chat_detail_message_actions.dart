// 文件用途：实现 _ChatDetailMessageActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailMessageActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail message actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMessageActions on _ChatDetailPageState {
  VoidCallback? _buildMessageTapHandler(MessageItem message) {
    if (!message.shouldHideBurnContent) {
      if (message.type == MessageItemType.call &&
          widget.chatType == ChatType.private) {
        return () => _redialFromCallMessage(message);
      }
      return null;
    }
    return () {
      final seconds = ref
          .read(messageListProvider(widget.chatId).notifier)
          .revealBurnMessage(message.id);
      if (seconds == null || !mounted) {
        return;
      }
      AppSnackBar.info(
        context,
        _localizedText(
          zhCN: '已查看阅后即焚消息，$seconds 秒后自动销毁',
          zhTW: '已查看閱後即焚訊息，$seconds 秒後自動銷毀',
          en: 'Burn-after-read message opened. It will self-destruct in $seconds second(s).',
        ),
      );
    };
  }

  // 流程逻辑：`_redialFromCallMessage` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  void _redialFromCallMessage(MessageItem message) {
    final content = message.content.toLowerCase();
    final isVideoCall = content.contains('视频') ||
        content.contains('視訊') ||
        content.contains('video');
    this._startCall(isVideoCall ? CallType.video : CallType.voice);
  }

  /// 发红包
  void _showMessageOptions(MessageItem message, Offset tapPosition) {
    // 判断是否是媒体/文件类型消息（用于桌面端显示文件操作）
    final isMediaMessage = message.type == MessageItemType.image ||
        message.type == MessageItemType.video ||
        message.type == MessageItemType.file ||
        message.type == MessageItemType.voice;
    final isDesktop = PlatformUtils.isPhysicalDesktop;

    // 从后端配置获取撤回时间限制
    final revokeMinutes =
        ref.read(systemSettingsProvider).valueOrNull?.revokeMessageMinutes ?? 2;
    final chatDetail = ref.read(chatDetailProvider(widget.chatId)).valueOrNull;
    final isWritable = chatDetail?.status != 2;
    debugPrint(
      '[Chat] revokeMinutes from server: $revokeMinutes, message age: ${DateTime.now().difference(message.createdAt).inMinutes} min',
    );
    final canSelfRevoke = message.isOutgoing &&
        isWithinMessageRevokeWindow(
          createdAt: message.createdAt,
          now: DateTime.now(),
          revokeMinutes: revokeMinutes,
        );
    final canAdminRevoke = widget.chatType == ChatType.group &&
        (chatDetail?.myRole ?? 0) >= 2 &&
        !message.isDeleted &&
        message.type != MessageItemType.system;
    final canRevoke = canSelfRevoke || canAdminRevoke;
    final canCancelPending =
        message.isOutgoing && message.status == MessageStatus.sending;
    final isExpiredSelfMessage = message.isOutgoing &&
        !canSelfRevoke &&
        !canAdminRevoke &&
        message.status != MessageStatus.sending &&
        !message.isDeleted &&
        message.type != MessageItemType.system;

    showMessageContextMenu(
      context: context,
      message: message,
      isOutgoing: message.isOutgoing,
      tapPosition: tapPosition,
      showSenderName:
          widget.chatType != ChatType.private && !message.isOutgoing,
      onReaction:
          isWritable ? (emoji) => _handleReaction(message, emoji) : null,
      onReply: isWritable && !message.burnAfterRead
          ? () => _handleReply(message)
          : null,
      onCopy: () => _handleCopy(message),
      onTranslate: _canTranslateMessage(message)
          ? () => _handleTranslateMessage(message)
          : null,
      onForward:
          _canForwardMessage(message) ? () => _handleForward(message) : null,
      onFavorite: _canFavoriteMessage(message)
          ? () => _toggleFavoriteMessage(message)
          : null,
      onDetails: !message.isDeleted && !message.burnAfterRead && message.seq > 0
          ? () => _openMessageDetails(message)
          : null,
      onReport: !message.isOutgoing &&
              !message.isDeleted &&
              message.type != MessageItemType.system &&
              message.id.isNotEmpty &&
              message.seq > 0
          ? () => _openMessageReport(message)
          : null,
      onEdit:
          isWritable && message.isOutgoing ? () => _handleEdit(message) : null,
      onDelete: () => _handleDelete(message),
      onRevoke: !isWritable
          ? null
          : canRevoke || canCancelPending
              ? () => this._revokeMessage(message)
              : isExpiredSelfMessage
                  ? () => AppSnackBar.info(
                        context,
                        _localizedText(
                          zhCN: '已超过撤回时限（$revokeMinutes分钟）',
                          zhTW: '已超過撤回時限（$revokeMinutes分鐘）',
                          en: 'The $revokeMinutes-minute recall window has expired.',
                        ),
                      )
                  : null,
      revokeLabel: isExpiredSelfMessage
          ? _localizedText(
              zhCN: '撤回（已超过$revokeMinutes分钟）',
              zhTW: '撤回（已超過$revokeMinutes分鐘）',
              en: 'Recall window expired',
            )
          : null,
      onPin: (isWritable &&
              widget.chatType != ChatType.private &&
              ((chatDetail?.myRole ?? 0) >= 2 ||
                  (chatDetail?.canPinMessages ?? false)))
          ? () => _handlePinMessage(message)
          : null,
      onSelect: () => _enterSelectionMode(message),
      // 桌面端文件操作
      onSaveAs:
          isDesktop && isMediaMessage ? () => _handleSaveAs(message) : null,
      onShowInFolder: isDesktop && isMediaMessage
          ? () => _handleShowInFolder(message)
          : null,
      onOpenFile: isDesktop && message.type == MessageItemType.file
          ? () => _handleOpenFile(message)
          : null,
    );
  }

  void _openMessageReport(MessageItem message) {
    final senderName = message.senderName.trim().isEmpty
        ? _localizedText(
            zhCN: '未知用户',
            zhTW: '未知用戶',
            en: 'Unknown user',
          )
        : message.senderName.trim();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ReportPage(
          targetId: message.id,
          targetType: 'message',
          targetName: _localizedText(
            zhCN: '$senderName 发送的消息',
            zhTW: '$senderName 傳送的訊息',
            en: 'Message from $senderName',
          ),
          chatId: widget.chatId,
        ),
      ),
    );
  }

  /// 处理置顶消息
  Future<void> _handlePinMessage(MessageItem message) async {
    if (!_ensureChatWritable()) return;
    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.pinMessage(widget.chatId, message.id);
      if (!mounted) return;

      if (response.isSuccess) {
        String pinnedMessageId = message.id;
        String pinnedMessageText = this._buildPinnedMessagePreview(message);
        final data = response.data;
        debugPrint(
          '[Pin] pinMessage response data type: ${data.runtimeType}, value: $data',
        );
        if (data is Map) {
          final pinnedData = Map<String, dynamic>.from(data);
          pinnedMessageId =
              this._readPinnedMessageId(pinnedData) ?? pinnedMessageId;
          pinnedMessageText =
              this._readPinnedMessageText(pinnedData) ?? pinnedMessageText;
        }

        debugPrint(
          '[Pin] Setting pinned: id=$pinnedMessageId, text=$pinnedMessageText',
        );
        this._setPinnedMessage(
          messageId: pinnedMessageId,
          messageText: pinnedMessageText,
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              _localizedText(
                zhCN: '消息已置顶',
                zhTW: '訊息已置頂',
                en: 'Message pinned',
              ),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _displayServerMessage(
                raw: response.message,
                zhCN: '置顶失败',
                zhTW: '置頂失敗',
                en: 'Failed to pin message',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              _localizedText(
                zhCN: '置顶失败',
                zhTW: '置頂失敗',
                en: 'Failed to pin message. Please try again.',
              ),
            ),
          ),
        );
      }
    }
  }

  /// 处理表情回复
  void _handleReaction(MessageItem message, String emoji) async {
    if (!_ensureChatWritable()) return;
    GlobalHaptics.light();

    // 获取当前用户名
    final authState = ref.read(authServiceProvider);
    final userName = authState.user?.nickname ?? '';

    // 检查是否已经回复过这个表情
    final existingReaction = message.reactions
        .where(
          (r) => r.userId == (authState.user?.uuid ?? '') && r.emoji == emoji,
        )
        .isNotEmpty;

    bool success;
    if (existingReaction) {
      // 已回复，则移除
      success = await ref
          .read(messageListProvider(widget.chatId).notifier)
          .removeReaction(message.id, emoji);
    } else {
      // 未回复，则添加
      success = await ref
          .read(messageListProvider(widget.chatId).notifier)
          .addReaction(message.id, emoji, userName);
    }

    if (mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _localizedText(
              zhCN: '操作失败',
              zhTW: '操作失敗',
              en: 'Action failed',
            ),
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// 处理回复消息
  void _handleReply(MessageItem message) {
    if (!_ensureChatWritable()) return;
    if (message.burnAfterRead) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '阅后即焚消息不支持引用',
          zhTW: '閱後即焚訊息不支援引用',
          en: 'Burn-after-read messages cannot be quoted',
        ),
      );
      return;
    }
    GlobalHaptics.selection();
    _updateState(() {
      _replyToMessage = message;
      _editingMessage = null;
    });
    _inputFocusNode.requestFocus();
  }

  /// 取消回复
  void _cancelReply() {
    _updateState(() => _replyToMessage = null);
  }

  /// 处理复制消息
  void _handleCopy(MessageItem message) {
    String textToCopy = message.content;

    // 根据消息类型获取可复制的内容
    if (message.type == MessageItemType.text) {
      textToCopy = message.content;
    } else if (message.type == MessageItemType.file) {
      textToCopy = message.fileName ?? message.content;
    }

    Clipboard.setData(ClipboardData(text: textToCopy));
    GlobalHaptics.light();
  }
}
