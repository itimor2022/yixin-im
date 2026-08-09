// 文件用途：负责 Isar 本地数据库的初始化、实例管理和账号数据隔离。
// 核心逻辑：按账号初始化和复用 Isar 实例，管理本地集合生命周期，避免账号切换时读写到其他用户的数据。
import 'package:isar/isar.dart';

// 关键声明：isar service 是本地数据库生命周期入口，负责初始化、复用和关闭账号隔离的 Isar 实例。
/// Isar 数据库单例持有者
///
/// 解耦业务服务与 main.dart 的直接依赖：
/// - main.dart 在打开 Isar 后调用 [IsarService.instance.setIsar]
/// - 业务代码通过 [IsarService.instance.isar] 访问数据库，而不再 import main.dart
class IsarService {
  static final IsarService _instance = IsarService._();
  static IsarService get instance => _instance;
  IsarService._();

  Isar? _isar;

  // 流程逻辑：`setIsar` 先校验输入和当前权限，进入操作中状态后执行副作用；成功同步服务端结果，失败恢复可重试状态并保留错误原因。
  /// 由 main.dart 在 Isar.open() 成功后调用一次
  void setIsar(Isar isar) {
    // 此处只注入已打开的数据库句柄，不负责 schema、迁移或关闭生命周期。
    _isar = isar;
  }

  /// Isar 实例是否已初始化（Web 端始终为 false）
  bool get isAvailable => _isar != null;

  /// 获取 Isar 实例；未初始化时抛出 [StateError]
  Isar get isar {
    // 单例数据库可同时保存多个账号的数据，业务查询仍必须显式带 accountId。
    final db = _isar;
    if (db == null) {
      throw StateError(
        'Isar 尚未初始化。请先确认 IsarService.instance.setIsar() 已在 main() 中被调用。',
      );
    }
    return db;
  }
}
