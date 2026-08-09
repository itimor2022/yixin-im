import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/features/chat/services/message_detail_service.dart';

void main() {
  test('parses authoritative receipt summary and member states', () {
    final detail = MessageDetailData.fromJson({
      'message': {
        'message_id': 'message-220',
        'chat_id': 'chat-220',
        'seq': 220,
        'type': 1,
        'status': 'read',
        'created_at': '2026-07-16T14:20:00Z',
        'updated_at': '2026-07-16T14:21:00Z',
      },
      'receipts': {
        'recipient_count': 2,
        'read_count': 1,
        'unread_count': 1,
        'delivered_count': 1,
        'delivery_count_known': false,
        'can_view_members': true,
        'member_protection_on': true,
        'members': [
          {
            'user_id': 'reader-a',
            'nickname': 'Reader A',
            'avatar': '',
            'role': 0,
            'read': true,
            'delivered': true,
            'delivered_known': true,
          },
        ],
      },
    });

    expect(detail.messageId, 'message-220');
    expect(detail.seq, 220);
    expect(detail.status, 'read');
    expect(detail.receipts.readCount, 1);
    expect(detail.receipts.deliveryCountKnown, isFalse);
    expect(detail.receipts.members.single.isRead, isTrue);
  });

  test('drops member payload when server denies member visibility', () {
    final summary = MessageReceiptSummary.fromJson({
      'recipient_count': 8,
      'read_count': 3,
      'unread_count': 5,
      'can_view_members': false,
      'members': [
        {'user_id': 'must-not-leak', 'nickname': 'Hidden'},
      ],
    });

    expect(summary.canViewMembers, isFalse);
    expect(summary.members, isEmpty);
    expect(summary.recipientCount, 8);
  });
}
