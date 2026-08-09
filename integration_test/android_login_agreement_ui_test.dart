import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login requires accepting the terms', (tester) async {
    await TokenStorage.clear();
    await app.main(const <String>[]);
    FlutterErrorDetails? capturedError;
    FlutterError.onError = (details) {
      capturedError = details;
      FlutterError.presentError(details);
      debugPrint(
        '[Captured FlutterError] ${details.exceptionAsString()}\n'
        '${details.stack}',
      );
    };

    final usernameFinder =
        find.byKey(const Key('login_username_field')).hitTestable();
    await _pumpUntilVisible(
      tester,
      usernameFinder,
      timeout: const Duration(seconds: 35),
    );
    await tester.enterText(usernameFinder, _username);
    await tester.enterText(
      find.byKey(const Key('login_password_field')).hitTestable(),
      _password,
    );

    final submitFinder =
        find.byKey(const Key('login_submit_button')).hitTestable();
    await tester.ensureVisible(submitFinder);
    await tester.tap(submitFinder);

    await _pumpUntilVisible(
      tester,
      find.text('请先阅读并同意用户协议和隐私政策'),
      timeout: const Duration(seconds: 5),
    );
    expect(submitFinder, findsOneWidget);
    expect(await TokenStorage.getToken(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(capturedError, isNull);
  });
}

Future<void> _pumpUntilVisible(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Expected ${finder.description} to be visible.');
}
