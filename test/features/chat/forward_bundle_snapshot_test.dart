import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/features/chat/models/forward_bundle_snapshot.dart';

void main() {
  test('parses ordered fields and opens nested immutable snapshot', () {
    final bundle = ForwardBundleSnapshot.fromJson({
      'title': 'Alice and Bob chat history',
      'items': [
        {
          'source_message_id': 'first',
          'type': 1,
          'sender_name': 'Alice',
          'created_at': '2026-07-16T12:00:00Z',
          'content': {'text': 'hello'},
        },
        {
          'source_message_id': 'nested',
          'type': 14,
          'sender_name': 'Bob',
          'created_at': '2026-07-16T12:01:00Z',
          'content': {
            'forward_bundle': {
              'title': 'Nested history',
              'items': [
                {
                  'source_message_id': 'photo',
                  'type': 2,
                  'sender_name': 'Carol',
                  'created_at': '2026-07-16T11:59:00Z',
                  'content': {},
                },
              ],
            },
          },
        },
      ],
    });

    expect(
        bundle.items.map((item) => item.sourceMessageId), ['first', 'nested']);
    expect(bundle.items.first.preview(english: false), 'hello');
    expect(bundle.items.last.nestedBundle!.items.single.preview(english: false),
        '[图片]');
  });
}
