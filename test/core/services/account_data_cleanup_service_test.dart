import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:generic_im/core/services/account_data_cleanup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('account preference deletion set never includes another account', () {
    const accountA = 'account-a';
    const accountB = 'account-b';
    final prefixA = accountStoragePrefix(accountA);
    final prefixB = accountStoragePrefix(accountB);
    final keys = <String>{
      '${prefixA}offline_message_queue',
      '${prefixA}favorite_messages_v1',
      '${prefixB}offline_message_queue',
      'favorite_messages_v1_$accountA',
      'favorite_messages_v1_$accountB',
      'theme_mode',
    };

    expect(
      accountPreferenceDeletionSet(keys, accountA),
      <String>{
        '${prefixA}offline_message_queue',
        '${prefixA}favorite_messages_v1',
        'favorite_messages_v1_$accountA',
      },
    );
  });

  test('purge journal preserves the resumable stage', () {
    final createdAt = DateTime.utc(2026, 7, 14, 10, 30);
    final journal = AccountPurgeJournal(
      accountId: 'account-a',
      stage: AccountPurgeStage.offlineQueueDeleted,
      createdAt: createdAt,
    );

    final restored = AccountPurgeJournal.fromJson(
      Map<String, dynamic>.from(
        jsonDecode(jsonEncode(journal.toJson())) as Map,
      ),
    );

    expect(restored.accountId, 'account-a');
    expect(restored.stage, AccountPurgeStage.offlineQueueDeleted);
    expect(restored.createdAt, createdAt);
  });

  test('scheduling is idempotent but cannot replace another account', () async {
    final service = AccountDataCleanupService();
    await service.scheduleAccountPurge('account-a');
    await service.scheduleAccountPurge('account-a');

    final pending = await service.pendingJournal();
    expect(pending?.accountId, 'account-a');
    expect(pending?.stage, AccountPurgeStage.scheduled);

    await expectLater(
      service.scheduleAccountPurge('account-b'),
      throwsStateError,
    );
  });

  test('a completed interrupted purge removes its journal', () async {
    final prefs = await SharedPreferences.getInstance();
    final journal = AccountPurgeJournal(
      accountId: 'account-a',
      stage: AccountPurgeStage.mediaDeleted,
      createdAt: DateTime.utc(2026, 7, 14),
    );
    await prefs.setString(
      AccountDataCleanupService.journalPreferenceKey,
      jsonEncode(journal.toJson()),
    );

    final result = await AccountDataCleanupService().resumePendingPurge();

    expect(result.success, isTrue);
    expect(result.accountId, 'account-a');
    expect(
      prefs.containsKey(AccountDataCleanupService.journalPreferenceKey),
      isFalse,
    );
  });
}
