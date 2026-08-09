// 文件用途：封装 AudioplayersCallEndToneBackend 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 AudioplayersCallEndToneBackend 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 通话结束提示音后端，抽象后便于隔离播放器资源并进行时序测试。
abstract interface class CallEndToneBackend {
  Future<void> playOnce(String assetPath, {required double volume});

  Future<void> stop();

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  Future<void> dispose();
}

// 关键声明：call end tone service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
class AudioplayersCallEndToneBackend implements CallEndToneBackend {
  AudioplayersCallEndToneBackend({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> playOnce(
    String assetPath, {
    required double volume,
  }) async {
    await _player.setReleaseMode(ReleaseMode.stop);
    await _player.setVolume(volume);
    await _player.play(AssetSource(assetPath));
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// 在已接通的通话结束后播放一次短提示音。
///
/// 拒接、占线、取消和未接通不会播放此声音。若清理上一通电话期间又发起新通话，
/// 调用 [stop] 会让等待中的播放操作失效，避免与下一通电话的回铃音重叠。
class CallEndToneService {
  CallEndToneService({CallEndToneBackend? backend})
      : _backend = backend ?? AudioplayersCallEndToneBackend();

  static const String _assetPath = 'sounds/call_ended.wav';
  static const double _volume = 0.62;

  final CallEndToneBackend _backend;
  bool _disposed = false;
  int _operation = 0;

  Future<void> playAfter(Future<void> barrier) async {
    if (_disposed) return;
    // operation 是失效令牌：等待 barrier 时发生 stop/dispose 后，本次播放即作废。
    final operation = ++_operation;

    try {
      await barrier;
    } catch (error) {
      debugPrint('[CallEndTone] Cleanup barrier error: $error');
    }

    if (_disposed || operation != _operation) return;

    try {
      await _backend.playOnce(_assetPath, volume: _volume);
    } catch (error) {
      debugPrint('[CallEndTone] Play error: $error');
    }
  }

  Future<void> stop() async {
    if (_disposed) return;
    _operation += 1;
    try {
      await _backend.stop();
    } catch (error) {
      debugPrint('[CallEndTone] Stop error: $error');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _operation += 1;
    try {
      // 先停止再释放，确保短音频不会在播放器销毁过程中继续占用音频会话。
      await _backend.stop();
    } catch (error) {
      debugPrint('[CallEndTone] Dispose stop error: $error');
    }
    try {
      await _backend.dispose();
    } catch (error) {
      debugPrint('[CallEndTone] Dispose error: $error');
    }
  }
}
