import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/features/chat/utils/message_revoke_policy.dart';

void main() {
  test('allows recall immediately before the configured boundary', () {
    final now = DateTime(2026, 7, 16, 18, 0);

    expect(
      isWithinMessageRevokeWindow(
        createdAt: now
            .subtract(const Duration(minutes: 2))
            .add(const Duration(milliseconds: 1)),
        now: now,
        revokeMinutes: 2,
      ),
      isTrue,
    );
  });

  test('marks recall unavailable at the exact configured boundary', () {
    final now = DateTime(2026, 7, 16, 18, 0);

    expect(
      isWithinMessageRevokeWindow(
        createdAt: now.subtract(const Duration(minutes: 2)),
        now: now,
        revokeMinutes: 2,
      ),
      isFalse,
    );
  });

  test('falls back to the two-minute product default', () {
    final now = DateTime(2026, 7, 16, 18, 0);

    expect(
      isWithinMessageRevokeWindow(
        createdAt: now.subtract(const Duration(seconds: 119)),
        now: now,
        revokeMinutes: 0,
      ),
      isTrue,
    );
  });

  test('classifies an admin revoke before outgoing ownership', () {
    expect(
      classifyRevokedMessageActor(
        isGroup: true,
        isOutgoing: true,
        senderId: 'original-sender',
        revokedBy: 'group-admin',
        currentUserId: 'original-sender',
      ),
      RevokedMessageActor.admin,
    );
  });

  test('classifies the sender own revoke as self', () {
    expect(
      classifyRevokedMessageActor(
        isGroup: true,
        isOutgoing: true,
        senderId: 'sender',
        revokedBy: 'sender',
        currentUserId: 'sender',
      ),
      RevokedMessageActor.self,
    );
  });
}
