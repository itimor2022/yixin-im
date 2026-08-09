// 文件用途：封装 PerformanceTraceService 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 PerformanceTraceService 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'package:flutter/foundation.dart';

// 关键声明：performance trace service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
class PerformanceTraceService {
  PerformanceTraceService._();

  static const bool _enabled =
      kDebugMode || bool.fromEnvironment('ENABLE_PERF_TRACE');
  // mark 使用同一进程起点，便于比较启动阶段各里程碑，而非测量单段耗时。
  static final Stopwatch _appStopwatch = Stopwatch()..start();

  static void mark(String name) {
    if (!_enabled) return;
    // ignore: avoid_print
    print('[Perf] $name +${_appStopwatch.elapsedMilliseconds}ms');
  }

  static PerformanceTraceSpan start(String name) {
    return PerformanceTraceSpan._(name);
  }

  static Future<T> timeAsync<T>(
    String name,
    // 流程逻辑：`Function` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
    Future<T> Function() action,
  ) async {
    final span = start(name);
    try {
      return await action();
    } finally {
      // 被测动作抛错时也必须结束计时，且异常继续原样向调用方传播。
      span.finish();
    }
  }
}

class PerformanceTraceSpan {
  PerformanceTraceSpan._(this.name) {
    if (PerformanceTraceService._enabled) {
      _watch.start();
    }
  }

  final String name;
  final Stopwatch _watch = Stopwatch();
  bool _finished = false;

  void finish([String? detail]) {
    // span 只允许结束一次，防止重复回调产生误导性的第二条耗时记录。
    if (!PerformanceTraceService._enabled || _finished) return;
    _finished = true;
    _watch.stop();
    final suffix = detail == null || detail.isEmpty ? '' : ' $detail';
    // ignore: avoid_print
    print('[Perf] $name ${_watch.elapsedMilliseconds}ms$suffix');
  }
}
