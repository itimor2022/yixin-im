/// Isar 通用工具函数

/// FNV-1a 快速哈希（用于将字符串 ID 转为 Isar int 主键）
///
/// 注意：此函数被三个数据模型共用，请勿在各模型中单独重复定义。
int fastHash(String string) {
  var hash = 0x811c9dc5;
  var i = 0;
  while (i < string.length) {
    final codeUnit = string.codeUnitAt(i++);
    hash ^= codeUnit >> 8;
    hash *= 0x100000001b3;
    hash ^= codeUnit & 0xFF;
    hash *= 0x100000001b3;
  }
  return hash;
}
