// 文件用途：实现 _ChatDetailMediaWalletActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailMediaWalletActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail media wallet actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMediaWalletActions on _ChatDetailPageState {
  // 流程逻辑：`_sendRedPacket` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  void _sendRedPacket() async {
    if (!_ensureChatWritable()) return;
    // 从 chatDetailProvider 获取正确的用户信息
    final chatDetail = ref.read(chatDetailProvider(widget.chatId)).value;
    final targetName = chatDetail?.name ?? widget.chatName;
    final targetAvatar = chatDetail?.avatar;

    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (context) => SendRedPacketPage(
          chatId: widget.chatId, // 传递聊天会话 UUID
          receiverName: targetName.isNotEmpty
              ? targetName
              : _localizedText(
                  zhCN: '用户',
                  zhTW: '使用者',
                  en: 'User',
                ),
          receiverAvatar:
              targetAvatar?.isNotEmpty == true ? targetAvatar : null,
          isGroup: widget.chatType == ChatType.group,
          groupId: widget.chatType == ChatType.group
              ? int.tryParse(widget.chatId)
              : null,
        ),
      ),
    );

    if (!mounted) return;
    // 页面返回值代表钱包服务端已创建红包；下面只补聊天展示消息，不再次执行资金操作。
    if (result != null) {
      // 红包发送成功，添加红包消息到聊天
      try {
        final redPacketInfo = result as dynamic;
        final jsonData = redPacketInfo.toJson();

        // 获取当前用户信息
        final authService = ref.read(authServiceProvider);
        final currentUserName = authService.user?.nickname ??
            _localizedText(zhCN: '我', zhTW: '我', en: 'Me');
        final currentUserAvatar = authService.user?.avatar;

        // 添加红包消息
        ref
            .read(messageListProvider(widget.chatId).notifier)
            .addRedPacketMessage(
              redPacketJson: jsonEncode(jsonData),
              senderName: currentUserName,
              senderAvatar: currentUserAvatar,
            );

        debugPrint('[Chat] Red packet message added');
      } catch (e) {
        debugPrint('[Chat] Error adding red packet message: $e');
      }
    }
  }

  /// 转账
  void _transfer() async {
    if (!_ensureChatWritable()) return;
    // 从 chatDetailProvider 获取正确的用户信息
    final chatDetail = ref.read(chatDetailProvider(widget.chatId)).value;
    final targetUserId = chatDetail?.targetUserId ?? widget.chatId;
    final targetName = chatDetail?.name ?? widget.chatName;
    final targetAvatar = chatDetail?.avatar;

    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (context) => TransferPage(
          receiverId: targetUserId, // 传递接收者 UUID
          receiverName: targetName.isNotEmpty
              ? targetName
              : _localizedText(
                  zhCN: '用户',
                  zhTW: '使用者',
                  en: 'User',
                ),
          receiverAvatar:
              targetAvatar?.isNotEmpty == true ? targetAvatar : null,
        ),
      ),
    );

    if (!mounted) return;
    // 转账气泡是服务端转账实体的聊天投影，支付成功与否仍以钱包接口返回值为准。
    if (result != null) {
      // 转账成功，添加转账消息到聊天
      try {
        final transferInfo = result as dynamic;
        final jsonData = transferInfo.toJson();

        // 获取当前用户信息
        final authService = ref.read(authServiceProvider);
        final currentUserName = authService.user?.nickname ??
            _localizedText(zhCN: '我', zhTW: '我', en: 'Me');
        final currentUserAvatar = authService.user?.avatar;

        // 添加转账消息
        ref
            .read(messageListProvider(widget.chatId).notifier)
            .addTransferMessage(
              transferJson: jsonEncode(jsonData),
              senderName: currentUserName,
              senderAvatar: currentUserAvatar,
            );

        debugPrint('[Chat] Transfer message added');
      } catch (e) {
        debugPrint('[Chat] Error adding transfer message: $e');
      }
    }
  }
}
