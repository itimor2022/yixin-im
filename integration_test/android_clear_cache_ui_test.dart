import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:generic_im/core/router/app_router.dart';
import 'package:generic_im/core/services/api/api_client.dart';
import 'package:generic_im/features/settings/pages/data_storage_page.dart';
import 'package:generic_im/features/settings/pages/settings_page.dart';
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

  testWidgets('clear cache from data storage keeps the UI healthy',
      (tester) async {
    await TokenStorage.clear();
    final testFlutterErrorHandler = FlutterError.onError;
    await app.main(const <String>[]);
    FlutterError.onError = testFlutterErrorHandler;

    await _login(tester);
    await _dismissMultiDeviceNotice(tester);

    final rootContext =
        await _rootContext(timeout: const Duration(seconds: 10));
    unawaited(
      Navigator.of(rootContext).push(
        MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
      ),
    );
    await _pumpUntilVisible(
      tester,
      find.byType(SettingsPage),
      timeout: const Duration(seconds: 10),
    );

    final settingsScrollable = find.descendant(
      of: find.byType(SettingsPage),
      matching: find.byType(Scrollable),
    );
    final storageIcon = find.byIcon(Icons.cloud_outlined);
    await tester.scrollUntilVisible(
      storageIcon,
      500,
      scrollable: settingsScrollable,
      maxScrolls: 10,
    );
    await tester.tap(storageIcon.hitTestable());
    await _pumpUntilVisible(
      tester,
      find.byType(DataStoragePage),
      timeout: const Duration(seconds: 10),
    );

    final clearButton = find.text('清除缓存').hitTestable();
    await _pumpUntilVisible(tester, clearButton,
        timeout: const Duration(seconds: 5));
    await tester.tap(clearButton);
    await _pumpUntilVisible(
      tester,
      find.text('确定要清除所有缓存数据吗？\n\n这将删除临时文件，但不会影响你的聊天记录。'),
      timeout: const Duration(seconds: 5),
    );
    await tester.tap(find.text('清除').hitTestable().last);
    await _pumpUntilVisible(
      tester,
      find.text('缓存已清除'),
      timeout: const Duration(seconds: 10),
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

Future<void> _login(WidgetTester tester) async {
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
  final termsFinder = find.byKey(const Key('login_terms_checkbox'));
  await tester.ensureVisible(termsFinder);
  await tester.tap(termsFinder.hitTestable());
  await tester.pump(const Duration(milliseconds: 250));
  final submitFinder =
      find.byKey(const Key('login_submit_button')).hitTestable();
  await tester.ensureVisible(submitFinder);
  await tester.tap(submitFinder);
  await _pumpUntilGone(tester, submitFinder,
      timeout: const Duration(seconds: 35));
}

Future<void> _dismissMultiDeviceNotice(WidgetTester tester) async {
  final noticeButton =
      find.textContaining(RegExp(r'我知道了|Got it')).hitTestable();
  if (!await _waitFor(
    tester,
    () => noticeButton.evaluate().isNotEmpty,
    timeout: const Duration(seconds: 3),
  )) return;
  await tester.tap(noticeButton);
  await _pumpUntilGone(tester, noticeButton,
      timeout: const Duration(seconds: 5));
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

Future<void> _pumpUntilVisible(WidgetTester tester, Finder finder,
    {required Duration timeout}) async {
  await _pumpUntil(tester, () => finder.evaluate().isNotEmpty,
      timeout: timeout,
      failure: 'Expected ${finder.description} to be visible.');
}

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder,
    {required Duration timeout}) async {
  await _pumpUntil(tester, () => finder.evaluate().isEmpty,
      timeout: timeout,
      failure: 'Expected ${finder.description} to disappear.');
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() condition,
    {required Duration timeout, required String failure}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return;
  }
  fail(failure);
}

Future<bool> _waitFor(WidgetTester tester, bool Function() condition,
    {required Duration timeout}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return true;
  }
  return false;
}
