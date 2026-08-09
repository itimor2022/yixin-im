import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/utils/qr_payload.dart';

void main() {
  group('OneChat QR payload', () {
    test('builds and parses user payload', () {
      const userId = 'user-uuid-1';

      final payload = parseOneChatQrPayload(buildUserQrPayload(userId));

      expect(payload, isNotNull);
      expect(payload!.type, OneChatQrType.user);
      expect(payload.id, userId);
    });

    test('parses path-style custom scheme payload', () {
      final payload = parseOneChatQrPayload('genericim:///user/user-uuid-2');

      expect(payload, isNotNull);
      expect(payload!.type, OneChatQrType.user);
      expect(payload.id, 'user-uuid-2');
    });

    test('builds and parses group invite payload', () {
      const inviteLink = 'invite123';

      final payload = parseOneChatQrPayload(buildGroupQrPayload(inviteLink));

      expect(payload, isNotNull);
      expect(payload!.type, OneChatQrType.group);
      expect(payload.id, inviteLink);
    });

    test('builds and parses login payload', () {
      const ticket = 'login-ticket-1';

      final payload = parseOneChatQrPayload(buildLoginQrPayload(ticket));

      expect(payload, isNotNull);
      expect(payload!.type, OneChatQrType.login);
      expect(payload.id, ticket);
    });

    test('rejects unsupported or incomplete payloads', () {
      expect(parseOneChatQrPayload(''), isNull);
      expect(parseOneChatQrPayload('https://example.com/user/1'), isNull);
      expect(parseOneChatQrPayload('genericim://unknown/1'), isNull);
      expect(parseOneChatQrPayload('genericim://user'), isNull);
    });
  });
}
