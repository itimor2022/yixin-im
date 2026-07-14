// Web 端：主动调 navigator.mediaDevices.getUserMedia() 让浏览器弹权限窗，
// 避免"点了通话没反应 / 对方看不到来电"这种情况实际是麦克风被拒。
//
// 之前 _requestPermissions 在 web 分支直接 return true，
// 结果 Agora 的 createMicrophoneAudioTrack 才会真正触发 getUserMedia：
// 那时用户拒绝，Agora 抛 PERMISSION_DENIED，主叫已经 create call、
// 对方 APK 已收到 incoming_call 然后又立刻被 cancel，很难 debug。
//
// 现在把权限确认前置到 startCall 之前：
// - 允许 → 立刻把测试轨道 stop 掉（浏览器仍会记住授权，Agora 后续无缝复用）
// - 拒绝 / 无设备 / 非 HTTPS → 明确返回原因，call_service 里映射成人话给用户

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// DOMException 只关心 name 字段；把 JSObject 视作它就够了，
/// 不用引 js_interop_unsafe。
extension type _DomExceptionLike._(JSObject _) implements JSObject {
  external JSString? get name;
}

/// `{ name: 'microphone' }` 之类的 Permissions API 描述符。
extension type _PermissionDescriptor._(JSObject _) implements JSObject {
  external factory _PermissionDescriptor({String name});
}

class WebMediaPermissionResult {
  final bool ok;

  /// 语义化理由：granted / denied / no_device / insecure_context /
  /// timeout / api_missing / busy / unknown
  final String reason;
  const WebMediaPermissionResult({required this.ok, this.reason = 'granted'});
}

/// 主动弹出浏览器权限窗，尝试拿到 audio(+video) 轨道并立刻释放。
Future<WebMediaPermissionResult> ensureWebMediaPermission({
  required bool needCamera,
}) async {
  try {
    // 1. 非 HTTPS/localhost → getUserMedia 一定失败，短路给明确原因
    if (!web.window.isSecureContext) {
      return const WebMediaPermissionResult(
        ok: false,
        reason: 'insecure_context',
      );
    }

    // 2. ★ 优先走 Permissions API 探测已授予状态。
    //    如果 mic (+ camera) 已经是 granted，就完全不 gum、不占测试轨道，
    //    避免我们的探测 track 和后续 Agora enableAudio 的 track 撞在一起
    //    ——那正是"隔一次成功一次"的其中一个诱因。
    //    只有在 prompt/denied 或探测不可用时才 fallback 到 gum。
    if (await _permissionsAlreadyGranted(needCamera: needCamera)) {
      return const WebMediaPermissionResult(ok: true, reason: 'granted_cached');
    }

    // 3. Fallback：调 getUserMedia 触发浏览器权限窗
    //    老浏览器 / 内嵌 WebView 拿不到 mediaDevices 时，下面访问会抛异常，
    //    统一走 catch 分支处理成 api_missing。
    final md = web.window.navigator.mediaDevices;
    final constraints = web.MediaStreamConstraints(
      audio: true.toJS,
      video: needCamera ? true.toJS : false.toJS,
    );

    // 加 10s 超时（用户不理弹窗时 Promise 会永远 pending）
    final stream = await md.getUserMedia(constraints).toDart.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('gum_timeout'),
    );

    // 拿到就立刻停掉测试轨道，浏览器仍会记住授权，
    // Agora 之后自己 getUserMedia 时不会再弹窗
    try {
      final tracks = stream.getTracks().toDart;
      for (final t in tracks) {
        t.stop();
      }
    } catch (_) {}

    return const WebMediaPermissionResult(ok: true);
  } on TimeoutException {
    return const WebMediaPermissionResult(ok: false, reason: 'timeout');
  } catch (e) {
    // getUserMedia 抛出的是 DOMException，name 字段最有用
    final name = _extractErrorName(e);
    switch (name) {
      case 'NotAllowedError':
      case 'SecurityError':
        return const WebMediaPermissionResult(ok: false, reason: 'denied');
      case 'NotFoundError':
      case 'OverconstrainedError':
        return const WebMediaPermissionResult(ok: false, reason: 'no_device');
      case 'NotReadableError':
        // 硬件被别的应用占用（Zoom/腾讯会议还开着最常见）
        return const WebMediaPermissionResult(ok: false, reason: 'busy');
      default:
        return WebMediaPermissionResult(
          ok: false,
          reason: name.isEmpty ? 'unknown: $e' : name,
        );
    }
  }
}

/// 用 navigator.permissions.query 判断权限是否已经 granted。
/// 出错（老浏览器/权限名不支持/API 缺失）时返回 false，让上层 fallback 到 gum。
Future<bool> _permissionsAlreadyGranted({required bool needCamera}) async {
  try {
    final permissions = web.window.navigator.permissions;
    // ignore: unnecessary_null_comparison
    if (permissions == null) return false;

    Future<bool> _check(String name) async {
      try {
        final status = await permissions
            .query(_PermissionDescriptor(name: name))
            .toDart;
        // PermissionState 在 package:web 里就是 String（granted/denied/prompt）
        return status.state == 'granted';
      } catch (_) {
        return false;
      }
    }

    if (!await _check('microphone')) return false;
    if (needCamera && !await _check('camera')) return false;
    return true;
  } catch (_) {
    return false;
  }
}

String _extractErrorName(Object err) {
  // getUserMedia 拒绝时抛的 DOMException 会以 JSObject 形式穿到 catch，
  // 但也可能被 SDK 二次包装成 Dart Error；两种都兜底一下。
  try {
    if (err is JSObject) {
      final name = (err as _DomExceptionLike).name?.toDart;
      if (name != null && name.isNotEmpty) return name;
    }
  } catch (_) {}
  // 最后从 toString() 里正则捞一次（比如 "NotAllowedError: Permission denied"）
  final msg = err.toString();
  final match = RegExp(r'(NotAllowedError|NotFoundError|NotReadableError|'
          r'OverconstrainedError|SecurityError|AbortError|TypeError)')
      .firstMatch(msg);
  return match?.group(0) ?? '';
}
