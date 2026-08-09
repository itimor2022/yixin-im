// 文件用途：提供 phone validation 相关工具函数与通用转换逻辑，属于通用工具。
// 核心逻辑：提供 phone validation 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
// 关键声明：phone validation 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
// 流程逻辑：`isValidMainlandChinaMobile` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
/// Returns whether [input] is a mainland China mobile number.
///
/// The current public mobile prefixes start with 13 through 19. Formatting
/// such as spaces or a country code is intentionally rejected at UI entry
/// points so the client sends the same canonical 11-digit value as the API.
bool isValidMainlandChinaMobile(String input) {
  return RegExp(r'^1[3-9]\d{9}$').hasMatch(input.trim());
}
