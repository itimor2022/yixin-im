import 'package:isar/isar.dart';

import '../../../../core/utils/isar_utils.dart';

part 'chat_model.g.dart';

@collection
class ChatModel {
  Id get isarId => fastHash(id);
  
  /// 聊天唯一标识
  @Index(unique: true)
  late String id;
  
  /// 聊天类型：private, group, channel
  @enumerated
  late ChatType type;
  
  /// 聊天名称（私聊为对方名称，群聊为群名）
  late String name;
  
  /// 头像
  late String? avatar;
  
  /// 最后一条消息内容
  late String? lastMessage;
  
  /// 最后一条消息类型
  @enumerated
  late MessageType lastMessageType;
  
  /// 最后一条消息发送者名称
  late String? lastMessageSender;
  
  /// 最后消息时间
  @Index()
  late DateTime? lastMessageTime;
  
  /// 未读消息数
  late int unreadCount;
  
  /// 是否静音
  late bool isMuted;
  
  /// 是否置顶
  @Index()
  late bool isPinned;
  
  /// 是否归档
  late bool isArchived;
  
  /// 草稿
  late String? draft;
  
  /// 群组成员数（仅群聊/频道）
  late int? memberCount;
  
  /// 私聊对方用户 ID
  late String? peerUserId;

  /// 会员类型
  late String? premiumType;

  /// 是否会员（私聊对方）
  late bool? isMember;

  /// 徽章文字
  late String? badgeText;

  /// 徽章颜色
  late String? badgeColor;

  /// 昵称颜色（私聊对方）
  late String? nicknameColor;
  
  /// 创建时间
  late DateTime createdAt;
  
  /// 更新时间
  @Index()
  late DateTime updatedAt;

  ChatModel() {
    type = ChatType.private;
    lastMessageType = MessageType.text;
    unreadCount = 0;
    isMuted = false;
    isPinned = false;
    isArchived = false;
    createdAt = DateTime.now();
    updatedAt = DateTime.now();
  }
}

enum ChatType {
  private,  // 私聊
  group,    // 群组
  channel,  // 频道
}

enum MessageType {
  text,
  image,
  video,
  audio,
  voice,
  file,
  sticker,
  location,
  contact,
  system,
  call,  // 通话记录
}

// fastHash 已移至 lib/core/utils/isar_utils.dart
