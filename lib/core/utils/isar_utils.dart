// 文件用途：提供 isar utils 相关工具函数与通用转换逻辑，属于通用工具。
// 核心逻辑：提供 isar utils 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
/// Isar 通用工具函数

// 关键声明：isar utils 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
// 流程逻辑：`fastHash` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
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
