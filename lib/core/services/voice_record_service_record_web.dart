// Web 端 recorder 入口 —— 直接复用 package:record 官方 web 实现。
//
// 历史遗留：这里以前是一个"啥也不做"的空壳，导致 web 端点长按录音永远失败并弹
// "当前 Web 端暂不支持语音录制"。真正原因是当时项目没引入 record_web 分实现，
// pubspec 已经通过 `dependency_overrides: record_web: ^1.3.0` 补上，
// 只是这个文件没跟着改回来。
//
// 现在 record 5.x 在 web 上通过 record_web + MediaRecorder API 已经稳定可用：
//   - Chrome/Edge/Firefox: 会自动选中 audio/webm; codecs=opus
//   - Safari: 走 audio/mp4 (AAC)
// 具体使用哪个编码器由上层 voice_record_service.dart 在启动前做能力探测。
//
// 只保留一个 export 就够了，Native 侧的入口文件也是同样 pattern。
export 'package:record/record.dart';
