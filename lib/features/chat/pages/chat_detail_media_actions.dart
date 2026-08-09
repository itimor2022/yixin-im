// 文件用途：实现 _ChatDetailMediaActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailMediaActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail media actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMediaActions on _ChatDetailPageState {
  // 流程逻辑：`_handleDroppedFiles` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Future<void> _handleDroppedFiles(List<XFile> files) async {
    if (!_ensureCanSendMedia()) return;
    for (final xfile in files) {
      final path = xfile.path;
      final extension = path.split('.').last.toLowerCase();
      final fileName = path.split('/').last;

      // 判断文件类型
      final imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
      final videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'webm'];

      if (imageExtensions.contains(extension)) {
        // 发送图片
        final file = File(path);
        final decodedImage = await decodeImageFromList(
          await file.readAsBytes(),
        );
        ref.read(messageListProvider(widget.chatId).notifier).sendImageMessage(
              path,
              width: decodedImage.width,
              height: decodedImage.height,
              burnAfterRead: _activeBurnAfterRead,
              anonymous: _activeAnonymousSend,
            );
        this._updateChatListPreview(
          _localizedText(zhCN: '[图片]', zhTW: '[圖片]', en: '[Photo]'),
          type: MessageContentType.photo,
          mediaUrl: path,
        );
      } else if (videoExtensions.contains(extension)) {
        // 发送视频
        ref.read(messageListProvider(widget.chatId).notifier).sendVideoMessage(
              path,
              burnAfterRead: _activeBurnAfterRead,
              anonymous: _activeAnonymousSend,
            );
        this._updateChatListPreview(
          _localizedText(zhCN: '[视频]', zhTW: '[影片]', en: '[Video]'),
          type: MessageContentType.video,
        );
      } else {
        // 发送文件
        ref.read(messageListProvider(widget.chatId).notifier).sendFileMessage(
              path,
              fileName,
              burnAfterRead: _activeBurnAfterRead,
              anonymous: _activeAnonymousSend,
            );
        this._updateChatListPreview(
          '${_localizedText(zhCN: '[文件]', zhTW: '[檔案]', en: '[File]')} $fileName',
          type: MessageContentType.file,
        );
      }
    }
    this._scrollToBottom();
  }

  void _showAttachmentOptions() {
    FocusManager.instance.primaryFocus?.unfocus();
    _updateState(() {
      if (_showEmojiPickerState) {
        _showEmojiPickerState = false;
      }
      _showAttachmentPickerState = !_showAttachmentPickerState;
    });
  }

  void _hideAttachmentPicker() {
    if (!_showAttachmentPickerState) return;
    _updateState(() => _showAttachmentPickerState = false);
  }

  Widget _buildInlineAttachmentOptions() {
    final isPrivateChat = widget.chatType == ChatType.private;
    final isGroupChat = widget.chatType == ChatType.group;
    final menuSettings =
        ref.watch(systemSettingsProvider).valueOrNull?.chatAttachmentMenu ??
            const ChatAttachmentMenuSettings();

    return _AttachmentSheet(
      onPickFromGallery: this._pickFromGallery,
      onTakePhoto: this._takePhotoOrVideo,
      onStartCall: isPrivateChat ? this._showCallTypeOptions : null,
      onStartMeeting: isGroupChat ? this._showMeetingStartOptionsCompact : null,
      onSendLocation: this._sendCurrentLocation,
      onOpenFavorites: this._openFavoriteMessages,
      onPickFile: this._pickFile,
      onSendRedPacket:
          (isPrivateChat || isGroupChat) ? this._sendRedPacket : null,
      onTransfer: isPrivateChat ? this._transfer : null,
      onBurnAfterReadToggle: this._toggleBurnAfterRead,
      onDismiss: this._hideAttachmentPicker,
      menuSettings: menuSettings,
      burnAfterReadEnabled: _burnAfterReadEnabled,
      allowBurnAfterRead: _isBurnAfterReadAllowed,
    );
  }

  void _showCallTypeOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final l10n = AppLocalizations.of(sheetContext);
        final actionColor =
            isDark ? AppColors.callMeetingIconDark : AppColors.callMeetingIcon;
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.videocam_rounded, color: actionColor),
                  title: Text(l10n.videoCall),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    this._startCall(CallType.video);
                  },
                ),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white10 : const Color(0xFFEDEDED),
                ),
                ListTile(
                  leading: Icon(Icons.call_rounded, color: actionColor),
                  title: Text(l10n.voiceCall),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    this._startCall(CallType.voice);
                  },
                ),
                Divider(
                  height: 1,
                  color: isDark ? Colors.white10 : const Color(0xFFEDEDED),
                ),
                ListTile(
                  title: Center(child: Text(l10n.cancel)),
                  onTap: () => Navigator.pop(sheetContext),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleBurnAfterRead() {
    if (!_isBurnAfterReadAllowed) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '后台已关闭阅后即焚',
          zhTW: '後台已關閉閱後即焚',
          en: 'Burn-after-read has been disabled in admin settings',
        ),
      );
      return;
    }
    _updateState(() => _burnAfterReadEnabled = !_burnAfterReadEnabled);
    AppSnackBar.info(
      context,
      _burnAfterReadEnabled
          ? _localizedText(
              zhCN: '已开启阅后即焚',
              zhTW: '已開啟閱後即焚',
              en: 'Burn-after-read enabled',
            )
          : _localizedText(
              zhCN: '已关闭阅后即焚',
              zhTW: '已關閉閱後即焚',
              en: 'Burn-after-read disabled',
            ),
    );
  }

  void _toggleAnonymousSend() {
    if (!_anonymousSendAllowed) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '本群未开放匿名发言',
          zhTW: '本群未開放匿名發言',
          en: 'Anonymous messages are disabled in this group',
        ),
      );
      return;
    }
    _updateState(() => _anonymousSendEnabled = !_anonymousSendEnabled);
    AppSnackBar.info(
      context,
      _anonymousSendEnabled
          ? _localizedText(
              zhCN: '匿名发言已开启',
              zhTW: '匿名發言已開啟',
              en: 'Anonymous messages enabled',
            )
          : _localizedText(
              zhCN: '匿名发言已关闭',
              zhTW: '匿名發言已關閉',
              en: 'Anonymous messages disabled',
            ),
    );
  }

  void _toggleEmojiPicker() {
    _updateState(() {
      if (!_showEmojiPickerState) {
        _showAttachmentPickerState = false;
      }
      _showEmojiPickerState = !_showEmojiPickerState;
    });
  }
}
