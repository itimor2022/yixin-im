// 文件用途：提供 profile share link 相关工具函数与通用转换逻辑，属于通用工具。
// 核心逻辑：提供 profile share link 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
// 关键声明：profile share link 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
// 流程逻辑：`buildUserProfileShareUrl` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
/// 构建分享用户公开资料时使用的浏览器链接。
///
/// 落地页先尝试唤起客户端，系统没有协议处理器时再回退 Flutter Web。
String buildUserProfileShareUrl({
  required String userId,
  String? name,
  String? avatar,
  String configuredBaseUrl = '',
  String compiledPublicH5Url = '',
  Uri? currentWebUri,
}) {
  final normalizedUserId = userId.trim();
  if (normalizedUserId.isEmpty) return '';

  // 地址优先级：服务端配置、编译期默认值、当前 Web origin。
  // API 域名会被过滤，避免把公开落地页错误拼到接口服务上。
  final baseUrl = _firstPublicH5BaseUrl(<String>[
    configuredBaseUrl,
    compiledPublicH5Url,
    if (currentWebUri != null &&
        (currentWebUri.scheme == 'http' || currentWebUri.scheme == 'https'))
      currentWebUri.origin,
  ]);
  if (baseUrl.isEmpty) return '';

  final params = <String, String>{
    'type': 'user',
    'id': normalizedUserId,
  };
  // name/avatar 只是落地页展示提示，接收端仍须按 id 获取权威用户资料。
  if (name?.trim().isNotEmpty == true) params['name'] = name!.trim();
  if (avatar?.trim().isNotEmpty == true) params['avatar'] = avatar!.trim();
  final query = Uri(queryParameters: params).query;

  return '$baseUrl/open.html?$query';
}

String _firstPublicH5BaseUrl(List<String> candidates) {
  for (final candidate in candidates) {
    final normalized = _normalizePublicH5BaseUrl(candidate);
    if (normalized.isNotEmpty) return normalized;
  }
  return '';
}

String _normalizePublicH5BaseUrl(String rawValue) {
  final value = rawValue.trim();
  if (value.isEmpty) return '';

  // 配置可能指向带 hash 路由的 H5 地址；拼接 open.html 前先去掉 hash 和尾斜杠。
  final hashIndex = value.indexOf('#');
  final withoutHash = (hashIndex >= 0 ? value.substring(0, hashIndex) : value)
      .replaceFirst(RegExp(r'/+$'), '');
  final uri = Uri.tryParse(withoutHash);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      _looksLikeApiOrigin(uri)) {
    return '';
  }

  return withoutHash;
}

bool _looksLikeApiOrigin(Uri uri) {
  final host = uri.host.toLowerCase();
  final firstLabel = host.split('.').first;
  final path = uri.path.toLowerCase();
  return firstLabel == 'api' ||
      firstLabel == 'imapi' ||
      firstLabel.endsWith('-api') ||
      path == '/api' ||
      path.startsWith('/api/');
}
