import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/account_session_coordinator.dart';

void main() {
  group('AccountSessionCoordinator', () {
    test('activate increments epoch when the account changes', () {
      final coordinator = AccountSessionCoordinator();
      addTearDown(coordinator.dispose);

      final first = coordinator.activate('account-a');
      final same = coordinator.activate('account-a');
      final second = coordinator.activate('account-b');

      expect(same, first);
      expect(second.accountId, 'account-b');
      expect(second.epoch, first.epoch + 1);
      expect(coordinator.isCurrent(first), isFalse);
      expect(coordinator.isCurrent(second), isTrue);
    });

    test('exit quarantines synchronously and is idempotent', () async {
      final coordinator = AccountSessionCoordinator();
      addTearDown(coordinator.dispose);
      final active = coordinator.activate('account-a');
      final remoteGate = Completer<void>();
      var quarantineCount = 0;
      var remoteCount = 0;
      var localCount = 0;

      final first = coordinator.exit(
        reason: SessionExitReason.manual,
        quarantine: (_) => quarantineCount++,
        remoteCleanup: (_) async {
          remoteCount++;
          await remoteGate.future;
        },
        localCleanup: (_) async => localCount++,
      );
      final second = coordinator.exit(
        reason: SessionExitReason.forcedOffline,
        quarantine: (_) => quarantineCount++,
      );

      expect(identical(first, second), isTrue);
      expect(quarantineCount, 1);
      expect(coordinator.state.phase, AccountSessionPhase.exiting);
      expect(coordinator.state.epoch, active.epoch + 1);
      expect(coordinator.isCurrent(active), isFalse);

      remoteGate.complete();
      await first;

      expect(remoteCount, 1);
      expect(localCount, 1);
      expect(coordinator.state.phase, AccountSessionPhase.inactive);
      expect(coordinator.state.accountId, isEmpty);
    });

    test('remote cleanup failure cannot skip local cleanup', () async {
      final coordinator = AccountSessionCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.activate('account-a');
      var localRan = false;

      await coordinator.exit(
        reason: SessionExitReason.tokenExpired,
        remoteCleanup: (_) async => throw StateError('offline'),
        localCleanup: (_) async => localRan = true,
      );

      expect(localRan, isTrue);
      expect(coordinator.state.phase, AccountSessionPhase.inactive);
    });
  });
}
