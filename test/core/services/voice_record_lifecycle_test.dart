import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/voice_record_service.dart';

void main() {
  test('voice recording boundaries reject short clips and stop at five minutes',
      () {
    expect(
      isVoiceRecordingUsable(durationMs: 999, size: 100),
      isFalse,
    );
    expect(
      isVoiceRecordingUsable(durationMs: 1000, size: 100),
      isTrue,
    );
    expect(shouldAutoStopVoiceRecording(299), isFalse);
    expect(shouldAutoStopVoiceRecording(300), isTrue);
  });

  test('background lifecycle states interrupt active voice recording', () {
    expect(
      shouldInterruptVoiceRecordingOnLifecycle(AppLifecycleState.inactive),
      isTrue,
    );
    expect(
      shouldInterruptVoiceRecordingOnLifecycle(AppLifecycleState.paused),
      isTrue,
    );
    expect(
      shouldInterruptVoiceRecordingOnLifecycle(AppLifecycleState.detached),
      isTrue,
    );
  });

  test('foreground lifecycle states keep voice recording available', () {
    expect(
      shouldInterruptVoiceRecordingOnLifecycle(AppLifecycleState.resumed),
      isFalse,
    );
    expect(
      shouldInterruptVoiceRecordingOnLifecycle(AppLifecycleState.hidden),
      isFalse,
    );
  });
}
