import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:generic_im/core/router/app_router.dart';
import 'package:generic_im/core/services/api/api_client.dart';
import 'package:generic_im/features/settings/pages/devices_page.dart';
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

  testWidgets('login, log out from devices, and stay signed out',
      (tester) async {
    await TokenStorage.clear();
    await app.main(const <String>[]);

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

    final submitFinder = find.byKey(const Key('login_submit_button'));
    await tester.ensureVisible(submitFinder);
    await tester.tap(submitFinder.hitTestable());
    await _pumpUntilGone(
      tester,
      submitFinder,
      timeout: const Duration(seconds: 35),
    );

    final multiDeviceNotice = find.text('我知道了').hitTestable();
    if (await _waitFor(
      tester,
      () => multiDeviceNotice.evaluate().isNotEmpty,
      timeout: const Duration(seconds: 3),
    )) {
      await tester.tap(multiDeviceNotice);
      await _pumpUntilGone(
        tester,
        multiDeviceNotice,
        timeout: const Duration(seconds: 5),
      );
    }

    final rootContext =
        await _rootContext(timeout: const Duration(seconds: 10));
    unawaited(
      Navigator.of(rootContext).push(
        MaterialPageRoute<void>(builder: (_) => const DevicesPage()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final logoutIcon = find.byIcon(Icons.logout_rounded);
    await tester.scrollUntilVisible(
      logoutIcon,
      700,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 30,
    );
    await tester.tap(logoutIcon.hitTestable());
    await _pumpUntilVisible(
      tester,
      find.text('取消').hitTestable(),
      timeout: const Duration(seconds: 5),
    );
    await tester.tap(find.text('退出登录').hitTestable().last);

    await _pumpUntilVisible(
      tester,
      find.byKey(const Key('login_username_field')).hitTestable(),
      timeout: const Duration(seconds: 35),
    );
    expect(await TokenStorage.getToken(), isNull);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      find.byKey(const Key('login_username_field')).hitTestable(),
      findsOneWidget,
    );
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

Future<bool> _waitFor(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (condition()) return true;
  }
  return false;
}
