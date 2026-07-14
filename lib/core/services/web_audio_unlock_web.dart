// Web 侧同步透传到 window.__unlockWebAudio()（定义在 web/index.html）。
//
// ★ 关键：这个函数必须**同步**执行，任何 Dart await / 异步跳板都会让
//   iOS Safari 把用户手势上下文丢掉，然后 AudioContext.resume() 永久失效。
//   所以：
//     - 不用 Future / async
//     - 通过 @JS 直接 bind 全局函数，一次同步调用完成
//     - startCall / acceptCall 里必须在**任何 await 之前**调它

import 'dart:js_interop';

@JS('__unlockWebAudio')
external JSFunction? get _unlockFn;

void unlockWebAudio() {
  try {
    final fn = _unlockFn;
    if (fn == null) return; // index.html 没定义就是老 build，静默跳过
    fn.callAsFunction();
  } catch (_) {
    // AudioContext 解锁失败不能拖垮通话主流程，吞掉即可
  }
}
