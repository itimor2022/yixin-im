import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/app_router.dart';
import '../../../core/services/api/meeting_service.dart';
import '../../../core/services/meeting_session_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../pages/meeting_page.dart';

class MeetingOverlay extends ConsumerStatefulWidget {
  const MeetingOverlay({super.key});

  @override
  ConsumerState<MeetingOverlay> createState() => _MeetingOverlayState();
}

class _MeetingOverlayState extends ConsumerState<MeetingOverlay> {
  Offset _position = const Offset(20, 220);

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
          title: Text(session.isHost ? '结束会议' : '离开会议'),
          content: Text(
            session.isHost
                ? '确认结束当前群会议吗？'
                : '确认离开当前群会议吗？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(session.isHost ? '结束' : '离开'),
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
            response.message?.trim().isNotEmpty == true
                ? response.message!
                : (session.isHost ? '结束会议失败' : '离开会议失败'),
          ),
        ),
      );
      return;
    }

    ref.read(meetingSessionProvider.notifier).clear();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(session.isHost ? '会议已结束' : '已离开会议')),
    );
  }

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
              (_position.dx + details.delta.dx).clamp(0, screenSize.width - 186),
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
                            session.isHost ? '主持中' : '会议中',
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
                      icon: isVideo ? Icons.videocam_outlined : Icons.mic_outlined,
                      text: isVideo ? '视频' : '语音',
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
                        label: '打开',
                        icon: Icons.open_in_full_rounded,
                        background: Colors.white.withOpacity(0.10),
                        onTap: _openMeetingPage,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _actionButton(
                        label: session.isHost ? '结束' : '离开',
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
