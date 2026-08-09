import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/call_service.dart';

void main() {
  test('reconnect countdown rounds up and reaches zero at deadline', () {
    final deadline = DateTime.utc(2026, 7, 16, 12, 0, 20);

    expect(
      callReconnectSecondsRemaining(
        deadline,
        DateTime.utc(2026, 7, 16, 12, 0, 0, 1),
      ),
      20,
    );
    expect(
      callReconnectSecondsRemaining(
        deadline,
        DateTime.utc(2026, 7, 16, 12, 0, 19, 999),
      ),
      1,
    );
    expect(callReconnectSecondsRemaining(deadline, deadline), 0);
  });

  test('only camera denial offers voice downgrade', () {
    expect(
      callPermissionSupportsVoiceFallback(CallPermissionIssue.cameraDenied),
      isTrue,
    );
    expect(
      callPermissionSupportsVoiceFallback(
        CallPermissionIssue.cameraPermanentlyDenied,
      ),
      isTrue,
    );
    expect(
      callPermissionSupportsVoiceFallback(
        CallPermissionIssue.microphoneDenied,
      ),
      isFalse,
    );
  });

  test('elapsed call time is based on server connection time', () {
    final now = DateTime.utc(2026, 7, 16, 12, 5);
    expect(
      callElapsedSeconds(now.subtract(const Duration(minutes: 2)), now),
      120,
    );
    expect(callElapsedSeconds(now.add(const Duration(seconds: 3)), now), 0);
    expect(callElapsedSeconds(null, now), 0);
  });

  test('expired incoming call payload is rejected', () {
    final now = DateTime.utc(2026, 7, 16, 12, 0, 30);
    expect(incomingCallIsExpired('2026-07-16T12:00:29Z', now), isTrue);
    expect(incomingCallIsExpired('2026-07-16T12:00:31Z', now), isFalse);
    expect(incomingCallIsExpired('1784203229', now), isTrue);
    expect(incomingCallIsExpired('1784203231000', now), isFalse);
    expect(incomingCallIsExpired(null, now), isFalse);
  });
}
