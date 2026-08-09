// 文件用途：提供 user model 在 Web 平台的实现，服务于业务服务。
// 核心逻辑：实现 UserModel 的 Web 平台分支，适配浏览器 API 和资源生命周期，并保持与原生实现相同的调用契约。
import 'package:isar/isar.dart';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。

// 关键声明：user model web 是 Web 平台实现，负责把浏览器资源和异步生命周期适配为跨平台接口。
class UserModel {
  int get isarId => 0;

  late String accountId;

  late String id;
  late String username;
  late String? nickname;
  late String? phone;
  late String? avatar;
  late String? bio;
  late String? nicknameColor;
  late String? emojiAvatar;
  late bool isOnline;
  late DateTime? lastSeen;
  late bool isContact;
  late bool isBlocked;
  late DateTime createdAt;
  late DateTime updatedAt;

  UserModel() {
    accountId = '';
    id = '';
    username = '';
    isOnline = false;
    isContact = false;
    isBlocked = false;
    createdAt = DateTime.now();
    updatedAt = DateTime.now();
  }
}

extension GetUserModelCollection on Isar {
  dynamic get userModels => throw UnsupportedError(
        'Isar user storage is not available on web.',
      );
}
