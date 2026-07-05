import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:universal_io/io.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:isar/isar.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../../core/services/api/chat_service.dart' as api;
import '../../../core/services/api/websocket_service.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/storage/models/message_model.dart';
import '../../../core/services/offline_message_queue.dart';
import '../../../core/utils/image_compress_util.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/services/storage/isar_service.dart';
import '../widgets/message_bubble.dart' show WalletBubbleRefreshNotifier;

MessageItemType _msgTypeToItemType(MsgType t) {
  switch (t) {
    case MsgType.text:
      return MessageItemType.text;
    case MsgType.image:
      return MessageItemType.image;
    case MsgType.video:
      return MessageItemType.video;
    case MsgType.audio:
      return MessageItemType.audio;
    case MsgType.voice:
      return MessageItemType.voice;
    case MsgType.file:
      return MessageItemType.file;
    case MsgType.sticker:
      return MessageItemType.sticker;
    case MsgType.gif:
      return MessageItemType.gif;
    case MsgType.location:
      return MessageItemType.location;
    case MsgType.contact:
      return MessageItemType.contact;
    case MsgType.poll:
      return MessageItemType.poll;
    case MsgType.system:
      return MessageItemType.system;
    case MsgType.call:
      return MessageItemType.call;
    case MsgType.redPacket:
      return MessageItemType.redPacket;
    case MsgType.transfer:
      return MessageItemType.transfer;
  }
}

MessageStatus _msgStatusToMessageStatus(MsgStatus s) {
  switch (s) {
    case MsgStatus.sending:
      return MessageStatus.sending;
    case MsgStatus.sent:
      return MessageStatus.sent;
    case MsgStatus.delivered:
      return MessageStatus.delivered;
    case MsgStatus.read:
      return MessageStatus.read;
    case MsgStatus.failed:
      return MessageStatus.failed;
  }
}

const Object _messageItemUnset = Object();

class MessageItem {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String? senderNicknameColor;
  final String? senderPremiumType;
  final String? senderEmojiAvatar;
  final MessageItemType type;
  final String content;
  final String? mediaUrl;
  final String? thumbnail;
  final int? mediaWidth;
  final int? mediaHeight;
  final int? mediaSize;
  final int? mediaDuration;
  final String? fileName;
  final bool isOutgoing;
  final MessageStatus status;
  final bool isRead;
  final ReplyInfo? replyTo;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool isEdited;
  final bool isDeleted;
  final String? revokedBy;
  final bool burnAfterRead;
  final int burnAfterSeconds;
  final bool burnLocked;
  final int? burnCountdownSeconds;
  final int seq;
  final List<MessageReaction> reactions;
  final double? uploadProgress;
  // Contact card fields
  final String? contactUserId;
  final String? contactName;
  final String? contactAvatar;
  final String? contactUsername;
  final String? contactNicknameColor;
  final String? contactEmojiAvatar;
  final String? contactPremiumType;
  final double? locationLatitude;
  final double? locationLongitude;
  final String? locationTitle;
  final String? locationAddress;

  const MessageItem({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    this.senderNicknameColor,
    this.senderPremiumType,
    this.senderEmojiAvatar,
    this.type = MessageItemType.text,
    required this.content,
    this.mediaUrl,
    this.thumbnail,
    this.mediaWidth,
    this.mediaHeight,
    this.mediaSize,
    this.mediaDuration,
    this.fileName,
    this.isOutgoing = true,
    this.status = MessageStatus.sent,
    this.isRead = false,
    this.replyTo,
    required this.createdAt,
    this.editedAt,
    this.isEdited = false,
    this.isDeleted = false,
    this.revokedBy,
    this.burnAfterRead = false,
    this.burnAfterSeconds = 0,
    this.burnLocked = false,
    this.burnCountdownSeconds,
    this.seq = 0,
    this.reactions = const [],
    this.uploadProgress,
    this.contactUserId,
    this.contactName,
    this.contactAvatar,
    this.contactUsername,
    this.contactNicknameColor,
    this.contactEmojiAvatar,
    this.contactPremiumType,
    this.locationLatitude,
    this.locationLongitude,
    this.locationTitle,
    this.locationAddress,
  });

  MessageItem copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? senderName,
    String? senderAvatar,
    String? senderNicknameColor,
    String? senderPremiumType,
    String? senderEmojiAvatar,
    MessageItemType? type,
    String? content,
    String? mediaUrl,
    String? thumbnail,
    int? mediaWidth,
    int? mediaHeight,
    int? mediaSize,
    int? mediaDuration,
    String? fileName,
    bool? isOutgoing,
    MessageStatus? status,
    bool? isRead,
    ReplyInfo? replyTo,
    DateTime? createdAt,
    DateTime? editedAt,
    bool? isEdited,
    bool? isDeleted,
    String? revokedBy,
    bool? burnAfterRead,
    int? burnAfterSeconds,
    bool? burnLocked,
    Object? burnCountdownSeconds = _messageItemUnset,
    int? seq,
    List<MessageReaction>? reactions,
    double? uploadProgress,
    String? contactUserId,
    String? contactName,
    String? contactAvatar,
    String? contactUsername,
    String? contactNicknameColor,
    String? contactEmojiAvatar,
    String? contactPremiumType,
    double? locationLatitude,
    double? locationLongitude,
    String? locationTitle,
    String? locationAddress,
  }) {
    return MessageItem(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      senderNicknameColor: senderNicknameColor ?? this.senderNicknameColor,
      senderPremiumType: senderPremiumType ?? this.senderPremiumType,
      senderEmojiAvatar: senderEmojiAvatar ?? this.senderEmojiAvatar,
      type: type ?? this.type,
      content: content ?? this.content,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnail: thumbnail ?? this.thumbnail,
      mediaWidth: mediaWidth ?? this.mediaWidth,
      mediaHeight: mediaHeight ?? this.mediaHeight,
      mediaSize: mediaSize ?? this.mediaSize,
      mediaDuration: mediaDuration ?? this.mediaDuration,
      fileName: fileName ?? this.fileName,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      status: status ?? this.status,
      isRead: isRead ?? this.isRead,
      replyTo: replyTo ?? this.replyTo,
      createdAt: createdAt ?? this.createdAt,
      editedAt: editedAt ?? this.editedAt,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      revokedBy: revokedBy ?? this.revokedBy,
      burnAfterRead: burnAfterRead ?? this.burnAfterRead,
      burnAfterSeconds: burnAfterSeconds ?? this.burnAfterSeconds,
      burnLocked: burnLocked ?? this.burnLocked,
      burnCountdownSeconds: identical(burnCountdownSeconds, _messageItemUnset)
          ? this.burnCountdownSeconds
          : burnCountdownSeconds as int?,
      seq: seq ?? this.seq,
      reactions: reactions ?? this.reactions,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      contactUserId: contactUserId ?? this.contactUserId,
      contactName: contactName ?? this.contactName,
      contactAvatar: contactAvatar ?? this.contactAvatar,
      contactUsername: contactUsername ?? this.contactUsername,
      contactNicknameColor: contactNicknameColor ?? this.contactNicknameColor,
      contactEmojiAvatar: contactEmojiAvatar ?? this.contactEmojiAvatar,
      contactPremiumType: contactPremiumType ?? this.contactPremiumType,
      locationLatitude: locationLatitude ?? this.locationLatitude,
      locationLongitude: locationLongitude ?? this.locationLongitude,
      locationTitle: locationTitle ?? this.locationTitle,
      locationAddress: locationAddress ?? this.locationAddress,
    );
  }

  factory MessageItem.fromApiMessage(api.Message msg, String currentUserId) {
    final isOutgoing = msg.senderId == currentUserId;

    MessageItemType type = MessageItemType.text;
    String content = msg.content.text ?? '';
    String? mediaUrl;
    String? thumbnail;
    int? mediaWidth;
    int? mediaHeight;
    int? mediaSize;
    int? mediaDuration;
    String? fileName;
    double? locationLatitude;
    double? locationLongitude;
    String? locationTitle;
    String? locationAddress;

    switch (msg.type) {
      case 1:
        type = MessageItemType.text;
        break;
      case 2:
        type = MessageItemType.image;
        if (msg.content.media != null) {
          mediaUrl = ApiConfig.getMediaUrl(msg.content.media!.url);
          thumbnail = ApiConfig.getMediaUrl(msg.content.media!.thumbnail);
          mediaWidth = msg.content.media!.width;
          mediaHeight = msg.content.media!.height;
          mediaSize = msg.content.media!.size;
        }
        break;
      case 3:
        type = MessageItemType.video;
        if (msg.content.media != null) {
          mediaUrl = ApiConfig.getMediaUrl(msg.content.media!.url);
          thumbnail = ApiConfig.getMediaUrl(msg.content.media!.thumbnail);
          mediaWidth = msg.content.media!.width;
          mediaHeight = msg.content.media!.height;
          mediaSize = msg.content.media!.size;
          mediaDuration = msg.content.media!.duration;
        }
        break;
      case 4:
        type = MessageItemType.voice;
        if (msg.content.voice != null) {
          mediaUrl = ApiConfig.getMediaUrl(msg.content.voice!.url);
          mediaDuration = msg.content.voice!.duration;
          mediaSize = msg.content.voice!.size;
          content = msg.content.voice!.transcript ?? '';
        }
        break;
      case 5:
        type = MessageItemType.file;
        if (msg.content.file != null) {
          mediaUrl = ApiConfig.getMediaUrl(msg.content.file!.url);
          fileName = msg.content.file!.name;
          mediaSize = msg.content.file!.size;
        }
        break;
      case 6:
        type = MessageItemType.location;
        if (msg.content.location != null) {
          final location = msg.content.location!;
          locationLatitude = location.latitude;
          locationLongitude = location.longitude;
          locationTitle = location.title;
          locationAddress = location.address;
          content = location.title?.isNotEmpty == true
              ? location.title!
              : (location.address?.isNotEmpty == true
                    ? location.address!
                    : '位置');
        }
        break;
      case 10:
        type = MessageItemType.contact;
        if (msg.content.contact != null) {
          content = msg.content.contact!.nickname;
        }
        break;
      case 11:
        type = MessageItemType.call;
        break;
      case 12:
        type = MessageItemType.redPacket;
        break;
      case 13:
        type = MessageItemType.transfer;
        break;
      case 99:
        type = MessageItemType.system;
        break;
    }

    String? contactUserId;
    String? contactName;
    String? contactAvatar;
    String? contactUsername;
    String? contactNicknameColor;
    String? contactEmojiAvatar;
    String? contactPremiumType;
    if (msg.type == 10 && msg.content.contact != null) {
      contactUserId = msg.content.contact!.userId;
      contactName = msg.content.contact!.nickname;
      contactAvatar = msg.content.contact!.avatar;
      contactUsername = msg.content.contact!.username;
      contactNicknameColor = msg.content.contact!.nicknameColor;
      contactEmojiAvatar = msg.content.contact!.emojiAvatar;
      contactPremiumType = msg.content.contact!.premiumType;
    }

    ReplyInfo? replyTo;
    if (msg.replyTo != null) {
      replyTo = ReplyInfo(
        messageId: msg.replyTo!.msgId,
        senderName: msg.replyTo!.senderName,
        content: msg.replyTo!.content,
      );
    }

    final reactions = msg.reactions
        .map(
          (r) => MessageReaction(
            emoji: r.emoji,
            userId: r.userId,
            userName: r.userName,
            createdAt: r.createdAt,
          ),
        )
        .toList();

    return MessageItem(
      id: msg.msgId,
      chatId: msg.chatId,
      senderId: msg.senderId,
      senderName: msg.senderName,
      senderAvatar: msg.senderAvatar,
      senderNicknameColor: msg.senderNicknameColor,
      senderPremiumType: msg.senderPremiumType,
      senderEmojiAvatar: msg.senderEmojiAvatar,
      type: type,
      content: content,
      mediaUrl: mediaUrl,
      thumbnail: thumbnail,
      mediaWidth: mediaWidth,
      mediaHeight: mediaHeight,
      mediaSize: mediaSize,
      mediaDuration: mediaDuration,
      fileName: fileName,
      isOutgoing: isOutgoing,
      // status: 1=sent, 2=delivered, 3=read
      status: msg.status >= 3
          ? MessageStatus.read
          : (msg.status >= 2 ? MessageStatus.delivered : MessageStatus.sent),
      isRead: msg.status >= 3,
      replyTo: replyTo,
      createdAt: msg.createdAt,
      editedAt: msg.editedAt,
      isEdited: msg.isEdited,
      isDeleted: msg.isRevoked,
      revokedBy: msg.revokedBy,
      burnAfterRead: msg.burnAfterRead,
      burnAfterSeconds: msg.burnAfterSeconds,
      seq: msg.seq,
      reactions: reactions,
      contactUserId: contactUserId,
      contactName: contactName,
      contactAvatar: contactAvatar,
      contactUsername: contactUsername,
      contactNicknameColor: contactNicknameColor,
      contactEmojiAvatar: contactEmojiAvatar,
      contactPremiumType: contactPremiumType,
      locationLatitude: locationLatitude,
      locationLongitude: locationLongitude,
      locationTitle: locationTitle,
      locationAddress: locationAddress,
    );
  }

  /// Create a message item from a cached local [MessageModel].
  factory MessageItem.fromMessageModel(MessageModel m) {
    ReplyInfo? replyTo;
    if (m.replyToId != null && m.replyToId!.isNotEmpty) {
      replyTo = ReplyInfo(
        messageId: m.replyToId!,
        senderName: '',
        content: m.replyToPreview ?? '',
      );
    }

    List<MessageReaction> reactions = [];
    if (m.reactions != null && m.reactions!.isNotEmpty) {
      try {
        final list = jsonDecode(m.reactions!) as List;
        reactions = list.map((e) => MessageReaction.fromJson(e)).toList();
      } catch (_) {}
    }

    double? locationLatitude;
    double? locationLongitude;
    String? locationTitle;
    String? locationAddress;
    if (m.type == MsgType.location && m.content.isNotEmpty) {
      try {
        final data = jsonDecode(m.content) as Map<String, dynamic>;
        final lat = data['latitude'];
        final lng = data['longitude'];
        locationLatitude = lat is num
            ? lat.toDouble()
            : double.tryParse(lat?.toString() ?? '');
        locationLongitude = lng is num
            ? lng.toDouble()
            : double.tryParse(lng?.toString() ?? '');
        locationTitle = data['title']?.toString();
        locationAddress = data['address']?.toString();
      } catch (_) {}
    }

    return MessageItem(
      id: m.id,
      chatId: m.chatId,
      senderId: m.senderId,
      senderName: m.senderName,
      senderAvatar: m.senderAvatar,
      senderNicknameColor: m.senderNicknameColor,
      senderEmojiAvatar: m.senderEmojiAvatar,
      type: _msgTypeToItemType(m.type),
      content: m.content,
      mediaUrl: m.remoteUrl,
      thumbnail: m.thumbnail,
      mediaWidth: m.mediaWidth,
      mediaHeight: m.mediaHeight,
      mediaSize: m.mediaSize,
      mediaDuration: m.mediaDuration,
      fileName: m.fileName,
      isOutgoing: m.isOutgoing,
      status: _msgStatusToMessageStatus(m.status),
      isRead: m.isRead,
      replyTo: replyTo,
      createdAt: m.createdAt,
      editedAt: m.editedAt,
      isEdited: m.editedAt != null,
      isDeleted: m.isDeleted,
      burnAfterRead: m.burnAfterRead,
      burnAfterSeconds: m.burnAfterSeconds,
      seq: m.seq,
      reactions: reactions,
      contactUserId: m.contactUserId,
      contactName: m.contactName,
      contactAvatar: m.contactAvatar,
      contactUsername: m.contactUsername,
      locationLatitude: locationLatitude,
      locationLongitude: locationLongitude,
      locationTitle: locationTitle,
      locationAddress: locationAddress,
    );
  }

  bool get shouldHideBurnContent => burnAfterRead && burnLocked && !isOutgoing;
}

MsgType _itemTypeToStorageMsgType(MessageItemType type) {
  switch (type) {
    case MessageItemType.text:
      return MsgType.text;
    case MessageItemType.image:
      return MsgType.image;
    case MessageItemType.video:
      return MsgType.video;
    case MessageItemType.audio:
      return MsgType.audio;
    case MessageItemType.voice:
      return MsgType.voice;
    case MessageItemType.file:
      return MsgType.file;
    case MessageItemType.sticker:
      return MsgType.sticker;
    case MessageItemType.gif:
      return MsgType.gif;
    case MessageItemType.location:
      return MsgType.location;
    case MessageItemType.contact:
      return MsgType.contact;
    case MessageItemType.poll:
      return MsgType.poll;
    case MessageItemType.call:
      return MsgType.call;
    case MessageItemType.system:
      return MsgType.system;
    case MessageItemType.redPacket:
      return MsgType.redPacket;
    case MessageItemType.transfer:
      return MsgType.transfer;
  }
}

MsgStatus _itemStatusToStorageMsgStatus(MessageStatus status) {
  switch (status) {
    case MessageStatus.sending:
      return MsgStatus.sending;
    case MessageStatus.sent:
      return MsgStatus.sent;
    case MessageStatus.delivered:
      return MsgStatus.delivered;
    case MessageStatus.read:
      return MsgStatus.read;
    case MessageStatus.failed:
      return MsgStatus.failed;
  }
}

/// Persist messages to Isar for reuse by [MessageListNotifier] and chat preload flows.
Future<void> persistMessageItemsToIsarCache(List<MessageItem> messages) async {
  if (PlatformUtils.isWeb) return;
  if (messages.isEmpty) return;
  if (!IsarService.instance.isAvailable) return;
  try {
    final models = messages.map((msg) {
      final content = msg.type == MessageItemType.location
          ? jsonEncode({
              'latitude': msg.locationLatitude,
              'longitude': msg.locationLongitude,
              if (msg.locationTitle != null) 'title': msg.locationTitle,
              if (msg.locationAddress != null) 'address': msg.locationAddress,
            })
          : msg.content;
      return MessageModel()
        ..id = msg.id
        ..chatId = msg.chatId
        ..senderId = msg.senderId
        ..senderName = msg.senderName
        ..senderAvatar = msg.senderAvatar
        ..senderNicknameColor = msg.senderNicknameColor
        ..senderEmojiAvatar = msg.senderEmojiAvatar
        ..content = content
        ..type = _itemTypeToStorageMsgType(msg.type)
        ..seq = msg.seq
        ..localPath = null
        ..remoteUrl = msg.mediaUrl
        ..thumbnail = msg.thumbnail
        ..mediaWidth = msg.mediaWidth
        ..mediaHeight = msg.mediaHeight
        ..mediaSize = msg.mediaSize
        ..mediaDuration = msg.mediaDuration
        ..fileName = msg.fileName
        ..isOutgoing = msg.isOutgoing
        ..status = _itemStatusToStorageMsgStatus(msg.status)
        ..isRead = msg.isRead
        ..replyToId = msg.replyTo?.messageId
        ..replyToPreview = msg.replyTo?.content
        ..forwardFrom = null
        ..burnAfterRead = msg.burnAfterRead
        ..burnAfterSeconds = msg.burnAfterSeconds
        ..reactions = msg.reactions.isNotEmpty
            ? jsonEncode(msg.reactions.map((r) => r.toJson()).toList())
            : null
        ..contactUserId = msg.contactUserId
        ..contactName = msg.contactName
        ..contactAvatar = msg.contactAvatar
        ..contactUsername = msg.contactUsername
        ..createdAt = msg.createdAt
        ..editedAt = msg.editedAt
        ..isDeleted = msg.isDeleted;
    }).toList();

    await IsarService.instance.isar.writeTxn(() async {
      await IsarService.instance.isar.messageModels.putAll(models);
    });
  } catch (e) {
    if (kDebugMode) debugPrint('[IsarCache] persistMessageItemsToIsarCache failed: $e');
  }
}

class ReplyInfo {
  final String messageId;
  final String senderName;
  final String content;

  const ReplyInfo({
    required this.messageId,
    required this.senderName,
    required this.content,
  });
}

class MessageReaction {
  final String emoji;
  final String userId;
  final String userName;
  final DateTime createdAt;

  const MessageReaction({
    required this.emoji,
    required this.userId,
    required this.userName,
    required this.createdAt,
  });

  factory MessageReaction.fromJson(Map<String, dynamic> json) {
    return MessageReaction(
      emoji: json['emoji'] ?? '',
      userId: json['user_id'] ?? '',
      userName: json['user_name'] ?? '',
      createdAt: DateTime.tryParse(json['created_at'] ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'emoji': emoji,
    'user_id': userId,
    'user_name': userName,
    'created_at': createdAt.toIso8601String(),
  };
}

enum MessageItemType {
  text,
  image,
  video,
  audio,
  voice,
  file,
  sticker,
  gif,
  location,
  contact,
  poll,
  system,
  call,
  redPacket,
  transfer,
}

enum MessageStatus { sending, sent, delivered, read, failed }

MessageItemType _messageItemTypeFromApiType(int t) {
  switch (t) {
    case 1:
      return MessageItemType.text;
    case 2:
      return MessageItemType.image;
    case 3:
      return MessageItemType.video;
    case 4:
      return MessageItemType.voice;
    case 5:
      return MessageItemType.file;
    case 10:
      return MessageItemType.contact;
    case 11:
      return MessageItemType.call;
    case 12:
      return MessageItemType.redPacket;
    case 13:
      return MessageItemType.transfer;
    case 99:
      return MessageItemType.system;
    default:
      return MessageItemType.text;
  }
}

String? _walletMessageId(String content) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) {
      final id = decoded['id']?.toString().trim();
      if (id != null && id.isNotEmpty) return id;
    }
  } catch (_) {
    return null;
  }
  return null;
}

String? _walletMessageKey(MessageItem msg) {
  if (msg.type != MessageItemType.redPacket &&
      msg.type != MessageItemType.transfer) {
    return null;
  }
  final walletId = _walletMessageId(msg.content);
  if (walletId == null) return null;
  return '${msg.type.name}:$walletId';
}

final messageListProvider = StateNotifierProvider.family
    .autoDispose<MessageListNotifier, List<MessageItem>, String>((ref, chatId) {
      // Rebuild with the account uuid so keepAlive never holds the previous user context after account switching.
      // This keeps Isar/API identities aligned when ChatDetailPage triggers initialize() again via ref.listen.
      final currentUserId = ref.watch(
        authServiceProvider.select((state) => state.user?.uuid ?? ''),
      );

      final link = ref.keepAlive();
      Timer? timer;
      ref.onDispose(() => timer?.cancel());
      ref.onCancel(() {
        timer?.cancel();
        timer = Timer(const Duration(seconds: 8), () => link.close());
      });
      ref.onResume(() {
        timer?.cancel();
      });

      final chatService = ref.read(api.chatServiceProvider);
      final wsService = ref.read(webSocketServiceProvider.notifier);
      final apiClient = ref.read(apiClientProvider);
      return MessageListNotifier(
        chatId,
        chatService,
        wsService,
        apiClient,
        currentUserId,
      );
    });

class MessageListNotifier extends StateNotifier<List<MessageItem>> {
  final String chatId;
  final api.ChatService _chatService;
  final WebSocketService _wsService;
  final ApiClient _apiClient;
  final String _currentUserId;
  final _uuid = const Uuid();

  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isActive = false; // Whether the current chat page is active
  Set<String>? _cachedDeletedIds;
  Map<String, Map<String, dynamic>>? _cachedBurnState;
  final Map<String, Timer> _burnTimers = {};
  int? _lastSeq;
  bool _isSyncing = false;
  late final Function(dynamic) _newMessageHandler;
  late final Function(dynamic) _messageRevokedHandler;
  late final Function(dynamic) _readReceiptHandler;
  late final Function(dynamic) _reactionHandler;
  late final Function(dynamic) _messageEditedHandler;
  late final Function(dynamic) _reconnectedHandler;
  late final Function(dynamic) _chatHistoryClearedHandler;
  late final Function(dynamic) _messageBurnedHandler;

  MessageListNotifier(
    this.chatId,
    this._chatService,
    this._wsService,
    this._apiClient,
    this._currentUserId,
  ) : super([]) {
    _setupWebSocketHandlers();
  }

  void _setupWebSocketHandlers() {
    // Listen for new WebSocket messages, including call-related system messages.
    _newMessageHandler = (data) async {
      if (!mounted) return;
      final rawMsg = data['message'];
      if (rawMsg == null) return;
      if (rawMsg is! Map) {
        if (kDebugMode) debugPrint(
          '[Message] WS new_message: expected message object, got ${rawMsg.runtimeType}',
        );
        return;
      }
      try {
        final message = await _chatService.parseIncomingMessage(
          Map<String, dynamic>.from(rawMsg),
        );
        if (!mounted) return;
        if (message.chatId == chatId) {
          _addNewMessage(message);
          final item = MessageItem.fromApiMessage(message, _currentUserId);
          _saveMessagesToLocal([item]);
          if (message.type == 99) {
            _checkAndRefreshWalletBubbles(message);
          }
        }
      } catch (e, st) {
        if (kDebugMode) debugPrint('[Message] WS new_message fromJson failed: $e');
        debugPrintStack(stackTrace: st, maxFrames: 12);
      }
    };
    _wsService.registerHandler(WSMessageType.newMessage, _newMessageHandler);

    _messageRevokedHandler = (data) {
      if (!mounted) return;
      final msgId = data['msg_id']?.toString() ?? '';
      final msgChatId = data['chat_id']?.toString() ?? '';
      final revokerId = data['revoker_id']?.toString();
      if (msgChatId == chatId) {
        _markMessageAsRevokedBy(msgId, revokerId);
      }
    };
    _wsService.registerHandler(
      WSMessageType.messageRevoked,
      _messageRevokedHandler,
    );

    // Listen for read-receipt broadcasts from other users in the same chat.
    _readReceiptHandler = (data) {
      if (!mounted) return;
      final msgChatId = data['chat_id'] as String?;
      final readUserId = data['user_id'] as String?;
      final msgSeq = data['msg_seq'];
      // Ignore read receipts sent by the current user because SendToChat broadcasts to everyone.
      if (readUserId == _currentUserId) return;
      if (kDebugMode) debugPrint(
        '[Message] Received read receipt from $readUserId: chatId=$msgChatId, seq=$msgSeq',
      );
      if (msgChatId == chatId && msgSeq != null) {
        final seq = msgSeq is int
            ? msgSeq
            : int.tryParse(msgSeq.toString()) ?? 0;
        _markMessagesAsRead(seq);
      }
    };
    _wsService.registerHandler('read', _readReceiptHandler);
    _wsService.registerHandler(WSMessageType.readReceipt, _readReceiptHandler);

    _reactionHandler = (data) {
      if (!mounted) return;
      final msgChatId = data['chat_id'] as String?;
      if (msgChatId == chatId) {
        handleReactionEvent(data);
      }
    };
    _wsService.registerHandler(WSMessageType.reaction, _reactionHandler);

    _messageEditedHandler = (data) async {
      if (!mounted) return;
      final msgChatId = data['chat_id'] as String?;
      if (msgChatId == chatId) {
        final rawMsg = data['message'];
        if (rawMsg is Map) {
          try {
            final message = await _chatService.parseIncomingMessage(
              Map<String, dynamic>.from(rawMsg),
            );
            if (!mounted) return;
            _applyEditedMessage(message);
            return;
          } catch (e) {
            if (kDebugMode) debugPrint('[Message] parse edited message failed: $e');
          }
        }
        _handleMessageEdited(data);
      }
    };
    _wsService.registerHandler(
      WSMessageType.messageEdited,
      _messageEditedHandler,
    );

    _reconnectedHandler = (data) {
      if (!mounted) return;
      if (kDebugMode) debugPrint('[Message] Reconnected, starting delta sync for chat $chatId');
      _deltaSyncAfterReconnect();
    };
    _wsService.registerHandler(WSMessageType.reconnected, _reconnectedHandler);

    _wsService.registerHandler('admin_message_delete', (data) {
        final msgId = data['msg_id']?.toString() ?? '';
        state = state.where((msg) => msg.id != msgId).toList();
      });

    _chatHistoryClearedHandler = (data) {
      if (!mounted) return;
      final msgChatId = data['chat_id']?.toString();
      if (msgChatId != chatId) return;
      if (kDebugMode) debugPrint('[Message] Chat history cleared event: chatId=$chatId');
      unawaited(_clearHistoryFromEvent());
    };
    _wsService.registerHandler(
      WSMessageType.chatHistoryCleared,
      _chatHistoryClearedHandler,
    );

    _messageBurnedHandler = (data) {
      if (!mounted) return;
      final msgChatId = data['chat_id']?.toString();
      final userId = data['user_id']?.toString();
      final msgSeq = (data['msg_seq'] as num?)?.toInt() ?? 0;
      if (msgChatId != chatId || userId != _currentUserId || msgSeq <= 0) {
        return;
      }
      _lockIncomingBurnMessagesUpToSeq(msgSeq);
    };
    _wsService.registerHandler('message_burned', _messageBurnedHandler);
  }

  @override
  void dispose() {
    for (final timer in _burnTimers.values) {
      timer.cancel();
    }
    _burnTimers.clear();
    _wsService.removeSpecificHandler(
      WSMessageType.newMessage,
      _newMessageHandler,
    );
    _wsService.removeSpecificHandler(
      WSMessageType.messageRevoked,
      _messageRevokedHandler,
    );
    _wsService.removeSpecificHandler('read', _readReceiptHandler);
    _wsService.removeSpecificHandler(
      WSMessageType.readReceipt,
      _readReceiptHandler,
    );
    _wsService.removeSpecificHandler(WSMessageType.reaction, _reactionHandler);
    _wsService.removeSpecificHandler(
      WSMessageType.messageEdited,
      _messageEditedHandler,
    );
    _wsService.removeSpecificHandler(
      WSMessageType.reconnected,
      _reconnectedHandler,
    );
    _wsService.removeSpecificHandler(
      WSMessageType.chatHistoryCleared,
      _chatHistoryClearedHandler,
    );
    _wsService.removeSpecificHandler('message_burned', _messageBurnedHandler);
    super.dispose();
  }

  int? revealBurnMessage(String messageId) {
    final message = state.cast<MessageItem?>().firstWhere(
      (msg) => msg?.id == messageId,
      orElse: () => null,
    );
    if (message == null || !message.shouldHideBurnContent) {
      return null;
    }

    return _startBurnCountdown(message, unlockContent: true);
  }

  int _startBurnCountdown(MessageItem message, {required bool unlockContent}) {
    final messageId = message.id;
    final seconds =
        (message.burnCountdownSeconds != null &&
            message.burnCountdownSeconds! > 0)
        ? message.burnCountdownSeconds!
        : (message.burnAfterSeconds > 0 ? message.burnAfterSeconds : 10);

    _burnTimers.remove(messageId)?.cancel();

    state = state.map((msg) {
      if (msg.id != messageId) return msg;
      return msg.copyWith(
        burnLocked: unlockContent ? false : msg.burnLocked,
        burnCountdownSeconds: seconds,
      );
    }).toList();

    final updated = state.cast<MessageItem?>().firstWhere(
      (msg) => msg?.id == messageId,
      orElse: () => null,
    );
    if (updated != null) {
      unawaited(_saveMessagesToLocal([updated]));
      unawaited(_persistBurnState(updated));
    }

    _burnTimers[messageId] = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      final current = state.cast<MessageItem?>().firstWhere(
        (msg) => msg?.id == messageId,
        orElse: () => null,
      );
      if (current == null) {
        timer.cancel();
        _burnTimers.remove(messageId);
        return;
      }

      final remaining = current.burnCountdownSeconds ?? 0;
      if (remaining <= 1) {
        timer.cancel();
        _burnTimers.remove(messageId);
        unawaited(deleteMessage(messageId));
        return;
      }

      state = state.map((msg) {
        if (msg.id != messageId) return msg;
        return msg.copyWith(burnCountdownSeconds: remaining - 1);
      }).toList();

      final next = state.cast<MessageItem?>().firstWhere(
        (msg) => msg?.id == messageId,
        orElse: () => null,
      );
      if (next != null) {
        unawaited(_persistBurnState(next));
      }
    });

    return seconds;
  }

  void _reconcileBurnStateFromCurrentMessages() {
    if (!mounted || state.isEmpty) {
      return;
    }

    var lockedIncomingChanged = false;
    final nextState = state.map((msg) {
      final shouldLockIncoming =
          msg.burnAfterRead &&
          !msg.isOutgoing &&
          msg.status == MessageStatus.read &&
          !msg.burnLocked &&
          (msg.burnCountdownSeconds == null || msg.burnCountdownSeconds! <= 0);
      if (!shouldLockIncoming) {
        return msg;
      }
      lockedIncomingChanged = true;
      return msg.copyWith(burnLocked: true, burnCountdownSeconds: null);
    }).toList();

    if (lockedIncomingChanged) {
      state = nextState;
      final burnMessages = state.where((msg) => msg.burnAfterRead).toList();
      if (burnMessages.isNotEmpty) {
        unawaited(_saveMessagesToLocal(burnMessages));
        unawaited(_persistBurnStates(burnMessages));
      }
    }

    for (final msg in state) {
      final shouldResumeCountdown =
          msg.burnAfterRead &&
          (msg.burnCountdownSeconds != null && msg.burnCountdownSeconds! > 0);
      if (shouldResumeCountdown) {
        _startBurnCountdown(msg, unlockContent: false);
        continue;
      }

      final shouldStartOutgoingCountdown =
          msg.burnAfterRead &&
          msg.isOutgoing &&
          msg.status == MessageStatus.read &&
          (msg.burnCountdownSeconds == null || msg.burnCountdownSeconds! <= 0);
      if (!shouldStartOutgoingCountdown) {
        continue;
      }
      _startBurnCountdown(msg, unlockContent: false);
    }
  }

  Future<void> _clearHistoryFromEvent() async {
    if (!mounted) return;

    state = [];
    _lastSeq = null;
    _hasMore = true;
    _cachedDeletedIds = null;
    await _clearBurnStateMap();

    if (PlatformUtils.isWeb || !IsarService.instance.isAvailable) {
      return;
    }

    try {
      await IsarService.instance.isar.writeTxn(() async {
        await IsarService.instance.isar.messageModels
            .filter()
            .chatIdEqualTo(chatId)
            .deleteAll();
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Message] Clear local history failed: $e');
    }
  }

  void _markMessagesAsRead(int seq) {
    if (!mounted || seq <= 0) return;

    bool hasChanges = false;
    for (final msg in state) {
      if (msg.seq > 0 &&
          msg.seq <= seq &&
          msg.isOutgoing &&
          msg.status != MessageStatus.read) {
        hasChanges = true;
        break;
      }
    }

    // Return early when nothing changed.
    if (!hasChanges) return;

    int updatedCount = 0;
    state = state.map((msg) {
      if (msg.seq > 0 &&
          msg.seq <= seq &&
          msg.isOutgoing &&
          msg.status != MessageStatus.read) {
        updatedCount++;
        return msg.copyWith(status: MessageStatus.read, isRead: true);
      }
      return msg;
    }).toList();
    if (kDebugMode) debugPrint(
      '[Message] Updated $updatedCount messages to read status (up to seq=$seq)',
    );

    // Persist read status locally
    final readMsgs = state
        .where((m) => m.isOutgoing && m.seq > 0 && m.seq <= seq)
        .toList();
    if (readMsgs.isNotEmpty) {
      _saveMessagesToLocal(readMsgs);
    }

    for (final msg in readMsgs) {
      final shouldStartBurnCountdown =
          msg.burnAfterRead &&
          (msg.burnCountdownSeconds == null || msg.burnCountdownSeconds! <= 0);
      if (!shouldStartBurnCountdown) {
        continue;
      }
      _startBurnCountdown(msg, unlockContent: false);
    }
  }

  void _lockIncomingBurnMessagesUpToSeq(int seq) {
    if (!mounted || seq <= 0) return;

    var changed = false;
    state = state.map((msg) {
      if (msg.isOutgoing || msg.seq <= 0 || msg.seq > seq) {
        return msg;
      }

      final shouldMarkRead = msg.status != MessageStatus.read || !msg.isRead;
      final shouldLockBurn =
          msg.burnAfterRead &&
          !msg.burnLocked &&
          (msg.burnCountdownSeconds == null || msg.burnCountdownSeconds! <= 0);

      if (!shouldMarkRead && !shouldLockBurn) {
        return msg;
      }

      changed = true;
      return msg.copyWith(
        status: shouldMarkRead ? MessageStatus.read : null,
        isRead: shouldMarkRead ? true : null,
        burnLocked: shouldLockBurn ? true : null,
        burnCountdownSeconds: shouldLockBurn ? null : _messageItemUnset,
      );
    }).toList();

    if (!changed) {
      return;
    }

    final updatedMessages = state
        .where((msg) => !msg.isOutgoing && msg.seq > 0 && msg.seq <= seq)
        .toList();
    if (updatedMessages.isEmpty) {
      return;
    }

    unawaited(_saveMessagesToLocal(updatedMessages));
    final burnMessages = updatedMessages
        .where((msg) => msg.burnAfterRead)
        .toList();
    if (burnMessages.isNotEmpty) {
      unawaited(_persistBurnStates(burnMessages));
    }
  }

  void _markAsReadUpToSeq(int seq) {
    if (seq <= 0) return;
    _lockIncomingBurnMessagesUpToSeq(seq);
    unawaited(_chatService.markAsRead(chatId, msgSeq: seq));
  }

  void _addNewMessage(api.Message message) {
    if (!mounted) return;

    final existingIndex = state.indexWhere((msg) => msg.id == message.msgId);
    if (existingIndex >= 0) {
      final existing = state[existingIndex];
      final item = MessageItem.fromApiMessage(message, _currentUserId);
      final shouldUpdateExisting =
          existing.seq <= 0 ||
          existing.status == MessageStatus.sending ||
          existing.status == MessageStatus.failed;

      if (shouldUpdateExisting) {
        final displayItem = item.copyWith(createdAt: existing.createdAt);
        state = state.map((msg) {
          if (msg.id == message.msgId) {
            return displayItem;
          }
          return msg;
        }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _saveMessagesToLocal([displayItem]);
        if (_isActive) {
          _markAsReadUpToSeq(message.seq);
        }
        if (kDebugMode) debugPrint(
          '[Message] Updated existing message from WS echo: ${message.msgId}',
        );
        return;
      }

      if (kDebugMode) debugPrint('[Message] Skip duplicate message: ${message.msgId}');
      return;
    }

    // Handle WebSocket echoes from messages sent by the current user.
    // For self-sent messages echoed back by WebSocket, try to align them with local optimistic items first.
    if (message.senderId == _currentUserId) {
      final now = DateTime.now();
      const echoAlignSecs = 5;
      if (message.type == 1) {
        final t = message.content.text ?? '';
        final mergeIdx = state.indexWhere(
          (msg) =>
              msg.senderId == _currentUserId &&
              msg.status == MessageStatus.sending &&
              msg.type == MessageItemType.text &&
              msg.content == t &&
              now.difference(msg.createdAt).inSeconds < 15 &&
              message.createdAt.difference(msg.createdAt).abs().inSeconds <=
                  echoAlignSecs,
        );
        if (mergeIdx >= 0) {
          final localId = state[mergeIdx].id;
          final item = MessageItem.fromApiMessage(message, _currentUserId);
          state = [item, ...state.where((m) => m.id != localId)];
          if (_isActive) {
            _markAsReadUpToSeq(message.seq);
          }
          _persistMessageUpdate(localId, item);
          if (kDebugMode) debugPrint(
            '[Message] Merged WS text into optimistic row: ${message.msgId}',
          );
          return;
        }
      } else {
        final incomingItemType = _messageItemTypeFromApiType(message.type);
        if (incomingItemType == MessageItemType.redPacket ||
            incomingItemType == MessageItemType.transfer) {
          final incomingWalletId = _walletMessageId(message.content.text ?? '');
          if (incomingWalletId != null) {
            final mergeIdx = state.indexWhere(
              (msg) =>
                  msg.senderId == _currentUserId &&
                  msg.type == incomingItemType &&
                  _walletMessageId(msg.content) == incomingWalletId,
            );
            if (mergeIdx >= 0) {
              final localId = state[mergeIdx].id;
              final item = MessageItem.fromApiMessage(message, _currentUserId);
              state = [item, ...state.where((m) => m.id != localId)];
              if (_isActive) {
                _markAsReadUpToSeq(message.seq);
              }
              _persistMessageUpdate(localId, item);
              if (kDebugMode) debugPrint(
                '[Message] Merged WS wallet message into local row: ${message.msgId}',
              );
              return;
            }
          }
        }
        if (incomingItemType != MessageItemType.text) {
          final mergeIdx = state.indexWhere(
            (msg) =>
                msg.senderId == _currentUserId &&
                (msg.status == MessageStatus.sending ||
                    msg.status == MessageStatus.failed) &&
                msg.type == incomingItemType &&
                now.difference(msg.createdAt).inSeconds < 15 &&
                message.createdAt.difference(msg.createdAt).abs().inSeconds <=
                    echoAlignSecs,
          );
          if (mergeIdx >= 0) {
            final localId = state[mergeIdx].id;
            final item = MessageItem.fromApiMessage(message, _currentUserId);
            state = [item, ...state.where((m) => m.id != localId)];
            if (_isActive) {
              _markAsReadUpToSeq(message.seq);
            }
            _persistMessageUpdate(localId, item);
            if (kDebugMode) debugPrint(
              '[Message] Merged WS non-text into optimistic row: ${message.msgId}',
            );
            return;
          }
        }
      }
    }

    final item = MessageItem.fromApiMessage(message, _currentUserId);
    state = [item, ...state];

    // Send read receipts only when the current chat page is active.
    if (_isActive) {
      _markAsReadUpToSeq(message.seq);
    }
  }

  void _checkAndRefreshWalletBubbles(api.Message sysMsg) {
    try {
      final text = sysMsg.content.text ?? '';
      // Parse system message text. It may be wrapped in JSON.
      String displayText = text;
      if (text.startsWith('{')) {
        try {
          final json = jsonDecode(text);
          displayText = json['text'] ?? json['content'] ?? text;
        } catch (_) {}
      }
      if (displayText.contains('领取了红包') ||
          displayText.contains('已收款') ||
          displayText.contains('已退款') ||
          displayText.contains('已拒收') ||
          displayText.contains('红包已过期') ||
          displayText.contains('转账已过期')) {
        if (kDebugMode) debugPrint(
          '[Message] Wallet status change detected, refreshing bubbles',
        );
        WalletBubbleRefreshNotifier.instance.refresh();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Message] _checkAndRefreshWalletBubbles error: $e');
    }
  }

  void _markMessageAsRevokedBy(String msgId, String? revokerId) {
    if (!mounted) return;
    state = state.map((msg) {
      if (msg.id == msgId) {
        return msg.copyWith(
          isDeleted: true,
          content: '此消息已撤回',
          revokedBy: revokerId,
        );
      }
      return msg;
    }).toList();
  }

  void _markMessageAsRevoked(String msgId) =>
      _markMessageAsRevokedBy(msgId, null);

  /// Track whether the user is actively viewing this chat page.
  /// Read receipts are only sent while the page is active.
  void setActive(bool active) {
    final wasInactive = !_isActive && active;
    _isActive = active;
    // When becoming active again, run a delta sync to catch up after reconnect.
    if (wasInactive && state.isNotEmpty) {
      Future.microtask(_deltaSyncAfterReconnect);
    }
  }

  Future<void> initialize() async {
    _isActive = true;
    await loadMessages();
  }

  Future<void> _deltaSyncAfterReconnect() async {
    if (!mounted || _isSyncing) return;
    _isSyncing = true;

    try {
      int maxSeq = 0;
      for (final msg in state) {
        if (msg.seq > maxSeq) maxSeq = msg.seq;
      }

      // If seq is still missing, fall back to a full message reload.
      if (maxSeq == 0) {
        if (kDebugMode) debugPrint('[Message] Delta sync: no seq yet, fallback to full load');
        await loadMessages();
        return;
      }

      if (kDebugMode) debugPrint('[Message] Delta sync: chatId=$chatId, lastSeq=$maxSeq');

      final deletedFuture = _getDeletedMessageIds();
      final response = await _chatService.syncMessages(chatId, lastSeq: maxSeq);
      if (!mounted) return;

      if (!response.isSuccess ||
          response.data == null ||
          response.data!.isEmpty) {
        await deletedFuture;
        return;
      }

      final deletedIds = await deletedFuture;

      final newMessages = response.data!
          .map<MessageItem>(
            (msg) => MessageItem.fromApiMessage(msg, _currentUserId),
          )
          .where((msg) => !deletedIds.contains(msg.id))
          .toList();

      if (newMessages.isEmpty) return;

      if (kDebugMode) debugPrint(
        '[Message] Delta sync: got ${newMessages.length} new messages',
      );

      // Merge by message id so only truly new messages are inserted.
      final existingIds = state.map((m) => m.id).toSet();
      final trulyNew = newMessages
          .where((m) => !existingIds.contains(m.id))
          .toList();

      if (trulyNew.isNotEmpty) {
        trulyNew.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        state = _dedupeWalletMessages([...trulyNew, ...state]);
        _reconcileBurnStateFromCurrentMessages();

        // Save the new messages locally.
        _saveMessagesToLocal(trulyNew);

        // Only send read receipts while the chat page is active.
        if (_isActive) {
          final latestSeq = trulyNew
              .map((m) => m.seq)
              .reduce((a, b) => a > b ? a : b);
          _markAsReadUpToSeq(latestSeq);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Message] Delta sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _loadFromLocal() async {
    if (PlatformUtils.isWeb) return;

    try {
      await _getBurnStateMap();
      final list = await IsarService.instance.isar.messageModels
          .filter()
          .chatIdEqualTo(chatId)
          .sortByCreatedAtDesc()
          .limit(50)
          .findAll();
      if (list.isEmpty || !mounted) return;

      final seen = <String>{};
      final deduped = <MessageModel>[];
      for (final m in list) {
        if (seen.add(m.id)) {
          deduped.add(m);
        }
      }

      final parsedItems = deduped.map((m) {
        var item = MessageItem.fromMessageModel(m);
        item = _applyPersistedBurnState(item);
        if (item.type == MessageItemType.text && item.content.startsWith('{')) {
          try {
            final json = jsonDecode(item.content) as Map<String, dynamic>;
            if (json.containsKey('total_amount') ||
                json.containsKey('red_packet_id')) {
              item = item.copyWith(type: MessageItemType.redPacket);
            } else if (json.containsKey('receiver_id') &&
                json.containsKey('amount')) {
              item = item.copyWith(type: MessageItemType.transfer);
            }
          } catch (_) {}
        }
        if (item.status == MessageStatus.sending) {
          final age = DateTime.now().difference(item.createdAt);
          if (age.inMinutes >= 2) {
            item = item.copyWith(status: MessageStatus.failed);
          }
        }
        return item;
      }).toList();
      final items = _dedupeWalletMessages(parsedItems);
      if (mounted) {
        state = _mergeLoadedMessages(items);
        _reconcileBurnStateFromCurrentMessages();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Message] Failed to load from local: $e');
    }
  }

  List<MessageItem> _dedupeWalletMessages(List<MessageItem> messages) {
    final byWalletKey = <String, MessageItem>{};
    final result = <MessageItem>[];

    for (final msg in messages) {
      final key = _walletMessageKey(msg);
      if (key == null) {
        result.add(msg);
        continue;
      }

      final existing = byWalletKey[key];
      if (existing == null) {
        byWalletKey[key] = msg;
        result.add(msg);
        continue;
      }

      final preferIncoming =
          msg.seq > existing.seq ||
          (existing.id.startsWith('local_') && !msg.id.startsWith('local_'));
      if (preferIncoming) {
        final index = result.indexWhere((item) => identical(item, existing));
        if (index >= 0) {
          result[index] = msg;
        }
        byWalletKey[key] = msg;
      }
    }

    return result;
  }

  List<MessageItem> _mergeLoadedMessages(List<MessageItem> loadedMessages) {
    if (state.isEmpty) return _dedupeWalletMessages(loadedMessages);

    final loadedIds = loadedMessages.map((m) => m.id).toSet();
    final loadedWalletKeys = loadedMessages
        .map(_walletMessageKey)
        .whereType<String>()
        .toSet();
    DateTime? newestLoadedTime;
    for (final msg in loadedMessages) {
      if (newestLoadedTime == null || msg.createdAt.isAfter(newestLoadedTime)) {
        newestLoadedTime = msg.createdAt;
      }
    }

    final now = DateTime.now();
    final transientMessages = state.where((msg) {
      if (loadedIds.contains(msg.id)) return false;
      final walletKey = _walletMessageKey(msg);
      if (walletKey != null && loadedWalletKeys.contains(walletKey)) {
        return false;
      }
      // 发送中/失败的消息始终保留
      if (msg.status == MessageStatus.sending ||
          msg.status == MessageStatus.failed) {
        return true;
      }
      // 2分钟内本地已发送成功的消息也保留，防止服务端时间戳精度差异导致消息消失
      if (msg.isOutgoing &&
          msg.status == MessageStatus.sent &&
          now.difference(msg.createdAt).inMinutes < 2) {
        return true;
      }
      if (newestLoadedTime != null && msg.createdAt.isAfter(newestLoadedTime)) {
        return true;
      }
      return false;
    }).toList();

    final merged = [...transientMessages, ...loadedMessages];
    merged.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return _dedupeWalletMessages(merged);
  }

  /// Load messages from the server while showing cached local messages first.
  Future<void> loadMessages() async {
    if (!mounted) return;

    try {
      // Run local cache loading and server fetching in parallel.
      final localFuture = _loadFromLocal();
      final burnStateFuture = _getBurnStateMap();
      final deletedIdsFuture = _getDeletedMessageIds();
      final serverFuture = _chatService.getMessages(chatId, limit: 30);

      await Future.wait([localFuture, burnStateFuture]);

      final results = await Future.wait([deletedIdsFuture, serverFuture]);
      final deletedIds = results[0] as Set<String>;
      final response = results[1] as dynamic;

      if (!mounted) return;

      if (response.isSuccess && response.data != null) {
        // Keep local timestamps so server createdAt values do not reorder failed local messages.
        final localTimeMap = <String, DateTime>{};
        for (final msg in state) {
          localTimeMap[msg.id] = msg.createdAt;
        }

        final List<MessageItem> messages = response.data!
            .map<MessageItem>((msg) {
              final item = _applyPersistedBurnState(
                MessageItem.fromApiMessage(msg, _currentUserId),
              );
              final localTime = localTimeMap[item.id];
              if (localTime != null) {
                return item.copyWith(createdAt: localTime);
              }
              return item;
            })
            .where((msg) => !deletedIds.contains(msg.id))
            .toList();

        state = _mergeLoadedMessages(messages);
        _reconcileBurnStateFromCurrentMessages();
        _hasMore = messages.length >= 30;
        _lastSeq = messages.isNotEmpty ? messages.last.seq : null;

        // Only send read receipts while the chat page is active.
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!mounted) return;
          _saveMessagesToLocal(messages);
        });

        _prefetchMediaThumbnails(messages.take(5).toList());

        // Save to local storage with a small delay to avoid blocking the UI thread.
        if (_isActive && messages.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (!mounted) return;
            final maxSeq = messages.first.seq;
            _markAsReadUpToSeq(maxSeq);
            // 双保险:进会话后追加一次纯拉平调用(不传 msgSeq),
            // 让后端用 Redis last_seq 把系统消息等未进列表的消息也覆盖,避免重开冒未读
            unawaited(_chatService.markAsRead(chatId));
          });
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Message] loadMessages error: $e');
    }
  }

  /// Prefetch media thumbnails without affecting first paint.
  void _prefetchMediaThumbnails(List<MessageItem> messages) async {
    // Wait briefly so the UI can render before prefetching.
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    int prefetchCount = 0;
    const maxPrefetch = 5; // Prefetch up to 5 media items

    for (final msg in messages) {
      if (!mounted) break;

      String? imageUrl;

      if (msg.type == MessageItemType.image && msg.mediaUrl != null) {
        imageUrl = msg.mediaUrl;
      } else if (msg.type == MessageItemType.video && msg.thumbnail != null) {
        imageUrl = msg.thumbnail;
      }

      if (imageUrl == null || imageUrl.isEmpty) continue;

      if (imageUrl.startsWith('/uploads')) {
        imageUrl = '${ApiConfig.serverUrl}$imageUrl';
      } else if (!imageUrl.startsWith('http') && !imageUrl.startsWith('/')) {
        imageUrl = '${ApiConfig.serverUrl}/$imageUrl';
      }

      if (!imageUrl.startsWith('http')) continue;

      try {
        CachedNetworkImageProvider(
          imageUrl,
        ).resolve(const ImageConfiguration());
        prefetchCount++;
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        if (kDebugMode) debugPrint('[Message] Failed to prefetch image: $e');
      }
    }
  }

  Future<void> loadMoreMessages() async {
    if (!mounted || _isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;

    try {
      final deletedFuture = _getDeletedMessageIds();
      final response = await _chatService.getMessages(
        chatId,
        beforeSeq: _lastSeq,
        limit: 30,
      );

      if (!mounted) return;

      final deletedIds = await deletedFuture;

      if (response.isSuccess && response.data != null) {
        final List<MessageItem> messages = response.data!
            .map<MessageItem>(
              (msg) => MessageItem.fromApiMessage(msg, _currentUserId),
            )
            .where((msg) => !deletedIds.contains(msg.id))
            .toList();

        messages.sort((a, b) => b.createdAt.compareTo(a.createdAt));

        final existingIds = state.map((m) => m.id).toSet();
        final existingWalletKeys = state
            .map(_walletMessageKey)
            .whereType<String>()
            .toSet();
        final uniqueMessages = messages.where((msg) {
          if (existingIds.contains(msg.id)) return false;
          final walletKey = _walletMessageKey(msg);
          if (walletKey != null && existingWalletKeys.contains(walletKey)) {
            return false;
          }
          return true;
        }).toList();

        if (uniqueMessages.isNotEmpty) {
          state = [...state, ...uniqueMessages]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _reconcileBurnStateFromCurrentMessages();
        }
        _hasMore = messages.length >= 30;
        _lastSeq = messages.isNotEmpty ? messages.last.seq : _lastSeq;

        _saveMessagesToLocal(uniqueMessages);
      } else {
        _hasMore = false;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Message] loadMoreMessages failed: $e');
      _hasMore = false;
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> _saveMessagesToLocal(List<MessageItem> messages) async {
    await persistMessageItemsToIsarCache(messages);
  }

  /// Send a text message.
  /// Returns null on success or when the message is queued offline.
  Future<String?> sendTextMessage(
    String text, {
    ReplyInfo? replyTo,
    List<String>? mentions,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
  }) async {
    // If offline, queue the message locally first.
    final offlineQueue = OfflineMessageQueue();
    if (!offlineQueue.isOnline) {
      final localId = _uuid.v4();
      final message = MessageItem(
        id: localId,
        chatId: chatId,
        senderId: _currentUserId,
        senderName: '我',
        type: MessageItemType.text,
        content: text,
        isOutgoing: true,
        status: MessageStatus.sending,
        replyTo: replyTo,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
        createdAt: DateTime.now(),
      );
      state = [message, ...state];
      // Persist the local placeholder before enqueueing offline.
      _saveMessagesToLocal([message]);

      await offlineQueue.enqueue(
        OfflineMessage(
          id: localId,
          chatId: chatId,
          type: OfflineMessageType.text,
          content: text,
          createdAt: DateTime.now(),
        ),
      );
      if (kDebugMode) debugPrint('[Message] Offline, queued text message: $localId');
      return null;
    }

    final localId = _uuid.v4();
    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: '我',
      type: MessageItemType.text,
      content: text,
      isOutgoing: true,
      status: MessageStatus.sending,
      replyTo: replyTo,
      burnAfterRead: burnAfterRead,
      burnAfterSeconds: burnAfterSeconds,
      createdAt: DateTime.now(),
    );

    state = [message, ...state];
    // Persist the optimistic sending state locally.
    _saveMessagesToLocal([message]);

    // Send the message to the server.
    try {
      api.ReplyInfo? apiReplyTo;
      if (replyTo != null) {
        apiReplyTo = api.ReplyInfo(
          msgId: replyTo.messageId,
          senderId: '',
          senderName: replyTo.senderName,
          content: replyTo.content,
        );
      }

      final response = await _chatService.sendMessage(
        chatId: chatId,
        type: 1,
        content: api.MessageContent(text: text),
        msgId: localId,
        replyTo: apiReplyTo,
        mentions: (mentions != null && mentions.isNotEmpty) ? mentions : null,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
      );

      if (response.isSuccess && response.data != null) {
        // Update the local message id, status, and seq after the server acknowledges it.
        _updateLocalMessage(
          localId,
          response.data!.msgId,
          MessageStatus.sent,
          seq: response.data!.seq,
        );
        return null;
      } else {
        if (kDebugMode) debugPrint(
          '[Message] sendMessage failed: code=${response.code} message=${response.message} dataNull=${response.data == null}',
        );
        // Server-side rejections are final business errors. Do not put them
        // into the offline queue, otherwise muted/blocked/expired-login sends
        // look like they are silently stuck and get retried pointlessly.
        if (response.code > 0) {
          state = state.where((m) => m.id != localId).toList();
          return response.message.isNotEmpty ? response.message : '发送失败，请稍后再试';
        }
        _updateMessageStatus(localId, MessageStatus.failed);
        // Queue the message offline again after a normal send failure.
        await offlineQueue.enqueue(
          OfflineMessage(
            id: localId,
            chatId: chatId,
            type: OfflineMessageType.text,
            content: text,
            createdAt: DateTime.now(),
          ),
        );
        return null;
      }
    } catch (e, st) {
      if (kDebugMode) debugPrint('[Message] sendMessage exception: $e');
      debugPrintStack(stackTrace: st, maxFrames: 6);
      _updateMessageStatus(localId, MessageStatus.failed);
      // Also queue the message offline when an exception happens.
      await offlineQueue.enqueue(
        OfflineMessage(
          id: localId,
          chatId: chatId,
          type: OfflineMessageType.text,
          content: text,
          createdAt: DateTime.now(),
        ),
      );
      return null;
    }
  }

  /// Send an image message.
  ///
  /// [localPath] Local image path.
  /// [width] Image width.
  /// [height] Image height.
  /// [skipCompress] Whether to skip compression. Defaults to false.
  Future<void> sendImageMessage(
    String localPath, {
    int? width,
    int? height,
    bool skipCompress = false,
    String? caption,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
  }) async {
    // On web, read the local file bytes directly and send them.
    if (PlatformUtils.isWeb) {
      final xfile = XFile(localPath);
      final bytes = await xfile.readAsBytes();
      if (bytes.isNotEmpty) {
        await sendImageFromBytes(
          bytes,
          caption: caption,
          burnAfterRead: burnAfterRead,
          burnAfterSeconds: burnAfterSeconds,
        );
      }
      return;
    }

    final localId = _uuid.v4();
    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: '我',
      type: MessageItemType.image,
      content: caption ?? '',
      mediaUrl: localPath,
      mediaWidth: width,
      mediaHeight: height,
      isOutgoing: true,
      status: MessageStatus.sending,
      burnAfterRead: burnAfterRead,
      burnAfterSeconds: burnAfterSeconds,
      createdAt: DateTime.now(),
    );

    state = [message, ...state];
    Future.microtask(() => _saveMessagesToLocal([message]));

    try {
      String uploadPath = localPath;
      if (!skipCompress) {
        uploadPath = await ImageCompressUtil.compressImage(localPath);
      }

      final file = File(uploadPath);
      if (!await file.exists()) {
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final fileSize = await file.length();
      final ext = uploadPath.split('.').last.toLowerCase();
      final mimeType = _getMimeType(ext);

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          uploadPath,
          filename: 'image_${DateTime.now().millisecondsSinceEpoch}.$ext',
        ),
      });

      final uploadResponse = await _apiClient.upload<Map<String, dynamic>>(
        '/upload/image',
        formData,
      );

      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        if (kDebugMode) debugPrint('[Image] Upload failed: ${uploadResponse.message}');
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final imageUrl = ApiConfig.getMediaUrl(
        uploadResponse.data!['url'] as String?,
      );

      final sendResponse = await _chatService.sendMessage(
        chatId: chatId,
        type: 2, // image type
        content: api.MessageContent(
          text: (caption != null && caption.isNotEmpty) ? caption : null,
          media: api.MediaInfo(
            url: imageUrl,
            width: width,
            height: height,
            size: fileSize,
            mimeType: mimeType,
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
      );

      if (sendResponse.isSuccess && sendResponse.data != null) {
        final serverMsg = sendResponse.data!;
        MessageItem? updated;
        state = state.map((msg) {
          if (msg.id == localId) {
            updated = msg.copyWith(
              id: serverMsg.msgId,
              mediaUrl: imageUrl,
              mediaSize: fileSize,
              content: caption ?? '',
              status: MessageStatus.sent,
              seq: serverMsg.seq,
            );
            return updated!;
          }
          return msg;
        }).toList();
        if (updated != null) _persistMessageUpdate(localId, updated!);
      } else {
        _updateMessageStatus(localId, MessageStatus.failed);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Image] Send error: $e');
      _updateMessageStatus(localId, MessageStatus.failed);
    }
  }

  Future<void> sendImageFromBytes(
    Uint8List bytes, {
    String ext = 'png',
    String? caption,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
  }) async {
    final localId = _uuid.v4();

    final base64Str = 'data:image/$ext;base64,${base64Encode(bytes)}';

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: '我',
      type: MessageItemType.image,
      content: caption ?? '',
      mediaUrl: base64Str,
      isOutgoing: true,
      status: MessageStatus.sending,
      burnAfterRead: burnAfterRead,
      burnAfterSeconds: burnAfterSeconds,
      createdAt: DateTime.now(),
    );

    state = [message, ...state];

    try {
      final mimeType = 'image/$ext';
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: 'paste_${DateTime.now().millisecondsSinceEpoch}.$ext',
          contentType: DioMediaType.parse(mimeType),
        ),
      });

      final uploadResponse = await _apiClient.upload<Map<String, dynamic>>(
        '/upload/image',
        formData,
      );

      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        if (kDebugMode) debugPrint('[Image] Paste upload failed: ${uploadResponse.message}');
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final imageUrl = ApiConfig.getMediaUrl(
        uploadResponse.data!['url'] as String?,
      );

      CachedNetworkImage.evictFromCache(imageUrl);

      final sendResponse = await _chatService.sendMessage(
        chatId: chatId,
        type: 2,
        content: api.MessageContent(
          text: (caption != null && caption.isNotEmpty) ? caption : null,
          media: api.MediaInfo(
            url: imageUrl,
            width: null,
            height: null,
            size: bytes.length,
            mimeType: mimeType,
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
      );

      if (sendResponse.isSuccess && sendResponse.data != null) {
        final serverMsg = sendResponse.data!;
        MessageItem? updated;
        state = state.map((msg) {
          if (msg.id == localId) {
            updated = msg.copyWith(
              id: serverMsg.msgId,
              mediaUrl: imageUrl,
              mediaSize: bytes.length,
              content: caption ?? '',
              status: MessageStatus.sent,
              seq: serverMsg.seq,
            );
            return updated!;
          }
          return msg;
        }).toList();
        if (updated != null) _persistMessageUpdate(localId, updated!);
      } else {
        _updateMessageStatus(localId, MessageStatus.failed);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Image] Paste send error: $e');
      _updateMessageStatus(localId, MessageStatus.failed);
    }
  }

  /// Send an image message from a remote URL.
  Future<void> sendImageByUrl(
    String imageUrl, {
    String? caption,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
  }) async {
    final localId = _uuid.v4();

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: '我',
      type: MessageItemType.image,
      content: caption ?? '',
      mediaUrl: imageUrl,
      isOutgoing: true,
      status: MessageStatus.sending,
      burnAfterRead: burnAfterRead,
      burnAfterSeconds: burnAfterSeconds,
      createdAt: DateTime.now(),
    );

    state = [message, ...state];
    Future.microtask(() => _saveMessagesToLocal([message]));

    try {
      final sendResponse = await _chatService.sendMessage(
        chatId: chatId,
        type: 2,
        content: api.MessageContent(
          text: (caption != null && caption.isNotEmpty) ? caption : null,
          media: api.MediaInfo(
            url: imageUrl,
            width: null,
            height: null,
            size: 1,
            mimeType: 'image/png',
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
      );

      if (sendResponse.isSuccess && sendResponse.data != null) {
        final serverMsg = sendResponse.data!;
        MessageItem? updated;
        state = state.map((msg) {
          if (msg.id == localId) {
            updated = msg.copyWith(
              id: serverMsg.msgId,
              mediaUrl: imageUrl,
              content: caption ?? '',
              status: MessageStatus.sent,
              seq: serverMsg.seq,
            );
            return updated!;
          }
          return msg;
        }).toList();
        if (updated != null) _persistMessageUpdate(localId, updated!);
      } else {
        _updateMessageStatus(localId, MessageStatus.failed);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Image] Send by url error: $e');
      _updateMessageStatus(localId, MessageStatus.failed);
    }
  }

  Future<void> sendVideoMessage(
    String localPath, {
    int? duration,
    String? thumbnail,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
  }) async {
    final localId = _uuid.v4();

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: '我',
      type: MessageItemType.video,
      content: '',
      mediaUrl: localPath,
      mediaDuration: duration,
      thumbnail: thumbnail,
      isOutgoing: true,
      status: MessageStatus.sending,
      burnAfterRead: burnAfterRead,
      burnAfterSeconds: burnAfterSeconds,
      createdAt: DateTime.now(),
    );

    state = [message, ...state];
    Future.microtask(() => _saveMessagesToLocal([message]));

    // Generate the local thumbnail asynchronously and update the optimistic message once ready.
    String? localThumbnail = thumbnail;
    if (localThumbnail == null) {
      try {
        final tempDir = await getTemporaryDirectory();
        localThumbnail = await VideoThumbnail.thumbnailFile(
          video: localPath,
          thumbnailPath: tempDir.path,
          imageFormat: ImageFormat.JPEG,
          maxWidth: 320,
          quality: 75,
        );
        if (localThumbnail != null && mounted) {
          state = state.map((msg) {
            if (msg.id == localId) {
              return msg.copyWith(thumbnail: localThumbnail);
            }
            return msg;
          }).toList();
        }
      } catch (e) {
        if (kDebugMode) debugPrint('[Message] Failed to generate video thumbnail: $e');
      }
    }

    try {
      final file = File(localPath);
      if (!await file.exists()) {
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final fileSize = await file.length();
      final ext = localPath.split('.').last.toLowerCase();

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          localPath,
          filename: 'video_${DateTime.now().millisecondsSinceEpoch}.$ext',
        ),
      });

      final uploadResponse = await _apiClient.upload<Map<String, dynamic>>(
        '/upload/video',
        formData,
        onSendProgress: (sent, total) {
          if (total > 0) {
            _updateUploadProgress(localId, sent / total);
          }
        },
      );

      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final videoUrl = ApiConfig.getMediaUrl(
        uploadResponse.data!['url'] as String?,
      );

      // Upload the thumbnail separately when available.
      String? thumbnailUrl;
      if (localThumbnail != null) {
        try {
          final thumbFile = File(localThumbnail);
          if (await thumbFile.exists()) {
            final thumbFormData = FormData.fromMap({
              'file': await MultipartFile.fromFile(
                localThumbnail,
                filename: 'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg',
              ),
            });

            final thumbResponse = await _apiClient.upload<Map<String, dynamic>>(
              '/upload/image',
              thumbFormData,
            );

            if (thumbResponse.isSuccess && thumbResponse.data != null) {
              thumbnailUrl = ApiConfig.getMediaUrl(
                thumbResponse.data!['url'] as String?,
              );
            }
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[Message] Failed to upload video thumbnail: $e');
        }
      }

      final sendResponse = await _chatService.sendMessage(
        chatId: chatId,
        type: 3, // video type
        content: api.MessageContent(
          media: api.MediaInfo(
            url: videoUrl,
            thumbnail: thumbnailUrl,
            duration: duration,
            size: fileSize,
            mimeType: 'video/$ext',
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
      );

      if (sendResponse.isSuccess && sendResponse.data != null) {
        final serverMsg = sendResponse.data!;
        MessageItem? updated;
        state = state.map((msg) {
          if (msg.id == localId) {
            updated = msg.copyWith(
              id: serverMsg.msgId,
              mediaUrl: videoUrl,
              thumbnail: thumbnailUrl,
              mediaSize: fileSize,
              status: MessageStatus.sent,
              seq: serverMsg.seq,
            );
            return updated!;
          }
          return msg;
        }).toList();
        if (updated != null) _persistMessageUpdate(localId, updated!);
      } else {
        _updateMessageStatus(localId, MessageStatus.failed);
      }
    } catch (_) {
      _updateMessageStatus(localId, MessageStatus.failed);
    }
  }

  Future<void> sendFileFromBytes(
    Uint8List bytes,
    String fileName, {
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
  }) async {
    final localId = _uuid.v4();
    final fileSize = bytes.length;
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: '我',
      type: MessageItemType.file,
      content: '',
      mediaUrl: null,
      fileName: fileName,
      mediaSize: fileSize,
      isOutgoing: true,
      status: MessageStatus.sending,
      burnAfterRead: burnAfterRead,
      burnAfterSeconds: burnAfterSeconds,
      createdAt: DateTime.now(),
    );

    state = [message, ...state];

    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: fileName),
      });

      final uploadResponse = await _apiClient.upload<Map<String, dynamic>>(
        '/upload/file',
        formData,
      );

      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        if (kDebugMode) debugPrint('[File] Bytes upload failed: ${uploadResponse.message}');
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final fileUrl = ApiConfig.getMediaUrl(
        uploadResponse.data!['url'] as String?,
      );

      final sendResponse = await _chatService.sendMessage(
        chatId: chatId,
        type: 5,
        content: api.MessageContent(
          file: api.FileInfo(
            url: fileUrl,
            name: fileName,
            size: fileSize,
            mimeType: _getMimeType(ext),
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
      );

      if (sendResponse.isSuccess && sendResponse.data != null) {
        final serverMsg = sendResponse.data!;
        MessageItem? updated;
        state = state.map((msg) {
          if (msg.id == localId) {
            updated = msg.copyWith(
              id: serverMsg.msgId,
              mediaUrl: fileUrl,
              mediaSize: fileSize,
              status: MessageStatus.sent,
              seq: serverMsg.seq,
            );
            return updated!;
          }
          return msg;
        }).toList();
        if (updated != null) _persistMessageUpdate(localId, updated!);
      } else {
        _updateMessageStatus(localId, MessageStatus.failed);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[File] Bytes send error: $e');
      _updateMessageStatus(localId, MessageStatus.failed);
    }
  }

  Future<void> sendFileMessage(
    String localPath,
    String fileName, {
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
  }) async {
    final localId = _uuid.v4();
    final file = File(localPath);
    final fileSize = await file.exists() ? await file.length() : 0;

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: '我',
      type: MessageItemType.file,
      content: '',
      mediaUrl: localPath,
      fileName: fileName,
      mediaSize: fileSize,
      isOutgoing: true,
      status: MessageStatus.sending,
      burnAfterRead: burnAfterRead,
      burnAfterSeconds: burnAfterSeconds,
      createdAt: DateTime.now(),
    );

    state = [message, ...state];
    Future.microtask(() => _saveMessagesToLocal([message]));

    try {
      if (!await file.exists()) {
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final ext = fileName.split('.').last.toLowerCase();

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(localPath, filename: fileName),
      });

      // Reuse the generic file upload flow before sending the file message.
      final uploadResponse = await _apiClient.upload<Map<String, dynamic>>(
        '/upload/file',
        formData,
      );

      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        if (kDebugMode) debugPrint('[File] Upload failed: ${uploadResponse.message}');
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final fileUrl = ApiConfig.getMediaUrl(
        uploadResponse.data!['url'] as String?,
      );

      final sendResponse = await _chatService.sendMessage(
        chatId: chatId,
        type: 5, // file type
        content: api.MessageContent(
          file: api.FileInfo(
            url: fileUrl,
            name: fileName,
            size: fileSize,
            mimeType: _getMimeType(ext),
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
      );

      if (sendResponse.isSuccess && sendResponse.data != null) {
        final serverMsg = sendResponse.data!;
        MessageItem? updated;
        state = state.map((msg) {
          if (msg.id == localId) {
            updated = msg.copyWith(
              id: serverMsg.msgId,
              mediaUrl: fileUrl,
              status: MessageStatus.sent,
              seq: serverMsg.seq,
            );
            return updated!;
          }
          return msg;
        }).toList();
        if (updated != null) _persistMessageUpdate(localId, updated!);
      } else {
        _updateMessageStatus(localId, MessageStatus.failed);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[File] Send error: $e');
      _updateMessageStatus(localId, MessageStatus.failed);
    }
  }

  String _getMimeType(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'xls':
      case 'xlsx':
        return 'application/vnd.ms-excel';
      case 'ppt':
      case 'pptx':
        return 'application/vnd.ms-powerpoint';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/x-rar-compressed';
      default:
        return 'application/octet-stream';
    }
  }

  /// Send a voice message.
  Future<void> sendVoiceMessage(
    String localPath,
    int durationMs, {
    String? transcript,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
  }) async {
    final localId = _uuid.v4();

    // Insert the local optimistic message first.
    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: '我',
      type: MessageItemType.voice,
      content: transcript ?? '',
      mediaUrl: localPath,
      mediaDuration: durationMs,
      isOutgoing: true,
      status: MessageStatus.sending,
      burnAfterRead: burnAfterRead,
      burnAfterSeconds: burnAfterSeconds,
      createdAt: DateTime.now(),
    );

    state = [message, ...state];
    Future.microtask(() => _saveMessagesToLocal([message]));

    try {
      final file = File(localPath);
      if (!await file.exists()) {
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          localPath,
          filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        ),
        'duration': durationMs.toString(),
      });

      final uploadResponse = await _apiClient.upload<Map<String, dynamic>>(
        '/upload/voice',
        formData,
      );

      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        if (kDebugMode) debugPrint('[Voice] Upload failed: ${uploadResponse.message}');
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final voiceUrl = uploadResponse.data!['url'] as String;
      final voiceSize = uploadResponse.data!['size'] as int? ?? 0;

      // 2. Send the voice message.
      final sendResponse = await _chatService.sendMessage(
        chatId: chatId,
        type: 4, // voice type
        content: api.MessageContent(
          voice: api.VoiceInfo(
            url: voiceUrl,
            duration: durationMs,
            size: voiceSize,
            transcript: transcript,
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
      );

      if (sendResponse.isSuccess && sendResponse.data != null) {
        final serverMsg = sendResponse.data!;
        MessageItem? updated;
        state = state.map((msg) {
          if (msg.id == localId) {
            updated = msg.copyWith(
              id: serverMsg.msgId,
              mediaUrl: voiceUrl,
              mediaSize: voiceSize,
              content: transcript ?? msg.content,
              status: MessageStatus.sent,
              seq: serverMsg.seq,
            );
            return updated!;
          }
          return msg;
        }).toList();
        if (updated != null) _persistMessageUpdate(localId, updated!);
      } else {
        _updateMessageStatus(localId, MessageStatus.failed);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Voice] Send error: $e');
      _updateMessageStatus(localId, MessageStatus.failed);
    }
  }

  Future<String?> sendLocationMessage({
    required double latitude,
    required double longitude,
    String? title,
    String? address,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
  }) async {
    final localId = _uuid.v4();
    final preview = (title != null && title.trim().isNotEmpty)
        ? title.trim()
        : ((address != null && address.trim().isNotEmpty)
              ? address.trim()
              : '位置');

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: '我',
      type: MessageItemType.location,
      content: preview,
      isOutgoing: true,
      status: MessageStatus.sending,
      burnAfterRead: burnAfterRead,
      burnAfterSeconds: burnAfterSeconds,
      locationLatitude: latitude,
      locationLongitude: longitude,
      locationTitle: title,
      locationAddress: address,
      createdAt: DateTime.now(),
    );

    state = [message, ...state];
    Future.microtask(() => _saveMessagesToLocal([message]));

    try {
      final sendResponse = await _chatService.sendMessage(
        chatId: chatId,
        type: 6,
        content: api.MessageContent(
          location: api.LocationInfo(
            latitude: latitude,
            longitude: longitude,
            title: title,
            address: address,
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
      );

      if (sendResponse.isSuccess && sendResponse.data != null) {
        _updateLocalMessage(
          localId,
          sendResponse.data!.msgId,
          MessageStatus.sent,
          seq: sendResponse.data!.seq,
        );
        return null;
      } else {
        if (kDebugMode) debugPrint(
          '[Location] sendMessage failed: code=${sendResponse.code} message=${sendResponse.message} dataNull=${sendResponse.data == null}',
        );
        if (sendResponse.code > 0) {
          state = state.where((m) => m.id != localId).toList();
          return sendResponse.message.isNotEmpty
              ? sendResponse.message
              : '发送位置失败，请稍后再试';
        }
        _updateMessageStatus(localId, MessageStatus.failed);
        return '发送位置失败，请检查网络后重试';
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Location] Send error: $e');
      _updateMessageStatus(localId, MessageStatus.failed);
      return '发送位置失败，请检查网络后重试';
    }
  }

  void _updateLocalMessage(
    String localId,
    String serverId,
    MessageStatus status, {
    int? seq,
  }) {
    MessageItem? updated;
    state = state.map((msg) {
      if (msg.id == localId) {
        updated = msg.copyWith(id: serverId, status: status, seq: seq);
        return updated!;
      }
      return msg;
    }).toList();
    if (updated != null) {
      _persistMessageUpdate(localId, updated!);
    }
  }

  void _updateUploadProgress(String messageId, double progress) {
    state = state.map((msg) {
      if (msg.id == messageId) {
        return msg.copyWith(uploadProgress: progress);
      }
      return msg;
    }).toList();
  }

  void _updateMessageStatus(String messageId, MessageStatus status) {
    MessageItem? updated;
    state = state.map((msg) {
      if (msg.id == messageId) {
        updated = msg.copyWith(status: status);
        return updated!;
      }
      return msg;
    }).toList();
    // Persist the updated message locally.
    if (updated != null) {
      _saveMessagesToLocal([updated!]);
    }
  }

  void markQueuedMessageFailed(String messageId) {
    _updateMessageStatus(messageId, MessageStatus.failed);
  }

  Future<void> _persistMessageUpdate(String oldId, MessageItem newMsg) async {
    if (PlatformUtils.isWeb) return;

    try {
      await IsarService.instance.isar.writeTxn(() async {
        // Remove the old local message record by id.
        await IsarService.instance.isar.messageModels
            .filter()
            .idEqualTo(oldId)
            .deleteAll();
      });
      // Write the updated message back to local storage.
      _saveMessagesToLocal([newMsg]);
    } catch (e) {
      if (kDebugMode) debugPrint('[Message] Persist message update failed: $e');
    }
  }

  Future<void> deleteMessage(String messageId) async {
    if (PlatformUtils.isWeb) {
      state = state.where((msg) => msg.id != messageId).toList();
      _cachedDeletedIds ??= <String>{};
      _cachedDeletedIds!.add(messageId);
      await _addToDeletedMessages(messageId);
      await _removeBurnState(messageId);
      return;
    }
    state = state.where((msg) => msg.id != messageId).toList();

    _cachedDeletedIds ??= <String>{};
    _cachedDeletedIds!.add(messageId);

    await _addToDeletedMessages(messageId);
    await _removeBurnState(messageId);

    // Remove the local message record from Isar as well.
    try {
      await IsarService.instance.isar.writeTxn(() async {
        await IsarService.instance.isar.messageModels
            .filter()
            .idEqualTo(messageId)
            .deleteAll();
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[MessageProvider] Delete local message failed: $e');
    }
  }

  Future<void> _addToDeletedMessages(String messageId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'deleted_messages_$chatId';
      final deletedIds = prefs.getStringList(key) ?? [];
      if (!deletedIds.contains(messageId)) {
        deletedIds.add(messageId);
        await prefs.setStringList(key, deletedIds);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[MessageProvider] Save deleted message IDs failed: $e');
    }
  }

  String get _burnStateStorageKey => 'burn_state_$chatId';

  Future<Map<String, Map<String, dynamic>>> _getBurnStateMap() async {
    if (_cachedBurnState != null) return _cachedBurnState!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_burnStateStorageKey);
      if (raw == null || raw.isEmpty) {
        _cachedBurnState = <String, Map<String, dynamic>>{};
        return _cachedBurnState!;
      }

      final decoded = jsonDecode(raw);
      final parsed = <String, Map<String, dynamic>>{};
      if (decoded is Map) {
        decoded.forEach((key, value) {
          if (key is String && value is Map) {
            parsed[key] = Map<String, dynamic>.from(value);
          }
        });
      }
      _cachedBurnState = parsed;
    } catch (e) {
      if (kDebugMode) debugPrint('[MessageProvider] Load burn state failed: $e');
      _cachedBurnState = <String, Map<String, dynamic>>{};
    }
    return _cachedBurnState!;
  }

  MessageItem _applyPersistedBurnState(MessageItem message) {
    final snapshot = _cachedBurnState?[message.id];
    if (snapshot == null || !message.burnAfterRead) {
      return message;
    }

    return message.copyWith(
      burnLocked: snapshot['burn_locked'] == true,
      burnCountdownSeconds: (snapshot['burn_countdown_seconds'] as num?)
          ?.toInt(),
    );
  }

  Future<void> _persistBurnState(MessageItem message) async {
    if (!message.burnAfterRead) return;
    final burnState = await _getBurnStateMap();
    burnState[message.id] = {
      'burn_locked': message.burnLocked,
      'burn_countdown_seconds': message.burnCountdownSeconds,
    };
    await _flushBurnStateMap();
  }

  Future<void> _persistBurnStates(Iterable<MessageItem> messages) async {
    final burnMessages = messages.where((msg) => msg.burnAfterRead).toList();
    if (burnMessages.isEmpty) return;
    final burnState = await _getBurnStateMap();
    for (final message in burnMessages) {
      burnState[message.id] = {
        'burn_locked': message.burnLocked,
        'burn_countdown_seconds': message.burnCountdownSeconds,
      };
    }
    await _flushBurnStateMap();
  }

  Future<void> _removeBurnState(String messageId) async {
    final burnState = await _getBurnStateMap();
    if (burnState.remove(messageId) == null) {
      return;
    }
    await _flushBurnStateMap();
  }

  Future<void> _clearBurnStateMap() async {
    _cachedBurnState = <String, Map<String, dynamic>>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_burnStateStorageKey);
    } catch (e) {
      if (kDebugMode) debugPrint('[MessageProvider] Clear burn state failed: $e');
    }
  }

  Future<void> _flushBurnStateMap() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final burnState = _cachedBurnState ?? <String, Map<String, dynamic>>{};
      if (burnState.isEmpty) {
        await prefs.remove(_burnStateStorageKey);
        return;
      }
      await prefs.setString(_burnStateStorageKey, jsonEncode(burnState));
    } catch (e) {
      if (kDebugMode) debugPrint('[MessageProvider] Save burn state failed: $e');
    }
  }

  /// Get deleted message IDs with in-memory caching to avoid repeated disk reads.
  Future<Set<String>> _getDeletedMessageIds() async {
    if (_cachedDeletedIds != null) return _cachedDeletedIds!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'deleted_messages_$chatId';
      final deletedIds = prefs.getStringList(key) ?? [];
      _cachedDeletedIds = deletedIds.toSet();
      return _cachedDeletedIds!;
    } catch (e) {
      if (kDebugMode) debugPrint('[MessageProvider] Get deleted message IDs failed: $e');
      return {};
    }
  }

  /// Revoke a message via API.
  Future<bool> revokeMessage(String messageId) async {
    final response = await _chatService.revokeMessage(chatId, messageId);

    if (response.isSuccess) {
      _markMessageAsRevoked(messageId);
      return true;
    }

    return false;
  }

  /// Edit a message via the backend API.
  Future<bool> editMessage(String messageId, String newContent) async {
    final response = await _chatService.editMessage(
      chatId,
      messageId,
      newContent,
    );

    if (response.isSuccess) {
      state = state.map((msg) {
        if (msg.id == messageId) {
          return msg.copyWith(
            content: newContent,
            isEdited: true,
            editedAt: DateTime.now(),
          );
        }
        return msg;
      }).toList();
      return true;
    }

    return false;
  }

  void _applyEditedMessage(api.Message message) {
    if (!mounted) return;
    final updated = MessageItem.fromApiMessage(message, _currentUserId);
    var found = false;
    state = state.map((msg) {
      if (msg.id == message.msgId) {
        found = true;
        return updated.copyWith(createdAt: msg.createdAt);
      }
      return msg;
    }).toList();
    if (found) {
      _saveMessagesToLocal([
        state.firstWhere((msg) => msg.id == message.msgId),
      ]);
    }
  }

  void _handleMessageEdited(Map<String, dynamic> data) {
    if (!mounted) return;
    final msgId = data['msg_id']?.toString();
    final newContent = data['new_content']?.toString();

    if (msgId == null || newContent == null) return;

    state = state.map((msg) {
      if (msg.id == msgId) {
        return msg.copyWith(
          content: newContent,
          isEdited: true,
          editedAt: DateTime.now(),
        );
      }
      return msg;
    }).toList();
  }

  /// Forward a message via the backend API.
  Future<bool> forwardMessage(String messageId, String targetChatId) async {
    final localMessage = state.cast<MessageItem?>().firstWhere(
      (item) => item?.id == messageId,
      orElse: () => null,
    );
    if (localMessage?.burnAfterRead == true) {
      return false;
    }
    if (localMessage != null) {
      final content = _buildForwardContent(localMessage);
      final type = _buildForwardType(localMessage);
      if (content != null && type != null) {
        final response = await _chatService.sendMessage(
          chatId: targetChatId,
          type: type,
          content: content,
        );
        return response.isSuccess;
      }
    }

    final response = await _chatService.forwardMessage(
      sourceChatId: chatId,
      sourceMsgId: messageId,
      targetChatId: targetChatId,
    );

    return response.isSuccess;
  }

  int? _buildForwardType(MessageItem message) {
    switch (message.type) {
      case MessageItemType.text:
        return 1;
      case MessageItemType.image:
        return 2;
      case MessageItemType.video:
        return 3;
      case MessageItemType.voice:
        return 4;
      case MessageItemType.file:
        return 5;
      case MessageItemType.location:
        return 6;
      case MessageItemType.contact:
        return 10;
      default:
        return null;
    }
  }

  api.MessageContent? _buildForwardContent(MessageItem message) {
    switch (message.type) {
      case MessageItemType.text:
        return api.MessageContent(text: message.content);
      case MessageItemType.image:
        if (message.mediaUrl == null || message.mediaUrl!.isEmpty) return null;
        return api.MessageContent(
          text: message.content.isEmpty ? null : message.content,
          media: api.MediaInfo(
            url: message.mediaUrl!,
            thumbnail: message.thumbnail,
            width: message.mediaWidth,
            height: message.mediaHeight,
            size: message.mediaSize ?? 0,
            mimeType: 'image/jpeg',
          ),
        );
      case MessageItemType.video:
        if (message.mediaUrl == null || message.mediaUrl!.isEmpty) return null;
        return api.MessageContent(
          media: api.MediaInfo(
            url: message.mediaUrl!,
            thumbnail: message.thumbnail,
            width: message.mediaWidth,
            height: message.mediaHeight,
            duration: message.mediaDuration,
            size: message.mediaSize ?? 0,
            mimeType: 'video/mp4',
          ),
        );
      case MessageItemType.voice:
        if (message.mediaUrl == null || message.mediaUrl!.isEmpty) return null;
        return api.MessageContent(
          voice: api.VoiceInfo(
            url: message.mediaUrl!,
            duration: message.mediaDuration ?? 0,
            size: message.mediaSize ?? 0,
            transcript: message.content.isEmpty ? null : message.content,
          ),
        );
      case MessageItemType.file:
        if (message.mediaUrl == null || message.mediaUrl!.isEmpty) return null;
        return api.MessageContent(
          file: api.FileInfo(
            url: message.mediaUrl!,
            name: message.fileName ?? 'file',
            size: message.mediaSize ?? 0,
            mimeType: _getMimeType(() {
              final name = message.fileName ?? '';
              if (!name.contains('.')) return '';
              return name.split('.').last.toLowerCase();
            }()),
          ),
        );
      case MessageItemType.location:
        if (message.locationLatitude == null ||
            message.locationLongitude == null) {
          return null;
        }
        return api.MessageContent(
          location: api.LocationInfo(
            latitude: message.locationLatitude!,
            longitude: message.locationLongitude!,
            title: message.locationTitle,
            address: message.locationAddress,
          ),
        );
      case MessageItemType.contact:
        if (message.contactUserId == null || message.contactName == null)
          return null;
        return api.MessageContent(
          contact: api.ContactCardInfo(
            userId: message.contactUserId!,
            nickname: message.contactName!,
            username: message.contactUsername,
            avatar: message.contactAvatar,
            nicknameColor: message.contactNicknameColor,
            emojiAvatar: message.contactEmojiAvatar,
            premiumType: message.contactPremiumType,
          ),
        );
      default:
        return null;
    }
  }

  /// Retry sending a failed message.
  Future<void> resendMessage(String messageId) async {
    final idx = state.indexWhere((msg) => msg.id == messageId);
    if (idx < 0) return;
    final message = state[idx];

    if (message.status != MessageStatus.failed) return;

    _updateMessageStatus(messageId, MessageStatus.sending);

    try {
      switch (message.type) {
        case MessageItemType.text:
          final response = await _chatService.sendMessage(
            chatId: chatId,
            type: 1,
            content: api.MessageContent(text: message.content),
            msgId: messageId,
            burnAfterRead: message.burnAfterRead,
            burnAfterSeconds: message.burnAfterSeconds,
          );
          if (response.isSuccess && response.data != null) {
            _updateLocalMessage(
              messageId,
              response.data!.msgId,
              MessageStatus.sent,
              seq: response.data!.seq,
            );
          } else {
            _updateMessageStatus(messageId, MessageStatus.failed);
          }
          break;

        case MessageItemType.image:
          if (message.mediaUrl != null) {
            final url = message.mediaUrl!;
            if (url.startsWith('data:image/')) {
              try {
                final comma = url.indexOf(',');
                if (comma != -1) {
                  final bytes = base64Decode(url.substring(comma + 1));
                  // Remove the failed placeholder and resend.
                  state = state.where((msg) => msg.id != messageId).toList();
                  await sendImageFromBytes(
                    bytes,
                    caption: message.content.isEmpty ? null : message.content,
                    burnAfterRead: message.burnAfterRead,
                    burnAfterSeconds: message.burnAfterSeconds,
                  );
                } else {
                  _updateMessageStatus(messageId, MessageStatus.failed);
                }
              } catch (_) {
                _updateMessageStatus(messageId, MessageStatus.failed);
              }
            } else if (url.startsWith('/') && !url.startsWith('/uploads')) {
              // Re-send local file paths through the normal image flow.
              await sendImageMessage(
                url,
                width: message.mediaWidth,
                height: message.mediaHeight,
                caption: message.content.isEmpty ? null : message.content,
                burnAfterRead: message.burnAfterRead,
                burnAfterSeconds: message.burnAfterSeconds,
              );
              state = state.where((msg) => msg.id != messageId).toList();
            } else {
              // Reuse already-uploaded remote URLs directly when retrying.
              final sendResponse = await _chatService.sendMessage(
                chatId: chatId,
                type: 2,
                content: api.MessageContent(
                  media: api.MediaInfo(
                    url: url,
                    width: message.mediaWidth,
                    height: message.mediaHeight,
                    size: message.mediaSize ?? 0,
                    mimeType: 'image/jpeg',
                  ),
                ),
                msgId: messageId,
                burnAfterRead: message.burnAfterRead,
                burnAfterSeconds: message.burnAfterSeconds,
              );
              if (sendResponse.isSuccess && sendResponse.data != null) {
                _updateLocalMessage(
                  messageId,
                  sendResponse.data!.msgId,
                  MessageStatus.sent,
                  seq: sendResponse.data!.seq,
                );
              } else {
                _updateMessageStatus(messageId, MessageStatus.failed);
              }
            }
          } else {
            _updateMessageStatus(messageId, MessageStatus.failed);
          }
          break;

        case MessageItemType.video:
          if (message.mediaUrl != null &&
              message.mediaUrl!.startsWith('/uploads')) {
            final sendResponse = await _chatService.sendMessage(
              chatId: chatId,
              type: 3,
              content: api.MessageContent(
                media: api.MediaInfo(
                  url: message.mediaUrl!,
                  thumbnail: message.thumbnail,
                  duration: message.mediaDuration,
                  size: message.mediaSize ?? 0,
                  mimeType: 'video/mp4',
                ),
              ),
              msgId: messageId,
              burnAfterRead: message.burnAfterRead,
              burnAfterSeconds: message.burnAfterSeconds,
            );
            if (sendResponse.isSuccess && sendResponse.data != null) {
              _updateLocalMessage(
                messageId,
                sendResponse.data!.msgId,
                MessageStatus.sent,
                seq: sendResponse.data!.seq,
              );
            } else {
              _updateMessageStatus(messageId, MessageStatus.failed);
            }
          } else {
            _updateMessageStatus(messageId, MessageStatus.failed);
          }
          break;

        case MessageItemType.file:
          if (message.mediaUrl != null &&
              message.mediaUrl!.startsWith('/uploads')) {
            final ext =
                (message.fileName ?? '').split('.').lastOrNull?.toLowerCase() ??
                '';
            final sendResponse = await _chatService.sendMessage(
              chatId: chatId,
              type: 5,
              content: api.MessageContent(
                file: api.FileInfo(
                  url: message.mediaUrl!,
                  name: message.fileName ?? 'file',
                  size: message.mediaSize ?? 0,
                  mimeType: _getMimeType(ext),
                ),
              ),
              msgId: messageId,
              burnAfterRead: message.burnAfterRead,
              burnAfterSeconds: message.burnAfterSeconds,
            );
            if (sendResponse.isSuccess && sendResponse.data != null) {
              _updateLocalMessage(
                messageId,
                sendResponse.data!.msgId,
                MessageStatus.sent,
                seq: sendResponse.data!.seq,
              );
            } else {
              _updateMessageStatus(messageId, MessageStatus.failed);
            }
          } else {
            _updateMessageStatus(messageId, MessageStatus.failed);
          }
          break;

        case MessageItemType.voice:
          if (message.mediaUrl != null &&
              message.mediaUrl!.startsWith('/uploads')) {
            final sendResponse = await _chatService.sendMessage(
              chatId: chatId,
              type: 4,
              content: api.MessageContent(
                voice: api.VoiceInfo(
                  url: message.mediaUrl!,
                  duration: message.mediaDuration ?? 0,
                  size: message.mediaSize ?? 0,
                  transcript: message.content.isEmpty ? null : message.content,
                ),
              ),
              msgId: messageId,
              burnAfterRead: message.burnAfterRead,
              burnAfterSeconds: message.burnAfterSeconds,
            );
            if (sendResponse.isSuccess && sendResponse.data != null) {
              _updateLocalMessage(
                messageId,
                sendResponse.data!.msgId,
                MessageStatus.sent,
                seq: sendResponse.data!.seq,
              );
            } else {
              _updateMessageStatus(messageId, MessageStatus.failed);
            }
          } else {
            _updateMessageStatus(messageId, MessageStatus.failed);
          }
          break;

        case MessageItemType.location:
          final latitude = message.locationLatitude;
          final longitude = message.locationLongitude;
          if (latitude != null && longitude != null) {
            state = state.where((msg) => msg.id != messageId).toList();
            await sendLocationMessage(
              latitude: latitude,
              longitude: longitude,
              title: message.locationTitle,
              address: message.locationAddress,
              burnAfterRead: message.burnAfterRead,
              burnAfterSeconds: message.burnAfterSeconds,
            );
          } else {
            _updateMessageStatus(messageId, MessageStatus.failed);
          }
          break;

        default:
          _updateMessageStatus(messageId, MessageStatus.failed);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Message] Resend error: $e');
      _updateMessageStatus(messageId, MessageStatus.failed);
    }
  }

  Future<bool> addReaction(
    String messageId,
    String emoji,
    String userName,
  ) async {
    final response = await _chatService.addReaction(chatId, messageId, emoji);

    if (response.isSuccess) {
      _addLocalReaction(messageId, emoji, _currentUserId, userName);
      return true;
    }

    return false;
  }

  Future<bool> removeReaction(String messageId, String emoji) async {
    final response = await _chatService.removeReaction(
      chatId,
      messageId,
      emoji,
    );

    if (response.isSuccess) {
      _removeLocalReaction(messageId, emoji, _currentUserId);
      return true;
    }

    return false;
  }

  void _addLocalReaction(
    String messageId,
    String emoji,
    String userId,
    String userName,
  ) {
    if (!mounted) return;
    state = state.map((msg) {
      if (msg.id == messageId) {
        final existing = msg.reactions
            .where((r) => r.userId == userId && r.emoji == emoji)
            .isNotEmpty;

        if (existing) return msg;

        final newReactions = [
          ...msg.reactions,
          MessageReaction(
            emoji: emoji,
            userId: userId,
            userName: userName,
            createdAt: DateTime.now(),
          ),
        ];

        return msg.copyWith(reactions: newReactions);
      }
      return msg;
    }).toList();
  }

  void _removeLocalReaction(String messageId, String emoji, String userId) {
    if (!mounted) return;
    state = state.map((msg) {
      if (msg.id == messageId) {
        final newReactions = msg.reactions
            .where((r) => !(r.userId == userId && r.emoji == emoji))
            .toList();

        return msg.copyWith(reactions: newReactions);
      }
      return msg;
    }).toList();
  }

  void handleReactionEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final msgId = data['msg_id']?.toString();
    final userId = data['user_id']?.toString();
    final userName = data['user_name']?.toString();
    final emoji = data['emoji']?.toString();
    final action = data['action']?.toString();

    if (msgId == null || userId == null || emoji == null || action == null)
      return;

    if (action == 'add') {
      _addLocalReaction(msgId, emoji, userId, userName ?? '');
    } else if (action == 'remove') {
      _removeLocalReaction(msgId, emoji, userId);
    }
  }

  void addRedPacketMessage({
    required String redPacketJson,
    required String senderName,
    String? senderAvatar,
  }) {
    final localId = 'local_rp_${DateTime.now().millisecondsSinceEpoch}';
    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: senderName,
      senderAvatar: senderAvatar,
      type: MessageItemType.redPacket,
      content: redPacketJson,
      isOutgoing: true,
      status: MessageStatus.sent,
      isRead: true,
      createdAt: DateTime.now(),
      seq: 0,
      reactions: const [],
    );
    _addWalletOptimisticMessage(message);
  }

  void addTransferMessage({
    required String transferJson,
    required String senderName,
    String? senderAvatar,
  }) {
    final localId = 'local_tf_${DateTime.now().millisecondsSinceEpoch}';
    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: senderName,
      senderAvatar: senderAvatar,
      type: MessageItemType.transfer,
      content: transferJson,
      isOutgoing: true,
      status: MessageStatus.sent,
      isRead: true,
      createdAt: DateTime.now(),
      seq: 0,
      reactions: const [],
    );
    _addWalletOptimisticMessage(message);
  }

  void _addWalletOptimisticMessage(MessageItem message) {
    final merged = _dedupeWalletMessages([message, ...state]);
    final inserted = merged.any((item) => item.id == message.id);
    state = merged;
    if (inserted) {
      _saveMessagesToLocal([message]);
    }
  }

  void addSystemMessage({required String content, String? messageId}) {
    final normalizedId = messageId?.trim();
    final localId = normalizedId != null && normalizedId.isNotEmpty
        ? normalizedId
        : 'local_system_${DateTime.now().millisecondsSinceEpoch}';

    if (state.any((msg) => msg.id == localId)) {
      return;
    }

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId.isNotEmpty ? _currentUserId : 'system',
      senderName: '系统消息',
      type: MessageItemType.system,
      content: content,
      isOutgoing: false,
      status: MessageStatus.sent,
      isRead: true,
      createdAt: DateTime.now(),
      seq: 0,
      reactions: const [],
    );

    state = [message, ...state];
    _saveMessagesToLocal([message]);
  }
}
