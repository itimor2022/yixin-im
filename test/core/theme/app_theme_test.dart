import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:generic_im/core/theme/app_colors.dart';
import 'package:generic_im/core/theme/app_theme.dart';

void main() {
  test('light theme keeps the brand primary black', () {
    final theme = AppTheme.light;
    final scheme = theme.colorScheme;

    final filledStyle = theme.filledButtonTheme.style!;
    final filledBackground =
        filledStyle.backgroundColor!.resolve(<WidgetState>{})!;
    final filledForeground =
        filledStyle.foregroundColor!.resolve(<WidgetState>{})!;

    expect(AppColors.primary, const Color(0xFF0B0D12));
    expect(scheme.primary, AppColors.primary);
    expect(filledBackground, AppColors.primary);
    expect(filledForeground, Colors.white);
    expect(
        _contrastRatio(filledForeground, filledBackground), greaterThan(4.5));
  });

  test('dark theme keeps primary controls visible on dark surfaces', () {
    final theme = AppTheme.dark;
    final scheme = theme.colorScheme;
    final darkBackground = theme.scaffoldBackgroundColor;
    final darkSurface = scheme.surface;

    expect(_contrastRatio(scheme.primary, darkBackground), greaterThan(4.5));
    expect(_contrastRatio(scheme.primary, darkSurface), greaterThan(4.5));
    expect(
      _contrastRatio(Colors.white, AppColors.primary),
      greaterThan(4.5),
    );

    final filledStyle = theme.filledButtonTheme.style!;
    final filledBackground =
        filledStyle.backgroundColor!.resolve(<WidgetState>{})!;
    final filledForeground =
        filledStyle.foregroundColor!.resolve(<WidgetState>{})!;
    expect(
      _contrastRatio(filledBackground, AppColors.darkBackground),
      greaterThan(4.5),
    );
    expect(
        _contrastRatio(filledForeground, filledBackground), greaterThan(4.5));

    final elevatedStyle = theme.elevatedButtonTheme.style!;
    final elevatedBackground =
        elevatedStyle.backgroundColor!.resolve(<WidgetState>{})!;
    final elevatedForeground =
        elevatedStyle.foregroundColor!.resolve(<WidgetState>{})!;
    expect(
      _contrastRatio(elevatedBackground, AppColors.darkBackground),
      greaterThan(4.5),
    );
    expect(
      _contrastRatio(elevatedForeground, elevatedBackground),
      greaterThan(4.5),
    );

    final selectedNavColor = theme.bottomNavigationBarTheme.selectedItemColor!;
    final navBackground = theme.bottomNavigationBarTheme.backgroundColor!;
    expect(_contrastRatio(selectedNavColor, navBackground), greaterThan(4.5));

    final textButtonColor =
        theme.textButtonTheme.style!.foregroundColor!.resolve(<WidgetState>{})!;
    expect(_contrastRatio(textButtonColor, darkBackground), greaterThan(4.5));

    final outlinedButtonColor = theme
        .outlinedButtonTheme.style!.foregroundColor!
        .resolve(<WidgetState>{})!;
    final outlinedButtonSide =
        theme.outlinedButtonTheme.style!.side!.resolve(<WidgetState>{})!;
    expect(
      _contrastRatio(outlinedButtonColor, darkBackground),
      greaterThan(4.5),
    );
    expect(outlinedButtonSide.color, AppColors.primaryDarkModeBorder);

    final iconButtonColor =
        theme.iconButtonTheme.style!.foregroundColor!.resolve(<WidgetState>{})!;
    expect(_contrastRatio(iconButtonColor, darkBackground), greaterThan(4.5));

    final checkboxColor = theme.checkboxTheme.fillColor!
        .resolve(<WidgetState>{WidgetState.selected})!;
    final switchThumbColor =
        theme.switchTheme.thumbColor!.resolve(<WidgetState>{
      WidgetState.selected,
    })!;
    expect(checkboxColor, AppColors.primaryDarkMode);
    expect(switchThumbColor, AppColors.primaryDarkMode);
    expect(theme.sliderTheme.activeTrackColor, AppColors.primaryDarkMode);
    expect(theme.tabBarTheme.labelColor, AppColors.primaryDarkMode);
  });

  testWidgets('adaptive primary tokens switch by brightness', (tester) async {
    late Color lightPrimary;
    late Color lightOnPrimary;
    late Color darkPrimary;
    late Color darkOnPrimary;
    late Color lightLink;
    late Color darkLink;
    late Color lightInputHint;
    late Color darkInputHint;
    late Color lightControlActive;
    late Color lightOnControlActive;
    late Color darkControlActive;
    late Color darkOnControlActive;
    late Color lightEmphasisSoft;
    late Color darkEmphasisSoft;

    await tester.pumpWidget(
      MaterialApp(
        home: Theme(
          data: AppTheme.light,
          child: Builder(
            builder: (context) {
              lightPrimary = AppColors.primaryFor(context);
              lightOnPrimary = AppColors.onPrimaryFor(context);
              lightLink = AppColors.linkFor(context);
              lightInputHint = AppColors.inputHintFor(context);
              lightControlActive = AppColors.controlActiveFor(context);
              lightOnControlActive = AppColors.onControlActiveFor(context);
              lightEmphasisSoft = AppColors.emphasisSoftFor(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Theme(
          data: AppTheme.dark,
          child: Builder(
            builder: (context) {
              darkPrimary = AppColors.primaryFor(context);
              darkOnPrimary = AppColors.onPrimaryFor(context);
              darkLink = AppColors.linkFor(context);
              darkInputHint = AppColors.inputHintFor(context);
              darkControlActive = AppColors.controlActiveFor(context);
              darkOnControlActive = AppColors.onControlActiveFor(context);
              darkEmphasisSoft = AppColors.emphasisSoftFor(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(lightPrimary, AppColors.primary);
    expect(lightOnPrimary, Colors.white);
    expect(darkPrimary, AppColors.primaryDarkMode);
    expect(darkOnPrimary, AppColors.onPrimaryDarkMode);

    expect(lightLink, AppColors.primary);
    expect(darkLink, AppColors.darkLink);
    expect(lightInputHint, AppColors.lightTextSecondary);
    expect(darkInputHint, AppColors.darkTextSecondary);
    expect(lightControlActive, AppColors.primary);
    expect(lightOnControlActive, Colors.white);
    expect(darkControlActive, AppColors.primaryDarkMode);
    expect(darkOnControlActive, AppColors.onPrimaryDarkMode);
    expect(lightEmphasisSoft, AppColors.primary.withOpacity(0.08));
    expect(darkEmphasisSoft, AppColors.darkEmphasisSoft);

    expect(
      _contrastRatio(darkLink, AppColors.darkBackground),
      greaterThan(4.5),
    );
    expect(
      _contrastRatio(darkInputHint, AppColors.darkInputBackground),
      greaterThan(4.5),
    );
    expect(
      _contrastRatio(darkOnControlActive, darkControlActive),
      greaterThan(4.5),
    );
  });

  test('dark disabled button colors remain visible but subdued', () {
    final theme = AppTheme.dark;
    final disabledState = <WidgetState>{WidgetState.disabled};

    final filledStyle = theme.filledButtonTheme.style!;
    final disabledFilledBackground =
        filledStyle.backgroundColor!.resolve(disabledState)!;
    final disabledFilledForeground =
        filledStyle.foregroundColor!.resolve(disabledState)!;

    expect(disabledFilledBackground, AppColors.darkInputBackground);
    expect(disabledFilledForeground, AppColors.darkTextDisabled);
    expect(
      _contrastRatio(disabledFilledForeground, disabledFilledBackground),
      greaterThan(3),
    );

    final textButtonColor =
        theme.textButtonTheme.style!.foregroundColor!.resolve(disabledState)!;
    final iconButtonColor =
        theme.iconButtonTheme.style!.foregroundColor!.resolve(disabledState)!;
    expect(textButtonColor, AppColors.darkTextDisabled);
    expect(iconButtonColor, AppColors.darkTextDisabled);
  });
}

double _contrastRatio(Color a, Color b) {
  final aLuminance = _relativeLuminance(a);
  final bLuminance = _relativeLuminance(b);
  final lightest = math.max(aLuminance, bLuminance);
  final darkest = math.min(aLuminance, bLuminance);
  return (lightest + 0.05) / (darkest + 0.05);
}

double _relativeLuminance(Color color) {
  return 0.2126 * _linearChannel(color.red) +
      0.7152 * _linearChannel(color.green) +
      0.0722 * _linearChannel(color.blue);
}

double _linearChannel(int value) {
  final channel = value / 255;
  if (channel <= 0.03928) return channel / 12.92;
  return math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
}
