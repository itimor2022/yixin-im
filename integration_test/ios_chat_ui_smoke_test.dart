import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter/foundation.dart';
import 'package:generic_im/core/router/app_router.dart';
import 'package:generic_im/core/services/api/api_client.dart';
import 'package:generic_im/main.dart' as app;

const _username = String.fromEnvironment(
  'GENERIC_IM_SMOKE_ALICE_USERNAME',
  defaultValue: 'smoke_alice',
);
const _password = String.fromEnvironment(
  'GENERIC_IM_SMOKE_PASSWORD',
  defaultValue: 'Smoke123',
);
const _chatId = String.fromEnvironment('GENERIC_IM_SMOKE_CHAT_ID');
const _chatName = String.fromEnvironment(
  'GENERIC_IM_SMOKE_CHAT_NAME',
  defaultValue: 'smoke_bob',
);
const _message = String.fromEnvironment(
  'GENERIC_IM_SMOKE_MESSAGE',
  defaultValue: 'codex ios ui smoke',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login, enter private chat, and send text', (tester) async {
    if (_chatId.trim().isEmpty) {
      fail('GENERIC_IM_SMOKE_CHAT_ID is required.');
    }

    await TokenStorage.clear();
    await app.main(const <String>[]);

    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('login_username_field')).hitTestable(),
      timeout: const Duration(seconds: 35),
    );
    await tester.enterText(
      find.byKey(const Key('login_username_field')).hitTestable(),
      _username,
    );
    await tester.enterText(
      find.byKey(const Key('login_password_field')).hitTestable(),
      _password,
    );
    final termsFinder = find.byKey(const Key('login_terms_checkbox'));
    await tester.ensureVisible(termsFinder);
    await tester.tap(termsFinder.hitTestable());
    await tester.pump(const Duration(milliseconds: 250));
    final submitFinder = find.byKey(const Key('login_submit_button'));
    await tester.ensureVisible(submitFinder);
    await tester.tap(submitFinder.hitTestable());

    await _pumpUntilGone(
      tester,
      find.byKey(const Key('login_submit_button')),
      timeout: const Duration(seconds: 35),
    );

    final rootContext =
        await _rootContext(timeout: const Duration(seconds: 10));
    rootContext.go(
      '/chat/$_chatId?name=${Uri.encodeComponent(_chatName)}&type=private',
    );

    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('chat_message_input')),
      timeout: const Duration(seconds: 35),
    );
    await tester.enterText(
      find.byKey(const Key('chat_message_input')),
      _message,
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.testTextInput.receiveAction(TextInputAction.send);

    await _pumpUntil(
      tester,
      () {
        final input = tester.widget<TextField>(
          find.byKey(const Key('chat_message_input')),
        );
        return input.controller?.text.isEmpty ?? false;
      },
      timeout: const Duration(seconds: 10),
      failure: 'Expected chat input to clear after sending.',
    );

    await _pumpUntilVisible(
      tester,
      find.text(_message),
      timeout: const Duration(seconds: 20),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    await tester.pump();
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await binding.convertFlutterSurfaceToImage();
      await binding.takeScreenshot('ios_chat_ui_smoke');
    }
  });
}

Future<BuildContext> _rootContext({required Duration timeout}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final context = rootNavigatorKey.currentContext;
    if (context != null) return context;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw TimeoutException('Root navigator context was not ready.', timeout);
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
}) async {
  await _pumpUntil(
    tester,
    () => finder.evaluate().isNotEmpty,
    timeout: timeout,
    failure: 'Expected ${finder.description} to be visible.',
  );
}

Future<void> _pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
}) async {
  await _pumpUntil(
    tester,
    () => finder.evaluate().isEmpty,
    timeout: timeout,
    failure: 'Expected ${finder.description} to disappear.',
  );
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String failure,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return;
  }
  fail(failure);
}
