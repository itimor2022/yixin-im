// 文件用途：管理会话列表、未读数、置顶状态、草稿和会话同步。
// 核心逻辑：聚合会话列表、未读数、置顶和草稿状态，监听实时消息并将服务端更新合并到本地窗口缓存。
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/storage/isar_service.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/services/api/chat_service.dart' as api;
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/account_session_coordinator.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/android_message_notification_service.dart';
import '../../../core/services/background_service.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/desktop_notification_service.dart';
import '../../../core/services/performance_trace_service.dart';
import '../../../core/services/time_zone_refresh_service.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/storage/models/chat_model.dart'
    if (dart.library.js_interop) '../../../core/services/storage/models/chat_model_web.dart'
    as storage;
import '../../../core/services/storage/models/message_model.dart'
    if (dart.library.js_interop) '../../../core/services/storage/models/message_model_web.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../services/emoji_store_service.dart';
import '../utils/call_preview_formatter.dart';
import '../utils/system_message_text.dart';
import 'message_provider.dart'
    show
        MessageItem,
        MessageMemoryWindowCache,
        persistMessageItemsToIsarCache,
        persistMessageItemsToWebWindowCache,
        readWebMessageWindowMaxSeq;

const Object _chatItemUnset = Object();

String _chatProviderText({
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

String _chatPreviewLabel(String key) {
  switch (key) {
    case 'photo':
      return _chatProviderText(zhCN: '[图片]', zhTW: '[圖片]', en: '[Photo]');
    case 'video':
      return _chatProviderText(zhCN: '[视频]', zhTW: '[影片]', en: '[Video]');
    case 'voice':
      return _chatProviderText(
        zhCN: '[语音]',
        zhTW: '[語音]',
        en: '[Voice message]',
      );
    case 'file':
      return _chatProviderText(zhCN: '[文件]', zhTW: '[檔案]', en: '[File]');
    case 'location':
      return _chatProviderText(
        zhCN: '[位置]',
        zhTW: '[位置]',
        en: '[Location]',
      );
    case 'sticker':
      return _chatProviderText(
        zhCN: '[表情]',
        zhTW: '[貼圖]',
        en: '[Sticker]',
      );
    case 'contact':
      return _chatProviderText(
        zhCN: '[联系人名片]',
        zhTW: '[聯絡人名片]',
        en: '[Contact card]',
      );
    case 'call':
      return _chatProviderText(zhCN: '[通话]', zhTW: '[通話]', en: '[Call]');
    case 'red_packet':
      return _chatProviderText(
        zhCN: '[红包]',
        zhTW: '[紅包]',
        en: '[Red packet]',
      );
    case 'transfer':
      return _chatProviderText(
        zhCN: '[转账]',
        zhTW: '[轉帳]',
        en: '[Transfer]',
      );
    case 'message':
      return _chatProviderText(zhCN: '[消息]', zhTW: '[訊息]', en: '[Message]');
    default:
      return key;
  }
}

String? _normalizePreviewSenderName(String? rawName) {
  final value = rawName?.trim();
  if (value == null || value.isEmpty) return rawName;
  if (value == _legacySystemSenderMojibake) {
    return _chatProviderText(zhCN: '系统消息', zhTW: '系統消息', en: 'System');
  }
  return value;
}

final _legacySystemSenderMojibake =
    String.fromCharCodes([0x7eef, 0x837b, 0x7cba, 0x5a11, 0x581f, 0x4f05]);
String _localizedCallPreview(
  String? rawText, {
  String? callType,
  String? status,
  int? duration,
  bool isOutgoing = false,
}) {
  final preview = formatChatCallPreview(
    text: rawText,
    callType: callType,
    status: status,
    durationSeconds: duration,
    isOutgoing: isOutgoing,
  );
  return preview.summary.isEmpty ? _chatPreviewLabel('call') : preview.summary;
}

String _chatServerMessage(String? raw, {required String fallbackEn}) {
  return localizeServerMessage(raw, fallbackEn: fallbackEn);
}

DateTime? _normalizeChatListTime(DateTime? value) {
  if (value == null) return null;
  final normalized = toCurrentLocalTime(value);
  if (normalized.year <= 1) return null;
  return normalized;
}

// 关键声明：chat provider 是状态边界，统一管理加载、成功、失败和刷新状态，避免页面直接维护异步请求结果。
/// 消息内容类型
enum MessageContentType {
  text,
  photo,
  video,
  voice,
  file,
  sticker,
  location,
  contact,
  poll,
  call,
}

/// 聊天项数据模型
class ChatItem {
  final String id;
  final String name;
  final String? avatar;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final bool isOnline;
  final bool isVerified;
  final int pendingJoinRequestCount;
  final bool hasPendingJoinRequests;
  final ChatItemType type;
  final String? draft;
  final String? lastMessageSender;
  final MessageContentType? lastMessageType;
  final String? lastMessageMediaUrl;
  final bool isSentByMe;
  final bool isRead;
  final List<String> memberIds;
  final String? description;
  final DateTime createdAt;
  final String? targetUserId; // 私聊对方用户 ID（用于头像颜色一致性）
  final String? targetUserUuid; // 私聊对方用户 UUID（用于官方用户判断）
  final String? username;
  final int _realMemberCount; // 后端返回的真实成员数
  final String? emojiAvatar; // 表情状态
  final String? nicknameColor; // 昵称颜色
  final int vipLevel;
  final String vipBadge;
  final String vipBadgeIcon;
  final bool vipActive;
  final int lastMessageSeq; // 最新消息序号，用于判断编辑是否影响预览
  final bool hasMention;
  final bool lastMessageFailed;
  final int status;

  const ChatItem({
    required this.id,
    required this.name,
    this.avatar,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.isOnline = false,
    this.isVerified = false,
    this.pendingJoinRequestCount = 0,
    this.hasPendingJoinRequests = false,
    this.type = ChatItemType.private,
    this.draft,
    this.lastMessageSender,
    this.lastMessageType,
    this.lastMessageMediaUrl,
    this.isSentByMe = false,
    this.isRead = false,
    this.memberIds = const [],
    this.description,
    required this.createdAt,
    this.targetUserId,
    this.targetUserUuid,
    this.username,
    int realMemberCount = 0,
    this.emojiAvatar,
    this.nicknameColor,
    this.vipLevel = 0,
    this.vipBadge = '',
    this.vipBadgeIcon = '',
    this.vipActive = false,
    this.lastMessageSeq = 0,
    this.hasMention = false,
    this.lastMessageFailed = false,
    this.status = 0,
  }) : _realMemberCount = realMemberCount;

  bool get vipVisible => vipActive && vipLevel > 0;

  ChatItem copyWith({
    String? id,
    String? name,
    String? avatar,
    String? lastMessage,
    bool clearLastMessage = false,
    DateTime? lastMessageTime,
    bool clearLastMessageTime = false,
    int? unreadCount,
    bool? isPinned,
    bool? isMuted,
    bool? isOnline,
    bool? isVerified,
    int? pendingJoinRequestCount,
    bool? hasPendingJoinRequests,
    ChatItemType? type,
    String? draft,
    bool clearDraft = false,
    String? lastMessageSender,
    bool clearLastMessageSender = false,
    MessageContentType? lastMessageType,
    bool clearLastMessageType = false,
    Object? lastMessageMediaUrl = _chatItemUnset,
    bool? isSentByMe,
    bool? isRead,
    List<String>? memberIds,
    String? description,
    DateTime? createdAt,
    String? targetUserId,
    String? targetUserUuid,
    String? username,
    int? realMemberCount,
    String? emojiAvatar,
    String? nicknameColor,
    int? vipLevel,
    String? vipBadge,
    String? vipBadgeIcon,
    bool? vipActive,
    int? lastMessageSeq,
    bool? hasMention,
    bool? lastMessageFailed,
    int? status,
  }) {
    return ChatItem(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      lastMessage: clearLastMessage ? null : (lastMessage ?? this.lastMessage),
      lastMessageTime: clearLastMessageTime
          ? null
          : (lastMessageTime ?? this.lastMessageTime),
      unreadCount: unreadCount ?? this.unreadCount,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      isOnline: isOnline ?? this.isOnline,
      isVerified: isVerified ?? this.isVerified,
      pendingJoinRequestCount:
          pendingJoinRequestCount ?? this.pendingJoinRequestCount,
      hasPendingJoinRequests:
          hasPendingJoinRequests ?? this.hasPendingJoinRequests,
      type: type ?? this.type,
      draft: clearDraft ? null : (draft ?? this.draft),
      lastMessageSender: clearLastMessageSender
          ? null
          : (lastMessageSender ?? this.lastMessageSender),
      lastMessageType: clearLastMessageType
          ? null
          : (lastMessageType ?? this.lastMessageType),
      lastMessageMediaUrl: identical(lastMessageMediaUrl, _chatItemUnset)
          ? this.lastMessageMediaUrl
          : lastMessageMediaUrl as String?,
      isSentByMe: isSentByMe ?? this.isSentByMe,
      isRead: isRead ?? this.isRead,
      memberIds: memberIds ?? this.memberIds,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      targetUserId: targetUserId ?? this.targetUserId,
      targetUserUuid: targetUserUuid ?? this.targetUserUuid,
      username: username ?? this.username,
      realMemberCount: realMemberCount ?? _realMemberCount,
      emojiAvatar: emojiAvatar ?? this.emojiAvatar,
      nicknameColor: nicknameColor ?? this.nicknameColor,
      vipLevel: vipLevel ?? this.vipLevel,
      vipBadge: vipBadge ?? this.vipBadge,
      vipBadgeIcon: vipBadgeIcon ?? this.vipBadgeIcon,
      vipActive: vipActive ?? this.vipActive,
      lastMessageSeq: lastMessageSeq ?? this.lastMessageSeq,
      hasMention: hasMention ?? this.hasMention,
      lastMessageFailed: lastMessageFailed ?? this.lastMessageFailed,
      status: status ?? this.status,
    );
  }

  /// 格式化时间（统一：昨天/周X 带具体时间，更早日期用 月/日 或 年/月/日）
  String get time {
    final t = _normalizeChatListTime(lastMessageTime);
    if (t == null) return '';
    final now = DateTime.now();
    final diff = now.difference(t);
    final hhmm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    if (diff.inMinutes < 1) {
      return _chatProviderText(zhCN: '刚刚', zhTW: '剛剛', en: 'Just now');
    }
    if (diff.inHours < 1) {
      return _chatProviderText(
        zhCN: '${diff.inMinutes}分钟前',
        zhTW: '${diff.inMinutes}分鐘前',
        en: '${diff.inMinutes}m ago',
      );
    }
    if (diff.inDays < 1) {
      return hhmm;
    }
    if (diff.inDays == 1) {
      return _chatProviderText(
        zhCN: '昨天 $hhmm',
        zhTW: '昨天 $hhmm',
        en: 'Yesterday $hhmm',
      );
    }
    if (diff.inDays < 7) {
      final weekDays = [
        _chatProviderText(zhCN: '周一', zhTW: '週一', en: 'Mon'),
        _chatProviderText(zhCN: '周二', zhTW: '週二', en: 'Tue'),
        _chatProviderText(zhCN: '周三', zhTW: '週三', en: 'Wed'),
        _chatProviderText(zhCN: '周四', zhTW: '週四', en: 'Thu'),
        _chatProviderText(zhCN: '周五', zhTW: '週五', en: 'Fri'),
        _chatProviderText(zhCN: '周六', zhTW: '週六', en: 'Sat'),
        _chatProviderText(zhCN: '周日', zhTW: '週日', en: 'Sun'),
      ];
      return '${weekDays[t.weekday - 1]} $hhmm';
    }
    if (t.year == now.year) {
      return '${t.month}/${t.day}';
    }
    return '${t.year}/${t.month}/${t.day}';
  }

  /// 成员数量（优先使用后端返回的真实数量）
  int get memberCount =>
      _realMemberCount > 0 ? _realMemberCount : memberIds.length;
}

@visibleForTesting
List<ChatItem> mergeServerChatsWithLocalDrafts(
  List<ChatItem> serverChats,
  Iterable<ChatItem> localChats,
) {
  final localById = {for (final chat in localChats) chat.id: chat};
  if (localById.isEmpty) return serverChats;

  return serverChats.map(
    (chat) {
      final local = localById[chat.id];
      if (local == null) return chat;

      var merged = chat;
      final localFailureIsCurrent = local.lastMessageFailed &&
          local.lastMessageTime != null &&
          (chat.lastMessageTime == null ||
              !local.lastMessageTime!.isBefore(chat.lastMessageTime!));
      if (localFailureIsCurrent) {
        merged = merged.copyWith(
          lastMessage: local.lastMessage,
          lastMessageTime: local.lastMessageTime,
          lastMessageSender: local.lastMessageSender,
          lastMessageType: local.lastMessageType,
          lastMessageMediaUrl: local.lastMessageMediaUrl,
          isSentByMe: true,
          lastMessageFailed: true,
        );
      }
      if ((local.draft ?? '').isNotEmpty) {
        merged = merged.copyWith(draft: local.draft);
      }
      return merged;
    },
  ).toList();
}

enum ChatItemType { private, group, channel }

/// 会话列表的可见投影：服务端会话元数据与本地草稿、未读和实时预览在此合并。
class ChatListState {
  final List<ChatItem> pinnedChats;
  final List<ChatItem> regularChats;
  final Map<String, String> typingByChat; // chatId -> typing display text
  final bool isLoading;
  final bool isSilentLoading; // 静默刷新中（从后台恢复时）
  final String? error;
  final bool isInitialized;

  const ChatListState({
    this.pinnedChats = const [],
    this.regularChats = const [],
    this.typingByChat = const {},
    this.isLoading = false,
    this.isSilentLoading = false,
    this.error,
    this.isInitialized = false,
  });

  ChatListState copyWith({
    List<ChatItem>? pinnedChats,
    List<ChatItem>? regularChats,
    Map<String, String>? typingByChat,
    bool? isLoading,
    bool? isSilentLoading,
    String? error,
    bool clearError = false,
    bool? isInitialized,
  }) {
    return ChatListState(
      pinnedChats: pinnedChats ?? this.pinnedChats,
      regularChats: regularChats ?? this.regularChats,
      typingByChat: typingByChat ?? this.typingByChat,
      isLoading: isLoading ?? this.isLoading,
      isSilentLoading: isSilentLoading ?? this.isSilentLoading,
      // 仅在明确传入 error 或 clearError=true 时才覆盖，否则保留原有 error
      error: clearError ? null : (error ?? this.error),
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }

  /// 获取所有聊天
  List<ChatItem> get allChats => [...pinnedChats, ...regularChats];

  /// 是否为空
  bool get isEmpty => pinnedChats.isEmpty && regularChats.isEmpty;

  /// 是否在加载中（包括静默加载）
  bool get isRefreshing => isLoading || isSilentLoading;
}

/// 聊天列表 Provider
final chatListProvider = StateNotifierProvider<ChatListNotifier, ChatListState>(
  (ref) {
    // 聊天列表是用户态数据，切换账号时必须重建，避免沿用旧账号缓存
    final accountId = ref.watch(currentAccountIdProvider);
    // 使用 ref.read 而非 ref.watch，这些服务不会变化，避免不必要的重建
    final chatService = ref.read(api.chatServiceProvider);
    final wsService = ref.read(webSocketServiceProvider.notifier);
    return ChatListNotifier(chatService, wsService, ref, accountId);
  },
);

/// 管理会话列表级状态；单个会话的完整消息窗口由 [MessageListNotifier] 负责。
class ChatListNotifier extends StateNotifier<ChatListState> {
  static final String _burnAfterReadPreviewText = _chatProviderText(
    zhCN: '[阅后即焚消息]',
    zhTW: '[閱後即焚訊息]',
    en: '[Burn after reading]',
  );

  final api.ChatService _chatService;
  final WebSocketService _wsService;
  final Ref _ref;
  final String _accountId;
  final _uuid = const Uuid();

  // 存储 handler IDs 用于清理
  final List<String> _wsHandlerIds = [];

  // 是否已被释放（用于安全检查）
  bool _isDisposed = false;
  bool _deliveryEndpointUnavailable = false;
  Timer? _deliveryReceiptTimer;
  final Map<String, int> _pendingDeliverySeqByChat = <String, int>{};
  String? _activeChatId; // 用户当前正在查看的聊天 ID，防止误加未读
  /// 防止 WS 重连后并发执行多轮「全会话增量预取」
  bool _prefetchMissedMessagesRunning = false;
  bool _hotPrewarmRunning = false;
  Future<void>? _initializeFuture;
  DateTime? _lastMissedMessageSyncTime;
  DateTime? _lastHotPrewarmTime;
  static const Duration _missedMessageSyncMinInterval = Duration(seconds: 8);
  static const Duration _typingTimeout = Duration(seconds: 8);
  static const int _recentMessageIdLimit = 512;
  final Map<String, Map<String, String>> _typingUsersByChat = {};
  final Map<String, Timer> _typingTimers = {};
  final Set<String> _recentMessageIds = <String>{};
  final List<String> _recentMessageIdOrder = <String>[];
  final Map<String, api.Message> _pendingChatListMessages =
      <String, api.Message>{};
  Timer? _chatListMessageBatchTimer;
  static const Duration _chatListMessageBatchDelay = Duration(milliseconds: 80);

  /// 设置当前活跃聊天（进入聊天页面时调用）
  void setActiveChatId(String? chatId) {
    _activeChatId = chatId;
    if (chatId != null && chatId.isNotEmpty) {
      final chat = _findChatById(chatId);
      if (chat != null && chat.hasMention) {
        updateChat(chat.copyWith(hasMention: false));
      }
    }
  }

  String? get activeChatId => _activeChatId;

  ChatListNotifier(
    this._chatService,
    this._wsService,
    this._ref,
    this._accountId,
  ) : super(const ChatListState()) {
    if (_accountId.isNotEmpty) {
      _setupWebSocketHandlers();
    }
  }

  /// 安全地更新 state（防止 dispose 后更新）
  void _safeSetState(ChatListState Function(ChatListState) update) {
    if (_isDisposed) return;
    state = update(state);
  }

  /// 设置 WebSocket 消息处理
  void _setupWebSocketHandlers() {
    // 清理旧的 handlers
    _cleanupHandlers();

    // 列表层只更新预览、未读和通知；完整消息由 MessageListNotifier 的唯一 WS handler 消费。
    // 监听新消息
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.newMessage, (data) async {
        final raw = data['message'];
        if (raw == null) return;
        if (raw is! Map) {
          debugPrint(
            '[Chat] WS new_message: expected message object, got ${raw.runtimeType}',
          );
          return;
        }
        try {
          final message = await _chatService.parseIncomingMessage(
            Map<String, dynamic>.from(raw),
          );
          if (message.senderId != _accountId && message.seq > 0) {
            _scheduleRealtimeDelivery(message);
          }
          _queueNewMessage(message);
        } catch (e, st) {
          debugPrint('[Chat] WS new_message fromJson failed: $e');
          debugPrintStack(stackTrace: st, maxFrames: 12);
        }
      }),
    );

    // 监听正在输入状态（用于会话列表预览）
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.typing, (data) {
        _handleTypingEvent(data);
      }),
    );

    // 监听新会话
    _wsHandlerIds.add(
      _wsService.registerHandler('new_chat', (data) {
        _handleNewChat(data);
      }),
    );

    // 监听重连事件 → 静默刷新会话列表，并对本地会话做增量预取写入 Isar（无需再进会话才拉到断网期间消息）
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.reconnected, (data) {
        debugPrint('[Chat] WS reconnected, silent refreshing chat list...');
        unawaited(_onWebSocketReconnectedResume());
      }),
    );

    // 监听已读回执 (后端发送的 type 是 "read")
    _wsHandlerIds.add(
      _wsService.registerHandler('read', (data) {
        final chatId = data['chat_id'] as String?;
        if (chatId != null) {
          debugPrint('[Chat] Received read receipt for chat: $chatId');
        }
      }),
    );

    // 监听自己其他设备的已读同步（type: "read_sync"）
    _wsHandlerIds.add(
      _wsService.registerHandler('read_sync', (data) {
        final chatId = data['chat_id'] as String?;
        if (chatId != null) {
          final chat = _findChatById(chatId);
          if (chat != null && chat.unreadCount > 0) {
            debugPrint('[Chat] read_sync: clearing unread for chat $chatId');
            updateChat(chat.copyWith(unreadCount: 0, hasMention: false));
          }
        }
      }),
    );

    _wsHandlerIds.add(
      _wsService.registerHandler('chat_state_changed', (data) {
        _applyChatStateChanged(data);
      }),
    );

    // 监听群组被解散（type: "chat_deleted"）
    _wsHandlerIds.add(
      _wsService.registerHandler('chat_deleted', (data) {
        final chatId = data['chat_id'] as String?;
        if (chatId != null) {
          debugPrint('[Chat] Chat deleted: $chatId');
          removeChat(chatId);
        }
      }),
    );

    _wsHandlerIds.add(
      _wsService.registerHandler('chat_dissolved', (data) {
        final chatId = data['chat_id']?.toString();
        if (chatId == null || chatId.isEmpty) return;
        final chat = _findChatById(chatId);
        if (chat != null) {
          _clearTypingForChat(chatId);
          updateChat(chat.copyWith(status: 2));
        }
        _ref.invalidate(chatDetailProvider(chatId));
      }),
    );

    _wsHandlerIds.add(
      _wsService.registerHandler('member_role_changed', (data) {
        final chatId = data['chat_id']?.toString();
        if (chatId == null || chatId.isEmpty) return;
        _ref.invalidate(chatDetailProvider(chatId));
        _ref.invalidate(chatMembersProvider(chatId));
      }),
    );

    // 监听当前用户在其他设备上隐藏/删除了会话（多端同步，type: "chat_hidden"）
    _wsHandlerIds.add(
      _wsService.registerHandler('chat_hidden', (data) {
        final chatId = data['chat_id'] as String?;
        if (chatId != null) {
          debugPrint('[Chat] Chat hidden on another device, syncing: $chatId');
          _clearTypingForChat(chatId);
          // 从本地列表移除（不再调用后端，避免循环）
          state = state.copyWith(
            pinnedChats:
                state.pinnedChats.where((c) => c.id != chatId).toList(),
            regularChats:
                state.regularChats.where((c) => c.id != chatId).toList(),
          );
        }
      }),
    );

    // 监听聊天记录被清空（仅自己/双方）
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.chatHistoryCleared, (data) {
        final chatId = data['chat_id']?.toString();
        if (chatId == null || chatId.isEmpty) return;

        final chat = _findChatById(chatId);
        if (chat == null) return;

        _clearTypingForChat(chatId);
        clearHistoryPreview(chatId);
      }),
    );

    // 监听自己退出群组/被踢出（type: "chat_left"）
    _wsHandlerIds.add(
      _wsService.registerHandler('chat_left', (data) {
        final chatId = data['chat_id'] as String?;
        if (chatId != null) {
          debugPrint('[Chat] Chat left: $chatId');
          removeChat(chatId);
        }
      }),
    );

    // 监听个人资料更新（其他设备编辑后同步，type: "profile_updated"）
    _wsHandlerIds.add(
      _wsService.registerHandler('profile_updated', (data) {
        debugPrint('[Chat] Profile updated from another device');
        // 刷新当前用户信息
        _ref.read(authServiceProvider.notifier).getCurrentUser();
        // 同步刷新聊天列表，确保自己的资料变更后相关会话样式及时更新
        unawaited(silentRefresh(bypassDebounce: true));
      }),
    );

    // 监听用户资料更新（昵称、头像、彩名、表情状态）
    _wsHandlerIds.add(
      _wsService.registerHandler('user_profile', (data) {
        _handleUserProfileUpdate(data);
        final activeChatId = _activeChatId;
        if (activeChatId == null || activeChatId.isEmpty) return;

        final chatId = data['chat_id']?.toString();
        final userId = data['user_id']?.toString();
        if ((chatId != null && chatId == activeChatId) ||
            (userId != null &&
                state.allChats.any(
                  (chat) =>
                      chat.id == activeChatId &&
                      chat.type == ChatItemType.private &&
                      (chat.targetUserUuid == userId ||
                          chat.targetUserId == userId),
                ))) {
          _ref.invalidate(chatDetailProvider(activeChatId));
        }
      }),
    );

    // 监听加入申请通过
    _wsHandlerIds.add(
      _wsService.registerHandler('join_approved', (data) {
        final chatId = data['chat_id'] as String?;
        final name = data['name'] as String?;
        debugPrint('[Chat] Join request approved for chat: $chatId ($name)');
        loadFromServer();
        if (chatId != null) {
          _ref.invalidate(chatDetailProvider(chatId));
        }
      }),
    );

    // 监听加入申请被拒绝
    _wsHandlerIds.add(
      _wsService.registerHandler('join_rejected', (data) {
        final chatId = data['chat_id'] as String?;
        final name = data['name'] as String?;
        debugPrint('[Chat] Join request rejected for chat: $chatId ($name)');
        if (chatId != null) {
          _ref.invalidate(chatDetailProvider(chatId));
        }
      }),
    );

    // 监听群组/频道成员变化
    _wsHandlerIds.add(
      _wsService.registerHandler('chat_update', (data) {
        final chatId = data['chat_id'] as String?;
        debugPrint('[Chat] Chat updated: $chatId');
        if (chatId != null) {
          _ref.invalidate(chatDetailProvider(chatId));
          _ref.invalidate(chatMembersProvider(chatId));
        }
        loadFromServer();
      }),
    );

    // 监听用户在线状态变化 — 只刷新匹配的私聊，避免 N 次 API 请求
    _wsHandlerIds.add(
      _wsService.registerHandler('user_status', (data) {
        final userId = data['user_id'] as String?;
        final isOnline = data['is_online'] as bool? ?? false;
        if (userId == null) return;
        debugPrint('[Chat] User status changed: $userId, isOnline=$isOnline');
        var matchedChatId = '';
        ChatItem updateChat(ChatItem chat) {
          final matches = chat.type == ChatItemType.private &&
              (chat.targetUserUuid == userId || chat.targetUserId == userId);
          if (!matches) return chat;
          matchedChatId = chat.id;
          return chat.copyWith(isOnline: isOnline);
        }

        final nextRegular = state.regularChats.map(updateChat).toList();
        final nextPinned = state.pinnedChats.map(updateChat).toList();
        if (matchedChatId.isNotEmpty) {
          state = state.copyWith(
            regularChats: nextRegular,
            pinnedChats: nextPinned,
          );
          _ref.invalidate(chatDetailProvider(matchedChatId));
        }

        // 只找到与该用户的私聊并刷新（O(1) 而不是 O(N)）
        final allChats = [...state.regularChats, ...state.pinnedChats];
        for (final chat in allChats) {
          if (chat.type == ChatItemType.private &&
              chat.targetUserUuid == userId) {
            _ref.invalidate(chatDetailProvider(chat.id));
            break; // 一个用户最多一个私聊
          }
        }
      }),
    );

    // 监听消息编辑
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.messageEdited, (data) async {
        final rawMessage = data['message'];
        if (rawMessage is Map) {
          try {
            final message = await _chatService.parseIncomingMessage(
              Map<String, dynamic>.from(rawMessage),
            );
            final preview = _previewForMessage(message);
            _handleMessageEdited(
              message.chatId,
              preview.$1,
              msgId: message.msgId,
              msgSeq: message.seq,
              lastMessageType: preview.$2,
            );
            return;
          } catch (e) {
            debugPrint('[Chat] parse edited message failed: $e');
          }
        }
        final chatId = data['chat_id']?.toString();
        final newContent = data['new_content']?.toString();
        final msgId = data['msg_id']?.toString();
        final msgSeq = (data['seq'] as num?)?.toInt();
        if (chatId != null && newContent != null) {
          _handleMessageEdited(
            chatId,
            newContent,
            msgId: msgId,
            msgSeq: msgSeq,
          );
        }
      }),
    );

    // 监听消息撤回 — 更新聊天列表预览
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.messageRevoked, (data) {
        final chatId = data['chat_id'] as String?;
        final revokerId = data['revoker_id'] as String?;
        final msgSeq = (data['msg_seq'] as num?)?.toInt();
        if (chatId != null) {
          // Notification validity is independent of whether this message is
          // still the conversation preview. Never let the preview guard leave
          // revoked unread content visible in the Android notification tray.
          unawaited(
            AndroidMessageNotificationService.instance
                .cancelMessageNotification(
              chatId: chatId,
              messageId: data['msg_id']?.toString(),
            ),
          );
          final chat = _findChatById(chatId);
          if (chat != null) {
            // 仅当被撤回消息是最后一条时才更新预览
            if (msgSeq != null && msgSeq > 0 && chat.lastMessageSeq != msgSeq) {
              return;
            }
            final isSelf = revokerId == _getCurrentUserId();
            final isGroup = chat.type == ChatItemType.group ||
                chat.type == ChatItemType.channel;
            final revokeText = isSelf
                ? _chatProviderText(
                    zhCN: '你撤回了一条消息',
                    zhTW: '你撤回了一則訊息',
                    en: 'You revoked a message',
                  )
                : isGroup
                    ? _chatProviderText(
                        zhCN: '有人撤回了一条消息',
                        zhTW: '有人撤回了一則訊息',
                        en: 'Someone revoked a message',
                      )
                    : _chatProviderText(
                        zhCN: '对方撤回了一条消息',
                        zhTW: '對方撤回了一則訊息',
                        en: 'The other party revoked a message',
                      );
            final updatedChat = chat.copyWith(
              lastMessage: revokeText,
              lastMessageMediaUrl: null,
              lastMessageFailed: false,
            );
            updateChat(updatedChat);
          }
        }
      }),
    );

    // 监听成员禁言状态变更
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.memberMuteStatusChanged, (data) {
        final payload = data['message'] is Map
            ? Map<String, dynamic>.from(data['message'] as Map)
            : data;
        final chatId = payload['chat_id'] as String?;
        final userId = payload['user_id'] as String?;
        debugPrint(
          '[Chat] Member mute status changed: chatId=$chatId, userId=$userId',
        );
        if (chatId != null && userId != null) {
          _ref.invalidate(myMuteStatusProvider((chatId, userId)));
          _ref.invalidate(chatMembersProvider(chatId));
        }
      }),
    );

    // 监听聊天权限更新（全员禁言等）
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.chatPermissionsUpdated, (data) {
        // 后端发送格式: { type, message: { chat_id, can_send_message, ... } }
        final message = data['message'] as Map<String, dynamic>?;
        final chatId =
            message?['chat_id'] as String? ?? data['chat_id'] as String?;
        debugPrint('[Chat] Chat permissions updated: chatId=$chatId');
        if (chatId != null) {
          _ref.invalidate(chatDetailProvider(chatId));
        }
      }),
    );
  }

  void _scheduleRealtimeDelivery(api.Message message) {
    final current = _pendingDeliverySeqByChat[message.chatId] ?? 0;
    if (message.seq > current) {
      _pendingDeliverySeqByChat[message.chatId] = message.seq;
    }
    _deliveryReceiptTimer?.cancel();
    _deliveryReceiptTimer = Timer(
      const Duration(milliseconds: 400),
      () {
        _deliveryReceiptTimer = null;
        unawaited(_flushRealtimeDeliveries());
      },
    );
  }

  Future<void> _flushRealtimeDeliveries() async {
    if (_isDisposed) return;
    if (_pendingDeliverySeqByChat.isEmpty) return;
    final pending = Map<String, int>.from(_pendingDeliverySeqByChat);
    _pendingDeliverySeqByChat.clear();

    for (final entry in pending.entries) {
      if (!_deliveryEndpointUnavailable) {
        final response = await _chatService.markAsDelivered(
          entry.key,
          msgSeq: entry.value,
        );
        if (response.isSuccess) continue;
        if (response.code == 404) {
          _deliveryEndpointUnavailable = true;
        }
      }

      // Compatibility with servers that predate /message/delivered: fetching
      // the newest row uses the existing idempotent delivered-receipt path.
      await _chatService.getMessages(entry.key, limit: 1);
    }
  }

  /// 清理 WebSocket handlers
  void _cleanupHandlers() {
    for (final id in _wsHandlerIds) {
      _wsService.unregisterHandler(id);
    }
    _wsHandlerIds.clear();
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  @override
  void dispose() {
    _deliveryReceiptTimer?.cancel();
    _deliveryReceiptTimer = null;
    _chatListMessageBatchTimer?.cancel();
    _chatListMessageBatchTimer = null;
    _pendingChatListMessages.clear();
    if (_pendingDeliverySeqByChat.isNotEmpty) {
      unawaited(_flushRealtimeDeliveries());
    }
    _isDisposed = true;
    _cleanupHandlers();
    _clearAllTyping();
    _recentMessageIds.clear();
    _recentMessageIdOrder.clear();
    super.dispose();
  }

  /// 处理用户资料更新（昵称、头像、彩名、表情状态）
  void _handleUserProfileUpdate(dynamic data) {
    if (_isDisposed) return;

    final userId = data['user_id']?.toString();
    if (userId == null || userId.isEmpty) return;

    String? avatarUrl = data['avatar'] as String?;
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
    }

    final nextName = (data['nickname'] ?? data['name'])?.toString();
    final nextNicknameColor = data['nickname_color']?.toString();
    final nextEmojiAvatar = data['emoji_avatar']?.toString();

    bool changed = false;
    final previousPinned = state.pinnedChats;
    final previousRegular = state.regularChats;
    final updatedPinned = previousPinned.map((chat) {
      final updated = _applyProfileUpdateToChat(
        chat,
        userId: userId,
        name: nextName,
        avatar: avatarUrl,
        nicknameColor: nextNicknameColor,
        emojiAvatar: nextEmojiAvatar,
      );
      if (!identical(updated, chat)) changed = true;
      return updated;
    }).toList();

    final updatedRegular = previousRegular.map((chat) {
      final updated = _applyProfileUpdateToChat(
        chat,
        userId: userId,
        name: nextName,
        avatar: avatarUrl,
        nicknameColor: nextNicknameColor,
        emojiAvatar: nextEmojiAvatar,
      );
      if (!identical(updated, chat)) changed = true;
      return updated;
    }).toList();

    if (!changed) return;

    state = state.copyWith(
      pinnedChats: updatedPinned,
      regularChats: updatedRegular,
    );

    if (PlatformUtils.isWeb) {
      unawaited(
        _saveChatListToWebCache([...state.pinnedChats, ...state.regularChats]),
      );
    } else {
      Future.microtask(() async {
        try {
          if (!IsarService.instance.isAvailable) return;
          final accountId = _getCurrentUserId() ?? '';
          if (accountId.isEmpty) return;
          final changedChats = [
            ...updatedPinned.where(
              (chat) => previousPinned.any(
                (old) => old.id == chat.id && !identical(old, chat),
              ),
            ),
            ...updatedRegular.where(
              (chat) => previousRegular.any(
                (old) => old.id == chat.id && !identical(old, chat),
              ),
            ),
          ];
          if (changedChats.isEmpty) return;
          await IsarService.instance.isar.writeTxn(() async {
            await IsarService.instance.isar.chatModels.putAll(
              changedChats.map(_itemToChatModel).toList(),
            );
          });
        } catch (e) {
          debugPrint('[Chat] Failed to persist user profile update: $e');
        }
      });
    }
  }

  ChatItem _applyProfileUpdateToChat(
    ChatItem chat, {
    required String userId,
    String? name,
    String? avatar,
    String? nicknameColor,
    String? emojiAvatar,
  }) {
    final isTargetUser = chat.type == ChatItemType.private &&
        (chat.targetUserUuid == userId || chat.targetUserId == userId);
    if (!isTargetUser) return chat;

    return chat.copyWith(
      name: name != null && name.isNotEmpty ? name : chat.name,
      avatar: avatar ?? chat.avatar,
      nicknameColor: nicknameColor ?? chat.nicknameColor,
      emojiAvatar: emojiAvatar ?? chat.emojiAvatar,
    );
  }

  void _handleTypingEvent(dynamic data) {
    if (_isDisposed || data is! Map) return;
    final payload = Map<String, dynamic>.from(data);
    final chatId = payload['chat_id']?.toString();
    final userId = payload['user_id']?.toString();
    final action = payload['action']?.toString() ?? '';
    if (chatId == null || chatId.isEmpty || userId == null || userId.isEmpty) {
      return;
    }
    if (userId == _getCurrentUserId()) return;

    final chat = _findChatById(chatId);
    if (chat == null) return;

    if (action == 'stop') {
      _removeTypingUser(chatId, userId);
      return;
    }

    final rawName = payload['user_name']?.toString().trim() ?? '';
    final displayName = rawName.isNotEmpty
        ? rawName
        : (chat.type == ChatItemType.private
            ? _chatProviderText(
                zhCN: '对方',
                zhTW: '對方',
                en: 'Other party',
              )
            : _chatProviderText(
                zhCN: '有人',
                zhTW: '有人',
                en: 'Someone',
              ));

    final typingUsers = _typingUsersByChat.putIfAbsent(
      chatId,
      () => <String, String>{},
    );
    // Reinsert to keep this user as the "latest typing" one.
    typingUsers.remove(userId);
    typingUsers[userId] = displayName;

    final timerKey = '$chatId:$userId';
    _typingTimers[timerKey]?.cancel();
    _typingTimers[timerKey] = Timer(_typingTimeout, () {
      _removeTypingUser(chatId, userId);
    });

    _syncTypingDisplay(chatId);
  }

  void _removeTypingUser(String chatId, String userId) {
    final typingUsers = _typingUsersByChat[chatId];
    if (typingUsers == null) return;

    typingUsers.remove(userId);
    final timerKey = '$chatId:$userId';
    _typingTimers[timerKey]?.cancel();
    _typingTimers.remove(timerKey);

    if (typingUsers.isEmpty) {
      _typingUsersByChat.remove(chatId);
    }
    _syncTypingDisplay(chatId);
  }

  void _syncTypingDisplay(String chatId) {
    final chat = _findChatById(chatId);
    if (chat == null) return;

    final next = Map<String, String>.from(state.typingByChat);
    final typingUsers = _typingUsersByChat[chatId];
    if (typingUsers == null || typingUsers.isEmpty) {
      next.remove(chatId);
    } else if (chat.type == ChatItemType.private) {
      next[chatId] = _chatProviderText(
        zhCN: '正在输入...',
        zhTW: '正在輸入...',
        en: 'Typing...',
      );
    } else {
      final latestName = typingUsers.values.isNotEmpty
          ? typingUsers.values.last
          : _chatProviderText(
              zhCN: '有人',
              zhTW: '有人',
              en: 'Someone',
            );
      next[chatId] = _chatProviderText(
        zhCN: '$latestName 正在输入...',
        zhTW: '$latestName 正在輸入...',
        en: '$latestName is typing...',
      );
    }

    _safeSetState((s) => s.copyWith(typingByChat: next));
  }

  void _clearTypingForChat(String chatId) {
    _typingUsersByChat.remove(chatId);
    final prefix = '$chatId:';
    final keysToRemove =
        _typingTimers.keys.where((k) => k.startsWith(prefix)).toList();
    for (final key in keysToRemove) {
      _typingTimers[key]?.cancel();
      _typingTimers.remove(key);
    }

    if (state.typingByChat.containsKey(chatId)) {
      final next = Map<String, String>.from(state.typingByChat)..remove(chatId);
      _safeSetState((s) => s.copyWith(typingByChat: next));
    }
  }

  void _clearAllTyping() {
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    _typingUsersByChat.clear();
    _safeSetState((s) => s.copyWith(typingByChat: const {}));
  }

  /// 处理消息编辑 - 更新聊天列表最后消息预览
  void _handleMessageEdited(
    String chatId,
    String newContent, {
    String? msgId,
    int? msgSeq,
    MessageContentType? lastMessageType,
  }) {
    final chat = _findChatById(chatId);
    if (chat == null) return;
    // 若有 seq 信息，仅当编辑的是最后一条消息时才更新预览
    if (msgSeq != null && msgSeq > 0) {
      if (chat.lastMessageSeq != msgSeq) return;
    }
    // 只更新文本类型的预览（图片/视频等类型不受编辑影响）
    if (chat.lastMessageType == null ||
        chat.lastMessageType == MessageContentType.text) {
      updateChat(
        chat.copyWith(
          lastMessage: _previewText(newContent),
          lastMessageType: lastMessageType ?? chat.lastMessageType,
          lastMessageMediaUrl: null,
          lastMessageFailed: false,
        ),
      );
    }
  }

  MessageContentType? _previewTypeForRawMessage(int type) {
    switch (type) {
      case 2:
        return MessageContentType.photo;
      case 3:
        return MessageContentType.video;
      case 4:
        return MessageContentType.voice;
      case 5:
        return MessageContentType.file;
      case 6:
        return MessageContentType.location;
      case 8:
        return MessageContentType.sticker;
      case 10:
        return MessageContentType.contact;
      case 11:
        return MessageContentType.call;
      default:
        return MessageContentType.text;
    }
  }

  String _normalizeServerChatPreview(String? text, int? rawType) {
    final value = (text ?? '').trim();
    if (looksLikeServerSystemPreviewText(value)) {
      return resolveServerPreviewText(
        value,
        currentUserId: _getCurrentUserId(),
      );
    }
    switch (rawType) {
      case 2:
        return _chatPreviewLabel('photo');
      case 3:
        return _chatPreviewLabel('video');
      case 4:
        return _chatPreviewLabel('voice');
      case 5:
        return _chatPreviewLabel('file');
      case 6:
        return _chatPreviewLabel('location');
      case 8:
        return _chatPreviewLabel('sticker');
      case 10:
        return _chatPreviewLabel('contact');
      case 11:
        return value.isNotEmpty
            ? _localizedCallPreview(value)
            : _chatPreviewLabel('call');
      case 12:
        return _chatPreviewLabel('red_packet');
      case 13:
        return _chatPreviewLabel('transfer');
      case 99:
        return resolveSystemMessageText(
          value,
          currentUserId: _getCurrentUserId(),
        );
      default:
        return value;
    }
  }

  String _normalizeStoredChatPreview(String? text, storage.MessageType type) {
    final value = (text ?? '').trim();
    if (looksLikeServerSystemPreviewText(value)) {
      return resolveServerPreviewText(
        value,
        currentUserId: _getCurrentUserId(),
      );
    }
    switch (type) {
      case storage.MessageType.image:
        return _chatPreviewLabel('photo');
      case storage.MessageType.video:
        return _chatPreviewLabel('video');
      case storage.MessageType.voice:
      case storage.MessageType.audio:
        return _chatPreviewLabel('voice');
      case storage.MessageType.file:
        return _chatPreviewLabel('file');
      case storage.MessageType.sticker:
        return _chatPreviewLabel('sticker');
      case storage.MessageType.location:
        return _chatPreviewLabel('location');
      case storage.MessageType.contact:
        return _chatPreviewLabel('contact');
      case storage.MessageType.call:
        return value.isNotEmpty
            ? _localizedCallPreview(value)
            : _chatPreviewLabel('call');
      case storage.MessageType.system:
        return resolveSystemMessageText(
          value,
          currentUserId: _getCurrentUserId(),
        );
      case storage.MessageType.text:
        return value;
    }
  }

  String _previewText(String? text, {bool burnAfterRead = false}) {
    if (burnAfterRead) {
      return _burnAfterReadPreviewText;
    }
    if ((text ?? '').startsWith(EmojiStoreService.builtInStickerSendPrefix)) {
      return _chatPreviewLabel('sticker');
    }
    return text ?? '';
  }

  (String, MessageContentType?) _previewForMessage(api.Message message) {
    if (message.burnAfterRead) {
      return (
        _burnAfterReadPreviewText,
        _previewTypeForRawMessage(message.type),
      );
    }
    switch (message.type) {
      case 2:
        return (_chatPreviewLabel('photo'), MessageContentType.photo);
      case 3:
        return (_chatPreviewLabel('video'), MessageContentType.video);
      case 4:
        return (_chatPreviewLabel('voice'), MessageContentType.voice);
      case 5:
        return (_chatPreviewLabel('file'), MessageContentType.file);
      case 6:
        return (_chatPreviewLabel('location'), MessageContentType.location);
      case 8:
        return (_chatPreviewLabel('sticker'), MessageContentType.sticker);
      case 10:
        return (_chatPreviewLabel('contact'), MessageContentType.contact);
      case 11:
        return (
          _localizedCallPreview(
            message.content.text,
            callType: message.content.callType,
            status: message.content.callStatus,
            duration: message.content.callDuration,
            isOutgoing: message.senderId == _getCurrentUserId(),
          ),
          MessageContentType.call,
        );
      case 12:
        return (_chatPreviewLabel('red_packet'), MessageContentType.text);
      case 13:
        return (_chatPreviewLabel('transfer'), MessageContentType.text);
      case 99:
        return (
          resolveSystemMessageText(
            message.content.text ?? '',
            currentUserId: _getCurrentUserId(),
          ),
          MessageContentType.text,
        );
      default:
        return (
          message.content.text ?? _chatPreviewLabel('message'),
          MessageContentType.text,
        );
    }
  }

  String? _previewMediaUrlForMessage(api.Message message) {
    if (message.burnAfterRead) return null;
    switch (message.type) {
      case 2:
      case 3:
        final media = message.content.media;
        if (media == null) return null;
        final source =
            (media.thumbnail?.isNotEmpty == true) ? media.thumbnail : media.url;
        final url = ApiConfig.getMediaUrl(source);
        return url.isEmpty ? null : url;
      case 8:
        final sticker = message.content.sticker;
        if (sticker == null) return null;
        final url = EmojiStoreService.resolveStickerDisplayPath(sticker.url);
        return url.isEmpty ? null : url;
      default:
        return null;
    }
  }

  /// 处理新消息
  void _queueNewMessage(api.Message message) {
    if (_isDisposed) return;
    if (!_rememberMessageId(message.msgId)) {
      debugPrint('[Chat] Skip duplicate new_message: ${message.msgId}');
      return;
    }
    final key = message.msgId.isNotEmpty
        ? message.msgId
        : '${message.chatId}:${message.seq}:${message.senderId}';
    _pendingChatListMessages[key] = message;
    _chatListMessageBatchTimer ??= Timer(
      _chatListMessageBatchDelay,
      _flushNewMessageBatch,
    );
  }

  void _flushNewMessageBatch() {
    _chatListMessageBatchTimer = null;
    if (_isDisposed || _pendingChatListMessages.isEmpty) return;
    final messages = _pendingChatListMessages.values.toList(growable: false);
    _pendingChatListMessages.clear();
    _applyNewMessageBatch(messages);
  }

  void _handleNewMessage(api.Message message) {
    if (!_rememberMessageId(message.msgId)) {
      debugPrint('[Chat] Skip duplicate new_message: ${message.msgId}');
      return;
    }
    _applyNewMessageBatch(<api.Message>[message]);
  }

  void _applyNewMessageBatch(List<api.Message> messages) {
    if (_isDisposed || messages.isEmpty) return;

    final grouped = <String, List<api.Message>>{};
    for (final message in messages) {
      grouped.putIfAbsent(message.chatId, () => <api.Message>[]).add(message);
    }

    final updates = <String, ChatItem>{};
    final notificationMessages = <String, api.Message>{};
    var shouldRefreshMissingChat = false;

    for (final entry in grouped.entries) {
      final chat = _findChatById(entry.key);
      if (chat == null) {
        shouldRefreshMissingChat = true;
        continue;
      }

      final batch = entry.value
        ..sort((a, b) {
          if (a.seq > 0 && b.seq > 0 && a.seq != b.seq) {
            return a.seq.compareTo(b.seq);
          }
          return a.createdAt.compareTo(b.createdAt);
        });
      final message = batch.last;

      _clearTypingForChat(message.chatId);
      final activeChatMatches = _activeChatId == message.chatId;
      final isViewing = shouldTreatActiveChatAsVisible(
        activeChatMatches: activeChatMatches,
        lifecycleState: WidgetsBinding.instance.lifecycleState,
      );
      final currentUserId = _getCurrentUserId() ?? '';
      var unreadDelta = 0;
      var mentionsMe = false;
      for (final candidate in batch) {
        final isSelf = candidate.senderId == currentUserId;
        final isSystemMsg = candidate.type == 99;
        if (!isSelf && !isViewing && !isSystemMsg) {
          unreadDelta++;
          if (currentUserId.isNotEmpty &&
              ((candidate.mentions?.contains(currentUserId) ?? false) ||
                  (candidate.mentions?.contains('__all__') ?? false))) {
            mentionsMe = true;
          }
          notificationMessages[entry.key] = candidate;
        }
      }

      final preview = _previewForMessage(message);
      final updatedChat = chat.copyWith(
        lastMessage: preview.$1,
        lastMessageTime: message.createdAt,
        lastMessageSender: _normalizePreviewSenderName(message.senderName),
        lastMessageType: preview.$2,
        lastMessageMediaUrl: _previewMediaUrlForMessage(message),
        unreadCount: chat.unreadCount + unreadDelta,
        lastMessageSeq: message.seq,
        hasMention: mentionsMe ? true : chat.hasMention,
        lastMessageFailed: false,
      );
      updates[entry.key] = updatedChat;
    }

    if (updates.isNotEmpty) {
      final updatedIDs = updates.keys.toSet();
      final updatedPinned =
          updates.values.where((chat) => chat.isPinned).toList()
            ..sort((a, b) => (b.lastMessageTime ?? DateTime(1970)).compareTo(
                  a.lastMessageTime ?? DateTime(1970),
                ));
      final updatedRegular =
          updates.values.where((chat) => !chat.isPinned).toList()
            ..sort((a, b) => (b.lastMessageTime ?? DateTime(1970)).compareTo(
                  a.lastMessageTime ?? DateTime(1970),
                ));
      state = state.copyWith(
        pinnedChats: <ChatItem>[
          ...updatedPinned,
          ...state.pinnedChats.where((chat) => !updatedIDs.contains(chat.id)),
        ],
        regularChats: <ChatItem>[
          ...updatedRegular,
          ...state.regularChats.where((chat) => !updatedIDs.contains(chat.id)),
        ],
      );
      _updateChatsInCache(updates.values);
    }

    for (final entry in notificationMessages.entries) {
      final chat = updates[entry.key];
      if (chat == null || chat.isMuted) continue;
      final message = entry.value;
      final preview = _previewForMessage(message);
      final senderName = _normalizePreviewSenderName(message.senderName) ??
          _chatProviderText(
            zhCN: '未知',
            zhTW: '未知',
            en: 'Unknown',
          );
      _playNotificationSound(chat.type);
      _showAndroidMessageNotification(
        chat: chat,
        messageId: message.msgId,
        senderName: senderName,
        content: preview.$1,
        unreadCount: _totalUnreadCount(),
        activeChatMatches: _activeChatId == message.chatId,
      );
      _showDesktopNotification(
        chat: chat,
        senderName: senderName,
        content: preview.$1,
      );
    }

    if (shouldRefreshMissingChat) {
      unawaited(loadFromServer());
    }
  }

  bool _rememberMessageId(String msgId) {
    if (msgId.isEmpty) return true;
    if (_recentMessageIds.contains(msgId)) return false;

    _recentMessageIds.add(msgId);
    _recentMessageIdOrder.add(msgId);
    while (_recentMessageIdOrder.length > _recentMessageIdLimit) {
      final removed = _recentMessageIdOrder.removeAt(0);
      _recentMessageIds.remove(removed);
    }
    return true;
  }

  /// 获取当前用户ID
  String? _getCurrentUserId() {
    return _accountId.isEmpty ? null : _accountId;
  }

  int _totalUnreadCount() {
    var total = 0;
    for (final chat in state.pinnedChats) {
      total += chat.unreadCount;
    }
    for (final chat in state.regularChats) {
      total += chat.unreadCount;
    }
    return total;
  }

  List<String> _subscriptionChatIds(List<ChatItem> chats, {int? limit}) {
    if (chats.isEmpty) return const [];

    final ordered = [...chats];
    ordered.sort((a, b) {
      final aPriority = (a.unreadCount > 0 ? 2 : 0) + (a.isPinned ? 1 : 0);
      final bPriority = (b.unreadCount > 0 ? 2 : 0) + (b.isPinned ? 1 : 0);
      if (aPriority != bPriority) return bPriority.compareTo(aPriority);
      return (b.lastMessageTime ?? DateTime(1970)).compareTo(
        a.lastMessageTime ?? DateTime(1970),
      );
    });

    final seen = <String>{};
    final ids = ordered
        .where((chat) => seen.add(chat.id))
        .map((chat) => chat.id)
        .toList();
    return limit == null ? ids : ids.take(limit).toList();
  }

  /// 播放通知音效
  void _scheduleHotChatPrewarm(
    List<ChatItem> chats, {
    required String reason,
  }) {
    if (_isDisposed || chats.isEmpty || _hotPrewarmRunning) return;
    final now = DateTime.now();
    if (_lastHotPrewarmTime != null &&
        now.difference(_lastHotPrewarmTime!) < const Duration(seconds: 30)) {
      return;
    }
    _lastHotPrewarmTime = now;
    final snapshot = List<ChatItem>.of(chats);
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 900), () {
        return _prewarmHotChats(snapshot, reason: reason);
      }),
    );
  }

  Future<void> _prewarmHotChats(
    List<ChatItem> chats, {
    required String reason,
  }) async {
    if (_isDisposed || _hotPrewarmRunning) return;
    final accountId = _getCurrentUserId();
    if (accountId == null || accountId.isEmpty) return;

    _hotPrewarmRunning = true;
    final span = PerformanceTraceService.start('chat.hot_prewarm');
    var warmed = 0;
    try {
      final priorityIds = _subscriptionChatIds(chats, limit: 8).toSet();
      final targets = chats
          .where(
            (chat) => chat.id != _activeChatId && priorityIds.contains(chat.id),
          )
          .take(5)
          .toList();

      for (final chat in targets) {
        if (_isDisposed) break;
        try {
          final maxSeq = await _cachedMaxSeqForHotChat(accountId, chat.id);
          if (chat.lastMessageSeq > 0 && maxSeq >= chat.lastMessageSeq) {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            continue;
          }
          if (maxSeq == 0 && chat.unreadCount == 0 && reason != 'load') {
            await Future<void>.delayed(const Duration(milliseconds: 40));
            continue;
          }
          final response = maxSeq > 0
              ? await _chatService.syncMessages(chat.id, lastSeq: maxSeq)
              : await _chatService.getMessages(chat.id, limit: 20);
          if (!response.isSuccess ||
              response.data == null ||
              response.data!.isEmpty) {
            await Future<void>.delayed(const Duration(milliseconds: 80));
            continue;
          }
          final items = response.data!
              .map((msg) => MessageItem.fromApiMessage(msg, accountId))
              .toList();
          await _persistHotChatMessages(accountId, chat.id, items);
          MessageMemoryWindowCache.write(
            accountId: accountId,
            chatId: chat.id,
            messages: items,
          );
          warmed++;
        } catch (e) {
          debugPrint('[Chat] Hot prewarm failed for ${chat.id}: $e');
        }
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    } finally {
      _hotPrewarmRunning = false;
      span.finish('reason=$reason warmed=$warmed');
    }
  }

  Future<int> _cachedMaxSeqForHotChat(String accountId, String chatId) async {
    if (PlatformUtils.isWeb) {
      return readWebMessageWindowMaxSeq(accountId: accountId, chatId: chatId);
    }
    if (!IsarService.instance.isAvailable) return 0;
    final last = await IsarService.instance.isar.messageModels
        .filter()
        .accountIdEqualTo(accountId)
        .chatIdEqualTo(chatId)
        .sortBySeqDesc()
        .findFirst();
    return last?.seq ?? 0;
  }

  Future<void> _persistHotChatMessages(
    String accountId,
    String chatId,
    List<MessageItem> items,
  ) async {
    if (items.isEmpty) return;
    if (PlatformUtils.isWeb) {
      await persistMessageItemsToWebWindowCache(
        items,
        accountId: accountId,
        chatId: chatId,
      );
      return;
    }
    await persistMessageItemsToIsarCache(items, accountId: accountId);
  }

  void _playNotificationSound(ChatItemType type) {
    try {
      final soundService = _ref.read(notificationSoundServiceProvider.notifier);
      NotificationType notificationType;

      switch (type) {
        case ChatItemType.private:
          notificationType = NotificationType.privateMessage;
          break;
        case ChatItemType.group:
          notificationType = NotificationType.groupMessage;
          break;
        case ChatItemType.channel:
          notificationType = NotificationType.channelMessage;
          break;
      }

      soundService.playNotification(notificationType, isInApp: true).catchError(
        (e) {
          debugPrint('[Chat] Play notification sound async error: $e');
        },
      );
    } catch (e) {
      debugPrint('[Chat] Play notification sound failed: $e');
    }
  }

  void _showAndroidMessageNotification({
    required ChatItem chat,
    required String messageId,
    required String senderName,
    required String content,
    required int unreadCount,
    required bool activeChatMatches,
  }) {
    if (!PlatformUtils.isAndroid) return;

    try {
      if (_shouldUseRemotePushForAndroidNotification()) {
        BackgroundService.instance.updateNotification(
          unreadCount: unreadCount,
        );
        return;
      }

      final soundService = _ref.read(notificationSoundServiceProvider.notifier);
      final notificationType = switch (chat.type) {
        ChatItemType.private => NotificationType.privateMessage,
        ChatItemType.group => NotificationType.groupMessage,
        ChatItemType.channel => NotificationType.channelMessage,
      };
      if (!soundService.shouldShowNotification(notificationType)) return;
      final showPreview = soundService.shouldShowPreview();

      String title;
      String body;

      switch (chat.type) {
        case ChatItemType.private:
          title = chat.name;
          body = showPreview
              ? content
              : _chatProviderText(
                  zhCN: '您收到一条新消息',
                  zhTW: '您收到一則新訊息',
                  en: 'You received a new message',
                );
          break;
        case ChatItemType.group:
          title = chat.name;
          body = showPreview
              ? '$senderName: $content'
              : _chatProviderText(
                  zhCN: '您收到一条群消息',
                  zhTW: '您收到一則群組訊息',
                  en: 'You received a new group message',
                );
          break;
        case ChatItemType.channel:
          title = chat.name;
          body = showPreview
              ? content
              : _chatProviderText(
                  zhCN: '频道有新消息',
                  zhTW: '頻道有新訊息',
                  en: 'There is a new channel message',
                );
          break;
      }

      final privacyText = messageNotificationPrivacyText(
        showPreview: showPreview,
        title: title,
        body: body,
      );

      unawaited(
        AndroidMessageNotificationService.instance
            .showMessageNotification(
          chatId: chat.id,
          messageId: messageId,
          title: privacyText.title,
          body: privacyText.body,
          unreadCount: unreadCount,
          activeChatMatches: activeChatMatches,
        )
            .catchError((Object error) {
          debugPrint(
              '[ChatProvider] Show Android message notification failed: $error');
        }),
      );

      BackgroundService.instance.updateNotification(
        unreadCount: unreadCount,
      );
    } catch (e) {
      debugPrint('[ChatProvider] Android message notification error: $e');
    }
  }

  /// 显示桌面端通知
  bool _shouldUseRemotePushForAndroidNotification() {
    if (!PlatformUtils.isAndroid) {
      return false;
    }
    try {
      final pushService = _ref.read(pushNotificationServiceProvider);
      return pushService.isRegistered &&
          (pushService.deviceToken?.isNotEmpty ?? false) &&
          pushService.pushChannel.isNotEmpty &&
          pushService.pushChannel != 'unknown';
    } catch (_) {
      return false;
    }
  }

  void _showDesktopNotification({
    required ChatItem chat,
    required String senderName,
    required String content,
  }) {
    if (!DesktopNotificationService.isDesktop) return;

    try {
      final soundService = _ref.read(notificationSoundServiceProvider.notifier);
      final showPreview = soundService.shouldShowPreview();

      String title;
      String body;

      switch (chat.type) {
        case ChatItemType.private:
          title = chat.name;
          body = showPreview
              ? content
              : _chatProviderText(
                  zhCN: '您收到一条新消息',
                  zhTW: '您收到一則新訊息',
                  en: 'You received a new message',
                );
          break;
        case ChatItemType.group:
          title = chat.name;
          body = showPreview
              ? '$senderName: $content'
              : _chatProviderText(
                  zhCN: '您收到一条群消息',
                  zhTW: '您收到一則群組訊息',
                  en: 'You received a new group message',
                );
          break;
        case ChatItemType.channel:
          title = chat.name;
          body = showPreview
              ? content
              : _chatProviderText(
                  zhCN: '频道有新消息',
                  zhTW: '頻道有新訊息',
                  en: 'There is a new channel message',
                );
          break;
      }

      DesktopNotificationService().showMessageNotification(
        title: title,
        body: body,
        payload: chat.id,
      );
    } catch (e) {
      debugPrint('[ChatProvider] Desktop notification error: $e');
    }
  }

  /// 处理新会话
  void _handleNewChat(dynamic data) {
    // 后端发送格式: { type: "new_chat", message: { id, type, name, avatar, ... } }
    final message = data['message'] as Map<String, dynamic>?;
    if (message == null) return;

    final chatId = message['id'] as String?;
    final chatType = message['type'] as int? ?? 1;
    final name = message['name'] as String? ??
        _chatProviderText(zhCN: '未知', zhTW: '未知', en: 'Unknown');
    final rawAvatar = message['avatar'] as String?;
    final username = message['username']?.toString();
    // 转换头像 URL
    final avatar = rawAvatar != null && rawAvatar.isNotEmpty
        ? ApiConfig.getMediaUrl(rawAvatar)
        : rawAvatar;

    if (chatId == null) return;

    debugPrint(
      '[Chat] Received new_chat notification: $chatId, name: $name, type: $chatType',
    );

    // 检查是否已存在
    if (_findChatById(chatId) != null) {
      debugPrint('[Chat] Chat already exists, skipping');
      return;
    }

    // 添加新聊天到列表
    final chat = ChatItem(
      id: chatId,
      name: name,
      avatar: avatar,
      type: chatType == 1
          ? ChatItemType.private
          : chatType == 2
              ? ChatItemType.group
              : ChatItemType.channel,
      username: username,
      createdAt: DateTime.now(),
    );

    if (_isDisposed) return;
    state = state.copyWith(regularChats: [chat, ...state.regularChats]);

    debugPrint('[Chat] Added new chat to list');
  }

  /// 移动聊天到列表顶部
  void _moveToTop(ChatItem chat) {
    if (_isDisposed) return;
    if (chat.isPinned) {
      final others = state.pinnedChats.where((c) => c.id != chat.id).toList();
      state = state.copyWith(pinnedChats: [chat, ...others]);
    } else {
      final pinnedWithout =
          state.pinnedChats.where((c) => c.id != chat.id).toList();
      final regularWithout =
          state.regularChats.where((c) => c.id != chat.id).toList();
      state = state.copyWith(
        pinnedChats: pinnedWithout,
        regularChats: [chat, ...regularWithout],
      );
    }

    // 异步更新 Isar 缓存（不阻塞 UI）
    _updateChatInCache(chat);
  }

  /// 异步更新单个聊天到 Isar 缓存
  void _updateChatInCache(ChatItem chat) {
    if (PlatformUtils.isWeb) {
      unawaited(
        _saveChatListToWebCache([...state.pinnedChats, ...state.regularChats]),
      );
      return;
    }
    final accountId = _getCurrentUserId();
    if (accountId == null || accountId.isEmpty) return;

    Future.microtask(() async {
      if (_isDisposed) return;
      try {
        final model = _itemToChatModel(chat);
        await IsarService.instance.isar.writeTxn(() async {
          await IsarService.instance.isar.chatModels.put(model);
        });
      } catch (e) {
        debugPrint('[Chat] Failed to update chat in cache: $e');
      }
    });
  }

  /// Persists one realtime batch in one transaction instead of opening an
  /// Isar transaction for every message in a burst.
  void _updateChatsInCache(Iterable<ChatItem> chats) {
    final snapshot = chats.toList(growable: false);
    if (snapshot.isEmpty) return;
    if (PlatformUtils.isWeb) {
      unawaited(
        _saveChatListToWebCache([...state.pinnedChats, ...state.regularChats]),
      );
      return;
    }
    final accountId = _getCurrentUserId();
    if (accountId == null || accountId.isEmpty) return;

    Future.microtask(() async {
      if (_isDisposed) return;
      try {
        final models = snapshot.map(_itemToChatModel).toList(growable: false);
        await IsarService.instance.isar.writeTxn(() async {
          await IsarService.instance.isar.chatModels.putAll(models);
        });
      } catch (e) {
        debugPrint('[Chat] Failed to update chat batch in cache: $e');
      }
    });
  }

  /// 初始化 - 从服务器加载聊天列表
  Future<void> initialize() async {
    if (_accountId.isEmpty || _isDisposed) return;
    if (state.isInitialized) return;
    // 初始化 Future 复用同一轮缓存和网络加载，避免多个页面同时监听时重复覆盖列表。
    final activeInitialize = _initializeFuture;
    if (activeInitialize != null) {
      await activeInitialize;
      return;
    }
    PerformanceTraceService.mark('chat.initialize_start');
    final future = loadFromServer();
    _initializeFuture = future;
    try {
      await future;
    } finally {
      if (identical(_initializeFuture, future)) {
        _initializeFuture = null;
      }
    }
  }

  String? get _chatListWebCacheKey {
    final accountId = _getCurrentUserId();
    if (accountId == null || accountId.isEmpty) return null;
    return 'chat_window_$accountId';
  }

  Map<String, dynamic> _chatItemToCacheJson(ChatItem chat) {
    return {
      'id': chat.id,
      'name': chat.name,
      'avatar': chat.avatar,
      'last_message': chat.lastMessage,
      'last_message_time': chat.lastMessageTime?.toIso8601String(),
      'unread_count': chat.unreadCount,
      'is_pinned': chat.isPinned,
      'is_muted': chat.isMuted,
      'pending_join_request_count': chat.pendingJoinRequestCount,
      'has_pending_join_requests': chat.hasPendingJoinRequests,
      'type': chat.type.name,
      'draft': chat.draft,
      'last_message_sender': chat.lastMessageSender,
      'last_message_type': chat.lastMessageType?.name,
      'last_message_media_url': chat.lastMessageMediaUrl,
      'is_sent_by_me': chat.isSentByMe,
      'is_read': chat.isRead,
      'member_ids': chat.memberIds,
      'description': chat.description,
      'created_at': chat.createdAt.toIso8601String(),
      'target_user_id': chat.targetUserId,
      'target_user_uuid': chat.targetUserUuid,
      'username': chat.username,
      'real_member_count': chat.memberCount,
      'emoji_avatar': chat.emojiAvatar,
      'nickname_color': chat.nicknameColor,
      'last_message_seq': chat.lastMessageSeq,
      'has_mention': chat.hasMention,
      'last_message_failed': chat.lastMessageFailed,
      'status': chat.status,
    };
  }

  ChatItem? _chatItemFromCacheJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final id = json['id']?.toString() ?? '';
    if (id.isEmpty) return null;

    DateTime? parseTime(Object? value) {
      final text = value?.toString();
      if (text == null || text.isEmpty) return null;
      return DateTime.tryParse(text);
    }

    T enumByName<T extends Enum>(
      List<T> values,
      Object? rawValue,
      T fallback,
    ) {
      final name = rawValue?.toString();
      for (final value in values) {
        if (value.name == name) return value;
      }
      return fallback;
    }

    final type = enumByName(
      ChatItemType.values,
      json['type'],
      ChatItemType.private,
    );
    final lastType = json['last_message_type'] == null
        ? null
        : enumByName(
            MessageContentType.values,
            json['last_message_type'],
            MessageContentType.text,
          );

    return ChatItem(
      id: id,
      name: json['name']?.toString() ?? '',
      avatar: json['avatar']?.toString(),
      lastMessage: json['last_message']?.toString(),
      lastMessageTime: parseTime(json['last_message_time']),
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
      isPinned: json['is_pinned'] == true,
      isMuted: json['is_muted'] == true,
      type: type,
      pendingJoinRequestCount:
          (json['pending_join_request_count'] as num?)?.toInt() ?? 0,
      hasPendingJoinRequests: json['has_pending_join_requests'] == true,
      draft: json['draft']?.toString(),
      lastMessageSender: _normalizePreviewSenderName(
        json['last_message_sender']?.toString(),
      ),
      lastMessageType: lastType,
      lastMessageMediaUrl: json['last_message_media_url']?.toString(),
      isSentByMe: json['is_sent_by_me'] == true,
      isRead: json['is_read'] == true,
      memberIds: (json['member_ids'] as List?)
              ?.map((value) => value.toString())
              .toList() ??
          const [],
      description: json['description']?.toString(),
      createdAt: parseTime(json['created_at']) ?? DateTime.now(),
      targetUserId: json['target_user_id']?.toString(),
      targetUserUuid: json['target_user_uuid']?.toString(),
      username: json['username']?.toString(),
      realMemberCount: (json['real_member_count'] as num?)?.toInt() ?? 0,
      emojiAvatar: json['emoji_avatar']?.toString(),
      nicknameColor: json['nickname_color']?.toString(),
      lastMessageSeq: (json['last_message_seq'] as num?)?.toInt() ?? 0,
      hasMention: json['has_mention'] == true,
      lastMessageFailed: json['last_message_failed'] == true,
      status: (json['status'] as num?)?.toInt() ?? 0,
    );
  }

  Future<bool> _loadChatListFromWebCache() async {
    final key = _chatListWebCacheKey;
    if (key == null) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return false;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return false;
      final seenIds = <String>{};
      final items = decoded
          .map(_chatItemFromCacheJson)
          .whereType<ChatItem>()
          .where((chat) => seenIds.add(chat.id))
          .toList();
      if (items.isEmpty || _isDisposed) return false;

      final pinned = items.where((c) => c.isPinned).toList()
        ..sort(
          (a, b) => (b.lastMessageTime ?? DateTime(1970)).compareTo(
            a.lastMessageTime ?? DateTime(1970),
          ),
        );
      final regular = items.where((c) => !c.isPinned).toList()
        ..sort(
          (a, b) => (b.lastMessageTime ?? DateTime(1970)).compareTo(
            a.lastMessageTime ?? DateTime(1970),
          ),
        );

      state = state.copyWith(
        pinnedChats: pinned,
        regularChats: regular,
        isInitialized: true,
      );
      return true;
    } catch (e) {
      debugPrint('[Chat] Failed to load web chat cache: $e');
      return false;
    }
  }

  Future<void> _saveChatListToWebCache(List<ChatItem> chats) async {
    final key = _chatListWebCacheKey;
    if (key == null) return;

    try {
      final ordered = [...chats]..sort(
          (a, b) => (b.lastMessageTime ?? DateTime(1970)).compareTo(
            a.lastMessageTime ?? DateTime(1970),
          ),
        );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode(ordered.take(100).map(_chatItemToCacheJson).toList()),
      );
    } catch (e) {
      debugPrint('[Chat] Failed to save web chat cache: $e');
    }
  }

  /// 从本地 Isar 读取聊天列表缓存，先展示再请求服务器
  Future<bool> _loadChatListFromCache() async {
    final span = PerformanceTraceService.start('chat.load_cache');
    if (PlatformUtils.isWeb) {
      final hit = await _loadChatListFromWebCache();
      span.finish(hit ? 'web_hit' : 'web_miss');
      return hit;
    }

    final accountId = _getCurrentUserId();
    if (accountId == null || accountId.isEmpty) {
      span.finish('missing_account');
      return false;
    }
    if (!IsarService.instance.isAvailable) {
      final hit = await _loadChatListFromWebCache();
      span.finish(hit ? 'prefs_hit_isar_unavailable' : 'isar_unavailable');
      return hit;
    }

    try {
      // 限制查询数量，避免大量数据导致性能问题
      final list = await IsarService.instance.isar.chatModels
          .filter()
          .accountIdEqualTo(accountId)
          .sortByLastMessageTimeDesc()
          .limit(200)
          .findAll();
      if (list.isEmpty || _isDisposed) {
        span.finish('miss');
        return false;
      }
      // 去重：使用 Set 确保每个 chatId 只出现一次
      final seenIds = <String>{};
      final items = list
          .map(_chatModelToItem)
          .where((chat) => seenIds.add(chat.id))
          .toList();
      final pinned = items.where((c) => c.isPinned).toList();
      final regular = items.where((c) => !c.isPinned).toList();

      // 确保按最后消息时间降序排序
      pinned.sort(
        (a, b) => (b.lastMessageTime ?? DateTime(1970)).compareTo(
          a.lastMessageTime ?? DateTime(1970),
        ),
      );
      regular.sort(
        (a, b) => (b.lastMessageTime ?? DateTime(1970)).compareTo(
          a.lastMessageTime ?? DateTime(1970),
        ),
      );

      if (!_isDisposed) {
        state = state.copyWith(
          pinnedChats: pinned,
          regularChats: regular,
          isInitialized: true,
        );
      }
      span.finish('hit count=${items.length}');
      return true;
    } catch (e) {
      debugPrint('[Chat] Failed to load from cache: $e');
      span.finish('error');
      return false;
    }
  }

  ChatItem _chatModelToItem(storage.ChatModel m) {
    final type = m.type == storage.ChatType.private
        ? ChatItemType.private
        : m.type == storage.ChatType.group
            ? ChatItemType.group
            : ChatItemType.channel;
    MessageContentType? lastMsgType;
    switch (m.lastMessageType) {
      case storage.MessageType.text:
        lastMsgType = MessageContentType.text;
        break;
      case storage.MessageType.image:
        lastMsgType = MessageContentType.photo;
        break;
      case storage.MessageType.video:
        lastMsgType = MessageContentType.video;
        break;
      case storage.MessageType.voice:
        lastMsgType = MessageContentType.voice;
        break;
      case storage.MessageType.file:
        lastMsgType = MessageContentType.file;
        break;
      case storage.MessageType.sticker:
        lastMsgType = MessageContentType.sticker;
        break;
      case storage.MessageType.location:
        lastMsgType = MessageContentType.location;
        break;
      case storage.MessageType.contact:
        lastMsgType = MessageContentType.contact;
        break;
      case storage.MessageType.system:
        lastMsgType = MessageContentType.text;
        break;
      case storage.MessageType.call:
        lastMsgType = MessageContentType.call;
        break;
      default:
        lastMsgType = MessageContentType.text;
    }
    return ChatItem(
      id: m.id,
      name: m.name,
      avatar: m.avatar,
      lastMessage: _normalizeStoredChatPreview(
        m.lastMessage,
        m.lastMessageType,
      ),
      lastMessageTime: _normalizeChatListTime(m.lastMessageTime),
      unreadCount: m.unreadCount,
      isPinned: m.isPinned,
      isMuted: m.isMuted,
      type: type,
      pendingJoinRequestCount: 0,
      hasPendingJoinRequests: false,
      draft: m.draft,
      lastMessageSender: _normalizePreviewSenderName(m.lastMessageSender),
      lastMessageType: lastMsgType,
      lastMessageMediaUrl: m.lastMessageMediaUrl,
      createdAt: m.createdAt,
      targetUserId: m.peerUserId,
      realMemberCount: m.memberCount ?? 0,
      lastMessageSeq: m.lastMessageSeq,
      hasMention: m.hasMention,
      lastMessageFailed: m.lastMessageFailed,
    );
  }

  storage.ChatModel _itemToChatModel(ChatItem c) {
    final type = c.type == ChatItemType.private
        ? storage.ChatType.private
        : c.type == ChatItemType.group
            ? storage.ChatType.group
            : storage.ChatType.channel;
    storage.MessageType lastMsgType = storage.MessageType.text;
    if (c.lastMessageType != null) {
      switch (c.lastMessageType!) {
        case MessageContentType.photo:
          lastMsgType = storage.MessageType.image;
          break;
        case MessageContentType.video:
          lastMsgType = storage.MessageType.video;
          break;
        case MessageContentType.voice:
          lastMsgType = storage.MessageType.voice;
          break;
        case MessageContentType.file:
          lastMsgType = storage.MessageType.file;
          break;
        case MessageContentType.sticker:
          lastMsgType = storage.MessageType.sticker;
          break;
        case MessageContentType.location:
          lastMsgType = storage.MessageType.location;
          break;
        case MessageContentType.contact:
          lastMsgType = storage.MessageType.contact;
          break;
        case MessageContentType.call:
          lastMsgType = storage.MessageType.call;
          break;
        default:
          lastMsgType = storage.MessageType.text;
      }
    }
    final now = DateTime.now();
    final accountId = _getCurrentUserId() ?? '';
    return storage.ChatModel()
      ..accountId = accountId
      ..id = c.id
      ..type = type
      ..name = c.name
      ..avatar = c.avatar
      ..lastMessage = c.lastMessage
      ..lastMessageType = lastMsgType
      ..lastMessageSender = c.lastMessageSender
      ..lastMessageMediaUrl = c.lastMessageMediaUrl
      ..lastMessageTime = _normalizeChatListTime(c.lastMessageTime)
      ..unreadCount = c.unreadCount
      ..hasMention = c.hasMention
      ..lastMessageFailed = c.lastMessageFailed
      ..isMuted = c.isMuted
      ..isPinned = c.isPinned
      ..isArchived = false
      ..draft = c.draft
      ..memberCount = c.memberCount > 0 ? c.memberCount : null
      ..peerUserId = c.targetUserId
      ..lastMessageSeq = c.lastMessageSeq
      ..lastSyncedSeq = 0
      ..lastSyncedAt = null
      ..hasMessageGap = false
      ..createdAt = c.createdAt
      ..updatedAt = now;
  }

  // 防抖：记录上次请求时间，避免短时间内重复请求
  DateTime? _lastLoadTime;
  static const _minLoadInterval = Duration(milliseconds: 500);

  /// 从服务器加载聊天列表
  Future<void> loadFromServer() async {
    if (_accountId.isEmpty || _isDisposed) return;

    // 防抖：500ms 内不重复请求
    final now = DateTime.now();
    if (_lastLoadTime != null &&
        now.difference(_lastLoadTime!) < _minLoadInterval) {
      return;
    }
    _lastLoadTime = now;

    var hasWarmCache = state.isInitialized && state.allChats.isNotEmpty;

    // 仅在首次加载时读取本地缓存，已初始化后不再用缓存覆盖当前状态
    if (!state.isInitialized) {
      hasWarmCache = await _loadChatListFromCache();
    }
    PerformanceTraceService.mark(
      hasWarmCache ? 'chat.cache_hit' : 'chat.cache_miss',
    );

    if (_isDisposed) return;
    state = state.copyWith(
      isLoading: !hasWarmCache,
      isSilentLoading: hasWarmCache,
      clearError: true,
      isInitialized: hasWarmCache ? true : state.isInitialized,
    );

    final loadSpan = PerformanceTraceService.start('chat.loadFromServer');
    try {
      PerformanceTraceService.mark('chat.server_request_start');
      final response = await _chatService.getChatList(pageSize: 50);
      PerformanceTraceService.mark('chat.server_response');

      if (_isDisposed) return;

      if (response.isSuccess && response.data != null) {
        // 使用 Map 去重，保留第一个出现的（最新的）
        final seenIds = <String>{};
        final serverChats = response.data!
            .map(
              (userChat) => ChatItem(
                id: userChat.chatId,
                // 优先使用直接返回的 name，其次使用 chat.name
                name: userChat.name ??
                    userChat.chat?.name ??
                    _chatProviderText(
                      zhCN: '未知',
                      zhTW: '未知',
                      en: 'Unknown',
                    ),
                avatar: userChat.avatar ?? userChat.chat?.avatar,
                lastMessage: _normalizeServerChatPreview(
                  userChat.lastMsgText,
                  userChat.lastMsgType,
                ),
                lastMessageTime: userChat.lastMsgTime,
                lastMessageType: _mapMessageContentType(userChat.lastMsgType),
                lastMessageSender:
                    _normalizePreviewSenderName(userChat.lastMsgSender),
                lastMessageMediaUrl: userChat.lastMsgMediaUrl,
                unreadCount: userChat.unreadCount,
                hasMention: userChat.hasMention,
                isPinned: userChat.isPinned,
                isMuted: userChat.isMuted,
                pendingJoinRequestCount: userChat.pendingRequestCount ?? 0,
                hasPendingJoinRequests:
                    (userChat.pendingRequestCount ?? 0) > 0 ||
                        (userChat.pendingRequest ??
                            userChat.chat?.pendingRequest ??
                            false),
                type: userChat.type != null
                    ? _mapChatTypeFromInt(userChat.type!)
                    : _mapChatType(userChat.chat?.type ?? api.ChatType.private),
                createdAt: userChat.chat?.createdAt ?? DateTime.now(),
                targetUserId: userChat.targetId, // 私聊对方用户 ID（头像颜色）
                targetUserUuid: userChat.targetUuid, // 私聊对方用户 UUID（官方用户判断）
                username: userChat.username ?? userChat.chat?.username,
                realMemberCount: userChat.memberCount,
                emojiAvatar: userChat.emojiAvatar, // 表情状态
                nicknameColor: userChat.nicknameColor, // 昵称颜色
                vipLevel: userChat.vipLevel != 0
                    ? userChat.vipLevel
                    : (userChat.chat?.vipLevel ?? 0),
                vipBadge: userChat.vipBadge.isNotEmpty
                    ? userChat.vipBadge
                    : (userChat.chat?.vipBadge ?? ''),
                vipBadgeIcon: userChat.vipBadgeIcon.isNotEmpty
                    ? userChat.vipBadgeIcon
                    : (userChat.chat?.vipBadgeIcon ?? ''),
                vipActive:
                    userChat.vipActive || (userChat.chat?.vipActive ?? false),
                lastMessageSeq: userChat.lastMsgSeq,
                status: userChat.status,
              ),
            )
            .where((chat) => seenIds.add(chat.id)) // 去重：只保留第一次出现的
            .toList();
        final chats = mergeServerChatsWithLocalDrafts(
          serverChats,
          state.allChats,
        );

        final pinned = chats.where((c) => c.isPinned).toList();
        final regular = chats.where((c) => !c.isPinned).toList();

        // 按最后消息时间降序排序（最新的在前）
        pinned.sort(
          (a, b) => (b.lastMessageTime ?? DateTime(1970)).compareTo(
            a.lastMessageTime ?? DateTime(1970),
          ),
        );
        regular.sort(
          (a, b) => (b.lastMessageTime ?? DateTime(1970)).compareTo(
            a.lastMessageTime ?? DateTime(1970),
          ),
        );

        state = state.copyWith(
          pinnedChats: pinned,
          regularChats: regular,
          isLoading: false,
          isSilentLoading: false,
          clearError: true,
          isInitialized: true,
        );

        // 订阅所有会话（优先执行，确保实时消息）
        if (chats.isNotEmpty) {
          final chatIds = _subscriptionChatIds(chats);
          _wsService.subscribeChats(chatIds);
        }
        _scheduleHotChatPrewarm(chats, reason: 'load');

        // 异步写入 Isar，使用增量更新避免数据丢失
        unawaited(_saveChatListToWebCache(chats));

        if (PlatformUtils.isWeb || !IsarService.instance.isAvailable) {
          return;
        }

        Future.microtask(() async {
          try {
            final models = chats.map(_itemToChatModel).toList();
            final newChatIds = models.map((m) => m.id).toSet();
            final accountId = _getCurrentUserId() ?? '';
            if (accountId.isEmpty) return;

            await IsarService.instance.isar.writeTxn(() async {
              // 获取现有聊天 ID
              final existingModels = await IsarService.instance.isar.chatModels
                  .filter()
                  .accountIdEqualTo(accountId)
                  .findAll();
              final existingIds = existingModels.map((m) => m.id).toSet();

              // 删除不再存在的聊天（用户已删除/离开的）
              final toDelete = existingIds.difference(newChatIds);
              if (toDelete.isNotEmpty) {
                final deleteIsarIds = existingModels
                    .where((m) => toDelete.contains(m.id))
                    .map((m) => m.isarId)
                    .toList();
                await IsarService.instance.isar.chatModels.deleteAll(
                  deleteIsarIds,
                );
              }

              // 更新或插入新数据
              await IsarService.instance.isar.chatModels.putAll(models);
            });
          } catch (e) {
            debugPrint('[Chat] Failed to cache chats: $e');
          }
        });

        // 延迟预取头像，不阻塞首屏渲染
        Future.delayed(const Duration(milliseconds: 300), () {
          final avatarUrls = chats
              .map((c) => c.avatar)
              .whereType<String>()
              .where((u) => u.isNotEmpty)
              .toList();
          AvatarCacheManager.prefetchUrls(avatarUrls);
        });
      } else {
        state = state.copyWith(
          isLoading: false,
          isSilentLoading: false,
          error: hasWarmCache
              ? null
              : _chatServerMessage(
                  response.message,
                  fallbackEn: 'Failed to load chats',
                ),
          clearError: hasWarmCache,
          isInitialized: true,
        );
      }
    } catch (e) {
      if (_isDisposed) return;
      if (hasWarmCache) {
        state = state.copyWith(
          isLoading: false,
          isSilentLoading: false,
          clearError: true,
          isInitialized: true,
        );
        return;
      }
      state = state.copyWith(
        isLoading: false,
        error: _chatProviderText(
          zhCN: '加载聊天列表失败，请检查网络后重试',
          zhTW: '載入聊天列表失敗，請檢查網路後重試',
          en: 'Failed to load chats. Check your network and try again.',
        ),
        isInitialized: true,
      );
    } finally {
      loadSpan.finish('count=${state.allChats.length}');
    }
  }

  /// 刷新聊天列表
  Future<void> refresh() async {
    await loadFromServer();
  }

  /// 静默刷新聊天列表（从后台恢复时使用，不显示加载状态）
  ///
  /// [bypassDebounce]：WS 重连后必须尽快对齐服务端未读/预览，避免与上一请求落在同一 500ms 窗口被吞掉。
  Future<void> silentRefresh({bool bypassDebounce = false}) async {
    if (_isDisposed) return;

    // 防抖：500ms 内不重复请求
    final now = DateTime.now();
    if (!bypassDebounce &&
        _lastLoadTime != null &&
        now.difference(_lastLoadTime!) < _minLoadInterval) {
      return;
    }
    _lastLoadTime = now;

    // 如果还没有初始化，则正常加载（显示loading）
    if (!state.isInitialized) {
      await loadFromServer();
      return;
    }

    // 已初始化的情况下，静默刷新（显示小的加载指示器，保持列表可见）
    if (_isDisposed) return;
    state = state.copyWith(isSilentLoading: true);

    final refreshSpan = PerformanceTraceService.start('chat.silentRefresh');
    try {
      final response = await _chatService.getChatList(pageSize: 50);

      if (_isDisposed) return;

      if (response.isSuccess && response.data != null) {
        // 使用 Map 去重，保留第一个出现的（最新的）
        final seenIds = <String>{};
        final serverChats = response.data!
            .map(
              (userChat) => ChatItem(
                id: userChat.chatId,
                name: userChat.name ??
                    userChat.chat?.name ??
                    _chatProviderText(
                      zhCN: '未知',
                      zhTW: '未知',
                      en: 'Unknown',
                    ),
                avatar: userChat.avatar ?? userChat.chat?.avatar,
                lastMessage: _normalizeServerChatPreview(
                  userChat.lastMsgText,
                  userChat.lastMsgType,
                ),
                lastMessageTime: userChat.lastMsgTime,
                lastMessageType: _mapMessageContentType(userChat.lastMsgType),
                lastMessageSender:
                    _normalizePreviewSenderName(userChat.lastMsgSender),
                lastMessageMediaUrl: userChat.lastMsgMediaUrl,
                unreadCount: userChat.unreadCount,
                hasMention: userChat.hasMention,
                isPinned: userChat.isPinned,
                isMuted: userChat.isMuted,
                pendingJoinRequestCount: userChat.pendingRequestCount ?? 0,
                hasPendingJoinRequests:
                    (userChat.pendingRequestCount ?? 0) > 0 ||
                        (userChat.pendingRequest ??
                            userChat.chat?.pendingRequest ??
                            false),
                type: userChat.type != null
                    ? _mapChatTypeFromInt(userChat.type!)
                    : _mapChatType(userChat.chat?.type ?? api.ChatType.private),
                createdAt: userChat.chat?.createdAt ?? DateTime.now(),
                targetUserId: userChat.targetId,
                targetUserUuid: userChat.targetUuid,
                username: userChat.username ?? userChat.chat?.username,
                realMemberCount: userChat.memberCount,
                emojiAvatar: userChat.emojiAvatar,
                nicknameColor: userChat.nicknameColor,
                vipLevel: userChat.vipLevel != 0
                    ? userChat.vipLevel
                    : (userChat.chat?.vipLevel ?? 0),
                vipBadge: userChat.vipBadge.isNotEmpty
                    ? userChat.vipBadge
                    : (userChat.chat?.vipBadge ?? ''),
                vipBadgeIcon: userChat.vipBadgeIcon.isNotEmpty
                    ? userChat.vipBadgeIcon
                    : (userChat.chat?.vipBadgeIcon ?? ''),
                vipActive:
                    userChat.vipActive || (userChat.chat?.vipActive ?? false),
                lastMessageSeq: userChat.lastMsgSeq,
                status: userChat.status,
              ),
            )
            .where((chat) => seenIds.add(chat.id))
            .toList();
        final chats = mergeServerChatsWithLocalDrafts(
          serverChats,
          state.allChats,
        );

        final pinned = chats.where((c) => c.isPinned).toList();
        final regular = chats.where((c) => !c.isPinned).toList();

        // 按最后消息时间降序排序（最新的在前）
        pinned.sort(
          (a, b) => (b.lastMessageTime ?? DateTime(1970)).compareTo(
            a.lastMessageTime ?? DateTime(1970),
          ),
        );
        regular.sort(
          (a, b) => (b.lastMessageTime ?? DateTime(1970)).compareTo(
            a.lastMessageTime ?? DateTime(1970),
          ),
        );

        // 检查数据是否有变化，避免不必要的UI更新
        final hasChanges = _hasListChanges(pinned, regular);

        if (hasChanges) {
          state = state.copyWith(
            pinnedChats: pinned,
            regularChats: regular,
            isSilentLoading: false,
          );
        } else {
          // 即使没有变化也要关闭加载状态
          state = state.copyWith(isSilentLoading: false);
        }

        // 订阅所有会话
        if (chats.isNotEmpty) {
          final chatIds = _subscriptionChatIds(chats);
          _wsService.subscribeChats(chatIds);
        }

        // 异步写入 Isar
        _scheduleHotChatPrewarm(chats, reason: 'silent');

        Future.microtask(() async {
          if (_isDisposed) {
            return;
          }
          if (PlatformUtils.isWeb) {
            await _saveChatListToWebCache(chats);
            return;
          }
          if (!IsarService.instance.isAvailable) {
            return;
          }
          try {
            final accountId = _getCurrentUserId() ?? '';
            if (accountId.isEmpty) return;
            final models = chats.map(_itemToChatModel).toList();
            await IsarService.instance.isar.writeTxn(() async {
              await IsarService.instance.isar.chatModels.putAll(models);
            });
          } catch (e) {
            debugPrint('[Chat] Failed to cache chats in silent refresh: $e');
          }
        });
      } else {
        // 请求失败也要关闭加载状态
        if (!_isDisposed) {
          state = state.copyWith(isSilentLoading: false);
        }
      }
    } catch (e) {
      // 静默刷新失败记录日志但不显示错误
      debugPrint('[Chat] Silent refresh failed: $e');
      if (!_isDisposed) {
        state = state.copyWith(isSilentLoading: false);
      }
    } finally {
      refreshSpan.finish('count=${state.allChats.length}');
    }
  }

  /// 登录、冷启动、恢复前台或 WS 重连后补同步会话列表和漏掉的消息。
  Future<void> syncMissedMessages({
    String reason = 'manual',
    bool force = false,
  }) async {
    if (_isDisposed) return;

    final now = DateTime.now();
    if (!force &&
        _lastMissedMessageSyncTime != null &&
        now.difference(_lastMissedMessageSyncTime!) <
            _missedMessageSyncMinInterval) {
      return;
    }
    _lastMissedMessageSyncTime = now;

    final span = PerformanceTraceService.start('chat.syncMissedMessages');
    try {
      await silentRefresh(bypassDebounce: true);
      await _prefetchMissedMessages(reason: reason);
    } catch (e) {
      debugPrint('[Chat] Missed message sync failed ($reason): $e');
    } finally {
      span.finish('reason=$reason count=${state.allChats.length}');
    }
  }

  Future<void> _onWebSocketReconnectedResume() async {
    await syncMissedMessages(reason: 'ws_reconnected', force: true);
  }

  /// 根据本地 Isar 中各会话最大 seq 调用 `/message/sync`，把断线期间消息写入缓存。
  /// Web 端无 Isar，跳过；当前会话仍由 [MessageListNotifier] 的 reconnected 增量合并内存列表。
  Future<void> _prefetchMissedMessages({required String reason}) async {
    if (_isDisposed || PlatformUtils.isWeb || !IsarService.instance.isAvailable)
      return;
    if (_prefetchMissedMessagesRunning) return;
    _prefetchMissedMessagesRunning = true;

    final uid = _getCurrentUserId();
    if (uid == null || uid.isEmpty) {
      _prefetchMissedMessagesRunning = false;
      return;
    }

    try {
      // 此处只把非活跃会话缺口预热到持久层，不直接改写各聊天页当前的内存窗口。
      final all = [...state.pinnedChats, ...state.regularChats];
      if (all.isEmpty) return;

      // 控制规模，避免一次重连对服务端造成突发压力
      const maxChats = 10;
      final priorityIds = _subscriptionChatIds(all, limit: maxChats).toSet();
      final chats = all.where((chat) => priorityIds.contains(chat.id)).toList();

      for (final chat in chats) {
        if (_isDisposed) break;
        try {
          final last = await IsarService.instance.isar.messageModels
              .filter()
              .accountIdEqualTo(uid)
              .chatIdEqualTo(chat.id)
              .sortBySeqDesc()
              .findFirst();
          final maxSeq = last?.seq ?? 0;
          if (chat.lastMessageSeq > 0 && maxSeq >= chat.lastMessageSeq) {
            continue;
          }
          final resp = await _chatService.syncMessages(
            chat.id,
            lastSeq: maxSeq,
          );
          if (!resp.isSuccess || resp.data == null || resp.data!.isEmpty) {
            continue;
          }
          final items = resp.data!
              .map((m) => MessageItem.fromApiMessage(m, uid))
              .toList();
          await persistMessageItemsToIsarCache(items, accountId: uid);
          debugPrint(
            '[Chat] Missed sync ($reason): ${items.length} messages -> Isar, chat=${chat.id}',
          );
        } catch (e) {
          debugPrint(
            '[Chat] Missed sync failed for chat ${chat.id}: $e',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    } finally {
      _prefetchMissedMessagesRunning = false;
    }
  }

  /// 检查列表是否有变化
  bool _hasListChanges(List<ChatItem> newPinned, List<ChatItem> newRegular) {
    if (state.pinnedChats.length != newPinned.length ||
        state.regularChats.length != newRegular.length) {
      return true;
    }

    // 检查置顶列表
    for (var i = 0; i < newPinned.length; i++) {
      if (_chatItemChanged(state.pinnedChats[i], newPinned[i])) {
        return true;
      }
    }

    // 检查普通列表
    for (var i = 0; i < newRegular.length; i++) {
      if (_chatItemChanged(state.regularChats[i], newRegular[i])) {
        return true;
      }
    }

    return false;
  }

  /// 检查单个聊天项是否有变化
  bool _chatItemChanged(ChatItem old, ChatItem newItem) {
    return old.id != newItem.id ||
        old.lastMessage != newItem.lastMessage ||
        old.lastMessageMediaUrl != newItem.lastMessageMediaUrl ||
        old.lastMessageTime != newItem.lastMessageTime ||
        old.unreadCount != newItem.unreadCount ||
        old.hasMention != newItem.hasMention ||
        old.isPinned != newItem.isPinned ||
        old.isMuted != newItem.isMuted ||
        old.name != newItem.name ||
        old.avatar != newItem.avatar;
  }

  /// 重置状态（登出时调用）
  void reset() {
    if (_isDisposed) return;
    _activeChatId = null;
    _clearAllTyping();
    _recentMessageIds.clear();
    _recentMessageIdOrder.clear();
    state = const ChatListState();
  }

  ChatItemType _mapChatType(api.ChatType type) {
    switch (type) {
      case api.ChatType.private:
        return ChatItemType.private;
      case api.ChatType.group:
        return ChatItemType.group;
      case api.ChatType.channel:
        return ChatItemType.channel;
    }
  }

  ChatItemType _mapChatTypeFromInt(int type) {
    switch (type) {
      case 1:
        return ChatItemType.private;
      case 2:
        return ChatItemType.group;
      case 3:
        return ChatItemType.channel;
      default:
        return ChatItemType.private;
    }
  }

  MessageContentType? _mapMessageContentType(int? type) {
    if (type == null) return null;
    switch (type) {
      case 1:
        return MessageContentType.text;
      case 2:
        return MessageContentType.photo;
      case 3:
        return MessageContentType.video;
      case 4:
        return MessageContentType.voice;
      case 5:
        return MessageContentType.file;
      case 6:
        return MessageContentType.location;
      case 8:
        return MessageContentType.sticker;
      case 10:
        return MessageContentType.contact;
      case 11:
        return MessageContentType.call;
      default:
        return MessageContentType.text;
    }
  }

  /// 创建私聊（调用API）
  Future<ChatItem?> createPrivateChatFromServer({
    required String targetUserId,
    required String targetUserName,
    String? avatar,
  }) async {
    // 检查是否已存在（通过 targetUserId 查找私聊）
    final existingByTarget = _findPrivateChatByTargetUserId(targetUserId);
    if (existingByTarget != null) return existingByTarget;

    final response = await _chatService.createChat(
      type: api.ChatType.private,
      memberIds: [targetUserId],
    );

    if (response.isSuccess && response.data != null) {
      final chatUuid = response.data!.uuid;

      // 再次检查：会话 UUID 是否已存在（可能从服务器加载过）
      final existingByUuid = _findChatById(chatUuid);
      if (existingByUuid != null) {
        // 订阅会话（确保已订阅）
        _wsService.subscribeChats([chatUuid]);
        return existingByUuid;
      }

      // 判断 targetUserId 是 UUID 还是数字 ID
      final isUuid = targetUserId.contains('-');
      final chat = ChatItem(
        id: chatUuid,
        name: targetUserName,
        avatar: avatar,
        type: ChatItemType.private,
        createdAt: response.data!.createdAt,
        targetUserId: isUuid ? null : targetUserId, // 数字 ID
        targetUserUuid: isUuid ? targetUserId : null, // UUID
      );

      if (!_isDisposed) {
        state = state.copyWith(regularChats: [chat, ...state.regularChats]);
      }

      // 订阅新会话
      _wsService.subscribeChats([chat.id]);

      return chat;
    }

    return null;
  }

  /// 通过 targetUserId 或 targetUserUuid 查找私聊
  /// 支持传入数字 ID 或 UUID，会同时匹配两个字段
  ChatItem? _findPrivateChatByTargetUserId(String targetUserId) {
    for (final chat in state.pinnedChats) {
      if (chat.type == ChatItemType.private &&
          (chat.targetUserId == targetUserId ||
              chat.targetUserUuid == targetUserId)) {
        return chat;
      }
    }
    for (final chat in state.regularChats) {
      if (chat.type == ChatItemType.private &&
          (chat.targetUserId == targetUserId ||
              chat.targetUserUuid == targetUserId)) {
        return chat;
      }
    }
    return null;
  }

  /// 创建群组（调用API）
  Future<ChatItem?> createGroupFromServer({
    required String name,
    required List<String> memberIds,
    String? description,
    String? avatar,
    bool isPublic = false,
  }) async {
    final response = await _chatService.createChat(
      type: api.ChatType.group,
      name: name,
      memberIds: memberIds,
      description: description,
      avatar: avatar,
      isPublic: isPublic,
    );

    if (!response.isSuccess) {
      throw Exception(
        _chatServerMessage(
          response.message,
          fallbackEn: 'Failed to create group',
        ),
      );
    }

    if (response.isSuccess && response.data != null) {
      final chatUuid = response.data!.uuid;

      // WS new_chat 事件可能比 HTTP 响应先到，检查是否已存在避免重复
      final existingByUuid = _findChatById(chatUuid);
      if (existingByUuid != null) {
        _wsService.subscribeChats([chatUuid]);
        return existingByUuid;
      }

      final chat = ChatItem(
        id: chatUuid,
        name: response.data!.name ?? name,
        avatar: response.data!.avatar,
        type: ChatItemType.group,
        memberIds: memberIds,
        description: description,
        username: response.data!.username,
        lastMessage: _chatProviderText(
          zhCN: '群组已创建',
          zhTW: '群組已建立',
          en: 'Group created',
        ),
        lastMessageTime: DateTime.now(),
        createdAt: response.data!.createdAt,
      );

      if (!_isDisposed) {
        state = state.copyWith(regularChats: [chat, ...state.regularChats]);
      }

      // 订阅新会话
      _wsService.subscribeChats([chat.id]);

      return chat;
    }

    return null;
  }

  /// 创建频道（调用API）
  Future<ChatItem?> createChannelFromServer({
    required String name,
    String? description,
    bool isPublic = true,
    String? avatar,
  }) async {
    final response = await _chatService.createChat(
      type: api.ChatType.channel,
      name: name,
      description: description,
      isPublic: isPublic,
      avatar: avatar,
    );

    if (!response.isSuccess) {
      throw Exception(
        _chatServerMessage(
          response.message,
          fallbackEn: 'Failed to create channel',
        ),
      );
    }

    if (response.isSuccess && response.data != null) {
      final chatUuid = response.data!.uuid;

      // WS new_chat 事件可能比 HTTP 响应先到，检查是否已存在避免重复
      final existingByUuid = _findChatById(chatUuid);
      if (existingByUuid != null) {
        _wsService.subscribeChats([chatUuid]);
        return existingByUuid;
      }

      final chat = ChatItem(
        id: chatUuid,
        name: response.data!.name ?? name,
        avatar: response.data!.avatar,
        type: ChatItemType.channel,
        description: description,
        username: response.data!.username,
        lastMessage: _chatProviderText(
          zhCN: '频道已创建',
          zhTW: '頻道已建立',
          en: 'Channel created',
        ),
        lastMessageTime: DateTime.now(),
        memberIds: ['me'],
        createdAt: response.data!.createdAt,
      );

      if (!_isDisposed) {
        state = state.copyWith(regularChats: [chat, ...state.regularChats]);
      }

      // 订阅新会话
      _wsService.subscribeChats([chat.id]);

      return chat;
    }

    return null;
  }

  void _applyChatStateChanged(dynamic data) {
    if (_isDisposed || data is! Map) return;
    final chatId = data['chat_id']?.toString();
    if (chatId == null || chatId.isEmpty) return;

    final chat = _findChatById(chatId);
    if (chat == null) {
      unawaited(silentRefresh());
      return;
    }

    final unreadRaw = data['unread_count'];
    final unreadCount = unreadRaw is num ? unreadRaw.toInt() : null;
    final pinnedRaw = data['is_pinned'];
    final mutedRaw = data['is_muted'];
    final mentionRaw = data['has_mention'];
    final isPinned = pinnedRaw is bool ? pinnedRaw : null;
    final isMuted = mutedRaw is bool ? mutedRaw : null;
    final hasMention = mentionRaw is bool ? mentionRaw : null;

    final updated = chat.copyWith(
      unreadCount: unreadCount,
      isPinned: isPinned,
      isMuted: isMuted,
      isRead: unreadCount == 0 ? true : null,
      hasMention: unreadCount == 0 ? false : hasMention,
    );

    if (updated.isPinned != chat.isPinned) {
      if (updated.isPinned) {
        state = state.copyWith(
          pinnedChats: [
            updated,
            ...state.pinnedChats.where((c) => c.id != chatId),
          ],
          regularChats:
              state.regularChats.where((c) => c.id != chatId).toList(),
        );
      } else {
        state = state.copyWith(
          pinnedChats: state.pinnedChats.where((c) => c.id != chatId).toList(),
          regularChats: [
            updated,
            ...state.regularChats.where((c) => c.id != chatId),
          ],
        );
      }
      _updateChatInCache(updated);
      return;
    }

    updateChat(updated);
  }

  /// 根据ID查找聊天
  ChatItem? _findChatById(String id) {
    for (final chat in state.pinnedChats) {
      if (chat.id == id) return chat;
    }
    for (final chat in state.regularChats) {
      if (chat.id == id) return chat;
    }
    return null;
  }

  /// 根据ID获取聊天
  ChatItem? getChatById(String id) => _findChatById(id);

  /// 清空消息后立即移除会话摘要；服务端 cleared_at 负责阻止旧消息重新加载。
  void clearHistoryPreview(String chatId) {
    final chat = _findChatById(chatId);
    if (chat == null) return;

    updateChat(
      chat.copyWith(
        clearLastMessage: true,
        clearLastMessageTime: true,
        clearLastMessageSender: true,
        clearLastMessageType: true,
        lastMessageMediaUrl: null,
        lastMessageSeq: 0,
        unreadCount: 0,
        isRead: true,
        hasMention: false,
        lastMessageFailed: false,
      ),
    );
  }

  /// 更新聊天
  void updateChat(ChatItem updatedChat) {
    if (_isDisposed) return;
    state = state.copyWith(
      pinnedChats: state.pinnedChats
          .map((c) => c.id == updatedChat.id ? updatedChat : c)
          .toList(),
      regularChats: state.regularChats
          .map((c) => c.id == updatedChat.id ? updatedChat : c)
          .toList(),
    );

    // 异步更新 Isar 缓存
    _updateChatInCache(updatedChat);
  }

  /// 更新私聊在会话列表里的显示名（好友备注变更后立即生效）
  void updatePrivateChatDisplayName({
    required String userId,
    required String name,
  }) {
    final nextName = name.trim();
    if (_isDisposed || userId.isEmpty || nextName.isEmpty) return;

    final changedChats = <ChatItem>[];
    ChatItem updateIfMatched(ChatItem chat) {
      final matched = chat.type == ChatItemType.private &&
          (chat.targetUserUuid == userId || chat.targetUserId == userId);
      if (!matched || chat.name == nextName) return chat;

      final updated = chat.copyWith(name: nextName);
      changedChats.add(updated);
      return updated;
    }

    state = state.copyWith(
      pinnedChats: state.pinnedChats.map(updateIfMatched).toList(),
      regularChats: state.regularChats.map(updateIfMatched).toList(),
    );

    for (final chat in changedChats) {
      _updateChatInCache(chat);
    }
  }

  /// 更新最后一条消息并移动到顶部
  DateTime? updateLastMessage(
    String chatId,
    String message, {
    String? sender,
    MessageContentType? type,
    String? mediaUrl,
    bool burnAfterRead = false,
  }) {
    final chat = _findChatById(chatId);
    if (chat == null) return null;

    final previewTime = DateTime.now();

    final updatedChat = chat.copyWith(
      lastMessage: _previewText(message, burnAfterRead: burnAfterRead),
      lastMessageTime: previewTime,
      lastMessageSender: _normalizePreviewSenderName(sender),
      lastMessageType: type,
      lastMessageMediaUrl:
          _shouldKeepLastMessageMediaUrl(type) ? mediaUrl : null,
      isSentByMe: sender == null,
      lastMessageFailed: false,
    );

    // 移动到列表顶部（实时排序）
    _moveToTop(updatedChat);
    return previewTime;
  }

  void updateLastMessageFailure(
    String chatId,
    DateTime? previewTime, {
    required bool failed,
  }) {
    if (previewTime == null) return;
    final chat = _findChatById(chatId);
    if (chat == null ||
        chat.lastMessageTime != previewTime ||
        !chat.isSentByMe) {
      return;
    }
    updateChat(chat.copyWith(lastMessageFailed: failed));
  }

  bool _shouldKeepLastMessageMediaUrl(MessageContentType? type) {
    return type == MessageContentType.photo ||
        type == MessageContentType.video ||
        type == MessageContentType.sticker;
  }

  /// 切换置顶（调用API并持久化）
  Future<void> togglePin(String chatId) async {
    if (_isDisposed) return;
    final chat = _findChatById(chatId);
    if (chat == null) return;

    // 先乐观更新 UI
    final updatedChat = chat.copyWith(isPinned: !chat.isPinned);

    if (updatedChat.isPinned) {
      state = state.copyWith(
        pinnedChats: [updatedChat, ...state.pinnedChats],
        regularChats: state.regularChats.where((c) => c.id != chatId).toList(),
      );
    } else {
      state = state.copyWith(
        pinnedChats: state.pinnedChats.where((c) => c.id != chatId).toList(),
        regularChats: [updatedChat, ...state.regularChats],
      );
    }

    // 调用 API 持久化
    final response = await _chatService.togglePin(chatId);
    if (!response.isSuccess && !_isDisposed) {
      // 如果失败，回滚状态
      if (updatedChat.isPinned) {
        state = state.copyWith(
          pinnedChats: state.pinnedChats.where((c) => c.id != chatId).toList(),
          regularChats: [chat, ...state.regularChats],
        );
      } else {
        state = state.copyWith(
          pinnedChats: [chat, ...state.pinnedChats],
          regularChats:
              state.regularChats.where((c) => c.id != chatId).toList(),
        );
      }
      throw Exception(
        _chatServerMessage(
          response.message,
          fallbackEn: 'Pin action failed',
        ),
      );
    }
  }

  /// 切换静音（调用API并持久化）
  Future<void> toggleMute(String chatId) async {
    if (_isDisposed) return;
    final chat = _findChatById(chatId);
    if (chat == null) return;

    // 先乐观更新 UI
    final updatedChat = chat.copyWith(isMuted: !chat.isMuted);
    updateChat(updatedChat);

    // 调用 API 持久化
    final response = await _chatService.toggleMuteChat(chatId);
    if (!response.isSuccess && !_isDisposed) {
      updateChat(chat);
    }
  }

  /// 切换未读状态（调用API并持久化）
  Future<void> toggleUnread(String chatId) async {
    if (_isDisposed) return;
    final chat = _findChatById(chatId);
    if (chat == null) return;

    // 先乐观更新 UI
    final newUnreadCount = chat.unreadCount == 0 ? 1 : 0;
    final updatedChat = chat.copyWith(
      unreadCount: newUnreadCount,
      hasMention: newUnreadCount > 0 ? chat.hasMention : false,
    );
    updateChat(updatedChat);

    // 调用 API 持久化
    final response = await _chatService.toggleUnread(chatId);
    if (response.isSuccess && response.data != null && !_isDisposed) {
      final authoritativeCount = response.data!;
      final current = _findChatById(chatId);
      if (current != null && current.unreadCount != authoritativeCount) {
        updateChat(
          current.copyWith(
            unreadCount: authoritativeCount,
            hasMention: authoritativeCount > 0 ? current.hasMention : false,
          ),
        );
      }
    } else if (!_isDisposed) {
      updateChat(chat);
    }
  }

  /// 保存账号隔离的会话草稿，并同步到会话列表与本地缓存。
  void updateDraft(String chatId, String value) {
    if (_isDisposed) return;
    final chat = _findChatById(chatId);
    if (chat == null) return;

    final draft = value.isEmpty ? null : value;
    if (chat.draft == draft) return;
    updateChat(
      draft == null
          ? chat.copyWith(clearDraft: true)
          : chat.copyWith(draft: draft),
    );
  }

  /// 标记已读
  void markAsRead(String chatId) {
    final chat = _findChatById(chatId);
    if (chat == null) return;

    final updatedChat = chat.copyWith(unreadCount: 0, hasMention: false);
    updateChat(updatedChat);
  }

  /// 标记未读
  void markAsUnread(String chatId) {
    final chat = _findChatById(chatId);
    if (chat == null) return;

    // 设置为1条未读
    final updatedChat = chat.copyWith(unreadCount: 1);
    updateChat(updatedChat);
  }

  /// 归档聊天
  void archiveChat(String chatId) {
    if (_isDisposed) return;
    _clearTypingForChat(chatId);
    state = state.copyWith(
      pinnedChats: state.pinnedChats.where((c) => c.id != chatId).toList(),
      regularChats: state.regularChats.where((c) => c.id != chatId).toList(),
    );
  }

  /// 移除聊天（退出群组/频道）
  void removeChat(String chatId) {
    if (_isDisposed) return;
    _clearTypingForChat(chatId);
    state = state.copyWith(
      pinnedChats: state.pinnedChats.where((c) => c.id != chatId).toList(),
      regularChats: state.regularChats.where((c) => c.id != chatId).toList(),
    );
  }

  /// 删除聊天（本地 + 清空本地消息记录）
  Future<void> deleteChat(String chatId) async {
    if (_isDisposed) return;
    _clearTypingForChat(chatId);

    // 1. 从列表中移除（乐观更新）
    state = state.copyWith(
      pinnedChats: state.pinnedChats.where((c) => c.id != chatId).toList(),
      regularChats: state.regularChats.where((c) => c.id != chatId).toList(),
    );

    // 2. 删除本地 Isar 中该聊天的所有消息（仅非 Web 平台有 Isar）
    if (PlatformUtils.isWeb) {
      unawaited(
        _saveChatListToWebCache([...state.pinnedChats, ...state.regularChats]),
      );
    } else {
      final accountId = _getCurrentUserId() ?? '';
      if (accountId.isEmpty) return;
      try {
        await IsarService.instance.isar.writeTxn(() async {
          // 删除该聊天的所有消息
          await IsarService.instance.isar.messageModels
              .filter()
              .accountIdEqualTo(accountId)
              .chatIdEqualTo(chatId)
              .deleteAll();
          // 删除该聊天记录
          await IsarService.instance.isar.chatModels
              .filter()
              .accountIdEqualTo(accountId)
              .idEqualTo(chatId)
              .deleteAll();
        });
        debugPrint('[ChatProvider] 已清空聊天 $chatId 的本地记录');
      } catch (e) {
        debugPrint('[ChatProvider] 删除本地消息失败: $e');
      }
    }

    // 3. 通知后端隐藏聊天（全端统一调用，后端会广播多端同步事件）
    try {
      await _chatService.hideChat(chatId);
    } catch (e) {
      debugPrint('[ChatProvider] 通知后端隐藏聊天失败: $e');
    }
  }

  /// 创建私聊（本地）
  ChatItem createPrivateChat({
    required String contactId,
    required String contactName,
    String? avatar,
  }) {
    // 检查是否已存在
    final existing = _findChatById(contactId);
    if (existing != null) return existing;

    final chat = ChatItem(
      id: contactId,
      name: contactName,
      avatar: avatar,
      type: ChatItemType.private,
      isOnline: true,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(regularChats: [chat, ...state.regularChats]);

    return chat;
  }

  /// 创建群组（本地）
  ChatItem createGroup({
    required String name,
    required List<String> memberIds,
    String? avatar,
    String? description,
  }) {
    final now = DateTime.now();
    final chat = ChatItem(
      id: _uuid.v4(),
      name: name,
      avatar: avatar,
      type: ChatItemType.group,
      memberIds: ['me', ...memberIds],
      description: description,
      lastMessage: _chatProviderText(
        zhCN: '群组已创建',
        zhTW: '群組已建立',
        en: 'Group created',
      ),
      lastMessageTime: now,
      createdAt: now,
    );

    state = state.copyWith(regularChats: [chat, ...state.regularChats]);

    return chat;
  }

  /// 创建频道（本地）
  ChatItem createChannel({
    required String name,
    String? avatar,
    String? description,
    bool isPublic = true,
  }) {
    final now = DateTime.now();
    final chat = ChatItem(
      id: _uuid.v4(),
      name: name,
      avatar: avatar,
      type: ChatItemType.channel,
      description: description,
      lastMessage: _chatProviderText(
        zhCN: '频道已创建',
        zhTW: '頻道已建立',
        en: 'Channel created',
      ),
      lastMessageTime: now,
      memberIds: ['me'],
      createdAt: now,
    );

    state = state.copyWith(regularChats: [chat, ...state.regularChats]);

    return chat;
  }

  /// 删除聊天（调用API）- 解散群组，需要群主权限
  Future<bool> deleteChatFromServer(String chatId) async {
    final response = await _chatService.deleteChat(chatId);

    if (_isDisposed) return false;

    if (response.isSuccess) {
      state = state.copyWith(
        pinnedChats: state.pinnedChats.where((c) => c.id != chatId).toList(),
        regularChats: state.regularChats.where((c) => c.id != chatId).toList(),
      );
      return true;
    }

    return false;
  }

  /// 隐藏聊天（从列表移除，不删除消息）
  Future<bool> hideChatFromServer(String chatId) async {
    final response = await _chatService.hideChat(chatId);

    if (_isDisposed) return false;

    if (response.isSuccess) {
      state = state.copyWith(
        pinnedChats: state.pinnedChats.where((c) => c.id != chatId).toList(),
        regularChats: state.regularChats.where((c) => c.id != chatId).toList(),
      );
      return true;
    }

    return false;
  }

  /// 添加成员到群组（调用API）
  Future<bool> addMemberToGroupFromServer(
    String groupId,
    List<String> memberIds,
  ) async {
    final response = await _chatService.addMembers(groupId, memberIds);

    if (_isDisposed) return false;

    if (response.isSuccess) {
      final chat = _findChatById(groupId);
      if (chat != null) {
        final updatedChat = chat.copyWith(
          memberIds: [...chat.memberIds, ...memberIds],
        );
        updateChat(updatedChat);
      }
      return true;
    }

    return false;
  }

  /// 从群组移除成员（调用API）
  Future<bool> removeMemberFromGroupFromServer(
    String groupId,
    String memberId,
  ) async {
    final response = await _chatService.removeMember(groupId, memberId);

    if (_isDisposed) return false;

    if (response.isSuccess) {
      final chat = _findChatById(groupId);
      if (chat != null) {
        final updatedChat = chat.copyWith(
          memberIds: chat.memberIds.where((id) => id != memberId).toList(),
        );
        updateChat(updatedChat);
      }
      return true;
    }

    return false;
  }

  /// 退出群组/频道（调用API）
  Future<(bool, String?)> leaveChatFromServer(String chatId) async {
    final response = await _chatService.leaveChat(chatId);

    if (_isDisposed) return (false, null);

    if (response.isSuccess) {
      // 从本地列表中移除
      state = state.copyWith(
        pinnedChats: state.pinnedChats.where((c) => c.id != chatId).toList(),
        regularChats: state.regularChats.where((c) => c.id != chatId).toList(),
      );
      return (true, null);
    }

    return (
      false,
      _chatServerMessage(response.message, fallbackEn: 'Failed to leave chat'),
    );
  }

  /// 加入/订阅群组或频道（调用API）
  /// 返回 (成功, 错误消息, 是否需要审批, 审批消息)
  Future<(bool, String?, bool, String?)> joinChatFromServer(
    String chatId,
  ) async {
    final response = await _chatService.joinChat(chatId);

    if (_isDisposed) return (false, null, false, null);

    if (response.isSuccess) {
      // 检查是否需要审批
      final requiresApproval = response.data?['requires_approval'] == true;
      final message = _chatServerMessage(
        response.data?['message'] as String?,
        fallbackEn: 'Join request submitted. Please wait for approval.',
      );

      if (!requiresApproval) {
        // 直接加入成功，先获取聊天详情并添加到列表
        final chatResponse = await _chatService.getChat(chatId);
        if (chatResponse.isSuccess &&
            chatResponse.data != null &&
            !_isDisposed) {
          final chat = chatResponse.data!;
          // 检查是否已存在
          if (_findChatById(chatId) == null) {
            // 构建 ChatItem 并添加到列表
            final chatItem = ChatItem(
              id: chat.id,
              name: chat.name ??
                  _chatProviderText(
                    zhCN: '未知',
                    zhTW: '未知',
                    en: 'Unknown',
                  ),
              avatar: chat.avatar,
              type: chat.type == api.ChatType.private
                  ? ChatItemType.private
                  : chat.type == api.ChatType.group
                      ? ChatItemType.group
                      : ChatItemType.channel,
              username: chat.username,
              lastMessage: null,
              lastMessageTime: DateTime.now(),
              unreadCount: 0,
              isPinned: false,
              isMuted: false,
              createdAt: chat.createdAt,
            );
            // 添加到列表顶部
            state = state.copyWith(
              regularChats: [chatItem, ...state.regularChats],
            );
            debugPrint('[Chat] Added joined chat to list: ${chat.name}');
          }
        }
        // 同时刷新列表确保数据同步
        refresh(); // 不需要等待，后台刷新即可
      }

      return (true, null, requiresApproval, message);
    }

    return (
      false,
      _chatServerMessage(response.message, fallbackEn: 'Failed to join chat'),
      false,
      null,
    );
  }
}

/// 聊天详情 Provider (获取单个聊天的详情，包括在线人数等)
/// 使用 cacheTime 延迟销毁，避免快速切换时重复请求
final chatDetailProvider = FutureProvider.family.autoDispose<api.Chat?, String>(
  (ref, chatId) async {
    final currentUserId = ref.watch(currentAccountIdProvider);
    if (currentUserId.isEmpty) {
      return null;
    }

    // 延迟 60 秒销毁，用户快速切换时复用缓存
    final link = ref.keepAlive();
    Timer? timer;
    ref.onDispose(() => timer?.cancel());
    ref.onCancel(() {
      timer?.cancel();
      timer = Timer(const Duration(seconds: 60), () => link.close());
    });
    ref.onResume(() => timer?.cancel());

    final chatService = ref.read(api.chatServiceProvider);
    final response = await chatService.getChat(chatId);
    if (response.isSuccess && response.data != null) {
      return response.data;
    }
    return null;
  },
);

/// 群成员列表 Provider
final chatMembersProvider = FutureProvider.family
    .autoDispose<List<api.ChatMember>, String>((ref, chatId) async {
  final currentUserId = ref.watch(currentAccountIdProvider);
  if (currentUserId.isEmpty) {
    return [];
  }

  final chatService = ref.read(api.chatServiceProvider);
  final response = await chatService.getMembers(chatId);
  if (response.isSuccess && response.data != null) {
    return response.data!;
  }
  return [];
});

/// 当前用户禁言状态 Provider
final chatMemberSearchProvider = FutureProvider.family
    .autoDispose<List<api.ChatMember>, ({String chatId, String keyword})>((
  ref,
  params,
) async {
  final currentUserId = ref.watch(currentAccountIdProvider);
  if (currentUserId.isEmpty) {
    return [];
  }

  final chatService = ref.read(api.chatServiceProvider);
  final response = await chatService.searchMembers(
    params.chatId,
    params.keyword,
  );
  if (response.isSuccess && response.data != null) {
    return response.data!;
  }
  return [];
});

final myMuteStatusProvider = FutureProvider.family
    .autoDispose<api.MuteStatus?, (String chatId, String myUserId)>((
  ref,
  params,
) async {
  final currentUserId = ref.watch(currentAccountIdProvider);
  if (currentUserId.isEmpty) {
    return null;
  }

  final chatService = ref.read(api.chatServiceProvider);
  final response = await chatService.getMuteStatus(params.$1, params.$2);
  if (response.isSuccess && response.data != null) {
    return response.data;
  }
  return null;
});

/// 聊天编辑模式状态
final chatEditModeProvider = StateProvider<bool>((ref) => false);

/// Temporarily hides the mobile floating navigation bar while an overlay
/// needs the bottom edge, for example chat create option sheets.
final floatingNavHiddenProvider = StateProvider<bool>((ref) => false);
