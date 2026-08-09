// 文件用途：实现聊天详情主页面，并组合消息列表、输入区和各类消息操作。
// 核心逻辑：组合聊天详情的消息列表、输入区和附件面板，协调录音、发送、滚动定位、生命周期中断及消息预览刷新。
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:universal_io/io.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

import '../../../core/services/api/api_client.dart';
import '../../../core/constants/message_limits.dart';
import '../../../core/router/app_router.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/system_ui_styles.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../core/services/account_session_coordinator.dart';
import '../../../core/services/media_cache_manager.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/web_safe_lottie.dart';
import '../../../shared/utils/snackbar_utils.dart';
import '../../../core/services/api/chat_service.dart' as api;
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../settings/pages/chat_settings_page.dart';
import '../widgets/message_bubble.dart';
import '../widgets/chat_input_bar.dart';
import '../widgets/chat_background.dart';
import '../widgets/message_context_menu.dart';
import '../widgets/voice_record_overlay.dart';
import '../services/emoji_store_service.dart';
import './user_profile_page.dart';
import '../providers/message_provider.dart';
import '../providers/chat_provider.dart';
import '../../contacts/providers/contact_provider.dart';
import '../../../core/services/voice_record_service.dart';
import '../../../core/services/time_zone_refresh_service.dart';
import '../../../core/services/image_picker_diagnostics_service.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/call_service.dart';
import '../../../core/services/api/meeting_service.dart';
import '../../call/pages/call_page.dart';
import '../../meeting/pages/meeting_page.dart';
import '../../home/pages/home_desktop_page.dart';
import '../../wallet/pages/send_red_packet_page.dart';
import '../../wallet/pages/transfer_page.dart';
import '../../vip/widgets/vip_avatar_frame.dart';
import '../../vip/widgets/vip_badge.dart';
import '../utils/system_message_text.dart';
import '../utils/chat_attachment_menu_layout.dart';
import '../utils/message_revoke_policy.dart';
import '../../../core/utils/clipboard_image.dart';
import '../../../core/utils/image_compress_util.dart';
import '../../../core/utils/platform_utils.dart';
import '../pages/favorite_messages_page.dart';
import '../pages/message_detail_page.dart';
import 'chat_video_recorder_page.dart';
import 'message_search_page.dart';
import 'report_page.dart';
import '../services/favorite_message_service.dart';
import '../services/message_detail_service.dart';
part 'chat_detail_models.dart';
part 'chat_detail_attachment_sheet.dart';
part 'chat_detail_feedback_widgets.dart';
part 'chat_detail_common_widgets.dart';
part 'chat_detail_info_sheets.dart';
part 'chat_detail_channel_info_sheet.dart';
part 'chat_detail_group_info_sheet.dart';
part 'chat_detail_group_info_widgets.dart';
part 'chat_detail_group_member_list.dart';
part 'chat_detail_group_mute_actions.dart';
part 'chat_detail_selection_actions.dart';
part 'chat_detail_header_actions.dart';
part 'chat_detail_header_menu_actions.dart';
part 'chat_detail_header_leave_actions.dart';
part 'chat_detail_meeting_actions.dart';
part 'chat_detail_meeting_invite_prompt.dart';
part 'chat_detail_meeting_invite_picker.dart';
part 'chat_detail_meeting_realtime.dart';
part 'chat_detail_realtime_state.dart';
part 'chat_detail_message_list.dart';
part 'chat_detail_message_list_helpers.dart';
part 'chat_detail_input_area.dart';
part 'chat_detail_input_composer.dart';
part 'chat_detail_input_pending_images.dart';
part 'chat_detail_input_mentions.dart';
part 'chat_detail_input_access.dart';
part 'chat_detail_media_actions.dart';
part 'chat_detail_media_picker.dart';
part 'chat_detail_media_file_actions.dart';
part 'chat_detail_media_camera_actions.dart';
part 'chat_detail_media_image_actions.dart';
part 'chat_detail_media_location_actions.dart';
part 'chat_detail_media_voice_actions.dart';
part 'chat_detail_media_wallet_actions.dart';
part 'chat_detail_favorite_actions.dart';
part 'chat_detail_translation_actions.dart';
part 'chat_detail_forward_actions.dart';
part 'chat_detail_desktop_file_actions.dart';
part 'chat_detail_edit_delete_actions.dart';
part 'chat_detail_message_actions.dart';
part 'chat_detail_message_details.dart';
part 'chat_detail_page_flow.dart';
part 'chat_detail_session_actions.dart';
part 'chat_detail_send_actions.dart';
part 'chat_detail_chat_metadata.dart';
part 'chat_detail_build.dart';

// 关键声明：聊天详情页只协调界面生命周期和子模块，不直接复制消息业务规则，消息写入统一交给 message provider。
enum _PinnedEntryType { message, announcement }

class _PinnedEntry {
  final _PinnedEntryType type;
  final String id;
  final String content;
  final String? messageId;

  const _PinnedEntry({
    required this.type,
    required this.id,
    required this.content,
    this.messageId,
  });
}

class ChatDetailPage extends ConsumerStatefulWidget {
  final String chatId;
  final String chatName;
  final String? avatar;
  final ChatType chatType;
  final String? action; // 'call' 或 'video'，用于从用户主页直接发起通话
  final bool isDesktopMode; // 是否作为桌面端右侧内容区使用
  final String? initialMessageId;
  final int? initialMessageSeq;

  const ChatDetailPage({
    super.key,
    required this.chatId,
    this.chatName = '',
    this.avatar,
    this.chatType = ChatType.private,
    this.action,
    this.isDesktopMode = false,
    this.initialMessageId,
    this.initialMessageSeq,
  });

  @override
  ConsumerState<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends ConsumerState<ChatDetailPage>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final Map<String, GlobalKey> _messageKeys = {};

  bool _showScrollToBottom = false;
  bool _showEmojiPickerState = false;
  bool _showAttachmentPickerState = false;
  bool _isRecordingVoice = false;
  bool _isInterruptingVoiceRecord = false;
  bool _isDragging = false; // 桌面端拖拽状态

  // 回复消息状态
  MessageItem? _replyToMessage;
  // 编辑消息状态
  MessageItem? _editingMessage;
  String? _originalEditContent;

  // 多选模式
  bool _isSelectionMode = false;
  final Set<String> _selectedMessageIds = {};
  bool _isForwardingMessages = false;

  // 键盘收起防抖
  Timer? _keyboardDismissTimer;
  bool _isLoadingMore = false;

  // @ 提及功能
  String? _mentionQuery; // @ 后的搜索词，null 表示未在提及模式
  int _atSignIndex = -1; // @ 符号在文本中的位置
  final List<String> _pendingMentionIds = []; // 已选择的被提及用户 ID

  // 追踪活动的 OverlayEntry，确保在 dispose 时清理
  final Set<OverlayEntry> _activeOverlays = {};

  // 置顶消息
  String? _pinnedMessageText;
  String? _pinnedMessageId;

  // 群/频道公告置顶
  List<api.AnnouncementItem> _announcements = const [];
  int _pinnedEntryIndex = 0;
  bool _pinnedStackDismissed = false;
  MeetingActiveInfo? _activeMeetingInfo;
  bool _loadingActiveMeeting = false;

  // 正在输入状态
  Timer? _typingTimer;
  Timer? _draftSaveTimer;
  bool _isTyping = false;

  // 其他用户的输入状态 {userId: nickname}
  final Map<String, String> _typingUsers = {};
  // 每个用户独立的超时 Timer，防止多人 typing 时互相取消
  final Map<String, Timer> _typingUserTimers = {};
  String? _typingHandlerId;
  String? _pinnedHandlerId;
  String? _unpinnedHandlerId;
  String? _reconnectedHandlerId;
  String? _chatDissolvedHandlerId;
  String? _memberRoleChangedHandlerId;
  String? _announcementHandlerId;
  String? _announcementUpdatedHandlerId;
  String? _announcementDeletedHandlerId;
  String? _meetingStartedHandlerId;
  String? _meetingEndedHandlerId;
  String? _meetingInviteHandlerId;
  String? _meetingTitleUpdatedHandlerId;
  ProviderSubscription<CallServiceState>? _callStateSubscription;
  StreamSubscription<VoiceRecordData>? _voiceAutoStopSubscription;
  final Set<String> _shownMeetingInviteIds = {};

  // 缓存的 WebSocket 服务引用（用于 dispose 时安全访问）
  WebSocketService? _wsService;
  late final ChatListNotifier _chatListNotifier;
  late final VoiceRecordService _voiceRecordService;

  // 防止重复清理（back button + PopScope 双重触发）
  bool _hasCleanedUp = false;

  // 标记是否正在使用系统相机，防止 resumed 时 loadMessages 冲掉发送中的消息
  bool _isUsingCamera = false;

  // 待发送图片队列（图文混排功能）
  final List<_PendingImage> _pendingImages = [];
  late final FavoriteMessageService _favoriteMessageService;
  bool _burnAfterReadEnabled = false;
  bool _anonymousSendEnabled = false;

  bool get _isBurnAfterReadAllowed =>
      ref.read(systemSettingsProvider).valueOrNull?.burnAfterReadEnabled ??
      true;

  bool get _activeBurnAfterRead =>
      _burnAfterReadEnabled && _isBurnAfterReadAllowed;

  bool get _anonymousSendAllowed {
    final detail = ref.read(chatDetailProvider(widget.chatId)).valueOrNull;
    if (widget.chatType != ChatType.group || detail == null) return false;
    return detail.allowAnonymous;
  }

  bool get _activeAnonymousSend =>
      _anonymousSendEnabled && _anonymousSendAllowed;

  bool get _canForwardFromCurrentChat {
    final detail = ref.read(chatDetailProvider(widget.chatId)).valueOrNull;
    if (detail?.status == 2) return false;
    if (widget.chatType != ChatType.group) return true;
    if (detail == null) return false;
    return detail.allowForward || detail.myRole >= 2;
  }

  void _updateState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _chatListNotifier = ref.read(chatListProvider.notifier);
    _voiceRecordService = ref.read(voiceRecordProvider.notifier);
    _favoriteMessageService = FavoriteMessageService(
      apiClient: ref.read(apiClientProvider),
    );
    final savedDraft = _chatListNotifier.getChatById(widget.chatId)?.draft;
    if (savedDraft != null && savedDraft.isNotEmpty) {
      _inputController.value = TextEditingValue(
        text: savedDraft,
        selection: TextSelection.collapsed(offset: savedDraft.length),
      );
    }
    _callStateSubscription = ref.listenManual<CallServiceState>(
      callServiceProvider,
      (previous, next) {
        if (next.state == CallState.incoming &&
            previous?.state != CallState.incoming) {
          unawaited(
            this._interruptVoiceRecording(reason: 'incoming_call'),
          );
        }
      },
    );
    _voiceAutoStopSubscription =
        _voiceRecordService.autoStoppedRecordings.listen(
      this._handleAutoStoppedVoice,
    );
    // 监听应用生命周期
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(this._onScroll);
    // 监听输入变化发送 typing 状态
    _inputController.addListener(this._onInputChanged);
    // Web/桌面：注册 Ctrl+V 粘贴图片快捷键
    HardwareKeyboard.instance.addHandler(this._handleKeyEvent);
    // 立即启动消息加载，避免首帧只显示聊天背景后再闪出消息。
    unawaited(
        ref.read(messageListProvider(widget.chatId).notifier).initialize());
    // 其余页面绑定放到下一帧，避免阻塞首帧。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      this._setupTypingListener();
      // 标记当前正在查看的聊天，防止新消息误加未读
      ref.read(chatListProvider.notifier).setActiveChatId(widget.chatId);
      // 主动订阅当前会话的 WS 推送（不依赖列表加载完成才订阅）
      ref.read(webSocketServiceProvider.notifier).subscribeChats([
        widget.chatId,
      ]);
      Future.delayed(const Duration(milliseconds: 2500), () {
        if (!mounted) return;
        unawaited(ref.read(contactListProvider.notifier).initialize());
      });
      Future.delayed(const Duration(milliseconds: 600), () {
        if (!mounted) return;
        unawaited(this._persistReadState());
      });
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        this._loadPinnedMessage();
      });
      Future.delayed(const Duration(milliseconds: 1600), () {
        if (!mounted) return;
        this._loadLatestAnnouncement();
      });
      if (widget.initialMessageId?.isNotEmpty == true) {
        Future.delayed(const Duration(milliseconds: 900), () {
          if (!mounted) return;
          unawaited(
            this._scrollToMessage(
              widget.initialMessageId!,
              targetSeq: widget.initialMessageSeq,
            ),
          );
        });
      }
      if (widget.chatType == ChatType.group) {
        Future.delayed(const Duration(milliseconds: 2200), () {
          if (!mounted) return;
          this._loadActiveMeeting();
        });
      }
      // 如果有 action 参数，自动发起通话
      if (widget.action != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          if (widget.action == 'call') {
            this._startCall(CallType.voice);
          } else if (widget.action == 'video') {
            this._startCall(CallType.video);
          }
        });
      }
    });
  }

  String _translate(
    BuildContext context,
    String key,
    String fallback, [
    Map<String, String> variables = const {},
  ]) {
    var text = AppLocalizations.of(context).get(key);
    if (text == key) {
      text = fallback;
    }
    for (final entry in variables.entries) {
      text = text.replaceAll('{${entry.key}}', entry.value);
    }
    return text;
  }

  String _localizedText({
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

  String _displayServerMessage({
    required String? raw,
    required String zhCN,
    String? zhTW,
    required String en,
  }) {
    final message = raw?.trim() ?? '';
    if (message.isEmpty) {
      return _localizedText(zhCN: zhCN, zhTW: zhTW, en: en);
    }

    final containsHan = RegExp(r'[\u4e00-\u9fff]').hasMatch(message);
    if (!containsHan) {
      return message;
    }

    switch (AppLocalizations.of(context).language) {
      case AppLanguage.en:
        return en;
      case AppLanguage.zhTW:
        return zhTW ?? zhCN;
      case AppLanguage.zhCN:
        return message;
    }
  }

  void _stopTyping() {
    if (_isTyping) {
      _isTyping = false;
      _typingTimer?.cancel();
      // 使用缓存的 WebSocket 服务（避免在 dispose 后使用 ref）
      _wsService?.sendTyping(widget.chatId, isTyping: false);
    }
  }

  @override
  void dispose() {
    _voiceAutoStopSubscription?.cancel();
    _voiceAutoStopSubscription = null;
    _callStateSubscription?.close();
    _callStateSubscription = null;
    if (_isRecordingVoice || _voiceRecordService.currentState.isRecording) {
      unawaited(_voiceRecordService.cancelRecording());
    }
    // 移除生命周期观察者
    WidgetsBinding.instance.removeObserver(this);

    // 停止 typing 状态
    _stopTyping();

    // 取消定时器
    _keyboardDismissTimer?.cancel();
    _keyboardDismissTimer = null;
    _typingTimer?.cancel();
    _typingTimer = null;
    _draftSaveTimer?.cancel();
    _draftSaveTimer = null;
    _chatListNotifier.updateDraft(widget.chatId, _inputController.text);
    for (final timer in _typingUserTimers.values) {
      timer.cancel();
    }
    _typingUserTimers.clear();

    // 移除 WebSocket 监听（使用缓存的引用）
    if (_wsService != null) {
      for (final handlerId in [
        _typingHandlerId,
        _pinnedHandlerId,
        _unpinnedHandlerId,
        _reconnectedHandlerId,
        _chatDissolvedHandlerId,
        _memberRoleChangedHandlerId,
        _announcementHandlerId,
        _announcementUpdatedHandlerId,
        _announcementDeletedHandlerId,
        _meetingStartedHandlerId,
        _meetingEndedHandlerId,
        _meetingInviteHandlerId,
        _meetingTitleUpdatedHandlerId,
      ]) {
        if (handlerId != null) {
          _wsService!.unregisterHandler(handlerId);
        }
      }
    }
    _typingHandlerId = null;
    _pinnedHandlerId = null;
    _unpinnedHandlerId = null;
    _reconnectedHandlerId = null;
    _chatDissolvedHandlerId = null;
    _memberRoleChangedHandlerId = null;
    _announcementHandlerId = null;
    _announcementUpdatedHandlerId = null;
    _announcementDeletedHandlerId = null;
    _meetingStartedHandlerId = null;
    _meetingEndedHandlerId = null;
    _meetingInviteHandlerId = null;
    _meetingTitleUpdatedHandlerId = null;

    // 清理 typing 状态
    _typingUsers.clear();
    _wsService = null;

    // 清理所有活动的 OverlayEntry
    for (final overlay in _activeOverlays) {
      try {
        overlay.remove();
      } catch (_) {
        // 可能已被移除，忽略错误
      }
    }
    _activeOverlays.clear();

    // 移除滚动监听器（必须在 dispose 之前）
    _scrollController.removeListener(this._onScroll);
    _scrollController.dispose();

    // 移除输入监听器
    _inputController.removeListener(this._onInputChanged);

    // 清理输入相关
    _inputController.dispose();
    _inputFocusNode.dispose();

    // 移除 Ctrl+V 键盘监听
    HardwareKeyboard.instance.removeHandler(this._handleKeyEvent);

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;
    if (shouldInterruptVoiceRecordingOnLifecycle(state)) {
      unawaited(
        this._interruptVoiceRecording(reason: 'app_${state.name}'),
      );
    }
    // 应用从后台恢复时自动刷新消息
    // 但如果是从系统相机返回，跳过刷新，避免冲掉正在发送的本地消息
    if (state == AppLifecycleState.resumed) {
      ref.read(chatListProvider.notifier).setActiveChatId(widget.chatId);
      if (_isUsingCamera) {
        // 相机返回，不刷新消息，只刷新在线状态
        ref.invalidate(chatDetailProvider(widget.chatId));
        return;
      }
      // 先标记 inactive，再标记 active，触发 setActive 内部的增量同步
      final notifier = ref.read(messageListProvider(widget.chatId).notifier);
      notifier.setActive(false);
      notifier.setActive(true);
      unawaited(notifier.ensureReliableSync(reason: 'app_resumed'));
      Future.delayed(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        this._loadPinnedMessage();
      });
      if (widget.chatType == ChatType.group) {
        Future.delayed(const Duration(milliseconds: 1600), () {
          if (!mounted) return;
          this._loadActiveMeeting();
        });
      }
      // 刷新聊天详情（在线状态等）
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        ref.invalidate(chatDetailProvider(widget.chatId));
      });
    }
  }

  /// 清理逻辑（返回时执行）
  String? _highlightedMessageId;
  @override
  Widget build(BuildContext context) {
    ref.watch(timeZoneRefreshProvider);
    // Do not disable tickers for the entire chat subtree. Network-image fades,
    // progress indicators, video state and other visible controls rely on
    // them to leave their loading frame. Persistently mounted heavy panels
    // (notably the emoji picker) pause their own tickers when hidden.
    return this._buildChatDetailPage(context);
  }
}

// ==================== 组件 ====================
