// 文件用途：实现 _ChatDetailSendActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailSendActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail send actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailSendActions on _ChatDetailPageState {
  // 流程逻辑：`_sendMessage` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  void _sendMessage(String text, {bool refocusInput = true}) {
    if (!_ensureChatWritable()) return;
    if (text.trim().isEmpty) return;
    final mentions = _pendingMentionIds.isNotEmpty
        ? List<String>.from(_pendingMentionIds)
        : null;
    _pendingMentionIds.clear();
    _updateState(() {
      _mentionQuery = null;
      _atSignIndex = -1;
    });

    final previewTime =
        _updateChatListPreview(text, type: MessageContentType.text);
    ref
        .read(messageListProvider(widget.chatId).notifier)
        .sendTextMessage(
          text,
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
      if (error != null) {
        if (_inputController.text.isEmpty) {
          _inputController.value = TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          );
        }
        ref.read(chatListProvider.notifier).updateDraft(widget.chatId, text);
        _showMessageSendError(error);
        return;
      }
      ref.read(chatListProvider.notifier).updateDraft(widget.chatId, '');
    });
    _inputController.clear();
    ref.read(chatListProvider.notifier).updateDraft(widget.chatId, '');
    this._scrollToBottom();
    GlobalHaptics.light();
    if (refocusInput) {
      _inputFocusNode.requestFocus();
    }
  }

  DateTime? _updateChatListPreview(
    String message, {
    MessageContentType? type,
    String? mediaUrl,
    bool? burnAfterRead,
  }) {
    return ref.read(chatListProvider.notifier).updateLastMessage(
          widget.chatId,
          message,
          type: type,
          mediaUrl: mediaUrl,
          burnAfterRead: burnAfterRead ?? _activeBurnAfterRead,
        );
  }

  bool _isStrictCryptoSendError(String error) {
    final normalized = error.toLowerCase();
    return error.contains('严格加密模式下') ||
        error.contains('端到端加密') ||
        error.contains('加密设备') ||
        error.contains('设备公钥') ||
        error.contains('加密版本') ||
        error.contains('数据库未升级') ||
        error.contains('设备密钥') ||
        normalized.contains('strict encryption') ||
        normalized.contains('end-to-end encryption') ||
        normalized.contains('encrypted device') ||
        normalized.contains('device key') ||
        normalized.contains('device public key') ||
        normalized.contains('message encryption is currently disabled') ||
        normalized.contains('encryption-capable version');
  }

  Future<bool> _shouldShowStrictCryptoHelp(String error) async {
    if (!_isStrictCryptoSendError(error)) {
      return false;
    }

    final currentMode =
        ref.read(systemSettingsProvider).valueOrNull?.messageCryptoMode;
    if (currentMode != null) {
      return currentMode.isStrict;
    }

    final latestSettings = await ref
        .read(systemSettingsServiceProvider)
        .getSettings(forceRefresh: true);
    return latestSettings.messageCryptoMode.isStrict;
  }

  Future<void> _showStrictCryptoHelp(String error) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _localizedText(
            zhCN: '严格加密发送失败',
            zhTW: '嚴格加密發送失敗',
            en: 'Strict encryption send failed',
          ),
        ),
        content: Text(
          '${_localizedText(
            zhCN: '$error\n\n处理方法：\n'
                '1. 先让双方都升级到最新版客户端\n'
                '2. 双方都重新登录一次\n'
                '3. 重新进入当前会话后再发送\n'
                '4. 如果只是刚在后台切到严格模式，也请稍等几秒后重试',
            zhTW: '$error\n\n處理方法：\n'
                '1. 先讓雙方都升級到最新版客戶端\n'
                '2. 雙方都重新登入一次\n'
                '3. 重新進入目前會話後再發送\n'
                '4. 如果只是剛在後台切到嚴格模式，也請稍等幾秒後重試',
            en: '$error\n\nHow to fix:\n'
                '1. Make sure both users update to the latest app version\n'
                '2. Ask both users to log in again once\n'
                '3. Reopen this conversation and try sending again\n'
                '4. If strict mode was just enabled in the admin panel, wait a few seconds and retry',
          )}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              _localizedText(
                zhCN: '知道了',
                zhTW: '知道了',
                en: 'OK',
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMessageSendError(String error) {
    final normalized = error.trim();
    if (!mounted || normalized.isEmpty) {
      return;
    }
    unawaited(_presentMessageSendError(normalized));
  }

  Future<void> _presentMessageSendError(String normalized) async {
    final shouldShowStrictHelp = await _shouldShowStrictCryptoHelp(normalized);
    if (!mounted) {
      return;
    }
    if (shouldShowStrictHelp) {
      await _showStrictCryptoHelp(normalized);
      return;
    }
    if (_isStrictCryptoSendError(normalized)) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '消息加密模式正在同步，请稍后重试',
          zhTW: '訊息加密模式正在同步，請稍後重試',
          en: 'Message encryption mode is syncing. Please try again shortly.',
        ),
      );
      return;
    }
    AppSnackBar.warning(
      context,
      localizeServerMessage(
        normalized,
        fallbackZhCN: '发送失败，请重试',
        fallbackZhTW: '發送失敗，請重試',
        fallbackEn: 'Send failed. Please try again.',
      ),
    );
  }
}
