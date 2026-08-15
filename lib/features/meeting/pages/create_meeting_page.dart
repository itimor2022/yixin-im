// 预约会议：两步流程。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api/meeting_service.dart';
import 'meeting_list_page.dart' show formatMeetingNo, formatMeetingTimeRange;

const Color _kPrimary = Color(0xFF009CFF);
const Color _kTextPrimary = Color(0xFF1A1A1A);
const Color _kTextSecondary = Color(0xFF888888);

class _StartOption {
  final DateTime? time;
  final String label;
  const _StartOption(this.time, this.label);
}

class CreateMeetingPage extends ConsumerStatefulWidget {
  final List<int> durationOptions;
  const CreateMeetingPage({super.key, required this.durationOptions});

  @override
  ConsumerState<CreateMeetingPage> createState() => _CreateMeetingPageState();
}

class _CreateMeetingPageState extends ConsumerState<CreateMeetingPage> {
  final _titleController = TextEditingController();
  late List<_StartOption> _startOptions;
  int _startIndex = 0;
  late int _durationMinutes;
  bool _submitting = false;
  String _error = '';
  MeetingRoomItem? _created;

  @override
  void initState() {
    super.initState();
    _startOptions = _buildStartOptions();
    _durationMinutes = widget.durationOptions.contains(60) ? 60 : widget.durationOptions.first;
  }

  @override
  void dispose() { _titleController.dispose(); super.dispose(); }

  List<_StartOption> _buildStartOptions() {
    final now = DateTime.now();
    final options = <_StartOption>[const _StartOption(null, '立即开始')];
    var cursor = DateTime(now.year, now.month, now.day, now.hour, 0).add(const Duration(minutes: 30));
    while (!cursor.isAfter(now)) { cursor = cursor.add(const Duration(minutes: 30)); }
    final limit = now.add(const Duration(hours: 48));
    final today = DateTime(now.year, now.month, now.day);
    while (cursor.isBefore(limit)) {
      final day = DateTime(cursor.year, cursor.month, cursor.day);
      final diffDays = day.difference(today).inDays;
      final prefix = diffDays == 0 ? '今天 ' : diffDays == 1 ? '明天 ' : '${cursor.month}月${cursor.day}日 ';
      options.add(_StartOption(cursor, '$prefix${_hhmm(cursor)}'));
      cursor = cursor.add(const Duration(minutes: 30));
    }
    return options;
  }

  Future<void> _pickStart() async {
    final picked = await _showPickerSheet<int>(
      title: '选择开始时间',
      itemCount: _startOptions.length,
      labelAt: (i) => _startOptions[i].label,
      valueAt: (i) => i,
      selectedIndex: _startIndex,
    );
    if (picked != null && mounted) setState(() => _startIndex = picked);
  }

  Future<void> _pickDuration() async {
    final options = widget.durationOptions;
    final picked = await _showPickerSheet<int>(
      title: '选择会议时长',
      itemCount: options.length,
      labelAt: (i) => _durationLabel(options[i]),
      valueAt: (i) => options[i],
      selectedIndex: options.indexOf(_durationMinutes),
    );
    if (picked != null && mounted) setState(() => _durationMinutes = picked);
  }

  Future<T?> _showPickerSheet<T>({
    required String title,
    required int itemCount,
    required String Function(int) labelAt,
    required T Function(int) valueAt,
    required int selectedIndex,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _kTextPrimary)),
            ),
            const Divider(height: 1),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: itemCount,
                itemBuilder: (_, index) {
                  final selected = index == selectedIndex;
                  return ListTile(
                    title: Text(labelAt(index), style: TextStyle(color: selected ? _kPrimary : _kTextPrimary, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
                    trailing: selected ? const Icon(Icons.check, color: _kPrimary, size: 20) : null,
                    onTap: () => Navigator.of(ctx).pop(valueAt(index)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) { setState(() => _error = '请填写会议主题'); return; }
    setState(() { _submitting = true; _error = ''; });
    try {
      final startAt = _startOptions[_startIndex].time;
      final res = await ref.read(meetingRoomServiceProvider).createMeeting(
        title: title,
        startAt: startAt != null ? startAt.toUtc().toIso8601String() : null,
        durationMinutes: _durationMinutes,
      );
      if (!mounted) return;
      final meeting = res.data;
      if (!res.isSuccess || meeting == null) {
        setState(() { _submitting = false; _error = res.message.isNotEmpty ? res.message : '创建会议失败'; });
        return;
      }
      setState(() { _submitting = false; _created = meeting; });
    } catch (_) {
      if (!mounted) return;
      setState(() { _submitting = false; _error = '创建会议失败，请检查网络后重试'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final created = _created;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        title: Text(created == null ? '预约会议' : '会议详情'),
        backgroundColor: Colors.white,
        foregroundColor: _kTextPrimary,
        elevation: 0,
        leading: created == null
            ? null
            : IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.of(context).pop(true)),
      ),
      body: created == null ? _buildForm() : _buildDetail(created),
    );
  }

  Widget _buildForm() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: TextField(
                  controller: _titleController,
                  maxLength: 40,
                  enabled: !_submitting,
                  style: const TextStyle(fontSize: 16, color: _kTextPrimary),
                  cursorColor: _kPrimary,
                  decoration: const InputDecoration(
                    labelText: '会议主题',
                    labelStyle: TextStyle(color: _kTextSecondary),
                    counterText: '',
                    hintText: '例如：周一项目例会',
                    hintStyle: TextStyle(color: Color(0xFFCCCCCC)),
                    border: InputBorder.none,
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _pickerTile(label: '开始时间', value: _startOptions[_startIndex].label, onTap: _submitting ? null : _pickStart),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _pickerTile(label: '会议时长', value: _durationLabel(_durationMinutes), onTap: _submitting ? null : _pickDuration),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('会议到期后所有人会自动退出房间。', style: TextStyle(fontSize: 12, color: Color(0xFFAAAAAA))),
        ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(_error, style: const TextStyle(color: Color(0xFFE64545), fontSize: 13), textAlign: TextAlign.center),
        ],
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('下一步', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }

  Widget _pickerTile({required String label, required String value, VoidCallback? onTap}) {
    return ListTile(
      title: Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 14)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: const TextStyle(color: _kTextPrimary, fontSize: 15)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: Color(0xFFCCCCCC), size: 20),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _buildDetail(MeetingRoomItem meeting) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF00A9FF), Color(0xFF0074E4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white, size: 20),
                  SizedBox(width: 6),
                  Text('会议已创建', style: TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
              const SizedBox(height: 14),
              Text(meeting.title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                formatMeetingTimeRange(meeting.scheduledStartAt, meeting.durationMinutes),
                style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
          child: Column(
            children: [
              _detailRow('会议号', formatMeetingNo(meeting.meetingNo)),
              const Divider(height: 1, indent: 16, endIndent: 16),
              _detailRow('会议时长', _durationLabel(meeting.durationMinutes)),
            ],
          ),
        ),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text('把会议号告诉对方，进会后在成员列表里点「邀请」分享给好友和群。', style: TextStyle(fontSize: 12, color: Color(0xFFAAAAAA))),
        ),
        const SizedBox(height: 24),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('确认', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: _kTextSecondary, fontSize: 14)),
          const Spacer(),
          Text(value, style: const TextStyle(color: _kTextPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

String _durationLabel(int minutes) {
  final hours = minutes / 60;
  final text = hours == hours.roundToDouble() ? hours.toStringAsFixed(0) : hours.toStringAsFixed(1);
  return '$text 小时';
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
