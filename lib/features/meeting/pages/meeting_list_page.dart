// 会议入口页。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api/meeting_service.dart';
import '../../../features/meeting/pages/meeting_room_page.dart';
import 'create_meeting_page.dart';

const Color _kPrimary = Color(0xFF009CFF);
const Color _kTextPrimary = Color(0xFF1A1A1A);
const Color _kTextSecondary = Color(0xFF888888);

class MeetingListPage extends ConsumerStatefulWidget {
  const MeetingListPage({super.key});

  @override
  ConsumerState<MeetingListPage> createState() => _MeetingListPageState();
}

class _MeetingListPageState extends ConsumerState<MeetingListPage> {
  MeetingRoomEntry? _entry;
  List<MeetingRoomItem> _meetings = const [];
  bool _loading = true;
  String _error = '';
  bool _loadFailed = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (silent) { await _loadSilently(); return; }
    setState(() { _loading = true; _error = ''; _loadFailed = false; });
    try {
      final service = ref.read(meetingRoomServiceProvider);
      final entryRes = await service.getEntry();
      if (!mounted) return;
      if (!entryRes.isSuccess || entryRes.data == null) {
        setState(() {
          _loading = false; _loadFailed = true;
          _error = entryRes.message.isNotEmpty ? entryRes.message : '会议服务暂时无法连接';
        });
        return;
      }
      final entry = entryRes.data!;
      List<MeetingRoomItem> meetings = const [];
      if (entry.enabled) {
        final listRes = await service.listMyMeetings();
        if (!mounted) return;
        meetings = listRes.data ?? const [];
      }
      setState(() { _entry = entry; _meetings = meetings; _loading = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _loading = false; _loadFailed = true; _error = '加载会议信息失败，请检查网络'; });
    }
  }

  Future<void> _loadSilently() async {
    try {
      final service = ref.read(meetingRoomServiceProvider);
      final entryRes = await service.getEntry();
      if (!mounted) return;
      final entry = entryRes.data;
      if (!entryRes.isSuccess || entry == null) return;
      List<MeetingRoomItem> meetings = const [];
      if (entry.enabled) {
        final listRes = await service.listMyMeetings();
        if (!mounted) return;
        meetings = listRes.data ?? const [];
      }
      setState(() { _entry = entry; _meetings = meetings; _loading = false; _loadFailed = false; _error = ''; });
    } catch (_) {}
  }

  Future<void> _openJoinDialog() async {
    final meetingNo = await showDialog<String>(
      context: context,
      builder: (_) => const _JoinMeetingDialog(),
    );
    if (meetingNo == null || !mounted) return;
    await _joinByNo(meetingNo);
    if (mounted) await _load();
  }

  Future<void> _openCreatePage() async {
    final entry = _entry;
    if (entry == null) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CreateMeetingPage(durationOptions: entry.durationOptions),
      ),
    );
    if (created == true && mounted) await _load();
  }

  Future<void> _joinByNo(String meetingNo) async {
    final no = meetingNo.replaceAll(RegExp(r'\D'), '');
    if (no.length != 9) { _toast('请输入 9 位会议号'); return; }
    try {
      final res = await ref.read(meetingRoomServiceProvider).joinRoom(no);
      if (!mounted) return;
      final session = res.data;
      if (!res.isSuccess || session == null) {
        _toast(res.message.isNotEmpty ? res.message : '进入会议失败');
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MeetingRoomPage(meetingNo: session.meetingNo),
        ),
      );
    } catch (_) {
      if (mounted) _toast('进入会议失败，请检查网络后重试');
    }
  }

  Future<void> _enterMeeting(MeetingRoomItem meeting) async {
    if (meeting.isEnded) { _toast('会议已结束'); return; }
    await _joinByNo(meeting.meetingNo);
    if (mounted) await _load();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: const Text('会议'),
        backgroundColor: Colors.white,
        foregroundColor: _kTextPrimary,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kPrimary))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_loadFailed)
                    _buildErrorCard()
                  else if (entry == null || !entry.enabled)
                    _buildDisabledCard()
                  else ...[
                    _buildActionButtons(entry),
                    const SizedBox(height: 20),
                    if (_meetings.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Text('暂无会议记录', style: TextStyle(color: _kTextSecondary)),
                        ),
                      )
                    else
                      ..._meetings.map((m) => _buildMeetingCard(m)),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildActionButtons(MeetingRoomEntry entry) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.login_rounded,
            label: '加入会议',
            onTap: _openJoinDialog,
          ),
        ),
        if (entry.canCreate) ...[
          const SizedBox(width: 12),
          Expanded(
            child: _ActionButton(
              icon: Icons.add_circle_outline_rounded,
              label: '预约会议',
              onTap: _openCreatePage,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMeetingCard(MeetingRoomItem meeting) {
    final ended = meeting.isEnded;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      meeting.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: ended ? _kTextSecondary : _kTextPrimary,
                      ),
                    ),
                  ),
                  _stateTag(meeting),
                ],
              ),
              const SizedBox(height: 10),
              _infoRow(
                Icons.access_time_rounded,
                formatMeetingTimeRange(meeting.scheduledStartAt, meeting.durationMinutes),
              ),
              const SizedBox(height: 6),
              _infoRow(
                Icons.confirmation_number_outlined,
                '会议号 ${formatMeetingNo(meeting.meetingNo)}',
              ),
              if (!meeting.isCreator && meeting.creatorName.isNotEmpty) ...[
                const SizedBox(height: 6),
                _infoRow(Icons.person_outline, '${meeting.creatorName} 发起'),
              ],
              if (!ended) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: meeting.participantCount > 0
                          ? _infoRow(Icons.people_outline, '${meeting.participantCount} 人在会中')
                          : const SizedBox.shrink(),
                    ),
                    _joinButton(meeting),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _joinButton(MeetingRoomItem meeting) {
    final upcoming = meeting.isUpcoming;
    return Material(
      color: upcoming ? const Color(0xFFEAF6FF) : _kPrimary,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => _enterMeeting(meeting),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Text(
            upcoming ? '提前进入' : '加入',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: upcoming ? _kPrimary : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _stateTag(MeetingRoomItem meeting) {
    late final String text;
    late final Color color;
    switch (meeting.state) {
      case 'upcoming': text = '未开始'; color = const Color(0xFFFF9500); break;
      case 'ended':    text = '已结束'; color = const Color(0xFFAAAAAA); break;
      default:         text = '进行中'; color = const Color(0xFF23C08A);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: color)),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: const Color(0xFFAAAAAA)),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: _kTextSecondary))),
      ],
    );
  }

  Widget _buildDisabledCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: const Column(
        children: [
          Icon(Icons.videocam_off_outlined, size: 40, color: Color(0xFFBBBBBB)),
          SizedBox(height: 12),
          Text('会议功能暂未开启', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _kTextPrimary)),
          SizedBox(height: 6),
          Text('请联系管理员在后台开启会议功能', style: TextStyle(fontSize: 13, color: _kTextSecondary), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 40, color: Color(0xFFBBBBBB)),
          const SizedBox(height: 12),
          const Text('会议服务暂时无法连接', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _kTextPrimary)),
          const SizedBox(height: 6),
          Text(_error, style: const TextStyle(fontSize: 13, color: _kTextSecondary), textAlign: TextAlign.center),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: _load,
            style: OutlinedButton.styleFrom(
              foregroundColor: _kPrimary,
              side: const BorderSide(color: _kPrimary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

// ── 加入会议弹窗 ──
class _JoinMeetingDialog extends StatefulWidget {
  const _JoinMeetingDialog();
  @override
  State<_JoinMeetingDialog> createState() => _JoinMeetingDialogState();
}

class _JoinMeetingDialogState extends State<_JoinMeetingDialog> {
  final _controller = TextEditingController();
  String _error = '';

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  void _submit() {
    final no = _controller.text.replaceAll(RegExp(r'\D'), '');
    if (no.length != 9) { setState(() => _error = '请输入 9 位会议号'); return; }
    Navigator.of(context).pop(no);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: const Text('加入会议', style: TextStyle(color: _kTextPrimary, fontSize: 17)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 9,
            style: const TextStyle(fontSize: 24, letterSpacing: 4, fontWeight: FontWeight.w600, color: _kTextPrimary),
            cursorColor: _kPrimary,
            decoration: InputDecoration(
              counterText: '',
              hintText: '9 位会议号',
              hintStyle: const TextStyle(fontSize: 16, letterSpacing: 0, color: Color(0xFFCCCCCC)),
              filled: true,
              fillColor: const Color(0xFFF5F6F8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_error, style: const TextStyle(color: Color(0xFFE64545), fontSize: 13), textAlign: TextAlign.center),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消', style: TextStyle(color: _kTextSecondary))),
        TextButton(onPressed: _submit, child: const Text('加入', style: TextStyle(color: _kPrimary))),
      ],
    );
  }
}

// ── 动作按钮 ──
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            children: [
              Icon(icon, color: _kPrimary, size: 28),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontSize: 13, color: _kTextPrimary)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── 工具函数 ──
String formatMeetingNo(String meetingNo) {
  if (meetingNo.length != 9) return meetingNo;
  return '${meetingNo.substring(0, 3)} ${meetingNo.substring(3, 6)} ${meetingNo.substring(6)}';
}

String formatMeetingTimeRange(DateTime? start, int durationMinutes) {
  if (start == null) return '时间待定';
  final end = start.add(Duration(minutes: durationMinutes));
  final now = DateTime.now();
  final isToday = start.year == now.year && start.month == now.month && start.day == now.day;
  final datePart = isToday
      ? ''
      : '${start.month.toString().padLeft(2, '0')}月${start.day.toString().padLeft(2, '0')}日 ';
  return '$datePart${_hhmm(start)} - ${_hhmm(end)}';
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
