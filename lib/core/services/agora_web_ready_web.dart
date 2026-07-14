// Web 端：查询 index.html 里定义的 window.__isAgoraWebReady()
// 若 iris_web 脚本没加载 / 加载失败 / 还没就绪，返回具体原因给 UI。

import 'dart:js_interop';

/// window.__isAgoraWebReady() 返回的结构。
///
/// index.html 里定义：`{ ok: bool, reason: string }` 或 `{ ok: true }`
extension type _WebReadyReturn._(JSObject _) implements JSObject {
  external JSBoolean? get ok;
  external JSString? get reason;
}

@JS('__isAgoraWebReady')
external JSFunction? get _isAgoraWebReadyFn;

class AgoraWebReadyResult {
  final bool ok;
  final String reason;
  const AgoraWebReadyResult({required this.ok, this.reason = ''});
}

AgoraWebReadyResult checkAgoraWebReady() {
  try {
    final fn = _isAgoraWebReadyFn;
    if (fn == null) {
      return const AgoraWebReadyResult(ok: false, reason: 'probe_missing');
    }
    final resAny = fn.callAsFunction();
    if (resAny == null) {
      return const AgoraWebReadyResult(ok: false, reason: 'no_result');
    }
    final res = resAny as _WebReadyReturn;
    final okBool = res.ok?.toDart ?? false;
    final reasonStr = res.reason?.toDart ?? '';
    return AgoraWebReadyResult(ok: okBool, reason: reasonStr);
  } catch (e) {
    return AgoraWebReadyResult(ok: false, reason: 'probe_error: $e');
  }
}
