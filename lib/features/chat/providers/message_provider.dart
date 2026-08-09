// 文件用途：管理聊天消息列表、发送上传、同步重试、本地持久化和消息状态。
// 核心逻辑：维护消息窗口和本地持久化，串联文本/媒体/文件/语音上传与发送，处理乐观消息、重试、撤回和失败回滚。
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
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
import '../../../core/constants/message_limits.dart';
import '../../../core/services/api/websocket_service.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/account_session_coordinator.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/storage/models/message_model.dart'
    if (dart.library.js_interop) '../../../core/services/storage/models/message_model_web.dart';
import '../../../core/services/offline_message_queue.dart';
import '../../../core/services/performance_trace_service.dart';
import '../../../core/services/media_cache_manager.dart';
import '../../../core/services/s3_direct_upload_service.dart';
import '../../../core/utils/image_compress_util.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/services/storage/isar_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../widgets/message_bubble.dart' show WalletBubbleRefreshNotifier;
import '../utils/call_preview_formatter.dart';
import '../services/emoji_store_service.dart';

String _messageProviderText({
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

String _messageProviderSelfName() =>
    _messageProviderText(zhCN: '我', zhTW: '我', en: 'Me');

String _messageProviderLocationLabel() =>
    _messageProviderText(zhCN: '位置', zhTW: '位置', en: 'Location');

/// 多选转发按服务端 seq 正序提交；未同步消息放在其后并保持确定性顺序。
List<MessageItem> orderMessagesForForward(Iterable<MessageItem> messages) {
  final ordered = messages.toList().asMap().entries.toList();
  ordered.sort((aEntry, bEntry) {
    final a = aEntry.value;
    final b = bEntry.value;
    final aHasSeq = a.seq > 0;
    final bHasSeq = b.seq > 0;
    if (aHasSeq && bHasSeq) {
      final bySeq = a.seq.compareTo(b.seq);
      if (bySeq != 0) return bySeq;
    } else if (aHasSeq != bHasSeq) {
      return aHasSeq ? -1 : 1;
    }

    final byCreatedAt = a.createdAt.compareTo(b.createdAt);
    if (byCreatedAt != 0) return byCreatedAt;
    // Some production responses only have second-level timestamps and no seq.
    // Preserve the history/display order instead of sorting random UUIDs.
    return aEntry.key.compareTo(bEntry.key);
  });
  return ordered.map((entry) => entry.value).toList(growable: false);
}

// 关键声明：消息 Provider 是聊天写入的单一编排点，乐观消息、上传、服务端确认和本地持久化必须围绕同一 client ID 收敛。
typedef ForwardMessageAttempt = Future<bool> Function(
  MessageItem message,
  String clientMsgId,
);

class ForwardBatchResult {
  const ForwardBatchResult({
    required this.totalCount,
    required this.successCount,
    required this.failedMessageIds,
  });

  final int totalCount;
  final int successCount;
  final List<String> failedMessageIds;

  bool get isComplete => successCount == totalCount;
}

typedef ForwardTargetMessageAttempt = Future<bool> Function(
  String targetChatId,
  MessageItem message,
  String clientMsgId,
);

class ForwardTargetBatchResult {
  const ForwardTargetBatchResult({
    required this.targetChatId,
    required this.messages,
  });

  final String targetChatId;
  final ForwardBatchResult messages;

  bool get isComplete => messages.isComplete;
}

class ForwardBundleTargetResult {
  const ForwardBundleTargetResult({
    required this.targetChatId,
    required this.succeeded,
  });

  final String targetChatId;
  final bool succeeded;
}

typedef ForwardBundleTargetAttempt = Future<bool> Function(
  String targetChatId,
  String clientMsgId,
);

Future<List<ForwardBundleTargetResult>> forwardBundleToTargetsReliably(
  Iterable<String> targetChatIds,
  ForwardBundleTargetAttempt attempt, {
  Duration retryDelay = const Duration(milliseconds: 300),
  String Function()? clientMsgIdFactory,
}) async {
  final uniqueTargets = <String>[];
  final seen = <String>{};
  for (final rawTarget in targetChatIds) {
    final target = rawTarget.trim();
    if (target.isNotEmpty && seen.add(target)) uniqueTargets.add(target);
  }

  final results = <ForwardBundleTargetResult>[];
  for (final target in uniqueTargets) {
    final clientMsgId = clientMsgIdFactory?.call() ?? const Uuid().v4();
    Future<bool> run() async {
      try {
        return await attempt(target, clientMsgId);
      } catch (_) {
        return false;
      }
    }

    var succeeded = await run();
    if (!succeeded) {
      if (retryDelay > Duration.zero) await Future<void>.delayed(retryDelay);
      succeeded = await run();
    }
    results.add(
      ForwardBundleTargetResult(
        targetChatId: target,
        succeeded: succeeded,
      ),
    );
  }
  return List.unmodifiable(results);
}

/// Submits every selected message even if the page is closed or one request
/// fails. A transient failure gets one idempotent retry with the same client
/// message id, so an ambiguous response cannot create a duplicate.
Future<ForwardBatchResult> forwardMessagesReliably(
  Iterable<MessageItem> messages,
  ForwardMessageAttempt attempt, {
  Duration retryDelay = const Duration(milliseconds: 300),
  String Function()? clientMsgIdFactory,
}) async {
  final ordered = messages.toList(growable: false);
  final failedIds = <String>[];
  var successCount = 0;

  Future<bool> runAttempt(MessageItem message, String clientMsgId) async {
    try {
      return await attempt(message, clientMsgId);
    } catch (_) {
      return false;
    }
  }

  for (final message in ordered) {
    final clientMsgId = clientMsgIdFactory?.call() ?? const Uuid().v4();
    var success = await runAttempt(message, clientMsgId);
    if (!success) {
      if (retryDelay > Duration.zero) {
        await Future<void>.delayed(retryDelay);
      }
      success = await runAttempt(message, clientMsgId);
    }
    if (success) {
      successCount++;
    } else {
      failedIds.add(message.id);
    }
  }

  return ForwardBatchResult(
    totalCount: ordered.length,
    successCount: successCount,
    failedMessageIds: List.unmodifiable(failedIds),
  );
}

/// Runs each destination independently. Duplicate destination ids are removed
/// without changing the user's selection order, and one failed destination
/// never prevents the remaining destinations from being attempted.
Future<List<ForwardTargetBatchResult>> forwardMessagesToTargetsReliably(
  Iterable<MessageItem> messages,
  Iterable<String> targetChatIds,
  ForwardTargetMessageAttempt attempt, {
  Duration retryDelay = const Duration(milliseconds: 300),
  String Function()? clientMsgIdFactory,
}) async {
  final uniqueTargetIds = <String>[];
  final seen = <String>{};
  for (final rawTargetId in targetChatIds) {
    final targetId = rawTargetId.trim();
    if (targetId.isNotEmpty && seen.add(targetId)) {
      uniqueTargetIds.add(targetId);
    }
  }

  final orderedMessages = messages.toList(growable: false);
  final results = <ForwardTargetBatchResult>[];
  for (final targetId in uniqueTargetIds) {
    final result = await forwardMessagesReliably(
      orderedMessages,
      (message, clientMsgId) => attempt(targetId, message, clientMsgId),
      retryDelay: retryDelay,
      clientMsgIdFactory: clientMsgIdFactory,
    );
    results.add(
      ForwardTargetBatchResult(targetChatId: targetId, messages: result),
    );
  }
  return List.unmodifiable(results);
}

String _messageProviderStickerMediaUrl(String? url) {
  if (url == null) return '';
  return EmojiStoreService.resolveStickerDisplayPath(url);
}

String _messageServerMessage(
  String? raw, {
  String fallbackZhCN = '发送失败，请稍后重试',
  String fallbackZhTW = '發送失敗，請稍後重試',
  required String fallbackEn,
}) {
  return localizeServerMessage(
    raw,
    fallbackZhCN: fallbackZhCN,
    fallbackZhTW: fallbackZhTW,
    fallbackEn: fallbackEn,
  );
}

bool _isWalletStatusChangeText(String text) {
  const statusHints = [
    '领取了红包',
    '領取了紅包',
    '已收款',
    '已退款',
    '已拒收',
    '红包已过期',
    '紅包已過期',
    '转账已过期',
    '轉帳已過期',
    'claimed the red packet',
    'received the transfer',
    'returned',
    'expired',
  ];
  return statusHints.any(text.contains);
}

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

String? _initialPrivateMediaDisplayUrl(String? mediaId, String? rawUrl) {
  final normalizedUrl = ApiConfig.getMediaUrl(rawUrl);
  if (normalizedUrl.isEmpty) return null;

  // A media_id means the backend owns access control for this object. The raw
  // Amazon S3 object URL in the message payload is intentionally not public,
  // so starting an image request with it can leave CachedNetworkImage attached
  // to a failed 403 request while the signed URL is being resolved.
  //
  // Keep the placeholder URL-less until _refreshPrivateMediaAccess replaces it
  // with the authenticated short-lived URL.
  final normalizedMediaId = mediaId?.trim() ?? '';
  final uri = Uri.tryParse(normalizedUrl);
  final hasSignature = uri?.queryParameters.keys.any(
        (key) => key.toLowerCase() == 'x-amz-signature',
      ) ??
      false;
  // The payload may contain an unsigned CloudFront, S3, or legacy storage
  // URL. Once media_id is present, the object is private; rendering the raw
  // URL first can poison the image cache with a transient 403/network failure
  // before the authenticated access URL arrives.
  if (normalizedMediaId.isNotEmpty && !hasSignature) {
    return null;
  }
  return normalizedUrl;
}

class PendingMessageSendGuard {
  final Map<String, CancelToken> _activeUploads = {};
  final Set<String> _cancelledMessageIds = {};

  CancelToken registerUpload(String messageId) {
    final token = CancelToken();
    if (_cancelledMessageIds.contains(messageId)) {
      token.cancel('message_cancelled');
    } else {
      _activeUploads[messageId] = token;
    }
    return token;
  }

  bool cancel(String messageId) {
    final firstCancellation = _cancelledMessageIds.add(messageId);
    _activeUploads.remove(messageId)?.cancel('message_cancelled');
    return firstCancellation;
  }

  bool isCancelled(String messageId) =>
      _cancelledMessageIds.contains(messageId);

  void uploadFinished(String messageId) {
    _activeUploads.remove(messageId);
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  void dispose() {
    for (final entry in _activeUploads.entries) {
      entry.value.cancel('message_provider_disposed');
    }
    _activeUploads.clear();
  }
}

class MessageItem {
  final String id;
  final String chatId;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String? senderNicknameColor;
  final String? senderEmojiAvatar;
  final int senderVipLevel;
  final String senderVipBadge;
  final String senderVipBadgeIcon;
  final bool senderVipActive;
  final MessageItemType type;
  final String content;
  final String? mediaId;
  final String? thumbnailMediaId;
  final String? mediaUrl;
  final String? localPath;
  final String? thumbnail;
  final String? mediaGroupId;
  final int? mediaWidth;
  final int? mediaHeight;
  final int? mediaSize;
  final int? mediaDuration;
  final String? fileName;
  final bool isOutgoing;
  final MessageStatus status;
  final bool isRead;
  final ReplyInfo? replyTo;
  final List<String>? mentions;
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
    this.senderEmojiAvatar,
    this.senderVipLevel = 0,
    this.senderVipBadge = '',
    this.senderVipBadgeIcon = '',
    this.senderVipActive = false,
    this.type = MessageItemType.text,
    required this.content,
    this.mediaId,
    this.thumbnailMediaId,
    this.mediaUrl,
    this.localPath,
    this.thumbnail,
    this.mediaGroupId,
    this.mediaWidth,
    this.mediaHeight,
    this.mediaSize,
    this.mediaDuration,
    this.fileName,
    this.isOutgoing = true,
    this.status = MessageStatus.sent,
    this.isRead = false,
    this.replyTo,
    this.mentions,
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
    Object? senderAvatar = _messageItemUnset,
    String? senderNicknameColor,
    String? senderEmojiAvatar,
    int? senderVipLevel,
    String? senderVipBadge,
    String? senderVipBadgeIcon,
    bool? senderVipActive,
    MessageItemType? type,
    String? content,
    String? mediaId,
    String? thumbnailMediaId,
    String? mediaUrl,
    String? localPath,
    String? thumbnail,
    String? mediaGroupId,
    int? mediaWidth,
    int? mediaHeight,
    int? mediaSize,
    int? mediaDuration,
    String? fileName,
    bool? isOutgoing,
    MessageStatus? status,
    bool? isRead,
    ReplyInfo? replyTo,
    List<String>? mentions,
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
      senderAvatar: identical(senderAvatar, _messageItemUnset)
          ? this.senderAvatar
          : senderAvatar as String?,
      senderNicknameColor: senderNicknameColor ?? this.senderNicknameColor,
      senderEmojiAvatar: senderEmojiAvatar ?? this.senderEmojiAvatar,
      senderVipLevel: senderVipLevel ?? this.senderVipLevel,
      senderVipBadge: senderVipBadge ?? this.senderVipBadge,
      senderVipBadgeIcon: senderVipBadgeIcon ?? this.senderVipBadgeIcon,
      senderVipActive: senderVipActive ?? this.senderVipActive,
      type: type ?? this.type,
      content: content ?? this.content,
      mediaId: mediaId ?? this.mediaId,
      thumbnailMediaId: thumbnailMediaId ?? this.thumbnailMediaId,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      localPath: localPath ?? this.localPath,
      thumbnail: thumbnail ?? this.thumbnail,
      mediaGroupId: mediaGroupId ?? this.mediaGroupId,
      mediaWidth: mediaWidth ?? this.mediaWidth,
      mediaHeight: mediaHeight ?? this.mediaHeight,
      mediaSize: mediaSize ?? this.mediaSize,
      mediaDuration: mediaDuration ?? this.mediaDuration,
      fileName: fileName ?? this.fileName,
      isOutgoing: isOutgoing ?? this.isOutgoing,
      status: status ?? this.status,
      isRead: isRead ?? this.isRead,
      replyTo: replyTo ?? this.replyTo,
      mentions: mentions ?? this.mentions,
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
    String? mediaId;
    String? thumbnailMediaId;
    String? mediaUrl;
    String? thumbnail;
    String? mediaGroupId;
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
          mediaId = msg.content.media!.mediaId;
          thumbnailMediaId = msg.content.media!.thumbnailMediaId;
          mediaUrl = _initialPrivateMediaDisplayUrl(
            mediaId,
            msg.content.media!.url,
          );
          thumbnail = _initialPrivateMediaDisplayUrl(
            thumbnailMediaId,
            msg.content.media!.thumbnail,
          );
          mediaGroupId = msg.content.media!.mediaGroupId;
          mediaWidth = msg.content.media!.width;
          mediaHeight = msg.content.media!.height;
          mediaSize = msg.content.media!.size;
        }
        break;
      case 3:
        type = MessageItemType.video;
        if (msg.content.media != null) {
          mediaId = msg.content.media!.mediaId;
          thumbnailMediaId = msg.content.media!.thumbnailMediaId;
          mediaUrl = _initialPrivateMediaDisplayUrl(
            mediaId,
            msg.content.media!.url,
          );
          thumbnail = _initialPrivateMediaDisplayUrl(
            thumbnailMediaId,
            msg.content.media!.thumbnail,
          );
          mediaGroupId = msg.content.media!.mediaGroupId;
          mediaWidth = msg.content.media!.width;
          mediaHeight = msg.content.media!.height;
          mediaSize = msg.content.media!.size;
          mediaDuration = msg.content.media!.duration;
        }
        break;
      case 4:
        type = MessageItemType.voice;
        if (msg.content.voice != null) {
          mediaId = msg.content.voice!.mediaId;
          mediaUrl = _initialPrivateMediaDisplayUrl(
            mediaId,
            msg.content.voice!.url,
          );
          mediaDuration = msg.content.voice!.duration;
          mediaSize = msg.content.voice!.size;
          content = msg.content.voice!.transcript ?? '';
        }
        break;
      case 5:
        type = MessageItemType.file;
        if (msg.content.file != null) {
          mediaId = msg.content.file!.mediaId;
          mediaUrl = _initialPrivateMediaDisplayUrl(
            mediaId,
            msg.content.file!.url,
          );
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
                  : _messageProviderLocationLabel());
        }
        break;
      case 8:
        type = MessageItemType.sticker;
        if (msg.content.sticker != null) {
          mediaUrl = _messageProviderStickerMediaUrl(msg.content.sticker!.url);
          content = msg.content.sticker!.emoji ?? '';
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
        mediaDuration = msg.content.callDuration;
        content = formatChatCallPreview(
          text: msg.content.text,
          callType: msg.content.callType,
          status: msg.content.callStatus,
          durationSeconds: msg.content.callDuration,
          isOutgoing: isOutgoing,
        ).summary;
        break;
      case 12:
        type = MessageItemType.redPacket;
        break;
      case 13:
        type = MessageItemType.transfer;
        break;
      case 14:
        type = MessageItemType.forwardBundle;
        content = jsonEncode(
          msg.content.forwardBundle ?? const <String, dynamic>{},
        );
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
    if (msg.type == 10 && msg.content.contact != null) {
      contactUserId = msg.content.contact!.userId;
      contactName = msg.content.contact!.nickname;
      contactAvatar = msg.content.contact!.avatar;
      contactUsername = msg.content.contact!.username;
      contactNicknameColor = msg.content.contact!.nicknameColor;
      contactEmojiAvatar = msg.content.contact!.emojiAvatar;
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
      senderEmojiAvatar: msg.senderEmojiAvatar,
      senderVipLevel: msg.senderVipLevel,
      senderVipBadge: msg.senderVipBadge,
      senderVipBadgeIcon: msg.senderVipBadgeIcon,
      senderVipActive: msg.senderVipActive,
      type: type,
      content: content,
      mediaId: mediaId,
      thumbnailMediaId: thumbnailMediaId,
      mediaUrl: mediaUrl,
      localPath: null,
      thumbnail: thumbnail,
      mediaGroupId: mediaGroupId,
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
      mentions: msg.mentions,
      createdAt: msg.createdAt,
      editedAt: msg.editedAt,
      isEdited: msg.isEdited,
      isDeleted: msg.isRevoked,
      revokedBy: msg.revokedBy,
      burnAfterRead: msg.burnAfterRead,
      burnAfterSeconds: msg.burnAfterSeconds,
      // Never render incoming burn-after-read content before the recipient
      // explicitly opens it. A persisted active countdown can unlock it later.
      burnLocked: msg.burnAfterRead && !isOutgoing,
      seq: msg.seq,
      reactions: reactions,
      contactUserId: contactUserId,
      contactName: contactName,
      contactAvatar: contactAvatar,
      contactUsername: contactUsername,
      contactNicknameColor: contactNicknameColor,
      contactEmojiAvatar: contactEmojiAvatar,
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

    var cachedType = _msgTypeToItemType(m.type);
    if (cachedType == MessageItemType.text &&
        _isForwardBundleEncodedContent(m.content)) {
      cachedType = MessageItemType.forwardBundle;
    }

    return MessageItem(
      id: m.id,
      chatId: m.chatId,
      senderId: m.senderId,
      senderName: m.senderName,
      senderAvatar: m.senderAvatar,
      senderNicknameColor: m.senderNicknameColor,
      senderEmojiAvatar: m.senderEmojiAvatar,
      type: cachedType,
      content: m.content,
      mediaId: m.mediaId,
      thumbnailMediaId: m.thumbnailMediaId,
      mediaUrl: m.remoteUrl,
      localPath: m.localPath,
      thumbnail: m.thumbnail,
      mediaGroupId: null,
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

int _latestReadableSeqBeforeLockedBurn(
  Iterable<MessageItem> messages,
  int requestedSeq,
) {
  if (requestedSeq <= 0) return 0;

  int? firstLockedBurnSeq;
  for (final message in messages) {
    final isUnopenedIncomingBurn = message.burnAfterRead &&
        !message.isOutgoing &&
        message.seq > 0 &&
        message.seq <= requestedSeq &&
        (message.burnCountdownSeconds == null ||
            message.burnCountdownSeconds! <= 0);
    if (!isUnopenedIncomingBurn) continue;

    if (firstLockedBurnSeq == null || message.seq < firstLockedBurnSeq) {
      firstLockedBurnSeq = message.seq;
    }
  }

  if (firstLockedBurnSeq == null) return requestedSeq;
  return firstLockedBurnSeq > 1 ? firstLockedBurnSeq - 1 : 0;
}

@visibleForTesting
int debugLatestReadableSeqBeforeLockedBurn(
  Iterable<MessageItem> messages,
  int requestedSeq,
) =>
    _latestReadableSeqBeforeLockedBurn(messages, requestedSeq);

List<MessageItem> _applyBurnedReceipt(
  Iterable<MessageItem> messages,
  int burnedThroughSeq,
) {
  if (burnedThroughSeq <= 0) return messages.toList(growable: false);

  return messages.map((message) {
    final isAffectedIncomingBurn = message.burnAfterRead &&
        !message.isOutgoing &&
        message.seq > 0 &&
        message.seq <= burnedThroughSeq;
    if (!isAffectedIncomingBurn) return message;

    // Keep already revealed content visible until its local countdown ends.
    // Unopened content remains as a locked placeholder instead of disappearing.
    final countdown = message.burnCountdownSeconds ?? 0;
    if (countdown > 0) return message;

    return message.copyWith(
      status: MessageStatus.read,
      isRead: true,
      burnLocked: true,
      burnCountdownSeconds: null,
    );
  }).toList(growable: false);
}

@visibleForTesting
List<MessageItem> debugApplyBurnedReceipt(
  Iterable<MessageItem> messages,
  int burnedThroughSeq,
) =>
    _applyBurnedReceipt(messages, burnedThroughSeq);

bool _isForwardBundleEncodedContent(String content) {
  if (!content.trimLeft().startsWith('{')) return false;
  try {
    final decoded = jsonDecode(content);
    return decoded is Map &&
        decoded['items'] is List &&
        decoded['title'] != null;
  } catch (_) {
    return false;
  }
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
    case MessageItemType.forwardBundle:
      // Keep the Isar enum schema stable; the JSON payload lets cached loads
      // restore the forwarded-record type below.
      return MsgType.text;
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
Future<void> persistMessageItemsToIsarCache(
  List<MessageItem> messages, {
  required String accountId,
}) async {
  if (PlatformUtils.isWeb) return;
  if (messages.isEmpty) return;
  if (accountId.isEmpty) return;
  if (!IsarService.instance.isAvailable) return;
  try {
    final cachedAt = DateTime.now();
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
        ..accountId = accountId
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
        ..localPath = msg.localPath
        ..remoteUrl = msg.mediaUrl
        ..mediaId = msg.mediaId
        ..thumbnail = msg.thumbnail
        ..thumbnailMediaId = msg.thumbnailMediaId
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
        ..cachedAt = cachedAt
        ..editedAt = msg.editedAt
        ..isDeleted = msg.isDeleted;
    }).toList();

    // A burst used to execute one Isar query per message to remove an old
    // row with the same seq. On a 500-member group this kept Isar workers and
    // the Flutter UI busy long after the network burst had finished. Read the
    // affected seq range once per chat and remove every stale row in the same
    // transaction instead.
    final modelsByChat = <String, List<MessageModel>>{};
    for (final model in models.where((model) => model.seq > 0)) {
      modelsByChat.putIfAbsent(model.chatId, () => <MessageModel>[]).add(model);
    }

    await IsarService.instance.isar.writeTxn(() async {
      final staleIds = <int>{};
      for (final entry in modelsByChat.entries) {
        final incomingBySeq = <int, String>{
          for (final model in entry.value) model.seq: model.id,
        };
        final seqs = incomingBySeq.keys;
        if (seqs.isEmpty) continue;
        final minSeq = seqs.reduce(math.min);
        final maxSeq = seqs.reduce(math.max);
        final existing = await IsarService.instance.isar.messageModels
            .filter()
            .accountIdEqualTo(accountId)
            .chatIdEqualTo(entry.key)
            .seqBetween(minSeq, maxSeq)
            .findAll();
        for (final cached in existing) {
          final incomingId = incomingBySeq[cached.seq];
          if (incomingId != null && incomingId != cached.id) {
            staleIds.add(cached.isarId);
          }
        }
      }
      if (staleIds.isNotEmpty) {
        await IsarService.instance.isar.messageModels.deleteAll(
          staleIds.toList(growable: false),
        );
      }
      await IsarService.instance.isar.messageModels.putAll(models);
    });
  } catch (e) {
    debugPrint('[IsarCache] persistMessageItemsToIsarCache failed: $e');
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

List<MessageItem> debugApplyUserProfileToMessages(
  List<MessageItem> messages, {
  required String userId,
  String? name,
  bool avatarProvided = false,
  String? avatar,
  String? nicknameColor,
  String? emojiAvatar,
}) {
  return messages.map((message) {
    if (message.senderId != userId) return message;
    return message.copyWith(
      senderName: name?.trim().isNotEmpty == true ? name!.trim() : null,
      senderAvatar: avatarProvided ? avatar : _messageItemUnset,
      senderNicknameColor: nicknameColor,
      senderEmojiAvatar: emojiAvatar,
    );
  }).toList();
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
  forwardBundle,
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
    case 14:
      return MessageItemType.forwardBundle;
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

int _messageStatusRank(MessageStatus status) {
  switch (status) {
    case MessageStatus.sending:
      return 0;
    case MessageStatus.failed:
      return 1;
    case MessageStatus.sent:
      return 2;
    case MessageStatus.delivered:
      return 3;
    case MessageStatus.read:
      return 4;
  }
}

int _compareMessagesNewestFirst(MessageItem a, MessageItem b) {
  if (a.seq > 0 && b.seq > 0 && a.seq != b.seq) {
    return b.seq.compareTo(a.seq);
  }
  return b.createdAt.compareTo(a.createdAt);
}

MessageItem _preferReliableMessage(MessageItem current, MessageItem incoming) {
  final incomingHasServerSeq = incoming.seq > 0;
  final currentHasServerSeq = current.seq > 0;

  if (incomingHasServerSeq && !currentHasServerSeq) {
    return incoming.copyWith(
      createdAt: current.createdAt.isBefore(incoming.createdAt)
          ? current.createdAt
          : incoming.createdAt,
    );
  }
  if (!incomingHasServerSeq && currentHasServerSeq) {
    return current;
  }
  if (incomingHasServerSeq && currentHasServerSeq) {
    if (incoming.seq > current.seq) return incoming;
    if (incoming.seq < current.seq) return current;
  }

  final incomingRank = _messageStatusRank(incoming.status);
  final currentRank = _messageStatusRank(current.status);
  if (incomingRank > currentRank) return incoming;
  if (incomingRank < currentRank) return current;

  if (current.id.startsWith('local_') && !incoming.id.startsWith('local_')) {
    return incoming;
  }
  if (!current.id.startsWith('local_') && incoming.id.startsWith('local_')) {
    return current;
  }

  return incoming.createdAt.isAfter(current.createdAt) ? incoming : current;
}

List<MessageItem> _dedupeWalletMessageWindow(List<MessageItem> messages) {
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

    final preferIncoming = msg.seq > existing.seq ||
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

List<MessageItem> _dedupeReliableMessageWindow(List<MessageItem> messages) {
  final byId = <String, MessageItem>{};
  final noId = <MessageItem>[];

  for (final msg in messages) {
    if (msg.id.isEmpty) {
      noId.add(msg);
      continue;
    }
    final existing = byId[msg.id];
    byId[msg.id] =
        existing == null ? msg : _preferReliableMessage(existing, msg);
  }

  final bySeq = <String, MessageItem>{};
  final noSeq = <MessageItem>[];
  for (final msg in [...byId.values, ...noId]) {
    if (msg.seq <= 0) {
      noSeq.add(msg);
      continue;
    }
    final key = '${msg.chatId}:${msg.seq}';
    final existing = bySeq[key];
    bySeq[key] = existing == null ? msg : _preferReliableMessage(existing, msg);
  }

  final result = _dedupeWalletMessageWindow([...bySeq.values, ...noSeq])
    ..sort(_compareMessagesNewestFirst);
  return result;
}

@visibleForTesting
List<MessageItem> debugDedupeReliableMessageWindow(
  List<MessageItem> messages,
) =>
    _dedupeReliableMessageWindow(messages);

int _oldestPositiveSeq(List<MessageItem> messages) {
  var oldest = 0;
  for (final msg in messages) {
    if (msg.seq <= 0) continue;
    if (oldest == 0 || msg.seq < oldest) {
      oldest = msg.seq;
    }
  }
  return oldest;
}

bool _shouldBackfillInitialHistoryWindow(
  List<MessageItem> messages, {
  int targetSize = 30,
}) {
  if (messages.length >= targetSize) return false;
  return _oldestPositiveSeq(messages) > 1;
}

@visibleForTesting
bool debugShouldBackfillInitialHistoryWindow(
  List<MessageItem> messages, {
  int targetSize = 30,
}) =>
    _shouldBackfillInitialHistoryWindow(messages, targetSize: targetSize);

List<MessageItem> _mergeReliableSyncedWindow(
  List<MessageItem> current,
  List<MessageItem> incoming,
) {
  if (incoming.isEmpty) return _dedupeReliableMessageWindow(current);

  final existingIds = current.map((m) => m.id).toSet();
  final existingSeqs = current
      .where((m) => m.seq > 0)
      .map((m) => '${m.chatId}:${m.seq}')
      .toSet();
  final uniqueIncoming = incoming.where((msg) {
    if (existingIds.contains(msg.id)) return false;
    if (msg.seq > 0 && existingSeqs.contains('${msg.chatId}:${msg.seq}')) {
      return false;
    }
    return true;
  });

  return _dedupeReliableMessageWindow([...uniqueIncoming, ...current]);
}

MessageItem _applyServerSnapshot(
  MessageItem current,
  MessageItem incoming,
) {
  final currentStatusRank = _messageStatusRank(current.status);
  final incomingStatusRank = _messageStatusRank(incoming.status);

  return incoming.copyWith(
    createdAt: current.createdAt,
    localPath: current.localPath,
    thumbnail: incoming.thumbnail ?? current.thumbnail,
    status: currentStatusRank > incomingStatusRank
        ? current.status
        : incoming.status,
    isRead: current.isRead || incoming.isRead,
    burnLocked: current.burnLocked || incoming.burnLocked,
    burnCountdownSeconds:
        incoming.burnCountdownSeconds ?? current.burnCountdownSeconds,
  );
}

/// Reconciles a recent authoritative server snapshot with the current window.
///
/// Unlike seq-based delta sync, this deliberately replaces messages with the
/// same id so edits/revokes/reactions that keep their original seq are healed
/// after a missed websocket event.
List<MessageItem> _reconcileReliableMessageWindow(
  List<MessageItem> current,
  List<MessageItem> incoming,
) {
  if (incoming.isEmpty) return _dedupeReliableMessageWindow(current);

  final currentById = <String, MessageItem>{
    for (final message in current.where((message) => message.id.isNotEmpty))
      message.id: message,
  };
  final incomingIds = incoming
      .where((message) => message.id.isNotEmpty)
      .map((message) => message.id)
      .toSet();
  final incomingSeqs = incoming
      .where((message) => message.seq > 0)
      .map((message) => '${message.chatId}:${message.seq}')
      .toSet();

  final authoritative = incoming.map((message) {
    final existing = currentById[message.id];
    return existing == null ? message : _applyServerSnapshot(existing, message);
  });
  final preserved = current.where((message) {
    if (incomingIds.contains(message.id)) return false;
    if (message.seq > 0 &&
        incomingSeqs.contains('${message.chatId}:${message.seq}')) {
      return false;
    }
    return true;
  });

  return _dedupeReliableMessageWindow([...authoritative, ...preserved]);
}

@visibleForTesting
List<MessageItem> debugMergeReliableSyncedWindow(
  List<MessageItem> current,
  List<MessageItem> incoming,
) =>
    _mergeReliableSyncedWindow(current, incoming);

@visibleForTesting
List<MessageItem> debugReconcileReliableMessageWindow(
  List<MessageItem> current,
  List<MessageItem> incoming,
) =>
    _reconcileReliableMessageWindow(current, incoming);

/// Serializes message send requests in the order the user submitted them.
///
/// The server allocates the authoritative conversation sequence when a request
/// arrives. Without a client-side queue, rapid HTTP requests can overtake each
/// other and receive server sequences in a different order than the UI actions.
class SequentialMessageSendQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    final previous = _tail;
    _tail = previous.then((_) async {
      try {
        completer.complete(await task());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

Map<String, dynamic> _messageItemToCacheJson(MessageItem msg) => {
      'id': msg.id,
      'chat_id': msg.chatId,
      'sender_id': msg.senderId,
      'sender_name': msg.senderName,
      'sender_avatar': msg.senderAvatar,
      'sender_nickname_color': msg.senderNicknameColor,
      'sender_emoji_avatar': msg.senderEmojiAvatar,
      'type': msg.type.name,
      'content': msg.content,
      'media_id': msg.mediaId,
      'thumbnail_media_id': msg.thumbnailMediaId,
      'media_url': msg.mediaUrl,
      'local_path': msg.localPath,
      'thumbnail': msg.thumbnail,
      'media_group_id': msg.mediaGroupId,
      'media_width': msg.mediaWidth,
      'media_height': msg.mediaHeight,
      'media_size': msg.mediaSize,
      'media_duration': msg.mediaDuration,
      'file_name': msg.fileName,
      'is_outgoing': msg.isOutgoing,
      'status': msg.status.name,
      'is_read': msg.isRead,
      'reply_to': msg.replyTo == null
          ? null
          : {
              'message_id': msg.replyTo!.messageId,
              'sender_name': msg.replyTo!.senderName,
              'content': msg.replyTo!.content,
            },
      'mentions': msg.mentions,
      'created_at': msg.createdAt.toIso8601String(),
      'edited_at': msg.editedAt?.toIso8601String(),
      'is_edited': msg.isEdited,
      'is_deleted': msg.isDeleted,
      'revoked_by': msg.revokedBy,
      'burn_after_read': msg.burnAfterRead,
      'burn_after_seconds': msg.burnAfterSeconds,
      'burn_locked': msg.burnLocked,
      'burn_countdown_seconds': msg.burnCountdownSeconds,
      'seq': msg.seq,
      'reactions': msg.reactions.map((r) => r.toJson()).toList(),
      'upload_progress': msg.uploadProgress,
      'contact_user_id': msg.contactUserId,
      'contact_name': msg.contactName,
      'contact_avatar': msg.contactAvatar,
      'contact_username': msg.contactUsername,
      'contact_nickname_color': msg.contactNicknameColor,
      'contact_emoji_avatar': msg.contactEmojiAvatar,
      'location_latitude': msg.locationLatitude,
      'location_longitude': msg.locationLongitude,
      'location_title': msg.locationTitle,
      'location_address': msg.locationAddress,
    };

MessageItem? _messageItemFromCacheJson(Object? raw) {
  if (raw is! Map) return null;
  try {
    final json = Map<String, dynamic>.from(raw);
    final replyRaw = json['reply_to'];
    ReplyInfo? replyTo;
    if (replyRaw is Map) {
      final reply = Map<String, dynamic>.from(replyRaw);
      final messageId = reply['message_id']?.toString() ?? '';
      if (messageId.isNotEmpty) {
        replyTo = ReplyInfo(
          messageId: messageId,
          senderName: reply['sender_name']?.toString() ?? '',
          content: reply['content']?.toString() ?? '',
        );
      }
    }

    final reactionsRaw = json['reactions'];
    final reactions = reactionsRaw is List
        ? reactionsRaw
            .whereType<Map>()
            .map(
              (e) => MessageReaction.fromJson(Map<String, dynamic>.from(e)),
            )
            .toList()
        : <MessageReaction>[];
    final mentionsRaw = json['mentions'];
    final mentions = mentionsRaw is List
        ? mentionsRaw
            .map((item) => item.toString())
            .where((id) => id.isNotEmpty)
            .toList()
        : null;

    return MessageItem(
      id: json['id']?.toString() ?? '',
      chatId: json['chat_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? '',
      senderAvatar: json['sender_avatar']?.toString(),
      senderNicknameColor: json['sender_nickname_color']?.toString(),
      senderEmojiAvatar: json['sender_emoji_avatar']?.toString(),
      type: MessageItemType.values.byName(
        json['type']?.toString() ?? MessageItemType.text.name,
      ),
      content: json['content']?.toString() ?? '',
      mediaId: json['media_id']?.toString(),
      thumbnailMediaId: json['thumbnail_media_id']?.toString(),
      mediaUrl: json['media_url']?.toString(),
      localPath: json['local_path']?.toString(),
      thumbnail: json['thumbnail']?.toString(),
      mediaGroupId: json['media_group_id']?.toString(),
      mediaWidth: (json['media_width'] as num?)?.toInt(),
      mediaHeight: (json['media_height'] as num?)?.toInt(),
      mediaSize: (json['media_size'] as num?)?.toInt(),
      mediaDuration: (json['media_duration'] as num?)?.toInt(),
      fileName: json['file_name']?.toString(),
      isOutgoing: json['is_outgoing'] == true,
      status: MessageStatus.values.byName(
        json['status']?.toString() ?? MessageStatus.sent.name,
      ),
      isRead: json['is_read'] == true,
      replyTo: replyTo,
      mentions: mentions,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      editedAt: DateTime.tryParse(json['edited_at']?.toString() ?? ''),
      isEdited: json['is_edited'] == true,
      isDeleted: json['is_deleted'] == true,
      revokedBy: json['revoked_by']?.toString(),
      burnAfterRead: json['burn_after_read'] == true,
      burnAfterSeconds: (json['burn_after_seconds'] as num?)?.toInt() ?? 0,
      burnLocked: json['burn_locked'] == true,
      burnCountdownSeconds: (json['burn_countdown_seconds'] as num?)?.toInt(),
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      reactions: reactions,
      uploadProgress: (json['upload_progress'] as num?)?.toDouble(),
      contactUserId: json['contact_user_id']?.toString(),
      contactName: json['contact_name']?.toString(),
      contactAvatar: json['contact_avatar']?.toString(),
      contactUsername: json['contact_username']?.toString(),
      contactNicknameColor: json['contact_nickname_color']?.toString(),
      contactEmojiAvatar: json['contact_emoji_avatar']?.toString(),
      locationLatitude: (json['location_latitude'] as num?)?.toDouble(),
      locationLongitude: (json['location_longitude'] as num?)?.toDouble(),
      locationTitle: json['location_title']?.toString(),
      locationAddress: json['location_address']?.toString(),
    );
  } catch (_) {
    return null;
  }
}

class _MessageMemoryEntry {
  _MessageMemoryEntry(this.messages) : touchedAt = DateTime.now();

  final List<MessageItem> messages;
  DateTime touchedAt;
}

/// 进程内最近消息窗口，用于页面返回时立即恢复；它是加速层，不是可靠持久化来源。
///
/// key 同时包含账号和会话，防止切换账号后复用同一 chatId 的旧窗口。
class MessageMemoryWindowCache {
  MessageMemoryWindowCache._();

  static const int maxChats = 10;
  static const int maxMessagesPerChat = 120;
  static final LinkedHashMap<String, _MessageMemoryEntry> _entries =
      LinkedHashMap<String, _MessageMemoryEntry>();

  static String _key(String accountId, String chatId) => '$accountId:$chatId';

  static List<MessageItem> read({
    required String accountId,
    required String chatId,
  }) {
    if (accountId.isEmpty || chatId.isEmpty) return const [];
    final key = _key(accountId, chatId);
    final entry = _entries.remove(key);
    if (entry == null) return const [];
    entry.touchedAt = DateTime.now();
    _entries[key] = entry;
    return List<MessageItem>.of(entry.messages);
  }

  static void write({
    required String accountId,
    required String chatId,
    required List<MessageItem> messages,
  }) {
    if (accountId.isEmpty || chatId.isEmpty || messages.isEmpty) return;
    final key = _key(accountId, chatId);
    final merged = <String, MessageItem>{};
    _entries.remove(key);
    for (final message in messages) {
      if (message.chatId == chatId) {
        merged[message.id] = message;
      }
    }
    final window = _dedupeReliableMessageWindow(merged.values.toList());
    _entries[key] = _MessageMemoryEntry(
      window.take(maxMessagesPerChat).toList(),
    );
    while (_entries.length > maxChats) {
      _entries.remove(_entries.keys.first);
    }
  }

  static void remove({required String accountId, required String chatId}) {
    if (accountId.isEmpty || chatId.isEmpty) return;
    _entries.remove(_key(accountId, chatId));
  }
}

const int kActiveRealtimeMessageWindowLimit = 200;

/// Bounds the list that participates in every active-page rebuild while keeping
/// pending/failed outgoing rows available for retry.
List<MessageItem> boundActiveRealtimeMessageWindow(
  Iterable<MessageItem> messages, {
  int limit = kActiveRealtimeMessageWindowLimit,
}) {
  if (limit <= 0) return const <MessageItem>[];
  final ordered = _dedupeReliableMessageWindow(messages.toList());
  if (ordered.length <= limit) return ordered;

  final window = ordered.take(limit).toList(growable: true);
  final includedIds = window.map((message) => message.id).toSet();
  final pendingOutsideWindow = ordered.skip(limit).where(
        (message) =>
            message.status == MessageStatus.sending ||
            message.status == MessageStatus.failed,
      );
  for (final pending in pendingOutsideWindow) {
    if (!includedIds.add(pending.id)) continue;
    final replaceAt = window.lastIndexWhere(
      (message) =>
          message.status != MessageStatus.sending &&
          message.status != MessageStatus.failed,
    );
    if (replaceAt < 0) break;
    includedIds.remove(window[replaceAt].id);
    window[replaceAt] = pending;
  }
  window.sort(_compareMessagesNewestFirst);
  return window;
}

/// Coalesces high-frequency message updates into one local-storage transaction.
/// The latest snapshot for each message id wins inside a batch.
class MessagePersistenceBatcher {
  MessagePersistenceBatcher(
    this._writer, {
    this.delay = const Duration(milliseconds: 120),
    this.flushThreshold = 64,
  });

  final Future<void> Function(List<MessageItem>) _writer;
  final Duration delay;
  final int flushThreshold;
  final Map<String, MessageItem> _pending = <String, MessageItem>{};
  Timer? _timer;
  bool _isFlushing = false;
  bool _isClosed = false;

  int get pendingCount => _pending.length;

  void addAll(Iterable<MessageItem> messages) {
    if (_isClosed) return;
    for (final message in messages) {
      _pending[message.id] = message;
    }
    if (_pending.isEmpty) return;

    if (_pending.length >= flushThreshold) {
      _timer?.cancel();
      _timer = null;
      unawaited(flushNow());
      return;
    }
    _timer ??= Timer(delay, () {
      _timer = null;
      unawaited(flushNow());
    });
  }

  Future<void> flushNow() async {
    if (_isFlushing || _pending.isEmpty) return;
    _timer?.cancel();
    _timer = null;
    _isFlushing = true;
    final batch = _pending.values.toList(growable: false);
    _pending.clear();
    try {
      await _writer(batch);
    } finally {
      _isFlushing = false;
      if (_pending.isNotEmpty && !_isClosed) {
        _timer = Timer(Duration.zero, () {
          _timer = null;
          unawaited(flushNow());
        });
      }
    }
  }

  Future<void> close() async {
    if (_isClosed) return;
    _isClosed = true;
    _timer?.cancel();
    _timer = null;
    while (_isFlushing) {
      await Future<void>.delayed(Duration.zero);
    }
    await flushNow();
  }
}

Future<int> readWebMessageWindowMaxSeq({
  required String accountId,
  required String chatId,
}) async {
  if (accountId.isEmpty || chatId.isEmpty) return 0;
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('message_window_${accountId}_$chatId');
    if (raw == null || raw.isEmpty) return 0;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return 0;
    var maxSeq = 0;
    for (final item in decoded) {
      if (item is! Map) continue;
      final seq = (item['seq'] as num?)?.toInt() ?? 0;
      if (seq > maxSeq) maxSeq = seq;
    }
    return maxSeq;
  } catch (_) {
    return 0;
  }
}

Future<void> persistMessageItemsToWebWindowCache(
  List<MessageItem> messages, {
  required String accountId,
  required String chatId,
}) async {
  if (accountId.isEmpty || chatId.isEmpty || messages.isEmpty) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final key = 'message_window_${accountId}_$chatId';
    final existingRaw = prefs.getString(key);
    final existing = <MessageItem>[];
    if (existingRaw != null && existingRaw.isNotEmpty) {
      final decoded = jsonDecode(existingRaw);
      if (decoded is List) {
        existing.addAll(
          decoded.map(_messageItemFromCacheJson).whereType<MessageItem>(),
        );
      }
    }
    final merged = <String, MessageItem>{};
    for (final message in [...messages, ...existing]) {
      if (message.chatId == chatId) {
        merged[message.id] = message;
      }
    }
    final window = _dedupeReliableMessageWindow(merged.values.toList());
    await prefs.setString(
      key,
      jsonEncode(window.take(100).map(_messageItemToCacheJson).toList()),
    );
  } catch (e) {
    debugPrint('[Message] persist web prewarm cache failed: $e');
  }
}

final messageListProvider = StateNotifierProvider.family
    .autoDispose<MessageListNotifier, List<MessageItem>, String>((ref, chatId) {
  // Provider 生命周期绑定账号 UUID；切换账号会创建全新 Notifier，旧账号异步结果无法复用。
  // Rebuild with the account uuid so keepAlive never holds the previous user context after account switching.
  // This keeps Isar/API identities aligned when ChatDetailPage triggers initialize() again via ref.listen.
  final currentUserId = ref.watch(currentAccountIdProvider);

  // 离开页面后短暂保活减少往返闪烁，超时仍释放 WS handler、计时器和上传状态。
  final link = ref.keepAlive();
  Timer? timer;
  ref.onDispose(() => timer?.cancel());
  ref.onCancel(() {
    timer?.cancel();
    timer = Timer(const Duration(seconds: 30), () => link.close());
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

/// 单会话消息状态机，协调乐观发送、实时回显、HTTP 补洞和平台缓存。
///
/// `state` 是当前页面窗口；原生 Isar/Web 缓存可恢复，服务端 seq 是最终顺序依据。
class MessageListNotifier extends StateNotifier<List<MessageItem>> {
  final String chatId;
  final api.ChatService _chatService;
  final WebSocketService _wsService;
  final ApiClient _apiClient;
  late final S3DirectUploadService _s3DirectUpload =
      S3DirectUploadService(_apiClient);
  final String _currentUserId;
  final _uuid = const Uuid();
  final SequentialMessageSendQueue _textSendQueue =
      SequentialMessageSendQueue();
  final PendingMessageSendGuard _pendingSendGuard = PendingMessageSendGuard();
  late final MessagePersistenceBatcher _persistenceBatcher;

  bool _isLoadingMore = false;
  bool _isInitializing = false;
  bool _hasLoadedInitial = false;
  bool _hasMore = true;
  bool _isActive = false; // Whether the current chat page is active
  Set<String>? _cachedDeletedIds;
  Map<String, Map<String, dynamic>>? _cachedBurnState;
  final Map<String, Timer> _burnTimers = {};
  Timer? _privateMediaRefreshTimer;
  Timer? _privateMediaRefreshDebounce;
  bool _isRefreshingPrivateMedia = false;
  bool _privateMediaRefreshPending = false;
  bool _privateMediaForceRefreshPending = false;
  Timer? _readReceiptTimer;
  int _pendingReadReceiptSeq = 0;
  final Map<String, api.Message> _pendingWebSocketMessages =
      <String, api.Message>{};
  Timer? _webSocketMessageBatchTimer;
  static const Duration _webSocketMessageBatchDelay =
      Duration(milliseconds: 50);
  int? _lastSeq;
  bool _isSyncing = false;
  bool _isReconcilingRecent = false;
  late final Function(dynamic) _newMessageHandler;
  late final Function(dynamic) _messageRevokedHandler;
  late final Function(dynamic) _deliveryReceiptHandler;
  late final Function(dynamic) _readReceiptHandler;
  late final Function(dynamic) _reactionHandler;
  late final Function(dynamic) _messageEditedHandler;
  late final Function(dynamic) _reconnectedHandler;
  late final Function(dynamic) _chatHistoryClearedHandler;
  late final Function(dynamic) _messageBurnedHandler;
  late final Function(dynamic) _userProfileHandler;

  MessageListNotifier(
    this.chatId,
    this._chatService,
    this._wsService,
    this._apiClient,
    this._currentUserId,
  ) : super(
          MessageMemoryWindowCache.read(
            accountId: _currentUserId,
            chatId: chatId,
          ),
        ) {
    _persistenceBatcher = MessagePersistenceBatcher(_persistMessagesNow);
    _hasLoadedInitial = state.isNotEmpty;
    _setupWebSocketHandlers();
    _privateMediaRefreshTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _schedulePrivateMediaRefresh(forceRefresh: true),
    );
    _schedulePrivateMediaRefresh();
  }

  bool get hasLoadedInitial => _hasLoadedInitial;

  void _rememberCurrentWindow() {
    if (state.isEmpty) {
      MessageMemoryWindowCache.remove(
        accountId: _currentUserId,
        chatId: chatId,
      );
      return;
    }
    MessageMemoryWindowCache.write(
      accountId: _currentUserId,
      chatId: chatId,
      messages: state,
    );
    _schedulePrivateMediaRefresh();
  }

  void _schedulePrivateMediaRefresh({bool forceRefresh = false}) {
    if (!mounted) return;
    _privateMediaRefreshDebounce?.cancel();
    _privateMediaRefreshDebounce = Timer(
      const Duration(milliseconds: 50),
      () => unawaited(
        _refreshPrivateMediaAccess(forceRefresh: forceRefresh),
      ),
    );
  }

  Future<void> _refreshPrivateMediaAccess({
    bool forceRefresh = false,
  }) async {
    if (!mounted) return;
    if (_isRefreshingPrivateMedia) {
      _privateMediaRefreshPending = true;
      _privateMediaForceRefreshPending |= forceRefresh;
      return;
    }
    final mediaIDs = <String>{};
    for (final message in state) {
      if (message.isDeleted) continue;
      final mediaID = message.mediaId?.trim() ?? '';
      final thumbnailMediaID = message.thumbnailMediaId?.trim() ?? '';
      if (mediaID.isNotEmpty) mediaIDs.add(mediaID);
      if (thumbnailMediaID.isNotEmpty) mediaIDs.add(thumbnailMediaID);
    }
    if (mediaIDs.isEmpty) return;

    _isRefreshingPrivateMedia = true;
    final resolved = <String, String>{};
    final ids = mediaIDs.toList(growable: false);
    try {
      const batchSize = 200;
      for (var start = 0; start < ids.length; start += batchSize) {
        final end = math.min(start + batchSize, ids.length);
        try {
          resolved.addAll(
            await _s3DirectUpload.resolveAccessURLs(
              ids.sublist(start, end),
              forceRefresh: forceRefresh,
            ),
          );
        } catch (error) {
          debugPrint(
            '[Message] Resolve private media batch failed: '
            'count=${end - start} error=$error',
          );
        }
      }
      if (!mounted || resolved.isEmpty) return;
      var changed = false;
      final next = state.map((message) {
        final mediaURL = resolved[message.mediaId?.trim()];
        final thumbnailURL = resolved[message.thumbnailMediaId?.trim()];
        final nextMediaURL = mediaURL ?? message.mediaUrl;
        final nextThumbnailURL = thumbnailURL ?? message.thumbnail;
        if (nextMediaURL == message.mediaUrl &&
            nextThumbnailURL == message.thumbnail) {
          return message;
        }
        changed = true;
        return message.copyWith(
          mediaUrl: nextMediaURL,
          thumbnail: nextThumbnailURL,
        );
      }).toList(growable: false);
      if (changed) {
        state = next;
      }
    } finally {
      _isRefreshingPrivateMedia = false;
      if (mounted && _privateMediaRefreshPending) {
        final pendingForceRefresh = _privateMediaForceRefreshPending;
        _privateMediaRefreshPending = false;
        _privateMediaForceRefreshPending = false;
        _schedulePrivateMediaRefresh(
          forceRefresh: pendingForceRefresh,
        );
      }
    }
  }

  bool _hydrateFromMemoryCache() {
    if (state.isNotEmpty) return false;
    final cached = MessageMemoryWindowCache.read(
      accountId: _currentUserId,
      chatId: chatId,
    );
    if (cached.isEmpty) return false;
    state = _mergeLoadedMessages(cached);
    _reconcileBurnStateFromCurrentMessages();
    PerformanceTraceService.mark(
      'message_memory_hit chat=$chatId count=${cached.length}',
    );
    return true;
  }

  void _setupWebSocketHandlers() {
    // 同一新消息可能经聊天列表桥接和本 Provider 的 handler 到达，合并阶段必须保持幂等。
    // Listen for new WebSocket messages, including call-related system messages.
    _newMessageHandler = (data) async {
      if (!mounted) return;
      final rawMsg = data['message'];
      if (rawMsg == null) return;
      if (rawMsg is! Map) {
        debugPrint(
          '[Message] WS new_message: expected message object, got ${rawMsg.runtimeType}',
        );
        return;
      }
      try {
        final message = await _chatService.parseIncomingMessage(
          Map<String, dynamic>.from(rawMsg),
        );
        _queueWebSocketMessage(message);
      } catch (e, st) {
        debugPrint('[Message] WS new_message fromJson failed: $e');
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

    _deliveryReceiptHandler = (data) {
      if (!mounted) return;
      final msgChatId = data['chat_id']?.toString();
      final deliveredUserId = data['user_id']?.toString();
      final msgSeq = data['msg_seq'];
      if (deliveredUserId == _currentUserId) return;
      if (msgChatId == chatId && msgSeq != null) {
        final seq =
            msgSeq is int ? msgSeq : int.tryParse(msgSeq.toString()) ?? 0;
        _markMessagesAsDelivered(seq);
      }
    };
    _wsService.registerHandler(
      WSMessageType.delivered,
      _deliveryReceiptHandler,
    );
    _wsService.registerHandler(
      WSMessageType.messageDelivered,
      _deliveryReceiptHandler,
    );

    // Listen for read-receipt broadcasts from other users in the same chat.
    _readReceiptHandler = (data) {
      if (!mounted) return;
      final msgChatId = data['chat_id'] as String?;
      final readUserId = data['user_id'] as String?;
      final msgSeq = data['msg_seq'];
      // Ignore read receipts sent by the current user because SendToChat broadcasts to everyone.
      if (readUserId == _currentUserId) return;
      debugPrint(
        '[Message] Received read receipt from $readUserId: chatId=$msgChatId, seq=$msgSeq',
      );
      if (msgChatId == chatId && msgSeq != null) {
        final seq =
            msgSeq is int ? msgSeq : int.tryParse(msgSeq.toString()) ?? 0;
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
            debugPrint('[Message] parse edited message failed: $e');
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
      debugPrint('[Message] Reconnected, reliable sync for chat $chatId');
      unawaited(ensureReliableSync(reason: 'ws_reconnected'));
    };
    _wsService.registerHandler(WSMessageType.reconnected, _reconnectedHandler);

    _chatHistoryClearedHandler = (data) {
      if (!mounted) return;
      final msgChatId = data['chat_id']?.toString();
      if (msgChatId != chatId) return;
      debugPrint('[Message] Chat history cleared event: chatId=$chatId');
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
      _syncBurnedIncomingMessagesUpToSeq(msgSeq);
    };
    _wsService.registerHandler('message_burned', _messageBurnedHandler);

    _userProfileHandler = (data) {
      if (!mounted || data is! Map) return;
      _applyUserProfileUpdate(Map<String, dynamic>.from(data));
    };
    _wsService.registerHandler('user_profile', _userProfileHandler);
  }

  void _applyUserProfileUpdate(Map<String, dynamic> data) {
    final userId = data['user_id']?.toString().trim() ?? '';
    if (userId.isEmpty || state.isEmpty) return;

    final avatarProvided = data.containsKey('avatar');
    String? avatarUrl;
    if (avatarProvided) {
      final rawAvatar = data['avatar']?.toString().trim() ?? '';
      avatarUrl = rawAvatar.isEmpty ? null : ApiConfig.getMediaUrl(rawAvatar);
    }

    final previous = state;
    final next = debugApplyUserProfileToMessages(
      previous,
      userId: userId,
      name: (data['nickname'] ?? data['name'])?.toString(),
      avatarProvided: avatarProvided,
      avatar: avatarUrl,
      nicknameColor: data['nickname_color']?.toString(),
      emojiAvatar: data['emoji_avatar']?.toString(),
    );
    final updated = <MessageItem>[];
    for (var index = 0; index < previous.length; index++) {
      if (!identical(previous[index], next[index])) {
        updated.add(next[index]);
      }
    }
    if (updated.isEmpty) return;

    if (avatarProvided && !PlatformUtils.isWeb) {
      final oldAvatarUrls = previous
          .where((message) => message.senderId == userId)
          .map((message) => message.senderAvatar?.trim() ?? '')
          .where((url) => url.isNotEmpty && url != avatarUrl)
          .toSet();
      unawaited(_refreshAvatarCache(oldAvatarUrls, avatarUrl));
    }

    state = next;
    unawaited(_saveMessagesToLocal(updated));
  }

  Future<void> _refreshAvatarCache(
    Set<String> oldAvatarUrls,
    String? avatarUrl,
  ) async {
    for (final oldAvatarUrl in oldAvatarUrls) {
      try {
        await AvatarCacheManager.removeFile(oldAvatarUrl);
      } catch (_) {}
    }
    if (avatarUrl == null || avatarUrl.isEmpty) return;
    try {
      await AvatarCacheManager.prefetch(avatarUrl);
    } catch (_) {}
  }

  void handleRealtimeMessage(
    api.Message message, {
    String source = 'realtime',
  }) {
    if (!mounted || message.chatId != chatId) return;
    if (_pendingSendGuard.isCancelled(message.msgId)) {
      if (message.senderId == _currentUserId) {
        unawaited(_chatService.revokeMessage(chatId, message.msgId));
      }
      debugPrint('[Message] Suppressed cancelled send echo: ${message.msgId}');
      return;
    }

    final previousMaxSeq = _maxKnownSeq();
    _addNewMessage(message);
    _boundRealtimeWindow();
    _schedulePrivateMediaRefresh();
    final item = MessageItem.fromApiMessage(message, _currentUserId);
    unawaited(_saveMessagesToLocal([item]));

    if (previousMaxSeq > 0 && message.seq > previousMaxSeq + 1 && !_isSyncing) {
      debugPrint(
        '[Message] Realtime seq gap ($source): local=$previousMaxSeq incoming=${message.seq}',
      );
      unawaited(_deltaSyncAfterReconnect());
    }

    if (message.type == 99) {
      _checkAndRefreshWalletBubbles(message);
    }
  }

  void _queueWebSocketMessage(api.Message message) {
    if (!mounted || message.chatId != chatId) return;
    final key = message.msgId.isNotEmpty
        ? message.msgId
        : '${message.chatId}:${message.seq}:${message.senderId}';
    _pendingWebSocketMessages[key] = message;
    _webSocketMessageBatchTimer ??= Timer(
      _webSocketMessageBatchDelay,
      _flushWebSocketMessageBatch,
    );
  }

  void _flushWebSocketMessageBatch() {
    _webSocketMessageBatchTimer = null;
    if (!mounted || _pendingWebSocketMessages.isEmpty) return;
    final messages = _pendingWebSocketMessages.values.toList(growable: false);
    _pendingWebSocketMessages.clear();

    final previousMaxSeq = _maxKnownSeq();
    final existingIDs = state.map((message) => message.id).toSet();
    final fastIncoming = <api.Message>[];
    final fallback = <api.Message>[];

    for (final message in messages) {
      if (_pendingSendGuard.isCancelled(message.msgId)) {
        if (message.senderId == _currentUserId) {
          unawaited(_chatService.revokeMessage(chatId, message.msgId));
        }
        continue;
      }
      if (message.senderId != _currentUserId &&
          !existingIDs.contains(message.msgId)) {
        fastIncoming.add(message);
        existingIDs.add(message.msgId);
      } else {
        fallback.add(message);
      }
    }

    // Self echoes and updates keep the existing reconciliation path. A group
    // burst normally has at most one such row for this device.
    for (final message in fallback) {
      handleRealtimeMessage(message, source: 'ws_batch_fallback');
    }

    if (fastIncoming.isNotEmpty && mounted) {
      fastIncoming.sort((a, b) {
        if (a.seq > 0 && b.seq > 0 && a.seq != b.seq) {
          return a.seq.compareTo(b.seq);
        }
        return a.createdAt.compareTo(b.createdAt);
      });
      final items = fastIncoming
          .map((message) => MessageItem.fromApiMessage(
                message,
                _currentUserId,
              ))
          .toList(growable: false);
      state = boundActiveRealtimeMessageWindow(<MessageItem>[
        ...items,
        ...state,
      ]);
      _rememberCurrentWindow();
      _schedulePrivateMediaRefresh();
      unawaited(_saveMessagesToLocal(items));

      if (_isActive) {
        final maxSeq = fastIncoming.fold<int>(
          0,
          (current, message) => message.seq > current ? message.seq : current,
        );
        _markAsReadUpToSeq(maxSeq);
      }
      for (final message in fastIncoming) {
        if (message.type == 99) {
          _checkAndRefreshWalletBubbles(message);
        }
      }
    }

    final seqs = messages
        .map((message) => message.seq)
        .where((seq) => seq > previousMaxSeq)
        .toSet()
        .toList()
      ..sort();
    if (previousMaxSeq > 0 && seqs.isNotEmpty && !_isSyncing) {
      var expected = previousMaxSeq + 1;
      var hasGap = false;
      for (final seq in seqs) {
        if (seq != expected) {
          hasGap = true;
          break;
        }
        expected = seq + 1;
      }
      if (hasGap) {
        debugPrint(
          '[Message] Realtime batch seq gap: '
          'local=$previousMaxSeq first=${seqs.first} last=${seqs.last}',
        );
        unawaited(_deltaSyncAfterReconnect());
      }
    }
  }

  @override
  void dispose() {
    _webSocketMessageBatchTimer?.cancel();
    _webSocketMessageBatchTimer = null;
    _pendingWebSocketMessages.clear();
    _privateMediaRefreshDebounce?.cancel();
    _privateMediaRefreshTimer?.cancel();
    _readReceiptTimer?.cancel();
    _readReceiptTimer = null;
    if (_pendingReadReceiptSeq > 0) {
      unawaited(_flushReadReceipt());
    }
    unawaited(_persistenceBatcher.close());
    _pendingSendGuard.dispose();
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
    _wsService.removeSpecificHandler(
      WSMessageType.delivered,
      _deliveryReceiptHandler,
    );
    _wsService.removeSpecificHandler(
      WSMessageType.messageDelivered,
      _deliveryReceiptHandler,
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
    _wsService.removeSpecificHandler('user_profile', _userProfileHandler);
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

    final seconds = _startBurnCountdown(message, unlockContent: true);
    // Automatic read receipts stop before unopened burn messages. The explicit
    // recipient click is the point at which this message becomes readable.
    _markAsReadUpToSeq(message.seq);
    return seconds;
  }

  int _startBurnCountdown(MessageItem message, {required bool unlockContent}) {
    final messageId = message.id;
    final seconds = (message.burnCountdownSeconds != null &&
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
      final shouldLockIncoming = msg.burnAfterRead &&
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
      final shouldResumeCountdown = msg.burnAfterRead &&
          (msg.burnCountdownSeconds != null && msg.burnCountdownSeconds! > 0);
      if (shouldResumeCountdown) {
        _startBurnCountdown(msg, unlockContent: false);
        continue;
      }

      final shouldStartOutgoingCountdown = msg.burnAfterRead &&
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
    MessageMemoryWindowCache.remove(accountId: _currentUserId, chatId: chatId);
    _lastSeq = null;
    _hasMore = true;
    _cachedDeletedIds = null;
    await _clearBurnStateMap();

    if (PlatformUtils.isWeb) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_webMessageWindowStorageKey);
      } catch (e) {
        debugPrint('[Message] Clear web history failed: $e');
      }
      return;
    }

    if (!IsarService.instance.isAvailable) {
      return;
    }

    _rememberCurrentWindow();
    try {
      await IsarService.instance.isar.writeTxn(() async {
        await IsarService.instance.isar.messageModels
            .filter()
            .accountIdEqualTo(_currentUserId)
            .chatIdEqualTo(chatId)
            .deleteAll();
      });
    } catch (e) {
      debugPrint('[Message] Clear local history failed: $e');
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
    debugPrint(
      '[Message] Updated $updatedCount messages to read status (up to seq=$seq)',
    );

    // Persist read status locally
    final readMsgs =
        state.where((m) => m.isOutgoing && m.seq > 0 && m.seq <= seq).toList();
    if (readMsgs.isNotEmpty) {
      _saveMessagesToLocal(readMsgs);
    }

    for (final msg in readMsgs) {
      final shouldStartBurnCountdown = msg.burnAfterRead &&
          (msg.burnCountdownSeconds == null || msg.burnCountdownSeconds! <= 0);
      if (!shouldStartBurnCountdown) {
        continue;
      }
      _startBurnCountdown(msg, unlockContent: false);
    }
  }

  void _markMessagesAsDelivered(int seq) {
    if (!mounted || seq <= 0) return;

    bool hasChanges = false;
    for (final msg in state) {
      if (msg.seq > 0 &&
          msg.seq <= seq &&
          msg.isOutgoing &&
          msg.status == MessageStatus.sent) {
        hasChanges = true;
        break;
      }
    }

    if (!hasChanges) return;

    int updatedCount = 0;
    state = state.map((msg) {
      if (msg.seq > 0 &&
          msg.seq <= seq &&
          msg.isOutgoing &&
          msg.status == MessageStatus.sent) {
        updatedCount++;
        return msg.copyWith(status: MessageStatus.delivered);
      }
      return msg;
    }).toList();
    debugPrint(
      '[Message] Updated $updatedCount messages to delivered status (up to seq=$seq)',
    );

    final deliveredMsgs = state
        .where(
          (m) =>
              m.isOutgoing &&
              m.seq > 0 &&
              m.seq <= seq &&
              m.status == MessageStatus.delivered,
        )
        .toList();
    if (deliveredMsgs.isNotEmpty) {
      unawaited(_saveMessagesToLocal(deliveredMsgs));
    }
  }

  void _lockIncomingBurnMessagesUpToSeq(
    int seq, {
    required int readableSeq,
  }) {
    if (!mounted || seq <= 0) return;

    var changed = false;
    final changedIds = <String>{};
    state = state.map((msg) {
      if (msg.isOutgoing || msg.seq <= 0 || msg.seq > seq) {
        return msg;
      }

      final shouldMarkRead = msg.seq <= readableSeq &&
          (msg.status != MessageStatus.read || !msg.isRead);
      final shouldLockBurn = msg.burnAfterRead &&
          !msg.burnLocked &&
          (msg.burnCountdownSeconds == null || msg.burnCountdownSeconds! <= 0);

      if (!shouldMarkRead && !shouldLockBurn) {
        return msg;
      }

      changed = true;
      changedIds.add(msg.id);
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

    final updatedMessages =
        state.where((msg) => changedIds.contains(msg.id)).toList();
    if (updatedMessages.isEmpty) {
      return;
    }

    unawaited(_saveMessagesToLocal(updatedMessages));
    final burnMessages =
        updatedMessages.where((msg) => msg.burnAfterRead).toList();
    if (burnMessages.isNotEmpty) {
      unawaited(_persistBurnStates(burnMessages));
    }
  }

  void _markAsReadUpToSeq(int seq) {
    if (seq <= 0) return;
    final readableSeq = _latestReadableSeqBeforeLockedBurn(state, seq);
    _lockIncomingBurnMessagesUpToSeq(seq, readableSeq: readableSeq);
    if (readableSeq <= 0) return;
    if (readableSeq > _pendingReadReceiptSeq) {
      _pendingReadReceiptSeq = readableSeq;
    }
    _readReceiptTimer?.cancel();
    _readReceiptTimer = Timer(
      const Duration(milliseconds: 400),
      () {
        _readReceiptTimer = null;
        unawaited(_flushReadReceipt());
      },
    );
  }

  Future<void> _flushReadReceipt() async {
    final seq = _pendingReadReceiptSeq;
    if (seq <= 0) return;
    _pendingReadReceiptSeq = 0;
    try {
      await _chatService.markAsRead(chatId, msgSeq: seq);
    } catch (error) {
      debugPrint('[Message] Flush read receipt failed: $error');
    }
  }

  void _boundRealtimeWindow() {
    if (state.length <= kActiveRealtimeMessageWindowLimit) return;
    final before = state.length;
    state = boundActiveRealtimeMessageWindow(state);
    _rememberCurrentWindow();
    debugPrint(
      '[Message] Bounded active realtime window: $before -> ${state.length}',
    );
  }

  void _syncBurnedIncomingMessagesUpToSeq(int seq) {
    if (seq <= 0) return;

    final affectedIds = state
        .where(
          (msg) =>
              msg.burnAfterRead &&
              !msg.isOutgoing &&
              msg.seq > 0 &&
              msg.seq <= seq &&
              (msg.burnCountdownSeconds == null ||
                  msg.burnCountdownSeconds! <= 0),
        )
        .map((msg) => msg.id)
        .toSet();
    if (affectedIds.isEmpty) return;

    state = _applyBurnedReceipt(state, seq);
    _rememberCurrentWindow();

    final updatedMessages =
        state.where((msg) => affectedIds.contains(msg.id)).toList();
    if (updatedMessages.isNotEmpty) {
      unawaited(_saveMessagesToLocal(updatedMessages));
      unawaited(_persistBurnStates(updatedMessages));
    }
  }

  void _addNewMessage(api.Message message) {
    if (!mounted) return;

    final existingIndex = state.indexWhere((msg) => msg.id == message.msgId);
    if (existingIndex >= 0) {
      final existing = state[existingIndex];
      final item = MessageItem.fromApiMessage(message, _currentUserId);
      final shouldUpdateExisting = existing.seq <= 0 ||
          existing.status == MessageStatus.sending ||
          existing.status == MessageStatus.failed;

      if (shouldUpdateExisting) {
        final displayItem = _applyServerSnapshot(existing, item).copyWith(
          mediaGroupId: item.mediaGroupId ?? existing.mediaGroupId,
        );
        state = state.map((msg) {
          if (msg.id == message.msgId) {
            return displayItem;
          }
          return msg;
        }).toList()
          ..sort(_compareMessagesNewestFirst);
        _saveMessagesToLocal([displayItem]);
        if (_isActive) {
          _markAsReadUpToSeq(message.seq);
        }
        debugPrint(
          '[Message] Updated existing message from WS echo: ${message.msgId}',
        );
        return;
      }

      debugPrint('[Message] Skip duplicate message: ${message.msgId}');
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
          final item = MessageItem.fromApiMessage(
            message,
            _currentUserId,
          ).copyWith(
            mediaGroupId: message.content.media?.mediaGroupId ??
                state[mergeIdx].mediaGroupId,
          );
          state = [item, ...state.where((m) => m.id != localId)];
          if (_isActive) {
            _markAsReadUpToSeq(message.seq);
          }
          _persistMessageUpdate(localId, item);
          debugPrint(
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
              debugPrint(
                '[Message] Merged WS wallet message into local row: ${message.msgId}',
              );
              return;
            }
          }
        }
        if (incomingItemType != MessageItemType.text) {
          final incomingMediaUrl = _normalizedRealtimeMediaUrl(
            MessageItem.fromApiMessage(message, _currentUserId),
          );
          final mergeIdx = state.indexWhere(
            (msg) =>
                msg.senderId == _currentUserId &&
                (msg.status == MessageStatus.sending ||
                    msg.status == MessageStatus.failed) &&
                msg.type == incomingItemType &&
                _canMergeRealtimeMediaEcho(
                  local: msg,
                  incomingMediaUrl: incomingMediaUrl,
                ) &&
                now.difference(msg.createdAt).inSeconds < 15 &&
                message.createdAt.difference(msg.createdAt).abs().inSeconds <=
                    echoAlignSecs,
          );
          if (mergeIdx >= 0) {
            final localId = state[mergeIdx].id;
            final incoming = MessageItem.fromApiMessage(
              message,
              _currentUserId,
            );
            final item = _applyServerSnapshot(
              state[mergeIdx],
              incoming,
            ).copyWith(
              mediaGroupId: message.content.media?.mediaGroupId ??
                  state[mergeIdx].mediaGroupId,
            );
            state = [item, ...state.where((m) => m.id != localId)];
            if (_isActive) {
              _markAsReadUpToSeq(message.seq);
            }
            _persistMessageUpdate(localId, item);
            debugPrint(
              '[Message] Merged WS non-text into optimistic row: ${message.msgId}',
            );
            return;
          }
        }
      }
    }

    final item = MessageItem.fromApiMessage(message, _currentUserId);
    state = [item, ...state];
    _rememberCurrentWindow();

    // Send read receipts only when the current chat page is active.
    if (_isActive) {
      _markAsReadUpToSeq(message.seq);
    }
  }

  String _normalizedRealtimeMediaUrl(MessageItem item) {
    final value =
        (item.mediaUrl ?? item.thumbnail ?? item.localPath ?? '').trim();
    if (value.isEmpty) return '';
    return ApiConfig.getMediaUrl(value);
  }

  bool _canMergeRealtimeMediaEcho({
    required MessageItem local,
    required String incomingMediaUrl,
  }) {
    if (incomingMediaUrl.isEmpty) {
      return false;
    }

    final localMediaUrl = _normalizedRealtimeMediaUrl(local);
    if (localMediaUrl.isEmpty || localMediaUrl.startsWith('data:image/')) {
      return false;
    }
    return localMediaUrl == incomingMediaUrl;
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
      final systemType = text.startsWith('{')
          ? () {
              try {
                final json = jsonDecode(text);
                return json['type']?.toString();
              } catch (_) {
                return null;
              }
            }()
          : null;
      if (systemType == 'red_packet_claimed' ||
          systemType == 'transfer_accepted' ||
          _isWalletStatusChangeText(displayText)) {
        debugPrint(
          '[Message] Wallet status change detected, refreshing bubbles',
        );
        WalletBubbleRefreshNotifier.instance.refresh();
      }
    } catch (e) {
      debugPrint('[Message] _checkAndRefreshWalletBubbles error: $e');
    }
  }

  void _markMessageAsRevokedBy(String msgId, String? revokerId) {
    if (!mounted) return;
    state = state.map((msg) {
      if (msg.id == msgId) {
        return msg.copyWith(
          isDeleted: true,
          content: _messageProviderText(
            zhCN: '此消息已撤回',
            zhTW: '此訊息已撤回',
            en: 'This message was revoked',
          ),
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
    // 重新可见时不能假设 WS 覆盖了后台期间事件，主动按 seq 做一次可靠同步。
    if (wasInactive) {
      Future.microtask(() => ensureReliableSync(reason: 'active'));
    }
  }

  Future<void> initialize() async {
    _isActive = true;
    if (_isInitializing) return;
    _isInitializing = true;
    try {
      await loadMessages();
      unawaited(_recoverPendingDirectUploads(reason: 'initialize'));
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> ensureReliableSync({String reason = 'manual'}) async {
    // 顺序固定为恢复未完成上传、发送离线队列、再拉服务端增量，避免补洞覆盖待发送状态。
    if (!mounted) return;
    debugPrint('[Message] Reliable sync start: chatId=$chatId reason=$reason');

    await _recoverPendingDirectUploads(reason: reason);
    if (!mounted) return;
    await OfflineMessageQueue().processPending();
    if (!mounted) return;

    if (state.isEmpty || _maxKnownSeq() == 0) {
      await loadMessages();
      return;
    }

    await _deltaSyncAfterReconnect();
    if (!mounted) return;

    await _reconcileRecentMessages();
    if (!mounted) return;

    await _backfillInitialHistoryWindow();
  }

  Future<void> _reconcileRecentMessages() async {
    if (!mounted || _isReconcilingRecent) return;
    _isReconcilingRecent = true;

    try {
      final deletedFuture = _getDeletedMessageIds();
      final response = await _chatService.getMessages(chatId, limit: 30);
      if (!mounted) return;

      final deletedIds = await deletedFuture;
      if (!response.isSuccess || response.data == null) return;

      final snapshots = response.data!
          .map<MessageItem>(
            (message) => _applyPersistedBurnState(
              MessageItem.fromApiMessage(message, _currentUserId),
            ),
          )
          .where((message) => !deletedIds.contains(message.id))
          .toList();
      if (snapshots.isEmpty || !mounted) return;

      final beforeById = <String, MessageItem>{
        for (final message in state) message.id: message,
      };
      final reconciled = _reconcileReliableMessageWindow(state, snapshots);
      var changed = 0;
      for (final snapshot in snapshots) {
        final before = beforeById[snapshot.id];
        if (before == null ||
            before.content != snapshot.content ||
            before.isEdited != snapshot.isEdited ||
            before.editedAt != snapshot.editedAt ||
            before.isDeleted != snapshot.isDeleted ||
            before.reactions.length != snapshot.reactions.length) {
          changed++;
        }
      }

      state = reconciled;
      _reconcileBurnStateFromCurrentMessages();
      _rememberCurrentWindow();
      unawaited(_saveMessagesToLocal(snapshots));
      debugPrint(
        '[Message] Recent reconciliation: chatId=$chatId '
        'snapshots=${snapshots.length} changed=$changed',
      );
    } catch (e) {
      debugPrint('[Message] Recent reconciliation failed: $e');
    } finally {
      _isReconcilingRecent = false;
    }
  }

  Future<void> _deltaSyncAfterReconnect() async {
    if (!mounted || _isSyncing) return;
    _isSyncing = true;

    try {
      int maxSeq = _maxKnownSeq();

      // If seq is still missing, fall back to a full message reload.
      if (maxSeq == 0) {
        debugPrint('[Message] Delta sync: no seq yet, fallback to full load');
        await loadMessages();
        return;
      }

      debugPrint('[Message] Delta sync: chatId=$chatId, lastSeq=$maxSeq');

      const pageSize = 100;
      const maxRounds = 5;
      final deletedIds = await _getDeletedMessageIds();
      var totalMerged = 0;

      for (var round = 0; round < maxRounds; round++) {
        final response = await _chatService.syncMessages(
          chatId,
          lastSeq: maxSeq,
          limit: pageSize,
        );
        if (!mounted) return;

        if (!response.isSuccess ||
            response.data == null ||
            response.data!.isEmpty) {
          break;
        }

        final newMessages = response.data!
            .map<MessageItem>(
              (msg) => MessageItem.fromApiMessage(msg, _currentUserId),
            )
            .where((msg) => !deletedIds.contains(msg.id))
            .toList();

        final mergedCount = _mergeSyncedMessages(newMessages);
        totalMerged += mergedCount;

        final batchMaxSeq = response.data!.fold<int>(
          maxSeq,
          (max, msg) => msg.seq > max ? msg.seq : max,
        );
        if (batchMaxSeq <= maxSeq) break;
        maxSeq = batchMaxSeq;

        if (response.data!.length < pageSize) break;
      }

      if (totalMerged > 0) {
        debugPrint('[Message] Delta sync: merged $totalMerged messages');
      }
      await _backfillInitialHistoryWindow();
    } catch (e) {
      debugPrint('[Message] Delta sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  int _maxKnownSeq() {
    var maxSeq = 0;
    for (final msg in state) {
      if (msg.seq > maxSeq) maxSeq = msg.seq;
    }
    return maxSeq;
  }

  int _mergeSyncedMessages(List<MessageItem> messages) {
    if (messages.isEmpty || !mounted) return 0;

    final beforeIds = state.map((m) => m.id).toSet();
    final uniqueMessages = messages.where((msg) {
      if (beforeIds.contains(msg.id)) return false;
      if (msg.seq > 0 &&
          state.any(
            (item) => item.chatId == msg.chatId && item.seq == msg.seq,
          )) {
        return false;
      }
      return true;
    }).toList();

    if (uniqueMessages.isEmpty) return 0;

    state = _mergeReliableSyncedWindow(state, uniqueMessages);
    _reconcileBurnStateFromCurrentMessages();
    _rememberCurrentWindow();
    unawaited(_saveMessagesToLocal(uniqueMessages));

    if (_isActive) {
      final latestSeq =
          uniqueMessages.map((m) => m.seq).reduce((a, b) => a > b ? a : b);
      if (latestSeq > 0) {
        _markAsReadUpToSeq(latestSeq);
      }
    }

    return uniqueMessages.length;
  }

  Future<void> _loadFromLocal() async {
    if (_currentUserId.isEmpty) return;
    if (PlatformUtils.isWeb) {
      await _loadFromWebCache();
      return;
    }

    try {
      await _getBurnStateMap();
      final deletedIds = await _getDeletedMessageIds();
      final list = await IsarService.instance.isar.messageModels
          .filter()
          .accountIdEqualTo(_currentUserId)
          .chatIdEqualTo(chatId)
          .sortByCreatedAtDesc()
          .limit(50)
          .findAll();
      if (list.isEmpty || !mounted) return;

      final seen = <String>{};
      final deduped = <MessageModel>[];
      for (final m in list) {
        if (deletedIds.contains(m.id)) {
          continue;
        }
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
        _rememberCurrentWindow();
      }
    } catch (e) {
      debugPrint('[Message] Failed to load from local: $e');
    }
  }

  String get _webMessageWindowStorageKey =>
      'message_window_${_currentUserId}_$chatId';

  Future<void> _loadFromWebCache() async {
    try {
      await _getBurnStateMap();
      final deletedIds = await _getDeletedMessageIds();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_webMessageWindowStorageKey);
      if (raw == null || raw.isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! List) return;

      final parsedItems = decoded
          .map(_messageItemFromCacheJson)
          .whereType<MessageItem>()
          .where((msg) => msg.chatId == chatId)
          .where((msg) => !deletedIds.contains(msg.id))
          .map((msg) {
        var item = _applyPersistedBurnState(msg);
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
      }).toList()
        ..sort(_compareMessagesNewestFirst);

      final items = _dedupeWalletMessages(parsedItems.take(50).toList());
      if (items.isEmpty || !mounted) return;

      state = _mergeLoadedMessages(items);
      _reconcileBurnStateFromCurrentMessages();
      _rememberCurrentWindow();
    } catch (e) {
      debugPrint('[Message] Failed to load from web cache: $e');
    }
  }

  Future<void> _writeMessagesToWebCache(List<MessageItem> messages) async {
    if (_currentUserId.isEmpty) return;
    try {
      final normalized = _dedupeWalletMessages([...messages]);
      final limited = normalized.take(100).toList();
      final prefs = await SharedPreferences.getInstance();
      if (limited.isEmpty) {
        await prefs.remove(_webMessageWindowStorageKey);
        return;
      }
      await prefs.setString(
        _webMessageWindowStorageKey,
        jsonEncode(limited.map(_messageItemToCacheJson).toList()),
      );
    } catch (e) {
      debugPrint('[Message] Failed to write web cache: $e');
    }
  }

  Future<void> _saveMessagesToWebCache(List<MessageItem> messages) async {
    if (messages.isEmpty || _currentUserId.isEmpty) return;
    try {
      final deletedIds = await _getDeletedMessageIds();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_webMessageWindowStorageKey);
      final existing = <MessageItem>[];
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          existing.addAll(
            decoded.map(_messageItemFromCacheJson).whereType<MessageItem>(),
          );
        }
      }

      final byId = <String, MessageItem>{
        for (final msg in existing.where(
          (msg) => msg.chatId == chatId && !deletedIds.contains(msg.id),
        ))
          msg.id: msg,
      };
      for (final msg in messages.where(
        (msg) => msg.chatId == chatId && !deletedIds.contains(msg.id),
      )) {
        byId[msg.id] = msg;
      }

      await _writeMessagesToWebCache(byId.values.toList());
    } catch (e) {
      debugPrint('[Message] Failed to save web cache: $e');
    }
  }

  List<MessageItem> _dedupeWalletMessages(List<MessageItem> messages) =>
      _dedupeReliableMessageWindow(messages);

  List<MessageItem> _mergeLoadedMessages(List<MessageItem> loadedMessages) {
    if (state.isEmpty) return _dedupeWalletMessages(loadedMessages);

    final loadedIds = loadedMessages.map((m) => m.id).toSet();
    final loadedWalletKeys =
        loadedMessages.map(_walletMessageKey).whereType<String>().toSet();
    DateTime? newestLoadedTime;
    for (final msg in loadedMessages) {
      if (newestLoadedTime == null || msg.createdAt.isAfter(newestLoadedTime)) {
        newestLoadedTime = msg.createdAt;
      }
    }

    final transientMessages = state.where((msg) {
      if (loadedIds.contains(msg.id)) return false;
      final walletKey = _walletMessageKey(msg);
      if (walletKey != null && loadedWalletKeys.contains(walletKey)) {
        return false;
      }
      if (msg.status == MessageStatus.sending ||
          msg.status == MessageStatus.failed) {
        return true;
      }
      if (newestLoadedTime != null && msg.createdAt.isAfter(newestLoadedTime)) {
        return true;
      }
      return false;
    }).toList();

    return _dedupeWalletMessages([...transientMessages, ...loadedMessages]);
  }

  /// Load messages from the server while showing cached local messages first.
  Future<void> loadMessages() async {
    if (!mounted) return;
    final loadSpan = PerformanceTraceService.start('message.loadMessages');

    try {
      final memoryHit = _hydrateFromMemoryCache();
      final localFuture = memoryHit ? Future<void>.value() : _loadFromLocal();
      if (memoryHit) {
        unawaited(_loadFromLocal());
      }
      await localFuture;

      final hasLocalWindow = state.isNotEmpty;
      if (hasLocalWindow) {
        _lastSeq = state.last.seq;
      }
      final localMaxSeq = hasLocalWindow
          ? state.map((m) => m.seq).reduce((a, b) => a > b ? a : b)
          : 0;

      if (hasLocalWindow) {
        await _mergeServerMessages(
          deletedIdsFuture: _getDeletedMessageIds(),
          responseFuture: _chatService.getMessages(chatId, limit: 30),
          localMaxSeq: localMaxSeq,
        );
        if (!mounted) return;
        await _deltaSyncAfterReconnect();
        await _backfillInitialHistoryWindow();
      } else {
        await _mergeServerMessages(
          deletedIdsFuture: _getDeletedMessageIds(),
          responseFuture: _chatService.getMessages(chatId, limit: 30),
          localMaxSeq: localMaxSeq,
        );
      }
    } catch (e) {
      debugPrint('[Message] loadMessages error: $e');
    } finally {
      final shouldNotifyLoadedEmpty = !_hasLoadedInitial && state.isEmpty;
      _hasLoadedInitial = true;
      if (shouldNotifyLoadedEmpty && mounted) {
        state = <MessageItem>[];
      }
      loadSpan.finish('chat=$chatId count=${state.length}');
    }
  }

  Future<void> _mergeServerMessages({
    required Future<Set<String>> deletedIdsFuture,
    required Future<dynamic> responseFuture,
    required int localMaxSeq,
  }) async {
    try {
      final results = await Future.wait([deletedIdsFuture, responseFuture]);
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

        if (localMaxSeq == 0 || messages.isNotEmpty) {
          state = _mergeLoadedMessages(messages);
          _reconcileBurnStateFromCurrentMessages();
          _rememberCurrentWindow();
        }
        if (localMaxSeq == 0) {
          _hasMore = messages.length >= 30;
        }
        _lastSeq = state.isNotEmpty ? state.last.seq : _lastSeq;

        Future.delayed(const Duration(milliseconds: 200), () {
          if (!mounted) return;
          _saveMessagesToLocal(messages);
        });

        _prefetchMediaThumbnails(messages.take(5).toList());

        if (_isActive && messages.isNotEmpty) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (!mounted) return;
            final maxSeq = messages.first.seq;
            _markAsReadUpToSeq(maxSeq);
          });
        }
      }
    } catch (e) {
      debugPrint('[Message] merge server messages error: $e');
    }
  }

  Future<void> _backfillInitialHistoryWindow() async {
    if (!mounted || !_shouldBackfillInitialHistoryWindow(state)) return;

    final beforeSeq = _oldestPositiveSeq(state);
    if (beforeSeq <= 1) return;

    try {
      final deletedFuture = _getDeletedMessageIds();
      final response = await _chatService.getMessages(
        chatId,
        beforeSeq: beforeSeq,
        limit: 30,
      );

      if (!mounted) return;

      final deletedIds = await deletedFuture;
      if (!response.isSuccess || response.data == null) {
        return;
      }

      final messages = response.data!
          .map<MessageItem>(
            (msg) => _applyPersistedBurnState(
              MessageItem.fromApiMessage(msg, _currentUserId),
            ),
          )
          .where((msg) => !deletedIds.contains(msg.id))
          .toList()
        ..sort(_compareMessagesNewestFirst);

      if (messages.isEmpty) {
        _hasMore = false;
        return;
      }

      final beforeCount = state.length;
      state = _dedupeWalletMessages([...state, ...messages]);
      _reconcileBurnStateFromCurrentMessages();
      _rememberCurrentWindow();
      _hasMore = messages.length >= 30;
      _lastSeq = _oldestPositiveSeq(state);

      unawaited(_saveMessagesToLocal(messages));

      final mergedCount = state.length - beforeCount;
      if (mergedCount > 0) {
        debugPrint(
          '[Message] Initial history backfill merged $mergedCount messages '
          'before seq $beforeSeq',
        );
      }
    } catch (e) {
      debugPrint('[Message] initial history backfill failed: $e');
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

      imageUrl = ChatMediaCacheManager.normalizeUrl(imageUrl);
      if (!imageUrl.startsWith('http')) continue;

      try {
        ChatMediaCacheManager.prefetchImage(imageUrl);
        prefetchCount++;
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        debugPrint('[Message] Failed to prefetch image: $e');
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

        messages.sort(_compareMessagesNewestFirst);

        final existingIds = state.map((m) => m.id).toSet();
        final existingWalletKeys =
            state.map(_walletMessageKey).whereType<String>().toSet();
        final uniqueMessages = messages.where((msg) {
          if (existingIds.contains(msg.id)) return false;
          final walletKey = _walletMessageKey(msg);
          if (walletKey != null && existingWalletKeys.contains(walletKey)) {
            return false;
          }
          return true;
        }).toList();

        if (uniqueMessages.isNotEmpty) {
          state = _dedupeWalletMessages([...state, ...uniqueMessages]);
          _reconcileBurnStateFromCurrentMessages();
          _rememberCurrentWindow();
        }
        _hasMore = messages.length >= 30;
        _lastSeq = messages.isNotEmpty ? messages.last.seq : _lastSeq;

        _saveMessagesToLocal(uniqueMessages);
      } else {
        _hasMore = false;
      }
    } catch (e) {
      debugPrint('[Message] loadMoreMessages failed: $e');
      _hasMore = false;
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> _saveMessagesToLocal(List<MessageItem> messages) async {
    _rememberCurrentWindow();
    _persistenceBatcher.addAll(messages);
  }

  Future<void> _persistMessagesNow(List<MessageItem> messages) async {
    try {
      final deletedIds = await _getDeletedMessageIds();
      final visibleMessages = messages
          .where((message) => !deletedIds.contains(message.id))
          .toList();
      if (visibleMessages.isEmpty) return;

      if (PlatformUtils.isWeb) {
        await _saveMessagesToWebCache(visibleMessages);
        return;
      }
      await persistMessageItemsToIsarCache(
        visibleMessages,
        accountId: _currentUserId,
      );
    } catch (error) {
      debugPrint('[Message] Batched local persistence failed: $error');
    }
  }

  Future<bool> ensureMessageLoaded(
    String messageId, {
    int? targetSeq,
    int maxBatches = 20,
  }) async {
    if (state.any((message) => message.id == messageId)) {
      return true;
    }

    // 页面初始化与搜索跳转可能同时发生。先等初始化落盘，避免 loadMore 因
    // 正在加载而直接返回，随后被误判为“没有更多消息”。
    for (var i = 0; i < 100 && _isInitializing; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return false;
    }

    if (targetSeq != null && targetSeq > 0) {
      try {
        final deletedFuture = _getDeletedMessageIds();
        final response = await _chatService.getMessages(
          chatId,
          beforeSeq: targetSeq + 1,
          limit: 30,
        );
        if (!mounted) return false;
        final deletedIds = await deletedFuture;
        if (response.isSuccess && response.data != null) {
          final targetWindow = response.data!
              .map<MessageItem>(
                (message) => _applyPersistedBurnState(
                  MessageItem.fromApiMessage(message, _currentUserId),
                ),
              )
              .where((message) => !deletedIds.contains(message.id))
              .toList();
          final merged = <MessageItem>[...state, ...targetWindow]
            ..sort(_compareMessagesNewestFirst);
          state = _dedupeWalletMessages(merged);
          _reconcileBurnStateFromCurrentMessages();
          _rememberCurrentWindow();
          unawaited(_saveMessagesToLocal(targetWindow));
          if (state.any((message) => message.id == messageId)) {
            return true;
          }
        }
      } catch (e) {
        debugPrint('[Message] target window load failed: $e');
      }
    }

    for (var i = 0; i < maxBatches; i++) {
      final beforeCount = state.length;
      await loadMoreMessages();

      if (state.any((message) => message.id == messageId)) {
        return true;
      }

      if (state.length == beforeCount) {
        break;
      }
    }

    return state.any((message) => message.id == messageId);
  }

  /// Send a text message.
  /// Returns null on success or when the message is queued offline.
  Future<String?> sendTextMessage(
    String text, {
    ReplyInfo? replyTo,
    List<String>? mentions,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
    bool anonymous = false,
  }) async {
    if (text.runes.length > maxTextMessageLength) {
      return _messageProviderText(
        zhCN: '消息内容不能超过5000个字符',
        zhTW: '訊息內容不能超過5000個字元',
        en: 'Messages cannot exceed 5000 characters.',
      );
    }
    // If offline, queue the message locally first.
    final offlineQueue = OfflineMessageQueue();
    if (anonymous && !offlineQueue.isOnline) {
      return _messageProviderText(
        zhCN: '匿名消息需要联网发送，请连接网络后重试',
        zhTW: '匿名訊息需要連線發送，請連接網路後重試',
        en: 'Anonymous messages require a network connection. Please reconnect and try again.',
      );
    }
    if (!offlineQueue.isOnline) {
      final localId = _uuid.v4();
      final message = MessageItem(
        id: localId,
        chatId: chatId,
        senderId: _currentUserId,
        senderName: _messageProviderSelfName(),
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
          accountId: _currentUserId,
          id: localId,
          chatId: chatId,
          type: OfflineMessageType.text,
          content: text,
          createdAt: DateTime.now(),
        ),
      );
      debugPrint('[Message] Offline, queued text message: $localId');
      return null;
    }

    final localId = _uuid.v4();
    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: _messageProviderSelfName(),
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

    // Keep server sequence allocation aligned with the user's submission
    // order. Optimistic messages are still inserted immediately above.
    return _textSendQueue.enqueue(() async {
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
          anonymous: anonymous,
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
          debugPrint(
            '[Message] sendMessage failed: code=${response.code} message=${response.message} dataNull=${response.data == null}',
          );
          // Server-side rejections are final business errors. Do not put them
          // into the offline queue, otherwise muted/blocked/expired-login sends
          // look like they are silently stuck and get retried pointlessly.
          if (response.code > 0) {
            _updateMessageStatus(localId, MessageStatus.failed);
            return _messageServerMessage(
              response.message,
              fallbackEn: 'Send failed, please try again later',
            );
          }
          _updateMessageStatus(localId, MessageStatus.failed);
          // Queue the message offline again after a normal send failure.
          await offlineQueue.enqueue(
            OfflineMessage(
              accountId: _currentUserId,
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
        debugPrint('[Message] sendMessage exception: $e');
        debugPrintStack(stackTrace: st, maxFrames: 6);
        _updateMessageStatus(localId, MessageStatus.failed);
        // Also queue the message offline when an exception happens.
        await offlineQueue.enqueue(
          OfflineMessage(
            accountId: _currentUserId,
            id: localId,
            chatId: chatId,
            type: OfflineMessageType.text,
            content: text,
            createdAt: DateTime.now(),
          ),
        );
        return null;
      }
    });
  }

  /// Send an image message.
  ///
  /// [localPath] Local image path.
  /// [width] Image width.
  /// [height] Image height.
  /// [skipCompress] Whether to skip compression. Defaults to false.
  Future<bool> sendImageMessage(
    String localPath, {
    int? width,
    int? height,
    bool skipCompress = false,
    String? caption,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
    bool anonymous = false,
    List<String>? mentions,
    String? mediaGroupId,
  }) async {
    // On web, read the local file bytes directly and send them.
    if (PlatformUtils.isWeb) {
      final xfile = XFile(localPath);
      final bytes = await xfile.readAsBytes();
      if (bytes.isNotEmpty) {
        return sendImageFromBytes(
          bytes,
          caption: caption,
          burnAfterRead: burnAfterRead,
          burnAfterSeconds: burnAfterSeconds,
          anonymous: anonymous,
          mentions: mentions,
          mediaGroupId: mediaGroupId,
        );
      }
      return false;
    }

    final localId = _uuid.v4();
    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: _messageProviderSelfName(),
      type: MessageItemType.image,
      content: caption ?? '',
      mediaUrl: localPath,
      localPath: localPath,
      mediaGroupId: mediaGroupId,
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
        return false;
      }

      var persistentLocalPath = uploadPath;
      try {
        persistentLocalPath = await ChatMediaCacheManager.persistOutgoingMedia(
          accountId: _currentUserId,
          sourcePath: uploadPath,
          messageId: localId,
          category: 'images',
        );
        MessageItem? persistedLocalMessage;
        state = state.map((item) {
          if (item.id != localId) return item;
          persistedLocalMessage = item.copyWith(
            mediaUrl: persistentLocalPath,
            localPath: persistentLocalPath,
          );
          return persistedLocalMessage!;
        }).toList();
        if (persistedLocalMessage != null) {
          await _saveMessagesToLocal([persistedLocalMessage!]);
        }
      } catch (error) {
        // Persistence is a local display/retry safety net. Upload can still
        // proceed from the picker/cache path if Application Support is full or
        // temporarily unavailable.
        debugPrint('[Image] Persist outgoing image failed: $error');
      }

      final fileSize = await file.length();
      final ext = uploadPath.split('.').last.toLowerCase();
      final mimeType = _getMimeType(ext);

      final uploadFileName =
          'image_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final directResult = await _s3DirectUpload.tryUpload(
        clientRequestId: localId,
        category: 'image',
        fileName: uploadFileName,
        mimeType: mimeType,
        filePath: uploadPath,
        onProgress: (sent, total) {
          if (total > 0) _updateUploadProgress(localId, sent / total);
        },
      );
      final ApiResponse<Map<String, dynamic>> uploadResponse;
      if (directResult != null) {
        uploadResponse = ApiResponse(
          code: 0,
          message: '',
          data: directResult,
        );
      } else {
        final formData = FormData.fromMap({
          'client_request_id': localId,
          'file': await MultipartFile.fromFile(
            uploadPath,
            filename: uploadFileName,
            contentType: DioMediaType.parse(mimeType),
          ),
        });
        uploadResponse = await _apiClient.upload<Map<String, dynamic>>(
          '/upload/image',
          formData,
          onSendProgress: (sent, total) {
            if (total > 0) _updateUploadProgress(localId, sent / total);
          },
        );
      }

      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        debugPrint('[Image] Upload failed: ${uploadResponse.message}');
        _updateMessageStatus(localId, MessageStatus.failed);
        return false;
      }

      final imageUrl = ApiConfig.normalizeMediaUrlForMessage(
        uploadResponse.data!['url'] as String?,
      );
      final imageMediaId = uploadResponse.data!['media_id']?.toString().trim();
      final thumbnailMediaId =
          uploadResponse.data!['thumbnail_media_id']?.toString().trim();
      final thumbnailUrl = ApiConfig.normalizeMediaUrlForMessage(
        uploadResponse.data!['thumbnail']?.toString(),
      );
      final uploadedWidth =
          (uploadResponse.data!['width'] as num?)?.toInt() ?? width;
      final uploadedHeight =
          (uploadResponse.data!['height'] as num?)?.toInt() ?? height;
      final uploadedSize =
          (uploadResponse.data!['size'] as num?)?.toInt() ?? fileSize;
      final uploadedMimeType =
          uploadResponse.data!['mime_type']?.toString().trim();

      final sendResponse = await _chatService.sendMessage(
        chatId: chatId,
        type: 2, // image type
        content: api.MessageContent(
          text: (caption != null && caption.isNotEmpty) ? caption : null,
          media: api.MediaInfo(
            mediaId: imageMediaId,
            url: imageUrl,
            thumbnailMediaId:
                (thumbnailMediaId?.isEmpty ?? true) ? null : thumbnailMediaId,
            thumbnail: thumbnailUrl.isEmpty ? null : thumbnailUrl,
            width: uploadedWidth,
            height: uploadedHeight,
            size: uploadedSize,
            mimeType: uploadedMimeType == null || uploadedMimeType.isEmpty
                ? mimeType
                : uploadedMimeType,
            mediaGroupId: mediaGroupId,
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
        anonymous: anonymous,
        mentions: mentions,
      );

      if (sendResponse.isSuccess && sendResponse.data != null) {
        final serverMsg = sendResponse.data!;
        MessageItem? updated;
        state = state.map((msg) {
          if (msg.id == localId) {
            updated = msg.copyWith(
              id: serverMsg.msgId,
              mediaId: imageMediaId,
              thumbnailMediaId:
                  (thumbnailMediaId?.isEmpty ?? true) ? null : thumbnailMediaId,
              mediaUrl: imageUrl,
              localPath: persistentLocalPath,
              thumbnail: thumbnailUrl.isEmpty ? null : thumbnailUrl,
              mediaGroupId: mediaGroupId,
              mediaWidth: uploadedWidth,
              mediaHeight: uploadedHeight,
              mediaSize: uploadedSize,
              content: caption ?? '',
              status: MessageStatus.sent,
              seq: serverMsg.seq,
            );
            return updated!;
          }
          return msg;
        }).toList();
        if (updated != null) _persistMessageUpdate(localId, updated!);
        return true;
      } else {
        _updateMessageStatus(localId, MessageStatus.failed);
        return false;
      }
    } catch (e) {
      debugPrint('[Image] Send error: $e');
      _updateMessageStatus(localId, MessageStatus.failed);
      return false;
    }
  }

  Future<bool> sendImageFromBytes(
    Uint8List bytes, {
    String ext = 'png',
    String? caption,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
    bool anonymous = false,
    List<String>? mentions,
    String? mediaGroupId,
  }) async {
    final localId = _uuid.v4();

    final base64Str = 'data:image/$ext;base64,${base64Encode(bytes)}';

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: _messageProviderSelfName(),
      type: MessageItemType.image,
      content: caption ?? '',
      mediaUrl: base64Str,
      mediaGroupId: mediaGroupId,
      isOutgoing: true,
      status: MessageStatus.sending,
      burnAfterRead: burnAfterRead,
      burnAfterSeconds: burnAfterSeconds,
      createdAt: DateTime.now(),
    );

    state = [message, ...state];

    try {
      final normalizedExt = ext.trim().toLowerCase().replaceFirst('.', '');
      final safeExt = normalizedExt.isEmpty ? 'png' : normalizedExt;
      final mimeType = _getMimeType(safeExt);
      final uploadFileName =
          'paste_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
      final directResult = await _s3DirectUpload.tryUpload(
        clientRequestId: localId,
        category: 'image',
        fileName: uploadFileName,
        mimeType: mimeType,
        bytes: bytes,
        onProgress: (sent, total) {
          if (total > 0) _updateUploadProgress(localId, sent / total);
        },
      );
      final ApiResponse<Map<String, dynamic>> uploadResponse;
      if (directResult != null) {
        uploadResponse = ApiResponse(
          code: 0,
          message: '',
          data: directResult,
        );
      } else {
        final formData = FormData.fromMap({
          'client_request_id': localId,
          'file': MultipartFile.fromBytes(
            bytes,
            filename: uploadFileName,
            contentType: DioMediaType.parse(mimeType),
          ),
        });
        uploadResponse = await _apiClient.upload<Map<String, dynamic>>(
          '/upload/image',
          formData,
          onSendProgress: (sent, total) {
            if (total > 0) _updateUploadProgress(localId, sent / total);
          },
        );
      }

      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        debugPrint('[Image] Paste upload failed: ${uploadResponse.message}');
        _updateMessageStatus(localId, MessageStatus.failed);
        return false;
      }

      final imageUrl = ApiConfig.normalizeMediaUrlForMessage(
        uploadResponse.data!['url'] as String?,
      );
      final imageMediaId = uploadResponse.data!['media_id']?.toString().trim();
      final thumbnailMediaId =
          uploadResponse.data!['thumbnail_media_id']?.toString().trim();
      final thumbnailUrl = ApiConfig.normalizeMediaUrlForMessage(
        uploadResponse.data!['thumbnail']?.toString(),
      );
      final uploadedWidth = (uploadResponse.data!['width'] as num?)?.toInt();
      final uploadedHeight = (uploadResponse.data!['height'] as num?)?.toInt();
      final uploadedSize =
          (uploadResponse.data!['size'] as num?)?.toInt() ?? bytes.length;
      final uploadedMimeType =
          uploadResponse.data!['mime_type']?.toString().trim();

      CachedNetworkImage.evictFromCache(ApiConfig.getMediaUrl(imageUrl));

      final sendResponse = await _chatService.sendMessage(
        chatId: chatId,
        type: 2,
        content: api.MessageContent(
          text: (caption != null && caption.isNotEmpty) ? caption : null,
          media: api.MediaInfo(
            mediaId: imageMediaId,
            url: imageUrl,
            thumbnailMediaId:
                (thumbnailMediaId?.isEmpty ?? true) ? null : thumbnailMediaId,
            thumbnail: thumbnailUrl.isEmpty ? null : thumbnailUrl,
            width: uploadedWidth,
            height: uploadedHeight,
            size: uploadedSize,
            mimeType: uploadedMimeType == null || uploadedMimeType.isEmpty
                ? mimeType
                : uploadedMimeType,
            mediaGroupId: mediaGroupId,
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
        anonymous: anonymous,
        mentions: mentions,
      );

      if (sendResponse.isSuccess && sendResponse.data != null) {
        final serverMsg = sendResponse.data!;
        MessageItem? updated;
        state = state.map((msg) {
          if (msg.id == localId) {
            updated = msg.copyWith(
              id: serverMsg.msgId,
              mediaId: imageMediaId,
              thumbnailMediaId:
                  (thumbnailMediaId?.isEmpty ?? true) ? null : thumbnailMediaId,
              mediaUrl: imageUrl,
              thumbnail: thumbnailUrl.isEmpty ? null : thumbnailUrl,
              mediaGroupId: mediaGroupId,
              mediaWidth: uploadedWidth,
              mediaHeight: uploadedHeight,
              mediaSize: uploadedSize,
              content: caption ?? '',
              status: MessageStatus.sent,
              seq: serverMsg.seq,
            );
            return updated!;
          }
          return msg;
        }).toList();
        if (updated != null) _persistMessageUpdate(localId, updated!);
        return true;
      } else {
        _updateMessageStatus(localId, MessageStatus.failed);
        return false;
      }
    } catch (e) {
      debugPrint('[Image] Paste send error: $e');
      _updateMessageStatus(localId, MessageStatus.failed);
      return false;
    }
  }

  /// Send an image message from a remote URL.
  Future<void> sendImageByUrl(
    String imageUrl, {
    String? caption,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
    bool anonymous = false,
    List<String>? mentions,
    String? mediaGroupId,
  }) async {
    final localId = _uuid.v4();
    final messageImageUrl = ApiConfig.normalizeMediaUrlForMessage(imageUrl);
    final ext = _extensionFromUrl(messageImageUrl);
    final mimeType = ext.isEmpty ? 'image/png' : _getMimeType(ext);

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: _messageProviderSelfName(),
      type: MessageItemType.image,
      content: caption ?? '',
      mediaUrl: messageImageUrl,
      mediaGroupId: mediaGroupId,
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
            url: messageImageUrl,
            width: null,
            height: null,
            size: 1,
            mimeType: mimeType,
            mediaGroupId: mediaGroupId,
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
        anonymous: anonymous,
        mentions: mentions,
      );

      if (sendResponse.isSuccess && sendResponse.data != null) {
        final serverMsg = sendResponse.data!;
        MessageItem? updated;
        state = state.map((msg) {
          if (msg.id == localId) {
            updated = msg.copyWith(
              id: serverMsg.msgId,
              mediaUrl: messageImageUrl,
              mediaGroupId: mediaGroupId,
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
      debugPrint('[Image] Send by url error: $e');
      _updateMessageStatus(localId, MessageStatus.failed);
    }
  }

  Future<void> sendStickerByUrl({
    required String packId,
    required String stickerId,
    required String stickerUrl,
    String? emoji,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
  }) async {
    final localId = _uuid.v4();
    final displayUrl = _messageProviderStickerMediaUrl(stickerUrl);

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: _messageProviderSelfName(),
      type: MessageItemType.sticker,
      content: emoji ?? '',
      mediaUrl: displayUrl,
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
        type: 8,
        content: api.MessageContent(
          sticker: api.StickerInfo(
            packId: packId,
            stickerId: stickerId,
            url: stickerUrl,
            emoji: emoji,
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
              mediaUrl: displayUrl,
              content: emoji ?? '',
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
      debugPrint('[Sticker] Send by url error: $e');
      _updateMessageStatus(localId, MessageStatus.failed);
    }
  }

  Future<void> sendVideoMessage(
    String localPath, {
    int? duration,
    String? thumbnail,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
    bool anonymous = false,
  }) async {
    final localId = _uuid.v4();

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: _messageProviderSelfName(),
      type: MessageItemType.video,
      content: '',
      mediaUrl: localPath,
      localPath: localPath,
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
        debugPrint('[Message] Failed to generate video thumbnail: $e');
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
      final mimeType = _getMimeType(ext);

      final uploadFileName =
          'video_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final directResult = await _s3DirectUpload.tryUpload(
        clientRequestId: localId,
        category: 'video',
        fileName: uploadFileName,
        mimeType: mimeType,
        filePath: localPath,
        retainSessionUntilAcknowledged: true,
        onProgress: (sent, total) {
          if (total > 0) _updateUploadProgress(localId, sent / total);
        },
      );
      final ApiResponse<Map<String, dynamic>> uploadResponse;
      if (directResult != null) {
        uploadResponse = ApiResponse(
          code: 0,
          message: '',
          data: directResult,
        );
      } else {
        final formData = FormData.fromMap({
          'client_request_id': localId,
          'file': await MultipartFile.fromFile(
            localPath,
            filename: uploadFileName,
            contentType: DioMediaType.parse(mimeType),
          ),
        });
        uploadResponse = await _apiClient.upload<Map<String, dynamic>>(
          '/upload/video',
          formData,
          onSendProgress: (sent, total) {
            if (total > 0) {
              _updateUploadProgress(localId, sent / total);
            }
          },
        );
      }

      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final videoUrl = ApiConfig.getMediaUrl(
        uploadResponse.data!['url'] as String?,
      );

      // Upload the thumbnail separately when available.
      String? thumbnailUrl =
          uploadResponse.data!['thumbnail']?.toString().trim();
      String? thumbnailMediaId =
          uploadResponse.data!['thumbnail_media_id']?.toString().trim();
      if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
        thumbnailUrl = ApiConfig.getMediaUrl(thumbnailUrl);
      } else {
        thumbnailUrl = null;
      }
      final hasServerThumbnail =
          (thumbnailMediaId?.isNotEmpty ?? false) || thumbnailUrl != null;
      if (!hasServerThumbnail && localThumbnail != null) {
        try {
          final thumbFile = File(localThumbnail);
          if (await thumbFile.exists()) {
            final thumbnailResult = await _uploadVideoThumbnail(
              messageId: localId,
              localPath: localThumbnail,
            );
            if (thumbnailResult != null) {
              thumbnailMediaId = thumbnailResult['media_id']?.toString();
              thumbnailUrl = ApiConfig.getMediaUrl(
                thumbnailResult['url'] as String?,
              );
            }
          }
        } catch (e) {
          debugPrint('[Message] Failed to upload video thumbnail: $e');
        }
      }

      final sendResponse = await _chatService.sendMessage(
        chatId: chatId,
        type: 3, // video type
        content: api.MessageContent(
          media: api.MediaInfo(
            mediaId: uploadResponse.data!['media_id']?.toString(),
            url: videoUrl,
            thumbnailMediaId: thumbnailMediaId,
            thumbnail: thumbnailUrl,
            duration: duration,
            size: fileSize,
            mimeType: 'video/$ext',
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
        anonymous: anonymous,
      );

      if (sendResponse.isSuccess && sendResponse.data != null) {
        await _s3DirectUpload.forgetPendingSession(localId);
        final serverMsg = sendResponse.data!;
        MessageItem? updated;
        state = state.map((msg) {
          if (msg.id == localId) {
            updated = msg.copyWith(
              id: serverMsg.msgId,
              mediaId: uploadResponse.data!['media_id']?.toString(),
              thumbnailMediaId: thumbnailMediaId,
              mediaUrl: videoUrl,
              localPath: localPath,
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

  Future<void> sendVideoFromBytes(
    Uint8List bytes,
    String fileName, {
    int? duration,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
    bool anonymous = false,
  }) async {
    final localId = _uuid.v4();
    final fileSize = bytes.length;
    final ext =
        fileName.contains('.') ? fileName.split('.').last.toLowerCase() : 'mp4';
    final mimeType = _getMimeType(ext);

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: _messageProviderSelfName(),
      type: MessageItemType.video,
      content: '',
      mediaSize: fileSize,
      mediaDuration: duration,
      isOutgoing: true,
      status: MessageStatus.sending,
      burnAfterRead: burnAfterRead,
      burnAfterSeconds: burnAfterSeconds,
      createdAt: DateTime.now(),
    );

    state = [message, ...state];
    Future.microtask(() => _saveMessagesToLocal([message]));

    try {
      final uploadFileName = fileName.isNotEmpty
          ? fileName
          : 'video_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final directResult = await _s3DirectUpload.tryUpload(
        clientRequestId: localId,
        category: 'video',
        fileName: uploadFileName,
        mimeType: mimeType,
        bytes: bytes,
        retainSessionUntilAcknowledged: true,
        onProgress: (sent, total) {
          if (total > 0) _updateUploadProgress(localId, sent / total);
        },
      );
      final ApiResponse<Map<String, dynamic>> uploadResponse;
      if (directResult != null) {
        uploadResponse = ApiResponse(code: 0, message: '', data: directResult);
      } else {
        final formData = FormData.fromMap({
          'client_request_id': localId,
          'file': MultipartFile.fromBytes(
            bytes,
            filename: uploadFileName,
            contentType: DioMediaType.parse(mimeType),
          ),
        });
        uploadResponse = await _apiClient.upload<Map<String, dynamic>>(
          '/upload/video',
          formData,
          onSendProgress: (sent, total) {
            if (total > 0) {
              _updateUploadProgress(localId, sent / total);
            }
          },
        );
      }

      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        debugPrint('[Video] Bytes upload failed: ${uploadResponse.message}');
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final videoUrl = ApiConfig.getMediaUrl(
        uploadResponse.data!['url'] as String?,
      );
      final thumbnailMediaId =
          uploadResponse.data!['thumbnail_media_id']?.toString();
      final thumbnailUrl = ApiConfig.getMediaUrl(
        uploadResponse.data!['thumbnail']?.toString(),
      );

      final sendResponse = await _chatService.sendMessage(
        chatId: chatId,
        type: 3,
        content: api.MessageContent(
          media: api.MediaInfo(
            mediaId: uploadResponse.data!['media_id']?.toString(),
            url: videoUrl,
            thumbnailMediaId: thumbnailMediaId,
            thumbnail: thumbnailUrl.isEmpty ? null : thumbnailUrl,
            duration: duration,
            size: fileSize,
            mimeType: mimeType,
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
        anonymous: anonymous,
      );

      if (sendResponse.isSuccess && sendResponse.data != null) {
        await _s3DirectUpload.forgetPendingSession(localId);
        final serverMsg = sendResponse.data!;
        MessageItem? updated;
        state = state.map((msg) {
          if (msg.id == localId) {
            updated = msg.copyWith(
              id: serverMsg.msgId,
              mediaId: uploadResponse.data!['media_id']?.toString(),
              thumbnailMediaId: thumbnailMediaId,
              mediaUrl: videoUrl,
              thumbnail: thumbnailUrl.isEmpty ? null : thumbnailUrl,
              mediaSize: fileSize,
              mediaDuration: duration,
              status: MessageStatus.sent,
              uploadProgress: 1,
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
      debugPrint('[Video] Bytes send error: $e');
      _updateMessageStatus(localId, MessageStatus.failed);
    }
  }

  Future<void> sendFileFromBytes(
    Uint8List bytes,
    String fileName, {
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
    bool anonymous = false,
  }) async {
    final localId = _uuid.v4();
    final fileSize = bytes.length;
    final ext =
        fileName.contains('.') ? fileName.split('.').last.toLowerCase() : '';

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: _messageProviderSelfName(),
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
      // 文件优先尝试 S3 直传；未配置或不可用时回退到 API 代理上传，
      // 两条路径共用 client_request_id，服务端可以幂等收敛重试结果。
      final mimeType = _getMimeType(ext);
      final directResult = await _s3DirectUpload.tryUpload(
        clientRequestId: localId,
        category: 'file',
        fileName: fileName,
        mimeType: mimeType,
        bytes: bytes,
        onProgress: (sent, total) {
          if (total > 0) _updateUploadProgress(localId, sent / total);
        },
      );
      final ApiResponse<Map<String, dynamic>> uploadResponse;
      if (directResult != null) {
        uploadResponse = ApiResponse(code: 0, message: '', data: directResult);
      } else {
        final formData = FormData.fromMap({
          'client_request_id': localId,
          'file': MultipartFile.fromBytes(bytes, filename: fileName),
        });
        uploadResponse = await _apiClient.upload<Map<String, dynamic>>(
          '/upload/file',
          formData,
        );
      }

      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        debugPrint('[File] Bytes upload failed: ${uploadResponse.message}');
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final fileUrl = ApiConfig.getMediaUrl(
        uploadResponse.data!['url'] as String?,
      );
      final fileMediaId = uploadResponse.data!['media_id']?.toString().trim();

      final sendResponse = await _chatService.sendMessage(
        chatId: chatId,
        type: 5,
        content: api.MessageContent(
          file: api.FileInfo(
            mediaId: fileMediaId,
            url: fileUrl,
            name: fileName,
            size: fileSize,
            mimeType: mimeType,
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
        anonymous: anonymous,
      );

      if (sendResponse.isSuccess && sendResponse.data != null) {
        final serverMsg = sendResponse.data!;
        MessageItem? updated;
        state = state.map((msg) {
          if (msg.id == localId) {
            updated = msg.copyWith(
              id: serverMsg.msgId,
              mediaId: (fileMediaId?.isEmpty ?? true) ? null : fileMediaId,
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
      debugPrint('[File] Bytes send error: $e');
      _updateMessageStatus(localId, MessageStatus.failed);
    }
  }

  Future<void> sendFileMessage(
    String localPath,
    String fileName, {
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
    bool anonymous = false,
  }) async {
    final localId = _uuid.v4();
    final file = File(localPath);
    final fileSize = await file.exists() ? await file.length() : 0;

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: _messageProviderSelfName(),
      type: MessageItemType.file,
      content: '',
      mediaUrl: localPath,
      localPath: localPath,
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

    final uploadCancelToken = _pendingSendGuard.registerUpload(localId);
    try {
      if (!await file.exists()) {
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final ext = fileName.split('.').last.toLowerCase();

      final mimeType = _getMimeType(ext);
      final directResult = await _s3DirectUpload.tryUpload(
        clientRequestId: localId,
        category: 'file',
        fileName: fileName,
        mimeType: mimeType,
        filePath: localPath,
        cancelToken: uploadCancelToken,
        onProgress: (sent, total) {
          if (total > 0) _updateUploadProgress(localId, sent / total);
        },
      );
      final ApiResponse<Map<String, dynamic>> uploadResponse;
      if (directResult != null) {
        uploadResponse = ApiResponse(code: 0, message: '', data: directResult);
      } else {
        final formData = FormData.fromMap({
          'client_request_id': localId,
          'file': await MultipartFile.fromFile(localPath, filename: fileName),
        });
        // Keep the P0 proxy path as a compatibility fallback.
        uploadResponse = await _apiClient.upload<Map<String, dynamic>>(
          '/upload/file',
          formData,
          cancelToken: uploadCancelToken,
        );
      }

      if (_pendingSendGuard.isCancelled(localId)) return;
      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        debugPrint('[File] Upload failed: ${uploadResponse.message}');
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final fileUrl = ApiConfig.getMediaUrl(
        uploadResponse.data!['url'] as String?,
      );
      final fileMediaId = uploadResponse.data!['media_id']?.toString().trim();

      final sendResponse = await _chatService.sendMessage(
        chatId: chatId,
        type: 5, // file type
        content: api.MessageContent(
          file: api.FileInfo(
            mediaId: fileMediaId,
            url: fileUrl,
            name: fileName,
            size: fileSize,
            mimeType: mimeType,
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
        anonymous: anonymous,
      );

      if (_pendingSendGuard.isCancelled(localId)) {
        if (sendResponse.isSuccess && sendResponse.data != null) {
          _pendingSendGuard.cancel(sendResponse.data!.msgId);
          await _chatService.revokeMessage(
            chatId,
            sendResponse.data!.msgId,
          );
        }
        return;
      }

      if (sendResponse.isSuccess && sendResponse.data != null) {
        final serverMsg = sendResponse.data!;
        MessageItem? updated;
        state = state.map((msg) {
          if (msg.id == localId) {
            updated = msg.copyWith(
              id: serverMsg.msgId,
              mediaId: (fileMediaId?.isEmpty ?? true) ? null : fileMediaId,
              mediaUrl: fileUrl,
              localPath: localPath,
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
      debugPrint('[File] Send error: $e');
      if (!_pendingSendGuard.isCancelled(localId)) {
        _updateMessageStatus(localId, MessageStatus.failed);
      }
    } finally {
      _pendingSendGuard.uploadFinished(localId);
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
      case 'heif':
        return 'image/heif';
      case 'avif':
        return 'image/avif';
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'avi':
        return 'video/x-msvideo';
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

  String _extensionFromUrl(String value) {
    final path = Uri.tryParse(value)?.path ?? value;
    final parts = path.split('/').where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    final name = parts.last;
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// Send a voice message.
  bool _shouldRetryVoiceUpload(ApiResponse<Map<String, dynamic>> response) {
    return response.code == -1 || response.code >= 500;
  }

  Future<ApiResponse<Map<String, dynamic>>> _uploadVoiceWithRetry(
    Future<FormData> Function() buildFormData, {
    required String logPrefix,
  }) async {
    ApiResponse<Map<String, dynamic>>? lastResponse;
    Object? lastError;

    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final response = await _apiClient.upload<Map<String, dynamic>>(
          '/upload/voice',
          await buildFormData(),
        );
        lastResponse = response;
        if (response.isSuccess || !_shouldRetryVoiceUpload(response)) {
          return response;
        }
        debugPrint(
          '[$logPrefix] Upload retry ${attempt + 1}/1: ${response.message}',
        );
      } catch (e) {
        lastError = e;
        debugPrint('[$logPrefix] Upload attempt ${attempt + 1} error: $e');
      }

      if (attempt == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }
    }

    return lastResponse ??
        ApiResponse<Map<String, dynamic>>(
          code: -1,
          message: lastError?.toString() ?? 'Voice upload failed',
        );
  }

  Future<void> sendVoiceMessage(
    String localPath,
    int durationMs, {
    String? transcript,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
    bool anonymous = false,
  }) async {
    final localId = _uuid.v4();

    // Insert the local optimistic message first.
    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: _messageProviderSelfName(),
      type: MessageItemType.voice,
      content: transcript ?? '',
      mediaUrl: localPath,
      localPath: localPath,
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
      final fileSize = await file.length();
      if (fileSize <= 0) {
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      // 语音发送分为“上传媒体”和“提交消息”两步：先取得服务端媒体 URL，
      // 再把 URL 写入消息正文；任一步失败都保留失败态，避免出现没有可播放地址的“已发送”消息。
      final uploadResponse = await _uploadVoiceWithRetry(
        () async => FormData.fromMap({
          'client_request_id': localId,
          'file': await MultipartFile.fromFile(
            localPath,
            filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
            contentType: DioMediaType.parse('audio/mp4'),
          ),
          'duration': durationMs.toString(),
        }),
        logPrefix: 'Voice',
      );

      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        debugPrint('[Voice] Upload failed: ${uploadResponse.message}');
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
            mediaId: uploadResponse.data!['media_id']?.toString(),
            url: voiceUrl,
            duration: durationMs,
            size: voiceSize,
            transcript: transcript,
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
        anonymous: anonymous,
      );

      if (sendResponse.isSuccess && sendResponse.data != null) {
        final serverMsg = sendResponse.data!;
        MessageItem? updated;
        state = state.map((msg) {
          if (msg.id == localId) {
            updated = msg.copyWith(
              id: serverMsg.msgId,
              mediaUrl: voiceUrl,
              localPath: localPath,
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
      debugPrint('[Voice] Send error: $e');
      _updateMessageStatus(localId, MessageStatus.failed);
    }
  }

  Future<void> sendVoiceFromBytes(
    Uint8List bytes,
    int durationMs, {
    String? fileName,
    String mimeType = 'audio/webm',
    String? transcript,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
    bool anonymous = false,
  }) async {
    final localId = _uuid.v4();
    final voiceFileName = fileName?.trim().isNotEmpty == true
        ? fileName!.trim()
        : 'voice_${DateTime.now().millisecondsSinceEpoch}.webm';
    final fileSize = bytes.length;

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: _messageProviderSelfName(),
      type: MessageItemType.voice,
      content: transcript ?? '',
      mediaDuration: durationMs,
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
      final uploadResponse = await _uploadVoiceWithRetry(
        () async => FormData.fromMap({
          'client_request_id': localId,
          'file': MultipartFile.fromBytes(
            bytes,
            filename: voiceFileName,
            contentType: DioMediaType.parse(mimeType),
          ),
          'duration': durationMs.toString(),
        }),
        logPrefix: 'Voice',
      );

      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        debugPrint('[Voice] Bytes upload failed: ${uploadResponse.message}');
        _updateMessageStatus(localId, MessageStatus.failed);
        return;
      }

      final voiceUrl = ApiConfig.getMediaUrl(
        uploadResponse.data!['url'] as String?,
      );
      final voiceSize = uploadResponse.data!['size'] as int? ?? fileSize;

      final sendResponse = await _chatService.sendMessage(
        chatId: chatId,
        type: 4,
        content: api.MessageContent(
          voice: api.VoiceInfo(
            mediaId: uploadResponse.data!['media_id']?.toString(),
            url: voiceUrl,
            duration: durationMs,
            size: voiceSize,
            transcript: transcript,
          ),
        ),
        msgId: localId,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
        anonymous: anonymous,
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
      debugPrint('[Voice] Bytes send error: $e');
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
            : _messageProviderLocationLabel());

    final message = MessageItem(
      id: localId,
      chatId: chatId,
      senderId: _currentUserId,
      senderName: _messageProviderSelfName(),
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
        debugPrint(
          '[Location] sendMessage failed: code=${sendResponse.code} message=${sendResponse.message} dataNull=${sendResponse.data == null}',
        );
        if (sendResponse.code > 0) {
          state = state.where((m) => m.id != localId).toList();
          return localizeServerMessage(
            sendResponse.message,
            fallbackZhCN: '发送位置失败，请稍后再试',
            fallbackZhTW: '發送位置失敗，請稍後再試',
            fallbackEn: 'Failed to send location, please try again later',
          );
        }
        _updateMessageStatus(localId, MessageStatus.failed);
        return _messageProviderText(
          zhCN: '发送位置失败，请检查网络后重试',
          zhTW: '發送位置失敗，請檢查網路後重試',
          en: 'Failed to send location. Check your network and try again',
        );
      }
    } catch (e) {
      debugPrint('[Location] Send error: $e');
      _updateMessageStatus(localId, MessageStatus.failed);
      return _messageProviderText(
        zhCN: '发送位置失败，请检查网络后重试',
        zhTW: '發送位置失敗，請檢查網路後重試',
        en: 'Failed to send location. Check your network and try again',
      );
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

  void markQueuedMessageSent(api.Message message) {
    if (message.chatId != chatId) return;
    _addNewMessage(message);
    _boundRealtimeWindow();
    final item = MessageItem.fromApiMessage(message, _currentUserId);
    unawaited(_saveMessagesToLocal([item]));
  }

  Future<void> _persistMessageUpdate(String oldId, MessageItem newMsg) async {
    if (PlatformUtils.isWeb) {
      state = state.where((msg) => msg.id != oldId).toList();
      state = _dedupeWalletMessages([newMsg, ...state]);
      _rememberCurrentWindow();
      await _writeMessagesToWebCache(state);
      return;
    }

    try {
      await IsarService.instance.isar.writeTxn(() async {
        // Remove the old local message record by id.
        await IsarService.instance.isar.messageModels
            .filter()
            .accountIdEqualTo(_currentUserId)
            .idEqualTo(oldId)
            .deleteAll();
      });
      // Write the updated message back to local storage.
      await _saveMessagesToLocal([newMsg]);
    } catch (e) {
      debugPrint('[Message] Persist message update failed: $e');
    }
  }

  Future<void> deleteMessage(String messageId) async {
    if (PlatformUtils.isWeb) {
      state = state.where((msg) => msg.id != messageId).toList();
      _rememberCurrentWindow();
      _cachedDeletedIds ??= <String>{};
      _cachedDeletedIds!.add(messageId);
      await _addToDeletedMessages(messageId);
      await _removeBurnState(messageId);
      await _writeMessagesToWebCache(state);
      return;
    }
    state = state.where((msg) => msg.id != messageId).toList();
    _rememberCurrentWindow();

    _cachedDeletedIds ??= <String>{};
    _cachedDeletedIds!.add(messageId);

    await _addToDeletedMessages(messageId);
    await _removeBurnState(messageId);

    // Remove the local message record from Isar as well.
    try {
      await IsarService.instance.isar.writeTxn(() async {
        await IsarService.instance.isar.messageModels
            .filter()
            .accountIdEqualTo(_currentUserId)
            .idEqualTo(messageId)
            .deleteAll();
      });
    } catch (e) {
      debugPrint('[MessageProvider] Delete local message failed: $e');
    }
  }

  Future<void> _addToDeletedMessages(String messageId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _deletedMessagesStorageKey;
      final deletedIds = prefs.getStringList(key) ?? [];
      if (!deletedIds.contains(messageId)) {
        deletedIds.add(messageId);
        await prefs.setStringList(key, deletedIds);
      }
    } catch (e) {
      debugPrint('[MessageProvider] Save deleted message IDs failed: $e');
    }
  }

  Future<void> _saveDeletedMessageIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _deletedMessagesStorageKey;
      final deletedIds = (_cachedDeletedIds ?? <String>{}).toList();
      await prefs.setStringList(key, deletedIds);
    } catch (e) {
      debugPrint('[MessageProvider] Save deleted message IDs failed: $e');
    }
  }

  String get _deletedMessagesStorageKey =>
      'deleted_messages_${_currentUserId}_$chatId';

  String get _burnStateStorageKey => 'burn_state_${_currentUserId}_$chatId';

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
      debugPrint('[MessageProvider] Load burn state failed: $e');
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
      burnCountdownSeconds:
          (snapshot['burn_countdown_seconds'] as num?)?.toInt(),
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
      debugPrint('[MessageProvider] Clear burn state failed: $e');
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
      debugPrint('[MessageProvider] Save burn state failed: $e');
    }
  }

  /// Get deleted message IDs with in-memory caching to avoid repeated disk reads.
  Future<Set<String>> _getDeletedMessageIds() async {
    if (_cachedDeletedIds != null) return _cachedDeletedIds!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _deletedMessagesStorageKey;
      final deletedIds = prefs.getStringList(key) ?? [];
      _cachedDeletedIds = deletedIds.toSet();
      return _cachedDeletedIds!;
    } catch (e) {
      debugPrint('[MessageProvider] Get deleted message IDs failed: $e');
      return {};
    }
  }

  /// Revoke a server message or cancel an optimistic message still sending.
  /// Returns null on success, otherwise a user-visible failure reason.
  Future<String?> revokeMessage(String messageId) async {
    final localMessage = state
        .where((message) => message.id == messageId)
        .cast<MessageItem?>()
        .firstOrNull;
    if (localMessage != null &&
        localMessage.isOutgoing &&
        localMessage.status == MessageStatus.sending) {
      _pendingSendGuard.cancel(messageId);
      await deleteMessage(messageId);
      return null;
    }

    final response = await _chatService.revokeMessage(chatId, messageId);

    if (response.isSuccess) {
      _markMessageAsRevoked(messageId);
      return null;
    }

    return _messageServerMessage(
      response.message,
      fallbackZhCN: '撤回失败，请稍后重试',
      fallbackZhTW: '撤回失敗，請稍後重試',
      fallbackEn: 'Failed to recall message. Please try again.',
    );
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

  Future<bool> editImageMessageFromPath(
    String messageId,
    String localPath, {
    int? width,
    int? height,
    bool skipCompress = false,
  }) async {
    try {
      String uploadPath = localPath;
      if (!skipCompress) {
        uploadPath = await ImageCompressUtil.compressImage(localPath);
      }

      final file = File(uploadPath);
      if (!await file.exists()) {
        return false;
      }

      final fileSize = await file.length();
      final ext = uploadPath.split('.').last.toLowerCase();
      final mimeType = _getMimeType(ext);
      final uploadRequestId =
          '$messageId:edit:${DateTime.now().millisecondsSinceEpoch}';
      final formData = FormData.fromMap({
        'client_request_id': uploadRequestId,
        'file': await MultipartFile.fromFile(
          uploadPath,
          filename: 'image_edit_${DateTime.now().millisecondsSinceEpoch}.$ext',
          contentType: DioMediaType.parse(mimeType),
        ),
      });

      final uploadResponse = await _apiClient.upload<Map<String, dynamic>>(
        '/upload/image',
        formData,
      );
      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        debugPrint('[ImageEdit] Upload failed: ${uploadResponse.message}');
        return false;
      }

      final imageUrl = ApiConfig.normalizeMediaUrlForMessage(
        uploadResponse.data!['url'] as String?,
      );
      final existingMediaGroupId = state
          .where((msg) => msg.id == messageId)
          .map((msg) => msg.mediaGroupId)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .firstOrNull;
      final media = api.MediaInfo(
        mediaId: uploadResponse.data!['media_id']?.toString(),
        url: imageUrl,
        width: width,
        height: height,
        size: fileSize,
        mimeType: mimeType,
        mediaGroupId: existingMediaGroupId,
      );
      return editImageMessageWithMedia(messageId, media);
    } catch (e, st) {
      debugPrint('[ImageEdit] editImageMessageFromPath failed: $e');
      debugPrintStack(stackTrace: st, maxFrames: 8);
      return false;
    }
  }

  Future<bool> editImageMessageFromBytes(
    String messageId,
    Uint8List bytes, {
    String ext = 'png',
    int? width,
    int? height,
  }) async {
    if (bytes.isEmpty) return false;
    try {
      final normalizedExt = ext.trim().toLowerCase().replaceFirst('.', '');
      final safeExt = normalizedExt.isEmpty ? 'png' : normalizedExt;
      final mimeType = _getMimeType(safeExt);
      final uploadRequestId =
          '$messageId:edit:${DateTime.now().millisecondsSinceEpoch}';
      final formData = FormData.fromMap({
        'client_request_id': uploadRequestId,
        'file': MultipartFile.fromBytes(
          bytes,
          filename:
              'image_edit_${DateTime.now().millisecondsSinceEpoch}.$safeExt',
          contentType: DioMediaType.parse(mimeType),
        ),
      });

      final uploadResponse = await _apiClient.upload<Map<String, dynamic>>(
        '/upload/image',
        formData,
      );
      if (!uploadResponse.isSuccess || uploadResponse.data == null) {
        debugPrint(
            '[ImageEdit] Bytes upload failed: ${uploadResponse.message}');
        return false;
      }

      final imageUrl = ApiConfig.normalizeMediaUrlForMessage(
        uploadResponse.data!['url'] as String?,
      );
      final existingMediaGroupId = state
          .where((msg) => msg.id == messageId)
          .map((msg) => msg.mediaGroupId)
          .where((id) => id != null && id.isNotEmpty)
          .cast<String>()
          .firstOrNull;
      final media = api.MediaInfo(
        mediaId: uploadResponse.data!['media_id']?.toString(),
        url: imageUrl,
        width: width,
        height: height,
        size: bytes.length,
        mimeType: mimeType,
        mediaGroupId: existingMediaGroupId,
      );
      return editImageMessageWithMedia(messageId, media);
    } catch (e, st) {
      debugPrint('[ImageEdit] editImageMessageFromBytes failed: $e');
      debugPrintStack(stackTrace: st, maxFrames: 8);
      return false;
    }
  }

  Future<bool> editImageMessageWithMedia(
    String messageId,
    api.MediaInfo media,
  ) async {
    final response = await _chatService.editImageMessage(
      chatId,
      messageId,
      media,
    );

    if (!response.isSuccess) {
      debugPrint('[ImageEdit] edit API failed: ${response.message}');
      return false;
    }

    state = state.map((msg) {
      if (msg.id == messageId) {
        return msg.copyWith(
          content: '',
          mediaUrl: media.url,
          thumbnail: media.thumbnail,
          mediaGroupId: media.mediaGroupId,
          mediaWidth: media.width,
          mediaHeight: media.height,
          mediaSize: media.size,
          mediaDuration: media.duration,
          isEdited: true,
          editedAt: DateTime.now(),
        );
      }
      return msg;
    }).toList();

    final updated = state.where((msg) => msg.id == messageId).toList();
    if (updated.isNotEmpty) {
      _saveMessagesToLocal([updated.first]);
    }
    return true;
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

    final existing = state.cast<MessageItem?>().firstWhere(
          (msg) => msg?.id == msgId,
          orElse: () => null,
        );
    if (existing != null && existing.type != MessageItemType.text) {
      unawaited(ensureReliableSync(reason: 'edited_message_fallback'));
      return;
    }

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
  Future<bool> forwardMessage(
    String messageId,
    String targetChatId, {
    String? clientMsgId,
    MessageItem? sourceMessage,
  }) async {
    final localMessage = sourceMessage ??
        state.cast<MessageItem?>().firstWhere(
              (item) => item?.id == messageId,
              orElse: () => null,
            );
    if (localMessage?.burnAfterRead == true) {
      return false;
    }

    final response = await _chatService.forwardMessage(
      sourceChatId: chatId,
      sourceMsgId: messageId,
      targetChatId: targetChatId,
      clientMsgId: clientMsgId ?? const Uuid().v4(),
    );

    return response.isSuccess;
  }

  Future<bool> forwardBundleMessages(
    List<String> messageIds,
    String targetChatId, {
    required String clientMsgId,
  }) async {
    final uniqueMessageIds = <String>[];
    final seen = <String>{};
    for (final rawId in messageIds) {
      final id = rawId.trim();
      if (id.isNotEmpty && seen.add(id)) uniqueMessageIds.add(id);
    }
    if (uniqueMessageIds.length < 2) return false;
    final response = await _chatService.forwardBundle(
      sourceChatId: chatId,
      sourceMsgIds: uniqueMessageIds,
      targetChatId: targetChatId,
      clientMsgId: clientMsgId,
    );
    return response.isSuccess;
  }

  Future<bool> _retryVoiceFromLocal(
    String messageId,
    MessageItem message,
  ) async {
    final localPath = message.localPath?.trim() ?? '';
    if (localPath.isEmpty) return false;

    final file = File(localPath);
    if (!await file.exists()) return false;
    final fileSize = await file.length();
    if (fileSize <= 0) return false;

    final ext = localPath.contains('.')
        ? localPath.split('.').last.toLowerCase()
        : 'm4a';
    final mimeType =
        ext == 'm4a' || ext == 'aac' ? 'audio/mp4' : _getMimeType(ext);
    final duration = message.mediaDuration ?? 0;
    final uploadResponse = await _uploadVoiceWithRetry(
      () async => FormData.fromMap({
        'client_request_id': messageId,
        'file': await MultipartFile.fromFile(
          localPath,
          filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.$ext',
          contentType: DioMediaType.parse(mimeType),
        ),
        'duration': duration.toString(),
      }),
      logPrefix: 'VoiceRetry',
    );
    if (!uploadResponse.isSuccess || uploadResponse.data == null) return false;

    final rawUrl = uploadResponse.data!['url']?.toString() ?? '';
    final messageUrl = ApiConfig.normalizeMediaUrlForMessage(rawUrl);
    if (messageUrl.isEmpty) return false;
    final uploadedSize =
        (uploadResponse.data!['size'] as num?)?.toInt() ?? fileSize;
    final response = await _chatService.sendMessage(
      chatId: chatId,
      type: 4,
      content: api.MessageContent(
        voice: api.VoiceInfo(
          mediaId: uploadResponse.data!['media_id']?.toString(),
          url: messageUrl,
          duration: duration,
          size: uploadedSize,
          transcript: message.content.isEmpty ? null : message.content,
        ),
      ),
      msgId: messageId,
      burnAfterRead: message.burnAfterRead,
      burnAfterSeconds: message.burnAfterSeconds,
    );
    if (!response.isSuccess || response.data == null) return false;

    MessageItem? updated;
    state = state.map((item) {
      if (item.id != messageId) return item;
      updated = item.copyWith(
        id: response.data!.msgId,
        mediaUrl: ApiConfig.getMediaUrl(messageUrl),
        localPath: localPath,
        mediaSize: uploadedSize,
        status: MessageStatus.sent,
        seq: response.data!.seq,
      );
      return updated!;
    }).toList();
    if (updated != null) {
      _persistMessageUpdate(messageId, updated!);
    }
    return updated != null;
  }

  Future<Map<String, dynamic>?> _uploadVideoThumbnail({
    required String messageId,
    required String localPath,
  }) async {
    final direct = await _s3DirectUpload.tryUpload(
      clientRequestId: '$messageId:thumbnail',
      category: 'image',
      fileName: 'thumb_$messageId.jpg',
      mimeType: 'image/jpeg',
      filePath: localPath,
    );
    if (direct != null) return direct;

    final response = await _apiClient.upload<Map<String, dynamic>>(
      '/upload/image',
      FormData.fromMap({
        'client_request_id': '$messageId:thumbnail',
        'file': await MultipartFile.fromFile(
          localPath,
          filename: 'thumb_$messageId.jpg',
          contentType: DioMediaType.parse('image/jpeg'),
        ),
      }),
    );
    return response.isSuccess ? response.data : null;
  }

  Future<void> _recoverPendingDirectUploads({
    required String reason,
  }) async {
    final sessions = await _s3DirectUpload.pendingSessions();
    if (!mounted || sessions.isEmpty) return;

    for (final session in sessions) {
      if (!mounted ||
          session.category != 'video' ||
          !session.canResumeFromFile) {
        continue;
      }
      final index = state.indexWhere(
        (message) =>
            message.id == session.clientRequestId &&
            message.type == MessageItemType.video &&
            (message.status == MessageStatus.sending ||
                message.status == MessageStatus.failed),
      );
      if (index < 0) continue;
      final path = session.filePath!;
      if (!await File(path).exists()) {
        _updateMessageStatus(session.clientRequestId, MessageStatus.failed);
        continue;
      }

      debugPrint(
        '[DirectUpload] Resume video message=${session.clientRequestId} '
        'upload=${session.uploadId} reason=$reason',
      );
      _updateMessageStatus(session.clientRequestId, MessageStatus.sending);
      final current = state.firstWhere(
        (message) => message.id == session.clientRequestId,
      );
      var succeeded = false;
      try {
        succeeded = await _retryVideoFromLocal(
          session.clientRequestId,
          current,
        );
      } catch (error, stackTrace) {
        debugPrint(
          '[DirectUpload] Resume failed message=${session.clientRequestId} '
          'upload=${session.uploadId} error=$error',
        );
        debugPrintStack(stackTrace: stackTrace, maxFrames: 12);
      }
      if (!succeeded && mounted) {
        _updateMessageStatus(session.clientRequestId, MessageStatus.failed);
      }
    }
  }

  Future<bool> _retryVideoFromLocal(
    String messageId,
    MessageItem message,
  ) async {
    final localPath = message.localPath?.trim() ?? '';
    if (localPath.isEmpty) return false;

    final file = File(localPath);
    if (!await file.exists()) return false;
    final fileSize = await file.length();
    if (fileSize <= 0) return false;

    final ext = localPath.contains('.')
        ? localPath.split('.').last.toLowerCase()
        : 'mp4';
    final mimeType = _getMimeType(ext);
    final directResult = await _s3DirectUpload.tryUpload(
      clientRequestId: messageId,
      category: 'video',
      fileName: 'video_$messageId.$ext',
      mimeType: mimeType,
      filePath: localPath,
      retainSessionUntilAcknowledged: true,
      onProgress: (sent, total) {
        if (total > 0) _updateUploadProgress(messageId, sent / total);
      },
    );
    final ApiResponse<Map<String, dynamic>> uploadResponse;
    if (directResult != null) {
      uploadResponse = ApiResponse(code: 0, message: '', data: directResult);
    } else {
      uploadResponse = await _apiClient.upload<Map<String, dynamic>>(
        '/upload/video',
        FormData.fromMap({
          'client_request_id': messageId,
          'file': await MultipartFile.fromFile(
            localPath,
            filename: 'video_$messageId.$ext',
            contentType: DioMediaType.parse(mimeType),
          ),
        }),
        onSendProgress: (sent, total) {
          if (total > 0) _updateUploadProgress(messageId, sent / total);
        },
      );
    }
    if (!uploadResponse.isSuccess || uploadResponse.data == null) return false;

    final rawUrl = uploadResponse.data!['url']?.toString() ?? '';
    final messageUrl = ApiConfig.normalizeMediaUrlForMessage(rawUrl);
    if (messageUrl.isEmpty) return false;

    String? thumbnailMessageUrl =
        uploadResponse.data!['thumbnail']?.toString().trim();
    String? thumbnailMediaId =
        uploadResponse.data!['thumbnail_media_id']?.toString().trim();
    if (thumbnailMessageUrl?.isEmpty ?? false) {
      thumbnailMessageUrl = null;
    }
    if (thumbnailMediaId?.isEmpty ?? false) {
      thumbnailMediaId = null;
    }
    final localThumbnail = message.thumbnail?.trim() ?? '';
    final hasServerThumbnail =
        thumbnailMediaId != null || thumbnailMessageUrl != null;
    if (!hasServerThumbnail && localThumbnail.isNotEmpty) {
      final thumbnailFile = File(localThumbnail);
      if (await thumbnailFile.exists()) {
        try {
          final thumbnailResult = await _uploadVideoThumbnail(
            messageId: messageId,
            localPath: localThumbnail,
          );
          if (thumbnailResult != null) {
            thumbnailMediaId = thumbnailResult['media_id']?.toString();
            thumbnailMessageUrl = ApiConfig.normalizeMediaUrlForMessage(
              thumbnailResult['url']?.toString(),
            );
          }
        } catch (e) {
          debugPrint('[VideoRetry] Thumbnail upload failed: $e');
        }
      } else {
        thumbnailMessageUrl = ApiConfig.normalizeMediaUrlForMessage(
          localThumbnail,
        );
      }
    }

    final response = await _chatService.sendMessage(
      chatId: chatId,
      type: 3,
      content: api.MessageContent(
        media: api.MediaInfo(
          mediaId: uploadResponse.data!['media_id']?.toString(),
          url: messageUrl,
          thumbnailMediaId: thumbnailMediaId,
          thumbnail: thumbnailMessageUrl,
          duration: message.mediaDuration,
          size: fileSize,
          mimeType: mimeType,
        ),
      ),
      msgId: messageId,
      burnAfterRead: message.burnAfterRead,
      burnAfterSeconds: message.burnAfterSeconds,
    );
    if (!response.isSuccess || response.data == null) return false;
    await _s3DirectUpload.forgetPendingSession(messageId);

    MessageItem? updated;
    state = state.map((item) {
      if (item.id != messageId) return item;
      updated = item.copyWith(
        id: response.data!.msgId,
        mediaId: uploadResponse.data!['media_id']?.toString(),
        thumbnailMediaId: thumbnailMediaId,
        mediaUrl: ApiConfig.getMediaUrl(messageUrl),
        localPath: localPath,
        thumbnail: thumbnailMessageUrl == null
            ? item.thumbnail
            : ApiConfig.getMediaUrl(thumbnailMessageUrl),
        mediaSize: fileSize,
        status: MessageStatus.sent,
        seq: response.data!.seq,
      );
      return updated!;
    }).toList();
    if (updated != null) {
      _persistMessageUpdate(messageId, updated!);
    }
    return updated != null;
  }

  String? _retryableRemoteMediaUrl(String? rawUrl) {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty) return null;
    final normalized = ApiConfig.normalizeMediaUrlForMessage(value);
    if (normalized.startsWith('/uploads/')) return normalized;
    final uri = Uri.tryParse(normalized);
    if (uri != null &&
        (uri.scheme.toLowerCase() == 'http' ||
            uri.scheme.toLowerCase() == 'https')) {
      return normalized;
    }
    return null;
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
                    mediaGroupId: message.mediaGroupId,
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
                mediaGroupId: message.mediaGroupId,
              );
              state = state.where((msg) => msg.id != messageId).toList();
            } else {
              // Reuse already-uploaded remote URLs directly when retrying.
              final messageUrl = ApiConfig.normalizeMediaUrlForMessage(url);
              final sendResponse = await _chatService.sendMessage(
                chatId: chatId,
                type: 2,
                content: api.MessageContent(
                  media: api.MediaInfo(
                    url: messageUrl,
                    width: message.mediaWidth,
                    height: message.mediaHeight,
                    size: message.mediaSize ?? 0,
                    mimeType: 'image/jpeg',
                    mediaGroupId: message.mediaGroupId,
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
          if (await _retryVideoFromLocal(messageId, message)) {
            break;
          }
          final videoUrl = _retryableRemoteMediaUrl(message.mediaUrl);
          if (videoUrl != null) {
            final sendResponse = await _chatService.sendMessage(
              chatId: chatId,
              type: 3,
              content: api.MessageContent(
                media: api.MediaInfo(
                  url: videoUrl,
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
          if (await _retryVoiceFromLocal(messageId, message)) {
            break;
          }
          final voiceUrl = _retryableRemoteMediaUrl(message.mediaUrl);
          if (voiceUrl != null) {
            final sendResponse = await _chatService.sendMessage(
              chatId: chatId,
              type: 4,
              content: api.MessageContent(
                voice: api.VoiceInfo(
                  url: voiceUrl,
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
      debugPrint('[Message] Resend error: $e');
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
      senderName: _messageProviderText(
        zhCN: '系统消息',
        zhTW: '系統訊息',
        en: 'System',
      ),
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
