import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/services/android_callkit_helper.dart';

void main() {
  final now = DateTime.utc(2026, 7, 16, 12, 0, 30);

  Map<String, dynamic> payload(Object? expiresAt) => <String, dynamic>{
        'type': 'incoming_call',
        'call_id': 305,
        'caller_id': 'caller-1',
        'caller_name': 'Caller',
        'channel_name': 'call-channel',
        if (expiresAt != null) 'expires_at': expiresAt,
      };

  test('incoming call expiry accepts RFC3339 and Unix timestamps', () {
    expect(
      incomingCallPayloadIsExpired(
        payload('2026-07-16T12:00:29Z'),
        now: now,
      ),
      isTrue,
    );
    expect(
      incomingCallPayloadIsExpired(payload('1784203229'), now: now),
      isTrue,
    );
    expect(
      incomingCallPayloadIsExpired(payload(1784203231000), now: now),
      isFalse,
    );
  });

  test('legacy and invalid expiry keep the compatibility window', () {
    expect(
      incomingCallDisplayDuration(payload(null), now: now),
      kIncomingCallkitDuration,
    );
    expect(
      incomingCallDisplayDuration(payload('invalid'), now: now),
      kIncomingCallkitDuration,
    );
    expect(
      incomingCallDisplayDuration(
        payload('999999999999999999999999'),
        now: now,
      ),
      kIncomingCallkitDuration,
    );
  });

  test('callkit duration is clipped to the authoritative remaining time', () {
    expect(
      incomingCallDisplayDuration(
        payload('2026-07-16T12:00:42Z'),
        now: now,
      ),
      const Duration(seconds: 12),
    );
    expect(
      incomingCallDisplayDuration(
        payload('2026-07-16T12:02:00Z'),
        now: now,
      ),
      kIncomingCallkitDuration,
    );
    expect(
      incomingCallDisplayDuration(
        payload('2026-07-16T12:00:29Z'),
        now: now,
      ),
      Duration.zero,
    );
  });

  test('callkit params use the remaining expiry duration', () {
    final params = buildAndroidIncomingCallParams(
      payload('2026-07-16T12:00:37Z'),
      uuid: 'call-305',
      now: now,
    );

    expect(params.id, 'call-305');
    expect(params.duration, 7000);
    expect(params.extra?['expires_at'], '2026-07-16T12:00:37Z');
  });

  test('background incoming call obeys the notification master switch', () {
    expect(
      shouldShowAndroidIncomingCallNotification(
        payload('2026-07-16T12:00:37Z'),
        masterEnabled: true,
        now: now,
      ),
      isTrue,
    );
    expect(
      shouldShowAndroidIncomingCallNotification(
        payload('2026-07-16T12:00:37Z'),
        masterEnabled: false,
        now: now,
      ),
      isFalse,
    );
    expect(
      shouldShowAndroidIncomingCallNotification(
        payload('2026-07-16T12:00:29Z'),
        masterEnabled: true,
        now: now,
      ),
      isFalse,
    );
  });

  test('callkit returns before display when the master switch is disabled',
      () async {
    var reads = 0;
    await showAndroidIncomingCallFromPayload(
      payload('2026-07-16T12:00:37Z'),
      notificationMasterEnabled: () async {
        reads += 1;
        return false;
      },
    );

    expect(reads, 1);
  });

  test('callkit rechecks the master switch immediately before display',
      () async {
    var reads = 0;
    await showAndroidIncomingCallFromPayload(
      payload(DateTime.now().toUtc().add(const Duration(seconds: 20))),
      notificationMasterEnabled: () async {
        reads += 1;
        return reads == 1;
      },
    );

    expect(reads, 2);
  });
}
