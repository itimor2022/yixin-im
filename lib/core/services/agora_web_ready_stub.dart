// Native 端占位：Agora native SDK 通过原生库加载，不依赖浏览器脚本。
// 保持接口一致，返回 "ok"。

class AgoraWebReadyResult {
  final bool ok;
  final String reason;
  const AgoraWebReadyResult({required this.ok, this.reason = ''});
}

AgoraWebReadyResult checkAgoraWebReady() =>
    const AgoraWebReadyResult(ok: true);
