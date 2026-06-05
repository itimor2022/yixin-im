import 'package:isar/isar.dart';

import '../../../../core/utils/isar_utils.dart';

part 'user_model.g.dart';

@collection
class UserModel {
  Id get isarId => fastHash(id);
  
  /// 用户唯一标识
  @Index(unique: true)
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

  /// 会员类型
  late String? premiumType;

  /// 是否会员
  late bool isMember;

  /// 徽章文字
  late String? badgeText;

  /// 徽章颜色
  late String? badgeColor;
  
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
    isOnline = false;
    isContact = false;
    isBlocked = false;
    isMember = false;
    badgeText = null;
    badgeColor = null;
    createdAt = DateTime.now();
    updatedAt = DateTime.now();
  }
}

// fastHash 已移至 lib/core/utils/isar_utils.dart
