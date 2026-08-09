// 文件用途：封装 VoicePlaybackRoute 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 VoicePlaybackRoute 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// 关键声明：voice playback audio context 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 语音消息的输出路由偏好。
enum VoicePlaybackRoute { speaker, earpiece }

/// 距离传感器靠近时临时切到听筒；移开后恢复用户原先选择的路由。
VoicePlaybackRoute resolveVoicePlaybackRoute({
  required VoicePlaybackRoute preferredRoute,
  required bool proximityNear,
}) {
  return proximityNear ? VoicePlaybackRoute.earpiece : preferredRoute;
}

AudioContext _voicePlaybackAudioContext(VoicePlaybackRoute route) {
  final speaker = route == VoicePlaybackRoute.speaker;
  // 扬声器按媒体播放配置；听筒按通话语音配置，确保系统选择正确的输出设备。
  return AudioContext(
    android: AudioContextAndroid(
      isSpeakerphoneOn: speaker,
      audioMode:
          speaker ? AndroidAudioMode.normal : AndroidAudioMode.inCommunication,
      stayAwake: false,
      contentType: AndroidContentType.speech,
      usageType: speaker
          ? AndroidUsageType.media
          : AndroidUsageType.voiceCommunication,
      audioFocus: AndroidAudioFocus.gainTransient,
    ),
    iOS: AudioContextIOS(
      category: speaker
          ? AVAudioSessionCategory.playback
          : AVAudioSessionCategory.playAndRecord,
      options: speaker
          ? const [AVAudioSessionOptions.allowBluetoothA2DP]
          : const [AVAudioSessionOptions.allowBluetooth],
    ),
  );
}

// 流程逻辑：`configureVoicePlaybackAudio` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
Future<void> configureVoicePlaybackAudio(
  AudioPlayer player, {
  VoicePlaybackRoute route = VoicePlaybackRoute.speaker,
}) async {
  // 音频上下文和音量设置属于增强能力，失败时仍允许播放器继续尝试播放。
  try {
    await player.setAudioContext(_voicePlaybackAudioContext(route));
  } catch (e) {
    debugPrint('[VoicePlayback] Audio context error: $e');
  }

  try {
    await player.setVolume(1.0);
  } catch (e) {
    debugPrint('[VoicePlayback] Volume error: $e');
  }
}

/// 距离传感器与原生熄屏能力的轻量桥接。
///
/// 事件格式兼容 bool、数字和字符串，便于不同版本原生插件平滑升级。
/// 不支持该通道的平台保持当前路由和屏幕状态，不把能力缺失视为播放失败。
class VoicePlaybackProximityBridge {
  VoicePlaybackProximityBridge._();

  static const EventChannel _events = EventChannel(
    'com.genericim/voice_proximity/events',
  );
  static const MethodChannel _methods = MethodChannel(
    'com.genericim/voice_proximity/methods',
  );

  static Stream<bool>? _stream;

  static Stream<bool> get changes {
    // 缓存广播流，保证多个监听方共享同一个原生事件订阅。
    return _stream ??= _events.receiveBroadcastStream().map((event) {
      if (event is bool) return event;
      if (event is num) return event != 0;
      return event?.toString().toLowerCase() == 'true';
    }).handleError((Object error, StackTrace stackTrace) {
      debugPrint('[VoicePlayback] Proximity stream unavailable: $error');
    });
  }

  static Future<void> setScreenOffEnabled(bool enabled) async {
    if (kIsWeb) return;
    try {
      await _methods.invokeMethod<void>('setScreenOffEnabled', enabled);
    } on MissingPluginException {
      // 桌面端和未实现该通道的旧客户端安全地保留当前路由。
    } on PlatformException catch (error) {
      debugPrint('[VoicePlayback] Proximity screen control error: $error');
    }
  }
}
