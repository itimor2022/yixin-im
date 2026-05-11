import 'package:isar/isar.dart';

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

  /// 由 main.dart 在 Isar.open() 成功后调用一次
  void setIsar(Isar isar) {
    _isar = isar;
  }

  /// Isar 实例是否已初始化（Web 端始终为 false）
  bool get isAvailable => _isar != null;

  /// 获取 Isar 实例；未初始化时抛出 [StateError]
  Isar get isar {
    final db = _isar;
    if (db == null) {
      throw StateError(
        'Isar 尚未初始化。请先确认 IsarService.instance.setIsar() 已在 main() 中被调用。',
      );
    }
    return db;
  }
}
