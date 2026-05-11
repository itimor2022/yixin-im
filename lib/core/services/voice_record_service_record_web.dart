import 'package:flutter/foundation.dart';

class AudioRecorder {
  Future<bool> hasPermission({bool request = true}) async => false;

  Future<void> start(RecordConfig config, {required String path}) async {}

  Future<String?> stop() async => null;

  Future<void> pause() async {}

  Future<void> resume() async {}

  Future<Amplitude> getAmplitude() async => const Amplitude(current: -60);

  Future<void> cancel() async {}

  void dispose() {}
}

class RecordConfig {
  final AudioEncoder encoder;
  final int bitRate;
  final int sampleRate;
  final int numChannels;

  const RecordConfig({
    required this.encoder,
    required this.bitRate,
    required this.sampleRate,
    required this.numChannels,
  });
}

enum AudioEncoder { aacLc }

class Amplitude {
  final double current;

  const Amplitude({required this.current});
}
