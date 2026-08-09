// 文件用途：封装 RecordingState 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：管理录音状态机和临时资源，在达到时长/内容门槛后产出可上传数据，并在取消或生命周期中断时安全清理。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_io/io.dart';

import '../i18n/app_localizations.dart';
import '../utils/platform_utils.dart';
import 'voice_record_blob_reader.dart'
    if (dart.library.html) 'voice_record_blob_reader_web.dart';
import 'voice_record_service_record.dart'
    if (dart.library.html) 'voice_record_service_record_web.dart';

String _voiceRecordText({
  required String zhCN,
  required String zhTW,
  required String en,
}) {
  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 关键声明：voice record service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 录音会话状态。业务层只应通过 [VoiceRecordService] 驱动状态迁移，
/// 不要根据计时器或临时文件是否存在反推录音状态。
enum RecordingState {
  idle,
  recording,
  paused,
  stopped,
}

const int voiceRecordMinDurationMs = 1000;
const int voiceRecordMaxDurationSeconds = 300;

bool isVoiceRecordingUsable({
  required int durationMs,
  required int size,
}) {
  // 时长和文件内容同时达标才允许上传，避免发送空录音或误触产生的短音频。
  return durationMs >= voiceRecordMinDurationMs && size > 0;
}

bool shouldAutoStopVoiceRecording(int elapsedSeconds) {
  return elapsedSeconds >= voiceRecordMaxDurationSeconds;
}

bool shouldInterruptVoiceRecordingOnLifecycle(AppLifecycleState state) {
  return state == AppLifecycleState.inactive ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached;
}

/// 已完成且可交给上传层的录音结果。
///
/// 原生端通过 [path] 暴露临时文件；Web 端在结束录音时立即读取 Blob，
/// 因而上传方应使用 [bytes]，不能依赖已经被释放的 Blob URL。
class VoiceRecordData {
  final String path;
  final int duration;
  final int size;
  final Uint8List? bytes;
  final String? fileName;
  final String? mimeType;

  VoiceRecordData({
    required this.path,
    required this.duration,
    required this.size,
    this.bytes,
    this.fileName,
    this.mimeType,
  });
}

class VoiceRecordState {
  final RecordingState state;
  final int duration;
  final double amplitude;
  final String? error;

  const VoiceRecordState({
    this.state = RecordingState.idle,
    this.duration = 0,
    this.amplitude = 0,
    this.error,
  });

  VoiceRecordState copyWith({
    RecordingState? state,
    int? duration,
    double? amplitude,
    String? error,
    bool clearError = false,
  }) {
    return VoiceRecordState(
      state: state ?? this.state,
      duration: duration ?? this.duration,
      amplitude: amplitude ?? this.amplitude,
      error: clearError ? null : (error ?? this.error),
    );
  }

  bool get isRecording => state == RecordingState.recording;
  bool get isPaused => state == RecordingState.paused;
  bool get isIdle => state == RecordingState.idle;
}

/// 管理单次录音会话的状态、计时和临时资源。
///
/// [stopRecording] 表示保留有效录音，[cancelRecording] 表示丢弃录音。
/// 两个入口都可能被生命周期、通话中断和用户操作同时触发，因此内部会复用
/// 正在执行的 Future，避免对底层录音器重复 stop/cancel。
class VoiceRecordService extends StateNotifier<VoiceRecordState> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _durationTimer;
  Timer? _amplitudeTimer;
  DateTime? _startTime;
  String? _currentPath;
  String? _currentFileName;
  String? _currentMimeType;
  bool _isDisposed = false;
  bool _isAutoStopping = false;
  // 并发调用共享同一清理过程，保护底层录音器和临时文件不被重复处理。
  Future<void>? _cancelFuture;
  Future<VoiceRecordData?>? _stopFuture;
  final StreamController<VoiceRecordData> _autoStoppedController =
      StreamController<VoiceRecordData>.broadcast();

  VoiceRecordService() : super(const VoiceRecordState());

  /// 达到最长录音时长后产出的结果。
  ///
  /// 自动停止发生在计时器异步回调中，调用方需监听此流才能继续发送流程。
  Stream<VoiceRecordData> get autoStoppedRecordings =>
      _autoStoppedController.stream;

  VoiceRecordState get currentState => state;

  /// 检查并在支持的平台发起麦克风授权。
  ///
  /// Web 权限由浏览器和录音插件负责；原生端由 permission_handler 负责，
  /// 永久拒绝时会引导到系统设置页。
  Future<bool> checkPermission() async {
    if (PlatformUtils.isWeb) {
      try {
        final granted = await _recorder.hasPermission();
        if (!granted) {
          state = state.copyWith(
            error: _voiceRecordText(
              zhCN: '请允许浏览器访问麦克风后再录音',
              zhTW: '請允許瀏覽器存取麥克風後再錄音',
              en: 'Allow microphone access in the browser to record audio',
            ),
          );
        }
        return granted;
      } catch (e) {
        debugPrint('[VoiceRecord] Web permission error: $e');
        state = state.copyWith(
          error: _voiceRecordText(
            zhCN: '浏览器麦克风权限不可用',
            zhTW: '瀏覽器麥克風權限不可用',
            en: 'Browser microphone permission is unavailable',
          ),
        );
        return false;
      }
    }

    debugPrint('[VoiceRecord] Checking permission...');
    var status = await Permission.microphone.status;
    debugPrint('[VoiceRecord] Current status: $status');

    if (status.isGranted) {
      debugPrint('[VoiceRecord] Permission granted');
      return true;
    }

    if (status.isDenied || status.isRestricted || status.isLimited) {
      debugPrint('[VoiceRecord] Requesting permission...');
      status = await Permission.microphone.request();
      debugPrint('[VoiceRecord] Request result: $status');

      if (status.isGranted) {
        return true;
      }
    }

    if (status.isPermanentlyDenied) {
      debugPrint(
          '[VoiceRecord] Permission permanently denied, opening settings');
      state = state.copyWith(
        error: _voiceRecordText(
          zhCN: '麦克风权限被拒绝，请在设置中开启',
          zhTW: '麥克風權限被拒絕，請在設定中開啟',
          en: 'Microphone permission was denied. Enable it in settings',
        ),
      );
      await openAppSettings();
      return false;
    }

    status = await Permission.microphone.status;
    debugPrint('[VoiceRecord] Final status: $status');

    if (!status.isGranted) {
      state = state.copyWith(
        error: _voiceRecordText(
          zhCN: '需要麦克风权限才能录音',
          zhTW: '需要麥克風權限才能錄音',
          en: 'Microphone permission is required to record audio',
        ),
      );
    }

    return status.isGranted;
  }

  Future<bool> startRecording() async {
    debugPrint('[VoiceRecord] startRecording called');

    try {
      final hasPermission = await checkPermission();
      if (!hasPermission) {
        debugPrint('[VoiceRecord] No permission');
        return false;
      }

      final recorderPermission = await _recorder.hasPermission();
      debugPrint('[VoiceRecord] Recorder permission: $recorderPermission');
      if (!recorderPermission) {
        state = state.copyWith(
          error: _voiceRecordText(
            zhCN: '无法访问麦克风',
            zhTW: '無法存取麥克風',
            en: 'Unable to access the microphone',
          ),
        );
        return false;
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final encoder =
          PlatformUtils.isWeb ? AudioEncoder.opus : AudioEncoder.aacLc;
      final encoderSupported = await _recorder.isEncoderSupported(encoder);
      if (!encoderSupported) {
        state = state.copyWith(
          error: _voiceRecordText(
            zhCN: '当前浏览器不支持语音录制格式',
            zhTW: '目前瀏覽器不支援語音錄製格式',
            en: 'This browser does not support the audio recording format',
          ),
        );
        return false;
      }

      final config = RecordConfig(
        encoder: encoder,
        bitRate: PlatformUtils.isWeb ? 64000 : 128000,
        sampleRate: PlatformUtils.isWeb ? 48000 : 44100,
        numChannels: 1,
      );

      // Web 录音器返回 Blob URL；原生录音器则直接写入应用临时目录。
      if (PlatformUtils.isWeb) {
        _currentPath = '';
        _currentFileName = 'voice_$timestamp.webm';
        _currentMimeType = 'audio/webm';
      } else {
        final dir = await getTemporaryDirectory();
        _currentPath = '${dir.path}/voice_$timestamp.m4a';
        _currentFileName = 'voice_$timestamp.m4a';
        _currentMimeType = 'audio/mp4';
      }
      debugPrint('[VoiceRecord] Path: $_currentPath');

      debugPrint('[VoiceRecord] Starting recorder...');
      await _recorder.start(config, path: _currentPath!);
      debugPrint('[VoiceRecord] Recorder started');

      _startTime = DateTime.now();
      state = state.copyWith(
        state: RecordingState.recording,
        duration: 0,
        amplitude: 0,
        clearError: true,
      );
      debugPrint('[VoiceRecord] Recording state updated');

      _startTimers();
      return true;
    } catch (e) {
      debugPrint('[VoiceRecord] Start error: $e');
      state = state.copyWith(
        error: _voiceRecordText(
          zhCN: '录音启动失败',
          zhTW: '錄音啟動失敗',
          en: 'Failed to start recording',
        ),
      );
      return false;
    }
  }

  void _startTimers() {
    // 时长以墙钟差值计算，避免周期回调被系统调度延迟后累计误差。
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      if (_startTime != null) {
        final duration = DateTime.now().difference(_startTime!).inSeconds;
        state = state.copyWith(duration: duration);

        if (shouldAutoStopVoiceRecording(duration) && !_isAutoStopping) {
          _isAutoStopping = true;
          timer.cancel();
          unawaited(_finishAtMaxDuration());
        }
      }
    });

    // 振幅只用于实时 UI，读取失败不应终止仍在进行的录音。
    _amplitudeTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (_isDisposed) {
        timer.cancel();
        return;
      }

      try {
        final amplitude = await _recorder.getAmplitude();
        double normalized = 0;
        if (amplitude.current > -60) {
          normalized = (amplitude.current + 60) / 60;
          normalized = normalized.clamp(0.0, 1.0);
        }
        if (!_isDisposed) {
          state = state.copyWith(amplitude: normalized);
        }
      } catch (_) {}
    });
  }

  void _stopTimers() {
    _durationTimer?.cancel();
    _durationTimer = null;
    _amplitudeTimer?.cancel();
    _amplitudeTimer = null;
  }

  Future<void> _finishAtMaxDuration() async {
    try {
      final data = await stopRecording();
      if (data != null && !_isDisposed && !_autoStoppedController.isClosed) {
        _autoStoppedController.add(data);
      }
    } finally {
      _isAutoStopping = false;
    }
  }

  Future<VoiceRecordData?> stopRecording() {
    // 自动停止和手动松手可能同时到达，只允许一次底层 stop。
    final pending = _stopFuture;
    if (pending != null) return pending;

    final future = _stopRecordingInternal();
    _stopFuture = future;
    return future.whenComplete(() {
      if (identical(_stopFuture, future)) {
        _stopFuture = null;
      }
    });
  }

  Future<VoiceRecordData?> _stopRecordingInternal() async {
    try {
      _stopTimers();

      if (!state.isRecording && !state.isPaused) {
        return null;
      }

      final recordedPath = await _recorder.stop();
      if (recordedPath == null) {
        _clearCurrentRecording();
        state = state.copyWith(
          state: RecordingState.idle,
          duration: 0,
          amplitude: 0,
          error: _voiceRecordText(
            zhCN: '录音文件为空，请重试',
            zhTW: '錄音檔案為空，請重試',
            en: 'The recording is empty. Please try again',
          ),
        );
        return null;
      }

      final duration = _startTime != null
          ? DateTime.now().difference(_startTime!).inMilliseconds
          : 0;

      // Web 端必须先把 Blob URL 读成字节再释放 URL；原生端保留临时文件路径，
      // 后续发送层据此选择 MultipartFile.fromBytes 或 MultipartFile.fromFile。
      Uint8List? bytes;
      var outputPath = recordedPath;
      var size = 0;
      File? file;
      if (PlatformUtils.isWeb) {
        // Blob URL 仅用于取回本次录音；复制出字节后立即释放浏览器资源。
        bytes = await readWebRecordingBytes(recordedPath);
        size = bytes.length;
        revokeWebRecordingUrl(recordedPath);
      } else {
        outputPath = _currentPath ?? recordedPath;
        file = File(outputPath);
        size = await file.exists() ? await file.length() : 0;
      }

      state = state.copyWith(
        state: RecordingState.stopped,
        duration: 0,
        amplitude: 0,
      );

      if (!isVoiceRecordingUsable(durationMs: duration, size: size)) {
        if (file != null && await file.exists()) {
          await file.delete();
        }
        final error = duration < voiceRecordMinDurationMs
            ? _voiceRecordText(
                zhCN: '录音时间太短，请至少录制1秒',
                zhTW: '錄音時間太短，請至少錄製1秒',
                en: 'Recording is too short. Record for at least 1 second',
              )
            : _voiceRecordText(
                zhCN: '录音文件为空，请重试',
                zhTW: '錄音檔案為空，請重試',
                en: 'The recording is empty. Please try again',
              );
        _clearCurrentRecording();
        state = state.copyWith(
          state: RecordingState.idle,
          duration: 0,
          amplitude: 0,
          error: error,
        );
        return null;
      }

      final data = VoiceRecordData(
        path: outputPath,
        duration: duration,
        size: size,
        bytes: bytes,
        fileName: _currentFileName,
        mimeType: _currentMimeType,
      );

      state = state.copyWith(
        state: RecordingState.idle,
        clearError: true,
      );
      _clearCurrentRecording();

      return data;
    } catch (e) {
      debugPrint('[VoiceRecord] Stop error: $e');
      state = state.copyWith(
        state: RecordingState.idle,
        error: _voiceRecordText(
          zhCN: '录音停止失败',
          zhTW: '錄音停止失敗',
          en: 'Failed to stop recording',
        ),
      );
      return null;
    }
  }

  void _clearCurrentRecording() {
    _currentPath = null;
    _currentFileName = null;
    _currentMimeType = null;
    _startTime = null;
  }

  Future<void> cancelRecording() {
    // 取消只负责丢弃当前录音，不会产生可上传的 VoiceRecordData。
    final pending = _cancelFuture;
    if (pending != null) return pending;

    final future = _cancelRecordingInternal();
    _cancelFuture = future;
    return future.whenComplete(() {
      if (identical(_cancelFuture, future)) {
        _cancelFuture = null;
      }
    });
  }

  Future<void> _cancelRecordingInternal() async {
    _stopTimers();
    try {
      if (PlatformUtils.isWeb) {
        await _recorder.cancel();
      } else {
        await _recorder.stop();
      }
    } catch (e) {
      // The native recorder can already have been stopped by a concurrent
      // lifecycle/call interruption. Cleanup below must still run.
      debugPrint('[VoiceRecord] Recorder cancel/stop error: $e');
    }

    try {
      if (!PlatformUtils.isWeb && _currentPath?.isNotEmpty == true) {
        final file = File(_currentPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (e) {
      debugPrint('[VoiceRecord] Temporary recording cleanup error: $e');
    }

    if (!_isDisposed) {
      state = state.copyWith(
        state: RecordingState.idle,
        duration: 0,
        amplitude: 0,
      );
    }
    _clearCurrentRecording();
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    // dispose 后计时器不得再写 StateNotifier，广播流也不再接收自动停止结果。
    _stopTimers();
    _autoStoppedController.close();
    _recorder.dispose();
    super.dispose();
  }
}

final voiceRecordProvider =
    StateNotifierProvider<VoiceRecordService, VoiceRecordState>((ref) {
  return VoiceRecordService();
});
