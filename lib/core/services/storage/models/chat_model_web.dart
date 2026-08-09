// 文件用途：提供 chat model 在 Web 平台的实现，服务于业务服务。
// 核心逻辑：实现 ChatModel 的 Web 平台分支，适配浏览器 API 和资源生命周期，并保持与原生实现相同的调用契约。
import 'package:isar/isar.dart';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。

// 关键声明：chat model web 是 Web 平台实现，负责把浏览器资源和异步生命周期适配为跨平台接口。
/// Web 端的字段兼容模型，不提供 Isar 持久化。
///
/// 字段、默认值和枚举顺序必须与原生 ChatModel 同步，保证共享业务代码行为一致。
class ChatModel {
  // Web 没有 Isar 主键，0 仅为满足共享接口的哨兵值。
  int get isarId => 0;

  late String accountId;
  late String id;
  late ChatType type;
  late String name;
  late String? avatar;
  late String? lastMessage;
  late MessageType lastMessageType;
  late String? lastMessageSender;
  late String? lastMessageMediaUrl;
  late DateTime? lastMessageTime;
  late bool lastMessageFailed;
  late int unreadCount;
  late bool hasMention;
  late bool isMuted;
  late bool isPinned;
  late bool isArchived;
  late String? draft;
  late int? memberCount;
  late String? peerUserId;
  late int lastMessageSeq;
  late int lastSyncedSeq;
  late DateTime? lastSyncedAt;
  late bool hasMessageGap;
  late DateTime createdAt;
  late DateTime updatedAt;

  ChatModel() {
    accountId = '';
    id = '';
    type = ChatType.private;
    name = '';
    lastMessageType = MessageType.text;
    lastMessageFailed = false;
    unreadCount = 0;
    hasMention = false;
    isMuted = false;
    isPinned = false;
    isArchived = false;
    lastMessageSeq = 0;
    lastSyncedSeq = 0;
    hasMessageGap = false;
    createdAt = DateTime.now();
    updatedAt = DateTime.now();
  }
}

// 与原生枚举保持相同顺序；共享代码可能按 values 下标解释旧数据。
enum ChatType {
  private,
  group,
  channel,
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
  call,
}

extension GetChatModelCollection on Isar {
  // Web 若误走原生缓存路径应立即失败，不能静默返回空数据掩盖调用错误。
  dynamic get chatModels => throw UnsupportedError(
        'Isar chat storage is not available on web.',
      );
}
