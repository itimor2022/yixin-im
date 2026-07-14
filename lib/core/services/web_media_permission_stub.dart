// Native 桩：桌面/移动通过 permission_handler 走系统权限，不需要浏览器 API。

class WebMediaPermissionResult {
  final bool ok;
  /// 语义化理由：granted / denied / no_device / insecure_context /
  /// timeout / api_missing / unknown
  final String reason;
  const WebMediaPermissionResult({required this.ok, this.reason = 'granted'});
}

Future<WebMediaPermissionResult> ensureWebMediaPermission({
  required bool needCamera,
}) async =>
    const WebMediaPermissionResult(ok: true);
