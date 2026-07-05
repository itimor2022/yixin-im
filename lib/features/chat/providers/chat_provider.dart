import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:isar/isar.dart';
import 'package:uuid/uuid.dart';

import '../../../core/services/storage/isar_service.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/services/api/chat_service.dart' as api;
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/background_service.dart';
import '../../../core/services/notification_sound_service.dart';
import '../../../core/services/desktop_notification_service.dart';
import '../../../core/services/storage/models/chat_model.dart' as storage;
import '../../../core/services/storage/models/message_model.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../utils/system_message_text.dart';
import 'package:flutter/material.dart';
import '../../../core/router/app_router.dart';
import '../../contacts/providers/friend_request_provider.dart';
import '../../contacts/providers/contact_provider.dart';
import 'message_provider.dart' show MessageItem, persistMessageItemsToIsarCache;
import 'package:go_router/go_router.dart';

DateTime? _normalizeChatListTime(DateTime? value) {
  if (value == null) return null;
  final normalized = value.toLocal();
  if (normalized.year <= 1) return null;
  return normalized;
}

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
  final bool isSentByMe;
  final bool isRead;
  final List<String> memberIds;
  final String? description;
  final DateTime createdAt;
  final String? targetUserId; // 私聊对方用户 ID（用于头像颜色一致性）
  final String? targetUserUuid; // 私聊对方用户 UUID（用于官方用户判断）
  final int _realMemberCount; // 后端返回的真实成员数
  final String? emojiAvatar; // 表情状态
  final String? nicknameColor; // 昵称颜色
  final String? premiumType; // 会员类型
  final bool isMember; // 是否会员
  final String? badgeText; // 徽章文字
  final String? badgeColor; // 徽章颜色
  final int lastMessageSeq; // 最新消息序号，用于判断编辑是否影响预览

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
    this.isSentByMe = false,
    this.isRead = false,
    this.memberIds = const [],
    this.description,
    required this.createdAt,
    this.targetUserId,
    this.targetUserUuid,
    int realMemberCount = 0,
    this.emojiAvatar,
    this.nicknameColor,
    this.premiumType,
    this.isMember = false,
    this.badgeText,
    this.badgeColor,
    this.lastMessageSeq = 0,
  }) : _realMemberCount = realMemberCount;

  ChatItem copyWith({
    String? id,
    String? name,
    String? avatar,
    String? lastMessage,
    DateTime? lastMessageTime,
    int? unreadCount,
    bool? isPinned,
    bool? isMuted,
    bool? isOnline,
    bool? isVerified,
    int? pendingJoinRequestCount,
    bool? hasPendingJoinRequests,
    ChatItemType? type,
    String? draft,
    String? lastMessageSender,
    MessageContentType? lastMessageType,
    bool? isSentByMe,
    bool? isRead,
    List<String>? memberIds,
    String? description,
    DateTime? createdAt,
    String? targetUserId,
    String? targetUserUuid,
    int? realMemberCount,
    String? emojiAvatar,
    String? nicknameColor,
    String? premiumType,
    bool? isMember,
    String? badgeText,
    String? badgeColor,
    int? lastMessageSeq,
  }) {
    return ChatItem(
      id: id ?? this.id,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
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
      draft: draft ?? this.draft,
      lastMessageSender: lastMessageSender ?? this.lastMessageSender,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      isSentByMe: isSentByMe ?? this.isSentByMe,
      isRead: isRead ?? this.isRead,
      memberIds: memberIds ?? this.memberIds,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      targetUserId: targetUserId ?? this.targetUserId,
      targetUserUuid: targetUserUuid ?? this.targetUserUuid,
      realMemberCount: realMemberCount ?? _realMemberCount,
      emojiAvatar: emojiAvatar ?? this.emojiAvatar,
      nicknameColor: nicknameColor ?? this.nicknameColor,
      premiumType: premiumType ?? this.premiumType,
      isMember: isMember ?? this.isMember,
      badgeText: badgeText ?? this.badgeText,
      badgeColor: badgeColor ?? this.badgeColor,
      lastMessageSeq: lastMessageSeq ?? this.lastMessageSeq,
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
      return '刚刚';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes}分钟前';
    }
    if (diff.inDays < 1) {
      return hhmm;
    }
    if (diff.inDays == 1) {
      return '昨天 $hhmm';
    }
    if (diff.inDays < 7) {
      const weekDays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
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

enum ChatItemType { private, group, channel }

/// 聊天列表状态
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
    ref.watch(authServiceProvider.select((state) => state.user?.uuid));
    // 使用 ref.read 而非 ref.watch，这些服务不会变化，避免不必要的重建
    final chatService = ref.read(api.chatServiceProvider);
    final wsService = ref.read(webSocketServiceProvider.notifier);
    return ChatListNotifier(chatService, wsService, ref);
  },
);

class ChatListNotifier extends StateNotifier<ChatListState> {
  static const String _burnAfterReadPreviewText = '[阅后即焚消息]';

  final api.ChatService _chatService;
  final WebSocketService _wsService;
  final Ref _ref;
  final _uuid = const Uuid();

  // 存储 handler IDs 用于清理
  final List<String> _wsHandlerIds = [];

  // 是否已被释放（用于安全检查）
  bool _isDisposed = false;
  String? _activeChatId; // 用户当前正在查看的聊天 ID，防止误加未读
  /// 防止 WS 重连后并发执行多轮「全会话增量预取」
  bool _prefetchMissedMessagesRunning = false;
  static const Duration _typingTimeout = Duration(seconds: 8);
  static const int _recentMessageIdLimit = 512;
  final Map<String, Map<String, String>> _typingUsersByChat = {};
  final Map<String, Timer> _typingTimers = {};
  final Set<String> _recentMessageIds = <String>{};
  final List<String> _recentMessageIdOrder = <String>[];

  /// 设置当前活跃聊天（进入聊天页面时调用）
  void setActiveChatId(String? chatId) {
    _activeChatId = chatId;
  }

  String? get activeChatId => _activeChatId;

  ChatListNotifier(this._chatService, this._wsService, this._ref)
    : super(const ChatListState()) {
    _setupWebSocketHandlers();
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

    // 监听新消息
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.newMessage, (data) async {
        final raw = data['message'];
        if (raw == null) return;
        if (raw is! Map) {
          if (kDebugMode) debugPrint(
            '[Chat] WS new_message: expected message object, got ${raw.runtimeType}',
          );
          return;
        }
        try {
          final message = await _chatService.parseIncomingMessage(
            Map<String, dynamic>.from(raw),
          );
          _handleNewMessage(message);
        } catch (e, st) {
          if (kDebugMode) debugPrint('[Chat] WS new_message fromJson failed: $e');
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
      _wsService.registerHandler(WSMessageType.newChat, (data) {
        _handleNewChat(data);
      }),
    );

    // 监听重连事件 → 静默刷新会话列表，并对本地会话做增量预取写入 Isar（无需再进会话才拉到断网期间消息）
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.reconnected, (data) {
        if (kDebugMode) debugPrint('[Chat] WS reconnected, silent refreshing chat list...');
        unawaited(_onWebSocketReconnectedResume());
      }),
    );

    // 监听已读回执 (后端发送的 type 是 "read")
    _wsHandlerIds.add(
      _wsService.registerHandler('read', (data) {
        final chatId = data['chat_id'] as String?;
        if (chatId != null) {
          if (kDebugMode) debugPrint('[Chat] Received read receipt for chat: $chatId');
        }
      }),
    );

    // 监听自己其他设备的已读同步（type: "read_sync"）
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.readSync, (data) {
        final chatId = data['chat_id'] as String?;
        if (chatId != null) {
          final chat = _findChatById(chatId);
          if (chat != null && chat.unreadCount > 0) {
            if (kDebugMode) debugPrint('[Chat] read_sync: clearing unread for chat $chatId');
            updateChat(chat.copyWith(unreadCount: 0));
          }
        }
      }),
    );

    // 监听群组被解散（type: "chat_deleted"）
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.chatDeleted, (data) {
        final chatId = data['chat_id'] as String?;
        if (chatId != null) {
          if (kDebugMode) debugPrint('[Chat] Chat deleted: $chatId');
          removeChat(chatId);
        }
      }),
    );

    // 监听当前用户在其他设备上隐藏/删除了会话（多端同步，type: "chat_hidden"）
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.chatHidden, (data) {
        final chatId = data['chat_id'] as String?;
        if (chatId != null) {
          if (kDebugMode) debugPrint('[Chat] Chat hidden on another device, syncing: $chatId');
          _clearTypingForChat(chatId);
          // 从本地列表移除（不再调用后端，避免循环）
          state = state.copyWith(
            pinnedChats: state.pinnedChats
                .where((c) => c.id != chatId)
                .toList(),
            regularChats: state.regularChats
                .where((c) => c.id != chatId)
                .toList(),
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

        DateTime clearedAt = DateTime.now();
        final clearedAtRaw = data['cleared_at']?.toString();
        if (clearedAtRaw != null && clearedAtRaw.isNotEmpty) {
          final parsed = DateTime.tryParse(clearedAtRaw);
          if (parsed != null) {
            clearedAt = parsed.toLocal();
          }
        }

        _clearTypingForChat(chatId);
        updateChat(
          chat.copyWith(
            lastMessage: '',
            lastMessageTime: clearedAt,
            unreadCount: 0,
            isRead: true,
            lastMessageType: MessageContentType.text,
          ),
        );
      }),
    );

    // 监听自己退出群组/被踢出（type: "chat_left"）
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.chatLeft, (data) {
        final chatId = data['chat_id'] as String?;
        if (chatId != null) {
          if (kDebugMode) debugPrint('[Chat] Chat left: $chatId');
          removeChat(chatId);
        }
      }),
    );

    // 监听个人资料更新（其他设备编辑后同步，type: "profile_updated"）
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.profileUpdated, (data) {
        if (kDebugMode) debugPrint('[Chat] Profile updated from another device');
        // 刷新当前用户信息
        _ref.read(authServiceProvider.notifier).getCurrentUser();
        // 同步刷新聊天列表，确保自己的会员状态变更后相关会话样式及时更新
        unawaited(silentRefresh(bypassDebounce: true));
      }),
    );

    // 监听好友申请(F-12 双向好友验证)
    _wsHandlerIds.add(
      _wsService.registerHandler('friend_request', (data) {
        _ref.read(friendRequestProvider.notifier).increment();
        _playNotificationSound(ChatItemType.private);
        
        final ctx = rootNavigatorKey.currentContext;
        
        if (ctx != null) {
          final inner = data['data'];
          final fromName = (inner is Map && inner['from_name'] != null)
              ? inner['from_name'].toString()
              : '有人';

          ScaffoldMessenger.of(ctx).clearSnackBars(); 

          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text('$fromName 请求添加你为好友'),
              duration: const Duration(seconds: 4), 
              action: SnackBarAction(
                label: '查看',
                onPressed: () {
                  ScaffoldMessenger.of(ctx).hideCurrentSnackBar(); 
                  GoRouter.of(rootNavigatorKey.currentContext!).push('/friend-requests');
                },
              ),
            ),
          );

          Future.delayed(const Duration(seconds: 4), () {
            if (rootNavigatorKey.currentContext != null) {
              ScaffoldMessenger.of(rootNavigatorKey.currentContext!).hideCurrentSnackBar();
            }
          });
        }
      }),
    );

    // 监听好友申请被接受(F-12)
    _wsHandlerIds.add(
      _wsService.registerHandler('friend_request_accepted', (data) {
        // 刷新联系人列表
        try {
          _ref.read(contactListProvider.notifier).loadFromServer(force: true);
        } catch (_) {}
        // 刷新会话列表（新会话出现）
        unawaited(silentRefresh(bypassDebounce: true));
        // 提示
        final inner = data['data'];
        final byName = (inner is Map && inner['by_name'] != null)
            ? inner['by_name'].toString()
            : '对方';
        final ctx = rootNavigatorKey.currentContext;
        if (ctx != null) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(content: Text('$byName 已同意你的好友申请')),
          );
        }
      }),
    );

    // 监听对方删除好友 / 自己删除好友（立即从会话列表移除，无需重启）
    _wsHandlerIds.add(
      _wsService.registerHandler('chat_hidden', (data) {
        final chatId = data['chat_id']?.toString() ?? data['data']?['chat_id']?.toString();
        // 立即从内存状态移除该会话
        if (chatId != null && chatId.isNotEmpty) {
          state = state.copyWith(
            pinnedChats: state.pinnedChats.where((c) => c.id != chatId).toList(),
            regularChats: state.regularChats.where((c) => c.id != chatId).toList(),
          );
        }
        // 同步刷新联系人列表
        try {
          _ref.read(contactListProvider.notifier).loadFromServer(force: true);
        } catch (_) {}
      }),
    );

    // 监听用户资料更新（昵称、头像、会员、彩名、表情状态）
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
      _wsService.registerHandler(WSMessageType.joinApproved, (data) {
        final chatId = data['chat_id'] as String?;
        final name = data['name'] as String?;
        if (kDebugMode) debugPrint('[Chat] Join request approved for chat: $chatId ($name)');
        loadFromServer();
        if (chatId != null) {
          _ref.invalidate(chatDetailProvider(chatId));
        }
      }),
    );

    // 监听加入申请被拒绝
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.joinRejected, (data) {
        final chatId = data['chat_id'] as String?;
        final name = data['name'] as String?;
        if (kDebugMode) debugPrint('[Chat] Join request rejected for chat: $chatId ($name)');
        if (chatId != null) {
          _ref.invalidate(chatDetailProvider(chatId));
        }
      }),
    );

    // 监听群组/频道成员变化
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.chatUpdate, (data) {
        final chatId = data['chat_id'] as String?;
        if (kDebugMode) debugPrint('[Chat] Chat updated: $chatId');
        if (chatId != null) {
          _ref.invalidate(chatDetailProvider(chatId));
          _ref.invalidate(chatMembersProvider(chatId));
        }
        loadFromServer();
      }),
    );

    // 监听用户在线状态变化 — 只刷新匹配的私聊，避免 N 次 API 请求
    _wsHandlerIds.add(
      _wsService.registerHandler(WSMessageType.userStatus, (data) {
        final userId = data['user_id'] as String?;
        final isOnline = data['is_online'] as bool? ?? false;
        if (userId == null) return;
        if (kDebugMode) debugPrint('[Chat] User status changed: $userId, isOnline=$isOnline');

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
            if (kDebugMode) debugPrint('[Chat] parse edited message failed: $e');
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
          final chat = _findChatById(chatId);
          if (chat != null) {
            // 仅当被撤回消息是最后一条时才更新预览
            if (msgSeq != null && msgSeq > 0 && chat.lastMessageSeq != msgSeq) {
              return;
            }
            final isSelf = revokerId == _getCurrentUserId();
            final isGroup =
                chat.type == ChatItemType.group ||
                chat.type == ChatItemType.channel;
            final revokeText = isSelf
                ? '你撤回了一条消息'
                : isGroup
                ? '有人撤回了一条消息'
                : '对方撤回了一条消息';
            final updatedChat = chat.copyWith(lastMessage: revokeText);
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
        if (kDebugMode) debugPrint(
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
        if (kDebugMode) debugPrint('[Chat] Chat permissions updated: chatId=$chatId');
        if (chatId != null) {
          _ref.invalidate(chatDetailProvider(chatId));
        }
      }),
    );
  }

  /// 清理 WebSocket handlers
  void _cleanupHandlers() {
    for (final id in _wsHandlerIds) {
      _wsService.unregisterHandler(id);
    }
    _wsHandlerIds.clear();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _cleanupHandlers();
    _clearAllTyping();
    _recentMessageIds.clear();
    _recentMessageIdOrder.clear();
    super.dispose();
  }

  /// 处理用户资料更新（昵称、头像、会员、彩名、表情状态）
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
    final nextPremiumType = data['premium_type']?.toString();
    final nextIsMember = data['is_member'] == true || data['is_member'] == 1;
    final nextBadgeText = data['badge_text']?.toString();
    final nextBadgeColor = data['badge_color']?.toString();

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
        premiumType: nextPremiumType,
        isMember: nextIsMember,
        badgeText: nextBadgeText,
        badgeColor: nextBadgeColor,
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
        premiumType: nextPremiumType,
        isMember: nextIsMember,
        badgeText: nextBadgeText,
        badgeColor: nextBadgeColor,
      );
      if (!identical(updated, chat)) changed = true;
      return updated;
    }).toList();

    if (!changed) return;

    state = state.copyWith(
      pinnedChats: updatedPinned,
      regularChats: updatedRegular,
    );

    if (!PlatformUtils.isWeb) {
      Future.microtask(() async {
        try {
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
          if (kDebugMode) debugPrint('[Chat] Failed to persist user profile update: $e');
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
    String? premiumType,
    bool? isMember,
    String? badgeText,
    String? badgeColor,
  }) {
    final isTargetUser =
        chat.type == ChatItemType.private &&
        (chat.targetUserUuid == userId || chat.targetUserId == userId);
    if (!isTargetUser) return chat;

    return chat.copyWith(
      name: name != null && name.isNotEmpty ? name : chat.name,
      avatar: avatar ?? chat.avatar,
      nicknameColor: nicknameColor ?? chat.nicknameColor,
      emojiAvatar: emojiAvatar ?? chat.emojiAvatar,
      premiumType: premiumType ?? chat.premiumType,
      isMember: isMember ?? chat.isMember,
      badgeText: badgeText ?? chat.badgeText,
      badgeColor: badgeColor ?? chat.badgeColor,
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
        : (chat.type == ChatItemType.private ? '对方' : '有人');

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
      next[chatId] = '正在输入...';
    } else {
      final latestName = typingUsers.values.isNotEmpty
          ? typingUsers.values.last
          : '有人';
      next[chatId] = '$latestName 正在输入...';
    }

    _safeSetState((s) => s.copyWith(typingByChat: next));
  }

  void _clearTypingForChat(String chatId) {
    _typingUsersByChat.remove(chatId);
    final prefix = '$chatId:';
    final keysToRemove = _typingTimers.keys
        .where((k) => k.startsWith(prefix))
        .toList();
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
      case 10:
        return MessageContentType.contact;
      case 11:
        return MessageContentType.call;
      default:
        return MessageContentType.text;
    }
  }

  String _previewText(String? text, {bool burnAfterRead = false}) {
    if (burnAfterRead) {
      return _burnAfterReadPreviewText;
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
        return ('[图片]', MessageContentType.photo);
      case 3:
        return ('[视频]', MessageContentType.video);
      case 4:
        return ('[语音]', MessageContentType.voice);
      case 5:
        return ('[文件]', MessageContentType.file);
      case 6:
        return ('[位置]', MessageContentType.location);
      case 10:
        return ('[联系人名片]', MessageContentType.contact);
      case 11:
        return (message.content.text ?? '[通话]', MessageContentType.call);
      case 12:
        return ('[红包]', MessageContentType.text);
      case 13:
        return ('[转账]', MessageContentType.text);
      case 99:
        return (
          resolveSystemMessageText(
            message.content.text ?? '',
            currentUserId: _getCurrentUserId(),
          ),
          MessageContentType.text,
        );
      default:
        return (message.content.text ?? '[消息]', MessageContentType.text);
    }
  }

  /// 处理新消息
  void _handleNewMessage(api.Message message) {
    if (!_rememberMessageId(message.msgId)) {
      if (kDebugMode) debugPrint('[Chat] Skip duplicate new_message: ${message.msgId}');
      return;
    }

    final chat = _findChatById(message.chatId);
    if (chat != null) {
      _clearTypingForChat(message.chatId);
      final preview = _previewForMessage(message);
      final lastMessage = preview.$1;
      final lastMessageType = preview.$2;

      // 只有对方发的消息且用户不在该聊天页面时才增加未读计数
      // 系统消息（type=99）不增加未读数，避免创建群组等系统事件触发未读角标
      final isSelf = message.senderId == _getCurrentUserId();
      final isSystemMsg = message.type == 99;
      final isViewing = _activeChatId == message.chatId;
      final newUnread = (isSelf || isViewing || isSystemMsg)
          ? chat.unreadCount
          : chat.unreadCount + 1;

      final updatedChat = chat.copyWith(
        lastMessage: lastMessage,
        lastMessageTime: message.createdAt,
        lastMessageSender: message.senderName,
        lastMessageType: lastMessageType,
        unreadCount: newUnread,
        lastMessageSeq: message.seq,
      );

      // 移动到列表顶部
      _moveToTop(updatedChat);

      // 播放通知音效（如果不是静音且不是自己发送的消息）
      if (!chat.isMuted && message.senderId != _getCurrentUserId()) {
        _playNotificationSound(chat.type);
        if (newUnread > chat.unreadCount) {
          _updateAndroidBackgroundNotification(
            chat: chat,
            senderName: message.senderName ?? '未知',
            content: lastMessage,
            unreadCount: _totalUnreadCount(),
          );
        }
        // 发送桌面端通知
        _showDesktopNotification(
          chat: chat,
          senderName: message.senderName ?? '未知',
          content: lastMessage,
        );
      }
    } else {
      // 如果聊天不在列表中，刷新列表
      loadFromServer();
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
    try {
      final authState = _ref.read(authServiceProvider);
      return authState.user?.uuid;
    } catch (e) {
      return null;
    }
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

  /// 播放通知音效
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
          if (kDebugMode) debugPrint('[Chat] Play notification sound async error: $e');
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Chat] Play notification sound failed: $e');
    }
  }

  void _updateAndroidBackgroundNotification({
    required ChatItem chat,
    required String senderName,
    required String content,
    required int unreadCount,
  }) {
    if (!PlatformUtils.isAndroid || unreadCount <= 0) return;

    try {
      final soundService = _ref.read(notificationSoundServiceProvider.notifier);
      final showPreview = soundService.shouldShowPreview();

      String title;
      String body;

      switch (chat.type) {
        case ChatItemType.private:
          title = chat.name;
          body = showPreview ? content : '您收到一条新消息';
          break;
        case ChatItemType.group:
          title = chat.name;
          body = showPreview ? '$senderName: $content' : '您收到一条群消息';
          break;
        case ChatItemType.channel:
          title = chat.name;
          body = showPreview ? content : '频道有新消息';
          break;
      }

      BackgroundService.instance.updateLatestMessage(
        title: title,
        content: body,
        unreadCount: unreadCount,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatProvider] Background notification error: $e');
    }
  }

  /// 显示桌面端通知
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
          body = showPreview ? content : '您收到一条新消息';
          break;
        case ChatItemType.group:
          title = chat.name;
          body = showPreview ? '$senderName: $content' : '您收到一条群消息';
          break;
        case ChatItemType.channel:
          title = chat.name;
          body = showPreview ? content : '频道有新消息';
          break;
      }

      DesktopNotificationService().showMessageNotification(
        title: title,
        body: body,
        payload: chat.id,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatProvider] Desktop notification error: $e');
    }
  }

  /// 处理新会话
  void _handleNewChat(dynamic data) {
    // 后端发送格式: { type: "new_chat", message: { id, type, name, avatar, ... } }
    final message = data['message'] as Map<String, dynamic>?;
    if (message == null) return;

    final chatId = message['id'] as String?;
    final chatType = message['type'] as int? ?? 1;
    final name = message['name'] as String? ?? '未知';
    final rawAvatar = message['avatar'] as String?;
    // 转换头像 URL
    final avatar = rawAvatar != null && rawAvatar.isNotEmpty
        ? ApiConfig.getMediaUrl(rawAvatar)
        : rawAvatar;

    if (chatId == null) return;

    if (kDebugMode) debugPrint(
      '[Chat] Received new_chat notification: $chatId, name: $name, type: $chatType',
    );

    // 检查是否已存在
    if (_findChatById(chatId) != null) {
      if (kDebugMode) debugPrint('[Chat] Chat already exists, skipping');
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
      createdAt: DateTime.now(),
    );

    if (_isDisposed) return;
    state = state.copyWith(regularChats: [chat, ...state.regularChats]);

    if (kDebugMode) debugPrint('[Chat] Added new chat to list');
  }

  /// 移动聊天到列表顶部
  void _moveToTop(ChatItem chat) {
    if (_isDisposed) return;
    if (chat.isPinned) {
      final others = state.pinnedChats.where((c) => c.id != chat.id).toList();
      state = state.copyWith(pinnedChats: [chat, ...others]);
    } else {
      final pinnedWithout = state.pinnedChats
          .where((c) => c.id != chat.id)
          .toList();
      final regularWithout = state.regularChats
          .where((c) => c.id != chat.id)
          .toList();
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
    if (PlatformUtils.isWeb) return;

    Future.microtask(() async {
      if (_isDisposed) return;
      try {
        final model = _itemToChatModel(chat);
        await IsarService.instance.isar.writeTxn(() async {
          await IsarService.instance.isar.chatModels.put(model);
        });
      } catch (e) {
        if (kDebugMode) debugPrint('[Chat] Failed to update chat in cache: $e');
      }
    });
  }

  /// 初始化 - 从服务器加载聊天列表
  Future<void> initialize() async {
    if (state.isInitialized) return;
    await loadFromServer();
  }

  /// 从本地 Isar 读取聊天列表缓存，先展示再请求服务器
  Future<void> _loadChatListFromCache() async {
    if (PlatformUtils.isWeb) return;

    try {
      // 限制查询数量，避免大量数据导致性能问题
      final list = await IsarService.instance.isar.chatModels
          .where()
          .sortByLastMessageTimeDesc()
          .limit(200)
          .findAll();
      if (list.isEmpty || _isDisposed) return;
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
    } catch (e) {
      if (kDebugMode) debugPrint('[Chat] Failed to load from cache: $e');
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
      lastMessage: m.lastMessage,
      lastMessageTime: _normalizeChatListTime(m.lastMessageTime),
      unreadCount: m.unreadCount,
      isPinned: m.isPinned,
      isMuted: m.isMuted,
      type: type,
      pendingJoinRequestCount: 0,
      hasPendingJoinRequests: false,
      lastMessageSender: m.lastMessageSender,
      lastMessageType: lastMsgType,
      createdAt: m.createdAt,
      targetUserId: m.peerUserId,
      realMemberCount: m.memberCount ?? 0,
      premiumType: m.premiumType,
      isMember: m.isMember ?? false,
      badgeText: m.badgeText,
      badgeColor: m.badgeColor,
      nicknameColor: m.nicknameColor,
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
    return storage.ChatModel()
      ..id = c.id
      ..type = type
      ..name = c.name
      ..avatar = c.avatar
      ..lastMessage = c.lastMessage
      ..lastMessageType = lastMsgType
      ..lastMessageSender = c.lastMessageSender
      ..lastMessageTime = _normalizeChatListTime(c.lastMessageTime)
      ..unreadCount = c.unreadCount
      ..isMuted = c.isMuted
      ..isPinned = c.isPinned
      ..isArchived = false
      ..draft = c.draft
      ..memberCount = c.memberCount > 0 ? c.memberCount : null
      ..peerUserId = c.targetUserId
      ..premiumType = c.premiumType
      ..isMember = c.isMember
      ..badgeText = c.badgeText
      ..badgeColor = c.badgeColor
      ..nicknameColor = c.nicknameColor
      ..createdAt = c.createdAt
      ..updatedAt = now;
  }

  // 防抖：记录上次请求时间，避免短时间内重复请求
  DateTime? _lastLoadTime;
  static const _minLoadInterval = Duration(milliseconds: 500);

  /// 从服务器加载聊天列表
  Future<void> loadFromServer() async {
    if (_isDisposed) return;

    // 防抖：500ms 内不重复请求
    final now = DateTime.now();
    if (_lastLoadTime != null &&
        now.difference(_lastLoadTime!) < _minLoadInterval) {
      return;
    }
    _lastLoadTime = now;

    if (_isDisposed) return;
    state = state.copyWith(isLoading: true, error: null);

    // 仅在首次加载时读取本地缓存，已初始化后不再用缓存覆盖当前状态
    if (!state.isInitialized && !PlatformUtils.isWeb) {
      await _loadChatListFromCache();
    }

    try {
      final response = await _chatService.getChatList();

      if (_isDisposed) return;

      if (response.isSuccess && response.data != null) {
        // 使用 Map 去重，保留第一个出现的（最新的）
        final seenIds = <String>{};
        final chats = response.data!
            .map(
              (userChat) => ChatItem(
                id: userChat.chatId,
                // 优先使用直接返回的 name，其次使用 chat.name
                name: userChat.name ?? userChat.chat?.name ?? '未知',
                avatar: userChat.avatar ?? userChat.chat?.avatar,
                lastMessage: userChat.lastMsgType == 99
                    ? resolveSystemMessageText(
                        userChat.lastMsgText ?? '',
                        currentUserId: _getCurrentUserId(),
                      )
                    : userChat.lastMsgText,
                lastMessageTime: userChat.lastMsgTime,
                lastMessageType: _mapMessageContentType(userChat.lastMsgType),
                lastMessageSender: userChat.lastMsgSender,
                unreadCount: userChat.unreadCount,
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
                realMemberCount: userChat.memberCount,
                emojiAvatar: userChat.emojiAvatar, // 表情状态
                nicknameColor: userChat.nicknameColor, // 昵称颜色
                premiumType: userChat.premiumType, // 会员类型
                lastMessageSeq: userChat.lastMsgSeq,
                                // 会员/徽章字段：直接信任接口值（getChatList 已稳定下发 is_member/badge_*）
                isMember: userChat.isMember,
                badgeText: userChat.badgeText,
                badgeColor: userChat.badgeColor,
              ),
            )
            .where((chat) => seenIds.add(chat.id)) // 去重：只保留第一次出现的
            .toList();

        final pinned  = chats.where((c) =>  c.isPinned).toList();
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
          isInitialized: true,
        );

        // 订阅所有会话（优先执行，确保实时消息）
        if (chats.isNotEmpty) {
          final chatIds = chats.map((c) => c.id).toList();
          _wsService.subscribeChats(chatIds);
        }

        // 异步写入 Isar，使用增量更新避免数据丢失
        if (PlatformUtils.isWeb) {
          return;
        }

        Future.microtask(() async {
          try {
            final models = chats.map(_itemToChatModel).toList();
            final newChatIds = models.map((m) => m.id).toSet();

            await IsarService.instance.isar.writeTxn(() async {
              // 获取现有聊天 ID
              final existingModels = await IsarService.instance.isar.chatModels
                  .where()
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
            if (kDebugMode) debugPrint('[Chat] Failed to cache chats: $e');
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
          error: response.message,
          isInitialized: true,
        );
      }
    } catch (e) {
      if (_isDisposed) return;
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
        isInitialized: true,
      );
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

    try {
      final response = await _chatService.getChatList();

      if (_isDisposed) return;

      if (response.isSuccess && response.data != null) {
        // 使用 Map 去重，保留第一个出现的（最新的）
        final seenIds = <String>{};
        final chats = response.data!
            .map(
              (userChat) => ChatItem(
                id: userChat.chatId,
                name: userChat.name ?? userChat.chat?.name ?? '未知',
                avatar: userChat.avatar ?? userChat.chat?.avatar,
                lastMessage: userChat.lastMsgType == 99
                    ? resolveSystemMessageText(
                        userChat.lastMsgText ?? '',
                        currentUserId: _getCurrentUserId(),
                      )
                    : userChat.lastMsgText,
                lastMessageTime: userChat.lastMsgTime,
                lastMessageType: _mapMessageContentType(userChat.lastMsgType),
                lastMessageSender: userChat.lastMsgSender,
                unreadCount: userChat.unreadCount,
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
                realMemberCount: userChat.memberCount,
                emojiAvatar: userChat.emojiAvatar,
                nicknameColor: userChat.nicknameColor,
                premiumType: userChat.premiumType,
                lastMessageSeq: userChat.lastMsgSeq,
                // 会员/徽章字段：直接信任接口值，修复静默刷新徽章丢失
                isMember: userChat.isMember,
                badgeText: userChat.badgeText,
                badgeColor: userChat.badgeColor,
              ),
            )
            .where((chat) => seenIds.add(chat.id))
            .toList();

        // ==================== ❌ 二开好友过滤已被彻底干掉 ====================

        // 🌟 最核心修改：恢复成原版，直接将全量 chats 数据源分别拆分给置顶和常规列表
        final pinned  = chats.where((c) =>  c.isPinned).toList();
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
          final chatIds = chats.map((c) => c.id).toList();
          _wsService.subscribeChats(chatIds);
        }

        // 异步写入 Isar
        Future.microtask(() async {
          // 🛡️ 额外拦截：日志报过 Isar 故障，如果没开成功直接终止，保护内存数据
          if (_isDisposed ||
              PlatformUtils.isWeb ||
              IsarService.instance == null ||
              !IsarService.instance.isAvailable) {
            return;
          }
          try {
            final models = chats.map(_itemToChatModel).toList();
            await IsarService.instance.isar.writeTxn(() async {
              await IsarService.instance.isar.chatModels.clear();
              await IsarService.instance.isar.chatModels.putAll(models);
            });
          } catch (e) {
            if (kDebugMode) debugPrint('[Chat] Failed to cache chats in silent refresh: $e');
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
      if (kDebugMode) debugPrint('[Chat] Silent refresh failed: $e');
      if (!_isDisposed) {
        state = state.copyWith(isSilentLoading: false);
      }
    }
  }

  /// WS 重连后：先对齐会话列表，再后台按会话增量拉取消息写入 Isar（移动端离线恢复场景）
  Future<void> _onWebSocketReconnectedResume() async {
    await silentRefresh(bypassDebounce: true);
    await _prefetchMissedMessagesAfterReconnect();
  }

  /// 根据本地 Isar 中各会话最大 seq 调用 `/message/sync`，把断线期间消息写入缓存。
  /// Web 端无 Isar，跳过；当前会话仍由 [MessageListNotifier] 的 reconnected 增量合并内存列表。
  Future<void> _prefetchMissedMessagesAfterReconnect() async {
    if (_isDisposed) return;
    // Web端不依赖Isar，允许继续执行
    if (_prefetchMissedMessagesRunning) return;
    _prefetchMissedMessagesRunning = true;

    final uid = _getCurrentUserId();
    if (uid == null || uid.isEmpty) {
      _prefetchMissedMessagesRunning = false;
      return;
    }

    try {
      final all = [...state.pinnedChats, ...state.regularChats];
      if (all.isEmpty) return;

      // 控制规模，避免一次重连对服务端造成突发压力
      const maxChats = 40;
      final chats = all.take(maxChats).toList();

      for (final chat in chats) {
        if (_isDisposed) break;
        try {
          int maxSeq = 0;
          if (!PlatformUtils.isWeb && IsarService.instance.isAvailable) {
            final last = await IsarService.instance.isar.messageModels
                .filter()
                .chatIdEqualTo(chat.id)
                .sortBySeqDesc()
                .findFirst();
            maxSeq = last?.seq ?? 0;
          } else {
            maxSeq = chat.lastMessageSeq;
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
          if (!PlatformUtils.isWeb && IsarService.instance.isAvailable) {
            await persistMessageItemsToIsarCache(items);
          }
          // Web端和App端都更新内存消息列表
          for (final msg in resp.data!) {
            _handleNewMessage(msg);
          }
          if (kDebugMode) debugPrint(
            '[Chat] Reconnect prefetch: ${items.length} messages → Isar, chat=${chat.id}',
          );
        } catch (e) {
          if (kDebugMode) debugPrint(
            '[Chat] Reconnect prefetch failed for chat ${chat.id}: $e',
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
        old.lastMessageTime != newItem.lastMessageTime ||
        old.unreadCount != newItem.unreadCount ||
        old.isPinned != newItem.isPinned ||
        old.isMuted != newItem.isMuted ||
        old.name != newItem.name ||
        old.avatar != newItem.avatar;
  }

  /// 重置状态（登出时调用）
  void reset() {
    if (_isDisposed) return;
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
        return MessageContentType.sticker;
      case 7:
        return MessageContentType.location;
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
      throw AppCleanException(
        response.message.isNotEmpty ? response.message : '创建群组失败',
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
        lastMessage: '群组已创建',
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
      throw AppCleanException(
        response.message.isNotEmpty ? response.message : '创建频道失败',
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
        lastMessage: '频道已创建',
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
      final matched =
          chat.type == ChatItemType.private &&
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
  void updateLastMessage(
    String chatId,
    String message, {
    String? sender,
    MessageContentType? type,
    bool burnAfterRead = false,
  }) {
    final chat = _findChatById(chatId);
    if (chat == null) return;

    final updatedChat = chat.copyWith(
      lastMessage: _previewText(message, burnAfterRead: burnAfterRead),
      lastMessageTime: DateTime.now(),
      lastMessageSender: sender,
      lastMessageType: type,
      isSentByMe: sender == null,
    );

    // 移动到列表顶部（实时排序）
    _moveToTop(updatedChat);
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
          regularChats: state.regularChats
              .where((c) => c.id != chatId)
              .toList(),
        );
      }
      throw AppCleanException(
        response.message.isNotEmpty ? response.message : '置顶操作失败',
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
    final updatedChat = chat.copyWith(unreadCount: newUnreadCount);
    updateChat(updatedChat);

    // 调用 API 持久化
    final response = await _chatService.toggleUnread(chatId);
    if (!response.isSuccess && !_isDisposed) {
      updateChat(chat);
    }
  }

  /// 标记已读
  void markAsRead(String chatId) {
    final chat = _findChatById(chatId);
    if (chat == null) return;

    final updatedChat = chat.copyWith(unreadCount: 0);
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
    if (!PlatformUtils.isWeb) {
      try {
        await IsarService.instance.isar.writeTxn(() async {
          // 删除该聊天的所有消息
          await IsarService.instance.isar.messageModels
              .filter()
              .chatIdEqualTo(chatId)
              .deleteAll();
          // 删除该聊天记录
          await IsarService.instance.isar.chatModels
              .filter()
              .idEqualTo(chatId)
              .deleteAll();
        });
        if (kDebugMode) debugPrint('[ChatProvider] 已清空聊天 $chatId 的本地记录');
      } catch (e) {
        if (kDebugMode) debugPrint('[ChatProvider] 删除本地消息失败: $e');
      }
    }

    // 3. 通知后端隐藏聊天（全端统一调用，后端会广播多端同步事件）
    try {
      await _chatService.hideChat(chatId);
    } catch (e) {
      if (kDebugMode) debugPrint('[ChatProvider] 通知后端隐藏聊天失败: $e');
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
      lastMessage: '群组已创建',
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
      lastMessage: '频道已创建',
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

    return (false, response.message);
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
      final message = response.data?['message'] as String?;

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
              name: chat.name ?? '未知',
              avatar: chat.avatar,
              type: chat.type == api.ChatType.private
                  ? ChatItemType.private
                  : chat.type == api.ChatType.group
                  ? ChatItemType.group
                  : ChatItemType.channel,
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
            if (kDebugMode) debugPrint('[Chat] Added joined chat to list: ${chat.name}');
          }
        }
        // 同时刷新列表确保数据同步
        refresh(); // 不需要等待，后台刷新即可
      }

      return (true, null, requiresApproval, message);
    }

    return (false, response.message, false, null);
  }
}

/// 聊天详情 Provider (获取单个聊天的详情，包括在线人数等)
/// 使用 cacheTime 延迟销毁，避免快速切换时重复请求
final chatDetailProvider = FutureProvider.family.autoDispose<api.Chat?, String>(
  (ref, chatId) async {
    final currentUserId = ref.watch(
      authServiceProvider.select((state) => state.user?.uuid),
    );
    if (currentUserId == null || currentUserId.isEmpty) {
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
      final currentUserId = ref.watch(
        authServiceProvider.select((state) => state.user?.uuid),
      );
      if (currentUserId == null || currentUserId.isEmpty) {
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
      final currentUserId = ref.watch(
        authServiceProvider.select((state) => state.user?.uuid),
      );
      if (currentUserId == null || currentUserId.isEmpty) {
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
      final currentUserId = ref.watch(
        authServiceProvider.select((state) => state.user?.uuid),
      );
      if (currentUserId == null || currentUserId.isEmpty) {
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
