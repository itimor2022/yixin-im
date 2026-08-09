// 文件用途：提供 _MessageBubbleBurn 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _MessageBubbleBurn，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble burn 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
extension _MessageBubbleBurn on MessageBubble {
  // 流程逻辑：`_buildBurnLockedBubble` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  Widget _buildBurnLockedBubble(
    BuildContext context,
    Color bubbleColor,
    Color textColor,
    Color timeColor,
    bool isOutgoing,
    bool isDark,
  ) {
    final l10n = AppLocalizations.of(context);
    final lockedBurnSeconds =
        message.burnAfterSeconds > 0 ? message.burnAfterSeconds : 10;
    final lockedHintColor = isDark ? Colors.white70 : Colors.black87;
    final lockedSubColor = isDark ? Colors.white54 : Colors.black54;

    return Container(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 260),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: _getBubbleRadius(isOutgoing),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.local_fire_department_rounded,
                  size: 16,
                  color: Color(0xFFFF7A00),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.get('burn_after_read_message'),
                  style: TextStyle(
                    color: lockedHintColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              l10n
                  .get('tap_to_view_burn_after_read')
                  .replaceAll('{seconds}', '$lockedBurnSeconds'),
              style: TextStyle(
                color: lockedSubColor,
                fontSize: 12,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.max,
              children: [
                Text(
                  DateFormat('HH:mm')
                      .format(toCurrentLocalTime(message.createdAt)),
                  style: AppTextStyles.timestamp.copyWith(color: timeColor),
                ),
                if (isOutgoing) ...[
                  const SizedBox(width: 3),
                  _buildStatusIcon(timeColor),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _wrapBurnCountdown(
    BuildContext context,
    Widget child,
    bool isOutgoing,
    bool isDark,
  ) {
    final countdownSeconds = message.burnCountdownSeconds;
    if (!message.burnAfterRead ||
        countdownSeconds == null ||
        countdownSeconds <= 0) {
      return child;
    }

    final countdownBadgeColor =
        isDark ? const Color(0xFF2A1B12) : const Color(0xFFFFF3E8);
    final countdownBorderColor =
        isDark ? const Color(0x66FF8A50) : const Color(0xFFFFC7A7);
    final countdownLabelColor =
        isDark ? Colors.white70 : const Color(0xFF9A3412);

    return Column(
      crossAxisAlignment:
          isOutgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: countdownBadgeColor,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: countdownBorderColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_fire_department_rounded,
                size: 14,
                color: Color(0xFFFF7A00),
              ),
              const SizedBox(width: 4),
              Text(
                _localizedText(
                  context,
                  zhCN: '$countdownSeconds 秒后销毁',
                  zhTW: '$countdownSeconds 秒後銷毀',
                  en: 'Deletes in ${countdownSeconds}s',
                ),
                style: TextStyle(
                  color: countdownLabelColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
