import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/outgoing_call_tone_service.dart';

void main() {
  test('starts the outgoing tone once and stops it when the call changes state',
      () async {
    final backend = _FakeOutgoingCallToneBackend();
    final service = OutgoingCallToneService(backend: backend);

    await service.start();
    await service.start();

    expect(service.isPlaying, isTrue);
    expect(backend.playCount, 1);
    expect(backend.assetPath, 'sounds/ringtone.mp3');
    expect(backend.volume, 0.85);

    await service.stop();
    await service.stop();

    expect(service.isPlaying, isFalse);
    expect(backend.stopCount, 1);
  });

  test('a stop racing a delayed start cannot leak tone into a connected call',
      () async {
    final backend = _FakeOutgoingCallToneBackend(delayStart: true);
    final service = OutgoingCallToneService(backend: backend);

    final starting = service.start();
    await Future<void>.delayed(Duration.zero);
    final stopping = service.stop();
    backend.completeStart();
    await Future.wait([starting, stopping]);

    expect(service.isPlaying, isFalse);
    expect(backend.playCount, 1);
    expect(backend.stopCount, 1);
  });

  test('a new call starts only after the previous delayed tone is stopped',
      () async {
    final backend = _FakeOutgoingCallToneBackend(delayStart: true);
    final service = OutgoingCallToneService(backend: backend);

    final firstStart = service.start();
    await Future<void>.delayed(Duration.zero);
    final firstStop = service.stop();
    final secondStart = service.start();

    backend.completeStart();
    await Future.wait([firstStart, firstStop, secondStart]);

    expect(service.isPlaying, isTrue);
    expect(backend.playCount, 2);
    expect(backend.stopCount, 1);
  });

  test('dispose stops the tone and prevents future playback', () async {
    final backend = _FakeOutgoingCallToneBackend();
    final service = OutgoingCallToneService(backend: backend);

    await service.start();
    await service.dispose();
    await service.start();

    expect(service.isPlaying, isFalse);
    expect(backend.playCount, 1);
    expect(backend.stopCount, 1);
    expect(backend.disposeCount, 1);
  });
}

class _FakeOutgoingCallToneBackend implements OutgoingCallToneBackend {
  _FakeOutgoingCallToneBackend({this.delayStart = false});

  final bool delayStart;
  final Completer<void> _startCompleter = Completer<void>();

  int playCount = 0;
  int stopCount = 0;
  int disposeCount = 0;
  String? assetPath;
  double? volume;

  @override
  Future<void> playLoop(
    String assetPath, {
    required double volume,
  }) async {
    playCount += 1;
    this.assetPath = assetPath;
    this.volume = volume;
    if (delayStart) {
      await _startCompleter.future;
    }
  }

  void completeStart() {
    if (!_startCompleter.isCompleted) {
      _startCompleter.complete();
    }
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
