// 文件用途：提供 MeetingOverlay 可复用界面组件，服务于群组会议。
// 核心逻辑：根据输入模型和状态渲染 MeetingOverlay，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/meeting_service.dart';
import '../../../core/services/meeting_session_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../pages/meeting_page.dart';

String _meetingOverlayText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 关键声明：meeting overlay 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
class MeetingOverlay extends ConsumerStatefulWidget {
  const MeetingOverlay({super.key});

  @override
  ConsumerState<MeetingOverlay> createState() => _MeetingOverlayState();
}

class _MeetingOverlayState extends ConsumerState<MeetingOverlay> {
  Offset _position = const Offset(20, 220);

  String _serverMessage({
    required String? raw,
    required String zhCN,
    String? zhTW,
    required String en,
  }) {
    return localizeServerMessage(
      raw,
      fallbackZhCN: zhCN,
      fallbackZhTW: zhTW,
      fallbackEn: en,
    );
  }

  void _openMeetingPage() {
    HapticFeedback.selectionClick();
    final session = ref.read(meetingSessionProvider);
    ref.read(meetingSessionProvider.notifier).setMinimized(false);
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => MeetingPage(
          meetingId: session.meetingId,
          chatId: session.chatId.isNotEmpty ? session.chatId : null,
          chatName: session.chatName.isNotEmpty ? session.chatName : null,
        ),
      ),
    );
  }

  Future<void> _leaveOrEndMeeting() async {
    final session = ref.read(meetingSessionProvider);
    if (session.meetingId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(
            session.isHost
                ? _meetingOverlayText(
                    context,
                    zhCN: '结束会议',
                    zhTW: '結束會議',
                    en: 'End Meeting',
                  )
                : _meetingOverlayText(
                    context,
                    zhCN: '离开会议',
                    zhTW: '離開會議',
                    en: 'Leave Meeting',
                  ),
          ),
          content: Text(
            session.isHost
                ? _meetingOverlayText(
                    context,
                    zhCN: '确认结束当前群会议吗？',
                    zhTW: '確認結束目前群會議嗎？',
                    en: 'End the current group meeting?',
                  )
                : _meetingOverlayText(
                    context,
                    zhCN: '确认离开当前群会议吗？',
                    zhTW: '確認離開目前群會議嗎？',
                    en: 'Leave the current group meeting?',
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                _meetingOverlayText(
                  context,
                  zhCN: '取消',
                  zhTW: '取消',
                  en: 'Cancel',
                ),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(
                session.isHost
                    ? _meetingOverlayText(
                        context,
                        zhCN: '结束',
                        zhTW: '結束',
                        en: 'End',
                      )
                    : _meetingOverlayText(
                        context,
                        zhCN: '离开',
                        zhTW: '離開',
                        en: 'Leave',
                      ),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final meetingService = ref.read(meetingServiceProvider);
    final response = session.isHost
        ? await meetingService.endMeeting(session.meetingId)
        : await meetingService.leaveMeeting(session.meetingId);
    if (!mounted) return;
    if (!response.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _serverMessage(
              raw: response.message,
              zhCN: session.isHost ? '结束会议失败' : '离开会议失败',
              zhTW: session.isHost ? '結束會議失敗' : '離開會議失敗',
              en: session.isHost
                  ? 'Failed to end the meeting'
                  : 'Failed to leave the meeting',
            ),
          ),
        ),
      );
      return;
    }

    ref.read(meetingSessionProvider.notifier).clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          session.isHost
              ? _meetingOverlayText(
                  context,
                  zhCN: '会议已结束',
                  zhTW: '會議已結束',
                  en: 'Meeting ended',
                )
              : _meetingOverlayText(
                  context,
                  zhCN: '已离开会议',
                  zhTW: '已離開會議',
                  en: 'Left the meeting',
                ),
        ),
      ),
    );
  }

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(meetingSessionProvider);
    if (!session.isVisible) {
      return const SizedBox.shrink();
    }

    final screenSize = MediaQuery.sizeOf(context);
    final isVideo = session.meetingType == 'video';

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: GestureDetector(
        onTap: _openMeetingPage,
        onPanUpdate: (details) {
          setState(() {
            _position = Offset(
              (_position.dx + details.delta.dx)
                  .clamp(0, screenSize.width - 186),
              (_position.dy + details.delta.dy).clamp(
                MediaQuery.paddingOf(context).top,
                screenSize.height - 124,
              ),
            );
          });
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 186,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.28),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF2E5BFF), Color(0xFF6AA6FF)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isVideo ? Icons.videocam_rounded : Icons.groups_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            session.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            session.isHost
                                ? _meetingOverlayText(
                                    context,
                                    zhCN: '主持中',
                                    zhTW: '主持中',
                                    en: 'Hosting',
                                  )
                                : _meetingOverlayText(
                                    context,
                                    zhCN: '会议中',
                                    zhTW: '會議中',
                                    en: 'In Meeting',
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.72),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildTag(
                      icon: isVideo
                          ? Icons.videocam_outlined
                          : Icons.mic_outlined,
                      text: isVideo
                          ? _meetingOverlayText(
                              context,
                              zhCN: '视频',
                              zhTW: '視訊',
                              en: 'Video',
                            )
                          : _meetingOverlayText(
                              context,
                              zhCN: '语音',
                              zhTW: '語音',
                              en: 'Audio',
                            ),
                    ),
                    const SizedBox(width: 6),
                    _buildTag(
                      icon: Icons.people_outline,
                      text:
                          '${session.participantCount}/${session.maxParticipants}',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _actionButton(
                        label: _meetingOverlayText(
                          context,
                          zhCN: '打开',
                          zhTW: '開啟',
                          en: 'Open',
                        ),
                        icon: Icons.open_in_full_rounded,
                        background: Colors.white.withOpacity(0.10),
                        onTap: _openMeetingPage,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _actionButton(
                        label: session.isHost
                            ? _meetingOverlayText(
                                context,
                                zhCN: '结束',
                                zhTW: '結束',
                                en: 'End',
                              )
                            : _meetingOverlayText(
                                context,
                                zhCN: '离开',
                                zhTW: '離開',
                                en: 'Leave',
                              ),
                        icon: Icons.call_end_rounded,
                        background: AppColors.error,
                        onTap: _leaveOrEndMeeting,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTag({
    required IconData icon,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: Colors.white.withOpacity(0.8)),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color background,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MeetingOverlayWrapper extends ConsumerWidget {
  final Widget child;

  const MeetingOverlayWrapper({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(meetingSessionProvider);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (session.isVisible) const MeetingOverlay(),
      ],
    );
  }
}
