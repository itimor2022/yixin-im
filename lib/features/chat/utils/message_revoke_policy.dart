// 文件用途：提供 RevokedMessageActor 相关工具函数与通用转换逻辑，属于聊天与消息。
// 核心逻辑：提供 RevokedMessageActor 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
// 流程逻辑：`isWithinMessageRevokeWindow` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
bool isWithinMessageRevokeWindow({
  required DateTime createdAt,
  required DateTime now,
  required int revokeMinutes,
}) {
  final safeMinutes = revokeMinutes > 0 ? revokeMinutes : 2;
  return now.difference(createdAt) < Duration(minutes: safeMinutes);
}

// 关键声明：message revoke policy 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
enum RevokedMessageActor { self, admin, other }

RevokedMessageActor classifyRevokedMessageActor({
  required bool isGroup,
  required bool isOutgoing,
  required String senderId,
  required String? revokedBy,
  required String? currentUserId,
}) {
  if (isGroup && revokedBy != null && revokedBy != senderId) {
    return RevokedMessageActor.admin;
  }
  if (isOutgoing || (revokedBy != null && revokedBy == currentUserId)) {
    return RevokedMessageActor.self;
  }
  return RevokedMessageActor.other;
}
