// 文件用途：实现 _ChatDetailInputComposer 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailInputComposer 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail input composer 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailInputComposer on _ChatDetailPageState {
  // 流程逻辑：`_buildInputWithPreview` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  /// 构建带回复/编辑预览的输入区域
  Widget _buildInputWithPreview(bool isDark) {
    final messageSettings = ref.watch(messageSettingsProvider);
    final systemSettings =
        ref.watch(systemSettingsProvider).valueOrNull ?? const SystemSettings();
    final burnAfterReadAllowed = systemSettings.burnAfterReadEnabled;
    final hasAttachmentActions = _hasAvailableAttachmentAction(systemSettings);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // @ 提及成员选择面板（群聊/频道）
        if (_mentionQuery != null && widget.chatType != ChatType.private)
          this._buildMentionPicker(isDark),

        // 待发送图片预览面板
        if (_pendingImages.isNotEmpty) _buildPendingImagesPanel(isDark),

        // 回复/编辑预览栏
        if (_replyToMessage != null || _editingMessage != null)
          _buildReplyEditPreview(isDark),

        if (burnAfterReadAllowed && _burnAfterReadEnabled)
          _buildBurnAfterReadBanner(isDark),

        if (_activeAnonymousSend) _buildAnonymousSendBanner(isDark),

        // 输入栏
        ChatInputBar(
          controller: _inputController,
          focusNode: _inputFocusNode,
          onSend: (text, {refocusInput}) =>
              _sendMessageWithContext(text, refocusInput: refocusInput ?? true),
          onAttachment:
              hasAttachmentActions ? this._showAttachmentOptions : null,
          onVoice: this._startVoiceRecord,
          onBurnAfterReadToggle: this._toggleBurnAfterRead,
          onAnonymousToggle: widget.chatType == ChatType.group
              ? this._toggleAnonymousSend
              : null,
          showEmojiPicker: _showEmojiPickerState,
          showAttachmentPicker:
              hasAttachmentActions && _showAttachmentPickerState,
          onEmojiToggle: this._toggleEmojiPicker,
          onInputTap: this._hideAttachmentPicker,
          allowBurnAfterRead: burnAfterReadAllowed,
          allowVoice: _canCurrentUserSendMedia,
          burnAfterReadEnabled: _burnAfterReadEnabled,
          allowAnonymous: _anonymousSendAllowed,
          anonymousEnabled: _activeAnonymousSend,
          hasPendingAttachments: _pendingImages.isNotEmpty,
          fontSize: messageSettings.fontSize,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 210),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          clipBehavior: Clip.hardEdge,
          child: hasAttachmentActions && _showAttachmentPickerState
              ? this._buildInlineAttachmentOptions()
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  bool _hasAvailableAttachmentAction(SystemSettings settings) {
    final menu = settings.chatAttachmentMenu;
    final isPrivateChat = widget.chatType == ChatType.private;
    final isGroupChat = widget.chatType == ChatType.group;
    return menu.hasAvailableItem(
      isPrivateChat: isPrivateChat,
      isGroupChat: isGroupChat,
      burnAfterReadEnabled:
          settings.burnAfterReadEnabled && _isBurnAfterReadAllowed,
    );
  }

  Widget _buildAnonymousSendBanner(bool isDark) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x33202D3F) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0x665B8DEF) : const Color(0xFFBFDBFE),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.badge_outlined,
            size: 18,
            color: Color(0xFF2563EB),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _localizedText(
                zhCN: '匿名发言已开启，本条消息会以匿名身份发送',
                zhTW: '匿名發言已開啟，這則訊息會以匿名身份發送',
                en: 'Anonymous messages are on. This message will be sent anonymously.',
              ),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : const Color(0xFF1E40AF),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBurnAfterReadBanner(bool isDark) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x332A1B12) : const Color(0xFFFFF3E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0x66FF8A50) : const Color(0xFFFFC7A7),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            size: 18,
            color: Color(0xFFE65100),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _translate(
                context,
                'burn_after_read_banner',
                _localizedText(
                  zhCN: '已开启阅后即焚，对方已读后自动销毁',
                  zhTW: '已開啟閱後即焚，對方已讀後自動銷毀',
                  en: 'Burn after read is enabled. It will self-destruct after the recipient reads it',
                ),
              ),
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : const Color(0xFF9A3412),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyEditPreview(bool isDark) {
    final isEditing = _editingMessage != null;
    final message = isEditing ? _editingMessage! : _replyToMessage!;
    final accentColor =
        isEditing ? AppColors.warning : AppColors.primaryFor(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      decoration: BoxDecoration(
        color: isDark
            ? accentColor.withOpacity(0.15)
            : accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            // 左侧彩色竖条
            Container(width: 4, height: 44, color: accentColor),
            const SizedBox(width: 10),

            // 内容
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题行
                    Row(
                      children: [
                        if (isEditing)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 14,
                              color: accentColor,
                            ),
                          ),
                        Text(
                          isEditing
                              ? _localizedText(
                                  zhCN: '编辑消息',
                                  zhTW: '編輯訊息',
                                  en: 'Edit message',
                                )
                              : message.senderName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // 消息预览
                    Text(
                      _getMessagePreview(message),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 关闭按钮
            GestureDetector(
              onTap: () {
                GlobalHaptics.selection();
                if (isEditing) {
                  this._cancelEdit();
                } else {
                  this._cancelReply();
                }
              },
              child: Container(
                width: 40,
                height: 44,
                alignment: Alignment.center,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white12
                        : Colors.black.withOpacity(0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  /// 获取消息预览文本
  String _getMessagePreview(MessageItem message) {
    switch (message.type) {
      case MessageItemType.text:
        return message.content;
      case MessageItemType.image:
        return _localizedText(zhCN: '📷 图片', zhTW: '📷 圖片', en: '📷 Photo');
      case MessageItemType.video:
        return _localizedText(zhCN: '🎬 视频', zhTW: '🎬 影片', en: '🎬 Video');
      case MessageItemType.voice:
        return _localizedText(
          zhCN: '🎤 语音消息',
          zhTW: '🎤 語音訊息',
          en: '🎤 Voice message',
        );
      case MessageItemType.file:
        return '📎 ${message.fileName ?? _localizedText(zhCN: '文件', zhTW: '檔案', en: 'File')}';
      default:
        return message.content;
    }
  }

  /// 发送消息（处理回复和编辑）。[content] 为可选，表情选择器会直接传入 emoji，否则用输入框内容。
  void _sendMessageWithContext(
    String? content, {
    bool refocusInput = true,
  }) async {
    if (!_ensureChatWritable()) return;
    final text = (content ?? _inputController.text).trim();

    // 如果有待发送图片，优先作为图文消息发送
    if (_pendingImages.isNotEmpty) {
      await this._sendPendingImages(caption: text.isNotEmpty ? text : null);
      return;
    }

    if (text.startsWith(EmojiStoreService.remoteStickerSendPrefix)) {
      final sticker = EmojiStoreService.decodeRemoteStickerSend(text);
      if (sticker == null) return;

      await ref
          .read(messageListProvider(widget.chatId).notifier)
          .sendStickerByUrl(
            packId: sticker.packId,
            stickerId: sticker.stickerId,
            stickerUrl: sticker.url,
            emoji: sticker.emoji,
            burnAfterRead: _activeBurnAfterRead,
          );
      this._updateChatListPreview(
        _localizedText(zhCN: '[贴纸]', zhTW: '[貼紙]', en: '[Sticker]'),
        type: MessageContentType.sticker,
        mediaUrl: sticker.url,
      );
      _inputController.clear();
      this._scrollToBottom();
      GlobalHaptics.light();
      if (refocusInput) {
        _inputFocusNode.requestFocus();
      }
      return;
    }

    if (text.startsWith(EmojiStoreService.customEmojiSendUrlPrefix)) {
      final imageUrl = text.substring(
        EmojiStoreService.customEmojiSendUrlPrefix.length,
      );
      if (imageUrl.isEmpty) return;

      await ref
          .read(messageListProvider(widget.chatId).notifier)
          .sendImageByUrl(
            imageUrl,
            burnAfterRead: _activeBurnAfterRead,
            anonymous: _activeAnonymousSend,
          );
      this._updateChatListPreview(
        _localizedText(
          zhCN: '[自定义表情]',
          zhTW: '[自訂表情]',
          en: '[Custom emoji]',
        ),
        type: MessageContentType.photo,
        mediaUrl: imageUrl,
      );
      _inputController.clear();
      this._scrollToBottom();
      GlobalHaptics.light();
      if (refocusInput) {
        _inputFocusNode.requestFocus();
      }
      return;
    }

    if (text.startsWith(EmojiStoreService.builtInStickerSendPrefix)) {
      final assetPath = text.substring(
        EmojiStoreService.builtInStickerSendPrefix.length,
      );
      if (assetPath.isEmpty) return;

      await ref
          .read(messageListProvider(widget.chatId).notifier)
          .sendTextMessage(
            text,
            burnAfterRead: _activeBurnAfterRead,
            anonymous: _activeAnonymousSend,
          );
      this._updateChatListPreview(
        _localizedText(zhCN: '[贴纸]', zhTW: '[貼紙]', en: '[Sticker]'),
        type: MessageContentType.text,
      );
      _inputController.clear();
      this._scrollToBottom();
      GlobalHaptics.light();
      if (refocusInput) {
        _inputFocusNode.requestFocus();
      }
      return;
    }

    if (text.startsWith(EmojiStoreService.customEmojiSendPrefix)) {
      final imagePath = text.substring(
        EmojiStoreService.customEmojiSendPrefix.length,
      );
      if (imagePath.isEmpty) return;

      final file = File(imagePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(
            SnackBar(
              content: Text(
                _localizedText(
                  zhCN: '自定义表情文件不存在',
                  zhTW: '自訂表情檔案不存在',
                  en: 'Custom emoji file was not found',
                ),
              ),
            ),
          );
        }
        return;
      }

      await ref
          .read(messageListProvider(widget.chatId).notifier)
          .sendImageMessage(
            imagePath,
            burnAfterRead: _activeBurnAfterRead,
            anonymous: _activeAnonymousSend,
          );
      this._updateChatListPreview(
        _localizedText(
          zhCN: '[自定义表情]',
          zhTW: '[自訂表情]',
          en: '[Custom emoji]',
        ),
        type: MessageContentType.photo,
        mediaUrl: imagePath,
      );
      _inputController.clear();
      this._scrollToBottom();
      GlobalHaptics.light();
      if (refocusInput) {
        _inputFocusNode.requestFocus();
      }
      return;
    }

    if (text.isEmpty) return;

    if (text.runes.length > maxTextMessageLength) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '消息内容不能超过5000个字符',
          zhTW: '訊息內容不能超過5000個字元',
          en: 'Messages cannot exceed 5000 characters.',
        ),
      );
      return;
    }

    // 发送消息时停止 typing 状态
    _stopTyping();

    // 如果是编辑模式
    if (_editingMessage != null) {
      if (text != _originalEditContent) {
        final success = await ref
            .read(messageListProvider(widget.chatId).notifier)
            .editMessage(_editingMessage!.id, text);

        if (!mounted) return;

        if (!success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _localizedText(
                  zhCN: '编辑失败',
                  zhTW: '編輯失敗',
                  en: 'Failed to edit message',
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
      this._cancelEdit();
      _inputController.clear();
      return;
    }

    // 如果是回复模式
    if (_replyToMessage != null) {
      if (_replyToMessage!.burnAfterRead) {
        if (mounted) {
          AppSnackBar.warning(
            context,
            _localizedText(
              zhCN: '阅后即焚消息不支持引用',
              zhTW: '閱後即焚訊息不支援引用',
              en: 'Burn-after-read messages cannot be quoted',
            ),
          );
        }
        this._cancelReply();
        return;
      }
      // 发送带回复的消息
      final replyInfo = ReplyInfo(
        messageId: _replyToMessage!.id,
        senderName: _replyToMessage!.senderName,
        content: _replyToMessage!.content,
      );
      final mentions = _pendingMentionIds.isNotEmpty
          ? List<String>.from(_pendingMentionIds)
          : null;
      _pendingMentionIds.clear();
      _updateState(() {
        _mentionQuery = null;
        _atSignIndex = -1;
      });
      final previewTime =
          this._updateChatListPreview(text, type: MessageContentType.text);
      ref
          .read(messageListProvider(widget.chatId).notifier)
          .sendTextMessage(
            text,
            replyTo: replyInfo,
            mentions: mentions,
            burnAfterRead: _activeBurnAfterRead,
            anonymous: _activeAnonymousSend,
          )
          .then((error) {
        if (!mounted) return;
        ref.read(chatListProvider.notifier).updateLastMessageFailure(
              widget.chatId,
              previewTime,
              failed: error != null,
            );
        if (error != null) this._showMessageSendError(error);
      });
      this._cancelReply();
    } else {
      // 普通发送（_sendMessage 内部已处理 clear/scroll/haptic）
      this._sendMessage(text, refocusInput: refocusInput);
      return;
    }

    // 回复模式在此统一处理 clear/scroll/haptic
    _inputController.clear();
    this._scrollToBottom();
    GlobalHaptics.light();
    // 发送后保持/恢复输入框焦点
    if (refocusInput) {
      _inputFocusNode.requestFocus();
    }
  }
}
