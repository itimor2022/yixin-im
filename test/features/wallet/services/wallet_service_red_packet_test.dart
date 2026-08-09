import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/features/wallet/services/wallet_service.dart';

void main() {
  group('RedPacketDetail.fromJson', () {
    test('parses summary and claim list', () {
      final detail = RedPacketDetail.fromJson({
        'id': 'packet-1',
        'sender_id': 'sender-1',
        'sender_name': 'Sender',
        'chat_id': 'chat-1',
        'type': 'lucky',
        'total_amount': 20,
        'total_count': 3,
        'remaining_amount': 5.5,
        'remaining_count': 1,
        'message': 'Best wishes',
        'status': 'active',
        'is_sender': true,
        'is_claimed': false,
        'claimed_count': 2,
        'claimed_total_amount': 14.5,
        'created_at': '2026-07-16T10:00:00+08:00',
        'claims': [
          {
            'id': '10',
            'red_packet_id': 'packet-1',
            'user_id': 'user-1',
            'user_name': 'Alice',
            'user_avatar': '',
            'amount': 9.5,
            'is_best': true,
            'created_at': '2026-07-16T10:01:00+08:00',
          },
          {
            'id': 11,
            'red_packet_id': 'packet-1',
            'user_id': 'user-2',
            'user_name': 'Bob',
            'user_avatar': '',
            'amount': 5,
            'is_best': false,
            'created_at': '2026-07-16T10:02:00+08:00',
          },
        ],
      });

      expect(detail.redPacket.id, 'packet-1');
      expect(detail.redPacket.type, RedPacketType.lucky);
      expect(detail.claimedCount, 2);
      expect(detail.claimedTotalAmount, 14.5);
      expect(detail.isSender, isTrue);
      expect(detail.claims, hasLength(2));
      expect(detail.claims.first.isBest, isTrue);
      expect(detail.claims.last.id, '11');
      expect(detail.claims.last.amount, 5);
    });

    test('falls back to remaining values for older backend responses', () {
      final detail = RedPacketDetail.fromJson({
        'id': 'packet-2',
        'sender_id': 'sender-1',
        'sender_name': 'Sender',
        'chat_id': 'chat-1',
        'type': 'normal',
        'total_amount': 10,
        'total_count': 5,
        'remaining_amount': 4,
        'remaining_count': 2,
        'message': 'Best wishes',
        'status': 'active',
        'is_claimed': false,
        'created_at': '2026-07-16T10:00:00+08:00',
      });

      expect(detail.claimedCount, 3);
      expect(detail.claimedTotalAmount, 6);
      expect(detail.claims, isEmpty);
      expect(detail.isSender, isFalse);
    });
  });
}
