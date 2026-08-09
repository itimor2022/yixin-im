import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/features/contacts/providers/contact_provider.dart';

void main() {
  test('friend request parses direction, status, message and peer profile', () {
    final request = FriendRequestItem.fromJson({
      'id': 'request-1',
      'direction': 'incoming',
      'status': 'pending',
      'message': 'Please add me',
      'expires_at': '2026-07-25T12:00:00Z',
      'created_at': '2026-07-18T12:00:00Z',
      'user': {
        'id': 7,
        'uuid': 'user-7',
        'nickname': 'Peer',
        'username': 'peer_7',
      },
    });

    expect(request.id, 'request-1');
    expect(request.isPending, isTrue);
    expect(request.message, 'Please add me');
    expect(request.user.uuid, 'user-7');
    expect(request.user.name, 'Peer');
  });
}
