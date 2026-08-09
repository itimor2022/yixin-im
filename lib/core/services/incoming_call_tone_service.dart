// 文件用途：封装 AudioplayersIncomingCallToneBackend 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 AudioplayersIncomingCallToneBackend 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// 来电铃声后端；服务层只负责编排状态，播放器细节留在实现中。
abstract interface class IncomingCallToneBackend {
  Future<void> playLoop(String assetPath, {required double volume});

  Future<void> stop();

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  Future<void> dispose();
}

// 关键声明：incoming call tone service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
class AudioplayersIncomingCallToneBackend implements IncomingCallToneBackend {
  AudioplayersIncomingCallToneBackend({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  Future<void> playLoop(
    String assetPath, {
    required double volume,
  }) async {
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(volume);
    await _player.play(AssetSource(assetPath));
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

/// 串行执行来电铃声操作，防止异步 start 在接听、拒接或挂断之后才完成，
/// 从而遗留一个无法停止的循环铃声。
class IncomingCallToneService {
  IncomingCallToneService({IncomingCallToneBackend? backend})
      : _backend = backend ?? AudioplayersIncomingCallToneBackend();

  static const String _assetPath = 'sounds/ringtone.mp3';
  static const double _volume = 0.72;

  final IncomingCallToneBackend _backend;
  // 所有底层调用串联到同一队列，保证播放器按请求顺序被操作。
  Future<void> _backendQueue = Future<void>.value();
  bool _shouldPlay = false;
  bool _disposed = false;
  int _operation = 0;

  bool get isPlaying => _shouldPlay && !_disposed;

  Future<void> start() {
    if (_disposed || _shouldPlay) return _backendQueue;

    _shouldPlay = true;
    // operation 用于淘汰尚未执行但已被 stop/dispose 覆盖的启动任务。
    final operation = ++_operation;
    return _enqueue(() async {
      if (_disposed || !_shouldPlay || operation != _operation) return;
      try {
        await _backend.playLoop(_assetPath, volume: _volume);
      } catch (error) {
        if (operation == _operation) {
          _shouldPlay = false;
        }
        debugPrint('[IncomingCallTone] Start error: $error');
      }
    });
  }

  Future<void> stop() {
    if (_disposed) return _backendQueue;

    final needsStop = _shouldPlay;
    _shouldPlay = false;
    _operation += 1;
    if (!needsStop) return _backendQueue;

    return _enqueue(() async {
      try {
        await _backend.stop();
      } catch (error) {
        debugPrint('[IncomingCallTone] Stop error: $error');
      }
    });
  }

  Future<void> dispose() {
    if (_disposed) return _backendQueue;

    _disposed = true;
    _shouldPlay = false;
    _operation += 1;
    return _enqueue(() async {
      try {
        await _backend.stop();
      } catch (error) {
        debugPrint('[IncomingCallTone] Dispose stop error: $error');
      }
      try {
        await _backend.dispose();
      } catch (error) {
        debugPrint('[IncomingCallTone] Dispose error: $error');
      }
    });
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final scheduled = _backendQueue.then((_) => operation());
    // 队列自身吞掉上一个任务的错误，避免一次播放失败阻断后续停止和释放。
    _backendQueue = scheduled.catchError((Object error, StackTrace stack) {
      debugPrint('[IncomingCallTone] Queue error: $error');
    });
    return scheduled;
  }
}
