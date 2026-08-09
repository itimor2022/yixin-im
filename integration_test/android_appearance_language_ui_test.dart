import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:generic_im/core/i18n/app_localizations.dart';
import 'package:generic_im/core/router/app_router.dart';
import 'package:generic_im/core/services/api/api_client.dart';
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

  testWidgets('change language and appearance, then restore preferences',
      (tester) async {
    final preferences = await SharedPreferences.getInstance();
    final originalLanguage =
        preferences.getString('app_language') ?? AppLanguage.zhCN.code;
    final originalTheme = preferences.getString('theme_mode') ?? 'system';

    await TokenStorage.clear();
    await app.main(const <String>[]);

    final originalFlutterErrorHandler = FlutterError.onError;
    addTearDown(() {
      FlutterError.onError = originalFlutterErrorHandler;
    });
    FlutterErrorDetails? capturedError;
    FlutterError.onError = (details) {
      capturedError = details;
      FlutterError.presentError(details);
      debugPrint(
        '[Captured FlutterError] ${details.exceptionAsString()}\n'
        '${details.stack}',
      );
    };

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
    final languageIcon = find.byIcon(Icons.language_outlined);
    await tester.scrollUntilVisible(
      languageIcon,
      500,
      scrollable: settingsScrollable,
      maxScrolls: 10,
    );
    await tester.tap(languageIcon.hitTestable());
    await _pumpUntilVisible(
      tester,
      find.text('English').hitTestable(),
      timeout: const Duration(seconds: 5),
    );
    await tester.tap(find.text('English').hitTestable());
    await _pumpUntilVisible(
      tester,
      find.text('Language'),
      timeout: const Duration(seconds: 5),
    );
    await _waitForPreference(
      tester,
      preferences,
      key: 'app_language',
      value: AppLanguage.en.code,
    );

    final appearanceIcon = find.byIcon(Icons.brightness_6_outlined);
    await tester.tap(appearanceIcon.hitTestable());
    await _pumpUntilVisible(
      tester,
      find.text('Light').hitTestable(),
      timeout: const Duration(seconds: 5),
    );
    await tester.tap(find.text('Light').hitTestable());
    await _pumpUntil(
      tester,
      () => _settingsBrightness(tester) == Brightness.light,
      timeout: const Duration(seconds: 5),
      failure: 'Expected SettingsPage to use the light theme.',
    );
    await _waitForPreference(
      tester,
      preferences,
      key: 'theme_mode',
      value: 'light',
    );

    await tester.tap(appearanceIcon.hitTestable());
    await _pumpUntilVisible(
      tester,
      find.text('Dark').hitTestable(),
      timeout: const Duration(seconds: 5),
    );
    await tester.tap(find.text('Dark').hitTestable());
    await _pumpUntil(
      tester,
      () => _settingsBrightness(tester) == Brightness.dark,
      timeout: const Duration(seconds: 5),
      failure: 'Expected SettingsPage to use the dark theme.',
    );
    await _waitForPreference(
      tester,
      preferences,
      key: 'theme_mode',
      value: 'dark',
    );

    await tester.tap(appearanceIcon.hitTestable());
    await _pumpUntilVisible(
      tester,
      find.text(_englishThemeLabel(originalTheme)).hitTestable(),
      timeout: const Duration(seconds: 5),
    );
    await tester.tap(
      find.text(_englishThemeLabel(originalTheme)).hitTestable(),
    );
    await _waitForPreference(
      tester,
      preferences,
      key: 'theme_mode',
      value: originalTheme,
    );

    await tester.tap(languageIcon.hitTestable());
    final originalLanguageLabel =
        AppLanguage.fromCode(originalLanguage).displayName;
    await _pumpUntilVisible(
      tester,
      find.text(originalLanguageLabel).hitTestable(),
      timeout: const Duration(seconds: 5),
    );
    await tester.tap(find.text(originalLanguageLabel).hitTestable());
    await _waitForPreference(
      tester,
      preferences,
      key: 'app_language',
      value: originalLanguage,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final error = capturedError;
    FlutterError.onError = originalFlutterErrorHandler;
    expect(error, isNull);
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

  final submitFinder = find.byKey(const Key('login_submit_button'));
  await tester.ensureVisible(submitFinder);
  await tester.tap(submitFinder.hitTestable());
  await _pumpUntilGone(
    tester,
    submitFinder,
    timeout: const Duration(seconds: 35),
  );
}

Future<void> _dismissMultiDeviceNotice(WidgetTester tester) async {
  final noticeButton =
      find.textContaining(RegExp(r'我知道了|Got it')).hitTestable();
  if (!await _waitFor(
    tester,
    () => noticeButton.evaluate().isNotEmpty,
    timeout: const Duration(seconds: 3),
  )) {
    return;
  }
  await tester.tap(noticeButton);
  await _pumpUntilGone(
    tester,
    noticeButton,
    timeout: const Duration(seconds: 5),
  );
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

Brightness _settingsBrightness(WidgetTester tester) {
  return Theme.of(tester.element(find.byType(SettingsPage))).brightness;
}

String _englishThemeLabel(String theme) {
  return switch (theme) {
    'light' => 'Light',
    'dark' => 'Dark',
    _ => 'System',
  };
}

Future<void> _waitForPreference(
  WidgetTester tester,
  SharedPreferences preferences, {
  required String key,
  required String value,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    await preferences.reload();
    if (preferences.getString(key) == value) return;
  }
  fail('Expected preference $key to equal $value.');
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
