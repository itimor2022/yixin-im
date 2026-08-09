import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/features/chat/providers/message_provider.dart';
import 'package:generic_im/features/chat/widgets/message_bubble.dart';

void main() {
  testWidgets('voice route control does not trigger playback', (tester) async {
    final message = MessageItem(
      id: 'voice-control-test',
      chatId: 'chat-1',
      senderId: 'user-2',
      senderName: 'User 2',
      type: MessageItemType.voice,
      content: '',
      mediaUrl: 'https://example.com/voice.m4a',
      mediaDuration: 3000,
      isOutgoing: false,
      createdAt: DateTime(2026, 7, 16, 17),
      seq: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: MessageBubble(
              message: message,
              voicePlaylist: [message],
            ),
          ),
        ),
      ),
    );

    expect(find.bySemanticsLabel('当前为扬声器，点击切换听筒'), findsOneWidget);
    expect(find.bySemanticsLabel('正在播放语音'), findsNothing);

    await tester
        .tap(find.byKey(const ValueKey('voice_route_voice-control-test')));
    await tester.pump();

    expect(find.bySemanticsLabel('当前为听筒，点击切换扬声器'), findsOneWidget);
    expect(find.bySemanticsLabel('正在播放语音'), findsNothing);
  });
}
