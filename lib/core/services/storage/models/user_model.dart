// 文件用途：定义 UserModel 相关数据结构、字段转换与持久化模型，属于业务服务。
// 核心逻辑：定义 UserModel 的字段、默认值和序列化边界，保持服务端响应、内存对象与本地持久化格式一致。
import 'package:isar/isar.dart';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。

import '../../../../core/utils/isar_utils.dart';

part 'user_model.g.dart';

// 关键声明：user model 定义数据转换边界，负责默认值、空值兼容和 JSON/本地存储之间的双向映射。
@collection
class UserModel {
  Id get isarId => fastHash('$accountId:$id');

  /// 缓存所属账号 UUID
  @Index(composite: [CompositeIndex('id')], unique: true)
  late String accountId;

  /// 用户唯一标识
  @Index()
  late String id;

  /// 用户名
  @Index()
  late String username;

  /// 昵称
  late String? nickname;

  /// 手机号
  @Index()
  late String? phone;

  /// 头像 URL
  late String? avatar;

  /// 个性签名
  late String? bio;

  /// 昵称颜色
  late String? nicknameColor;

  /// 表情状态
  late String? emojiAvatar;

  /// 是否在线
  late bool isOnline;

  /// 最后在线时间
  late DateTime? lastSeen;

  /// 是否为联系人
  late bool isContact;

  /// 是否被屏蔽
  late bool isBlocked;

  /// 创建时间
  late DateTime createdAt;

  /// 更新时间
  late DateTime updatedAt;

  UserModel() {
    accountId = '';
    isOnline = false;
    isContact = false;
    isBlocked = false;
    createdAt = DateTime.now();
    updatedAt = DateTime.now();
  }
}

// fastHash 已移至 lib/core/utils/isar_utils.dart
