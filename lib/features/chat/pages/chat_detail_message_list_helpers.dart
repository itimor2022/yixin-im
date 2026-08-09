// 文件用途：实现 _ChatDetailMessageListHelpers 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailMessageListHelpers 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail message list helpers 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMessageListHelpers on _ChatDetailPageState {
  // 流程逻辑：`_buildEmptyChat` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Widget _buildEmptyChat() {
    // 根据聊天类型选择不同的提示文字
    String titleText;
    String subtitleText;

    if (widget.chatType == ChatType.group) {
      titleText = _localizedText(
        zhCN: '暂无消息',
        zhTW: '暫無訊息',
        en: 'No messages yet',
      );
      subtitleText = _localizedText(
        zhCN: '发送第一条消息，开始群聊吧！',
        zhTW: '發送第一條訊息，開始群聊吧！',
        en: 'Send the first message to start the group chat',
      );
    } else if (widget.chatType == ChatType.channel) {
      titleText = _localizedText(
        zhCN: '暂无消息',
        zhTW: '暫無訊息',
        en: 'No messages yet',
      );
      subtitleText = _localizedText(
        zhCN: '频道内容将在这里显示',
        zhTW: '頻道內容將顯示在這裡',
        en: 'Channel content will appear here',
      );
    } else {
      titleText = _localizedText(
        zhCN: '暂无消息',
        zhTW: '暫無訊息',
        en: 'No messages yet',
      );
      subtitleText = _localizedText(
        zhCN: '发送消息开始聊天',
        zhTW: '發送訊息開始聊天',
        en: 'Send a message to start chatting',
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 使用破壳小鸡动画
          WebSafeLottie.asset(
            'assets/emoji/lottie/hatching_chick.json',
            width: 120,
            height: 120,
            repeat: true,
          ),
          const SizedBox(height: 20),
          Text(
            titleText,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondaryFor(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitleText,
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textTertiaryFor(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateDivider(DateTime date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          _formatDateDivider(date),
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // 系统消息（如"xxx 加入了群组"）居中小字显示
  Widget _buildSystemMessage(String content) {
    final displayText = resolveSystemMessageText(
      content,
      currentUserId: ref.read(authServiceProvider).user?.uuid,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            displayText,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    final localA = toCurrentLocalTime(a);
    final localB = toCurrentLocalTime(b);
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }

  String _formatDateDivider(DateTime date) {
    date = toCurrentLocalTime(date);
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (_isSameDay(messageDate, today)) return l10n.today;
    if (_isSameDay(messageDate, yesterday)) return l10n.yesterday;
    if (date.year == now.year) return '${date.month}/${date.day}';
    return '${date.year}/${date.month}/${date.day}';
  }
}
