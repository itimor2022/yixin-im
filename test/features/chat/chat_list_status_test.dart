import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/i18n/app_localizations.dart';
import 'package:generic_im/features/chat/providers/chat_provider.dart';
import 'package:generic_im/features/chat/widgets/chat_list_item.dart';

void main() {
  test('unread badge caps display without losing the authoritative count', () {
    expect(formatUnreadBadgeCount(0), '');
    expect(formatUnreadBadgeCount(1), '1');
    expect(formatUnreadBadgeCount(99), '99');
    expect(formatUnreadBadgeCount(100), '99+');
    expect(formatUnreadBadgeCount(1000), '99+');
  });

  testWidgets('failed last message is visible even when a draft was restored',
      (tester) async {
    AppLocalizations.setCurrentLanguage(AppLanguage.zhCN);
    final chat = ChatItem(
      id: 'chat-1',
      name: 'Peer',
      lastMessage: 'failed message',
      lastMessageTime: DateTime.now(),
      lastMessageFailed: true,
      isSentByMe: true,
      draft: 'failed message',
      type: ChatItemType.private,
      createdAt: DateTime(2026, 7, 18),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: ChatListItem(chat: chat),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(
      find.textContaining('发送失败', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('草稿', findRichText: true), findsNothing);
  });
}
