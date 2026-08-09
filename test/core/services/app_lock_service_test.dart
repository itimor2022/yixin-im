import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/api/auth_service.dart';
import 'package:generic_im/core/services/app_lock_service.dart';

void main() {
  group('app lock passcode verification', () {
    test('only the exact six digit passcode matches', () {
      final expectedHash = hashAppLockPasscode('246810');

      expect(
        verifyAppLockPasscode(
          passcode: '246810',
          expectedHash: expectedHash,
        ),
        isTrue,
      );
      expect(
        verifyAppLockPasscode(
          passcode: '111111',
          expectedHash: expectedHash,
        ),
        isFalse,
      );
      expect(
        verifyAppLockPasscode(passcode: '24681', expectedHash: expectedHash),
        isFalse,
      );
      expect(
        verifyAppLockPasscode(passcode: 'abcdef', expectedHash: expectedHash),
        isFalse,
      );
      expect(
        verifyAppLockPasscode(passcode: '246810', expectedHash: null),
        isFalse,
      );
    });
  });

  group('app lock authentication lifecycle', () {
    test('authenticated refresh cannot reinitialize an active lock', () {
      expect(
        shouldInitializeAppLockForAuthTransition(
          previousStatus: AuthStatus.authenticated,
          nextStatus: AuthStatus.authenticated,
          initialized: true,
        ),
        isFalse,
      );
    });

    test('first authenticated state initializes the lock', () {
      expect(
        shouldInitializeAppLockForAuthTransition(
          previousStatus: null,
          nextStatus: AuthStatus.authenticated,
          initialized: false,
        ),
        isTrue,
      );
    });

    test('async reinitialization preserves an already locked state', () {
      expect(
        resolveInitializedAppLockState(
          wasInitialized: true,
          wasLocked: true,
          lockOnStart: false,
          shouldLock: true,
        ),
        isTrue,
      );
    });

    test('biometric prompt lifecycle does not relock during authentication',
        () {
      expect(
        shouldSuppressAppLockLifecycleForBiometric(
          authenticationInProgress: true,
          unlockGraceUntil: null,
          now: DateTime(2026, 7, 23, 13),
        ),
        isTrue,
      );
    });

    test('biometric success grace absorbs the delayed resume event', () {
      final now = DateTime(2026, 7, 23, 13);
      expect(
        shouldSuppressAppLockLifecycleForBiometric(
          authenticationInProgress: false,
          unlockGraceUntil: now.add(const Duration(seconds: 2)),
          now: now,
        ),
        isTrue,
      );
      expect(
        shouldSuppressAppLockLifecycleForBiometric(
          authenticationInProgress: false,
          unlockGraceUntil: now,
          now: now.add(const Duration(milliseconds: 1)),
        ),
        isFalse,
      );
    });
  });
}
