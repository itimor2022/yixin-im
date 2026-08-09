// 文件用途：实现 _ChatDetailHeaderLeaveActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailHeaderLeaveActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail header leave actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailHeaderLeaveActions on _ChatDetailPageState {
  // 流程逻辑：`_showLeaveConfirmDialog` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  /// 显示退出/取消订阅确认对话框（TG风格底部弹窗）
  void _showLeaveConfirmDialog(
    BuildContext context, {
    required bool isChannel,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final title = isChannel ? l10n.get('unsubscribe') : l10n.leaveGroup;
    final actionTitle = isChannel
        ? _localizedText(
            zhCN: '取消订阅「${widget.chatName}」？',
            zhTW: '取消訂閱「${widget.chatName}」？',
            en: 'Unsubscribe from "${widget.chatName}"?',
          )
        : _localizedText(
            zhCN: '退出「${widget.chatName}」？',
            zhTW: '退出「${widget.chatName}」？',
            en: 'Leave "${widget.chatName}"?',
          );
    final message = isChannel
        ? _localizedText(
            zhCN: '取消订阅后将不再接收此频道的消息',
            zhTW: '取消訂閱後將不再接收此頻道的訊息',
            en: 'You will no longer receive messages from this channel',
          )
        : _translate(
            context,
            'leave_confirm_message',
            _localizedText(
              zhCN: '退出后将不再接收此群组的消息',
              zhTW: '退出後將不再接收此群組的訊息',
              en: 'You will no longer receive messages from this group',
            ),
          );

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 操作区域
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  // 标题和描述
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Column(
                      children: [
                        Text(
                          actionTitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  // 确认按钮
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        this._leaveChat();
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 20,
                            color: AppColors.error,
                            fontWeight: FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 取消按钮
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      l10n.cancel,
                      style: TextStyle(
                        fontSize: 20,
                        color: AppColors.primaryFor(context),
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }
}
