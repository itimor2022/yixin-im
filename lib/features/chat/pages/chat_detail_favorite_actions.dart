// 文件用途：实现 _ChatDetailFavoriteActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailFavoriteActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail favorite actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailFavoriteActions on _ChatDetailPageState {
  // 流程逻辑：`_openFavoriteMessages` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Future<void> _openFavoriteMessages() async {
    final accountKey = ref.read(authServiceProvider).user?.uuid.trim() ?? '';
    if (accountKey.isEmpty) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '当前账号信息异常，请重新登录后再试',
          zhTW: '目前帳號資訊異常，請重新登入後再試',
          en: 'Account information is invalid. Please sign in again and retry.',
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FavoriteMessagesPage(
          accountKey: accountKey,
          favoriteService: _favoriteMessageService,
        ),
      ),
    );
  }

  bool _canFavoriteMessage(MessageItem message) {
    if (message.status == MessageStatus.sending ||
        message.status == MessageStatus.failed) {
      return false;
    }
    if (message.burnAfterRead) {
      return false;
    }
    return message.seq > 0;
  }

  Future<void> _toggleFavoriteMessage(MessageItem message) async {
    if (!_canFavoriteMessage(message)) {
      if (message.burnAfterRead) {
        AppSnackBar.warning(
          context,
          _localizedText(
            zhCN: '阅后即焚消息不支持收藏',
            zhTW: '閱後即焚訊息不支援收藏',
            en: 'Burn-after-read messages cannot be favorited',
          ),
        );
        return;
      }
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '消息发送完成后才可收藏',
          zhTW: '訊息發送完成後才可收藏',
          en: 'Only sent messages can be favorited',
        ),
      );
      return;
    }
    final accountKey = ref.read(authServiceProvider).user?.uuid.trim() ?? '';
    if (accountKey.isEmpty) {
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '当前账号信息异常，请重新登录后再试',
          zhTW: '目前帳號資訊異常，請重新登入後再試',
          en: 'Account information is invalid. Please sign in again and retry.',
        ),
      );
      return;
    }
    final chatName =
        ref.read(chatDetailProvider(widget.chatId)).valueOrNull?.name ??
            widget.chatName;
    bool added;
    try {
      added = await _favoriteMessageService.toggleFavorite(
        accountKey,
        message,
        chatName: chatName.trim().isNotEmpty
            ? chatName.trim()
            : _localizedText(
                zhCN: '当前会话',
                zhTW: '目前會話',
                en: 'Current Chat',
              ),
      );
    } catch (_) {
      if (!mounted) return;
      AppSnackBar.warning(
        context,
        _localizedText(
          zhCN: '收藏同步失败，请检查网络后重试',
          zhTW: '收藏同步失敗，請檢查網路後重試',
          en: 'Favorite sync failed. Check your network and retry.',
        ),
      );
      return;
    }
    if (!mounted) return;
    AppSnackBar.success(
      context,
      added
          ? _localizedText(
              zhCN: '收藏成功，可在收藏里查看',
              zhTW: '收藏成功，可在收藏中查看',
              en: 'Added to favorites. You can view it in Favorites.',
            )
          : _localizedText(
              zhCN: '已取消收藏',
              zhTW: '已取消收藏',
              en: 'Removed from favorites',
            ),
    );
  }
}
