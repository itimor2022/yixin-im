// 文件用途：实现 _ChatDetailInputArea 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailInputArea 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail input area 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailInputArea on _ChatDetailPageState {
  // 流程逻辑：`_handleKeyEvent` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  /// Ctrl+V 全局键盘事件处理（粘贴图片）
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isCtrlV = event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed);
    if (!isCtrlV) return false;
    // 只在输入框有焦点时处理
    if (!_inputFocusNode.hasFocus) return false;
    _handlePasteImage();
    return false; // 不消费事件，文字粘贴仍走默认处理
  }

  Future<void> _handlePasteImage() async {
    await _pasteImageFromClipboard(showEmptyMessage: false);
  }

  Future<void> _pasteImageFromClipboard({bool showEmptyMessage = true}) async {
    if (!_ensureCanSendMedia()) return;
    final bytes = await readImageFromClipboard();
    if (bytes == null || bytes.isEmpty) {
      if (showEmptyMessage && mounted) {
        AppSnackBar.info(
          context,
          _localizedText(
            zhCN: '剪贴板中没有图片',
            zhTW: '剪貼簿中沒有圖片',
            en: 'No image in clipboard',
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    try {
      await ref
          .read(messageListProvider(widget.chatId).notifier)
          .sendImageFromBytes(
            bytes,
            burnAfterRead: _activeBurnAfterRead,
            anonymous: _activeAnonymousSend,
          );
      this._updateChatListPreview(
        _localizedText(zhCN: '[图片]', zhTW: '[圖片]', en: '[Photo]'),
        type: MessageContentType.photo,
      );
      this._scrollToBottom();
    } catch (e) {
      debugPrint('[Paste] 粘贴图片失败: $e');
    }
  }

  Widget _buildInputArea(bool isDark) {
    // 私聊不检查禁言
    if (widget.chatType == ChatType.private) {
      return this._buildInputWithPreview(isDark);
    }
    // 群组和频道
    return this._buildInputAreaForGroupChannel(isDark);
  }
}
