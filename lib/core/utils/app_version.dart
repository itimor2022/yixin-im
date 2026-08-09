// 文件用途：提供 app version 相关工具函数与通用转换逻辑，属于通用工具。
// 核心逻辑：提供 app version 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
// 关键声明：app version 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
// 流程逻辑：`compareAppVersions` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
int compareAppVersions(String left, String right) {
  final leftParts = _extractVersionParts(left);
  final rightParts = _extractVersionParts(right);
  final maxLength = leftParts.length > rightParts.length
      ? leftParts.length
      : rightParts.length;

  for (var i = 0; i < maxLength; i++) {
    final leftValue = i < leftParts.length ? leftParts[i] : 0;
    final rightValue = i < rightParts.length ? rightParts[i] : 0;
    if (leftValue != rightValue) {
      return leftValue > rightValue ? 1 : -1;
    }
  }
  return 0;
}

List<int> _extractVersionParts(String input) {
  final matches = RegExp(r'\d+')
      .allMatches(input)
      .map((match) => int.tryParse(match.group(0) ?? '0') ?? 0)
      .toList();
  return matches.isEmpty ? const [0] : matches;
}
