// 文件用途：定义 ChatModel 相关数据结构、字段转换与持久化模型，属于业务服务。
// 核心逻辑：定义 ChatModel 的字段、默认值和序列化边界，保持服务端响应、内存对象与本地持久化格式一致。
import 'package:isar/isar.dart';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。

import '../../../../core/utils/isar_utils.dart';

part 'chat_model.g.dart';

// 关键声明：chat model 定义数据转换边界，负责默认值、空值兼容和 JSON/本地存储之间的双向映射。
@collection
class ChatModel {
  // 本地主键同时包含账号和会话 ID；同一 chatId 在多账号下必须落为不同记录。
  Id get isarId => fastHash('$accountId:$id');

  /// 聊天唯一标识
  @Index(composite: [CompositeIndex('id')], unique: true)
  late String accountId;

  @Index()
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

  /// 最后一条媒体消息缩略图或原图 URL
  late String? lastMessageMediaUrl;

  /// 最后消息时间
  @Index()
  late DateTime? lastMessageTime;

  /// 本地最后一条消息是否发送失败
  late bool lastMessageFailed;

  /// 未读消息数
  late int unreadCount;

  /// 是否有尚未读到的 @ 提醒
  late bool hasMention;

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

  /// 服务端已知的最后消息序号。
  late int lastMessageSeq;

  /// 本地已经连续同步完成的消息序号。
  late int lastSyncedSeq;

  late DateTime? lastSyncedAt;

  /// 两个序号之间存在缺口时置为 true，读取缓存后应触发补拉而非假定历史完整。
  late bool hasMessageGap;

  /// 创建时间
  late DateTime createdAt;

  /// 更新时间
  @Index()
  late DateTime updatedAt;

  ChatModel() {
    accountId = '';
    type = ChatType.private;
    lastMessageType = MessageType.text;
    lastMessageFailed = false;
    unreadCount = 0;
    hasMention = false;
    isMuted = false;
    isPinned = false;
    isArchived = false;
    lastMessageSeq = 0;
    lastSyncedSeq = 0;
    lastSyncedAt = null;
    hasMessageGap = false;
    createdAt = DateTime.now();
    updatedAt = DateTime.now();
  }
}

// @enumerated 按序号持久化：已有值禁止重排或插入，新类型只能追加到末尾。
enum ChatType {
  private, // 私聊
  group, // 群组
  channel, // 频道
}

// 该顺序还需与 chat_model_web.dart 保持一致，避免条件导入后的类型语义分叉。
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
  call, // 通话记录
}

// fastHash 已移至 lib/core/utils/isar_utils.dart
