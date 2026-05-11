enum OneChatQrType {
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

String buildUserQrPayload(String userUuid) => 'onechat://user/$userUuid';

String buildGroupQrPayload(String inviteLink) => 'onechat://group/$inviteLink';

String buildLoginQrPayload(String ticket) => 'onechat://login/$ticket';

OneChatQrPayload? parseOneChatQrPayload(String? rawValue) {
  final raw = rawValue?.trim() ?? '';
  if (raw.isEmpty) return null;

  final uri = Uri.tryParse(raw);
  if (uri == null || uri.scheme.toLowerCase() != 'onechat') return null;

  final target = uri.host.toLowerCase();
  final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first.trim() : '';
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
