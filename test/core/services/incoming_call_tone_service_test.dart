import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/incoming_call_tone_service.dart';

void main() {
  test('starts once and stops on answer or hangup', () async {
    final backend = _FakeIncomingCallToneBackend();
    final service = IncomingCallToneService(backend: backend);

    await service.start();
    await service.start();
    await service.stop();
    await service.stop();

    expect(service.isPlaying, isFalse);
    expect(backend.events, ['play', 'stop']);
    expect(backend.assetPath, 'sounds/ringtone.mp3');
    expect(backend.volume, 0.72);
  });

  test('stop waits behind a delayed start so looping audio cannot leak',
      () async {
    final backend = _FakeIncomingCallToneBackend(delayFirstStart: true);
    final service = IncomingCallToneService(backend: backend);

    final starting = service.start();
    await Future<void>.delayed(Duration.zero);
    final stopping = service.stop();

    backend.completeFirstStart();
    await Future.wait([starting, stopping]);

    expect(service.isPlaying, isFalse);
    expect(backend.events, ['play', 'stop']);
  });

  test('answer followed by a new call preserves serialized playback order',
      () async {
    final backend = _FakeIncomingCallToneBackend(delayFirstStart: true);
    final service = IncomingCallToneService(backend: backend);

    final firstStart = service.start();
    await Future<void>.delayed(Duration.zero);
    final firstStop = service.stop();
    final secondStart = service.start();

    backend.completeFirstStart();
    await Future.wait([firstStart, firstStop, secondStart]);

    expect(service.isPlaying, isTrue);
    expect(backend.events, ['play', 'stop', 'play']);

    await service.stop();
    expect(backend.events, ['play', 'stop', 'play', 'stop']);
  });

  test('dispose stops, releases and prevents later playback', () async {
    final backend = _FakeIncomingCallToneBackend();
    final service = IncomingCallToneService(backend: backend);

    await service.start();
    await service.dispose();
    await service.start();

    expect(service.isPlaying, isFalse);
    expect(backend.events, ['play', 'stop', 'dispose']);
  });
}

class _FakeIncomingCallToneBackend implements IncomingCallToneBackend {
  _FakeIncomingCallToneBackend({this.delayFirstStart = false});

  final bool delayFirstStart;
  final Completer<void> _firstStartCompleter = Completer<void>();
  final List<String> events = [];
  int _playCount = 0;
  String? assetPath;
  double? volume;

  @override
  Future<void> playLoop(
    String assetPath, {
    required double volume,
  }) async {
    _playCount += 1;
    events.add('play');
    this.assetPath = assetPath;
    this.volume = volume;
    if (delayFirstStart && _playCount == 1) {
      await _firstStartCompleter.future;
    }
  }

  void completeFirstStart() {
    if (!_firstStartCompleter.isCompleted) {
      _firstStartCompleter.complete();
    }
  }

  @override
  Future<void> stop() async {
    events.add('stop');
  }

  @override
  Future<void> dispose() async {
    events.add('dispose');
  }
}
