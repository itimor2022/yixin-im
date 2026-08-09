import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/theme/system_ui_styles.dart';

void main() {
  test('uses light status icons on dark and saturated headers', () {
    expect(
      AppSystemUiStyles.forBackground(const Color(0xFF0B0D12)),
      same(AppSystemUiStyles.onDarkBackground),
    );
    expect(
      AppSystemUiStyles.onDarkBackground.statusBarIconBrightness,
      Brightness.light,
    );
    expect(
      AppSystemUiStyles.onDarkBackground.statusBarColor,
      Colors.transparent,
    );
  });

  test('uses dark status icons on light headers', () {
    expect(
      AppSystemUiStyles.forBackground(const Color(0xFFF6F7F9)),
      same(AppSystemUiStyles.onLightBackground),
    );
    expect(
      AppSystemUiStyles.onLightBackground.statusBarIconBrightness,
      Brightness.dark,
    );
  });

  test('wallet uses a distinct status bar with light icons', () {
    expect(
      AppSystemUiStyles.onWalletBackground.statusBarColor,
      AppSystemUiStyles.walletStatusBarColor,
    );
    expect(
      AppSystemUiStyles.onWalletBackground.statusBarIconBrightness,
      Brightness.light,
    );
    expect(
      ThemeData.estimateBrightnessForColor(
        AppSystemUiStyles.walletStatusBarColor,
      ),
      Brightness.dark,
    );
  });

  test('does not force the bottom navigation-bar icon brightness', () {
    expect(
      AppSystemUiStyles.onDarkBackground.systemNavigationBarIconBrightness,
      isNull,
    );
    expect(
      AppSystemUiStyles.onLightBackground.systemNavigationBarIconBrightness,
      isNull,
    );
  });
}
