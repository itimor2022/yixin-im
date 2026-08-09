import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/call_end_tone_service.dart';

void main() {
  test('plays the call-ended cue after cleanup completes', () async {
    final backend = _FakeCallEndToneBackend();
    final service = CallEndToneService(backend: backend);
    final cleanup = Completer<void>();

    final playing = service.playAfter(cleanup.future);
    await Future<void>.delayed(Duration.zero);
    expect(backend.playCount, 0);

    cleanup.complete();
    await playing;

    expect(backend.playCount, 1);
    expect(backend.assetPath, 'sounds/call_ended.wav');
    expect(backend.volume, 0.62);
  });

  test('a new call can cancel a pending call-ended cue', () async {
    final backend = _FakeCallEndToneBackend();
    final service = CallEndToneService(backend: backend);
    final cleanup = Completer<void>();

    final playing = service.playAfter(cleanup.future);
    await Future<void>.delayed(Duration.zero);
    await service.stop();
    cleanup.complete();
    await playing;

    expect(backend.playCount, 0);
    expect(backend.stopCount, 1);
  });

  test('dispose cancels pending playback and releases the backend', () async {
    final backend = _FakeCallEndToneBackend();
    final service = CallEndToneService(backend: backend);
    final cleanup = Completer<void>();

    final playing = service.playAfter(cleanup.future);
    await Future<void>.delayed(Duration.zero);
    await service.dispose();
    cleanup.complete();
    await playing;

    expect(backend.playCount, 0);
    expect(backend.stopCount, 1);
    expect(backend.disposeCount, 1);
  });
}

class _FakeCallEndToneBackend implements CallEndToneBackend {
  int playCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  String? assetPath;
  double? volume;

  @override
  Future<void> playOnce(
    String assetPath, {
    required double volume,
  }) async {
    playCount += 1;
    this.assetPath = assetPath;
    this.volume = volume;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}
