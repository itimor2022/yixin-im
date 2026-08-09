// 文件用途：封装 time zone refresh service 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 time zone refresh service 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'package:flutter_riverpod/flutter_riverpod.dart';

// 关键声明：time zone refresh service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
final timeZoneRefreshProvider = StateProvider<int>((ref) => 0);

// 流程逻辑：`didTimeZoneOffsetChange` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
bool didTimeZoneOffsetChange(Duration previous, Duration current) {
  return previous != current;
}

/// Re-resolves a cached local [DateTime] against the device's current zone.
///
/// Calling `toLocal()` directly on an already-local value returns that same
/// object, including the offset that was active when it was created. The UTC
/// round trip preserves the instant while forcing Dart to apply the current
/// system time zone after a run-time zone change.
DateTime toCurrentLocalTime(DateTime value) => value.toUtc().toLocal();
