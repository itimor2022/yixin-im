// 文件用途：实现 _ChatDetailMediaVoiceActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：把按住录音、松开发送、取消和自动停止映射到录音服务，并按 Web/原生平台选择字节流或临时文件上传。
part of 'chat_detail_page.dart';

// 关键声明：chat detail media voice actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailMediaVoiceActions on _ChatDetailPageState {
  // 流程逻辑：`_interruptVoiceRecording` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Future<void> _interruptVoiceRecording({required String reason}) async {
    final serviceState = _voiceRecordService.currentState;
    if ((!_isRecordingVoice && !serviceState.isRecording) ||
        _isInterruptingVoiceRecord) {
      return;
    }

    _isInterruptingVoiceRecord = true;
    debugPrint('[ChatDetail] Interrupting voice recording: $reason');
    try {
      await _voiceRecordService.cancelRecording();
    } finally {
      _isInterruptingVoiceRecord = false;
      _updateState(() => _isRecordingVoice = false);
    }
  }

  void _startVoiceRecord() async {
    debugPrint('[ChatDetail] _startVoiceRecord called');
    if (!_ensureCanSendMedia()) return;
    GlobalHaptics.medium();

    final voiceService = ref.read(voiceRecordProvider.notifier);
    debugPrint('[ChatDetail] Starting recording...');
    final started = await voiceService.startRecording();
    debugPrint('[ChatDetail] Recording started: $started');

    if (started) {
      _updateState(() => _isRecordingVoice = true);
      debugPrint('[ChatDetail] _isRecordingVoice set to true');
    } else {
      final state = ref.read(voiceRecordProvider);
      debugPrint('[ChatDetail] Recording failed, error: ${state.error}');
      if (state.error != null && mounted) {
        final message = state.error!.trim().isNotEmpty
            ? state.error!
            : _localizedText(
                zhCN: '录音启动失败',
                zhTW: '錄音啟動失敗',
                en: 'Failed to start recording',
              );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  void _stopVoiceRecord() async {
    final voiceService = ref.read(voiceRecordProvider.notifier);
    _updateState(() => _isRecordingVoice = false);
    final voiceData = await voiceService.stopRecording();

    if (voiceData != null) {
      _sendRecordedVoice(voiceData);
      return;
    }

    final error = ref.read(voiceRecordProvider).error;
    if (mounted && error?.trim().isNotEmpty == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error!)),
      );
    }
  }

  void _handleAutoStoppedVoice(VoiceRecordData voiceData) {
    if (!mounted || !_isRecordingVoice) return;
    _updateState(() => _isRecordingVoice = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _localizedText(
            zhCN: '录音已达到5分钟上限，已自动发送',
            zhTW: '錄音已達到5分鐘上限，已自動傳送',
            en: 'The 5-minute limit was reached and the recording was sent',
          ),
        ),
      ),
    );
    _sendRecordedVoice(voiceData);
  }

  void _sendRecordedVoice(VoiceRecordData voiceData) {
    if (!_ensureCanSendMedia()) return;
    final notifier = ref.read(messageListProvider(widget.chatId).notifier);
    final bytes = voiceData.bytes;
    if (PlatformUtils.isWeb && bytes != null && bytes.isNotEmpty) {
      notifier.sendVoiceFromBytes(
        bytes,
        voiceData.duration,
        fileName: voiceData.fileName,
        mimeType: voiceData.mimeType ?? 'audio/webm',
        burnAfterRead: _activeBurnAfterRead,
        anonymous: _activeAnonymousSend,
      );
    } else {
      notifier.sendVoiceMessage(
        voiceData.path,
        voiceData.duration,
        burnAfterRead: _activeBurnAfterRead,
        anonymous: _activeAnonymousSend,
      );
    }
    this._updateChatListPreview(
      _localizedText(zhCN: '[语音]', zhTW: '[語音]', en: '[Voice]'),
      type: MessageContentType.voice,
    );
    this._scrollToBottom();
    GlobalHaptics.light();
  }

  void _cancelVoiceRecord() async {
    GlobalHaptics.medium();
    final voiceService = ref.read(voiceRecordProvider.notifier);
    await voiceService.cancelRecording();
    _updateState(() => _isRecordingVoice = false);
  }
}
