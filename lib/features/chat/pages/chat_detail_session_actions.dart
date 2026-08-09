// 文件用途：实现 _ChatDetailSessionActions 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatDetailSessionActions 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail session actions 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
extension _ChatDetailSessionActions on _ChatDetailPageState {
  // 流程逻辑：`_leaveChat` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  Future<void> _leaveChat() async {
    final (success, errorMsg) = await ref
        .read(chatListProvider.notifier)
        .leaveChatFromServer(widget.chatId);

    if (!mounted) return;

    if (success) {
      // 退出成功，返回聊天列表
      context.go('/home');
    } else {
      // 显示错误
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(
          content: Text(
            errorMsg ??
                _localizedText(
                  zhCN: '操作失败，请重试',
                  zhTW: '操作失敗，請重試',
                  en: 'Action failed. Please try again.',
                ),
          ),
        ),
      );
    }
  }

  /// 发起通话
  Future<void> _startCall(CallType type) async {
    if (!_ensureChatWritable()) return;
    final callService = ref.read(callServiceProvider.notifier);

    // 获取聊天详情
    final chatDetail = ref.read(chatDetailProvider(widget.chatId)).value;
    final targetUserId = chatDetail?.targetUserId ?? widget.chatId;
    final targetName = chatDetail?.name ?? widget.chatName;
    final targetAvatar = chatDetail?.avatar ?? widget.avatar;

    GlobalHaptics.medium();

    final success = await callService.startCall(
      targetUserId: targetUserId,
      targetName: targetName,
      targetAvatar: targetAvatar,
      type: type,
    );

    if (success && mounted) {
      // 使用根 Navigator 压栈，保证 Android 也能弹出拨通/接听页（不被 Shell 遮挡）
      final nav = rootNavigatorKey.currentState ?? Navigator.of(context);
      nav.push(
        MaterialPageRoute(
          builder: (_) => const CallPage(),
          settings: const RouteSettings(name: '/call'),
        ),
      );
    } else if (!success && mounted) {
      final failedState = ref.read(callServiceProvider);
      if (failedState.permissionIssue != null) {
        await _showCallPermissionFailure(type, failedState);
        return;
      }
      final errorMessage = failedState.errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            errorMessage ??
                _localizedText(
                  zhCN: '发起通话失败',
                  zhTW: '發起通話失敗',
                  en: 'Failed to start the call',
                ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showCallPermissionFailure(
    CallType requestedType,
    CallServiceState failedState,
  ) async {
    final issue = failedState.permissionIssue;
    if (!mounted || issue == null) return;
    final canUseVoice = requestedType == CallType.video &&
        callPermissionSupportsVoiceFallback(issue);
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _localizedText(
            zhCN: '通话权限未开启',
            zhTW: '通話權限未開啟',
            en: 'Call permission required',
          ),
        ),
        content: Text(
          failedState.errorMessage ??
              _localizedText(
                zhCN: '请检查麦克风和相机权限',
                zhTW: '請檢查麥克風和相機權限',
                en: 'Check microphone and camera permissions.',
              ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              _localizedText(zhCN: '取消', zhTW: '取消', en: 'Cancel'),
            ),
          ),
          if (canUseVoice)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('voice'),
              child: Text(
                _localizedText(
                  zhCN: '改用语音',
                  zhTW: '改用語音',
                  en: 'Use voice',
                ),
              ),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop('settings'),
            child: Text(
              _localizedText(
                zhCN: '前往设置',
                zhTW: '前往設定',
                en: 'Open settings',
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'voice') {
      await _startCall(CallType.voice);
    } else if (action == 'settings') {
      await ref.read(callServiceProvider.notifier).openCallPermissionSettings();
    }
  }

  Future<void> _startMeeting(
    MeetingType meetingType, {
    List<String> inviteeUserIds = const [],
  }) async {
    if (!_ensureChatWritable()) return;
    final meetingService = ref.read(meetingServiceProvider);
    final response = await meetingService.createMeeting(
      chatId: widget.chatId,
      meetingType: meetingType,
      title: widget.chatName,
      inviteeUserIds: inviteeUserIds,
      maxParticipants: 32,
    );

    if (!mounted) return;
    if (!response.isSuccess || response.data == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _displayServerMessage(
              raw: response.message,
              zhCN: '发起会议失败',
              zhTW: '發起會議失敗',
              en: 'Failed to start the meeting',
            ),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final created = response.data!;
    final authUser = ref.read(authServiceProvider).user;
    _updateState(() {
      _activeMeetingInfo = MeetingActiveInfo(
        hasActive: true,
        meetingId: created.meetingId,
        chatId: widget.chatId,
        title: created.title,
        meetingType: created.meetingType,
        channelName: created.channelName,
        roomName: created.roomName,
        rtcProvider: created.rtcProvider,
        serverUrl: created.serverUrl,
        startTime: DateTime.now(),
        hostUserId: authUser?.uuid ?? '',
        hostName: authUser?.nickname ?? '',
        hostAvatar: authUser?.avatar,
      );
    });
    final nav = rootNavigatorKey.currentState ?? Navigator.of(context);
    nav.push(
      MaterialPageRoute(
        builder: (_) => MeetingPage(
          meetingId: created.meetingId,
          chatId: widget.chatId,
          chatName: widget.chatName,
        ),
      ),
    );
  }
}
