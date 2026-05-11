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
  final String path;
  final int duration;
  final int size;

  VoiceRecordData({
    required this.path,
    required this.duration,
    required this.size,
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
  bool _isDisposed = false;

  VoiceRecordService() : super(const VoiceRecordState());

  Future<bool> checkPermission() async {
    if (PlatformUtils.isWeb) {
      debugPrint('[VoiceRecord] Web recording is disabled');
      state = state.copyWith(error: '当前 Web 端暂不支持语音录制');
      return false;
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
      debugPrint('[VoiceRecord] Permission permanently denied, opening settings');
      state = state.copyWith(error: '麦克风权限被拒绝，请在设置中开启');
      await openAppSettings();
      return false;
    }

    status = await Permission.microphone.status;
    debugPrint('[VoiceRecord] Final status: $status');

    if (!status.isGranted) {
      state = state.copyWith(error: '需要麦克风权限才能录音');
    }

    return status.isGranted;
  }

  Future<bool> startRecording() async {
    debugPrint('[VoiceRecord] startRecording called');

    try {
      if (PlatformUtils.isWeb) {
        state = state.copyWith(error: '当前 Web 端暂不支持语音录制');
        return false;
      }

      final hasPermission = await checkPermission();
      if (!hasPermission) {
        debugPrint('[VoiceRecord] No permission');
        return false;
      }

      final recorderPermission = await _recorder.hasPermission();
      debugPrint('[VoiceRecord] Recorder permission: $recorderPermission');
      if (!recorderPermission) {
        state = state.copyWith(error: '无法访问麦克风');
        return false;
      }

      final dir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentPath = '${dir.path}/voice_$timestamp.m4a';
      debugPrint('[VoiceRecord] Path: $_currentPath');

      const config = RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
        numChannels: 1,
      );

      debugPrint('[VoiceRecord] Starting recorder...');
      await _recorder.start(config, path: _currentPath!);
      debugPrint('[VoiceRecord] Recorder started');

      _startTime = DateTime.now();
      state = state.copyWith(
        state: RecordingState.recording,
        duration: 0,
        amplitude: 0,
        error: null,
      );
      debugPrint('[VoiceRecord] Recording state updated');

      _startTimers();
      return true;
    } catch (e) {
      debugPrint('[VoiceRecord] Start error: $e');
      state = state.copyWith(error: '录音启动失败');
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

      final path = await _recorder.stop();
      if (path == null || _currentPath == null) {
        state = state.copyWith(state: RecordingState.idle);
        return null;
      }

      final duration = _startTime != null
          ? DateTime.now().difference(_startTime!).inMilliseconds
          : 0;

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
      debugPrint('[VoiceRecord] Stop error: $e');
      state = state.copyWith(state: RecordingState.idle, error: '录音停止失败');
      return null;
    }
  }

  Future<void> cancelRecording() async {
    try {
      _stopTimers();
      await _recorder.stop();

      if (_currentPath != null) {
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
      debugPrint('[VoiceRecord] Cancel error: $e');
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
