// 文件用途：定义 MessageModel 相关数据结构、字段转换与持久化模型，属于业务服务。
// 核心逻辑：定义 MessageModel 的字段、默认值和序列化边界，保持服务端响应、内存对象与本地持久化格式一致。
import 'package:isar/isar.dart';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。

import '../../../../core/utils/isar_utils.dart';

part 'message_model.g.dart';

// 关键声明：message model 定义数据转换边界，负责默认值、空值兼容和 JSON/本地存储之间的双向映射。
@collection
class MessageModel {
  Id get isarId => fastHash('$accountId:$id');

  /// 消息唯一标识
  @Index(composite: [CompositeIndex('id')], unique: true)
  late String accountId;

  @Index()
  late String id;

  /// 所属聊天 ID（复合索引加速按聊天+时间查询）
  @Index(composite: [CompositeIndex('createdAt')])
  late String chatId;

  /// 发送者 ID
  @Index()
  late String senderId;

  /// 发送者名称
  late String senderName;

  /// 发送者头像
  late String? senderAvatar;

  /// 发送者昵称颜色
  late String? senderNicknameColor;

  /// 发送者表情状态
  late String? senderEmojiAvatar;

  /// 消息类型
  @enumerated
  late MsgType type;

  /// 消息内容（文本消息为文本，其他为 JSON 元数据）
  late String content;

  /// 消息序列号（用于分页游标和增量同步）
  late int seq;

  /// 媒体文件本地路径
  late String? localPath;

  /// 媒体文件远程 URL
  late String? remoteUrl;

  /// 私密媒体对象 ID，用于刷新短期签名 URL
  late String? mediaId;

  /// 媒体文件缩略图
  late String? thumbnail;

  /// 私密缩略图对象 ID，用于刷新短期签名 URL
  late String? thumbnailMediaId;

  /// 媒体文件宽度
  late int? mediaWidth;

  /// 媒体文件高度
  late int? mediaHeight;

  /// 媒体文件大小（字节）
  late int? mediaSize;

  /// 媒体文件时长（秒，音视频）
  late int? mediaDuration;

  /// 文件名（文件消息）
  late String? fileName;

  /// 是否为自己发送
  late bool isOutgoing;

  /// 消息状态
  @enumerated
  late MsgStatus status;

  /// 是否已读
  late bool isRead;

  /// 回复的消息 ID
  late String? replyToId;

  /// 回复的消息内容预览
  late String? replyToPreview;

  /// 转发来源
  late String? forwardFrom;

  /// 表情回复（JSON 数组字符串）
  late String? reactions;

  /// 名片消息 — 联系人用户 ID
  late String? contactUserId;

  /// 名片消息 — 联系人名称
  late String? contactName;

  /// 名片消息 — 联系人头像
  late String? contactAvatar;

  /// 名片消息 — 联系人用户名
  late String? contactUsername;

  /// 发送时间
  @Index()
  late DateTime createdAt;

  late DateTime cachedAt;

  /// 编辑时间
  late DateTime? editedAt;

  /// 是否已删除
  late bool isDeleted;

  /// 阅后即焚
  late bool burnAfterRead;

  /// 阅后即焚倒计时秒数
  late int burnAfterSeconds;

  MessageModel() {
    accountId = '';
    type = MsgType.text;
    isOutgoing = true;
    status = MsgStatus.sending;
    isRead = false;
    isDeleted = false;
    burnAfterRead = false;
    burnAfterSeconds = 0;
    seq = 0;
    createdAt = DateTime.now();
    cachedAt = DateTime.now();
  }
}

enum MsgType {
  text, // 文本
  image, // 图片
  video, // 视频
  audio, // 音频（音乐）
  voice, // 语音
  file, // 文件
  sticker, // 贴纸
  gif, // GIF
  location, // 位置
  contact, // 联系人名片
  poll, // 投票
  system, // 系统消息
  call, // 通话记录
  redPacket, // 红包
  transfer, // 转账
}

enum MsgStatus {
  sending, // 发送中
  sent, // 已发送
  delivered, // 已送达
  read, // 已读
  failed, // 发送失败
}

// fastHash 已移至 lib/core/utils/isar_utils.dart
