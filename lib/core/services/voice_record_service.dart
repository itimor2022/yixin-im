import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:universal_io/io.dart';

import '../utils/platform_utils.dart';
import 'voice_record_service_record.dart'
    if (dart.library.html) 'voice_record_service_record_web.dart';

enum RecordingState {
  idle,
  recording,
  paused,
  stopped,
}

class VoiceRecordData {
  /// 录音数据地址：
  ///   - Native: 本地文件绝对路径（`/tmp/voice_xxx.m4a`）
  ///   - Web: `MediaRecorder` 产出的 `blob:https://...` URL
  /// 上传逻辑（`message_provider.sendVoiceMessage`）会自行区分并按平台读取字节。
  final String path;
  final int duration;

  /// 文件字节数。Native 端在 stopRecording 时用 File.length 拿到，
  /// Web 端 blob 拿不到确切大小，先填 0，上传时用真实字节数补齐。
  final int size;

  /// 上传时的 MIME 类型，供 web 端使用（决定 backend 的 Content-Type 校验分支）。
  /// Native 端不用管，默认 `audio/mp4`。
  final String mimeType;

  /// 上传时的建议文件扩展名（不带点）。Native 是 `m4a`，Web 视浏览器可能是
  /// `webm` / `mp4` / `ogg`。
  final String extension;

  VoiceRecordData({
    required this.path,
    required this.duration,
    required this.size,
    this.mimeType = 'audio/mp4',
    this.extension = 'm4a',
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

class VoiceRecordService extends StateNotifier<VoiceRecordState> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _durationTimer;
  Timer? _amplitudeTimer;
  DateTime? _startTime;
  String? _currentPath;

  /// Web 端启动时探测出来的实际编码器 & MIME，stopRecording 时透传给上层。
  AudioEncoder _webEncoder = AudioEncoder.opus;
  String _webMimeType = 'audio/webm';
  String _webExtension = 'webm';

  bool _isDisposed = false;

  VoiceRecordService() : super(const VoiceRecordState());

  Future<bool> checkPermission() async {
    // Web：浏览器在 MediaRecorder.start() 时会自动弹麦克风授权对话框，
    // 不需要走 permission_handler（在纯 Web 环境下不可用）。
    // 真正拿不到麦克风时，start() 会抛异常，由 startRecording 的 catch 兜底。
    if (PlatformUtils.isWeb) {
      return true;
    }

    if (kDebugMode) debugPrint('[VoiceRecord] Checking permission...');
    var status = await Permission.microphone.status;
    if (kDebugMode) debugPrint('[VoiceRecord] Current status: $status');

    if (status.isGranted) {
      if (kDebugMode) debugPrint('[VoiceRecord] Permission granted');
      return true;
    }

    if (status.isDenied || status.isRestricted || status.isLimited) {
      if (kDebugMode) debugPrint('[VoiceRecord] Requesting permission...');
      status = await Permission.microphone.request();
      if (kDebugMode) debugPrint('[VoiceRecord] Request result: $status');

      if (status.isGranted) {
        return true;
      }
    }

    if (status.isPermanentlyDenied) {
      if (kDebugMode) debugPrint('[VoiceRecord] Permission permanently denied, opening settings');
      state = state.copyWith(error: '麦克风权限被拒绝，请在设置中开启');
      await openAppSettings();
      return false;
    }

    status = await Permission.microphone.status;
    if (kDebugMode) debugPrint('[VoiceRecord] Final status: $status');

    if (!status.isGranted) {
      state = state.copyWith(error: '需要麦克风权限才能录音');
    }

    return status.isGranted;
  }

  Future<bool> startRecording() async {
    if (kDebugMode) debugPrint('[VoiceRecord] startRecording called');

    try {
      // ─── Web 分支 ────────────────────────────────────────────────
      // record_web 内部走浏览器 MediaRecorder：
      //   1. 编码器选择：优先 opus (Chrome/Firefox/Edge)，回退 aacLc (Safari)；
      //   2. path 参数在 web 上被忽略，stop() 返回 blob URL；
      //   3. 权限提示由浏览器自动弹，不需要 permission_handler。
      if (PlatformUtils.isWeb) {
        // 能力探测：opus 一般所有主流浏览器都支持（除 Safari 部分老版本），
        // 挑不到就退回 aacLc。都不行才判"不支持"。
        AudioEncoder? picked;
        if (await _recorder.isEncoderSupported(AudioEncoder.opus)) {
          picked = AudioEncoder.opus;
          _webMimeType = 'audio/webm';
          _webExtension = 'webm';
        } else if (await _recorder.isEncoderSupported(AudioEncoder.aacLc)) {
          picked = AudioEncoder.aacLc;
          _webMimeType = 'audio/mp4';
          _webExtension = 'm4a';
        } else {
          state = state.copyWith(error: '当前浏览器不支持语音录制');
          return false;
        }
        _webEncoder = picked;

        // 给一个占位文件名，方便调试 —— web 端 record 库会忽略路径本身。
        _currentPath = 'voice_${DateTime.now().millisecondsSinceEpoch}.$_webExtension';

        final config = RecordConfig(
          encoder: _webEncoder,
          // opus 通常 32 kbps 就已经很清晰，128 kbps 属于浪费带宽；
          // aacLc 保持 128 kbps 跟 Native 端一致。
          bitRate: _webEncoder == AudioEncoder.opus ? 32000 : 128000,
          sampleRate: 44100,
          numChannels: 1,
        );

        await _recorder.start(config, path: _currentPath!);

        _startTime = DateTime.now();
        state = state.copyWith(
          state: RecordingState.recording,
          duration: 0,
          amplitude: 0,
          error: null,
        );

        _startTimers();
        return true;
      }

      // ─── Native 分支（Android / iOS / 桌面）保持原样 ─────────────────
      final hasPermission = await checkPermission();
      if (!hasPermission) {
        if (kDebugMode) debugPrint('[VoiceRecord] No permission');
        return false;
      }

      final recorderPermission = await _recorder.hasPermission();
      if (kDebugMode) debugPrint('[VoiceRecord] Recorder permission: $recorderPermission');
      if (!recorderPermission) {
        state = state.copyWith(error: '无法访问麦克风');
        return false;
      }

      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentPath = '${dir.path}/voice_$timestamp.m4a';
      if (kDebugMode) debugPrint('[VoiceRecord] Path: $_currentPath');

      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      );

      if (kDebugMode) debugPrint('[VoiceRecord] Starting recorder...');
      await _recorder.start(config, path: _currentPath!);
      if (kDebugMode) debugPrint('[VoiceRecord] Recorder started');

      _startTime = DateTime.now();
      state = state.copyWith(
        state: RecordingState.recording,
        duration: 0,
        amplitude: 0,
        error: null,
      );
      if (kDebugMode) debugPrint('[VoiceRecord] Recording state updated');

      _startTimers();
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[VoiceRecord] Start error: $e');
      // Web 上抛异常最常见的原因是用户拒绝了麦克风权限，或者浏览器安全策略
      // 禁用了 getUserMedia（比如 HTTP 非本地域名）。给个更明确的提示。
      final msg = PlatformUtils.isWeb
          ? '录音启动失败，请确认已授权麦克风且页面通过 HTTPS 访问'
          : '录音启动失败';
      state = state.copyWith(error: msg);
      return false;
    }
  }

  void _startTimers() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      if (_startTime != null) {
        final duration = DateTime.now().difference(_startTime!).inSeconds;
        state = state.copyWith(duration: duration);

        if (duration >= 300) {
          stopRecording();
        }
      }
    });

    _amplitudeTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) async {
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

  Future<VoiceRecordData?> stopRecording() async {
    try {
      _stopTimers();

      if (!state.isRecording && !state.isPaused) {
        return null;
      }

      // Web 上 stop() 返回 blob URL；Native 上返回文件路径。两边都可能返回 null。
      final resultPath = await _recorder.stop();
      if (resultPath == null || _currentPath == null) {
        state = state.copyWith(state: RecordingState.idle);
        return null;
      }

      final duration = _startTime != null
          ? DateTime.now().difference(_startTime!).inMilliseconds
          : 0;

      // ─── Web 分支 ────────────────────────────────────────────────
      if (PlatformUtils.isWeb) {
        // 太短直接丢弃（跟 native 保持一致的 <1s 阈值）。
        // Web 端没有本地文件可以 delete，blob 会随 GC 自动回收。
        state = state.copyWith(state: RecordingState.stopped, duration: 0, amplitude: 0);
        if (duration < 1000) {
          state = state.copyWith(state: RecordingState.idle);
          _currentPath = null;
          _startTime = null;
          return null;
        }

        final data = VoiceRecordData(
          path: resultPath, // blob URL
          duration: duration,
          size: 0, // web 端大小上传时补齐
          mimeType: _webMimeType,
          extension: _webExtension,
        );

        state = state.copyWith(state: RecordingState.idle);
        _currentPath = null;
        _startTime = null;
        return data;
      }

      // ─── Native 分支（原逻辑不动） ─────────────────────────────────
      final file = File(_currentPath!);
      final size = await file.exists() ? await file.length() : 0;

      state = state.copyWith(
        state: RecordingState.stopped,
        duration: 0,
        amplitude: 0,
      );

      if (duration < 1000) {
        await file.delete();
        state = state.copyWith(state: RecordingState.idle);
        return null;
      }

      final data = VoiceRecordData(
        path: _currentPath!,
        duration: duration,
        size: size,
      );

      state = state.copyWith(state: RecordingState.idle);
      _currentPath = null;
      _startTime = null;

      return data;
    } catch (e) {
      if (kDebugMode) debugPrint('[VoiceRecord] Stop error: $e');
      state = state.copyWith(state: RecordingState.idle, error: '录音停止失败');
      return null;
    }
  }

  Future<void> cancelRecording() async {
    try {
      _stopTimers();
      // record 5.x 有 cancel() 语义（停止 + 丢弃产出），Native/Web 两端行为一致，
      // 相比原来"先 stop 再 File.delete"更简洁，也避免 web 上访问 File 报错。
      await _recorder.cancel();

      // Native 上再兜一层 File.delete，防止个别设备 cancel 未完全清理临时文件。
      if (!PlatformUtils.isWeb && _currentPath != null) {
        final file = File(_currentPath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      state = state.copyWith(
        state: RecordingState.idle,
        duration: 0,
        amplitude: 0,
      );

      _currentPath = null;
      _startTime = null;
    } catch (e) {
      if (kDebugMode) debugPrint('[VoiceRecord] Cancel error: $e');
      state = state.copyWith(state: RecordingState.idle);
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _stopTimers();
    _recorder.dispose();
    super.dispose();
  }
}

final voiceRecordProvider =
    StateNotifierProvider<VoiceRecordService, VoiceRecordState>((ref) {
  return VoiceRecordService();
});
