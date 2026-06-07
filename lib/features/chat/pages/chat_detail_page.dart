import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:universal_io/io.dart';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:lottie/lottie.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:gao_ran_im/core/services/api/api_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_saver/file_saver.dart';
import 'package:dio/dio.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/premium_theme_tokens.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/emoji_status_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/premium_widgets.dart';
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
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/call_service.dart';
import '../../../core/services/api/meeting_service.dart';
import '../../call/pages/call_page.dart';
import '../../meeting/pages/meeting_page.dart';
import '../../home/pages/home_desktop_page.dart';
import '../../wallet/pages/send_red_packet_page.dart';
import '../../wallet/pages/transfer_page.dart';
import '../utils/system_message_text.dart';
import '../../../core/utils/clipboard_image.dart';
import '../../../core/utils/platform_utils.dart';
import '../pages/favorite_messages_page.dart';
import '../services/favorite_message_service.dart';

/// 待发送图片（支持 web bytes 和原生 path 两种模式）
class _PendingImage {
  final Uint8List? bytes; // web
  final String? path; // native
  final int? width;
  final int? height;
  final String ext;
  final String name;

  const _PendingImage({
    this.bytes,
    this.path,
    this.width,
    this.height,
    required this.ext,
    required this.name,
  });
}

/// 聊天类型
enum ChatType { private, group, channel }

class ChatDetailPage extends ConsumerStatefulWidget {
  final String chatId;
  final String chatName;
  final String? avatar;
  final ChatType chatType;
  final String? action; // 'call' 或 'video'，用于从用户主页直接发起通话
  final bool isDesktopMode; // 是否作为桌面端右侧内容区使用

  const ChatDetailPage({
    super.key,
    required this.chatId,
    this.chatName = '',
    this.avatar,
    this.chatType = ChatType.private,
    this.action,
    this.isDesktopMode = false,
  });

  @override
  ConsumerState<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends ConsumerState<ChatDetailPage>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();

  bool _showScrollToBottom = false;
  bool _showEmojiPickerState = false;
  bool _isRecordingVoice = false;
  bool _isDragging = false; // 桌面端拖拽状态

  // 回复消息状态
  MessageItem? _replyToMessage;
  // 编辑消息状态
  MessageItem? _editingMessage;
  String? _originalEditContent;

  // 多选模式
  bool _isSelectionMode = false;
  final Set<String> _selectedMessageIds = {};

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

  // 群公告置顶
  String? _announcementText;
  bool _announcementDismissed = false;
  MeetingActiveInfo? _activeMeetingInfo;
  bool _loadingActiveMeeting = false;

  // 正在输入状态
  Timer? _typingTimer;
  bool _isTyping = false;

  // 其他用户的输入状态 {userId: nickname}
  final Map<String, String> _typingUsers = {};
  // 每个用户独立的超时 Timer，防止多人 typing 时互相取消
  final Map<String, Timer> _typingUserTimers = {};
  String? _typingHandlerId;
  String? _pinnedHandlerId;
  String? _unpinnedHandlerId;
  String? _reconnectedHandlerId;
  String? _announcementHandlerId;
  String? _announcementUpdatedHandlerId;
  String? _announcementDeletedHandlerId;
  String? _meetingStartedHandlerId;
  String? _meetingEndedHandlerId;
  String? _meetingInviteHandlerId;
  String? _meetingTitleUpdatedHandlerId;
  final Set<String> _shownMeetingInviteIds = {};

  // 缓存的 WebSocket 服务引用（用于 dispose 时安全访问）
  WebSocketService? _wsService;

  // 防止重复清理（back button + PopScope 双重触发）
  bool _hasCleanedUp = false;

  // 标记是否正在使用系统相机，防止 resumed 时 loadMessages 冲掉发送中的消息
  bool _isUsingCamera = false;

  // 待发送图片队列（图文混排功能）
  final List<_PendingImage> _pendingImages = [];
  final FavoriteMessageService _favoriteMessageService =
      FavoriteMessageService();
  bool _burnAfterReadEnabled = false;

  bool get _isBurnAfterReadAllowed =>
      ref.read(systemSettingsProvider).valueOrNull?.burnAfterReadEnabled ??
      true;

  bool get _activeBurnAfterRead =>
      _burnAfterReadEnabled && _isBurnAfterReadAllowed;

  @override
  void initState() {
    super.initState();
    // 监听应用生命周期
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    // 监听输入变化发送 typing 状态
    _inputController.addListener(_onInputChanged);
    // Web/桌面：注册 Ctrl+V 粘贴图片快捷键
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    // 初始化时加载消息（下一帧，让 UI 先渲染框架）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setupTypingListener();
      // 标记当前正在查看的聊天，防止新消息误加未读
      ref.read(chatListProvider.notifier).setActiveChatId(widget.chatId);
      // 主动订阅当前会话的 WS 推送（不依赖列表加载完成才订阅）
      ref.read(webSocketServiceProvider.notifier).subscribeChats([
        widget.chatId,
      ]);
      unawaited(ref.read(contactListProvider.notifier).initialize());
      // 立即并行执行，不再人为延迟
      ref.read(messageListProvider(widget.chatId).notifier).initialize();
      ref.read(chatListProvider.notifier).markAsRead(widget.chatId);
      _loadPinnedMessage();
      _loadLatestAnnouncement();
      if (widget.chatType == ChatType.group) {
        _loadActiveMeeting();
      }
      // 如果有 action 参数，自动发起通话
      if (widget.action != null) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          if (widget.action == 'call') {
            _startCall(CallType.voice);
          } else if (widget.action == 'video') {
            _startCall(CallType.video);
          }
        });
      }
    });
  }

  Future<void> _loadPinnedMessage() async {
    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.getPinnedMessage(widget.chatId);
      if (!mounted) return;
      if (!response.isSuccess) {
        if (kDebugMode) debugPrint('[Pin] getPinnedMessage failed: ${response.message}');
        return;
      }

      final data = response.data;
      if (data is Map) {
        final pinnedData = Map<String, dynamic>.from(data);
        final id = _readPinnedMessageId(pinnedData);
        final text = _readPinnedMessageText(pinnedData);
        if (kDebugMode) debugPrint('[Pin] Loaded pinned: id=$id, text=$text');
        _setPinnedMessage(messageId: id, messageText: text);
      } else if (data == null) {
        _clearPinnedMessage();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Pin] _loadPinnedMessage error: $e');
    }
  }

  void _setPinnedMessage({String? messageId, String? messageText}) {
    if (!mounted) return;

    final normalizedId = messageId?.trim();
    final normalizedText = messageText?.trim();
    final hasId = normalizedId != null && normalizedId.isNotEmpty;
    final hasText = normalizedText != null && normalizedText.isNotEmpty;

    setState(() {
      _pinnedMessageId = hasId ? normalizedId : null;
      _pinnedMessageText = hasId ? (hasText ? normalizedText : '[置顶消息]') : null;
    });
  }

  void _clearPinnedMessage() {
    if (!mounted) return;

    setState(() {
      _pinnedMessageId = null;
      _pinnedMessageText = null;
    });
  }

  Future<void> _loadLatestAnnouncement() async {
    if (widget.chatType == ChatType.private) return;
    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.getAnnouncements(
        widget.chatId,
        page: 1,
        pageSize: 1,
      );
      if (!mounted) return;
      if (response.isSuccess &&
          response.data != null &&
          response.data!.list.isNotEmpty) {
        setState(() {
          _announcementText = response.data!.list.first.content;
          _announcementDismissed = false;
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Announcement] _loadLatestAnnouncement error: $e');
    }
  }

  Future<void> _loadActiveMeeting({bool silent = true}) async {
    if (widget.chatType != ChatType.group || _loadingActiveMeeting) return;
    _loadingActiveMeeting = true;
    try {
      final meetingService = ref.read(meetingServiceProvider);
      final response = await meetingService.getActiveMeeting(widget.chatId);
      if (!mounted) return;
      final info = response.isSuccess && response.data != null
          ? response.data!
          : MeetingActiveInfo(
              hasActive: false,
              meetingId: '',
              chatId: widget.chatId,
              title: '',
              meetingType: 'video',
              channelName: '',
              hostUserId: '',
              hostName: '',
            );
      setState(() {
        _activeMeetingInfo = info.hasActive ? info : null;
      });
    } catch (_) {
      if (!mounted || silent) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('加载群会议状态失败')));
    } finally {
      _loadingActiveMeeting = false;
    }
  }

  Map<String, dynamic> _extractWsPayload(dynamic raw) {
    if (raw is! Map) return {};
    final event = Map<String, dynamic>.from(raw);
    final nested = event['data'];
    if (nested is Map) {
      return Map<String, dynamic>.from(nested);
    }
    return event;
  }

  String _extractWsType(dynamic raw) {
    if (raw is! Map) return '';
    final event = Map<String, dynamic>.from(raw);
    return event['type']?.toString() ?? '';
  }

  void _handleMeetingWsChanged(dynamic raw) {
    if (!mounted || widget.chatType != ChatType.group) return;
    final type = _extractWsType(raw);
    final payload = _extractWsPayload(raw);
    final eventChatId = payload['chat_id']?.toString() ?? '';
    if (eventChatId.isNotEmpty && eventChatId != widget.chatId) return;
    if (type == WSMessageType.meetingStarted) {
      _handleMeetingStartedEvent(payload);
      unawaited(_loadActiveMeeting());
      return;
    }
    if (type == WSMessageType.meetingInvite) {
      _handleMeetingInviteEvent(payload);
      unawaited(_loadActiveMeeting());
      return;
    }
    if (type == WSMessageType.meetingTitleUpdated) {
      unawaited(_loadActiveMeeting());
      return;
    }
    if (type != WSMessageType.meetingEnded) return;
    unawaited(_loadActiveMeeting());
  }

  void _handleMeetingStartedEvent(Map<String, dynamic> payload) {
    // 会议开始会由后端落成系统消息，这里只保留占位，避免前端重复造消息。
  }

  void _handleMeetingInviteEvent(Map<String, dynamic> payload) {
    final meetingId = payload['meeting_id']?.toString() ?? '';
    if (meetingId.isEmpty) return;

    final inviterName = payload['inviter_name']?.toString() ?? '群成员';
    final inviteKey = '$meetingId:${payload['inviter_id']?.toString() ?? ''}';
    if (_shownMeetingInviteIds.add(inviteKey)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showMeetingInvitePromptCompact(
          meetingId: meetingId,
          inviterName: inviterName,
          title: payload['title']?.toString() ?? widget.chatName,
          meetingType: payload['meeting_type']?.toString() ?? 'video',
        );
      });
    }
  }

  void _showAnnouncementDetail() {
    if (_announcementText == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign, size: 20, color: Colors.orange.shade700),
                const SizedBox(width: 8),
                Text(
                  '群公告',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SelectableText(
              _announcementText!,
              style: TextStyle(
                fontSize: 15,
                height: 1.6,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _readPinnedMessageId(Map<String, dynamic> data) {
    final raw = data['message_id'] ?? data['pinned_message_id'];
    final id = raw?.toString().trim();
    return (id == null || id.isEmpty) ? null : id;
  }

  String? _readPinnedMessageText(Map<String, dynamic> data) {
    final raw = data['message_text'] ?? data['pinned_message_text'];
    final text = raw?.toString().trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  String _buildPinnedMessagePreview(MessageItem message) {
    final content = message.content.trim();
    if (content.isNotEmpty) {
      return content.length > 100 ? '${content.substring(0, 100)}...' : content;
    }

    switch (message.type) {
      case MessageItemType.image:
        return '[图片]';
      case MessageItemType.video:
        return '[视频]';
      case MessageItemType.voice:
      case MessageItemType.audio:
        return '[语音]';
      case MessageItemType.file:
        final fileName = message.fileName?.trim();
        return (fileName != null && fileName.isNotEmpty)
            ? '[文件] $fileName'
            : '[文件]';
      case MessageItemType.sticker:
      case MessageItemType.gif:
        return '[表情]';
      case MessageItemType.location:
        return '[位置]';
      case MessageItemType.contact:
        return '[名片]';
      case MessageItemType.poll:
        return '[投票]';
      case MessageItemType.call:
        return '[通话]';
      case MessageItemType.redPacket:
        return '[红包]';
      case MessageItemType.transfer:
        return '[转账]';
      case MessageItemType.system:
        return '[系统消息]';
      case MessageItemType.text:
        return '[消息]';
    }
  }

  String _compactMeetingTitle(String text, {int maxLen = 16}) {
    final value = text.trim();
    if (value.isEmpty || value.length <= maxLen) return value;
    return '${value.substring(0, maxLen)}...';
  }

  Widget _buildSheetTag({required String text, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F2937) : const Color(0xFFF4F7FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.white70 : const Color(0xFF3557C4),
        ),
      ),
    );
  }

  Widget _buildMeetingStartOptionCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color),
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
      meeting.title.trim().isNotEmpty ? meeting.title.trim() : '群会议进行中',
      maxLen: 16,
    );
    final subtitle = meeting.hostName.trim().isNotEmpty
        ? '主持人：${meeting.hostName}'
        : '点击可直接进入';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF1F4033).withOpacity(0.95)
            : const Color(0xFFE9FFF3),
        border: Border(
          bottom: BorderSide(
            color: isDark ? const Color(0xFF285F49) : const Color(0xFFBDE9D0),
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
              color: const Color(0xFF1E9E66).withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.video_camera_front_rounded,
              color: Color(0xFF1E9E66),
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
                    color: isDark ? Colors.white : const Color(0xFF0D3324),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white70 : const Color(0xFF2B6A4C),
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
            label: const Text('进入'),
          ),
        ],
      ),
    );
  }

  Future<void> _showMeetingInvitePromptCompact({
    required String meetingId,
    required String inviterName,
    required String title,
    required String meetingType,
  }) async {
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final meetingLabel = meetingType == 'voice' ? '语音群会议' : '视频群会议';
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
                      gradient: const LinearGradient(
                        colors: [Color(0xFF16A085), Color(0xFF1E9E66)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.video_camera_front_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '群会议邀请',
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
                '$inviterName 邀请你加入$meetingLabel',
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
                    '会议：$shortTitle',
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
                      child: const Text('稍后'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: const Text('加入'),
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
                  '发起群会议',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '选择会议类型',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 14),
                _buildMeetingStartOptionCard(
                  context: ctx,
                  icon: Icons.call_outlined,
                  title: '语音会议',
                  subtitle: '轻量沟通，快速加入',
                  color: const Color(0xFF1E9E66),
                  onTap: () => Navigator.of(ctx).pop(MeetingType.voice),
                ),
                const SizedBox(height: 10),
                _buildMeetingStartOptionCard(
                  context: ctx,
                  icon: Icons.videocam_outlined,
                  title: '视频会议',
                  subtitle: '支持九宫格展示',
                  color: const Color(0xFF2E5BFF),
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
    await _startMeeting(result, inviteeUserIds: inviteeUserIds);
  }

  Future<List<String>?> _showMeetingInvitePickerCompact() async {
    List<api.ChatMember> members;
    try {
      members = await ref.read(chatMembersProvider(widget.chatId).future);
    } catch (_) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('加载群成员失败')));
      return null;
    }
    if (!mounted) return null;

    final currentUserId = ref.read(authServiceProvider).user?.uuid ?? '';
    final candidates = members
        .where((m) => m.userId.isNotEmpty && m.userId != currentUserId)
        .toList();
    if (candidates.isEmpty) {
      return <String>[];
    }

    final selectedIds = <String>{};
    final searchController = TextEditingController();
    String keyword = '';

    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final query = keyword.trim().toLowerCase();
            final filtered = query.isEmpty
                ? candidates
                : candidates.where((m) {
                    final displayName = m.displayName.toLowerCase();
                    final username = m.username.toLowerCase();
                    final userId = m.userId.toLowerCase();
                    return displayName.contains(query) ||
                        username.contains(query) ||
                        userId.contains(query);
                  }).toList();

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomInset),
              child: Container(
                height: MediaQuery.of(ctx).size.height * 0.82,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF111827) : Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '邀请群成员',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '从群成员里选择需要加入的人',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: '搜索昵称 / 用户名 / UUID',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: isDark
                            ? const Color(0xFF1F2937)
                            : const Color(0xFFF6F8FC),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onChanged: (value) {
                        setSheetState(() {
                          keyword = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _buildSheetTag(
                          text: '可选 ${candidates.length} 人',
                          isDark: isDark,
                        ),
                        const SizedBox(width: 8),
                        _buildSheetTag(
                          text: '已选 ${selectedIds.length} 人',
                          isDark: isDark,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                '未找到可邀请成员',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, index) {
                                final member = filtered[index];
                                final checked = selectedIds.contains(
                                  member.userId,
                                );
                                return InkWell(
                                  onTap: () {
                                    setSheetState(() {
                                      if (checked) {
                                        selectedIds.remove(member.userId);
                                      } else {
                                        selectedIds.add(member.userId);
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: checked
                                          ? (isDark
                                                ? const Color(0xFF1E2A45)
                                                : const Color(0xFFEAF1FF))
                                          : (isDark
                                                ? const Color(0xFF1F2937)
                                                : const Color(0xFFF7F9FC)),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: checked
                                            ? const Color(0xFF2E5BFF)
                                            : (isDark
                                                  ? const Color(0xFF334155)
                                                  : const Color(0xFFE2E8F0)),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        AvatarWidget(
                                          avatar: member.avatar,
                                          name: member.displayName,
                                          size: 34,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                member.displayName.isNotEmpty
                                                    ? member.displayName
                                                    : member.userId,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.black87,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                member.username.isNotEmpty
                                                    ? member.username
                                                    : member.userId,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark
                                                      ? Colors.white70
                                                      : Colors.black54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Checkbox(
                                          value: checked,
                                          onChanged: (value) {
                                            setSheetState(() {
                                              if (value == true) {
                                                selectedIds.add(member.userId);
                                              } else {
                                                selectedIds.remove(
                                                  member.userId,
                                                );
                                              }
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(sheetContext).pop(null),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF5A68C7),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: const Text('取消'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: TextButton(
                              onPressed: () =>
                                  Navigator.of(sheetContext).pop(<String>[]),
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF5A68C7),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              child: const Text('跳过'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: () => Navigator.of(
                                sheetContext,
                              ).pop(selectedIds.toList()),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              child: const Text(
                                '发起',
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    searchController.dispose();
    return result;
  }

  /// 设置 typing WebSocket 监听
  void _setupTypingListener() {
    _wsService = ref.read(webSocketServiceProvider.notifier);
    final myUserId = ref.read(authServiceProvider).user?.uuid;

    _typingHandlerId = _wsService!.registerHandler('typing', (data) {
      if (!mounted) return;

      final chatId = data['chat_id'] as String?;
      final userId = data['user_id'] as String?;
      final action = data['action'] as String?;

      // 只处理当前聊天的 typing 事件
      if (chatId != widget.chatId || userId == null) return;

      // 不处理自己的 typing 事件
      if (userId == myUserId) return;

      setState(() {
        if (action == 'start') {
          final userName = (data['user_name'] as String?)?.trim();
          final displayName = (userName != null && userName.isNotEmpty)
              ? userName
              : userId;
          // 重新插入以保证群聊里“最后输入的人”在 map 末尾。
          _typingUsers.remove(userId);
          _typingUsers[userId] = displayName;
          // 每个用户有独立的 8 秒超时 Timer，防止多人同时输入时互相取消
          _typingUserTimers[userId]?.cancel();
          _typingUserTimers[userId] = Timer(const Duration(seconds: 8), () {
            if (mounted) {
              setState(() {
                _typingUsers.remove(userId);
                _typingUserTimers.remove(userId);
              });
            }
          });
        } else {
          _typingUsers.remove(userId);
          _typingUserTimers[userId]?.cancel();
          _typingUserTimers.remove(userId);
        }
      });
    });

    _pinnedHandlerId = _wsService!.registerHandler(
      WSMessageType.messagePinned,
      (data) {
        if (!mounted || data is! Map) return;

        final event = Map<String, dynamic>.from(data);
        final chatId = event['chat_id']?.toString();
        if (chatId != widget.chatId) return;

        final id = _readPinnedMessageId(event);
        final text = _readPinnedMessageText(event);
        if (kDebugMode) debugPrint('[Pin] WS message_pinned: id=$id, text=$text');

        if (id != null && id.isNotEmpty) {
          _setPinnedMessage(messageId: id, messageText: text);
        } else {
          _loadPinnedMessage();
        }
      },
    );

    _unpinnedHandlerId = _wsService!.registerHandler(
      WSMessageType.messageUnpinned,
      (data) {
        if (!mounted || data is! Map) return;

        final event = Map<String, dynamic>.from(data);
        final chatId = event['chat_id']?.toString();
        if (chatId != widget.chatId) return;

        _clearPinnedMessage();
      },
    );

    _reconnectedHandlerId = _wsService!.registerHandler(
      WSMessageType.reconnected,
      (_) {
        _loadPinnedMessage();
        _loadLatestAnnouncement();
        if (widget.chatType == ChatType.group) {
          _loadActiveMeeting();
        }
      },
    );

    _announcementHandlerId = _wsService!.registerHandler(
      WSMessageType.chatAnnouncement,
      (data) {
        if (!mounted || data is! Map) return;
        final event = Map<String, dynamic>.from(data);
        final chatId = event['chat_id']?.toString();
        if (chatId != widget.chatId) return;
        final content = event['content']?.toString();
        if (content != null && content.isNotEmpty) {
          setState(() {
            _announcementText = content;
            _announcementDismissed = false;
          });
        }
      },
    );

    _announcementUpdatedHandlerId = _wsService!.registerHandler(
      WSMessageType.chatAnnouncementUpdated,
      (data) {
        if (!mounted || data is! Map) return;
        final event = Map<String, dynamic>.from(data);
        final chatId = event['chat_id']?.toString();
        if (chatId != widget.chatId) return;
        final content = event['content']?.toString();
        if (content != null && content.isNotEmpty) {
          setState(() {
            _announcementText = content;
            _announcementDismissed = false;
          });
        }
      },
    );

    _announcementDeletedHandlerId = _wsService!.registerHandler(
      WSMessageType.chatAnnouncementDeleted,
      (data) {
        if (!mounted || data is! Map) return;
        final event = Map<String, dynamic>.from(data);
        final chatId = event['chat_id']?.toString();
        if (chatId != widget.chatId) return;
        setState(() {
          _announcementText = null;
          _announcementDismissed = false;
        });
      },
    );

    _meetingStartedHandlerId = _wsService!.registerHandler(
      WSMessageType.meetingStarted,
      _handleMeetingWsChanged,
    );
    _meetingEndedHandlerId = _wsService!.registerHandler(
      WSMessageType.meetingEnded,
      _handleMeetingWsChanged,
    );
    _meetingInviteHandlerId = _wsService!.registerHandler(
      WSMessageType.meetingInvite,
      _handleMeetingWsChanged,
    );
    _meetingTitleUpdatedHandlerId = _wsService!.registerHandler(
      WSMessageType.meetingTitleUpdated,
      _handleMeetingWsChanged,
    );
  }

  /// 输入变化时发送 typing 状态
  /// Ctrl+V 全局键盘事件处理（粘贴图片）
  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final isCtrlV =
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed);
    if (!isCtrlV) return false;
    // 只在输入框有焦点时处理
    if (!_inputFocusNode.hasFocus) return false;
    _handlePasteImage();
    return false; // 不消费事件，文字粘贴仍走默认处理
  }

  Future<void> _handlePasteImage() async {
    final bytes = await readImageFromClipboard();
    if (bytes == null || bytes.isEmpty) return;
    if (!mounted) return;
    try {
      await ref
          .read(messageListProvider(widget.chatId).notifier)
          .sendImageFromBytes(bytes, burnAfterRead: _activeBurnAfterRead);
      _updateChatListPreview('[图片]', type: MessageContentType.photo);
      _scrollToBottom();
    } catch (e) {
      if (kDebugMode) debugPrint('[Paste] 粘贴图片失败: $e');
    }
  }

  void _onInputChanged() {
    if (!mounted || _wsService == null) return;

    final text = _inputController.text;

    if (text.isEmpty) {
      if (_isTyping) {
        _isTyping = false;
        _wsService!.sendTyping(widget.chatId, isTyping: false);
      }
      _typingTimer?.cancel();
      if (widget.chatType != ChatType.private) {
        _detectMentionQuery();
      }
      return;
    }

    if (text.isNotEmpty && !_isTyping) {
      _isTyping = true;
      _wsService!.sendTyping(widget.chatId, isTyping: true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 8), () {
      if (_isTyping && _wsService != null) {
        _isTyping = false;
        _wsService!.sendTyping(widget.chatId, isTyping: false);
      }
    });

    // 群聊/频道才检测 @ 提及
    if (widget.chatType != ChatType.private) {
      _detectMentionQuery();
    }
  }

  /// 检测光标前是否有未完成的 @mention 模式
  void _detectMentionQuery() {
    final text = _inputController.text;
    final cursor = _inputController.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) return;

    final textBeforeCursor = text.substring(0, cursor);
    final lastAt = textBeforeCursor.lastIndexOf('@');

    if (lastAt < 0) {
      if (_mentionQuery != null)
        setState(() {
          _mentionQuery = null;
          _atSignIndex = -1;
        });
      return;
    }

    // @ 后到光标之间不含空格才视为正在输入 mention
    final afterAt = textBeforeCursor.substring(lastAt + 1);
    if (afterAt.contains(' ') || afterAt.contains('\n')) {
      if (_mentionQuery != null)
        setState(() {
          _mentionQuery = null;
          _atSignIndex = -1;
        });
      return;
    }

    // 限制搜索词长度
    if (afterAt.length > 30) {
      if (_mentionQuery != null)
        setState(() {
          _mentionQuery = null;
          _atSignIndex = -1;
        });
      return;
    }

    setState(() {
      _atSignIndex = lastAt;
      _mentionQuery = afterAt;
    });
  }

  /// 插入 @ 提及并记录用户 ID
  void _insertMention(api.ChatMember member) {
    final text = _inputController.text;
    final cursor = _inputController.selection.baseOffset;
    final mentionText = '@${member.displayName} ';

    final safeCursor = (cursor >= 0 && cursor <= text.length)
        ? cursor
        : text.length;
    final newText =
        text.substring(0, _atSignIndex) +
        mentionText +
        text.substring(safeCursor);

    _inputController.text = newText;
    _inputController.selection = TextSelection.collapsed(
      offset: _atSignIndex + mentionText.length,
    );

    if (!_pendingMentionIds.contains(member.userId)) {
      _pendingMentionIds.add(member.userId);
    }

    setState(() {
      _mentionQuery = null;
      _atSignIndex = -1;
    });

    _inputFocusNode.requestFocus();
  }

  /// 发送消息时停止 typing 状态
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
    // 移除生命周期观察者
    WidgetsBinding.instance.removeObserver(this);

    // 停止 typing 状态
    _stopTyping();

    // 取消定时器
    _keyboardDismissTimer?.cancel();
    _keyboardDismissTimer = null;
    _typingTimer?.cancel();
    _typingTimer = null;
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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();

    // 移除输入监听器
    _inputController.removeListener(_onInputChanged);

    // 清理输入相关
    _inputController.dispose();
    _inputFocusNode.dispose();

    // 移除 Ctrl+V 键盘监听
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted) return;
    // 应用从后台恢复时自动刷新消息
    // 但如果是从系统相机返回，跳过刷新，避免冲掉正在发送的本地消息
    if (state == AppLifecycleState.resumed) {
      if (_isUsingCamera) {
        // 相机返回，不刷新消息，只刷新在线状态
        ref.invalidate(chatDetailProvider(widget.chatId));
        return;
      }
      // 先标记 inactive，再标记 active，触发 setActive 内部的增量同步
      final notifier = ref.read(messageListProvider(widget.chatId).notifier);
      notifier.setActive(false);
      notifier.setActive(true);
      notifier.loadMessages();
      _loadPinnedMessage();
      if (widget.chatType == ChatType.group) {
        _loadActiveMeeting();
      }
      // 刷新聊天详情（在线状态等）
      ref.invalidate(chatDetailProvider(widget.chatId));
    }
  }

  /// 清理逻辑（返回时执行）
  void _cleanupOnExit() {
    // 防止重复执行（back button 和 PopScope 会双重触发）
    if (_hasCleanedUp || !mounted) return;
    _hasCleanedUp = true;
    // 标记不再活跃，停止发送已读回执
    ref.read(messageListProvider(widget.chatId).notifier).setActive(false);
    // 清除活跃聊天 ID
    ref.read(chatListProvider.notifier).setActiveChatId(null);
    // 确保清除本地未读计数（不触发网络刷新，避免重复请求）
    ref.read(chatListProvider.notifier).markAsRead(widget.chatId);
  }

  /// 处理返回按钮点击
  void _handleBackButton() {
    _cleanupOnExit();
    Navigator.of(context).pop();
  }

  void _onScroll() {
    if (!mounted) return;

    final showButton = _scrollController.offset > 200;
    if (showButton != _showScrollToBottom) {
      setState(() => _showScrollToBottom = showButton);
    }

    // 键盘收起防抖：滚动 300ms 后才收起，避免频繁触发
    if (_inputFocusNode.hasFocus) {
      _keyboardDismissTimer?.cancel();
      _keyboardDismissTimer = Timer(const Duration(milliseconds: 300), () {
        if (_inputFocusNode.hasFocus && mounted) {
          _inputFocusNode.unfocus();
        }
      });
    }

    // 分页加载：接近顶部时加载更多（列表是 reverse 的，所以是 maxScrollExtent）
    if (_scrollController.hasClients && !_isLoadingMore) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      // 距离顶部 500 像素时开始加载
      if (maxScroll - currentScroll < 500) {
        _loadMoreMessages();
      }
    }
  }

  /// 加载更多历史消息
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore) return;
    _isLoadingMore = true;
    try {
      await ref
          .read(messageListProvider(widget.chatId).notifier)
          .loadMoreMessages();
    } finally {
      _isLoadingMore = false;
    }
  }

  /// 收起键盘和表情选择器
  void _dismissKeyboardAndEmoji() {
    // 收起键盘
    if (_inputFocusNode.hasFocus) {
      _inputFocusNode.unfocus();
    }
    // 收起表情选择器
    if (_showEmojiPickerState) {
      setState(() => _showEmojiPickerState = false);
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  /// 滚动到指定消息（用于点击回复预览时跳转）
  void _scrollToMessage(String messageId) {
    final messages = ref.read(messageListProvider(widget.chatId));
    final index = messages.indexWhere((m) => m.id == messageId);

    if (index == -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('消息不在当前视图中'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    // 通过 GlobalObjectKey 找到目标消息的 RenderObject，精确滚动
    final key = GlobalObjectKey(messageId);
    final targetContext = key.currentContext;
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      _highlightMessage(messageId);
    }
  }

  /// 高亮显示目标消息
  String? _highlightedMessageId;
  void _highlightMessage(String messageId) {
    setState(() => _highlightedMessageId = messageId);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ref.listen<AsyncValue<SystemSettings>>(systemSettingsProvider, (
      previous,
      next,
    ) {
      final allowed = next.valueOrNull?.burnAfterReadEnabled ?? true;
      if (!allowed && _burnAfterReadEnabled && mounted) {
        setState(() => _burnAfterReadEnabled = false);
      }
    });
    // 换号后 messageListProvider 会重建，但本页 initState 不会再次执行，需补一次加载与订阅
    ref.listen<String>(authServiceProvider.select((s) => s.user?.uuid ?? ''), (
      previous,
      next,
    ) {
      final p = previous ?? '';
      final n = next ?? '';
      if (p.isNotEmpty && n.isNotEmpty && p != n) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ref.read(chatListProvider.notifier).setActiveChatId(widget.chatId);
          ref.read(webSocketServiceProvider.notifier).subscribeChats([
            widget.chatId,
          ]);
          unawaited(ref.read(contactListProvider.notifier).initialize());
          ref.read(messageListProvider(widget.chatId).notifier).initialize();
          ref.read(chatListProvider.notifier).markAsRead(widget.chatId);
        });
      }
    });
    // 不在顶层 watch messageList，避免每条消息触发整页 rebuild
    // messages 只在 _buildMessageList 的 Consumer 内 watch
    final chatBackground = ref.watch(chatBackgroundProvider);

    final isDesktop =
        PlatformUtils.isPhysicalDesktop;

    Widget content = PopScope(
      canPop: true, // 允许左滑返回
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // 返回时执行清理逻辑（不再调用 pop，因为系统已经 pop 了）
          _cleanupOnExit();
        }
      },
      child: Scaffold(
        backgroundColor: isDark
            ? AppColors.darkBackground
            : AppColors.lightBackground,
        extendBodyBehindAppBar: true,
        extendBody: true,
        body: Stack(
          children: [
            // 聊天背景 - 全屏显示（使用 RepaintBoundary 避免重绘）
            Positioned.fill(
              child: RepaintBoundary(
                child: ChatBackgroundWidget(
                  background: chatBackground,
                  isDark: isDark,
                ),
              ),
            ),

            // 主内容
            SafeArea(
              top: false,
              bottom: false,
              child: Column(
                children: [
                  // 根据类型显示不同顶部栏（带毛玻璃效果）
                  _buildTopBar(isDark),

                  // 置顶消息条
                  if (_pinnedMessageText != null &&
                      _pinnedMessageText!.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        if (_pinnedMessageId != null) {
                          _scrollToMessage(_pinnedMessageId!);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.blue.shade900.withOpacity(0.95)
                              : Colors.blue.shade50,
                          border: Border(
                            bottom: BorderSide(
                              color: isDark
                                  ? Colors.blue.shade700
                                  : Colors.blue.shade200,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.push_pin,
                              size: 16,
                              color: Colors.blue.shade600,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _pinnedMessageText!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () async {
                                final chatService = ref.read(
                                  api.chatServiceProvider,
                                );
                                final response = await chatService.unpinMessage(
                                  widget.chatId,
                                );
                                if (!mounted) return;

                                if (response.isSuccess) {
                                  _clearPinnedMessage();
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        response.message.isNotEmpty
                                            ? response.message
                                            : '取消置顶失败',
                                      ),
                                    ),
                                  );
                                }
                              },
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 群公告置顶栏
                  if (_announcementText != null &&
                      _announcementText!.isNotEmpty &&
                      !_announcementDismissed &&
                      widget.chatType != ChatType.private)
                    GestureDetector(
                      onTap: () => _showAnnouncementDetail(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.orange.shade900.withOpacity(0.95)
                              : Colors.orange.shade50,
                          border: Border(
                            bottom: BorderSide(
                              color: isDark
                                  ? Colors.orange.shade700
                                  : Colors.orange.shade200,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.campaign,
                              size: 16,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _announcementText!,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () {
                                setState(() => _announcementDismissed = true);
                              },
                              child: Icon(
                                Icons.close,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 消息列表（点击收起键盘和表情选择器）
                  if (widget.chatType == ChatType.group &&
                      _activeMeetingInfo != null)
                    _buildActiveMeetingBannerCompact(isDark),
                  Expanded(
                    child: RepaintBoundary(
                      child: GestureDetector(
                        onTap: () => _dismissKeyboardAndEmoji(),
                        behavior: HitTestBehavior.translucent,
                        // Consumer 隔离：只有消息列表区域随消息变化 rebuild
                        child: Consumer(
                          builder: (context, ref, _) {
                            final messages = ref.watch(
                              messageListProvider(widget.chatId),
                            );
                            return messages.isEmpty
                                ? _buildEmptyChat()
                                : _buildMessageList(messages, isDark);
                          },
                        ),
                      ),
                    ),
                  ),

                  // 输入区域 或 选择模式操作栏
                  if (_isSelectionMode)
                    _buildSelectionActionBar(isDark)
                  else if (_isRecordingVoice)
                    VoiceRecordOverlay(
                      onSend: _stopVoiceRecord,
                      onCancel: _cancelVoiceRecord,
                    )
                  else
                    _buildInputArea(isDark),
                ],
              ),
            ),

            // 回到底部按钮
            if (_showScrollToBottom)
              Positioned(
                right: 16,
                bottom: 100,
                child: _ScrollToBottomButton(onTap: _scrollToBottom),
              ),

            // 桌面端拖拽提示遮罩
            if (_isDragging && isDesktop)
              Positioned.fill(
                child: Container(
                  color: AppColors.primary.withOpacity(0.15),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 24,
                      ),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.file_upload_outlined,
                            size: 48,
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '松开发送文件',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '支持图片、视频、文档等',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // 桌面端包装拖拽功能
    if (isDesktop) {
      return DropTarget(
        onDragEntered: (details) {
          setState(() => _isDragging = true);
        },
        onDragExited: (details) {
          setState(() => _isDragging = false);
        },
        onDragDone: (details) {
          setState(() => _isDragging = false);
          _handleDroppedFiles(details.files);
        },
        child: content,
      );
    }

    return content;
  }

  /// 处理拖拽的文件
  Future<void> _handleDroppedFiles(List<XFile> files) async {
    for (final xfile in files) {
      final path = xfile.path;
      final extension = path.split('.').last.toLowerCase();
      final fileName = path.split('/').last;

      // 判断文件类型
      final imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
      final videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'webm'];

      if (imageExtensions.contains(extension)) {
        // 发送图片
        final file = File(path);
        final decodedImage = await decodeImageFromList(
          await file.readAsBytes(),
        );
        ref
            .read(messageListProvider(widget.chatId).notifier)
            .sendImageMessage(
              path,
              width: decodedImage.width,
              height: decodedImage.height,
              burnAfterRead: _activeBurnAfterRead,
            );
        _updateChatListPreview('[图片]', type: MessageContentType.photo);
      } else if (videoExtensions.contains(extension)) {
        // 发送视频
        ref
            .read(messageListProvider(widget.chatId).notifier)
            .sendVideoMessage(path, burnAfterRead: _activeBurnAfterRead);
        _updateChatListPreview('[视频]', type: MessageContentType.video);
      } else {
        // 发送文件
        ref
            .read(messageListProvider(widget.chatId).notifier)
            .sendFileMessage(
              path,
              fileName,
              burnAfterRead: _activeBurnAfterRead,
            );
        _updateChatListPreview('[文件] $fileName', type: MessageContentType.file);
      }
    }
    _scrollToBottom();
  }

  ChatItem? _findCurrentChatItem(ChatListState chatListState) {
    for (final chat in chatListState.allChats) {
      if (chat.id == widget.chatId) return chat;
    }
    return null;
  }

  ContactItem? _findPrivateContact(
    List<ContactItem> contacts,
    api.Chat? detailChat,
    ChatItem? listChat,
  ) {
    if (widget.chatType != ChatType.private) return null;

    final ids = <String?>[
      detailChat?.targetUserId,
      listChat?.targetUserUuid,
      listChat?.targetUserId,
      widget.chatId,
    ].where((id) => id != null && id.isNotEmpty).cast<String>().toSet();

    for (final contact in contacts) {
      if ((contact.uuid != null && ids.contains(contact.uuid)) ||
          ids.contains(contact.id)) {
        return contact;
      }
    }
    return null;
  }

  String _resolveChatDisplayName(
    api.Chat? detailChat,
    ChatItem? listChat,
    ContactItem? privateContact,
  ) {
    final candidates = widget.chatType == ChatType.private
        ? <String?>[
            privateContact?.name,
            detailChat?.name,
            listChat?.name,
            widget.chatName,
          ]
        : <String?>[detailChat?.name, listChat?.name, widget.chatName];

    for (final value in candidates) {
      final text = value?.trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return '聊天';
  }

  Map<String, String> _buildContactDisplayNameMap(List<ContactItem> contacts) {
    final result = <String, String>{};
    for (final contact in contacts) {
      final name = contact.name.trim();
      if (name.isEmpty) continue;
      if (contact.id.isNotEmpty) result[contact.id] = name;
      final uuid = contact.uuid;
      if (uuid != null && uuid.isNotEmpty) result[uuid] = name;
    }
    return result;
  }

  MessageItem _applyContactDisplayName(
    MessageItem message,
    Map<String, String> contactDisplayNames,
  ) {
    if (message.isOutgoing) return message;
    final displayName = contactDisplayNames[message.senderId];
    if (displayName == null ||
        displayName.isEmpty ||
        displayName == message.senderName) {
      return message;
    }
    return message.copyWith(senderName: displayName);
  }

  /// 根据聊天类型构建不同的顶部栏
  Widget _buildTopBar(bool isDark) {
    final chatDetailAsync = ref.watch(chatDetailProvider(widget.chatId));
    final contacts = ref.watch(contactListProvider);
    final chatListState = ref.watch(chatListProvider);
    final listChat = _findCurrentChatItem(chatListState);
    final detailChat = chatDetailAsync.valueOrNull;
    final privateContact = _findPrivateContact(contacts, detailChat, listChat);
    final displayName = _resolveChatDisplayName(
      detailChat,
      listChat,
      privateContact,
    );
    final displayAvatar =
        privateContact?.avatar ??
        detailChat?.avatar ??
        listChat?.avatar ??
        widget.avatar;
    final displayUserId = widget.chatType == ChatType.private
        ? (privateContact?.uuid ??
              privateContact?.id ??
              detailChat?.targetUserId ??
              listChat?.targetUserUuid ??
              listChat?.targetUserId ??
              widget.chatId)
        : widget.chatId;
    final displayPremiumType =
        privateContact?.premiumType ??
        detailChat?.premiumType ??
        listChat?.premiumType;
    final displayIsMember =
        (privateContact?.isMember ??
            detailChat?.isMember ??
            listChat?.isMember) ??
        false;
    final displayBadgeColor =
        privateContact?.badgeColor ??
        detailChat?.badgeColor ??
        listChat?.badgeColor;
    final displayNicknameColor =
        privateContact?.nicknameColor ??
        detailChat?.nicknameColor ??
        listChat?.nicknameColor;
    final displayEmojiAvatar =
        privateContact?.emojiAvatar ??
        detailChat?.emojiAvatar ??
        listChat?.emojiAvatar;

    final bgColor = Platform.isAndroid || widget.isDesktopMode
        ? (isDark ? AppColors.darkBackground : AppColors.lightBackground)
        : (isDark ? Colors.black : Colors.white).withOpacity(0.5);

    final topPadding = widget.isDesktopMode
        ? 0.0
        : MediaQuery.of(context).padding.top;

    Widget content = Container(
      padding: EdgeInsets.only(top: topPadding),
      decoration: BoxDecoration(
        color: bgColor,
        boxShadow: [
          BoxShadow(
            color: (isDark ? Colors.black : const Color(0xFF94A3B8))
                .withOpacity(0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            _buildBackButton(ref),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showChatInfo(context),
                child: Row(
                  children: [
                    AvatarWidget(
                      avatar: displayAvatar,
                      name: displayName,
                      userId: displayUserId,
                      size: 40,
                      premiumType: displayPremiumType,
                      isMember: displayIsMember,
                      memberBadgeColor: displayBadgeColor,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PremiumContainer(
                        premiumType: displayPremiumType,
                        borderRadius: BorderRadius.circular(14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: ColoredNameWidget(
                                      name: displayName,
                                      nicknameColor: displayNicknameColor,
                                      premiumType: displayPremiumType,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      defaultColor: isDark
                                          ? AppColors.darkTextPrimary
                                          : AppColors.lightTextPrimary,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (displayEmojiAvatar != null &&
                                      displayEmojiAvatar.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(left: 4),
                                      child: EmojiStatusWidget(
                                        emoji: displayEmojiAvatar,
                                        size: 18,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              _buildSubtitle(chatDetailAsync, isDark),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.chatType == ChatType.private) ...[
              IconButton(
                icon: Icon(Icons.videocam_outlined, color: AppColors.primary),
                onPressed: () => _startCall(CallType.video),
              ),
              IconButton(
                icon: Icon(Icons.call_outlined, color: AppColors.primary),
                onPressed: () => _startCall(CallType.voice),
              ),
            ] else ...[
              IconButton(
                icon: Icon(Icons.search, color: AppColors.primary),
                onPressed: () {},
              ),
              Builder(
                builder: (moreCtx) => IconButton(
                  icon: Icon(Icons.more_vert, color: AppColors.primary),
                  onPressed: () => _showMoreOptions(moreCtx),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (Platform.isAndroid || widget.isDesktopMode) {
      return content;
    }
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: content,
      ),
    );
  }

  Widget _buildSubtitle(AsyncValue<dynamic> chatDetailAsync, bool isDark) {
    final defaultStyle = TextStyle(
      fontSize: 13,
      color: isDark
          ? AppColors.darkTextSecondary
          : AppColors.lightTextSecondary,
    );
    final onlineStyle = const TextStyle(fontSize: 13, color: Colors.green);
    final typingStyle = const TextStyle(
      fontSize: 13,
      color: Colors.blue,
      fontStyle: FontStyle.italic,
    );

    // 如果有人正在输入，优先显示
    if (_typingUsers.isNotEmpty) {
      final typingText = widget.chatType == ChatType.private
          ? '对方正在输入...'
          : '${_typingUsers.values.last} 正在输入...';
      return Text(typingText, style: typingStyle);
    }

    switch (widget.chatType) {
      case ChatType.private:
        // 私聊显示在线状态
        return chatDetailAsync.when(
          data: (chat) {
            final isOnline = chat != null && chat.onlineCount > 0;
            return Text(
              isOnline ? '在线' : '离线',
              style: isOnline ? onlineStyle : defaultStyle,
            );
          },
          loading: () => Text('...', style: defaultStyle),
          error: (_, __) => const SizedBox.shrink(),
        );
      case ChatType.group:
        return chatDetailAsync.when(
          data: (chat) {
            if (chat != null) {
              return Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${chat.memberCount} 位成员',
                      style: defaultStyle,
                    ),
                    if (chat.onlineCount > 0) ...[
                      TextSpan(text: '，', style: defaultStyle),
                      TextSpan(
                        text: '${chat.onlineCount} 位在线',
                        style: onlineStyle,
                      ),
                    ],
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          },
          loading: () => Text('加载中...', style: defaultStyle),
          error: (_, __) => const SizedBox.shrink(),
        );
      case ChatType.channel:
        return chatDetailAsync.when(
          data: (chat) {
            if (chat != null) {
              final count = chat.memberCount;
              String text;
              if (count >= 10000) {
                text = '${(count / 10000).toStringAsFixed(1)}万订阅者';
              } else {
                text = '$count 订阅者';
              }
              return Text(text, style: defaultStyle);
            }
            return const SizedBox.shrink();
          },
          loading: () => Text('加载中...', style: defaultStyle),
          error: (_, __) => const SizedBox.shrink(),
        );
    }
  }

  Widget _buildBackButton(WidgetRef ref) {
    // 桌面端不显示返回按钮（分栏布局）
    if (widget.isDesktopMode) {
      return const SizedBox(width: 12);
    }

    // 使用 select 只监听未读数变化，避免整个 chatState 变化时重建
    final unreadCount = ref.watch(
      chatListProvider.select((state) {
        return state.pinnedChats
                .where((c) => c.id != widget.chatId && c.unreadCount > 0)
                .fold<int>(0, (sum, c) => sum + c.unreadCount) +
            state.regularChats
                .where((c) => c.id != widget.chatId && c.unreadCount > 0)
                .fold<int>(0, (sum, c) => sum + c.unreadCount);
      }),
    );

    return IconButton(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_back_ios, size: 20, color: AppColors.primary),
          if (unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
      onPressed: _handleBackButton,
    );
  }

  void _showChatInfo(BuildContext context) async {
    final latestChat = ref.read(chatDetailProvider(widget.chatId)).valueOrNull;
    final currentName = latestChat?.name ?? widget.chatName;
    final currentAvatar = latestChat?.avatar ?? widget.avatar;
    final avatarParam = currentAvatar != null
        ? '&avatar=${Uri.encodeComponent(currentAvatar)}'
        : '';
    final nameParam = 'name=${Uri.encodeComponent(currentName)}';

    // 桌面端：在右侧面板显示资料页
    if (widget.isDesktopMode) {
      if (widget.chatType == ChatType.group) {
        ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo(
          type: DesktopProfileType.group,
          id: widget.chatId,
          name: currentName,
          avatar: currentAvatar,
        );
      } else if (widget.chatType == ChatType.channel) {
        ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo(
          type: DesktopProfileType.channel,
          id: widget.chatId,
          name: currentName,
          avatar: currentAvatar,
        );
      } else {
        // 私聊：获取对方用户 ID
        final chatDetail = ref.read(chatDetailProvider(widget.chatId));
        final targetUserId = chatDetail.value?.targetUserId ?? widget.chatId;
        ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo(
          type: DesktopProfileType.user,
          id: targetUserId,
          name: currentName,
          avatar: currentAvatar,
          chatId: widget.chatId,
        );
      }
      return;
    }

    // 移动端：导航到资料页
    if (widget.chatType == ChatType.group) {
      // 跳转到群组资料页
      context.push('/group/${widget.chatId}/profile?$nameParam$avatarParam');
    } else if (widget.chatType == ChatType.channel) {
      // 跳转到频道资料页
      context.push('/channel/${widget.chatId}/profile?$nameParam$avatarParam');
    } else {
      // 私聊：获取对方用户 ID
      final chatDetail = ref.read(chatDetailProvider(widget.chatId));
      final targetUserId = chatDetail.value?.targetUserId ?? widget.chatId;
      // 跳转到用户资料页，传入 chatId 以便加载媒体
      context.push(
        '/user/$targetUserId?$nameParam$avatarParam&chat_id=${widget.chatId}',
      );
    }
  }

  // 保留底部弹窗方法用于其他地方调用
  void _showUserInfoSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _UserInfoSheet(
        name: widget.chatName,
        avatar: widget.avatar,
        userId: widget.chatId,
      ),
    );
  }

  void _showGroupInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _GroupInfoSheet(
        name: widget.chatName,
        avatar: widget.avatar,
        groupId: widget.chatId,
      ),
    );
  }

  void _showChannelInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ChannelInfoSheet(
        name: widget.chatName,
        avatar: widget.avatar,
        channelId: widget.chatId,
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isGroup = widget.chatType == ChatType.group;
    final isChannel = widget.chatType == ChatType.channel;
    final isDesktop =
        PlatformUtils.isPhysicalDesktop;

    // 从 chatDetailProvider 获取用户角色
    final chatDetailAsync = ref.read(chatDetailProvider(widget.chatId));
    final isAdmin =
        chatDetailAsync.whenOrNull(data: (chat) => chat?.isAdmin) ?? false;

    // 桌面端使用弹出菜单
    if (isDesktop) {
      _showDesktopPopupMenu(context, isGroup, isChannel, isAdmin, isDark);
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkDivider
                      : AppColors.lightDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // 管理员或群主才显示管理选项
              if (isAdmin && (isGroup || isChannel))
                _OptionTile(
                  icon: Icons.settings_outlined,
                  title: isChannel ? '管理频道' : '管理群组',
                  onTap: () {
                    Navigator.pop(context);
                    _openEditPage(context);
                  },
                ),

              // 所有用户都能搜索
              _OptionTile(
                icon: Icons.search,
                title: '搜索',
                onTap: () => Navigator.pop(context),
              ),
              _OptionTile(
                icon: Icons.bookmark_outline,
                title: '收藏',
                onTap: () {
                  Navigator.pop(context);
                  _openFavoriteMessages();
                },
              ),

              // 退出/取消订阅
              if (isGroup)
                _OptionTile(
                  icon: Icons.exit_to_app,
                  title: '退出群组',
                  isDestructive: true,
                  onTap: () {
                    Navigator.pop(context);
                    _showLeaveConfirmDialog(context, isChannel: false);
                  },
                ),
              if (isChannel)
                _OptionTile(
                  icon: Icons.exit_to_app,
                  title: '取消订阅',
                  isDestructive: true,
                  onTap: () {
                    Navigator.pop(context);
                    _showLeaveConfirmDialog(context, isChannel: true);
                  },
                ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showDesktopPopupMenu(
    BuildContext context,
    bool isGroup,
    bool isChannel,
    bool isAdmin,
    bool isDark,
  ) {
    final buttonObj = context.findRenderObject();
    if (buttonObj is! RenderBox) return;
    final RenderBox button = buttonObj;
    final overlayState = Navigator.of(context).overlay;
    if (overlayState == null) return;
    final overlayObj = overlayState.context.findRenderObject();
    if (overlayObj is! RenderBox) return;
    final RenderBox overlay = overlayObj;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(
          Offset(button.size.width - 200, 50),
          ancestor: overlay,
        ),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? AppColors.darkSurface : Colors.white,
      items: [
        if (isAdmin && (isGroup || isChannel))
          PopupMenuItem(
            value: 'manage',
            child: Row(
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: 20,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                const SizedBox(width: 12),
                Text(isChannel ? '管理频道' : '管理群组'),
              ],
            ),
          ),
        PopupMenuItem(
          value: 'search',
          child: Row(
            children: [
              Icon(
                Icons.search,
                size: 20,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              const SizedBox(width: 12),
              const Text('搜索'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'favorites',
          child: Row(
            children: [
              Icon(
                Icons.bookmark_outline,
                size: 20,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              const SizedBox(width: 12),
              const Text('收藏'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'leave',
          child: Row(
            children: [
              Icon(Icons.exit_to_app, size: 20, color: AppColors.error),
              const SizedBox(width: 12),
              Text(
                isChannel ? '取消订阅' : '退出群组',
                style: TextStyle(color: AppColors.error),
              ),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == null) return;
      switch (value) {
        case 'manage':
          _openEditPage(context);
          break;
        case 'search':
          // TODO: 打开搜索
          break;
        case 'favorites':
          _openFavoriteMessages();
          break;
        case 'leave':
          _showLeaveConfirmDialog(context, isChannel: isChannel);
          break;
      }
    });
  }

  void _openEditPage(BuildContext context) {
    final isDesktop =
        PlatformUtils.isPhysicalDesktop;
    final isChannel = widget.chatType == ChatType.channel;

    if (isDesktop) {
      ref.read(desktopProfileProvider.notifier).state = DesktopProfileInfo(
        type: isChannel
            ? DesktopPanelType.channelEdit
            : DesktopPanelType.groupEdit,
        id: widget.chatId,
      );
    } else {
      context.push('/group/edit/${widget.chatId}');
    }
  }

  /// 显示退出/取消订阅确认对话框（TG风格底部弹窗）
  void _showLeaveConfirmDialog(
    BuildContext context, {
    required bool isChannel,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = isChannel ? '取消订阅' : '退出群组';
    final actionTitle = isChannel
        ? '取消订阅「${widget.chatName}」？'
        : '退出「${widget.chatName}」？';
    final message = isChannel ? '取消订阅后将不再接收此频道的消息' : '退出后将不再接收此群组的消息';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 操作区域
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  // 标题和描述
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Column(
                      children: [
                        Text(
                          actionTitle,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  // 确认按钮
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(context);
                        _leaveChat();
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 20,
                            color: AppColors.error,
                            fontWeight: FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // 取消按钮
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 20,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  /// 退出群组/取消订阅频道
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
      ).showSnackBar(SnackBar(content: Text(errorMsg ?? '操作失败，请重试')));
    }
  }

  Widget _buildEmptyChat() {
    // 根据聊天类型选择不同的提示文字
    String titleText;
    String subtitleText;

    if (widget.chatType == ChatType.group) {
      titleText = '暂无消息';
      subtitleText = '发送第一条消息，开始群聊吧！';
    } else if (widget.chatType == ChatType.channel) {
      titleText = '暂无消息';
      subtitleText = '频道内容将在这里显示';
    } else {
      titleText = '暂无消息';
      subtitleText = '发送消息开始聊天';
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 使用破壳小鸡动画
          Lottie.asset(
            'assets/emoji/lottie/hatching_chick.json',
            width: 120,
            height: 120,
            repeat: true,
          ),
          const SizedBox(height: 20),
          Text(
            titleText,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitleText,
            style: TextStyle(fontSize: 14, color: AppColors.lightTextTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList(List<MessageItem> messages, bool isDark) {
    // 性能优化：bubbleColors 在 ListView 外层一次性获取，避免每个 item 都 watch
    final bubbleColors = ref.watch(bubbleColorProvider);
    final contactDisplayNames = _buildContactDisplayNameMap(
      ref.watch(contactListProvider),
    );
    final chatDetail = ref.watch(chatDetailProvider(widget.chatId)).valueOrNull;
    final canOpenMemberProfile =
        !(widget.chatType == ChatType.group &&
            (chatDetail?.memberProtection ?? false) &&
            (chatDetail?.myRole ?? 0) < 2);

    return NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        if (_inputFocusNode.hasFocus) {
          _inputFocusNode.unfocus();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        itemCount: messages.length,
        cacheExtent: 400,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        addSemanticIndexes: false,
        physics: Theme.of(context).platform == TargetPlatform.iOS
            ? const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              )
            : const ClampingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
        itemBuilder: (context, index) {
          final message = _applyContactDisplayName(
            messages[index],
            contactDisplayNames,
          );
          final previousMessage = index < messages.length - 1
              ? _applyContactDisplayName(
                  messages[index + 1],
                  contactDisplayNames,
                )
              : null;
          final nextMessage = index > 0
              ? _applyContactDisplayName(
                  messages[index - 1],
                  contactDisplayNames,
                )
              : null;

          final showDateDivider =
              previousMessage == null ||
              !_isSameDay(message.createdAt, previousMessage.createdAt);

          final isFirstInGroup =
              previousMessage == null ||
              previousMessage.senderId != message.senderId ||
              message.createdAt
                      .difference(previousMessage.createdAt)
                      .inMinutes >
                  5;

          final isLastInGroup =
              nextMessage == null ||
              nextMessage.senderId != message.senderId ||
              nextMessage.createdAt.difference(message.createdAt).inMinutes > 5;

          return Column(
            key: GlobalObjectKey(message.id),
            children: [
              if (showDateDivider) _buildDateDivider(message.createdAt),
              if (message.isDeleted)
                _buildSystemMessage(() {
                  final currentUserId = ref
                      .read(authServiceProvider)
                      .user
                      ?.uuid;
                  final revokedBy = message.revokedBy;
                  // 自己撤回
                  if (message.isOutgoing ||
                      (revokedBy != null && revokedBy == currentUserId)) {
                    return '你撤回了一条消息';
                  }
                  // 管理员撤回了他人的消息（消息发送者不是撤回者）
                  if (widget.chatType == ChatType.group &&
                      revokedBy != null &&
                      revokedBy != message.senderId) {
                    return '管理员撤回了一条消息';
                  }
                  return '对方撤回了一条消息';
                }())
              else if (message.type == MessageItemType.system)
                _buildSystemMessage(message.content)
              else
                Container(
                  decoration: _highlightedMessageId == message.id
                      ? BoxDecoration(
                          color: AppColors.primary.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        )
                      : null,
                  child: RepaintBoundary(
                    child: _isSelectionMode
                        ? _buildSelectableMessage(
                            message,
                            isFirstInGroup,
                            isLastInGroup,
                            bubbleColors,
                            isDark,
                          )
                        : MessageBubble(
                            message: message,
                            isFirstInGroup: isFirstInGroup,
                            isLastInGroup: isLastInGroup,
                            showSenderName:
                                widget.chatType != ChatType.private &&
                                !message.isOutgoing,
                            isGroupChat: widget.chatType == ChatType.group,
                            onTap: _buildMessageTapHandler(message),
                            onLongPressStart: (details) => _showMessageOptions(
                              message,
                              details.globalPosition,
                            ),
                            onSecondaryTapDown: (details) =>
                                _showMessageOptions(
                                  message,
                                  details.globalPosition,
                                ),
                            onDoubleTap: () => _reactToMessage(message),
                            customOutgoingColor: bubbleColors.outgoing,
                            customIncomingColor: bubbleColors.incoming,
                            canOpenMemberProfile: canOpenMemberProfile,
                            onMentionUser: widget.chatType != ChatType.private
                                ? (userId, userName) =>
                                      _mentionUser(userId, userName)
                                : null,
                            onReplyTap: message.replyTo != null
                                ? () => _scrollToMessage(
                                    message.replyTo!.messageId,
                                  )
                                : null,
                          ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDateDivider(DateTime date) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          _formatDateDivider(date),
          style: const TextStyle(
            fontSize: 13,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // 系统消息（如"xxx 加入了群组"）居中小字显示
  Widget _buildSystemMessage(String content) {
    final displayText = resolveSystemMessageText(
      content,
      currentUserId: ref.read(authServiceProvider).user?.uuid,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.15),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            displayText,
            style: const TextStyle(fontSize: 13, color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatDateDivider(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) return '今天';
    if (messageDate == yesterday) return '昨天';
    if (date.year == now.year) return '${date.month}月${date.day}日';
    return '${date.year}年${date.month}月${date.day}日';
  }

  /// 构建多选模式操作栏
  Widget _buildSelectionActionBar(bool isDark) {
    final count = _selectedMessageIds.length;
    final selectedMessages = ref
        .watch(messageListProvider(widget.chatId))
        .where((message) => _selectedMessageIds.contains(message.id))
        .toList(growable: false);
    final canForwardSelected =
        count > 0 && !selectedMessages.any((message) => message.burnAfterRead);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).padding.bottom,
          ),
          decoration: BoxDecoration(
            color: (isDark ? Colors.black : Colors.white).withOpacity(0.85),
            border: Border(
              top: BorderSide(
                color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
              ),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  // 取消按钮
                  TextButton.icon(
                    onPressed: _exitSelectionMode,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    label: Text(
                      '取消',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontSize: 15,
                      ),
                    ),
                  ),

                  // 选中数量
                  Expanded(
                    child: Center(
                      child: Text(
                        '已选择 $count 条消息',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    ),
                  ),

                  // 操作按钮
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 转发
                      IconButton(
                        onPressed: canForwardSelected
                            ? _forwardSelectedMessages
                            : null,
                        icon: Icon(
                          Icons.shortcut_rounded,
                          color: canForwardSelected
                              ? AppColors.primary
                              : (isDark ? Colors.white24 : Colors.black26),
                        ),
                        tooltip: '转发',
                      ),

                      // 删除
                      IconButton(
                        onPressed: count > 0 ? _deleteSelectedMessages : null,
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: count > 0
                              ? AppColors.error
                              : (isDark ? Colors.white24 : Colors.black26),
                        ),
                        tooltip: '删除',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 构建输入区域（检查禁言状态）
  Widget _buildInputArea(bool isDark) {
    // 私聊不检查禁言
    if (widget.chatType == ChatType.private) {
      return _buildInputWithPreview(isDark);
    }
    // 群组和频道
    return _buildInputAreaForGroupChannel(isDark);
  }

  /// 构建带回复/编辑预览的输入区域
  Widget _buildInputWithPreview(bool isDark) {
    final burnAfterReadAllowed =
        ref.watch(systemSettingsProvider).valueOrNull?.burnAfterReadEnabled ??
        true;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // @ 提及成员选择面板（群聊/频道）
        if (_mentionQuery != null && widget.chatType != ChatType.private)
          _buildMentionPicker(isDark),

        // 待发送图片预览面板
        if (_pendingImages.isNotEmpty) _buildPendingImagesPanel(isDark),

        // 回复/编辑预览栏
        if (_replyToMessage != null || _editingMessage != null)
          _buildReplyEditPreview(isDark),

        if (burnAfterReadAllowed && _burnAfterReadEnabled)
          _buildBurnAfterReadBanner(isDark),

        // 输入栏
        ChatInputBar(
          controller: _inputController,
          focusNode: _inputFocusNode,
          onSend: (text) => _sendMessageWithContext(text),
          onAttachment: _showAttachmentOptions,
          onVoice: _startVoiceRecord,
          onBurnAfterReadToggle: _toggleBurnAfterRead,
          showEmojiPicker: _showEmojiPickerState,
          onEmojiToggle: _toggleEmojiPicker,
          allowBurnAfterRead: burnAfterReadAllowed,
          burnAfterReadEnabled: _burnAfterReadEnabled,
          hasPendingAttachments: _pendingImages.isNotEmpty,
        ),
      ],
    );
  }

  Widget _buildBurnAfterReadBanner(bool isDark) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x332A1B12) : const Color(0xFFFFF3E8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? const Color(0x66FF8A50) : const Color(0xFFFFC7A7),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            size: 18,
            color: Color(0xFFE65100),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '已开启阅后即焚，对方已读后自动销毁',
              style: TextStyle(
                fontSize: 13,
                color: isDark ? Colors.white70 : const Color(0xFF9A3412),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// @ 提及成员列表面板
  Widget _buildMentionPicker(bool isDark) {
    final query = _mentionQuery ?? '';
    final membersAsync = ref.watch(chatMembersProvider(widget.chatId));

    return membersAsync.when(
      data: (members) {
        final currentUserId = ref.read(authServiceProvider).user?.uuid;
        final filtered = members
            .where((m) {
              if (m.userId == currentUserId) return false; // 排除自己
              if (query.isEmpty) return true;
              final q = query.toLowerCase();
              return m.displayName.toLowerCase().contains(q) ||
                  m.username.toLowerCase().contains(q);
            })
            .take(8)
            .toList();

        if (filtered.isEmpty) return const SizedBox.shrink();

        return Container(
          constraints: const BoxConstraints(maxHeight: 256),
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.4 : 0.12),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => Divider(
                height: 1,
                thickness: 0.5,
                color: isDark
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.06),
                indent: 52,
              ),
              itemBuilder: (context, index) {
                final member = filtered[index];
                return InkWell(
                  onTap: () => _insertMention(member),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        AvatarWidget(
                          avatar: member.avatar,
                          name: member.displayName,
                          size: 32,
                          userId: member.userId,
                          premiumType: member.premiumType,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ColoredNameWidget(
                                name: member.displayName,
                                nicknameColor: member.nicknameColor,
                                premiumType: member.premiumType,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                defaultColor: isDark
                                    ? Colors.white
                                    : Colors.black87,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (member.username.isNotEmpty)
                                Text(
                                  '@${member.username}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (member.role >= 2)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              member.roleName,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  /// TG 风格待发送图片预览面板
  Widget _buildPendingImagesPanel(bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.primary.withOpacity(0.15)
            : AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.image_outlined,
                size: 16,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
              const SizedBox(width: 6),
              Text(
                '${_pendingImages.length} 张图片（可输入说明文字后发送）',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _pendingImages.clear()),
                child: Icon(
                  Icons.close,
                  size: 18,
                  color: isDark ? Colors.white54 : Colors.black38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _pendingImages.length,
              itemBuilder: (_, i) {
                final img = _pendingImages[i];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: img.bytes != null
                            ? Image.memory(
                                img.bytes!,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              )
                            : Image.file(
                                File(img.path!),
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                      ),
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _pendingImages.removeAt(i)),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 构建回复/编辑预览栏 - TG风格
  Widget _buildReplyEditPreview(bool isDark) {
    final isEditing = _editingMessage != null;
    final message = isEditing ? _editingMessage! : _replyToMessage!;
    final accentColor = isEditing ? AppColors.warning : AppColors.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      decoration: BoxDecoration(
        color: isDark
            ? accentColor.withOpacity(0.15)
            : accentColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            // 左侧彩色竖条
            Container(width: 4, height: 44, color: accentColor),
            const SizedBox(width: 10),

            // 内容
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题行
                    Row(
                      children: [
                        if (isEditing)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 14,
                              color: accentColor,
                            ),
                          ),
                        Text(
                          isEditing ? '编辑消息' : message.senderName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: accentColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    // 消息预览
                    Text(
                      _getMessagePreview(message),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 关闭按钮
            GestureDetector(
              onTap: () {
                GlobalHaptics.selection();
                if (isEditing) {
                  _cancelEdit();
                } else {
                  _cancelReply();
                }
              },
              child: Container(
                width: 40,
                height: 44,
                alignment: Alignment.center,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white12
                        : Colors.black.withOpacity(0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  /// 获取消息预览文本
  String _getMessagePreview(MessageItem message) {
    switch (message.type) {
      case MessageItemType.text:
        return message.content;
      case MessageItemType.image:
        return '📷 图片';
      case MessageItemType.video:
        return '🎬 视频';
      case MessageItemType.voice:
        return '🎤 语音消息';
      case MessageItemType.file:
        return '📎 ${message.fileName ?? "文件"}';
      default:
        return message.content;
    }
  }

  /// 发送消息（处理回复和编辑）。[content] 为可选，表情选择器会直接传入 emoji，否则用输入框内容。
  void _sendMessageWithContext([String? content]) async {
    final text = (content ?? _inputController.text).trim();

    // 如果有待发送图片，优先作为图文消息发送
    if (_pendingImages.isNotEmpty) {
      await _sendPendingImages(caption: text.isNotEmpty ? text : null);
      return;
    }

    if (text.startsWith(EmojiStoreService.customEmojiSendUrlPrefix)) {
      final imageUrl = text.substring(
        EmojiStoreService.customEmojiSendUrlPrefix.length,
      );
      if (imageUrl.isEmpty) return;

      await ref
          .read(messageListProvider(widget.chatId).notifier)
          .sendImageByUrl(imageUrl, burnAfterRead: _activeBurnAfterRead);
      _updateChatListPreview('[自定义表情]', type: MessageContentType.photo);
      _inputController.clear();
      _scrollToBottom();
      GlobalHaptics.light();
      _inputFocusNode.requestFocus();
      return;
    }

    if (text.startsWith(EmojiStoreService.customEmojiSendPrefix)) {
      final imagePath = text.substring(
        EmojiStoreService.customEmojiSendPrefix.length,
      );
      if (imagePath.isEmpty) return;

      final file = File(imagePath);
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('自定义表情文件不存在')));
        }
        return;
      }

      await ref
          .read(messageListProvider(widget.chatId).notifier)
          .sendImageMessage(imagePath, burnAfterRead: _activeBurnAfterRead);
      _updateChatListPreview('[自定义表情]', type: MessageContentType.photo);
      _inputController.clear();
      _scrollToBottom();
      GlobalHaptics.light();
      _inputFocusNode.requestFocus();
      return;
    }

    if (text.isEmpty) return;

    // 发送消息时停止 typing 状态
    _stopTyping();

    // 如果是编辑模式
    if (_editingMessage != null) {
      if (text != _originalEditContent) {
        final success = await ref
            .read(messageListProvider(widget.chatId).notifier)
            .editMessage(_editingMessage!.id, text);

        if (!mounted) return;

        if (!success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('编辑失败'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
      _cancelEdit();
      _inputController.clear();
      return;
    }

    // 如果是回复模式
    if (_replyToMessage != null) {
      // 发送带回复的消息
      final replyInfo = ReplyInfo(
        messageId: _replyToMessage!.id,
        senderName: _replyToMessage!.senderName,
        content: _replyToMessage!.content,
      );
      ref
          .read(messageListProvider(widget.chatId).notifier)
          .sendTextMessage(
            text,
            replyTo: replyInfo,
            burnAfterRead: _activeBurnAfterRead,
          )
          .then((error) {
            if (error != null && mounted) {
              _showMessageSendError(error);
            }
          });
      // 更新聊天列表的最后一条消息预览
      _updateChatListPreview(text, type: MessageContentType.text);
      _cancelReply();
    } else {
      // 普通发送（_sendMessage 内部已处理 clear/scroll/haptic）
      _sendMessage(text);
      return;
    }

    // 回复模式在此统一处理 clear/scroll/haptic
    _inputController.clear();
    _scrollToBottom();
    GlobalHaptics.light();
    // 发送后保持/恢复输入框焦点
    _inputFocusNode.requestFocus();
  }

  // 原始构建输入区域逻辑（用于群组和频道）
  Widget _buildInputAreaForGroupChannel(bool isDark) {
    // 频道：检查是否已订阅
    if (widget.chatType == ChatType.channel) {
      final chatDetail = ref.watch(chatDetailProvider(widget.chatId));
      return chatDetail.when(
        data: (chat) {
          // myRole == 0 表示未订阅
          if (chat == null || chat.myRole == 0) {
            // 检查是否已提交申请
            if (chat?.pendingRequest == true) {
              return _buildPendingRequestBar(isDark);
            }
            return _buildJoinButton(isDark, isChannel: true);
          }
          // 已订阅，检查禁言状态
          return _buildMuteStatusInputArea(isDark);
        },
        loading: () => _buildMuteStatusInputArea(isDark),
        error: (_, __) => _buildJoinButton(isDark, isChannel: true),
      );
    }

    // 群组：检查是否已加入
    if (widget.chatType == ChatType.group) {
      final chatDetail = ref.watch(chatDetailProvider(widget.chatId));
      return chatDetail.when(
        data: (chat) {
          // myRole == 0 表示未加入
          if (chat == null || chat.myRole == 0) {
            // 检查是否已提交申请
            if (chat?.pendingRequest == true) {
              return _buildPendingRequestBar(isDark);
            }
            return _buildJoinButton(isDark, isChannel: false);
          }
          // 已加入，检查禁言状态
          return _buildMuteStatusInputArea(isDark);
        },
        loading: () => _buildMuteStatusInputArea(isDark),
        error: (_, __) => _buildJoinButton(isDark, isChannel: false),
      );
    }

    // 默认检查禁言状态
    return _buildMuteStatusInputArea(isDark);
  }

  // 已申请等待审批状态栏
  Widget _buildPendingRequestBar(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_empty, color: Colors.orange, size: 22),
              const SizedBox(width: 8),
              Text(
                '已提交申请，等待审批',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                  color: Colors.orange,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 构建加入按钮 （支持频道和群组）
  Widget _buildJoinButton(bool isDark, {required bool isChannel}) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _joinChat(isChannel),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_circle_outline,
                    color: AppColors.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isChannel ? '加入频道' : '加入群组',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 加入频道/群组
  Future<void> _joinChat(bool isChannel) async {
    final (success, errorMsg, requiresApproval, approvalMsg) = await ref
        .read(chatListProvider.notifier)
        .joinChatFromServer(widget.chatId);

    if (!mounted) return;

    if (success) {
      if (requiresApproval) {
        // 需要审批
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              approvalMsg ?? (isChannel ? '已提交订阅申请，请等待审批' : '已提交加入申请，请等待审批'),
            ),
          ),
        );
        // 刷新详情以显示"等待审批"状态
        ref.invalidate(chatDetailProvider(widget.chatId));
      } else {
        // 直接加入成功，刷新详情
        ref.invalidate(chatDetailProvider(widget.chatId));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(isChannel ? '已订阅频道' : '已加入群组')));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg ?? (isChannel ? '订阅失败' : '加入失败'))),
      );
    }
  }

  // 构建禁言状态检查的输入区域
  Widget _buildMuteStatusInputArea(bool isDark) {
    final authState = ref.watch(authServiceProvider);
    final myUserId = authState.user?.uuid ?? '';

    if (myUserId.isEmpty) {
      return _buildInputWithPreview(isDark);
    }

    // 检查群组全员禁言权限
    final chatDetail = ref.watch(chatDetailProvider(widget.chatId));
    final chat = chatDetail.valueOrNull;

    // 频道模式: 仅管理员和创建者可发言（类似 Telegram）
    // myRole: 1=普通成员, 2=管理员, 3=群主
    if (chat != null &&
        widget.chatType == ChatType.channel &&
        chat.myRole < 2) {
      return _buildMutedBar(isDark, '仅管理员可发布内容');
    }

    // 如果群组开启了全员禁言，且当前用户不是管理员/群主
    if (chat != null &&
        widget.chatType == ChatType.group &&
        !chat.canSendMessage &&
        chat.myRole < 2) {
      return _buildMutedBar(isDark, '全员禁言中');
    }

    final muteStatus = ref.watch(
      myMuteStatusProvider((widget.chatId, myUserId)),
    );

    return muteStatus.when(
      data: (status) {
        if (status != null && status.isMuted) {
          // 被禁言，显示提示
          String muteText = '您已被禁言';
          if (status.muteEndTime != null) {
            final remaining = status.muteEndTime!.difference(DateTime.now());
            if (remaining.isNegative) {
              // 禁言已过期
              return _buildInputWithPreview(isDark);
            }
            if (remaining.inDays > 0) {
              muteText = '您已被禁言，剩余 ${remaining.inDays} 天';
            } else if (remaining.inHours > 0) {
              muteText = '您已被禁言，剩余 ${remaining.inHours} 小时';
            } else {
              muteText = '您已被禁言，剩余 ${remaining.inMinutes} 分钟';
            }
          }

          return _buildMutedBar(isDark, muteText);
        }

        // 未被禁言
        return _buildInputWithPreview(isDark);
      },
      loading: () => _buildInputWithPreview(isDark),
      error: (_, __) => _buildInputWithPreview(isDark),
    );
  }

  // 构建禁言提示栏（TG风格 - 仿输入框样式）
  Widget _buildMutedBar(bool isDark, String text) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF38383A) : const Color(0xFFE5E5EA),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.volume_off_rounded,
                  size: 18,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    text,
                    style: TextStyle(
                      color: isDark
                          ? Colors.grey.shade500
                          : Colors.grey.shade600,
                      fontSize: 15,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 长按头像@用户
  void _mentionUser(String userId, String userName) {
    // 在输入框中插入@用户名
    final currentText = _inputController.text;
    final selection = _inputController.selection;
    final mention = '@$userName ';

    // 获取有效的光标位置（如果无效则插入到末尾）
    final cursorPos =
        (selection.baseOffset >= 0 &&
            selection.baseOffset <= currentText.length)
        ? selection.baseOffset
        : currentText.length;

    // 在光标位置插入@
    final newText =
        currentText.substring(0, cursorPos) +
        mention +
        currentText.substring(cursorPos);

    _inputController.text = newText;
    // 将光标移动到@后面
    _inputController.selection = TextSelection.collapsed(
      offset: cursorPos + mention.length,
    );

    // 记录被提及的用户 ID（用于发送消息时携带 mentions 字段）
    if (!_pendingMentionIds.contains(userId)) {
      _pendingMentionIds.add(userId);
    }

    // 聚焦输入框
    _inputFocusNode.requestFocus();
  }

  /// 发起通话
  Future<void> _startCall(CallType type) async {
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
      nav.push(MaterialPageRoute(builder: (_) => const CallPage()));
    } else if (!success && mounted) {
      final errorMessage = ref.read(callServiceProvider).errorMessage;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage ?? '发起通话失败'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _startMeeting(
    MeetingType meetingType, {
    List<String> inviteeUserIds = const [],
  }) async {
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
            response.message.isNotEmpty ? response.message : '发起会议失败',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final created = response.data!;
    final authUser = ref.read(authServiceProvider).user;
    setState(() {
      _activeMeetingInfo = MeetingActiveInfo(
        hasActive: true,
        meetingId: created.meetingId,
        chatId: widget.chatId,
        title: created.title,
        meetingType: created.meetingType,
        channelName: created.channelName,
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

  void _sendMessage(String text) {
    if (text.trim().isEmpty) return;
    final mentions = _pendingMentionIds.isNotEmpty
        ? List<String>.from(_pendingMentionIds)
        : null;
    _pendingMentionIds.clear();
    setState(() {
      _mentionQuery = null;
      _atSignIndex = -1;
    });

    ref
        .read(messageListProvider(widget.chatId).notifier)
        .sendTextMessage(
          text,
          mentions: mentions,
          burnAfterRead: _activeBurnAfterRead,
        )
        .then((error) {
          if (error != null && mounted) {
            _showMessageSendError(error);
          }
        });
    _updateChatListPreview(text, type: MessageContentType.text);
    _inputController.clear();
    _scrollToBottom();
    GlobalHaptics.light();
    _inputFocusNode.requestFocus();
  }

  void _updateChatListPreview(
    String message, {
    MessageContentType? type,
    bool? burnAfterRead,
  }) {
    ref
        .read(chatListProvider.notifier)
        .updateLastMessage(
          widget.chatId,
          message,
          type: type,
          burnAfterRead: burnAfterRead ?? _activeBurnAfterRead,
        );
  }

  void _showAttachmentOptions() {
    final isPrivateChat = widget.chatType == ChatType.private;
    final isGroupChat = widget.chatType == ChatType.group;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _AttachmentSheet(
        onPickFromGallery: _pickFromGallery,
        onTakePhoto: _takePhotoOrVideo,
        onStartMeeting: isGroupChat ? _showMeetingStartOptionsCompact : null,
        onSendLocation: _sendCurrentLocation,
        onOpenFavorites: _openFavoriteMessages,
        onPickFile: _pickFile,
        onSendRedPacket: (isPrivateChat || isGroupChat) ? _sendRedPacket : null,
        onTransfer: isPrivateChat ? _transfer : null,
      ),
    );
  }

  void _toggleBurnAfterRead() {
    if (!_isBurnAfterReadAllowed) {
      AppSnackBar.warning(context, '后台已关闭阅后即焚');
      return;
    }
    setState(() => _burnAfterReadEnabled = !_burnAfterReadEnabled);
    AppSnackBar.info(context, _burnAfterReadEnabled ? '已开启阅后即焚' : '已关闭阅后即焚');
  }

  bool _isStrictCryptoSendError(String error) {
    return error.contains('严格加密模式下') ||
        error.contains('端到端加密') ||
        error.contains('加密设备') ||
        error.contains('设备公钥') ||
        error.contains('加密版本') ||
        error.contains('数据库未升级') ||
        error.contains('设备密钥');
  }

  Future<bool> _shouldShowStrictCryptoHelp(String error) async {
    if (!_isStrictCryptoSendError(error)) {
      return false;
    }

    final currentMode = ref
        .read(systemSettingsProvider)
        .valueOrNull
        ?.messageCryptoMode;
    if (currentMode != null) {
      return currentMode.isStrict;
    }

    final latestSettings = await ref
        .read(systemSettingsServiceProvider)
        .getSettings(forceRefresh: true);
    return latestSettings.messageCryptoMode.isStrict;
  }

  Future<void> _showStrictCryptoHelp(String error) async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('严格加密发送失败'),
        content: Text(
          '$error\n\n处理方法：\n'
          '1. 先让双方都升级到最新版客户端\n'
          '2. 双方都重新登录一次\n'
          '3. 重新进入当前会话后再发送\n'
          '4. 如果只是刚在后台切到严格模式，也请稍等几秒后重试',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  void _showMessageSendError(String error) {
    final normalized = error.trim();
    if (!mounted || normalized.isEmpty) {
      return;
    }
    unawaited(_presentMessageSendError(normalized));
  }

  Future<void> _presentMessageSendError(String normalized) async {
    final shouldShowStrictHelp = await _shouldShowStrictCryptoHelp(normalized);
    if (!mounted) {
      return;
    }
    if (shouldShowStrictHelp) {
      await _showStrictCryptoHelp(normalized);
      return;
    }
    if (_isStrictCryptoSendError(normalized)) {
      AppSnackBar.warning(context, '消息加密模式正在同步，请稍后重试');
      return;
    }
    AppSnackBar.warning(context, normalized);
  }

  Future<void> _sendCurrentLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        if (!mounted) return;
        AppSnackBar.warning(context, '请先开启定位服务');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (permission == LocationPermission.deniedForever) {
          await Geolocator.openAppSettings();
        }
        if (!mounted) return;
        AppSnackBar.warning(context, '未获得定位权限，无法发送位置');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      final address =
          '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';

      final error = await ref
          .read(messageListProvider(widget.chatId).notifier)
          .sendLocationMessage(
            latitude: position.latitude,
            longitude: position.longitude,
            title: '我的位置',
            address: address,
            burnAfterRead: _activeBurnAfterRead,
          );
      if (!mounted) return;
      if (error != null) {
        _showMessageSendError(error);
        return;
      }

      _updateChatListPreview('[位置]', type: MessageContentType.location);
      _scrollToBottom();
      GlobalHaptics.light();
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.error(context, '发送位置失败: $e');
    }
  }

  VoidCallback? _buildMessageTapHandler(MessageItem message) {
    if (!message.shouldHideBurnContent) {
      return null;
    }
    return () {
      final seconds = ref
          .read(messageListProvider(widget.chatId).notifier)
          .revealBurnMessage(message.id);
      if (seconds == null || !mounted) {
        return;
      }
      AppSnackBar.info(context, '已查看阅后即焚消息，$seconds 秒后自动销毁');
    };
  }

  Future<void> _openFavoriteMessages() async {
    final accountKey = ref.read(authServiceProvider).user?.uuid.trim() ?? '';
    if (accountKey.isEmpty) {
      AppSnackBar.warning(context, '当前账号信息异常，请重新登录后再试');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FavoriteMessagesPage(accountKey: accountKey),
      ),
    );
  }

  bool _canFavoriteMessage(MessageItem message) {
    if (message.status == MessageStatus.sending ||
        message.status == MessageStatus.failed) {
      return false;
    }
    if (message.burnAfterRead) {
      return false;
    }
    return message.seq > 0;
  }

  bool _canForwardMessage(MessageItem message) {
    return !message.burnAfterRead;
  }

  void _showForwardBlockedHint() {
    AppSnackBar.warning(context, '阅后即焚消息不支持转发');
  }

  Future<void> _toggleFavoriteMessage(MessageItem message) async {
    if (!_canFavoriteMessage(message)) {
      if (message.burnAfterRead) {
        AppSnackBar.warning(context, '阅后即焚消息不支持收藏');
        return;
      }
      AppSnackBar.warning(context, '消息发送完成后才可收藏');
      return;
    }
    final accountKey = ref.read(authServiceProvider).user?.uuid.trim() ?? '';
    if (accountKey.isEmpty) {
      AppSnackBar.warning(context, '当前账号信息异常，请重新登录后再试');
      return;
    }
    final chatName =
        ref.read(chatDetailProvider(widget.chatId)).valueOrNull?.name ??
        widget.chatName;
    final added = await _favoriteMessageService.toggleFavorite(
      accountKey,
      message,
      chatName: chatName.trim().isNotEmpty ? chatName.trim() : '当前会话',
    );
    if (!mounted) return;
    AppSnackBar.success(context, added ? '收藏成功，可在收藏里查看' : '已取消收藏');
  }

  /// 发红包
  void _sendRedPacket() async {
    // 从 chatDetailProvider 获取正确的用户信息
    final chatDetail = ref.read(chatDetailProvider(widget.chatId)).value;
    final targetName = chatDetail?.name ?? widget.chatName;
    final targetAvatar = chatDetail?.avatar;

    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (context) => SendRedPacketPage(
          chatId: widget.chatId, // 传递聊天会话 UUID
          receiverName: targetName.isNotEmpty ? targetName : '用户',
          receiverAvatar: targetAvatar?.isNotEmpty == true
              ? targetAvatar
              : null,
          isGroup: widget.chatType == ChatType.group,
          groupId: widget.chatType == ChatType.group
              ? int.tryParse(widget.chatId)
              : null,
        ),
      ),
    );

    if (!mounted) return;
    if (result != null) {
      // 红包发送成功，添加红包消息到聊天
      try {
        final redPacketInfo = result as dynamic;
        final jsonData = redPacketInfo.toJson();

        // 获取当前用户信息
        final authService = ref.read(authServiceProvider);
        final currentUserName = authService.user?.nickname ?? '我';
        final currentUserAvatar = authService.user?.avatar;

        // 添加红包消息
        ref
            .read(messageListProvider(widget.chatId).notifier)
            .addRedPacketMessage(
              redPacketJson: jsonEncode(jsonData),
              senderName: currentUserName,
              senderAvatar: currentUserAvatar,
            );

        if (kDebugMode) debugPrint('[Chat] Red packet message added');
      } catch (e) {
        if (kDebugMode) debugPrint('[Chat] Error adding red packet message: $e');
      }
    }
  }

  /// 转账
  void _transfer() async {
    // 从 chatDetailProvider 获取正确的用户信息
    final chatDetail = ref.read(chatDetailProvider(widget.chatId)).value;
    final targetUserId = chatDetail?.targetUserId ?? widget.chatId;
    final targetName = chatDetail?.name ?? widget.chatName;
    final targetAvatar = chatDetail?.avatar;

    final result = await Navigator.of(context).push<dynamic>(
      MaterialPageRoute(
        builder: (context) => TransferPage(
          receiverId: targetUserId, // 传递接收者 UUID
          receiverName: targetName.isNotEmpty ? targetName : '用户',
          receiverAvatar: targetAvatar?.isNotEmpty == true
              ? targetAvatar
              : null,
        ),
      ),
    );

    if (!mounted) return;
    if (result != null) {
      // 转账成功，添加转账消息到聊天
      try {
        final transferInfo = result as dynamic;
        final jsonData = transferInfo.toJson();

        // 获取当前用户信息
        final authService = ref.read(authServiceProvider);
        final currentUserName = authService.user?.nickname ?? '我';
        final currentUserAvatar = authService.user?.avatar;

        // 添加转账消息
        ref
            .read(messageListProvider(widget.chatId).notifier)
            .addTransferMessage(
              transferJson: jsonEncode(jsonData),
              senderName: currentUserName,
              senderAvatar: currentUserAvatar,
            );

        if (kDebugMode) debugPrint('[Chat] Transfer message added');
      } catch (e) {
        if (kDebugMode) debugPrint('[Chat] Error adding transfer message: $e');
      }
    }
  }

  Future<void> _pickFromGallery() async {
    final picker = ImagePicker();

    // 使用 pickMultipleMedia 同时支持图片和视频
    final mediaList = await picker.pickMultipleMedia(
      imageQuality: 80,
      maxWidth: 1920,
      maxHeight: 1920,
    );

    if (mediaList.isEmpty) return;

    if (PlatformUtils.isWeb) {
      // Web 端：将图片加入待发送队列，让用户可以添加 caption
      final pendingToAdd = <_PendingImage>[];
      for (final media in mediaList) {
        final bytes = await media.readAsBytes();
        final ext = media.name.split('.').last.toLowerCase();
        final isVideo = [
          'mp4',
          'mov',
          'avi',
          'm4v',
          'mkv',
          'webm',
        ].contains(ext);
        if (isVideo) {
          // Web 暂不支持视频发送
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Web 端暂不支持视频发送，请使用手机客户端')),
            );
          }
          continue;
        }
        // 过滤零字节（防止空文件入队）
        if (bytes.isEmpty) continue;
        pendingToAdd.add(
          _PendingImage(bytes: bytes, ext: ext, name: media.name),
        );
      }
      if (pendingToAdd.isNotEmpty && mounted) {
        setState(() => _pendingImages.addAll(pendingToAdd));
      }
      return;
    }

    // 原生平台：直接发送
    final settings = await ref
        .read(systemSettingsServiceProvider)
        .getSettings();
    final maxImageSize = settings.maxImageSize * 1024 * 1024;
    final maxVideoSize = settings.maxVideoSize * 1024 * 1024;

    for (final media in mediaList) {
      final file = File(media.path);
      final size = await file.length();
      final ext = media.path.split('.').last.toLowerCase();

      final isVideo = ['mp4', 'mov', 'avi', 'm4v', 'mkv', 'webm'].contains(ext);

      if (isVideo) {
        if (size > maxVideoSize) {
          if (mounted) _showFileSizeExceededDialog(size, maxVideoSize, '视频');
          continue;
        }
        ref
            .read(messageListProvider(widget.chatId).notifier)
            .sendVideoMessage(media.path, burnAfterRead: _activeBurnAfterRead);
        _updateChatListPreview('[视频]', type: MessageContentType.video);
      } else {
        if (size > maxImageSize) {
          if (mounted) _showFileSizeExceededDialog(size, maxImageSize, '图片');
          continue;
        }
        final decodedImage = await decodeImageFromList(
          await file.readAsBytes(),
        );
        // 原生也加入待发队列（支持 caption）
        if (mounted) {
          setState(
            () => _pendingImages.add(
              _PendingImage(
                path: media.path,
                width: decodedImage.width,
                height: decodedImage.height,
                ext: ext,
                name: media.name,
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _takePhotoOrVideo() async {
    final picker = ImagePicker();

    // 显示选择对话框
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkDivider
                      : AppColors.lightDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _AttachmentOption(
                    icon: Icons.photo_camera,
                    label: '拍照',
                    color: const Color(0xFFFF6B6B),
                    onTap: () => Navigator.pop(context, 'photo'),
                  ),
                  _AttachmentOption(
                    icon: Icons.videocam,
                    label: '录像',
                    color: const Color(0xFF4ECDC4),
                    onTap: () => Navigator.pop(context, 'video'),
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
            ],
          ),
        );
      },
    );

    if (result == null) return;

    // 标记正在使用相机，防止 resumed 时 loadMessages 冲掉发送中的消息
    _isUsingCamera = true;

    try {
      if (result == 'photo') {
        final photo = await picker.pickImage(
          source: ImageSource.camera,
          imageQuality: 80,
          maxWidth: 1920,
          maxHeight: 1920,
        );

        if (photo != null && mounted) {
          // 先获取图片尺寸，再发送消息
          final file = File(photo.path);
          int? imgWidth;
          int? imgHeight;
          try {
            final decodedImage = await decodeImageFromList(
              await file.readAsBytes(),
            );
            imgWidth = decodedImage.width;
            imgHeight = decodedImage.height;
          } catch (e) {
            if (kDebugMode) debugPrint('[Chat] Failed to decode image dimensions: $e');
          }

          if (!mounted) return;

          ref
              .read(messageListProvider(widget.chatId).notifier)
              .sendImageMessage(
                photo.path,
                width: imgWidth,
                height: imgHeight,
                burnAfterRead: _activeBurnAfterRead,
              );
          // 更新聊天列表预览
          _updateChatListPreview('[图片]', type: MessageContentType.photo);
          _scrollToBottom();
        }
      } else if (result == 'video') {
        final video = await picker.pickVideo(
          source: ImageSource.camera,
          maxDuration: const Duration(minutes: 5),
        );

        if (video != null && mounted) {
          final file = File(video.path);
          final size = await file.length();

          // 从后台获取大小限制
          final settings = await ref
              .read(systemSettingsServiceProvider)
              .getSettings();
          final maxSize = settings.maxVideoSize * 1024 * 1024;
          if (size > maxSize) {
            if (mounted) {
              _showFileSizeExceededDialog(size, maxSize, '视频');
            }
            return;
          }

          if (!mounted) return;

          ref
              .read(messageListProvider(widget.chatId).notifier)
              .sendVideoMessage(
                video.path,
                burnAfterRead: _activeBurnAfterRead,
              );
          // 更新聊天列表预览
          _updateChatListPreview('[视频]', type: MessageContentType.video);
          // 延迟滚动，确保 state 更新后 UI 已 rebuild
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToBottom();
          });
        }
      }
    } finally {
      // 延迟重置相机标志，避免 Android 上延迟的 resumed 事件触发 loadMessages
      // 冲掉正在上传的视频/图片消息
      Future.delayed(const Duration(seconds: 3), () {
        _isUsingCamera = false;
      });
    }
  }

  /// 发送待发送队列中的图片（支持 caption）
  Future<void> _sendPendingImages({String? caption}) async {
    if (_pendingImages.isEmpty) return;
    final images = List<_PendingImage>.from(_pendingImages);
    if (!mounted) return;
    setState(() => _pendingImages.clear());
    _inputController.clear();
    _stopTyping();

    for (int i = 0; i < images.length; i++) {
      if (!mounted) break;
      final img = images[i];
      final cap = i == 0 ? caption : null; // 只有第一张附 caption
      if (img.bytes != null) {
        await ref
            .read(messageListProvider(widget.chatId).notifier)
            .sendImageFromBytes(
              img.bytes!,
              ext: img.ext.isNotEmpty ? img.ext : 'png',
              caption: cap,
              burnAfterRead: _activeBurnAfterRead,
            );
      } else if (img.path != null) {
        await ref
            .read(messageListProvider(widget.chatId).notifier)
            .sendImageMessage(
              img.path!,
              width: img.width,
              height: img.height,
              caption: cap,
              burnAfterRead: _activeBurnAfterRead,
            );
      }
    }
    if (!mounted) return;
    _updateChatListPreview(
      images.length > 1 ? '[${images.length}张图片]' : '[图片]',
      type: MessageContentType.photo,
    );
    _scrollToBottom();
    GlobalHaptics.light();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
      withData: PlatformUtils.isWeb, // Web 必须读字节
    );

    if (result == null || result.files.isEmpty) return;

    final settings = await ref
        .read(systemSettingsServiceProvider)
        .getSettings();
    final maxSize = settings.maxFileSize * 1024 * 1024;

    for (final file in result.files) {
      if (file.size > maxSize) {
        if (mounted) _showFileSizeExceededDialog(file.size, maxSize, '文件');
        continue;
      }

      if (PlatformUtils.isWeb) {
        // Web：使用字节上传
        final bytes = file.bytes;
        if (bytes == null) continue;
        ref
            .read(messageListProvider(widget.chatId).notifier)
            .sendFileFromBytes(
              bytes,
              file.name,
              burnAfterRead: _activeBurnAfterRead,
            );
      } else {
        if (file.path == null) continue;
        ref
            .read(messageListProvider(widget.chatId).notifier)
            .sendFileMessage(
              file.path!,
              file.name,
              burnAfterRead: _activeBurnAfterRead,
            );
      }

      _updateChatListPreview('[文件]', type: MessageContentType.file);
    }
    _scrollToBottom();
  }

  void _showFileSizeExceededDialog(
    int actualSize,
    int maxSize,
    String fileType,
  ) {
    final actualMB = (actualSize / 1024 / 1024).toStringAsFixed(1);
    final maxMB = (maxSize / 1024 / 1024).toStringAsFixed(0);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.orange,
                  size: 36,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '$fileType过大',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '当前$fileType大小 ${actualMB}MB，超出限制 ${maxMB}MB',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '请选择较小的$fileType或进行压缩后重试',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text('我知道了', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _startVoiceRecord() async {
    if (kDebugMode) debugPrint('[ChatDetail] _startVoiceRecord called');
    GlobalHaptics.medium();

    final voiceService = ref.read(voiceRecordProvider.notifier);
    if (kDebugMode) debugPrint('[ChatDetail] Starting recording...');
    final started = await voiceService.startRecording();
    if (kDebugMode) debugPrint('[ChatDetail] Recording started: $started');

    if (started) {
      setState(() => _isRecordingVoice = true);
      if (kDebugMode) debugPrint('[ChatDetail] _isRecordingVoice set to true');
    } else {
      final state = ref.read(voiceRecordProvider);
      if (kDebugMode) debugPrint('[ChatDetail] Recording failed, error: ${state.error}');
      if (state.error != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.error!)));
      }
    }
  }

  void _stopVoiceRecord() async {
    final voiceService = ref.read(voiceRecordProvider.notifier);
    final voiceData = await voiceService.stopRecording();

    setState(() => _isRecordingVoice = false);

    if (voiceData != null) {
      // 发送语音消息
      ref
          .read(messageListProvider(widget.chatId).notifier)
          .sendVoiceMessage(
            voiceData.path,
            voiceData.duration,
            burnAfterRead: _activeBurnAfterRead,
          );
      // 更新聊天列表预览
      _updateChatListPreview('[语音]', type: MessageContentType.voice);
      _scrollToBottom();
      GlobalHaptics.light();
    }
  }

  void _cancelVoiceRecord() async {
    GlobalHaptics.medium();
    final voiceService = ref.read(voiceRecordProvider.notifier);
    await voiceService.cancelRecording();
    setState(() => _isRecordingVoice = false);
  }

  void _toggleEmojiPicker() {
    setState(() {
      _showEmojiPickerState = !_showEmojiPickerState;
    });
  }

  void _showMessageOptions(MessageItem message, Offset tapPosition) {
    // 判断是否是媒体/文件类型消息（用于桌面端显示文件操作）
    final isMediaMessage =
        message.type == MessageItemType.image ||
        message.type == MessageItemType.video ||
        message.type == MessageItemType.file ||
        message.type == MessageItemType.voice;
    final isDesktop =
        PlatformUtils.isPhysicalDesktop;

    // 从后端配置获取撤回时间限制
    final revokeMinutes =
        ref.read(systemSettingsProvider).valueOrNull?.revokeMessageMinutes ?? 2;
    final chatDetail = ref.read(chatDetailProvider(widget.chatId)).valueOrNull;
    if (kDebugMode) debugPrint(
      '[Chat] revokeMinutes from server: $revokeMinutes, message age: ${DateTime.now().difference(message.createdAt).inMinutes} min',
    );
    final canSelfRevoke =
        message.isOutgoing &&
        DateTime.now().difference(message.createdAt).inMinutes < revokeMinutes;
    final canAdminRevoke =
        widget.chatType == ChatType.group &&
        (chatDetail?.myRole ?? 0) >= 2 &&
        !message.isDeleted &&
        message.type != MessageItemType.system;
    final canRevoke = canSelfRevoke || canAdminRevoke;

    showMessageContextMenu(
      context: context,
      message: message,
      isOutgoing: message.isOutgoing,
      tapPosition: tapPosition,
      showSenderName:
          widget.chatType != ChatType.private && !message.isOutgoing,
      onReaction: (emoji) => _handleReaction(message, emoji),
      onReply: () => _handleReply(message),
      onCopy: () => _handleCopy(message),
      onForward: _canForwardMessage(message)
          ? () => _handleForward(message)
          : null,
      onFavorite: _canFavoriteMessage(message)
          ? () => _toggleFavoriteMessage(message)
          : null,
      onEdit: message.isOutgoing ? () => _handleEdit(message) : null,
      onDelete: () => _handleDelete(message),
      onRevoke: canRevoke ? () => _revokeMessage(message) : null,
      onPin:
          (widget.chatType != ChatType.private &&
              ((chatDetail?.myRole ?? 0) >= 2 ||
                  (chatDetail?.canPinMessages ?? false)))
          ? () => _handlePinMessage(message)
          : null,
      onSelect: () => _enterSelectionMode(message),
      // Web 端文件下载
      onDownload: kIsWeb && isMediaMessage
          ? () => _handleWebDownload(message)
          : null,
      // 桌面端文件操作
      onSaveAs: isDesktop && isMediaMessage
          ? () => _handleSaveAs(message)
          : null,
      onShowInFolder: isDesktop && isMediaMessage
          ? () => _handleShowInFolder(message)
          : null,
      onOpenFile: isDesktop && message.type == MessageItemType.file
          ? () => _handleOpenFile(message)
          : null,
    );
  }

  /// 处理置顶消息
  Future<void> _handlePinMessage(MessageItem message) async {
    try {
      final chatService = ref.read(api.chatServiceProvider);
      final response = await chatService.pinMessage(widget.chatId, message.id);
      if (!mounted) return;

      if (response.isSuccess) {
        String pinnedMessageId = message.id;
        String pinnedMessageText = _buildPinnedMessagePreview(message);
        final data = response.data;
        if (kDebugMode) debugPrint(
          '[Pin] pinMessage response data type: ${data.runtimeType}, value: $data',
        );
        if (data is Map) {
          final pinnedData = Map<String, dynamic>.from(data);
          pinnedMessageId = _readPinnedMessageId(pinnedData) ?? pinnedMessageId;
          pinnedMessageText =
              _readPinnedMessageText(pinnedData) ?? pinnedMessageText;
        }

        if (kDebugMode) debugPrint(
          '[Pin] Setting pinned: id=$pinnedMessageId, text=$pinnedMessageText',
        );
        _setPinnedMessage(
          messageId: pinnedMessageId,
          messageText: pinnedMessageText,
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('消息已置顶')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              response.message.isNotEmpty ? response.message : '置顶失败',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('置顶失败: $e')));
      }
    }
  }

  /// 处理表情回复
  void _handleReaction(MessageItem message, String emoji) async {
    GlobalHaptics.light();

    // 获取当前用户名
    final authState = ref.read(authServiceProvider);
    final userName = authState.user?.nickname ?? '';

    // 检查是否已经回复过这个表情
    final existingReaction = message.reactions
        .where(
          (r) => r.userId == (authState.user?.uuid ?? '') && r.emoji == emoji,
        )
        .isNotEmpty;

    bool success;
    if (existingReaction) {
      // 已回复，则移除
      success = await ref
          .read(messageListProvider(widget.chatId).notifier)
          .removeReaction(message.id, emoji);
    } else {
      // 未回复，则添加
      success = await ref
          .read(messageListProvider(widget.chatId).notifier)
          .addReaction(message.id, emoji, userName);
    }

    if (mounted && !success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('操作失败'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  /// 处理回复消息
  void _handleReply(MessageItem message) {
    GlobalHaptics.selection();
    setState(() {
      _replyToMessage = message;
      _editingMessage = null;
    });
    _inputFocusNode.requestFocus();
  }

  /// 取消回复
  void _cancelReply() {
    setState(() => _replyToMessage = null);
  }

  /// Web 端：通过浏览器下载文件（file_saver LinkDetails 触发浏览器下载管理器）
  Future<void> _handleWebDownload(MessageItem message) async {
    try {
      final mediaUrl = message.mediaUrl;
      if (mediaUrl == null || mediaUrl.isEmpty) {
        _showSnackBar('文件不存在');
        return;
      }
      final fullUrl = _getFullMediaUrl(mediaUrl);
      if (fullUrl.isEmpty) {
        _showSnackBar('无法解析文件地址');
        return;
      }

      // 推断文件名与扩展名
      final rawName = message.fileName ??
          Uri.parse(fullUrl).pathSegments.lastOrNull ??
          'file';
      final dotIdx = rawName.lastIndexOf('.');
      final name = dotIdx > 0 ? rawName.substring(0, dotIdx) : rawName;
      final ext  = dotIdx > 0 ? rawName.substring(dotIdx + 1) : '';

      // 推断 MimeType
      MimeType mimeType;
      switch (message.type) {
        case MessageItemType.image:
          mimeType = MimeType.png;
          break;
        case MessageItemType.video:
          mimeType = MimeType.mp4Video;
          break;
        case MessageItemType.voice:
          mimeType = MimeType.aac;
          break;
        default:
          mimeType = MimeType.other;
      }

      _showSnackBar('正在下载...');
      await FileSaver.instance.saveFile(
        name: name,
        fileExtension: ext,
        mimeType: mimeType,
        link: LinkDetails(link: fullUrl),
      );
      _showSnackBar('下载已开始');
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatDetail] Web download error: \$e');
      _showSnackBar('下载失败: \$e');
    }
  }

  Future<void> _handleSaveAs(MessageItem message) async {
    try {
      final mediaUrl = message.mediaUrl;
      if (mediaUrl == null || mediaUrl.isEmpty) {
        _showSnackBar('无法保存：文件不存在');
        return;
      }

      // 推断默认文件名
      String defaultFileName;
      switch (message.type) {
        case MessageItemType.image:
          defaultFileName = 'image_\${DateTime.now().millisecondsSinceEpoch}.jpg';
          break;
        case MessageItemType.video:
          defaultFileName = 'video_\${DateTime.now().millisecondsSinceEpoch}.mp4';
          break;
        case MessageItemType.voice:
          defaultFileName = 'voice_\${DateTime.now().millisecondsSinceEpoch}.m4a';
          break;
        case MessageItemType.file:
          defaultFileName = message.fileName ??
              'file_\${DateTime.now().millisecondsSinceEpoch}';
          break;
        default:
          defaultFileName = 'file_\${DateTime.now().millisecondsSinceEpoch}';
      }

      final fullUrl = _getFullMediaUrl(mediaUrl);
      final dotIdx = defaultFileName.lastIndexOf('.');
      final name = dotIdx > 0 ? defaultFileName.substring(0, dotIdx) : defaultFileName;
      final ext  = dotIdx > 0 ? defaultFileName.substring(dotIdx + 1) : '';

      if (kIsWeb) {
        // ── Web：交给浏览器下载管理器 ──
        MimeType mimeType;
        switch (message.type) {
          case MessageItemType.image: mimeType = MimeType.png;   break;
          case MessageItemType.video: mimeType = MimeType.mp4Video;   break;
          case MessageItemType.voice: mimeType = MimeType.aac;   break;
          default:                    mimeType = MimeType.other; break;
        }
        _showSnackBar('正在下载...');
        await FileSaver.instance.saveFile(
          name: name,
          fileExtension: ext,
          mimeType: mimeType,
          link: LinkDetails(link: fullUrl),
        );
        _showSnackBar('下载已开始');
      } else {
        // ── 桌面端：FilePicker 选择保存位置 + Dio 下载 ──
        final result = await FilePicker.platform.saveFile(
          dialogTitle: '保存文件',
          fileName: defaultFileName,
        );
        if (result == null) return;

        final dio = Dio();
        await dio.download(fullUrl, result);
        _showSnackBar('文件已保存');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatDetail] Save as error: $e');
      _showSnackBar('保存失败: $e');
    }
  }
  /// 桌面端：在 Finder/资源管理器中显示（Web 不支持）
  Future<void> _handleShowInFolder(MessageItem message) async {
    // Web 端不支持文件系统操作，降级为浏览器打开
    if (kIsWeb) {
      await _handleWebDownload(message);
      return;
    }
    try {
      final mediaUrl = message.mediaUrl;
      if (mediaUrl == null || mediaUrl.isEmpty) {
        _showSnackBar('文件不存在');
        return;
      }

      // 检查本地缓存路径
      final cacheDir = await _getMediaCacheDir();
      final fileName = Uri.parse(mediaUrl).pathSegments.lastOrNull ?? 'file';
      final localFile = File('$cacheDir/$fileName');

      if (await localFile.exists()) {
        // 文件存在，打开所在文件夹
        if (Platform.isMacOS) {
          await Process.run('open', ['-R', localFile.path]);
        } else if (Platform.isWindows) {
          await Process.run('explorer', ['/select,', localFile.path]);
        } else if (Platform.isLinux) {
          await Process.run('xdg-open', [localFile.parent.path]);
        }
      } else {
        // 文件不在缓存中，先下载
        _showSnackBar('正在下载文件...');

        final fullUrl = _getFullMediaUrl(mediaUrl);
        final dio = Dio();
        await dio.download(fullUrl, localFile.path);

        // 下载完成后打开文件夹
        if (Platform.isMacOS) {
          await Process.run('open', ['-R', localFile.path]);
        } else if (Platform.isWindows) {
          await Process.run('explorer', ['/select,', localFile.path]);
        } else if (Platform.isLinux) {
          await Process.run('xdg-open', [localFile.parent.path]);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatDetail] Show in folder error: $e');
      _showSnackBar('操作失败: $e');
    }
  }

  /// 桌面端：使用默认应用打开文件（Web 不支持本地进程）
  Future<void> _handleOpenFile(MessageItem message) async {
    // Web 端无法调用本地应用，降级为浏览器下载
    if (kIsWeb) {
      await _handleWebDownload(message);
      return;
    }
    try {
      final mediaUrl = message.mediaUrl;
      if (mediaUrl == null || mediaUrl.isEmpty) {
        _showSnackBar('文件不存在');
        return;
      }

      // 检查本地缓存路径
      final cacheDir = await _getMediaCacheDir();
      final fileName =
          message.fileName ??
          Uri.parse(mediaUrl).pathSegments.lastOrNull ??
          'file';
      final localFile = File('$cacheDir/$fileName');

      if (!await localFile.exists()) {
        // 文件不在缓存中，先下载
        _showSnackBar('正在下载文件...');

        final fullUrl = _getFullMediaUrl(mediaUrl);
        final dio = Dio();
        await dio.download(fullUrl, localFile.path);
      }

      // 使用默认应用打开
      if (Platform.isMacOS) {
        await Process.run('open', [localFile.path]);
      } else if (Platform.isWindows) {
        await Process.run('start', ['', localFile.path], runInShell: true);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [localFile.path]);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatDetail] Open file error: $e');
      _showSnackBar('打开失败: $e');
    }
  }

  /// 获取媒体缓存目录（仅原生平台可用）
  Future<String> _getMediaCacheDir() async {
    if (kIsWeb) return ''; // Web 不支持本地目录
    final appDir = await getApplicationSupportDirectory();
    final cacheDir = Directory('${appDir.path}/media_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir.path;
  }

  /// 获取完整的媒体URL
  String _getFullMediaUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    // 使用 ApiConfig 获取完整URL
    return ApiConfig.getMediaUrl(url);
  }

  /// 显示SnackBar
  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 处理复制消息
  void _handleCopy(MessageItem message) {
    String textToCopy = message.content;

    // 根据消息类型获取可复制的内容
    if (message.type == MessageItemType.text) {
      textToCopy = message.content;
    } else if (message.type == MessageItemType.file) {
      textToCopy = message.fileName ?? message.content;
    }

    Clipboard.setData(ClipboardData(text: textToCopy));
    GlobalHaptics.light();
  }

  /// 处理转发消息
  void _handleForward(MessageItem message) {
    if (!_canForwardMessage(message)) {
      _showForwardBlockedHint();
      return;
    }
    GlobalHaptics.selection();
    _showForwardDialog(message);
  }

  /// 显示转发对话框
  void _showForwardDialog(MessageItem message) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 拖动指示器
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // 标题
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '转发到...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              // 聊天列表
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final chatState = ref.watch(chatListProvider);
                    final chats = [
                      ...chatState.pinnedChats,
                      ...chatState.regularChats,
                    ];
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: chats.length,
                      itemBuilder: (context, index) {
                        final chat = chats[index];
                        if (chat.id == widget.chatId)
                          return const SizedBox.shrink();

                        return ListTile(
                          leading: AvatarWidget(
                            avatar: chat.avatar,
                            name: chat.name,
                            size: 48,
                          ),
                          title: Text(
                            chat.name,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          onTap: () async {
                            // 群组/频道：检查是否全员禁言
                            if (chat.type == ChatItemType.group ||
                                chat.type == ChatItemType.channel) {
                              final chatDetail = await ref.read(
                                chatDetailProvider(chat.id).future,
                              );
                              if (chatDetail != null) {
                                // 频道：仅管理员/群主可发言
                                if (chat.type == ChatItemType.channel &&
                                    chatDetail.myRole < 2) {
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    _showTopToast('仅管理员可发布内容，无法转发');
                                  }
                                  return;
                                }
                                // 群组：全员禁言且非管理员
                                if (chat.type == ChatItemType.group &&
                                    !chatDetail.canSendMessage &&
                                    chatDetail.myRole < 2) {
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    _showTopToast('该群组已禁言，无法转发');
                                  }
                                  return;
                                }
                              }
                            }
                            if (context.mounted) {
                              Navigator.pop(context);
                              _forwardMessageTo(message, chat.id, chat.name);
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 转发消息到指定聊天
  void _forwardMessageTo(
    MessageItem message,
    String targetChatId,
    String chatTitle,
  ) async {
    if (!_canForwardMessage(message)) {
      _showForwardBlockedHint();
      return;
    }
    GlobalHaptics.medium();

    final success = await ref
        .read(messageListProvider(widget.chatId).notifier)
        .forwardMessage(message.id, targetChatId);

    if (!mounted) return;

    if (success) {
      // Telegram 风格的转发成功提示 - 顶部浮动通知
      _showTopToast('已转发到 $chatTitle');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('转发失败'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  /// 显示顶部浮动提示 (Telegram 风格)
  void _showTopToast(String message) {
    if (!mounted) return;
    final overlay = Overlay.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _TopToastWidget(
        message: message,
        isDark: isDark,
        onDismiss: () {
          entry.remove();
          _activeOverlays.remove(entry);
        },
      ),
    );

    _activeOverlays.add(entry);
    overlay.insert(entry);
  }

  /// 处理编辑消息
  void _handleEdit(MessageItem message) {
    // 只能编辑文本消息
    if (message.type != MessageItemType.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('只能编辑文本消息'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    // 检查是否在可编辑时间内（48小时）
    final diff = DateTime.now().difference(message.createdAt);
    if (diff.inHours > 48) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('超过48小时的消息无法编辑'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    GlobalHaptics.selection();
    setState(() {
      _editingMessage = message;
      _originalEditContent = message.content;
      _replyToMessage = null;
      _inputController.text = message.content;
    });
    _inputFocusNode.requestFocus();
  }

  /// 取消编辑
  void _cancelEdit() {
    setState(() {
      _editingMessage = null;
      _originalEditContent = null;
      _inputController.clear();
    });
  }

  /// 处理删除消息 - 直接删除并播放破碎动画
  void _handleDelete(MessageItem message) {
    // 播放破碎动画并删除
    _playDeleteAnimation(message);
  }

  /// 播放删除破碎动画
  void _playDeleteAnimation(MessageItem message) {
    GlobalHaptics.medium();

    // 获取屏幕尺寸
    final screenSize = MediaQuery.of(context).size;
    final center = Offset(screenSize.width / 2, screenSize.height / 2);

    // 创建破碎粒子覆盖层
    late OverlayEntry overlayEntry;
    overlayEntry = OverlayEntry(
      builder: (context) => _MessageDeleteAnimation(
        screenCenter: center,
        onComplete: () {
          overlayEntry.remove();
          _activeOverlays.remove(overlayEntry);
        },
      ),
    );

    _activeOverlays.add(overlayEntry);
    Overlay.of(context).insert(overlayEntry);

    // 删除消息
    _deleteMessageLocally(message);
  }

  /// 本地删除消息（持久化删除）
  Future<void> _deleteMessageLocally(MessageItem message) async {
    GlobalHaptics.medium();
    await ref
        .read(messageListProvider(widget.chatId).notifier)
        .deleteMessage(message.id);
  }

  /// 进入多选模式
  void _enterSelectionMode(MessageItem message) {
    GlobalHaptics.selection();
    setState(() {
      _isSelectionMode = true;
      _selectedMessageIds.add(message.id);
    });
  }

  /// 退出多选模式
  void _exitSelectionMode() {
    GlobalHaptics.selection();
    setState(() {
      _isSelectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  /// 切换消息选中状态
  void _toggleMessageSelection(String messageId) {
    GlobalHaptics.selection();
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
        if (_selectedMessageIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  /// 删除选中的消息
  void _deleteSelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final count = _selectedMessageIds.length;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, anim1, anim2) => const SizedBox(),
      transitionBuilder: (context, anim1, anim2, child) {
        return Stack(
          children: [
            // 毛玻璃背景
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 8 * anim1.value,
                    sigmaY: 8 * anim1.value,
                  ),
                  child: Container(
                    color: Colors.black.withOpacity(0.3 * anim1.value),
                  ),
                ),
              ),
            ),
            // 弹窗内容
            Center(
              child: Transform.scale(
                scale: Curves.easeOutBack.transform(anim1.value),
                child: Opacity(
                  opacity: anim1.value,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withOpacity(0.12)
                                : Colors.white.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.15)
                                  : Colors.white.withOpacity(0.5),
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 图标
                              Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.delete_sweep_rounded,
                                  color: AppColors.error,
                                  size: 28,
                                ),
                              ),

                              const SizedBox(height: 16),

                              // 标题
                              Text(
                                '删除 $count 条消息',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),

                              const SizedBox(height: 8),

                              // 描述
                              Text(
                                '这些消息将从您的聊天记录中删除，且无法恢复',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black54,
                                  height: 1.4,
                                ),
                              ),

                              const SizedBox(height: 24),

                              // 按钮
                              Row(
                                children: [
                                  // 取消按钮
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        backgroundColor: isDark
                                            ? Colors.white.withOpacity(0.1)
                                            : Colors.black.withOpacity(0.05),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        '取消',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.white70
                                              : Colors.black54,
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(width: 12),

                                  // 删除按钮
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () async {
                                        Navigator.pop(context);
                                        GlobalHaptics.medium();
                                        final idsToDelete = _selectedMessageIds
                                            .toList();
                                        _exitSelectionMode();
                                        // 逐个删除，确保持久化
                                        for (final id in idsToDelete) {
                                          if (!mounted) break;
                                          await ref
                                              .read(
                                                messageListProvider(
                                                  widget.chatId,
                                                ).notifier,
                                              )
                                              .deleteMessage(id);
                                        }
                                      },
                                      style: TextButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 14,
                                        ),
                                        backgroundColor: AppColors.error,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                      child: const Text(
                                        '删除',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
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
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 转发选中的消息
  void _forwardSelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;

    // 获取选中的消息
    final messages = ref.read(messageListProvider(widget.chatId));
    final selectedMessages = messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();

    if (selectedMessages.isEmpty) return;
    if (selectedMessages.any((message) => message.burnAfterRead)) {
      _showForwardBlockedHint();
      return;
    }

    _showForwardDialogForMultiple(selectedMessages);
  }

  /// 显示转发对话框（多选）
  void _showForwardDialogForMultiple(List<MessageItem> messages) {
    if (messages.any((message) => message.burnAfterRead)) {
      _showForwardBlockedHint();
      return;
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 拖动指示器
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 标题
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  '转发 ${messages.length} 条消息到...',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),

              // 聊天列表
              Expanded(
                child: Consumer(
                  builder: (context, ref, _) {
                    final chatState = ref.watch(chatListProvider);
                    final chats = [
                      ...chatState.pinnedChats,
                      ...chatState.regularChats,
                    ];
                    return ListView.builder(
                      controller: scrollController,
                      itemCount: chats.length,
                      itemBuilder: (context, index) {
                        final chat = chats[index];
                        if (chat.id == widget.chatId)
                          return const SizedBox.shrink();

                        return ListTile(
                          leading: AvatarWidget(
                            avatar: chat.avatar,
                            name: chat.name,
                            size: 48,
                          ),
                          title: Text(
                            chat.name,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          onTap: () async {
                            // 群组/频道：检查是否全员禁言
                            if (chat.type == ChatItemType.group ||
                                chat.type == ChatItemType.channel) {
                              final chatDetail = await ref.read(
                                chatDetailProvider(chat.id).future,
                              );
                              if (chatDetail != null) {
                                // 频道：仅管理员/群主可发言
                                if (chat.type == ChatItemType.channel &&
                                    chatDetail.myRole < 2) {
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    _showTopToast('仅管理员可发布内容，无法转发');
                                  }
                                  return;
                                }
                                // 群组：全员禁言且非管理员
                                if (chat.type == ChatItemType.group &&
                                    !chatDetail.canSendMessage &&
                                    chatDetail.myRole < 2) {
                                  if (context.mounted) {
                                    Navigator.pop(context);
                                    _showTopToast('该群组已禁言，无法转发');
                                  }
                                  return;
                                }
                              }
                            }
                            if (context.mounted) {
                              Navigator.pop(context);
                            }

                            // 转发所有选中的消息
                            int successCount = 0;
                            for (final msg in messages) {
                              if (!mounted) break;
                              final success = await ref
                                  .read(
                                    messageListProvider(widget.chatId).notifier,
                                  )
                                  .forwardMessage(msg.id, chat.id);
                              if (success) successCount++;
                            }

                            if (mounted) {
                              _showTopToast(
                                '已转发 $successCount 条消息到 ${chat.name}',
                              );
                              _exitSelectionMode();
                            }
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 撤回消息
  Future<void> _revokeMessage(MessageItem message) async {
    GlobalHaptics.medium();

    final success = await ref
        .read(messageListProvider(widget.chatId).notifier)
        .revokeMessage(message.id);

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('撤回失败'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void _reactToMessage(MessageItem message) => GlobalHaptics.light();

  /// 构建可选择的消息项
  Widget _buildSelectableMessage(
    MessageItem message,
    bool isFirstInGroup,
    bool isLastInGroup,
    BubbleColors bubbleColors,
    bool isDark,
  ) {
    final isSelected = _selectedMessageIds.contains(message.id);

    return GestureDetector(
      onTap: () => _toggleMessageSelection(message.id),
      child: Container(
        color: isSelected
            ? AppColors.primary.withOpacity(isDark ? 0.15 : 0.1)
            : Colors.transparent,
        child: Row(
          children: [
            // 左侧选择框
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? Colors.white38 : Colors.black26),
                    width: 2,
                  ),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),

            // 消息气泡
            Expanded(
              child: IgnorePointer(
                child: MessageBubble(
                  message: message,
                  isFirstInGroup: isFirstInGroup,
                  isLastInGroup: isLastInGroup,
                  showSenderName:
                      widget.chatType != ChatType.private &&
                      !message.isOutgoing,
                  customOutgoingColor: bubbleColors.outgoing,
                  customIncomingColor: bubbleColors.incoming,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 组件 ====================

class _ScrollToBottomButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ScrollToBottomButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(Icons.keyboard_arrow_down, color: AppColors.primary),
      ),
    ).animate().scale(duration: 200.ms);
  }
}

class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool isDestructive;

  const _OptionTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.error : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      onTap: onTap,
    );
  }
}

// ==================== 用户信息 ====================

class _UserInfoSheet extends StatelessWidget {
  final String name;
  final String? avatar;
  final String userId;

  const _UserInfoSheet({required this.name, this.avatar, required this.userId});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: ListView(
          controller: scrollController,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkDivider
                      : AppColors.lightDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: AvatarWidget(
                name: name,
                avatar: avatar,
                userId: userId,
                size: 80,
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Center(
              child: Text(
                '在线',
                style: TextStyle(fontSize: 14, color: AppColors.online),
              ),
            ),
            const SizedBox(height: 24),
            _InfoRow(icon: Icons.phone, title: '+86 138****8888'),
            _InfoRow(icon: Icons.alternate_email, title: '@$userId'),
            _InfoRow(icon: Icons.info_outline, title: '这个人很懒，什么都没写'),
            const Divider(height: 32),
            _ActionRow(
              icon: Icons.notifications_outlined,
              title: '通知',
              trailing: '开启',
            ),
            _ActionRow(icon: Icons.block_outlined, title: '屏蔽用户'),
          ],
        ),
      ),
    );
  }
}

// ==================== 群组信息 ====================

class _GroupInfoSheet extends ConsumerWidget {
  final String name;
  final String? avatar;
  final String groupId;

  const _GroupInfoSheet({
    required this.name,
    this.avatar,
    required this.groupId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatDetailAsync = ref.watch(chatDetailProvider(groupId));

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: ListView(
          controller: scrollController,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkDivider
                      : AppColors.lightDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PremiumCard(
                isDark: isDark,
                premiumType: chatDetailAsync.valueOrNull?.premiumType,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
                borderRadius: BorderRadius.circular(24),
                colors: isDark
                    ? const [Color(0xFF1B2333), Color(0xFF111827)]
                    : const [Color(0xFFF8FAFF), Color(0xFFEEF4FF)],
                child: chatDetailAsync.when(
                  data: (chat) {
                    final memberCount = chat?.memberCount ?? 0;
                    final onlineCount = chat?.onlineCount ?? 0;
                    final username = chat?.username;
                    final description = chat?.description;
                    return Column(
                      children: [
                        AvatarWidget(
                          name: name,
                          avatar: avatar,
                          userId: groupId,
                          size: 84,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          name,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _buildInfoChip(
                              icon: Icons.group_outlined,
                              label: '$memberCount 位成员',
                              isDark: isDark,
                            ),
                            if (onlineCount > 0)
                              _buildInfoChip(
                                icon: Icons.wifi_tethering,
                                label: '$onlineCount 位在线',
                                isDark: isDark,
                                accentColor: AppColors.success,
                              ),
                            if (username != null && username.isNotEmpty)
                              _buildInfoChip(
                                icon: Icons.alternate_email,
                                label: '@$username',
                                isDark: isDark,
                              ),
                          ],
                        ),
                        if (description != null && description.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.04)
                                  : Colors.white.withOpacity(0.72),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '简介',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  description,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.45,
                                    color: isDark
                                        ? Colors.white.withOpacity(0.88)
                                        : const Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                  loading: () => Column(
                    children: [
                      AvatarWidget(
                        name: name,
                        avatar: avatar,
                        userId: groupId,
                        size: 84,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildInfoChip(
                        icon: Icons.hourglass_empty,
                        label: '加载中...',
                        isDark: isDark,
                      ),
                    ],
                  ),
                  error: (_, __) => Column(
                    children: [
                      AvatarWidget(
                        name: name,
                        avatar: avatar,
                        userId: groupId,
                        size: 84,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        name,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      title: '成员',
                      value: '${chatDetailAsync.value?.memberCount ?? 0}',
                      subtitle: '群组规模',
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      title: '在线',
                      value: '${chatDetailAsync.value?.onlineCount ?? 0}',
                      subtitle: '实时活跃',
                      isDark: isDark,
                      accentColor: AppColors.success,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _ActionRow(icon: Icons.person_add_outlined, title: '添加成员'),

            // 显示群组号
            chatDetailAsync.when(
              data: (chat) {
                if (chat != null &&
                    chat.username != null &&
                    chat.username!.isNotEmpty) {
                  return _ActionRow(
                    icon: Icons.alternate_email,
                    title: '群组号',
                    trailing: '@${chat.username}',
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: '@${chat.username}'),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('群组号已复制'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  );
                }
                return const SizedBox.shrink();
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            _ActionRow(
              icon: Icons.notifications_outlined,
              title: '通知',
              trailing: '开启',
            ),
            const Divider(height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '成员',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),

            // 显示真实成员列表
            ref
                .watch(chatMembersProvider(groupId))
                .when(
                  data: (members) {
                    final myRole = chatDetailAsync.value?.myRole ?? 0;
                    final canOpenMemberProfile =
                        !(chatDetailAsync.value?.memberProtection ?? false) ||
                        myRole >= 2;
                    return Column(
                      children: members
                          .map(
                            (member) => ListTile(
                              leading: Stack(
                                children: [
                                  AvatarWidget(
                                    name: member.displayName,
                                    avatar: member.avatar,
                                    userId: member.userId,
                                    size: 40,
                                    premiumType: member.premiumType,
                                  ),
                                  if (member.isOnline)
                                    Positioned(
                                      right: 0,
                                      bottom: 0,
                                      child: Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: AppColors.success,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: isDark
                                                ? AppColors.darkBackground
                                                : AppColors.lightBackground,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: ColoredNameWidget(
                                      name: member.displayName,
                                      nicknameColor: member.nicknameColor,
                                      premiumType: member.premiumType,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      defaultColor: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (member.isMuted)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        member.muteStatusText.isNotEmpty
                                            ? member.muteStatusText
                                            : '禁言中',
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.red,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              subtitle: Text(
                                member.roleName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: member.role >= 2
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: member.role >= 2
                                      ? AppColors.primary
                                      : (isDark
                                            ? Colors.white54
                                            : Colors.black45),
                                ),
                              ),
                              // 管理员和群主可以对成员进行操作
                              trailing: myRole >= 1 && member.role < myRole
                                  ? IconButton(
                                      icon: Icon(
                                        member.isMuted
                                            ? Icons.volume_up
                                            : Icons.volume_off,
                                        color: member.isMuted
                                            ? AppColors.success
                                            : Colors.grey,
                                        size: 20,
                                      ),
                                      onPressed: () => _showMuteOptions(
                                        context,
                                        ref,
                                        groupId,
                                        member,
                                        myRole,
                                      ),
                                    )
                                  : null,
                              onLongPress: myRole >= 1 && member.role < myRole
                                  ? () => _showMuteOptions(
                                      context,
                                      ref,
                                      groupId,
                                      member,
                                      myRole,
                                    )
                                  : null,
                              onTap: canOpenMemberProfile
                                  ? () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) => UserProfilePage(
                                            userId: member.userId,
                                            name: member.displayName,
                                            avatar: member.avatar,
                                            chatId: groupId,
                                          ),
                                        ),
                                      );
                                    }
                                  : null,
                            ),
                          )
                          .toList(),
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (_, __) => const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: Text('加载失败')),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String label,
    required bool isDark,
    Color? accentColor,
  }) {
    final chipColor = accentColor ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? chipColor.withOpacity(0.14)
            : chipColor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: chipColor.withOpacity(isDark ? 0.26 : 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: chipColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : const Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required bool isDark,
    Color? accentColor,
  }) {
    final tone = accentColor ?? AppColors.primary;
    return PremiumCard(
      isDark: isDark,
      accentColor: tone,
      padding: const EdgeInsets.all(14),
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: tone,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white54 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }

  // 禁言操作菜单
  void _showMuteOptions(
    BuildContext context,
    WidgetRef ref,
    String chatId,
    api.ChatMember member,
    int myRole,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageContext = context;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkDivider
                      : AppColors.lightDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  member.displayName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
              if (member.isMuted) ...[
                // 已禁言，显示解禁选项
                ListTile(
                  leading: const Icon(
                    Icons.volume_up,
                    color: AppColors.success,
                  ),
                  title: const Text('解除禁言'),
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      final chatService = ref.read(api.chatServiceProvider);
                      final result = await chatService.unmuteMember(
                        chatId,
                        member.userId,
                      );
                      if (result.isSuccess) {
                        ref.invalidate(chatMembersProvider(chatId));
                        if (pageContext.mounted) {
                          ScaffoldMessenger.of(pageContext).showSnackBar(
                            const SnackBar(content: Text('已解除禁言')),
                          );
                        }
                      } else if (pageContext.mounted) {
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          SnackBar(
                            content: Text(result.message ?? '操作失败'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    } catch (e) {
                      if (pageContext.mounted) {
                        ScaffoldMessenger.of(pageContext).showSnackBar(
                          SnackBar(
                            content: Text('操作失败: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
              ] else ...[
                // 未禁言，显示禁言选项
                ListTile(
                  leading: const Icon(Icons.volume_off, color: Colors.orange),
                  title: const Text('禁言 10 分钟'),
                  onTap: () => _muteMember(
                    pageContext,
                    context,
                    ref,
                    chatId,
                    member.userId,
                    10,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.volume_off, color: Colors.orange),
                  title: const Text('禁言 1 小时'),
                  onTap: () => _muteMember(
                    pageContext,
                    context,
                    ref,
                    chatId,
                    member.userId,
                    60,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.volume_off, color: Colors.orange),
                  title: const Text('禁言 1 天'),
                  onTap: () => _muteMember(
                    pageContext,
                    context,
                    ref,
                    chatId,
                    member.userId,
                    1440,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.volume_off, color: Colors.red),
                  title: const Text('永久禁言'),
                  onTap: () => _muteMember(
                    pageContext,
                    context,
                    ref,
                    chatId,
                    member.userId,
                    0,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(
                  Icons.close,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
                title: const Text('取消'),
                onTap: () => Navigator.pop(context),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _muteMember(
    BuildContext pageContext,
    BuildContext sheetContext,
    WidgetRef ref,
    String chatId,
    String userId,
    int duration,
  ) async {
    Navigator.pop(sheetContext);
    try {
      final chatService = ref.read(api.chatServiceProvider);
      final result = await chatService.muteMember(
        chatId,
        userId,
        duration: duration,
      );
      if (result.isSuccess) {
        ref.invalidate(chatMembersProvider(chatId));
        if (pageContext.mounted) {
          final durationText = duration == 0
              ? '永久'
              : duration >= 1440
              ? '${duration ~/ 1440} 天'
              : duration >= 60
              ? '${duration ~/ 60} 小时'
              : '$duration 分钟';
          ScaffoldMessenger.of(
            pageContext,
          ).showSnackBar(SnackBar(content: Text('已禁言 $durationText')));
        }
      } else if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(
            content: Text(result.message ?? '操作失败'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

// ==================== 频道信息 ====================

class _ChannelInfoSheet extends ConsumerWidget {
  final String name;
  final String? avatar;
  final String channelId;

  const _ChannelInfoSheet({
    required this.name,
    this.avatar,
    required this.channelId,
  });

  String _formatSubscriberCount(int count) {
    if (count >= 10000) {
      return '${(count / 10000).toStringAsFixed(1)}万订阅者';
    }
    return '$count 订阅者';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chatDetailAsync = ref.watch(chatDetailProvider(channelId));

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkBackground : AppColors.lightBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: ListView(
          controller: scrollController,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkDivider
                      : AppColors.lightDivider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Stack(
                children: [
                  AvatarWidget(
                    name: name,
                    avatar: avatar,
                    userId: channelId,
                    size: 80,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkBackground
                            : AppColors.lightBackground,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.verified,
                        size: 24,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Center(
              child: Text(
                chatDetailAsync.when(
                  data: (chat) => chat != null
                      ? '${_formatSubscriberCount(chat.memberCount)} · 频道'
                      : '频道',
                  loading: () => '加载中...',
                  error: (_, __) => '频道',
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
            ),

            // 显示简介
            chatDetailAsync.when(
              data: (chat) {
                if (chat != null &&
                    chat.description != null &&
                    chat.description!.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurface
                            : AppColors.lightSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '简介',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            chat.description!,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return const SizedBox(height: 16);
              },
              loading: () => const SizedBox(height: 16),
              error: (_, __) => const SizedBox(height: 16),
            ),

            // 频道号
            chatDetailAsync.when(
              data: (chat) {
                if (chat != null &&
                    chat.username != null &&
                    chat.username!.isNotEmpty) {
                  return _ActionRow(
                    icon: Icons.alternate_email,
                    title: '频道号',
                    trailing: '@${chat.username}',
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: '@${chat.username}'),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('频道号已复制'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                  );
                }
                return const SizedBox.shrink();
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            _ActionRow(
              icon: Icons.notifications_outlined,
              title: '通知',
              trailing: '开启',
            ),
            _ActionRow(icon: Icons.share_outlined, title: '分享频道'),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;

  const _InfoRow({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? trailing;
  final VoidCallback? onTap;

  const _ActionRow({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trailingColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF151D2D) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.primary.withOpacity(isDark ? 0.18 : 0.10),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(isDark ? 0.10 : 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(
                        isDark ? 0.16 : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  if (trailing != null)
                    Flexible(
                      child: Text(
                        trailing!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: trailingColor,
                        ),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: trailingColor,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ==================== 附件面板 ====================

class _AttachmentSheet extends StatelessWidget {
  final VoidCallback onPickFromGallery;
  final VoidCallback onTakePhoto;
  final VoidCallback? onStartMeeting;
  final VoidCallback? onSendLocation;
  final VoidCallback? onOpenFavorites;
  final VoidCallback onPickFile;
  final VoidCallback? onSendRedPacket;
  final VoidCallback? onTransfer;

  const _AttachmentSheet({
    required this.onPickFromGallery,
    required this.onTakePhoto,
    this.onStartMeeting,
    this.onSendLocation,
    this.onOpenFavorites,
    required this.onPickFile,
    this.onSendRedPacket,
    this.onTransfer,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkDivider : AppColors.lightDivider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 20,
            runSpacing: 20,
            children: [
              _AttachmentOption(
                icon: Icons.perm_media_rounded,
                label: '相册',
                color: const Color(0xFF7B68EE),
                onTap: () {
                  Navigator.pop(context);
                  onPickFromGallery();
                },
              ),
              _AttachmentOption(
                icon: Icons.camera_alt,
                label: '相机',
                color: const Color(0xFFFF6B6B),
                onTap: () {
                  Navigator.pop(context);
                  onTakePhoto();
                },
              ),
              if (onStartMeeting != null)
                _AttachmentOption(
                  icon: Icons.video_call_outlined,
                  label: '会议',
                  color: const Color(0xFF5B8CFF),
                  onTap: () {
                    Navigator.pop(context);
                    onStartMeeting!();
                  },
                ),
              if (onSendLocation != null)
                _AttachmentOption(
                  icon: Icons.location_on_outlined,
                  label: '位置',
                  color: const Color(0xFFEF6C57),
                  onTap: () {
                    Navigator.pop(context);
                    onSendLocation!();
                  },
                ),
              _AttachmentOption(
                icon: Icons.insert_drive_file,
                label: '文件',
                color: const Color(0xFF4ECDC4),
                onTap: () {
                  Navigator.pop(context);
                  onPickFile();
                },
              ),
              if (onSendRedPacket != null)
                _AttachmentOption(
                  imagePath: 'assets/stickers/hongbao.png',
                  label: '红包',
                  color: const Color(0xFFE53935),
                  onTap: () {
                    Navigator.pop(context);
                    onSendRedPacket!();
                  },
                ),
              if (onTransfer != null)
                _AttachmentOption(
                  imagePath: 'assets/stickers/zhuanzhang.png',
                  label: '转账',
                  color: const Color(0xFFFF9800),
                  onTap: () {
                    Navigator.pop(context);
                    onTransfer!();
                  },
                ),
              if (onOpenFavorites != null)
                _AttachmentOption(
                  icon: Icons.favorite_border_rounded,
                  label: '收藏',
                  color: const Color(0xFFFF6FA9),
                  onTap: () {
                    Navigator.pop(context);
                    onOpenFavorites!();
                  },
                ),
            ],
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 20),
        ],
      ),
    );
  }
}

class _AttachmentOption extends StatelessWidget {
  final IconData? icon;
  final String? imagePath;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachmentOption({
    this.icon,
    this.imagePath,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: imagePath != null
                ? Center(
                    child: Image.asset(
                      imagePath!,
                      width: 32,
                      height: 32,
                      errorBuilder: (_, __, ___) =>
                          Icon(icon ?? Icons.error, color: color, size: 26),
                    ),
                  )
                : Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Telegram 风格顶部浮动提示
class _TopToastWidget extends StatefulWidget {
  final String message;
  final bool isDark;
  final VoidCallback onDismiss;

  const _TopToastWidget({
    required this.message,
    required this.isDark,
    required this.onDismiss,
  });

  @override
  State<_TopToastWidget> createState() => _TopToastWidgetState();
}

class _TopToastWidgetState extends State<_TopToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<double>(
      begin: -1.0,
      end: 0.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // 自动消失
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.of(context).padding;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          top: padding.top + 60 + (_slideAnimation.value * 50),
          left: 16,
          right: 16,
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: widget.isDark
                      ? const Color(0xFF2C2C2E).withOpacity(0.95)
                      : Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 20,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.message,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: widget.isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 消息删除破碎动画
class _MessageDeleteAnimation extends StatefulWidget {
  final Offset screenCenter;
  final VoidCallback onComplete;

  const _MessageDeleteAnimation({
    required this.screenCenter,
    required this.onComplete,
  });

  @override
  State<_MessageDeleteAnimation> createState() =>
      _MessageDeleteAnimationState();
}

class _MessageDeleteAnimationState extends State<_MessageDeleteAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late List<_Particle> _particles;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // 创建粒子
    _particles = List.generate(25, (index) {
      final angle = _random.nextDouble() * 2 * math.pi;
      final speed = 150 + _random.nextDouble() * 200;
      final size = 4 + _random.nextDouble() * 8;

      return _Particle(
        x: widget.screenCenter.dx + (_random.nextDouble() - 0.5) * 80,
        y: widget.screenCenter.dy + (_random.nextDouble() - 0.5) * 40,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed - 100,
        size: size,
        color: [
          Colors.grey[400]!,
          Colors.grey[500]!,
          Colors.grey[600]!,
          Colors.blueGrey[300]!,
        ][_random.nextInt(4)],
        rotation: _random.nextDouble() * math.pi * 2,
        rotationSpeed: (_random.nextDouble() - 0.5) * 10,
      );
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: MediaQuery.of(context).size,
          painter: _ParticlePainter(
            particles: _particles,
            progress: _controller.value,
          ),
        );
      },
    );
  }
}

class _Particle {
  double x, y;
  double vx, vy;
  double size;
  Color color;
  double rotation;
  double rotationSpeed;

  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.color,
    required this.rotation,
    required this.rotationSpeed,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  _ParticlePainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final gravity = 800.0;
    final time = progress * 0.6; // 动画时间（秒）

    for (final p in particles) {
      // 计算位置（带重力）
      final x = p.x + p.vx * time;
      final y = p.y + p.vy * time + 0.5 * gravity * time * time;

      // 透明度随时间减少
      final opacity = (1 - progress).clamp(0.0, 1.0);

      // 大小随时间缩小
      final currentSize = p.size * (1 - progress * 0.5);

      // 旋转
      final rotation = p.rotation + p.rotationSpeed * progress;

      final paint = Paint()
        ..color = p.color.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(rotation);

      // 绘制不规则碎片
      final path = Path();
      path.moveTo(-currentSize / 2, -currentSize / 3);
      path.lineTo(currentSize / 2, -currentSize / 2);
      path.lineTo(currentSize / 3, currentSize / 2);
      path.lineTo(-currentSize / 3, currentSize / 3);
      path.close();

      canvas.drawPath(path, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
