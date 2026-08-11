import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';
import 'app_theme_preset.dart';

class AppTheme {
  AppTheme._();

  /// 根据预设 + 亮暗模式生成 ThemeData
  static ThemeData build(AppThemeColors c, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final primary = c.primaryA;
    final onPrimary = isDark ? c.darkOnPrimary : c.lightOnPrimary;
    final background = isDark ? c.darkBackground : c.lightBackground;
    final surface = isDark ? c.darkSurface : c.lightSurface;
    final card = isDark ? c.darkCard : c.lightCard;
    final appBar = isDark ? c.darkAppBar : c.lightAppBar;
    final navBar = isDark ? c.darkNavBar : c.lightNavBar;
    final inputBg = isDark ? c.darkInputBackground : c.lightInputBackground;
    final divider = isDark ? c.darkDivider : c.lightDivider;
    final textPrimary = isDark ? c.darkTextPrimary : c.lightTextPrimary;
    final textSecondary = isDark ? c.darkTextSecondary : c.lightTextSecondary;

    // AppBar 文字/图标颜色：如果 AppBar 是深色就用白色，否则跟随主色
    final appBarFg = _isColorDark(appBar) ? Colors.white : textPrimary;
    final appBarIconColor = _isColorDark(appBar) ? Colors.white : primary;
    final appBarStatusIconBrightness =
        _isColorDark(appBar) ? Brightness.light : Brightness.dark;
    final appBarStatusBarBrightness =
        _isColorDark(appBar) ? Brightness.dark : Brightness.light;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: primary,
        onPrimary: onPrimary,
        primaryContainer: primary.withOpacity(0.15),
        onPrimaryContainer: primary,
        secondary: c.primaryB,
        onSecondary: onPrimary,
        secondaryContainer: c.primaryB.withOpacity(0.15),
        onSecondaryContainer: c.primaryB,
        surface: surface,
        onSurface: textPrimary,
        error: AppColors.error,
        onError: Colors.white,
      ),
      scaffoldBackgroundColor: Color.lerp(background, c.primaryA, isDark ? 0.04 : 0.035)!,
      cardColor: card,
      dividerColor: divider,

      // AppBar
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        backgroundColor: appBar,
        foregroundColor: appBarFg,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: appBarStatusIconBrightness,
          statusBarBrightness: appBarStatusBarBrightness,
        ),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: appBarFg,
          letterSpacing: 0,
        ),
        iconTheme: IconThemeData(color: appBarFg, size: 24),
        actionsIconTheme: IconThemeData(color: appBarFg, size: 24),
      ),

      // 底部导航
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: navBar,
        selectedItemColor: primary,
        unselectedItemColor: textSecondary.withOpacity(0.6),
        selectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.w400),
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),

      // 列表
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minLeadingWidth: 0,
        horizontalTitleGap: 12,
      ),

      // 分割线
      dividerTheme: DividerThemeData(
        color: divider,
        thickness: 0.5,
        space: 0,
      ),

      // 卡片
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: EdgeInsets.zero,
      ),

      // 输入框
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide(color: primary, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: TextStyle(color: textSecondary, fontSize: 15),
      ),

      // 按钮
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: AppTextStyles.buttonPrimary,
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: AppTextStyles.buttonPrimary,
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          textStyle: AppTextStyles.buttonSecondary,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: AppTextStyles.buttonSecondary,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: primary),
      ),

      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return textSecondary;
          if (s.contains(WidgetState.selected)) return primary;
          return null;
        }),
        checkColor: WidgetStateProperty.all(onPrimary),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected)) return primary;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.selected))
            return primary.withOpacity(0.36);
          return null;
        }),
      ),

      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        thumbColor: primary,
        inactiveTrackColor: divider,
        overlayColor: primary.withOpacity(0.12),
      ),

      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: textSecondary,
        indicatorColor: primary,
        dividerColor: divider,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 4,
        shape: const CircleBorder(),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: card,
        elevation: 24,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? surface : background,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: isDark ? card : AppColors.darkSurface,
        contentTextStyle:
            AppTextStyles.bodyMedium.copyWith(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),

      textTheme: _textTheme(textPrimary, textSecondary),
    );
  }

  // 判断颜色是否偏暗（用于决定前景色）
  static bool _isColorDark(Color color) {
    final luminance = color.computeLuminance();
    return luminance < 0.35;
  }

  // 兼容旧代码的静态 getter（用 ocean 预设）
  static ThemeData get light => build(
        AppThemePresets.of(AppThemePreset.ocean),
        Brightness.light,
      );
  static ThemeData get dark => build(
        AppThemePresets.of(AppThemePreset.ocean),
        Brightness.dark,
      );

  static TextTheme _textTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: AppTextStyles.headline1.copyWith(color: primary),
      displayMedium: AppTextStyles.headline2.copyWith(color: primary),
      displaySmall: AppTextStyles.headline3.copyWith(color: primary),
      headlineLarge: AppTextStyles.headline1.copyWith(color: primary),
      headlineMedium: AppTextStyles.headline2.copyWith(color: primary),
      headlineSmall: AppTextStyles.headline3.copyWith(color: primary),
      titleLarge: AppTextStyles.headline3.copyWith(color: primary),
      titleMedium: AppTextStyles.bodyLarge
          .copyWith(color: primary, fontWeight: FontWeight.w500),
      titleSmall: AppTextStyles.bodyMedium
          .copyWith(color: primary, fontWeight: FontWeight.w500),
      bodyLarge: AppTextStyles.bodyLarge.copyWith(color: primary),
      bodyMedium: AppTextStyles.bodyMedium.copyWith(color: primary),
      bodySmall: AppTextStyles.bodySmall.copyWith(color: secondary),
      labelLarge: AppTextStyles.buttonPrimary.copyWith(color: primary),
      labelMedium: AppTextStyles.buttonSecondary.copyWith(color: primary),
      labelSmall: AppTextStyles.caption.copyWith(color: secondary),
    );
  }
}
