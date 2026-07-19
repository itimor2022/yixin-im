import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../e2ee/e2ee_models.dart';
import '../e2ee/e2ee_service.dart';
import 'api_client.dart';
import 'system_settings_service.dart';
import 'websocket_service.dart';

DateTime? _parseOptionalServerDateTime(dynamic raw) {
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text)?.toLocal();
  if (parsed == null) return null;
  if (parsed.year <= 1) return null;
  return parsed;
}

/// 会话类型
enum ChatType {
  private, // 私聊
  group, // 群聊
  channel, // 频道
}

/// 会话模型
class Chat {
  final String id;
  final String uuid;
  final ChatType type;
  final String? name;
  final String? avatar;
  final String? description;
  final String? ownerId;
  final int memberCount;
  final int onlineCount;
  final int myRole; // 当前用户角色: 0=非成员, 1=普通成员, 2=管理员, 3=群主
  final bool pendingRequest; // 是否有待审批的加入申请
  final bool isPublic;
  final String? inviteLink;
  final String? username; // 群组用户名
  final String? targetUserId; // 私聊对方用户 UUID
  final String? emojiAvatar; // 表情状态（私聊对方）
  final String? nicknameColor; // 昵称颜色（私聊对方）
  final String? premiumType; // 会员类型（私聊对方）
  final bool isMember; // 是否会员（私聊对方）
  final String? badgeText; // 徽章文字
  final String? badgeColor; // 徽章颜色
  // 权限设置
  final bool canSendMessage;
  final bool canSendMedia;
  final bool canSendLinks;
  final bool canAddMembers;
  final bool canPinMessages;
  final bool memberProtection;
  final bool joinApproval; // 是否需要审批加入
  final DateTime createdAt;

  Chat({
    required this.id,
    required this.uuid,
    required this.type,
    this.name,
    this.avatar,
    this.description,
    this.ownerId,
    this.memberCount = 0,
    this.onlineCount = 0,
    this.myRole = 0,
    this.pendingRequest = false,
    this.isPublic = false,
    this.inviteLink,
    this.username,
    this.targetUserId,
    this.emojiAvatar,
    this.nicknameColor,
    this.premiumType,
    this.isMember = false,
    this.badgeText,
    this.badgeColor,
    this.canSendMessage = true,
    this.canSendMedia = true,
    this.canSendLinks = true,
    this.canAddMembers = false,
    this.canPinMessages = false,
    this.memberProtection = false,
    this.joinApproval = false,
    required this.createdAt,
  });

  /// 是否是管理员或群主
  bool get isAdmin => myRole >= 2;

  /// 是否是群主
  bool get isOwner => myRole == 3;

  factory Chat.fromJson(Map<String, dynamic> json) {
    String? avatarUrl = json['avatar'];
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
    }

    return Chat(
      id: json['id']?.toString() ?? '',
      uuid: json['uuid'] ?? '',
      type: () {
        final typeVal = (json['type'] ?? 1) - 1;
        return (typeVal >= 0 && typeVal < ChatType.values.length)
            ? ChatType.values[typeVal]
            : ChatType.private;
      }(),
      name: json['name'],
      avatar: avatarUrl,
      description: json['description'],
      ownerId: json['owner_id']?.toString(),
      memberCount: json['member_count'] ?? 0,
      onlineCount: json['online_count'] ?? 0,
      myRole: json['my_role'] ?? 0,
      pendingRequest: json['pending_request'] ?? false,
      isPublic: json['is_public'] ?? false,
      inviteLink: json['invite_link'],
      username: json['username'],
      targetUserId: json['target_user_id'],
      emojiAvatar: json['emoji_avatar'],
      nicknameColor: json['nickname_color'],
      premiumType: json['premium_type'],
      isMember: json['is_member'] ?? false,
      badgeText: json['badge_text'],
      badgeColor: json['badge_color'],
      canSendMessage: json['can_send_message'] ?? true,
      canSendMedia: json['can_send_media'] ?? true,
      canSendLinks: json['can_send_links'] ?? true,
      canAddMembers: json['can_add_members'] ?? false,
      canPinMessages: json['can_pin_messages'] ?? false,
      memberProtection: json['member_protection'] ?? false,
      joinApproval: json['join_approval'] ?? false,
      createdAt:
          _parseOptionalServerDateTime(json['created_at']) ?? DateTime.now(),
    );
  }
}

/// 群成员模型
class ChatMember {
  final String userId;
  final String username;
  final String nickname;
  final String? avatar;
  final int role; // 1:成员 2:管理员 3:群主
  final bool isOnline;
  final bool isMuted;
  final DateTime? muteEndTime;
  final String? nicknameColor; // 昵称颜色
  final String? emojiAvatar; // 动态表情
  final String? premiumType; // 会员类型
  final bool isMember; // 是否会员
  final String? badgeText;
  final String? badgeColor;

  ChatMember({
    required this.userId,
    required this.username,
    required this.nickname,
    this.avatar,
    this.role = 1,
    this.isOnline = false,
    this.isMuted = false,
    this.muteEndTime,
    this.nicknameColor,
    this.emojiAvatar,
    this.premiumType,
    this.isMember = false,
    this.badgeText,
    this.badgeColor,
  });

  /// 显示名称（优先 nickname）
  String get displayName => nickname.isNotEmpty ? nickname : username;

  /// 角色名称
  String get roleName {
    switch (role) {
      case 3:
        return '群主';
      case 2:
        return '管理员';
      default:
        return '成员';
    }
  }

  /// 禁言状态文本
  String get muteStatusText {
    if (!isMuted) return '';
    if (muteEndTime == null) return '永久禁言';
    final remaining = muteEndTime!.difference(DateTime.now());
    if (remaining.isNegative) return '';
    if (remaining.inDays > 0) return '禁言 ${remaining.inDays} 天';
    if (remaining.inHours > 0) return '禁言 ${remaining.inHours} 小时';
    return '禁言 ${remaining.inMinutes} 分钟';
  }

  factory ChatMember.fromJson(Map<String, dynamic> json) {
    String? avatarUrl = json['avatar'];
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
    }

    return ChatMember(
      userId: json['user_id'] ?? '',
      username: json['username'] ?? '',
      nickname: json['nickname'] ?? '',
      avatar: avatarUrl,
      role: json['role'] ?? 1,
      isOnline: json['is_online'] ?? false,
      isMuted: json['is_muted'] ?? false,
      muteEndTime: json['mute_end_time'] != null
          ? DateTime.parse(json['mute_end_time']).toLocal()
          : null,
      nicknameColor: json['nickname_color'],
      emojiAvatar: json['emoji_avatar'],
      premiumType: json['premium_type'],
      isMember: json['is_member'] ?? false,
      badgeText: json['badge_text'],
      badgeColor: json['badge_color'],
    );
  }
}

/// 用户会话模型（会话列表项）
class UserChat {
  final String id;
  final String chatId;
  final String? targetId;
  final String? targetUuid; // 用于官方用户判断
  final String? lastMsgText;
  final String? lastMsgSender; // 最后一条消息发送者名称（群聊预览用）
  final DateTime? lastMsgTime;
  final int? lastMsgType; // 最后一条消息类型
  final int lastMsgSeq; // 最后一条消息序号
  final int unreadCount;
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final bool? pendingRequest;
  final int? pendingRequestCount;

  // 关联的会话信息（直接从响应解析）
  final Chat? chat;

  // 直接字段（后端返回的 name/avatar/member_count）
  final String? name;
  final String? avatar;
  final int? type;
  final int memberCount;
  final String? emojiAvatar; // 表情状态
  final String? nicknameColor; // 昵称颜色
  final String? premiumType; // 会员类型
  final bool isMember;
  final String? badgeText;
  final String? badgeColor;

  UserChat({
    required this.id,
    required this.chatId,
    this.targetId,
    this.targetUuid,
    this.lastMsgText,
    this.lastMsgSender,
    this.lastMsgTime,
    this.lastMsgType,
    this.lastMsgSeq = 0,
    this.unreadCount = 0,
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
    this.pendingRequest,
    this.pendingRequestCount,
    this.chat,
    this.name,
    this.avatar,
    this.type,
    this.memberCount = 0,
    this.emojiAvatar,
    this.nicknameColor,
    this.premiumType,
    this.isMember = false,
    this.badgeText,
    this.badgeColor,
  });

  factory UserChat.fromJson(Map<String, dynamic> json) {
    String? avatarUrl = json['avatar'];
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
    }

    return UserChat(
      id: json['id']?.toString() ?? '',
      chatId: json['chat_id']?.toString() ?? '',
      targetId: json['target_id']?.toString(),
      targetUuid: json['target_uuid']?.toString(), // 用于官方用户判断
      lastMsgText: json['last_msg_text'],
      lastMsgSender: json['last_msg_sender'],
      lastMsgTime: _parseOptionalServerDateTime(json['last_msg_time']),
      lastMsgType: json['last_msg_type'],
      lastMsgSeq: json['last_msg_seq'] ?? 0,
      unreadCount: json['unread_count'] ?? 0,
      isPinned: json['is_pinned'] ?? false,
      isMuted: json['is_muted'] ?? false,
      isArchived: json['is_archived'] ?? false,
      pendingRequest: json['pending_request'],
      pendingRequestCount: json['pending_request_count'],
      // 直接解析 name, avatar, member_count
      name: json['name'],
      avatar: avatarUrl,
      type: json['type'],
      memberCount: json['member_count'] ?? 0,
      emojiAvatar: json['emoji_avatar'],
      nicknameColor: json['nickname_color'],
      premiumType: json['premium_type'],
      isMember: json['is_member'] ?? false,
      badgeText: json['badge_text'],
      badgeColor: json['badge_color'],
    );
  }
}

/// 消息模型
class Message {
  final String id;
  final String msgId;
  final String chatId;
  final int seq;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final String? senderNicknameColor; // 发送者昵称颜色
  final String? senderPremiumType; // 发送者会员类型
  final String? senderEmojiAvatar; // 发送者动态表情
  final int type;
  final MessageContent content;
  final ReplyInfo? replyTo;
  final List<String>? mentions;
  final List<ReactionInfo> reactions;
  final int status;
  final bool isRevoked;
  final String? revokedBy; // 撤回者 UUID
  final bool isEdited;
  final bool burnAfterRead;
  final int burnAfterSeconds;
  final DateTime createdAt;
  final DateTime? editedAt;

  Message({
    required this.id,
    required this.msgId,
    required this.chatId,
    required this.seq,
    required this.senderId,
    required this.senderName,
    this.senderAvatar,
    this.senderNicknameColor,
    this.senderPremiumType,
    this.senderEmojiAvatar,
    required this.type,
    required this.content,
    this.replyTo,
    this.mentions,
    this.reactions = const [],
    this.status = 1,
    this.isRevoked = false,
    this.revokedBy,
    this.isEdited = false,
    this.burnAfterRead = false,
    this.burnAfterSeconds = 0,
    required this.createdAt,
    this.editedAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    // 转换发送者头像 URL
    String? senderAvatarUrl = json['sender_avatar'];
    if (senderAvatarUrl != null && senderAvatarUrl.isNotEmpty) {
      senderAvatarUrl = ApiConfig.getMediaUrl(senderAvatarUrl);
    }

    return Message(
      id: json['id']?.toString() ?? '',
      msgId: json['msg_id'] ?? '',
      chatId: json['chat_id'] ?? '',
      seq: json['seq'] ?? 0,
      senderId: json['sender_id'] ?? '',
      senderName: json['sender_name'] ?? '',
      senderAvatar: senderAvatarUrl,
      senderNicknameColor: json['sender_nickname_color'],
      senderPremiumType: json['sender_premium_type'],
      senderEmojiAvatar: json['sender_emoji_avatar'],
      type: json['type'] ?? 1,
      content: MessageContent.fromJson(json['content'] ?? {}),
      replyTo: json['reply_to'] != null
          ? ReplyInfo.fromJson(json['reply_to'])
          : null,
      mentions: json['mentions'] != null
          ? List<String>.from(json['mentions'])
          : null,
      reactions: json['reactions'] != null
          ? (json['reactions'] as List)
                .map((r) => ReactionInfo.fromJson(r))
                .toList()
          : [],
      status: json['status'] ?? 1,
      isRevoked: json['is_revoked'] ?? false,
      revokedBy: json['revoked_by'],
      isEdited: json['is_edited'] ?? false,
      burnAfterRead: json['burn_after_read'] == true,
      burnAfterSeconds: json['burn_after_seconds'] ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at']).toLocal()
          : DateTime.now(),
      editedAt: json['edited_at'] != null
          ? DateTime.parse(json['edited_at']).toLocal()
          : null,
    );
  }
}

/// 消息表情回复信息
class ReactionInfo {
  final String emoji;
  final String userId;
  final String userName;
  final DateTime createdAt;

  ReactionInfo({
    required this.emoji,
    required this.userId,
    required this.userName,
    required this.createdAt,
  });

  factory ReactionInfo.fromJson(Map<String, dynamic> json) {
    return ReactionInfo(
      emoji: json['emoji'] ?? '',
      userId: json['user_id'] ?? '',
      userName: json['user_name'] ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at']).toLocal()
          : DateTime.now(),
    );
  }
}

/// 消息内容
class MessageContent {
  final String? text;
  final MediaInfo? media;
  final VoiceInfo? voice;
  final FileInfo? file;
  final LocationInfo? location;
  final ContactCardInfo? contact;

  MessageContent({
    this.text,
    this.media,
    this.voice,
    this.file,
    this.location,
    this.contact,
  });

  factory MessageContent.fromJson(Map<String, dynamic> json) {
    return MessageContent(
      text: json['text'],
      media: json['media'] != null ? MediaInfo.fromJson(json['media']) : null,
      voice: json['voice'] != null ? VoiceInfo.fromJson(json['voice']) : null,
      file: json['file'] != null ? FileInfo.fromJson(json['file']) : null,
      location: json['location'] != null
          ? LocationInfo.fromJson(json['location'])
          : null,
      contact: json['contact'] != null
          ? ContactCardInfo.fromJson(json['contact'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (text != null) 'text': text,
      if (media != null) 'media': media!.toJson(),
      if (voice != null) 'voice': voice!.toJson(),
      if (file != null) 'file': file!.toJson(),
      if (location != null) 'location': location!.toJson(),
      if (contact != null) 'contact': contact!.toJson(),
    };
  }
}

/// 名片信息
class ContactCardInfo {
  final String userId;
  final String nickname;
  final String? username;
  final String? avatar;
  final String? bio;
  final String? nicknameColor;
  final String? emojiAvatar;
  final String? premiumType;
  final bool isMember;
  final String? badgeText;
  final String? badgeColor;

  ContactCardInfo({
    required this.userId,
    required this.nickname,
    this.username,
    this.avatar,
    this.bio,
    this.nicknameColor,
    this.emojiAvatar,
    this.premiumType,
    this.isMember = false,
    this.badgeText,
    this.badgeColor,
  });

  factory ContactCardInfo.fromJson(Map<String, dynamic> json) {
    final avatar = ApiConfig.getMediaUrl(json['avatar']?.toString());
    return ContactCardInfo(
      userId: json['user_id'] ?? '',
      nickname: json['nickname'] ?? '',
      username: json['username'],
      avatar: avatar.isEmpty ? null : avatar,
      bio: json['bio'],
      nicknameColor: json['nickname_color'],
      emojiAvatar: json['emoji_avatar'],
      premiumType: json['premium_type'],
      isMember: json['is_member'] ?? false,
      badgeText: json['badge_text'],
      badgeColor: json['badge_color'],
    );
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'nickname': nickname,
    if (username != null) 'username': username,
    if (avatar != null) 'avatar': avatar,
    if (bio != null) 'bio': bio,
    if (nicknameColor != null) 'nickname_color': nicknameColor,
    if (emojiAvatar != null) 'emoji_avatar': emojiAvatar,
    if (premiumType != null) 'premium_type': premiumType,
  };
}

/// 媒体信息
class MediaInfo {
  final String url;
  final String? thumbnail;
  final int? width;
  final int? height;
  final int? duration;
  final int size;
  final String mimeType;

  MediaInfo({
    required this.url,
    this.thumbnail,
    this.width,
    this.height,
    this.duration,
    required this.size,
    required this.mimeType,
  });

  factory MediaInfo.fromJson(Map<String, dynamic> json) {
    return MediaInfo(
      url: json['url'] ?? '',
      thumbnail: json['thumbnail'],
      width: json['width'],
      height: json['height'],
      duration: json['duration'],
      size: json['size'] ?? 0,
      mimeType: json['mime_type'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    if (thumbnail != null) 'thumbnail': thumbnail,
    if (width != null) 'width': width,
    if (height != null) 'height': height,
    if (duration != null) 'duration': duration,
    'size': size,
    'mime_type': mimeType,
  };
}

/// 语音信息
class VoiceInfo {
  final String url;
  final int duration;
  final int size;
  final String? transcript;

  VoiceInfo({
    required this.url,
    required this.duration,
    required this.size,
    this.transcript,
  });

  factory VoiceInfo.fromJson(Map<String, dynamic> json) {
    return VoiceInfo(
      url: json['url'] ?? '',
      duration: json['duration'] ?? 0,
      size: json['size'] ?? 0,
      transcript: json['transcript'],
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'duration': duration,
    'size': size,
    if (transcript != null && transcript!.isNotEmpty) 'transcript': transcript,
  };
}

class LocationInfo {
  final double latitude;
  final double longitude;
  final String? title;
  final String? address;

  LocationInfo({
    required this.latitude,
    required this.longitude,
    this.title,
    this.address,
  });

  factory LocationInfo.fromJson(Map<String, dynamic> json) {
    double readDouble(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      return double.tryParse(value?.toString() ?? '') ?? 0;
    }

    return LocationInfo(
      latitude: readDouble('latitude'),
      longitude: readDouble('longitude'),
      title: json['title']?.toString(),
      address: json['address']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    if (title != null && title!.isNotEmpty) 'title': title,
    if (address != null && address!.isNotEmpty) 'address': address,
  };
}

/// 文件信息
class FileInfo {
  final String url;
  final String name;
  final int size;
  final String mimeType;

  FileInfo({
    required this.url,
    required this.name,
    required this.size,
    required this.mimeType,
  });

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      url: json['url'] ?? '',
      name: json['name'] ?? '',
      size: json['size'] ?? 0,
      mimeType: json['mime_type'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'name': name,
    'size': size,
    'mime_type': mimeType,
  };
}

/// 回复信息
class ReplyInfo {
  final String msgId;
  final String senderId;
  final String senderName;
  final String content;

  ReplyInfo({
    required this.msgId,
    required this.senderId,
    required this.senderName,
    required this.content,
  });

  factory ReplyInfo.fromJson(Map<String, dynamic> json) {
    return ReplyInfo(
      msgId: json['msg_id'] ?? '',
      senderId: json['sender_id'] ?? '',
      senderName: json['sender_name'] ?? '',
      content: json['content'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'msg_id': msgId,
    'sender_id': senderId,
    'sender_name': senderName,
    'content': content,
  };
}

/// 会话服务
class ChatService {
  static const int localRejectedCode = 460;

  final ApiClient _api;
  final WebSocketService _ws;
  final E2EEService _e2ee;
  final SystemSettingsService _systemSettings;

  ChatService(this._api, this._ws, this._e2ee, this._systemSettings);

  Future<Message> parseIncomingMessage(Map<String, dynamic> raw) async {
    final normalized = Map<String, dynamic>.from(raw);
    final e2eeRaw = normalized['e2ee'];
    if (e2eeRaw is! Map) {
      return Message.fromJson(normalized);
    }

    try {
      final decryptResult = await _e2ee.decryptPayload(
        E2EEPayload.fromJson(Map<String, dynamic>.from(e2eeRaw)),
      );
      if (decryptResult != null) {
        normalized['content'] = decryptResult.content;
        if (decryptResult.replyTo != null) {
          normalized['reply_to'] = decryptResult.replyTo;
        } else {
          normalized.remove('reply_to');
        }
        if (decryptResult.mentions != null) {
          normalized['mentions'] = decryptResult.mentions;
        } else {
          normalized.remove('mentions');
        }
        normalized.remove('e2ee');
        return Message.fromJson(normalized);
      }
    } catch (_) {}

    final originalType = (normalized['type'] as num?)?.toInt() ?? 1;
    normalized['type'] = 1;
    normalized['content'] = {'text': _encryptedPlaceholder(originalType)};
    normalized.remove('reply_to');
    normalized.remove('mentions');
    normalized.remove('e2ee');
    return Message.fromJson(normalized);
  }

  Future<List<Message>> _parseMessageList(List<dynamic> rawList) async {
    final result = <Message>[];
    for (final item in rawList) {
      if (item is! Map) continue;
      result.add(await parseIncomingMessage(Map<String, dynamic>.from(item)));
    }
    return result;
  }

  String _encryptedPlaceholder(int type) {
    switch (type) {
      case 2:
        return '[加密图片]';
      case 3:
        return '[加密视频]';
      case 4:
        return '[加密语音]';
      case 5:
        return '[加密文件]';
      case 6:
        return '[加密位置]';
      case 10:
        return '[加密名片]';
      default:
        return '[加密消息]';
    }
  }

  Future<MessageCryptoMode> _loadMessageCryptoMode({
    bool forceRefresh = false,
  }) async {
    final settings = await _systemSettings.getSettings(
      forceRefresh: forceRefresh,
    );
    return settings.messageCryptoMode;
  }

  void _attachPlainMessagePayload(
    Map<String, dynamic> payload,
    Map<String, dynamic> contentJson, {
    ReplyInfo? replyTo,
    List<String>? mentions,
  }) {
    payload['content'] = contentJson;
    if (replyTo != null) payload['reply_to'] = replyTo.toJson();
    if (mentions != null) payload['mentions'] = mentions;
  }

  ApiResponse<T> _cryptoModeError<T>(String message) {
    return ApiResponse(code: localRejectedCode, message: message);
  }

  String _normalizeCryptoExceptionMessage(Object error, String fallback) {
    final raw = error.toString().trim();
    if (raw.isEmpty) {
      return fallback;
    }
    const prefix = 'Exception:';
    if (raw.startsWith(prefix)) {
      final trimmed = raw.substring(prefix.length).trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return raw;
  }

  bool _shouldRetryAfterCryptoModeRefresh(
    String message, {
    required bool isEdit,
  }) {
    final normalized = message.trim();
    if (normalized.isEmpty) {
      return false;
    }
    if (normalized.contains('当前系统已关闭消息加密')) {
      return true;
    }
    return isEdit
        ? normalized.contains('严格加密模式下，编辑消息必须使用端到端加密')
        : normalized.contains('严格加密模式下，消息必须使用端到端加密发送');
  }

  String _strictCryptoFailureMessage(Object error, {required bool isEdit}) {
    final fallback = isEdit
        ? '严格加密模式下，当前会话暂时无法编辑加密消息'
        : '严格加密模式下，当前会话暂时无法发送加密消息';
    final message = _normalizeCryptoExceptionMessage(error, fallback);

    if (message.contains('没有可用的加密设备')) {
      return isEdit
          ? '严格加密模式下，对方当前还没有可用的加密设备，请让对方登录最新版客户端后再重试编辑。'
          : '严格加密模式下，对方当前还没有可用的加密设备，请让对方登录最新版客户端后，再重新进入会话发送。';
    }
    if (message.contains('未升级到加密版本')) {
      return isEdit
          ? '严格加密模式下，会话里仍有设备未升级到加密版本。请双方更新到最新版客户端，并重新登录后再重试编辑。'
          : '严格加密模式下，会话里仍有设备未升级到加密版本。请双方更新到最新版客户端，并重新登录后再发送。';
    }
    if (message.contains('注册设备密钥失败')) {
      return isEdit
          ? '严格加密模式下，本机加密密钥注册失败。请重新登录一次后，再重试编辑消息。'
          : '严格加密模式下，本机加密密钥注册失败。请重新登录一次后，再重试发送消息。';
    }
    if (message.contains('保存设备公钥失败') || message.contains('数据库未升级')) {
      return isEdit
          ? '严格加密模式下，服务端设备密钥存储尚未升级完成。请重启最新后端服务后，再重试编辑消息。'
          : '严格加密模式下，服务端设备密钥存储尚未升级完成。请重启最新后端服务后，再重新发送消息。';
    }
    if (message.contains('加密封装失败')) {
      return isEdit
          ? '严格加密模式下，本次编辑的加密封装失败。请稍后重试，或重新进入会话后再试。'
          : '严格加密模式下，本次消息加密封装失败。请稍后重试，或重新进入会话后再试。';
    }
    return message;
  }

  /// 获取会话列表（自动拉取全部页，避免只显示第一页）
  Future<ApiResponse<List<UserChat>>> getChatList({int pageSize = 100}) async {
    final allChats = <UserChat>[];
    int page = 1;

    while (true) {
      final response = await _api.get(
        '/chat/list',
        queryParameters: {'page': page, 'page_size': pageSize},
      );

      if (!response.isSuccess || response.data == null) {
        if (allChats.isEmpty) {
          return ApiResponse(
            code: response.code,
            message: response.message,
            data: null,
          );
        }
        break;
      }

      final list =
          (response.data['list'] as List?)
              ?.map((e) => UserChat.fromJson(e))
              .toList() ??
          [];

      allChats.addAll(list);

      if (list.length < pageSize) break;
      page++;
      if (page > 50) break;
    }

    return ApiResponse(code: 0, message: 'success', data: allChats);
  }

  /// 获取会话列表（单页，供特定场景使用）
  Future<ApiResponse<List<UserChat>>> getChatListPage({
    int page = 1,
    int pageSize = 100,
  }) async {
    final response = await _api.get(
      '/chat/list',
      queryParameters: {'page': page, 'page_size': pageSize},
    );

    if (response.isSuccess && response.data != null) {
      final list =
          (response.data['list'] as List?)
              ?.map((e) => UserChat.fromJson(e))
              .toList() ??
          [];
      return ApiResponse(
        code: response.code,
        message: response.message,
        data: list,
      );
    }

    return ApiResponse(
      code: response.code,
      message: response.message,
      data: [],
    );
  }

  /// 创建会话
  Future<ApiResponse<Chat>> createChat({
    required ChatType type,
    String? name,
    String? description,
    List<String>? memberIds,
    bool isPublic = false,
    String? avatar,
  }) async {
    return _api.post(
      '/chat/create',
      data: {
        'type': type.index + 1,
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (memberIds != null) 'member_ids': memberIds,
        'is_public': isPublic,
        if (avatar != null) 'avatar': avatar,
      },
      fromJson: (data) => Chat.fromJson(data),
    );
  }

  /// 获取会话详情
  Future<ApiResponse<Chat>> getChat(String chatId) async {
    return _api.get('/chat/$chatId', fromJson: (data) => Chat.fromJson(data));
  }

  /// 更新会话
  Future<ApiResponse<Chat>> updateChat(
    String chatId, {
    String? name,
    String? description,
    String? avatar,
    String? username,
    bool? isPublic,
    bool? joinApproval,
    bool? canSendMessage,
    bool? canSendMedia,
    bool? canSendLinks,
    bool? canAddMembers,
    bool? canPinMessages,
    bool? memberProtection,
  }) async {
    return _api.put(
      '/chat/$chatId',
      data: {
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (avatar != null) 'avatar': avatar,
        if (username != null) 'username': username,
        if (isPublic != null) 'is_public': isPublic,
        if (joinApproval != null) 'join_approval': joinApproval,
        if (canSendMessage != null) 'can_send_message': canSendMessage,
        if (canSendMedia != null) 'can_send_media': canSendMedia,
        if (canSendLinks != null) 'can_send_links': canSendLinks,
        if (canAddMembers != null) 'can_add_members': canAddMembers,
        if (canPinMessages != null) 'can_pin_messages': canPinMessages,
        if (memberProtection != null) 'member_protection': memberProtection,
      },
      fromJson: (data) => Chat.fromJson(data),
    );
  }

  /// 删除会话
  Future<ApiResponse> deleteChat(String chatId) async {
    return _api.delete('/chat/$chatId');
  }

  /// 获取群成员列表
  Future<ApiResponse<List<ChatMember>>> getMembers(String chatId) async {
    final response = await _api.get('/chat/$chatId/members');

    if (response.isSuccess && response.data != null) {
      // 兼容后端返回 List 或 { list: [...] } 两种结构
      List rawList;
      if (response.data is List) {
        rawList = response.data as List;
      } else if (response.data is Map) {
        rawList = (response.data as Map)['list'] as List? ?? [];
      } else {
        rawList = [];
      }
      final list = rawList.map((e) => ChatMember.fromJson(e)).toList();
      return ApiResponse(
        code: response.code,
        message: response.message,
        data: list,
      );
    }

    return ApiResponse(
      code: response.code,
      message: response.message,
      data: [],
    );
  }

  /// 添加成员
  Future<ApiResponse<List<ChatMember>>> searchMembers(
    String chatId,
    String keyword, {
    int page = 1,
    int pageSize = 200,
  }) async {
    final response = await _api.get(
      '/chat/$chatId/members/search',
      queryParameters: {
        'keyword': keyword,
        'page': page,
        'page_size': pageSize,
      },
    );

    if (response.isSuccess && response.data != null) {
      // 兼容后端返回 List 或 { list: [...] } 两种结构
      List rawList;
      if (response.data is List) {
        rawList = response.data as List;
      } else if (response.data is Map) {
        rawList = (response.data as Map)['list'] as List? ?? [];
      } else {
        rawList = [];
      }
      final list = rawList.map((e) => ChatMember.fromJson(e)).toList();
      return ApiResponse(
        code: response.code,
        message: response.message,
        data: list,
      );
    }

    return ApiResponse(
      code: response.code,
      message: response.message,
      data: [],
    );
  }

  Future<ApiResponse> addMembers(String chatId, List<String> userIds) async {
    return _api.post('/chat/$chatId/members', data: {'user_ids': userIds});
  }

  /// 移除成员
  Future<ApiResponse> removeMember(String chatId, String userId) async {
    return _api.delete('/chat/$chatId/members/$userId');
  }

  /// 退出群组/频道
  Future<ApiResponse> leaveChat(String chatId) async {
    return _api.post('/chat/$chatId/leave');
  }

  /// 隐藏聊天（从列表移除，不删除消息）
  Future<ApiResponse> hideChat(String chatId) async {
    return _api.post('/chat/$chatId/hide');
  }

  /// 仅为自己清空聊天记录
  Future<ApiResponse> clearChatHistory(String chatId) async {
    return _api.post('/chat/$chatId/clear');
  }

  /// 为双方清空聊天记录（TG 模式，仅私聊）
  Future<ApiResponse> clearChatHistoryForBoth(String chatId) async {
    return _api.post('/chat/$chatId/clear-both');
  }

  /// 加入/订阅群组或频道
  Future<ApiResponse> joinChat(String chatId) async {
    return _api.post('/chat/$chatId/join');
  }

  /// 获取加入请求列表
  Future<ApiResponse<List<JoinRequest>>> getJoinRequests(String chatId) async {
    final response = await _api.get('/chat/$chatId/join-requests');
    if (response.isSuccess && response.data != null) {
      final list =
          (response.data['list'] as List?)
              ?.map((e) => JoinRequest.fromJson(e))
              .toList() ??
          [];
      return ApiResponse(code: 0, message: 'success', data: list);
    }
    return ApiResponse(
      code: response.code,
      message: response.message ?? '请求失败',
    );
  }

  /// 审批加入请求
  Future<ApiResponse> reviewJoinRequest(
    String chatId,
    String requestId,
    bool approve,
  ) async {
    return _api.post(
      '/chat/$chatId/join-requests/$requestId/review',
      data: {'approve': approve},
    );
  }

  /// 获取消息列表
  Future<ApiResponse<List<Message>>> getMessages(
    String chatId, {
    int? beforeSeq,
    int limit = 50,
  }) async {
    final response = await _api.get(
      '/message/list',
      queryParameters: {
        'chat_id': chatId,
        if (beforeSeq != null) 'before_seq': beforeSeq,
        'limit': limit,
      },
    );

    if (response.isSuccess && response.data != null) {
      final list = await _parseMessageList(response.data as List? ?? const []);
      return ApiResponse(
        code: response.code,
        message: response.message,
        data: list,
      );
    }

    return ApiResponse(
      code: response.code,
      message: response.message,
      data: [],
    );
  }

  /// 增量同步消息（断线重连后调用，获取 lastSeq 之后的新消息）
  Future<ApiResponse<List<Message>>> syncMessages(
    String chatId, {
    required int lastSeq,
  }) async {
    final response = await _api.post(
      '/message/sync',
      data: {'chat_id': chatId, 'last_seq': lastSeq},
    );

    if (response.isSuccess && response.data != null) {
      final messagesData = response.data is Map
          ? response.data['messages']
          : response.data;
      final list = await _parseMessageList(messagesData as List? ?? const []);
      return ApiResponse(
        code: response.code,
        message: response.message,
        data: list,
      );
    }

    return ApiResponse(
      code: response.code,
      message: response.message,
      data: [],
    );
  }

  /// 发送消息
  Future<ApiResponse<Message>> sendMessage({
    required String chatId,
    required int type,
    required MessageContent content,
    String? msgId,
    ReplyInfo? replyTo,
    List<String>? mentions,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
    bool allowModeRetry = true,
  }) async {
    final contentJson = content.toJson();
    final payload = <String, dynamic>{
      'chat_id': chatId,
      'type': type,
      if (msgId != null && msgId.isNotEmpty) 'msg_id': msgId,
      if (burnAfterRead) 'burn_after_read': true,
      if (burnAfterRead && burnAfterSeconds > 0)
        'burn_after_seconds': burnAfterSeconds,
    };

    final cryptoMode = await _loadMessageCryptoMode(forceRefresh: true);
    final supportsE2EE = _e2ee.supportsMessageType(type);
    if (cryptoMode.isPlain) {
      _attachPlainMessagePayload(
        payload,
        contentJson,
        replyTo: replyTo,
        mentions: mentions,
      );
    } else if (!supportsE2EE) {
      if (cryptoMode.isStrict) {
        return _cryptoModeError('严格加密模式下，当前消息类型暂不支持发送');
      }
      _attachPlainMessagePayload(
        payload,
        contentJson,
        replyTo: replyTo,
        mentions: mentions,
      );
    } else {
      try {
        final encrypted = await _e2ee.encryptMessage(
          chatId: chatId,
          type: type,
          content: contentJson,
          replyTo: replyTo?.toJson(),
          mentions: mentions,
        );
        if (encrypted != null) {
          payload['e2ee'] = encrypted.payload.toJson();
        } else if (cryptoMode.isStrict) {
          return _cryptoModeError('严格加密模式下，当前消息必须使用端到端加密发送');
        } else {
          _attachPlainMessagePayload(
            payload,
            contentJson,
            replyTo: replyTo,
            mentions: mentions,
          );
        }
      } catch (e) {
        if (cryptoMode.isStrict) {
          return _cryptoModeError(
            _strictCryptoFailureMessage(e, isEdit: false),
          );
        }
        _attachPlainMessagePayload(
          payload,
          contentJson,
          replyTo: replyTo,
          mentions: mentions,
        );
      }
    }

    final response = await _api.post('/message/send', data: payload);
    if (!response.isSuccess &&
        allowModeRetry &&
        _shouldRetryAfterCryptoModeRefresh(response.message, isEdit: false)) {
      await _systemSettings.getSettings(forceRefresh: true);
      return sendMessage(
        chatId: chatId,
        type: type,
        content: content,
        msgId: msgId,
        replyTo: replyTo,
        mentions: mentions,
        burnAfterRead: burnAfterRead,
        burnAfterSeconds: burnAfterSeconds,
        allowModeRetry: false,
      );
    }
    if (response.isSuccess && response.data != null && response.data is Map) {
      final parsed = await parseIncomingMessage(
        Map<String, dynamic>.from(response.data as Map),
      );
      return ApiResponse(
        code: response.code,
        message: response.message,
        data: parsed,
      );
    }

    return ApiResponse(code: response.code, message: response.message);
  }

  /// 撤回消息
  Future<ApiResponse> revokeMessage(String chatId, String msgId) async {
    return _api.post(
      '/message/revoke',
      data: {'chat_id': chatId, 'msg_id': msgId},
    );
  }

  /// 添加表情回复
  Future<ApiResponse> addReaction(
    String chatId,
    String msgId,
    String emoji,
  ) async {
    return _api.post(
      '/message/reaction/add',
      data: {'chat_id': chatId, 'msg_id': msgId, 'emoji': emoji},
    );
  }

  /// 移除表情回复
  Future<ApiResponse> removeReaction(
    String chatId,
    String msgId,
    String emoji,
  ) async {
    return _api.post(
      '/message/reaction/remove',
      data: {'chat_id': chatId, 'msg_id': msgId, 'emoji': emoji},
    );
  }

  /// 转发消息
  Future<ApiResponse<Message>> forwardMessage({
    required String sourceChatId,
    required String sourceMsgId,
    required String targetChatId,
  }) async {
    return _api.post(
      '/message/forward',
      data: {
        'source_chat_id': sourceChatId,
        'source_msg_id': sourceMsgId,
        'target_chat_id': targetChatId,
      },
      fromJson: (data) => Message.fromJson(data),
    );
  }
  /// 批量转发消息（多条×多目标，后端并发处理）
  Future<ApiResponse<Map<String, dynamic>>> forwardMessageBatch({
    required String sourceChatId,
    required List<String> sourceMsgIds,
    required List<String> targetChatIds,
  }) async {
    return _api.post<Map<String, dynamic>>(
      '/message/forward-batch',
      data: {
        'source_chat_id': sourceChatId,
        'source_msg_ids': sourceMsgIds,
        'target_chat_ids': targetChatIds,
      },
      fromJson: (json) => Map<String, dynamic>.from(json as Map),
    );
  }


  /// 编辑消息
  Future<ApiResponse> editMessage(
    String chatId,
    String msgId,
    String content, {
    bool allowModeRetry = true,
  }) async {
    final payload = <String, dynamic>{'chat_id': chatId, 'msg_id': msgId};
    final cryptoMode = await _loadMessageCryptoMode(forceRefresh: true);
    if (cryptoMode.isPlain) {
      payload['content'] = content;
      final response = await _api.post('/message/edit', data: payload);
      if (!response.isSuccess &&
          allowModeRetry &&
          _shouldRetryAfterCryptoModeRefresh(response.message, isEdit: true)) {
        await _systemSettings.getSettings(forceRefresh: true);
        return editMessage(chatId, msgId, content, allowModeRetry: false);
      }
      return response;
    }

    try {
      final encrypted = await _e2ee.encryptMessage(
        chatId: chatId,
        type: 1,
        content: {'text': content},
      );
      if (encrypted != null) {
        payload['e2ee'] = encrypted.payload.toJson();
      } else if (cryptoMode.isStrict) {
        return _cryptoModeError('严格加密模式下，编辑消息必须使用端到端加密');
      } else {
        payload['content'] = content;
      }
    } catch (e) {
      if (cryptoMode.isStrict) {
        return _cryptoModeError(_strictCryptoFailureMessage(e, isEdit: true));
      }
      payload['content'] = content;
    }
    final response = await _api.post('/message/edit', data: payload);
    if (!response.isSuccess &&
        allowModeRetry &&
        _shouldRetryAfterCryptoModeRefresh(response.message, isEdit: true)) {
      await _systemSettings.getSettings(forceRefresh: true);
      return editMessage(chatId, msgId, content, allowModeRetry: false);
    }
    return response;
  }

  /// 标记消息已读 (清除未读计数)
  Future<ApiResponse> markAsRead(String chatId, {int? msgSeq}) async {
    return _api.post(
      '/message/read',
      data: {'chat_id': chatId, if (msgSeq != null) 'msg_seq': msgSeq},
    );
  }

  /// 禁言成员
  /// [duration] 禁言时长(分钟)，0表示永久
  Future<ApiResponse> muteMember(
    String chatId,
    String userId, {
    int duration = 0,
  }) async {
    return _api.post(
      '/chat/$chatId/mute',
      data: {'user_id': userId, 'duration': duration},
    );
  }

  /// 解除禁言
  Future<ApiResponse> unmuteMember(String chatId, String userId) async {
    return _api.post('/chat/$chatId/unmute', data: {'user_id': userId});
  }

  /// 获取成员禁言状态
  Future<ApiResponse<MuteStatus>> getMuteStatus(
    String chatId,
    String userId,
  ) async {
    return _api.get(
      '/chat/$chatId/mute-status',
      queryParameters: {'user_id': userId},
      fromJson: (data) => MuteStatus.fromJson(data),
    );
  }

  /// 切换会话置顶状态
  Future<ApiResponse<bool>> togglePin(String chatId) async {
    final response = await _api.post('/chat/$chatId/pin');
    if (response.isSuccess && response.data != null) {
      return ApiResponse<bool>(
        code: 0,
        data: response.data['is_pinned'] ?? false,
        message: response.message,
      );
    }
    return ApiResponse<bool>(code: response.code, message: response.message);
  }

  /// 切换会话静音状态
  Future<ApiResponse<bool>> toggleMuteChat(String chatId) async {
    final response = await _api.post('/chat/$chatId/mute-chat');
    if (response.isSuccess && response.data != null) {
      return ApiResponse<bool>(
        code: 0,
        data: response.data['is_muted'] ?? false,
        message: response.message,
      );
    }
    return ApiResponse<bool>(code: response.code, message: response.message);
  }

  /// 切换会话未读状态
  Future<ApiResponse<int>> toggleUnread(String chatId) async {
    final response = await _api.post('/chat/$chatId/toggle-unread');
    if (response.isSuccess && response.data != null) {
      return ApiResponse<int>(
        code: 0,
        data: response.data['unread_count'] ?? 0,
        message: response.message,
      );
    }
    return ApiResponse<int>(code: response.code, message: response.message);
  }

  /// 获取聊天媒体列表
  /// [type] 类型: media(图片视频), file, link, voice
  Future<ApiResponse<ChatMediaResult>> getChatMedia(
    String chatId,
    String type, {
    int page = 1,
    int limit = 20,
  }) async {
    final response = await _api.get(
      '/message/media',
      queryParameters: {
        'chat_id': chatId,
        'type': type,
        'page': page,
        'limit': limit,
      },
    );

    if (response.isSuccess && response.data != null) {
      return ApiResponse(
        code: 0,
        message: response.message,
        data: ChatMediaResult.fromJson(response.data),
      );
    }
    return ApiResponse(code: response.code, message: response.message);
  }

  /// 获取聊天媒体数量统计
  Future<ApiResponse<ChatMediaCounts>> getChatMediaCounts(String chatId) async {
    final response = await _api.get(
      '/message/media/count',
      queryParameters: {'chat_id': chatId},
    );

    if (response.isSuccess && response.data != null) {
      return ApiResponse(
        code: 0,
        message: response.message,
        data: ChatMediaCounts.fromJson(response.data),
      );
    }
    return ApiResponse(code: response.code, message: response.message);
  }

  /// 搜索消息
  Future<ApiResponse<SearchMessageResult>> searchMessages(
    String chatId,
    String keyword,
  ) async {
    final response = await _api.get(
      '/chat/$chatId/search',
      queryParameters: {'keyword': keyword},
    );

    if (response.isSuccess && response.data != null) {
      return ApiResponse(
        code: 0,
        message: response.message,
        data: SearchMessageResult.fromJson(response.data),
      );
    }
    return ApiResponse(code: response.code, message: response.message);
  }

  /// 置顶消息
  Future<ApiResponse> pinMessage(String chatId, String messageId) async {
    return _api.post(
      '/chat/$chatId/pin-message',
      data: {'message_id': messageId},
    );
  }

  /// 取消置顶消息
  Future<ApiResponse> unpinMessage(String chatId) async {
    return _api.delete('/chat/$chatId/pin-message');
  }

  /// 获取置顶消息
  Future<ApiResponse> getPinnedMessage(String chatId) async {
    return _api.get('/chat/$chatId/pin-message');
  }

  /// 获取群公告列表
  Future<ApiResponse<AnnouncementListResult>> getAnnouncements(
    String chatId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final response = await _api.get(
      '/chat/$chatId/announcements',
      queryParameters: {
        'page': page.toString(),
        'page_size': pageSize.toString(),
      },
    );
    if (response.isSuccess && response.data != null) {
      return ApiResponse(
        code: 0,
        message: response.message,
        data: AnnouncementListResult.fromJson(response.data),
      );
    }
    return ApiResponse(code: response.code, message: response.message);
  }

  /// 创建群公告
  Future<ApiResponse> createAnnouncement(String chatId, String content) async {
    return _api.post('/chat/$chatId/announcements', data: {'content': content});
  }

  /// 更新群公告
  Future<ApiResponse> updateAnnouncement(
    String chatId,
    int announcementId,
    String content,
  ) async {
    return _api.put(
      '/chat/$chatId/announcements/$announcementId',
      data: {'content': content},
    );
  }

  /// 删除群公告
  Future<ApiResponse> deleteAnnouncement(
    String chatId,
    int announcementId,
  ) async {
    return _api.delete('/chat/$chatId/announcements/$announcementId');
  }
}

/// 聊天媒体结果
class ChatMediaResult {
  final List<ChatMediaItem> list;
  final int total;
  final int page;
  final int limit;

  ChatMediaResult({
    required this.list,
    required this.total,
    required this.page,
    required this.limit,
  });

  factory ChatMediaResult.fromJson(Map<String, dynamic> json) {
    return ChatMediaResult(
      list:
          (json['list'] as List?)
              ?.map((e) => ChatMediaItem.fromJson(e))
              .toList() ??
          [],
      total: json['total'] ?? 0,
      page: json['page'] ?? 1,
      limit: json['limit'] ?? 20,
    );
  }
}

/// 聊天媒体项
class ChatMediaItem {
  final String id;
  final String chatId;
  final String senderId;
  final String? senderName;
  final String? senderAvatar;
  final int type;
  final Map<String, dynamic> content;
  final DateTime createdAt;

  ChatMediaItem({
    required this.id,
    required this.chatId,
    required this.senderId,
    this.senderName,
    this.senderAvatar,
    required this.type,
    required this.content,
    required this.createdAt,
  });

  factory ChatMediaItem.fromJson(Map<String, dynamic> json) {
    final senderAvatar = ApiConfig.getMediaUrl(
      json['sender_avatar']?.toString(),
    );
    return ChatMediaItem(
      id: json['id']?.toString() ?? '',
      chatId: json['chat_id'] ?? '',
      senderId: json['sender_id'] ?? '',
      senderName: json['sender_name'],
      senderAvatar: senderAvatar.isEmpty ? null : senderAvatar,
      type: json['type'] ?? 1,
      content: json['content'] ?? {},
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at']).toLocal()
          : DateTime.now(),
    );
  }

  /// 获取媒体 URL（图片/视频）
  String? get mediaUrl {
    // 嵌套结构: content.media.url
    if (content['media'] != null) {
      final media = content['media'];
      if (media['url'] != null) {
        return ApiConfig.getMediaUrl(media['url']);
      }
      if (media['thumbnail'] != null) {
        return ApiConfig.getMediaUrl(media['thumbnail']);
      }
    }
    // 兼容扁平结构
    if (content['url'] != null) {
      return ApiConfig.getMediaUrl(content['url']);
    }
    if (content['thumbnail'] != null) {
      return ApiConfig.getMediaUrl(content['thumbnail']);
    }
    return null;
  }

  /// 获取缩略图 URL
  String? get thumbnailUrl {
    if (content['media'] != null) {
      final media = content['media'];
      if (media['thumbnail'] != null) {
        return ApiConfig.getMediaUrl(media['thumbnail']);
      }
    }
    if (content['thumbnail'] != null) {
      return ApiConfig.getMediaUrl(content['thumbnail']);
    }
    return mediaUrl;
  }

  /// 获取语音 URL
  String? get voiceUrl {
    if (content['voice'] != null) {
      final voice = content['voice'];
      if (voice['url'] != null) {
        return ApiConfig.getMediaUrl(voice['url']);
      }
    }
    if (content['url'] != null) {
      return ApiConfig.getMediaUrl(content['url']);
    }
    return null;
  }

  /// 获取文件 URL
  String? get fileUrl {
    if (content['file'] != null) {
      final file = content['file'];
      if (file['url'] != null) {
        return ApiConfig.getMediaUrl(file['url']);
      }
    }
    if (content['url'] != null) {
      return ApiConfig.getMediaUrl(content['url']);
    }
    return null;
  }

  /// 获取文本内容
  String? get text => content['text'];

  /// 获取文件名
  String? get fileName {
    if (content['file'] != null) {
      return content['file']['name'] ?? content['file']['filename'];
    }
    return content['name'] ?? content['filename'];
  }

  /// 获取文件大小
  int? get fileSize {
    if (content['file'] != null) {
      return content['file']['size'];
    }
    return content['size'];
  }

  /// 获取时长（语音/视频）
  int? get duration {
    if (content['voice'] != null) {
      return content['voice']['duration'];
    }
    if (content['media'] != null) {
      return content['media']['duration'];
    }
    return content['duration'];
  }
}

/// 聊天媒体数量统计
class ChatMediaCounts {
  final int media;
  final int file;
  final int link;
  final int voice;

  ChatMediaCounts({
    required this.media,
    required this.file,
    required this.link,
    required this.voice,
  });

  factory ChatMediaCounts.fromJson(Map<String, dynamic> json) {
    return ChatMediaCounts(
      media: json['media'] ?? 0,
      file: json['file'] ?? 0,
      link: json['link'] ?? 0,
      voice: json['voice'] ?? 0,
    );
  }
}

/// 搜索消息结果
class SearchMessageResult {
  final List<SearchMessageItem> list;
  final int total;

  SearchMessageResult({required this.list, required this.total});

  factory SearchMessageResult.fromJson(Map<String, dynamic> json) {
    return SearchMessageResult(
      list:
          (json['list'] as List?)
              ?.map((e) => SearchMessageItem.fromJson(e))
              .toList() ??
          [],
      total: json['total'] ?? 0,
    );
  }
}

/// 搜索消息项
class SearchMessageItem {
  final String id;
  final String msgId;   // 业务消息 ID（msg_id），用于跳转定位
  final String chatId;
  final String senderId;
  final String? senderName;
  final String? senderAvatar;
  final int type;
  final Map<String, dynamic> content;
  final DateTime createdAt;

  SearchMessageItem({
    required this.id,
    required this.msgId,
    required this.chatId,
    required this.senderId,
    this.senderName,
    this.senderAvatar,
    required this.type,
    required this.content,
    required this.createdAt,
  });

  factory SearchMessageItem.fromJson(Map<String, dynamic> json) {
    final senderAvatar = ApiConfig.getMediaUrl(
      json['sender_avatar']?.toString(),
    );

    // content 兼容两种格式：
    // 1. ES 返回字符串：content = "消息文字"，highlight = "<em>...</em>"
    // 2. MongoDB 返回对象：content = {text: "消息文字"}
    Map<String, dynamic> contentMap;
    final rawContent = json['content'];
    if (rawContent is Map) {
      contentMap = Map<String, dynamic>.from(rawContent);
    } else if (rawContent is String) {
      // ES 返回：用 highlight 或 content 字符串作为 text
      final highlight = json['highlight']?.toString() ?? '';
      final displayText = highlight.isNotEmpty ? highlight : rawContent;
      contentMap = {'text': displayText};
    } else {
      contentMap = {};
    }

    // created_at 兼容两种格式：
    // 1. ES 返回毫秒时间戳（int）
    // 2. MongoDB 返回 ISO 字符串
    DateTime createdAt;
    final rawTime = json['created_at'];
    if (rawTime is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(rawTime).toLocal();
    } else if (rawTime is String) {
      createdAt = DateTime.tryParse(rawTime)?.toLocal() ?? DateTime.now();
    } else {
      createdAt = DateTime.now();
    }

    return SearchMessageItem(
      id: json['id']?.toString() ?? json['msg_id']?.toString() ?? '',
      msgId: json['msg_id']?.toString() ?? json['id']?.toString() ?? '',
      chatId: json['chat_id'] ?? '',
      senderId: json['sender_id'] ?? '',
      senderName: json['sender_name'],
      senderAvatar: senderAvatar.isEmpty ? null : senderAvatar,
      type: json['type'] ?? 1,
      content: contentMap,
      createdAt: createdAt,
    );
  }

  /// 获取文本内容（去除 HTML 高亮标签）
  String get text {
    final raw = content['text']?.toString() ?? '';
    return raw.replaceAll(RegExp(r'<[^>]*>'), '');
  }
}

/// 禁言状态
class MuteStatus {
  final bool isMuted;
  final DateTime? muteEndTime;

  MuteStatus({required this.isMuted, this.muteEndTime});

  factory MuteStatus.fromJson(Map<String, dynamic> json) {
    final rawMuteEndTime = json['mute_end_time']?.toString();
    return MuteStatus(
      isMuted: json['is_muted'] ?? false,
      muteEndTime: rawMuteEndTime != null && rawMuteEndTime.isNotEmpty
          ? DateTime.tryParse(rawMuteEndTime)?.toLocal()
          : null,
    );
  }
}

/// 加入请求
class JoinRequest {
  final String id;
  final String userId;
  final String nickname;
  final String? username;
  final String? avatar;
  final String? message;
  final DateTime createdAt;

  JoinRequest({
    required this.id,
    required this.userId,
    required this.nickname,
    this.username,
    this.avatar,
    this.message,
    required this.createdAt,
  });

  factory JoinRequest.fromJson(Map<String, dynamic> json) {
    final avatar = ApiConfig.getMediaUrl(json['avatar']?.toString());
    return JoinRequest(
      id: json['id']?.toString() ?? '',
      userId: json['user_id'] ?? '',
      nickname: json['nickname'] ?? '',
      username: json['username'],
      avatar: avatar.isEmpty ? null : avatar,
      message: json['message'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at']).toLocal()
          : DateTime.now(),
    );
  }
}

/// 群公告列表结果
class AnnouncementListResult {
  final List<AnnouncementItem> list;
  final int total;
  final int page;
  final int pageSize;

  AnnouncementListResult({
    required this.list,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  factory AnnouncementListResult.fromJson(Map<String, dynamic> json) {
    return AnnouncementListResult(
      list:
          (json['list'] as List?)
              ?.map((e) => AnnouncementItem.fromJson(e))
              .toList() ??
          [],
      total: json['total'] ?? 0,
      page: json['page'] ?? 1,
      pageSize: json['page_size'] ?? 20,
    );
  }
}

/// 群公告项
class AnnouncementItem {
  final int id;
  final int chatId;
  final String content;
  final int authorId;
  final String? authorName;
  final String? authorAvatar;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime updatedAt;

  AnnouncementItem({
    required this.id,
    required this.chatId,
    required this.content,
    required this.authorId,
    this.authorName,
    this.authorAvatar,
    required this.isPinned,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AnnouncementItem.fromJson(Map<String, dynamic> json) {
    final authorAvatar = ApiConfig.getMediaUrl(
      json['author_avatar']?.toString(),
    );
    return AnnouncementItem(
      id: json['id'] ?? 0,
      chatId: json['chat_id'] ?? 0,
      content: json['content'] ?? '',
      authorId: json['author_id'] ?? 0,
      authorName: json['author_name'],
      authorAvatar: authorAvatar.isEmpty ? null : authorAvatar,
      isPinned: json['is_pinned'] ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at']).toLocal()
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at']).toLocal()
          : DateTime.now(),
    );
  }
}

/// Provider
final chatServiceProvider = Provider<ChatService>((ref) {
  final api = ref.watch(apiClientProvider);
  final ws = ref.watch(webSocketServiceProvider.notifier);
  final e2ee = ref.watch(e2eeServiceProvider);
  final systemSettings = ref.watch(systemSettingsServiceProvider);
  return ChatService(api, ws, e2ee, systemSettings);
});
