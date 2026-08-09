// 文件用途：实现 _ChatDetailMeetingActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailMeetingActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail meeting actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMeetingActions on _ChatDetailPageState {
  // 流程逻辑：`_compactMeetingTitle` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  String _compactMeetingTitle(String text, {int maxLen = 16}) {
    final value = text.trim();
    if (value.isEmpty || value.length <= maxLen) return value;
    return '${value.substring(0, maxLen)}...';
  }

  Widget _buildMeetingStartOptionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor =
        isDark ? AppColors.callMeetingIconDark : AppColors.callMeetingIcon;
    final iconBackground = isDark
        ? AppColors.callMeetingIconBackgroundDark
        : AppColors.callMeetingIconBackground;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE5EAF3),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveMeetingBannerCompact(bool isDark) {
    final meeting = _activeMeetingInfo;
    if (meeting == null) return const SizedBox.shrink();

    final title = _compactMeetingTitle(
      meeting.title.trim().isNotEmpty
          ? meeting.title.trim()
          : _localizedText(
              zhCN: '群会议进行中',
              zhTW: '群會議進行中',
              en: 'Group Meeting in Progress',
            ),
      maxLen: 16,
    );
    final subtitle = meeting.hostName.trim().isNotEmpty
        ? _localizedText(
            zhCN: '主持人：${meeting.hostName}',
            zhTW: '主持人：${meeting.hostName}',
            en: 'Host: ${meeting.hostName}',
          )
        : _localizedText(
            zhCN: '点击可直接进入',
            zhTW: '點擊可直接進入',
            en: 'Tap to join directly',
          );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.callMeetingIconBackgroundDark
            : AppColors.callMeetingIconBackground,
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? AppColors.callMeetingIconBorderDark
                : AppColors.callMeetingIconBorder,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.callMeetingIconBorderDark
                  : AppColors.callMeetingIconBorder,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.video_camera_front_rounded,
              color: isDark
                  ? AppColors.callMeetingIconDark
                  : AppColors.callMeetingIcon,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : const Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: () {
              final nav =
                  rootNavigatorKey.currentState ?? Navigator.of(context);
              nav.push(
                MaterialPageRoute(
                  builder: (_) => MeetingPage(
                    meetingId: meeting.meetingId,
                    chatId: widget.chatId,
                    chatName: widget.chatName,
                  ),
                ),
              );
            },
            icon: const Icon(Icons.login, size: 16),
            label: Text(
              _localizedText(
                zhCN: '进入',
                zhTW: '進入',
                en: 'Join',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMeetingStartOptionsCompact() async {
    if (widget.chatType == ChatType.private) {
      return;
    }

    final result = await showModalBottomSheet<MeetingType>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF111827) : Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _localizedText(
                    zhCN: '发起群会议',
                    zhTW: '發起群會議',
                    en: 'Start Group Meeting',
                  ),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _localizedText(
                    zhCN: '选择会议类型',
                    zhTW: '選擇會議類型',
                    en: 'Choose meeting type',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 14),
                _buildMeetingStartOptionCard(
                  context: ctx,
                  icon: Icons.call_outlined,
                  title: _localizedText(
                    zhCN: '语音会议',
                    zhTW: '語音會議',
                    en: 'Voice Meeting',
                  ),
                  subtitle: _localizedText(
                    zhCN: '轻量沟通，快速加入',
                    zhTW: '輕量溝通，快速加入',
                    en: 'Lightweight and quick to join',
                  ),
                  onTap: () => Navigator.of(ctx).pop(MeetingType.voice),
                ),
                const SizedBox(height: 10),
                _buildMeetingStartOptionCard(
                  context: ctx,
                  icon: Icons.videocam_outlined,
                  title: _localizedText(
                    zhCN: '视频会议',
                    zhTW: '視訊會議',
                    en: 'Video Meeting',
                  ),
                  subtitle: _localizedText(
                    zhCN: '支持九宫格展示',
                    zhTW: '支援九宮格展示',
                    en: 'Supports grid view',
                  ),
                  onTap: () => Navigator.of(ctx).pop(MeetingType.video),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null) return;
    final inviteeUserIds = await _showMeetingInvitePickerCompact();
    if (!mounted || inviteeUserIds == null) return;
    await this._startMeeting(result, inviteeUserIds: inviteeUserIds);
  }
}
