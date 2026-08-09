// 文件用途：实现 redirect utils 相关逻辑，服务于页面路由。
// 核心逻辑：围绕 redirect utils 组织，完成输入校验、核心处理和结果回传。
/// 只接受站内绝对路径，拒绝协议、域名和认证页，避免开放重定向及登录页循环跳转。
String? safeInAppRedirect(String? raw) {
  final value = raw?.trim();
  if (value == null || value.isEmpty) return null;

  final uri = Uri.tryParse(value);
  if (uri == null || uri.hasScheme || uri.hasAuthority) return null;
  if (!uri.path.startsWith('/') || uri.path.startsWith('//')) return null;
  if (_isAuthPath(uri.path)) return null;

  return uri.toString();
}

// 关键声明：redirect utils 维护导航状态与访问控制，重定向只读取权限相关状态，避免业务刷新触发整棵路由树重建。
// 流程逻辑：`loginLocationWithRedirect` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
String loginLocationWithRedirect(Uri from) {
  // 原目标经过二次编码保存，登录完成后仍必须通过 [safeInAppRedirect] 校验再回跳。
  final target = safeInAppRedirect(from.toString());
  if (target == null) return '/login';
  return '/login?redirect=${Uri.encodeComponent(target)}';
}

String splashLocationWithRedirect(Uri from) {
  final target = safeInAppRedirect(from.toString());
  if (target == null) return '/';
  return '/?redirect=${Uri.encodeComponent(target)}';
}

bool _isAuthPath(String path) {
  return path == '/login' ||
      path == '/register' ||
      path == '/forgot-password' ||
      path == '/';
}
