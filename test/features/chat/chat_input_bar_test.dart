import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/features/chat/widgets/chat_input_bar.dart';

void main() {
  testWidgets('hides attachment button when no attachment action is available',
      (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            onSend: (_, {refocusInput}) {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('chat_attachment_button')), findsNothing);
  });

  testWidgets('shows attachment button when callback is provided',
      (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            onSend: (_, {refocusInput}) {},
            onAttachment: () {},
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('chat_attachment_button')), findsOneWidget);
  });

  testWidgets('mobile trailing enter uses the same send callback',
      (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final sent = <String>[];
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInputBar(
            controller: controller,
            focusNode: focusNode,
            onSend: (value, {refocusInput}) => sent.add(value),
          ),
        ),
      ),
    );

    final input = find.byKey(const Key('chat_message_input'));
    await tester.tap(input);
    await tester.enterText(input, 'IME send');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sent, ['IME send']);
  });
}
