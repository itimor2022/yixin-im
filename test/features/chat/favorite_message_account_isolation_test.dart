import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:generic_im/features/chat/services/favorite_message_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('favorites never scan another account or the unowned legacy key',
      () async {
    final encoded = jsonEncode([_favoriteJson('message-b')]);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'favorite_messages_v1': encoded,
      'favorite_messages_v1_account-b': encoded,
    });

    final favorites = await FavoriteMessageService().loadFavorites('account-a');

    expect(favorites, isEmpty);
  });

  test('exact legacy account key migrates to the hashed account key', () async {
    final encoded = jsonEncode([_favoriteJson('message-a')]);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'favorite_messages_v1_account-a': encoded,
    });

    final favorites = await FavoriteMessageService().loadFavorites('account-a');
    final prefs = await SharedPreferences.getInstance();
    final accountHash = sha256.convert(utf8.encode('account-a'));

    expect(favorites.map((item) => item.messageId), ['message-a']);
    expect(
      prefs.getString('acct_v1_${accountHash}_favorite_messages_v1'),
      isNotNull,
    );
    expect(prefs.containsKey('favorite_messages_v1_account-a'), isFalse);
  });
}

Map<String, dynamic> _favoriteJson(String messageId) {
  return <String, dynamic>{
    'message_id': messageId,
    'chat_id': 'chat-1',
    'chat_name': 'Chat',
    'sender_id': 'sender-1',
    'sender_name': 'Sender',
    'message_type': 'text',
    'content': 'hello',
    'created_at': '2026-07-14T00:00:00.000Z',
    'collected_at': '2026-07-14T00:00:00.000Z',
  };
}
