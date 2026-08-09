// 文件用途：提供 chat attachment menu layout 相关工具函数与通用转换逻辑，属于聊天与消息。
// 核心逻辑：提供 chat attachment menu layout 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
// 关键声明：chat attachment menu layout 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
List<List<T>> paginateChatAttachmentActions<T>(
  List<T> actions, {
  int pageSize = 8,
}) {
  if (pageSize <= 0) {
    throw ArgumentError.value(pageSize, 'pageSize', 'must be greater than 0');
  }
  return [
    for (var start = 0; start < actions.length; start += pageSize)
      actions.sublist(
        start,
        start + pageSize < actions.length ? start + pageSize : actions.length,
      ),
  ];
}
