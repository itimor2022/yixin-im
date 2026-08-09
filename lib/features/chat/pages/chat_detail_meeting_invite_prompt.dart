// 文件用途：实现 _ChatDetailMeetingInvitePrompt 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailMeetingInvitePrompt 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail meeting invite prompt 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMeetingInvitePrompt on _ChatDetailPageState {
  // 流程逻辑：`_showMeetingInvitePromptCompact` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Future<void> _showMeetingInvitePromptCompact({
    required String meetingId,
    required String inviterName,
    required String title,
    required String meetingType,
  }) async {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final meetingLabel = meetingType == 'voice'
        ? _localizedText(
            zhCN: '语音群会议',
            zhTW: '語音群會議',
            en: 'voice group meeting',
          )
        : _localizedText(
            zhCN: '视频群会议',
            zhTW: '視訊群會議',
            en: 'video group meeting',
          );
    final shortTitle = _compactMeetingTitle(title, maxLen: 18);

    final shouldJoin = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF111827) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.16),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.callMeetingIconBackgroundDark
                          : AppColors.callMeetingIconBackground,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.video_camera_front_rounded,
                      color: isDark
                          ? AppColors.callMeetingIconDark
                          : AppColors.callMeetingIcon,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _localizedText(
                        zhCN: '群会议邀请',
                        zhTW: '群會議邀請',
                        en: 'Group Meeting Invite',
                      ),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _localizedText(
                  zhCN: '$inviterName 邀请你加入$meetingLabel',
                  zhTW: '$inviterName 邀請你加入$meetingLabel',
                  en: '$inviterName invited you to join the $meetingLabel',
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              if (shortTitle.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1F2937)
                        : const Color(0xFFF5FAFF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _localizedText(
                      zhCN: '会议：$shortTitle',
                      zhTW: '會議：$shortTitle',
                      en: 'Meeting: $shortTitle',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF17368A),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: Text(
                        _localizedText(
                          zhCN: '稍后',
                          zhTW: '稍後',
                          en: 'Later',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: Text(
                        _localizedText(
                          zhCN: '加入',
                          zhTW: '加入',
                          en: 'Join',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (shouldJoin != true || !mounted) return;
    final nav = rootNavigatorKey.currentState ?? Navigator.of(context);
    nav.push(
      MaterialPageRoute(
        builder: (_) => MeetingPage(
          meetingId: meetingId,
          chatId: widget.chatId,
          chatName: widget.chatName,
        ),
      ),
    );
  }
}
