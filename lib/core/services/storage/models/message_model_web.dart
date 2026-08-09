// 文件用途：提供 message model 在 Web 平台的实现，服务于业务服务。
// 核心逻辑：实现 MessageModel 的 Web 平台分支，适配浏览器 API 和资源生命周期，并保持与原生实现相同的调用契约。
import 'package:isar/isar.dart';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。

// 关键声明：message model web 是 Web 平台实现，负责把浏览器资源和异步生命周期适配为跨平台接口。
class MessageModel {
  int get isarId => 0;

  late String accountId;
  late String id;
  late String chatId;
  late String senderId;
  late String senderName;
  late String? senderAvatar;
  late String? senderNicknameColor;
  late String? senderEmojiAvatar;
  late MsgType type;
  late String content;
  late int seq;
  late String? localPath;
  late String? remoteUrl;
  late String? mediaId;
  late String? thumbnail;
  late String? thumbnailMediaId;
  late int? mediaWidth;
  late int? mediaHeight;
  late int? mediaSize;
  late int? mediaDuration;
  late String? fileName;
  late bool isOutgoing;
  late MsgStatus status;
  late bool isRead;
  late String? replyToId;
  late String? replyToPreview;
  late String? forwardFrom;
  late String? reactions;
  late String? contactUserId;
  late String? contactName;
  late String? contactAvatar;
  late String? contactUsername;
  late DateTime createdAt;
  late DateTime cachedAt;
  late DateTime? editedAt;
  late bool isDeleted;
  late bool burnAfterRead;
  late int burnAfterSeconds;

  MessageModel() {
    accountId = '';
    id = '';
    chatId = '';
    senderId = '';
    senderName = '';
    type = MsgType.text;
    content = '';
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

enum MsgStatus {
  sending,
  sent,
  delivered,
  read,
  failed,
}

extension GetMessageModelCollection on Isar {
  dynamic get messageModels => throw UnsupportedError(
        'Isar message storage is not available on web.',
      );
}
