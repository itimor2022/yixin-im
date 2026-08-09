// 文件用途：封装 ChatType 对应的后端 API 请求、响应模型与错误处理。
// 核心逻辑：封装会话、消息、媒体和成员相关 API，负责请求参数编码、分页结果转换以及端到端加密载荷的收发。
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../i18n/app_localizations.dart';
import '../e2ee/e2ee_models.dart';
import '../e2ee/e2ee_service.dart';
import 'api_client.dart';
import 'system_settings_service.dart';
import 'websocket_service.dart';

// 流程逻辑：`normalizeMessageMentions` 集中处理输入规范化、空值和兼容字段，输出稳定的数据结构，避免调用方重复实现边界判断。
({bool mentionAll, List<String>? memberIds}) normalizeMessageMentions(
  List<String>? mentions,
) {
  if (mentions == null) {
    return (mentionAll: false, memberIds: null);
  }
  final mentionAll = mentions.contains('__all__');
  final memberIds = mentions
      .where((mention) => mention != '__all__')
      .toSet()
      .toList(growable: false);
  return (
    mentionAll: mentionAll,
    memberIds: memberIds.isEmpty ? null : memberIds,
  );
}

String _chatServiceText({
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

bool _chatServiceContainsHan(String value) {
  return RegExp(r'[\u4e00-\u9fff]').hasMatch(value);
}

DateTime? _parseOptionalServerDateTime(dynamic raw) {
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text)?.toLocal();
  if (parsed == null) return null;
  if (parsed.year <= 1) return null;
  return parsed;
}

Map<String, dynamic> _parseVipPayload(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return const <String, dynamic>{};
}

int _parseVipLevel(dynamic raw) {
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}

String _parseVipBadgeIcon(dynamic raw) {
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return '';
  return ApiConfig.getMediaUrl(text);
}

// 关键声明：聊天 API 服务负责把服务端 JSON 映射为领域对象，并在发送前处理加密、提及、引用和幂等消息 ID。
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
  final int vipLevel;
  final String vipBadge;
  final String vipBadgeIcon;
  final bool vipActive;
  // 权限设置
  final bool canSendMessage;
  final bool canSendMedia;
  final bool canSendLinks;
  final bool canAddMembers;
  final bool canPinMessages;
  final bool allowAnonymous;
  final bool allowForward;
  final bool allowViewHistory;
  final bool memberProtection;
  final bool joinApproval; // 是否需要审批加入
  final int status; // 0=normal, 1=banned, 2=dissolved
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
    this.vipLevel = 0,
    this.vipBadge = '',
    this.vipBadgeIcon = '',
    this.vipActive = false,
    this.canSendMessage = true,
    this.canSendMedia = true,
    this.canSendLinks = true,
    this.canAddMembers = false,
    this.canPinMessages = false,
    this.allowAnonymous = false,
    this.allowForward = true,
    this.allowViewHistory = true,
    this.memberProtection = false,
    this.joinApproval = false,
    this.status = 0,
    required this.createdAt,
  });

  /// 是否是管理员或群主
  bool get isAdmin => myRole >= 2;

  /// 是否是群主
  bool get isOwner => myRole == 3;

  bool get vipVisible => vipActive && vipLevel > 0;

  factory Chat.fromJson(Map<String, dynamic> json) {
    String? avatarUrl = json['avatar'];
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
    }
    final vip = _parseVipPayload(json['vip']);

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
      vipLevel: _parseVipLevel(vip['level']),
      vipBadge: vip['badge']?.toString() ?? '',
      vipBadgeIcon: _parseVipBadgeIcon(vip['badge_icon']),
      vipActive: vip['is_active'] == true,
      canSendMessage: json['can_send_message'] ?? true,
      canSendMedia: json['can_send_media'] ?? true,
      canSendLinks: json['can_send_links'] ?? true,
      canAddMembers: json['can_add_members'] ?? false,
      canPinMessages: json['can_pin_messages'] ?? false,
      allowAnonymous: json['allow_anonymous'] ?? false,
      allowForward: json['allow_forward'] ?? true,
      allowViewHistory: json['allow_view_history'] ?? true,
      memberProtection: json['member_protection'] ?? false,
      joinApproval: json['join_approval'] ?? false,
      status: (json['status'] as num?)?.toInt() ?? 0,
      createdAt:
          _parseOptionalServerDateTime(json['created_at']) ?? DateTime.now(),
    );
  }
}

class ChatAdminPermissions {
  final bool canChangeInfo;
  final bool canDeleteMessages;
  final bool canBanUsers;
  final bool canMuteUsers;
  final bool canInviteUsers;
  final bool canManageJoinRequests;
  final bool canPinMessages;
  final bool canPostMessages;
  final bool canEditMessages;
  final bool canManageAdmins;
  final bool canManageInviteLinks;
  final bool canViewStats;

  const ChatAdminPermissions({
    this.canChangeInfo = false,
    this.canDeleteMessages = false,
    this.canBanUsers = false,
    this.canMuteUsers = false,
    this.canInviteUsers = false,
    this.canManageJoinRequests = false,
    this.canPinMessages = false,
    this.canPostMessages = false,
    this.canEditMessages = false,
    this.canManageAdmins = false,
    this.canManageInviteLinks = false,
    this.canViewStats = false,
  });

  factory ChatAdminPermissions.fromJson(Map<String, dynamic>? json) {
    final data = json ?? const <String, dynamic>{};
    return ChatAdminPermissions(
      canChangeInfo: data['can_change_info'] == true,
      canDeleteMessages: data['can_delete_messages'] == true,
      canBanUsers: data['can_ban_users'] == true,
      canMuteUsers: data['can_mute_users'] == true,
      canInviteUsers: data['can_invite_users'] == true,
      canManageJoinRequests: data['can_manage_join_requests'] == true,
      canPinMessages: data['can_pin_messages'] == true,
      canPostMessages: data['can_post_messages'] == true,
      canEditMessages: data['can_edit_messages'] == true,
      canManageAdmins: data['can_manage_admins'] == true,
      canManageInviteLinks: data['can_manage_invite_links'] == true,
      canViewStats: data['can_view_stats'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'can_change_info': canChangeInfo,
        'can_delete_messages': canDeleteMessages,
        'can_ban_users': canBanUsers,
        'can_mute_users': canMuteUsers,
        'can_invite_users': canInviteUsers,
        'can_manage_join_requests': canManageJoinRequests,
        'can_pin_messages': canPinMessages,
        'can_post_messages': canPostMessages,
        'can_edit_messages': canEditMessages,
        'can_manage_admins': canManageAdmins,
        'can_manage_invite_links': canManageInviteLinks,
        'can_view_stats': canViewStats,
      };
}

class MyChatPermissions {
  final int role;
  final bool isOwner;
  final bool isAdmin;
  final ChatAdminPermissions permissions;

  const MyChatPermissions({
    required this.role,
    required this.isOwner,
    required this.isAdmin,
    required this.permissions,
  });

  factory MyChatPermissions.fromJson(Map<String, dynamic> json) {
    return MyChatPermissions(
      role: json['role'] ?? 0,
      isOwner: json['is_owner'] == true,
      isAdmin: json['is_admin'] == true,
      permissions: ChatAdminPermissions.fromJson(
        (json['permissions'] as Map?)?.cast<String, dynamic>(),
      ),
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
  final int vipLevel;
  final String vipBadge;
  final String vipBadgeIcon;
  final bool vipActive;

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
    this.vipLevel = 0,
    this.vipBadge = '',
    this.vipBadgeIcon = '',
    this.vipActive = false,
  });

  /// 显示名称（优先 nickname）
  String get displayName => nickname.isNotEmpty ? nickname : username;

  bool get vipVisible => vipActive && vipLevel > 0;

  /// 角色名称
  String get roleName {
    switch (role) {
      case 3:
        return _chatServiceText(zhCN: '群主', zhTW: '群主', en: 'Owner');
      case 2:
        return _chatServiceText(zhCN: '管理员', zhTW: '管理員', en: 'Admin');
      default:
        return _chatServiceText(zhCN: '成员', zhTW: '成員', en: 'Member');
    }
  }

  /// 禁言状态文本
  String get muteStatusText {
    if (!isMuted) return '';
    if (muteEndTime == null) {
      return _chatServiceText(
        zhCN: '永久禁言',
        zhTW: '永久禁言',
        en: 'Muted permanently',
      );
    }
    final remaining = muteEndTime!.difference(DateTime.now());
    if (remaining.isNegative) return '';
    if (remaining.inDays > 0) {
      return _chatServiceText(
        zhCN: '禁言 ${remaining.inDays} 天',
        zhTW: '禁言 ${remaining.inDays} 天',
        en: 'Muted for ${remaining.inDays} days',
      );
    }
    if (remaining.inHours > 0) {
      return _chatServiceText(
        zhCN: '禁言 ${remaining.inHours} 小时',
        zhTW: '禁言 ${remaining.inHours} 小時',
        en: 'Muted for ${remaining.inHours} hours',
      );
    }
    return _chatServiceText(
      zhCN: '禁言 ${remaining.inMinutes} 分钟',
      zhTW: '禁言 ${remaining.inMinutes} 分鐘',
      en: 'Muted for ${remaining.inMinutes} minutes',
    );
  }

  factory ChatMember.fromJson(Map<String, dynamic> json) {
    String? avatarUrl = json['avatar'];
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
    }
    final rawVip = json['vip'];
    final vip = rawVip is Map
        ? Map<String, dynamic>.from(rawVip)
        : const <String, dynamic>{};

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
      vipLevel: int.tryParse(vip['level']?.toString() ?? '') ?? 0,
      vipBadge: vip['badge']?.toString() ?? '',
      vipBadgeIcon: _parseVipBadgeIcon(vip['badge_icon']),
      vipActive: vip['is_active'] == true,
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
  final String? lastMsgMediaUrl;
  final int unreadCount;
  final bool hasMention;
  final bool isPinned;
  final bool isMuted;
  final bool isArchived;
  final bool? pendingRequest;
  final int? pendingRequestCount;
  final int status;

  // 关联的会话信息（直接从响应解析）
  final Chat? chat;

  // 直接字段（后端返回的 name/avatar/member_count）
  final String? name;
  final String? avatar;
  final int? type;
  final String? username;
  final int memberCount;
  final String? emojiAvatar; // 表情状态
  final String? nicknameColor; // 昵称颜色
  final int vipLevel;
  final String vipBadge;
  final String vipBadgeIcon;
  final bool vipActive;

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
    this.lastMsgMediaUrl,
    this.unreadCount = 0,
    this.hasMention = false,
    this.isPinned = false,
    this.isMuted = false,
    this.isArchived = false,
    this.pendingRequest,
    this.pendingRequestCount,
    this.status = 0,
    this.chat,
    this.name,
    this.avatar,
    this.type,
    this.username,
    this.memberCount = 0,
    this.emojiAvatar,
    this.nicknameColor,
    this.vipLevel = 0,
    this.vipBadge = '',
    this.vipBadgeIcon = '',
    this.vipActive = false,
  });

  factory UserChat.fromJson(Map<String, dynamic> json) {
    String? avatarUrl = json['avatar'];
    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      avatarUrl = ApiConfig.getMediaUrl(avatarUrl);
    }
    final rawLastMsgMediaUrl = json['last_msg_media_url']?.toString();
    final resolvedLastMsgMediaUrl =
        rawLastMsgMediaUrl != null && rawLastMsgMediaUrl.isNotEmpty
            ? ApiConfig.getMediaUrl(rawLastMsgMediaUrl)
            : null;
    // Chat-list rows do not carry media_id yet, so they cannot request an
    // authenticated short-lived S3 URL. Hide a private S3 preview instead of
    // repeatedly rendering a broken 403 thumbnail; the full message resolves
    // through media_id after the user enters the chat.
    final lastMsgMediaUrl = _isAmazonS3ObjectURL(resolvedLastMsgMediaUrl)
        ? null
        : resolvedLastMsgMediaUrl;
    final vip = _parseVipPayload(json['vip']);

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
      lastMsgMediaUrl: lastMsgMediaUrl,
      unreadCount: json['unread_count'] ?? 0,
      hasMention: json['has_mention'] == true,
      isPinned: json['is_pinned'] ?? false,
      isMuted: json['is_muted'] ?? false,
      isArchived: json['is_archived'] ?? false,
      pendingRequest: json['pending_request'],
      pendingRequestCount: json['pending_request_count'],
      status: (json['status'] as num?)?.toInt() ?? 0,
      // 直接解析 name, avatar, member_count
      name: json['name'],
      avatar: avatarUrl,
      type: json['type'],
      username: json['username']?.toString(),
      memberCount: json['member_count'] ?? 0,
      emojiAvatar: json['emoji_avatar'],
      nicknameColor: json['nickname_color'],
      vipLevel: _parseVipLevel(vip['level']),
      vipBadge: vip['badge']?.toString() ?? '',
      vipBadgeIcon: _parseVipBadgeIcon(vip['badge_icon']),
      vipActive: vip['is_active'] == true,
    );
  }
}

bool _isAmazonS3ObjectURL(String? value) {
  final uri = Uri.tryParse(value?.trim() ?? '');
  final host = uri?.host.toLowerCase() ?? '';
  return host == 's3.amazonaws.com' ||
      host.contains('.s3.amazonaws.com') ||
      (host.startsWith('s3.') && host.endsWith('.amazonaws.com')) ||
      (host.contains('.s3.') && host.endsWith('.amazonaws.com'));
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
  final String? senderEmojiAvatar; // 发送者动态表情
  final int senderVipLevel;
  final String senderVipBadge;
  final String senderVipBadgeIcon;
  final bool senderVipActive;
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
    this.senderEmojiAvatar,
    this.senderVipLevel = 0,
    this.senderVipBadge = '',
    this.senderVipBadgeIcon = '',
    this.senderVipActive = false,
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
    final senderVip = _parseVipPayload(
      json['sender_vip'] ?? json['senderVip'] ?? json['vip'],
    );

    return Message(
      id: json['id']?.toString() ?? '',
      msgId: json['msg_id'] ?? '',
      chatId: json['chat_id'] ?? '',
      seq: json['seq'] ?? 0,
      senderId: json['sender_id'] ?? '',
      senderName: json['sender_name'] ?? '',
      senderAvatar: senderAvatarUrl,
      senderNicknameColor: json['sender_nickname_color'],
      senderEmojiAvatar: json['sender_emoji_avatar'],
      senderVipLevel: _parseVipLevel(senderVip['level']),
      senderVipBadge: senderVip['badge']?.toString() ?? '',
      senderVipBadgeIcon: _parseVipBadgeIcon(senderVip['badge_icon']),
      senderVipActive: senderVip['is_active'] == true,
      type: json['type'] ?? 1,
      content: MessageContent.fromJson(json['content'] ?? {}),
      replyTo: json['reply_to'] != null
          ? ReplyInfo.fromJson(json['reply_to'])
          : null,
      mentions:
          json['mentions'] != null ? List<String>.from(json['mentions']) : null,
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
  final StickerInfo? sticker;
  final String? callType;
  final String? callStatus;
  final int? callDuration;
  final Map<String, dynamic>? forwardBundle;

  MessageContent({
    this.text,
    this.media,
    this.voice,
    this.file,
    this.location,
    this.contact,
    this.sticker,
    this.callType,
    this.callStatus,
    this.callDuration,
    this.forwardBundle,
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
      sticker: json['sticker'] != null
          ? StickerInfo.fromJson(json['sticker'])
          : null,
      callType: json['call_type']?.toString(),
      callStatus: json['status']?.toString(),
      callDuration: json['duration'] is num
          ? (json['duration'] as num).toInt()
          : int.tryParse(json['duration']?.toString() ?? ''),
      forwardBundle: json['forward_bundle'] is Map
          ? Map<String, dynamic>.from(json['forward_bundle'] as Map)
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
      if (sticker != null) 'sticker': sticker!.toJson(),
      if (callType != null) 'call_type': callType,
      if (callStatus != null) 'status': callStatus,
      if (callDuration != null) 'duration': callDuration,
      if (forwardBundle != null) 'forward_bundle': forwardBundle,
    };
  }
}

/// 名片信息
class StickerInfo {
  final String packId;
  final String stickerId;
  final String url;
  final String? emoji;

  StickerInfo({
    required this.packId,
    required this.stickerId,
    required this.url,
    this.emoji,
  });

  factory StickerInfo.fromJson(Map<String, dynamic> json) {
    return StickerInfo(
      packId: json['pack_id']?.toString() ?? '',
      stickerId: json['sticker_id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      emoji: json['emoji']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'pack_id': packId,
        'sticker_id': stickerId,
        'url': url,
        if (emoji != null) 'emoji': emoji,
      };
}

class ContactCardInfo {
  final String userId;
  final String nickname;
  final String? username;
  final String? avatar;
  final String? bio;
  final String? nicknameColor;
  final String? emojiAvatar;

  ContactCardInfo({
    required this.userId,
    required this.nickname,
    this.username,
    this.avatar,
    this.bio,
    this.nicknameColor,
    this.emojiAvatar,
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
      };
}

class MessageTranslationResult {
  final String text;
  final String translation;
  final String targetLang;
  final String model;

  const MessageTranslationResult({
    required this.text,
    required this.translation,
    required this.targetLang,
    required this.model,
  });

  factory MessageTranslationResult.fromJson(Map<String, dynamic> json) {
    return MessageTranslationResult(
      text: json['text']?.toString() ?? '',
      translation: json['translation']?.toString() ?? '',
      targetLang: json['target_lang']?.toString() ?? '',
      model: json['model']?.toString() ?? '',
    );
  }
}

/// 媒体信息
class MediaInfo {
  final String? mediaId;
  final String url;
  final String? thumbnailMediaId;
  final String? thumbnail;
  final int? width;
  final int? height;
  final int? duration;
  final int size;
  final String mimeType;
  final String? mediaGroupId;

  MediaInfo({
    this.mediaId,
    required this.url,
    this.thumbnailMediaId,
    this.thumbnail,
    this.width,
    this.height,
    this.duration,
    required this.size,
    required this.mimeType,
    this.mediaGroupId,
  });

  factory MediaInfo.fromJson(Map<String, dynamic> json) {
    return MediaInfo(
      mediaId: json['media_id']?.toString(),
      url: json['url'] ?? '',
      thumbnailMediaId: json['thumbnail_media_id']?.toString(),
      thumbnail: json['thumbnail'],
      width: json['width'],
      height: json['height'],
      duration: json['duration'],
      size: json['size'] ?? 0,
      mimeType: json['mime_type'] ?? '',
      mediaGroupId: json['media_group_id']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        if (mediaId != null && mediaId!.isNotEmpty) 'media_id': mediaId,
        'url': url,
        if (thumbnailMediaId != null && thumbnailMediaId!.isNotEmpty)
          'thumbnail_media_id': thumbnailMediaId,
        if (thumbnail != null) 'thumbnail': thumbnail,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (duration != null) 'duration': duration,
        'size': size,
        'mime_type': mimeType,
        if (mediaGroupId != null && mediaGroupId!.isNotEmpty)
          'media_group_id': mediaGroupId,
      };
}

/// 语音信息
class VoiceInfo {
  final String? mediaId;
  final String url;
  final int duration;
  final int size;
  final String? transcript;

  VoiceInfo({
    this.mediaId,
    required this.url,
    required this.duration,
    required this.size,
    this.transcript,
  });

  factory VoiceInfo.fromJson(Map<String, dynamic> json) {
    return VoiceInfo(
      mediaId: json['media_id']?.toString(),
      url: json['url'] ?? '',
      duration: json['duration'] ?? 0,
      size: json['size'] ?? 0,
      transcript: json['transcript'],
    );
  }

  Map<String, dynamic> toJson() => {
        if (mediaId != null && mediaId!.isNotEmpty) 'media_id': mediaId,
        'url': url,
        'duration': duration,
        'size': size,
        if (transcript != null && transcript!.isNotEmpty)
          'transcript': transcript,
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
  final String? mediaId;
  final String url;
  final String name;
  final int size;
  final String mimeType;

  FileInfo({
    this.mediaId,
    required this.url,
    required this.name,
    required this.size,
    required this.mimeType,
  });

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      mediaId: json['media_id']?.toString(),
      url: json['url'] ?? '',
      name: json['name'] ?? '',
      size: json['size'] ?? 0,
      mimeType: json['mime_type'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        if (mediaId != null && mediaId!.isNotEmpty) 'media_id': mediaId,
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

/// 会话 HTTP 边界：负责协议模型转换、加解密策略和服务端确认，不持有页面可见状态。
class ChatService {
  static const int localRejectedCode = 460;

  final ApiClient _api;
  final WebSocketService _ws;
  final E2EEService _e2ee;
  final SystemSettingsService _systemSettings;

  ChatService(this._api, this._ws, this._e2ee, this._systemSettings);

  /// 将 HTTP 和 WebSocket 的原始消息统一转换为领域模型。
  ///
  /// 解密失败时保留消息占位而不是丢弃，确保 seq 连续性及后续同步游标仍然可靠。
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
        return _chatServiceText(
          zhCN: '[加密图片]',
          zhTW: '[加密圖片]',
          en: '[Encrypted photo]',
        );
      case 3:
        return _chatServiceText(
          zhCN: '[加密视频]',
          zhTW: '[加密影片]',
          en: '[Encrypted video]',
        );
      case 4:
        return _chatServiceText(
          zhCN: '[加密语音]',
          zhTW: '[加密語音]',
          en: '[Encrypted voice]',
        );
      case 5:
        return _chatServiceText(
          zhCN: '[加密文件]',
          zhTW: '[加密文件]',
          en: '[Encrypted file]',
        );
      case 6:
        return _chatServiceText(
          zhCN: '[加密位置]',
          zhTW: '[加密位置]',
          en: '[Encrypted location]',
        );
      case 10:
        return _chatServiceText(
          zhCN: '[加密名片]',
          zhTW: '[加密名片]',
          en: '[Encrypted contact]',
        );
      default:
        return _chatServiceText(
          zhCN: '[加密消息]',
          zhTW: '[加密消息]',
          en: '[Encrypted message]',
        );
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

  List<String> _messageMediaIds(Map<String, dynamic> contentJson) {
    final values = <String>[];
    final seen = <String>{};

    void add(dynamic raw) {
      final value = raw?.toString().trim() ?? '';
      if (value.isNotEmpty && seen.add(value)) values.add(value);
    }

    for (final key in const ['media', 'voice', 'file']) {
      final nested = contentJson[key];
      if (nested is! Map) continue;
      add(nested['media_id']);
      if (key == 'media') add(nested['thumbnail_media_id']);
    }
    return values;
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
        ? _chatServiceText(
            zhCN: '严格加密模式下，当前会话暂时无法编辑加密消息',
            zhTW: '嚴格加密模式下，當前會話暫時無法編輯加密消息',
            en: 'Strict encryption mode cannot edit encrypted messages in this chat right now.',
          )
        : _chatServiceText(
            zhCN: '严格加密模式下，当前会话暂时无法发送加密消息',
            zhTW: '嚴格加密模式下，當前會話暫時無法發送加密消息',
            en: 'Strict encryption mode cannot send encrypted messages in this chat right now.',
          );
    final message = _normalizeCryptoExceptionMessage(error, fallback);

    if (message.contains('没有可用的加密设备')) {
      return isEdit
          ? _chatServiceText(
              zhCN: '严格加密模式下，对方当前还没有可用的加密设备，请让对方登录最新版客户端后再重试编辑。',
              zhTW: '嚴格加密模式下，對方目前還沒有可用的加密設備，請讓對方登入最新版客戶端後再重試編輯。',
              en: 'Strict encryption mode requires the other side to have an available encrypted device. Ask them to sign in on the latest client, then try editing again.',
            )
          : _chatServiceText(
              zhCN: '严格加密模式下，对方当前还没有可用的加密设备，请让对方登录最新版客户端后，再重新进入会话发送。',
              zhTW: '嚴格加密模式下，對方目前還沒有可用的加密設備，請讓對方登入最新版客戶端後，再重新進入會話發送。',
              en: 'Strict encryption mode requires the other side to have an available encrypted device. Ask them to sign in on the latest client, then reopen the chat and send again.',
            );
    }
    if (message.contains('未升级到加密版本')) {
      return isEdit
          ? _chatServiceText(
              zhCN: '严格加密模式下，会话里仍有设备未升级到加密版本。请双方更新到最新版客户端，并重新登录后再重试编辑。',
              zhTW: '嚴格加密模式下，會話裡仍有設備未升級到加密版本。請雙方更新到最新版客戶端，並重新登入後再重試編輯。',
              en: 'Strict encryption mode still has devices in this chat that are not on an encryption-capable version. Update both clients and sign in again before retrying the edit.',
            )
          : _chatServiceText(
              zhCN: '严格加密模式下，会话里仍有设备未升级到加密版本。请双方更新到最新版客户端，并重新登录后再发送。',
              zhTW: '嚴格加密模式下，會話裡仍有設備未升級到加密版本。請雙方更新到最新版客戶端，並重新登入後再發送。',
              en: 'Strict encryption mode still has devices in this chat that are not on an encryption-capable version. Update both clients and sign in again before sending.',
            );
    }
    if (message.contains('注册设备密钥失败')) {
      return isEdit
          ? _chatServiceText(
              zhCN: '严格加密模式下，本机加密密钥注册失败。请重新登录一次后，再重试编辑消息。',
              zhTW: '嚴格加密模式下，本機加密密鑰註冊失敗。請重新登入一次後，再重試編輯消息。',
              en: 'Strict encryption mode failed to register this device key. Sign in again, then retry editing the message.',
            )
          : _chatServiceText(
              zhCN: '严格加密模式下，本机加密密钥注册失败。请重新登录一次后，再重试发送消息。',
              zhTW: '嚴格加密模式下，本機加密密鑰註冊失敗。請重新登入一次後，再重試發送消息。',
              en: 'Strict encryption mode failed to register this device key. Sign in again, then retry sending the message.',
            );
    }
    if (message.contains('保存设备公钥失败') || message.contains('数据库未升级')) {
      return isEdit
          ? _chatServiceText(
              zhCN: '严格加密模式下，服务端设备密钥存储尚未升级完成。请重启最新后端服务后，再重试编辑消息。',
              zhTW: '嚴格加密模式下，服務端設備密鑰存儲尚未升級完成。請重啟最新後端服務後，再重試編輯消息。',
              en: 'Strict encryption mode is blocked because server-side device key storage is not fully upgraded yet. Restart the latest backend service, then retry editing the message.',
            )
          : _chatServiceText(
              zhCN: '严格加密模式下，服务端设备密钥存储尚未升级完成。请重启最新后端服务后，再重新发送消息。',
              zhTW: '嚴格加密模式下，服務端設備密鑰存儲尚未升級完成。請重啟最新後端服務後，再重新發送消息。',
              en: 'Strict encryption mode is blocked because server-side device key storage is not fully upgraded yet. Restart the latest backend service, then send the message again.',
            );
    }
    if (message.contains('加密封装失败')) {
      return isEdit
          ? _chatServiceText(
              zhCN: '严格加密模式下，本次编辑的加密封装失败。请稍后重试，或重新进入会话后再试。',
              zhTW: '嚴格加密模式下，本次編輯的加密封裝失敗。請稍後重試，或重新進入會話後再試。',
              en: 'Strict encryption mode failed to package this encrypted edit. Try again later, or reopen the chat and retry.',
            )
          : _chatServiceText(
              zhCN: '严格加密模式下，本次消息加密封装失败。请稍后重试，或重新进入会话后再试。',
              zhTW: '嚴格加密模式下，本次消息加密封裝失敗。請稍後重試，或重新進入會話後再試。',
              en: 'Strict encryption mode failed to package this encrypted message. Try again later, or reopen the chat and retry.',
            );
    }
    if (_chatServiceContainsHan(message)) {
      return fallback;
    }
    return message;
  }

  String _localizeCryptoServerMessage(String message, {required bool isEdit}) {
    final normalized = message.trim();
    if (normalized.isEmpty) {
      return normalized;
    }
    if (normalized.contains('当前系统已关闭消息加密')) {
      return _chatServiceText(
        zhCN: '当前系统已关闭消息加密',
        zhTW: '當前系統已關閉消息加密',
        en: 'Message encryption is currently disabled in system settings.',
      );
    }
    if (normalized.contains('当前消息类型暂不支持发送')) {
      return _chatServiceText(
        zhCN: '严格加密模式下，当前消息类型暂不支持发送',
        zhTW: '嚴格加密模式下，當前消息類型暫不支持發送',
        en: 'Strict encryption mode does not support this message type yet.',
      );
    }
    if (normalized.contains('消息必须使用端到端加密发送')) {
      return _chatServiceText(
        zhCN: '严格加密模式下，当前消息必须使用端到端加密发送',
        zhTW: '嚴格加密模式下，當前消息必須使用端到端加密發送',
        en: 'Strict encryption mode requires end-to-end encryption for this message.',
      );
    }
    if (normalized.contains('编辑消息必须使用端到端加密')) {
      return _chatServiceText(
        zhCN: '严格加密模式下，编辑消息必须使用端到端加密',
        zhTW: '嚴格加密模式下，編輯消息必須使用端到端加密',
        en: 'Strict encryption mode requires end-to-end encryption to edit messages.',
      );
    }
    if (normalized.contains('没有可用的加密设备') ||
        normalized.contains('未升级到加密版本') ||
        normalized.contains('注册设备密钥失败') ||
        normalized.contains('保存设备公钥失败') ||
        normalized.contains('数据库未升级') ||
        normalized.contains('加密封装失败')) {
      return _strictCryptoFailureMessage(normalized, isEdit: isEdit);
    }
    return normalized;
  }

  ApiResponse<T> _localizeCryptoResponse<T>(
    ApiResponse<T> response, {
    required bool isEdit,
  }) {
    final localizedMessage = _localizeCryptoServerMessage(
      response.message,
      isEdit: isEdit,
    );
    if (localizedMessage == response.message) {
      return response;
    }
    return ApiResponse(
      code: response.code,
      message: localizedMessage,
      data: response.data,
    );
  }

  /// 获取会话列表（自动拉取全部页，避免只显示第一页）
  Future<ApiResponse<List<UserChat>>> getChatList({int pageSize = 100}) async {
    final allChats = <UserChat>[];
    final seenChatIds = <String>{};
    String? cursor;
    int page = 1;
    int guard = 0;

    while (true) {
      final response = await _api.get(
        '/chat/list',
        queryParameters: {
          'page_size': pageSize,
          if (cursor != null && cursor!.isNotEmpty)
            'cursor': cursor
          else
            'page': page,
        },
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

      final list = (response.data['list'] as List?)
              ?.map((e) => UserChat.fromJson(e))
              .toList() ??
          [];

      for (final chat in list) {
        if (chat.chatId.isEmpty || seenChatIds.contains(chat.chatId)) {
          continue;
        }
        seenChatIds.add(chat.chatId);
        allChats.add(chat);
      }

      final nextCursor = response.data['next_cursor']?.toString() ?? '';
      final hasMore = response.data['has_more'] == true;

      if (hasMore && nextCursor.isNotEmpty) {
        cursor = nextCursor;
      } else if (cursor != null && cursor!.isNotEmpty) {
        break;
      } else if (list.length >= pageSize) {
        page++;
      } else {
        break;
      }

      guard++;
      if (guard >= 50) break;
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
      final list = (response.data['list'] as List?)
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
    bool? allowAnonymous,
    bool? allowForward,
    bool? allowViewHistory,
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
        if (allowAnonymous != null) 'allow_anonymous': allowAnonymous,
        if (allowForward != null) 'allow_forward': allowForward,
        if (allowViewHistory != null) 'allow_view_history': allowViewHistory,
        if (memberProtection != null) 'member_protection': memberProtection,
      },
      fromJson: (data) => Chat.fromJson(data),
    );
  }

  /// 删除会话
  Future<ApiResponse> deleteChat(String chatId) async {
    return _api.delete('/chat/$chatId');
  }

  Future<ApiResponse> transferOwner(String chatId, String userId) async {
    return _api.put('/chat/$chatId/owner', data: {'user_id': userId});
  }

  Future<ApiResponse<MyChatPermissions>> getMyPermissions(String chatId) async {
    return _api.get(
      '/chat/$chatId/my-permissions',
      fromJson: (data) => MyChatPermissions.fromJson(data),
    );
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

  Future<ApiResponse> updateMemberNickname(
    String chatId,
    String userId,
    String nickname,
  ) async {
    return _api.put(
      '/chat/$chatId/members/$userId/nickname',
      data: {'nickname': nickname},
    );
  }

  Future<ApiResponse> setMemberRole(
    String chatId,
    String userId,
    int role, {
    ChatAdminPermissions? permissions,
  }) async {
    return _api.put(
      '/chat/$chatId/members/$userId/role',
      data: {
        'role': role,
        if (permissions != null) 'permissions': permissions.toJson(),
      },
    );
  }

  Future<ApiResponse<ChatAdminPermissions>> updateMemberPermissions(
    String chatId,
    String userId,
    ChatAdminPermissions permissions,
  ) async {
    return _api.put(
      '/chat/$chatId/members/$userId/permissions',
      data: permissions.toJson(),
      fromJson: (data) => ChatAdminPermissions.fromJson(
        (data['permissions'] as Map?)?.cast<String, dynamic>(),
      ),
    );
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

  Future<ApiResponse> clearGroupMessages(String chatId) async {
    return _api.post('/chat/$chatId/clear-messages');
  }

  /// 加入/订阅群组或频道
  Future<ApiResponse> joinChat(String chatId) async {
    return _api.post('/chat/$chatId/join');
  }

  /// 获取加入请求列表
  Future<ApiResponse<List<JoinRequest>>> getJoinRequests(String chatId) async {
    final response = await _api.get('/chat/$chatId/join-requests');
    if (response.isSuccess && response.data != null) {
      final list = (response.data['list'] as List?)
              ?.map((e) => JoinRequest.fromJson(e))
              .toList() ??
          [];
      return ApiResponse(code: 0, message: 'success', data: list);
    }
    return ApiResponse(
      code: response.code,
      message: response.message.isNotEmpty
          ? response.message
          : _chatServiceText(zhCN: '请求失败', zhTW: '請求失敗', en: 'Request failed.'),
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
  ///
  /// `beforeSeq` 面向向前翻页；返回结果是服务端历史窗口，不代表实时增量已经补齐。
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
  ///
  /// 调用方以本地已确认的最大 seq 为游标，并负责与乐观消息、缓存窗口去重合并。
  Future<ApiResponse<List<Message>>> syncMessages(
    String chatId, {
    required int lastSeq,
    int limit = 100,
  }) async {
    final response = await _api.post(
      '/message/sync',
      data: {'chat_id': chatId, 'last_seq': lastSeq, 'limit': limit},
    );

    if (response.isSuccess && response.data != null) {
      final messagesData =
          response.data is Map ? response.data['messages'] : response.data;
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
  ///
  /// 系统设置决定明文、兼容或严格加密；严格模式禁止静默降级，兼容模式才允许回退明文。
  Future<ApiResponse<Message>> sendMessage({
    required String chatId,
    required int type,
    required MessageContent content,
    String? msgId,
    ReplyInfo? replyTo,
    List<String>? mentions,
    bool burnAfterRead = false,
    int burnAfterSeconds = 0,
    bool anonymous = false,
    bool allowModeRetry = true,
  }) async {
    final contentJson = content.toJson();
    final mediaIds = _messageMediaIds(contentJson);
    final normalizedMentionPayload = normalizeMessageMentions(mentions);
    final mentionAll = normalizedMentionPayload.mentionAll;
    final normalizedMentions = normalizedMentionPayload.memberIds;
    final payload = <String, dynamic>{
      'chat_id': chatId,
      'type': type,
      if (msgId != null && msgId.isNotEmpty) 'msg_id': msgId,
      if (anonymous) 'anonymous': true,
      if (burnAfterRead) 'burn_after_read': true,
      if (burnAfterRead && burnAfterSeconds > 0)
        'burn_after_seconds': burnAfterSeconds,
      if (mentionAll) 'mention_all': true,
      if (mediaIds.isNotEmpty) 'media_ids': mediaIds,
    };

    final cryptoMode = await _loadMessageCryptoMode(forceRefresh: true);
    final supportsE2EE = _e2ee.supportsMessageType(type);
    if (cryptoMode.isPlain) {
      _attachPlainMessagePayload(
        payload,
        contentJson,
        replyTo: replyTo,
        mentions: normalizedMentions,
      );
    } else if (!supportsE2EE) {
      if (cryptoMode.isStrict) {
        return _cryptoModeError(
          _chatServiceText(
            zhCN: '严格加密模式下，当前消息类型暂不支持发送',
            zhTW: '嚴格加密模式下，當前消息類型暫不支持發送',
            en: 'Strict encryption mode does not support this message type yet.',
          ),
        );
      }
      _attachPlainMessagePayload(
        payload,
        contentJson,
        replyTo: replyTo,
        mentions: normalizedMentions,
      );
    } else {
      try {
        final encrypted = await _e2ee.encryptMessage(
          chatId: chatId,
          type: type,
          content: contentJson,
          replyTo: replyTo?.toJson(),
          mentions: normalizedMentions,
        );
        if (encrypted != null) {
          payload['e2ee'] = encrypted.payload.toJson();
        } else if (cryptoMode.isStrict) {
          return _cryptoModeError(
            _chatServiceText(
              zhCN: '严格加密模式下，当前消息必须使用端到端加密发送',
              zhTW: '嚴格加密模式下，當前消息必須使用端到端加密發送',
              en: 'Strict encryption mode requires end-to-end encryption for this message.',
            ),
          );
        } else {
          _attachPlainMessagePayload(
            payload,
            contentJson,
            replyTo: replyTo,
            mentions: normalizedMentions,
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
          mentions: normalizedMentions,
        );
      }
    }

    // 服务端响应才是 msgId、seq 和最终内容的权威确认，调用方据此替换本地乐观消息。
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
        anonymous: anonymous,
        allowModeRetry: false,
      );
    }
    final localizedResponse = _localizeCryptoResponse(response, isEdit: false);
    if (response.isSuccess && response.data != null && response.data is Map) {
      final parsed = await parseIncomingMessage(
        Map<String, dynamic>.from(response.data as Map),
      );
      return ApiResponse(
        code: localizedResponse.code,
        message: localizedResponse.message,
        data: parsed,
      );
    }

    return ApiResponse(
      code: localizedResponse.code,
      message: localizedResponse.message,
    );
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
    required String clientMsgId,
  }) async {
    return _api.post(
      '/message/forward',
      data: {
        'source_chat_id': sourceChatId,
        'source_msg_id': sourceMsgId,
        'target_chat_id': targetChatId,
        'client_msg_id': clientMsgId,
      },
      fromJson: (data) => Message.fromJson(data),
    );
  }

  /// 编辑消息
  Future<ApiResponse<Message>> forwardBundle({
    required String sourceChatId,
    required List<String> sourceMsgIds,
    required String targetChatId,
    required String clientMsgId,
  }) async {
    return _api.post(
      '/message/send',
      data: {
        'chat_id': targetChatId,
        'type': 14,
        'content': const <String, dynamic>{},
        'msg_id': clientMsgId,
        'source_chat_id': sourceChatId,
        'source_msg_ids': sourceMsgIds,
      },
      fromJson: (data) => Message.fromJson(data),
    );
  }

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
        return _cryptoModeError(
          _chatServiceText(
            zhCN: '严格加密模式下，编辑消息必须使用端到端加密',
            zhTW: '嚴格加密模式下，編輯消息必須使用端到端加密',
            en: 'Strict encryption mode requires end-to-end encryption to edit messages.',
          ),
        );
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
    return _localizeCryptoResponse(response, isEdit: true);
  }

  Future<ApiResponse> editImageMessage(
    String chatId,
    String msgId,
    MediaInfo media,
  ) async {
    return _api.post(
      '/message/edit',
      data: {
        'chat_id': chatId,
        'msg_id': msgId,
        'media': media.toJson(),
      },
    );
  }

  Future<ApiResponse<MessageTranslationResult>> translateMessage({
    required String chatId,
    String? msgId,
    String? text,
    String? targetLang,
    String? sourceLang,
  }) async {
    return _api.post(
      '/message/translate',
      data: {
        'chat_id': chatId,
        if (msgId != null && msgId.trim().isNotEmpty) 'msg_id': msgId.trim(),
        if (text != null && text.trim().isNotEmpty) 'text': text.trim(),
        if (targetLang != null && targetLang.trim().isNotEmpty)
          'target_lang': targetLang.trim(),
        if (sourceLang != null && sourceLang.trim().isNotEmpty)
          'source_lang': sourceLang.trim(),
      },
      fromJson: (data) => MessageTranslationResult.fromJson(
        Map<String, dynamic>.from(data as Map),
      ),
    );
  }

  /// 标记消息已读 (清除未读计数)
  Future<ApiResponse> markAsRead(String chatId, {int? msgSeq}) async {
    return _api.post(
      '/message/read',
      data: {'chat_id': chatId, if (msgSeq != null) 'msg_seq': msgSeq},
    );
  }

  /// 确认消息已实时送达到当前设备（不等同于打开会话已读）。
  Future<ApiResponse> markAsDelivered(String chatId, {required int msgSeq}) {
    return _api.post(
      '/message/delivered',
      data: {'chat_id': chatId, 'msg_seq': msgSeq},
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
    String keyword, {
    String? senderId,
    int? messageType,
    DateTime? startAt,
    DateTime? endAt,
  }) async {
    final response = await _api.get(
      '/chat/$chatId/search',
      queryParameters: {
        if (keyword.trim().isNotEmpty) 'keyword': keyword.trim(),
        if (senderId?.isNotEmpty == true) 'sender_id': senderId,
        if (messageType != null) 'message_type': messageType,
        if (startAt != null) 'start_at': startAt.toUtc().toIso8601String(),
        if (endAt != null) 'end_at': endAt.toUtc().toIso8601String(),
      },
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

  Future<ApiResponse<GlobalSearchResult>> globalSearch(
    String keyword, {
    String scope = 'all',
    int limit = 8,
    int page = 1,
  }) async {
    final response = await _api.get(
      '/search/global',
      queryParameters: {
        'keyword': keyword,
        'scope': scope,
        'limit': limit.toString(),
        'page': page.toString(),
      },
    );

    if (response.isSuccess && response.data != null) {
      return ApiResponse(
        code: 0,
        message: response.message,
        data: GlobalSearchResult.fromJson(response.data),
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

  Future<ApiResponse> acknowledgeAnnouncement(
    String chatId,
    int announcementId,
  ) async {
    return _api.post(
      '/chat/$chatId/announcements/$announcementId/acknowledge',
    );
  }

  Future<ApiResponse<List<ChatAutoMessage>>> getAutoMessages(
    String chatId,
  ) async {
    final response = await _api.get('/chat/$chatId/auto-messages');
    if (response.isSuccess && response.data != null) {
      final raw = response.data is List ? response.data as List : const [];
      return ApiResponse(
        code: response.code,
        message: response.message,
        data: raw.map((e) => ChatAutoMessage.fromJson(e)).toList(),
      );
    }
    return ApiResponse(code: response.code, message: response.message);
  }

  Future<ApiResponse<ChatAutoMessage>> createAutoMessage(
    String chatId,
    ChatAutoMessagePayload payload,
  ) async {
    return _api.post(
      '/chat/$chatId/auto-messages',
      data: payload.toJson(),
      fromJson: (data) => ChatAutoMessage.fromJson(data),
    );
  }

  Future<ApiResponse<ChatAutoMessage>> updateAutoMessage(
    String chatId,
    int autoMessageId,
    ChatAutoMessagePayload payload,
  ) async {
    return _api.put(
      '/chat/$chatId/auto-messages/$autoMessageId',
      data: payload.toJson(),
      fromJson: (data) => ChatAutoMessage.fromJson(data),
    );
  }

  Future<ApiResponse> deleteAutoMessage(
    String chatId,
    int autoMessageId,
  ) async {
    return _api.delete('/chat/$chatId/auto-messages/$autoMessageId');
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
      list: (json['list'] as List?)
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
      list: (json['list'] as List?)
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
  final int seq;
  final String chatId;
  final String senderId;
  final String? senderName;
  final String? senderAvatar;
  final int type;
  final Map<String, dynamic> content;
  final DateTime createdAt;

  SearchMessageItem({
    required this.id,
    required this.seq,
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
    return SearchMessageItem(
      id: json['id']?.toString() ?? '',
      seq: (json['seq'] as num?)?.toInt() ?? 0,
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

  /// 获取适合搜索结果列表展示的内容摘要。
  String get text {
    final value = content['text']?.toString() ?? '';
    if (value.isNotEmpty) return value;
    switch (type) {
      case 2:
        return _chatServiceText(zhCN: '[图片]', zhTW: '[圖片]', en: '[Image]');
      case 3:
        return _chatServiceText(zhCN: '[视频]', zhTW: '[影片]', en: '[Video]');
      case 4:
        final transcript =
            (content['voice'] as Map?)?['transcript']?.toString() ?? '';
        return transcript.isNotEmpty
            ? transcript
            : _chatServiceText(zhCN: '[语音]', zhTW: '[語音]', en: '[Voice]');
      case 5:
        return (content['file'] as Map?)?['name']?.toString() ??
            _chatServiceText(zhCN: '[文件]', zhTW: '[檔案]', en: '[File]');
      case 6:
        return (content['location'] as Map?)?['title']?.toString() ??
            _chatServiceText(zhCN: '[位置]', zhTW: '[位置]', en: '[Location]');
      case 8:
        return _chatServiceText(zhCN: '[贴纸]', zhTW: '[貼圖]', en: '[Sticker]');
      case 10:
        return (content['contact'] as Map?)?['nickname']?.toString() ??
            _chatServiceText(zhCN: '[联系人]', zhTW: '[聯絡人]', en: '[Contact]');
      case 11:
        return _chatServiceText(zhCN: '[通话]', zhTW: '[通話]', en: '[Call]');
      case 14:
        return (content['forward_bundle'] as Map?)?['title']?.toString() ??
            _chatServiceText(
                zhCN: '[聊天记录]', zhTW: '[聊天記錄]', en: '[Chat history]');
      case 99:
        return _chatServiceText(
            zhCN: '[系统消息]', zhTW: '[系統訊息]', en: '[System message]');
      default:
        return _chatServiceText(zhCN: '[消息]', zhTW: '[訊息]', en: '[Message]');
    }
  }
}

class GlobalSearchResult {
  final String keyword;
  final int page;
  final int limit;
  final Map<String, bool> hasMore;
  final List<GlobalSearchItem> contacts;
  final List<GlobalSearchItem> chats;
  final List<GlobalSearchItem> messages;
  final List<GlobalSearchItem> files;

  GlobalSearchResult({
    required this.keyword,
    this.page = 1,
    this.limit = 8,
    this.hasMore = const {},
    required this.contacts,
    required this.chats,
    required this.messages,
    required this.files,
  });

  factory GlobalSearchResult.fromJson(Map<String, dynamic> json) {
    List<GlobalSearchItem> parseList(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => GlobalSearchItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    Map<String, bool> parseHasMore() {
      final raw = json['has_more'];
      if (raw is! Map) return const {};
      return raw.map((key, value) => MapEntry(key.toString(), value == true));
    }

    return GlobalSearchResult(
      keyword: json['keyword']?.toString() ?? '',
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 8,
      hasMore: parseHasMore(),
      contacts: parseList('contacts'),
      chats: parseList('chats'),
      messages: parseList('messages'),
      files: parseList('files'),
    );
  }
}

class GlobalSearchItem {
  final String id;
  final String type;
  final String title;
  final String subtitle;
  final String? avatar;
  final String? chatId;
  final String? chatName;
  final int? chatType;
  final String? messageId;
  final int? seq;
  final Map<String, dynamic> content;
  final DateTime? createdAt;
  final String? mimeType;
  final int? size;
  final String? url;
  final String? highlightText;
  final int? highlightStart;
  final int? highlightEnd;
  final String? nicknameColor;
  final String? emojiAvatar;
  final int vipLevel;
  final String vipBadge;
  final String vipBadgeIcon;
  final bool vipActive;

  GlobalSearchItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    this.avatar,
    this.chatId,
    this.chatName,
    this.chatType,
    this.messageId,
    this.seq,
    this.content = const {},
    this.createdAt,
    this.mimeType,
    this.size,
    this.url,
    this.highlightText,
    this.highlightStart,
    this.highlightEnd,
    this.nicknameColor,
    this.emojiAvatar,
    this.vipLevel = 0,
    this.vipBadge = '',
    this.vipBadgeIcon = '',
    this.vipActive = false,
  });

  factory GlobalSearchItem.fromJson(Map<String, dynamic> json) {
    final avatar = ApiConfig.getMediaUrl(json['avatar']?.toString());
    final rawContent = json['content'];
    final rawHighlight = json['highlight'];
    final highlight = rawHighlight is Map
        ? Map<String, dynamic>.from(rawHighlight)
        : const <String, dynamic>{};
    final rawVip = json['vip'];
    final vip = rawVip is Map
        ? Map<String, dynamic>.from(rawVip)
        : const <String, dynamic>{};
    final title = _cleanGlobalSearchDisplayText(json['title']?.toString());
    final subtitle = _cleanGlobalSearchDisplayText(
      json['subtitle']?.toString(),
    );
    final highlightText = _cleanGlobalSearchDisplayText(
      highlight['text']?.toString(),
    );
    return GlobalSearchItem(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      title: title,
      subtitle: subtitle,
      avatar: avatar.isEmpty ? null : avatar,
      chatId: json['chat_id']?.toString(),
      chatName: json['chat_name']?.toString(),
      chatType: (json['chat_type'] as num?)?.toInt(),
      messageId: json['message_id']?.toString(),
      seq: (json['seq'] as num?)?.toInt(),
      content:
          rawContent is Map ? Map<String, dynamic>.from(rawContent) : const {},
      createdAt: DateTime.tryParse(
        json['created_at']?.toString() ?? '',
      )?.toLocal(),
      mimeType: json['mime_type']?.toString(),
      size: (json['size'] as num?)?.toInt(),
      url: json['url']?.toString(),
      highlightText: highlightText.isEmpty ? null : highlightText,
      highlightStart: (highlight['start'] as num?)?.toInt(),
      highlightEnd: (highlight['end'] as num?)?.toInt(),
      nicknameColor: json['nickname_color']?.toString(),
      emojiAvatar: json['emoji_avatar']?.toString(),
      vipLevel: int.tryParse(vip['level']?.toString() ?? '') ?? 0,
      vipBadge: vip['badge']?.toString() ?? '',
      vipBadgeIcon: _parseVipBadgeIcon(vip['badge_icon']),
      vipActive: vip['is_active'] == true,
    );
  }

  bool get vipVisible => vipActive && vipLevel > 0;

  String get text {
    final direct = content['text']?.toString() ?? '';
    if (direct.isNotEmpty) return direct;
    final file = content['file'];
    if (file is Map) {
      return file['name']?.toString() ?? '';
    }
    return '';
  }
}

String _cleanGlobalSearchDisplayText(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty || _isGlobalSearchInternalEmojiValue(text)) {
    return '';
  }
  return text;
}

bool _isGlobalSearchInternalEmojiValue(String value) {
  final text = value.trim();
  return text.startsWith('__custom_emoji__:') ||
      text.startsWith('__custom_emoji_url__:');
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
      list: (json['list'] as List?)
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
  final bool acknowledged;
  final int acknowledgedCount;
  final int memberCount;

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
    this.acknowledged = false,
    this.acknowledgedCount = 0,
    this.memberCount = 0,
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
      acknowledged: json['acknowledged'] == true,
      acknowledgedCount: (json['acknowledged_count'] as num?)?.toInt() ?? 0,
      memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class ChatAutoMessage {
  final int id;
  final int chatId;
  final String title;
  final String content;
  final int messageType;
  final Map<String, dynamic> media;
  final String scheduleType;
  final int intervalSeconds;
  final DateTime? sendAt;
  final String dailyTime;
  final DateTime? nextRunAt;
  final DateTime? lastRunAt;
  final bool enabled;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  ChatAutoMessage({
    required this.id,
    required this.chatId,
    required this.title,
    required this.content,
    this.messageType = 1,
    this.media = const {},
    required this.scheduleType,
    required this.intervalSeconds,
    this.sendAt,
    required this.dailyTime,
    this.nextRunAt,
    this.lastRunAt,
    required this.enabled,
    this.createdAt,
    this.updatedAt,
  });

  factory ChatAutoMessage.fromJson(dynamic raw) {
    final json = raw is Map ? Map<String, dynamic>.from(raw) : {};
    return ChatAutoMessage(
      id: int.tryParse(json['id']?.toString() ?? '') ?? 0,
      chatId: int.tryParse(json['chat_id']?.toString() ?? '') ?? 0,
      title: json['title']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      messageType: int.tryParse(json['message_type']?.toString() ?? '') ?? 1,
      media: json['media'] is Map
          ? Map<String, dynamic>.from(json['media'] as Map)
          : const {},
      scheduleType: json['schedule_type']?.toString() ?? 'once',
      intervalSeconds:
          int.tryParse(json['interval_seconds']?.toString() ?? '') ?? 0,
      sendAt: _parseOptionalServerDateTime(json['send_at']),
      dailyTime: json['daily_time']?.toString() ?? '',
      nextRunAt: _parseOptionalServerDateTime(json['next_run_at']),
      lastRunAt: _parseOptionalServerDateTime(json['last_run_at']),
      enabled: json['enabled'] != false,
      createdAt: _parseOptionalServerDateTime(json['created_at']),
      updatedAt: _parseOptionalServerDateTime(json['updated_at']),
    );
  }
}

class ChatAutoMessagePayload {
  final String? title;
  final String? content;
  final int? messageType;
  final Map<String, dynamic>? media;
  final String? scheduleType;
  final int? intervalMinutes;
  final int? intervalSeconds;
  final DateTime? sendAt;
  final String? dailyTime;
  final bool? enabled;

  const ChatAutoMessagePayload({
    this.title,
    this.content,
    this.messageType,
    this.media,
    this.scheduleType,
    this.intervalMinutes,
    this.intervalSeconds,
    this.sendAt,
    this.dailyTime,
    this.enabled,
  });

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (content != null) 'content': content,
        if (messageType != null) 'message_type': messageType,
        if (media != null) 'media': media,
        if (scheduleType != null) 'schedule_type': scheduleType,
        if (intervalMinutes != null) 'interval_minutes': intervalMinutes,
        if (intervalSeconds != null) 'interval_seconds': intervalSeconds,
        if (sendAt != null) 'send_at': sendAt!.toUtc().toIso8601String(),
        if (dailyTime != null) 'daily_time': dailyTime,
        if (enabled != null) 'enabled': enabled,
      };
}

/// Provider
final chatServiceProvider = Provider<ChatService>((ref) {
  final api = ref.watch(apiClientProvider);
  final ws = ref.watch(webSocketServiceProvider.notifier);
  final e2ee = ref.watch(e2eeServiceProvider);
  final systemSettings = ref.watch(systemSettingsServiceProvider);
  return ChatService(api, ws, e2ee, systemSettings);
});
