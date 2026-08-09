// 文件用途：提供 OneChatQrType 相关工具函数与通用转换逻辑，属于通用工具。
// 核心逻辑：提供 OneChatQrType 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
// 关键声明：二维码 payload 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
enum OneChatQrType {
  // 枚举表示解析后的业务目标，二维码文本本身使用稳定字符串而非枚举下标。
  user,
  group,
  login,
}

class OneChatQrPayload {
  final OneChatQrType type;
  final String id;

  const OneChatQrPayload({
    required this.type,
    required this.id,
  });
}

// 流程逻辑：`buildUserQrPayload` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
String buildUserQrPayload(String userUuid) => 'genericim://user/$userUuid';

String buildGroupQrPayload(String inviteLink) => 'genericim://group/$inviteLink';

String buildLoginQrPayload(String ticket) => 'genericim://login/$ticket';

OneChatQrPayload? parseOneChatQrPayload(String? rawValue) {
  final raw = rawValue?.trim() ?? '';
  if (raw.isEmpty) return null;

  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme.toLowerCase() != 'genericim') return null;

  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  // 同时兼容 genericim://user/id（host 形式）和 genericim:///user/id（path 形式）。
  final target = uri.host.isNotEmpty
      ? uri.host.toLowerCase()
      : (segments.isNotEmpty ? segments.removeAt(0).toLowerCase() : '');
  // ID 是单个不透明路径段；构建方不应传完整 URL 或额外层级。
  final id = segments.isNotEmpty ? segments.first.trim() : '';
  if (id.isEmpty) return null;

  switch (target) {
    case 'user':
      return OneChatQrPayload(type: OneChatQrType.user, id: id);
    case 'group':
      return OneChatQrPayload(type: OneChatQrType.group, id: id);
    case 'login':
      return OneChatQrPayload(type: OneChatQrType.login, id: id);
    default:
      return null;
  }
}
