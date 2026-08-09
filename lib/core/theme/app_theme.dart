// 文件用途：定义 AppTheme 相关主题、颜色或视觉样式，供应用界面统一使用。
// 核心逻辑：定义 AppTheme 的颜色、字体或组件样式，供主题构建和系统 UI 适配统一复用。
import 'package:flutter/material.dart';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

// 关键声明：app theme 统一提供视觉参数或主题对象，避免页面直接写死颜色、字体和尺寸。
///主题
class AppTheme {
  AppTheme._();

  // ==================== 亮色主题 ====================

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,

        // 颜色方案
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          primaryContainer: AppColors.primaryLight,
          secondary: AppColors.primary,
          secondaryContainer: AppColors.primaryLight,
          surface: AppColors.lightSurface,
          error: AppColors.error,
          onPrimary: Colors.white,
          onPrimaryContainer: Colors.white,
          onSecondary: Colors.white,
          onSecondaryContainer: Colors.white,
          onSurface: AppColors.lightTextPrimary,
          onError: Colors.white,
        ),

        // 脚手架
        scaffoldBackgroundColor: AppColors.lightBackground,

        // AppBar
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0.5,
          centerTitle: false,
          backgroundColor: AppColors.lightBackground,
          foregroundColor: AppColors.lightTextPrimary,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.lightTextPrimary,
            letterSpacing: 0,
          ),
          iconTheme: IconThemeData(
            color: AppColors.primary,
            size: 24,
          ),
        ),

        // 底部导航
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.lightBackground,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.lightTextSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
          selectedLabelStyle:
              TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          unselectedLabelStyle: TextStyle(fontSize: 12),
        ),

        // 列表瓦片
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          minLeadingWidth: 0,
          horizontalTitleGap: 12,
        ),

        // 分割线
        dividerTheme: const DividerThemeData(
          color: AppColors.lightDivider,
          thickness: 0.5,
          space: 0,
        ),

        // 卡片
        cardTheme: CardThemeData(
          color: AppColors.lightCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: EdgeInsets.zero,
        ),

        // 输入框
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.lightInputBackground,
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
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          hintStyle: AppTextStyles.inputHint.copyWith(
            color: AppColors.lightTextSecondary,
          ),
        ),

        // 按钮
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: AppTextStyles.buttonPrimary,
          ),
        ),

        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: AppTextStyles.buttonPrimary,
          ),
        ),

        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            textStyle: AppTextStyles.buttonSecondary,
          ),
        ),

        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: AppTextStyles.buttonSecondary,
          ),
        ),

        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: AppColors.primary,
          ),
        ),

        checkboxTheme: CheckboxThemeData(
          fillColor: _selectedControlColor(
            activeColor: AppColors.primary,
            disabledColor: AppColors.lightTextTertiary,
          ),
          checkColor: WidgetStateProperty.all(Colors.white),
        ),

        switchTheme: SwitchThemeData(
          thumbColor: _selectedControlColor(
            activeColor: AppColors.primary,
            disabledColor: AppColors.lightTextTertiary,
          ),
          trackColor: _selectedTrackColor(
            activeColor: AppColors.primary,
            disabledColor: AppColors.lightDivider,
          ),
        ),

        sliderTheme: SliderThemeData(
          activeTrackColor: AppColors.primary,
          thumbColor: AppColors.primary,
          inactiveTrackColor: AppColors.lightDivider,
          overlayColor: AppColors.primary.withOpacity(0.12),
        ),

        tabBarTheme: const TabBarThemeData(
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.lightTextSecondary,
          indicatorColor: AppColors.primary,
          dividerColor: AppColors.lightDivider,
        ),

        // 浮动操作按钮
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: CircleBorder(),
        ),

        // 对话框
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.lightCard,
          elevation: 24,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),

        // 底部弹出
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.lightBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
        ),

        // Snackbar
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.darkSurface,
          contentTextStyle:
              AppTextStyles.bodyMedium.copyWith(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),

        // 文字主题
        textTheme: _textTheme(
            AppColors.lightTextPrimary, AppColors.lightTextSecondary),
      );

  // ==================== 暗色主题 ====================

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,

        // 颜色方案
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primaryDarkMode,
          primaryContainer: AppColors.primaryDarkModeContainer,
          secondary: AppColors.primaryDarkMode,
          secondaryContainer: AppColors.primaryDarkModeContainer,
          surface: AppColors.darkSurface,
          error: AppColors.error,
          onPrimary: AppColors.onPrimaryDarkMode,
          onPrimaryContainer: AppColors.darkTextPrimary,
          onSecondary: AppColors.onPrimaryDarkMode,
          onSecondaryContainer: AppColors.darkTextPrimary,
          onSurface: AppColors.darkTextPrimary,
          onError: Colors.white,
        ),

        // 脚手架
        scaffoldBackgroundColor: AppColors.darkBackground,

        // AppBar
        appBarTheme: const AppBarTheme(
          elevation: 0,
          scrolledUnderElevation: 0.5,
          centerTitle: false,
          backgroundColor: AppColors.darkBackground,
          foregroundColor: AppColors.darkTextPrimary,
          surfaceTintColor: Colors.transparent,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.darkTextPrimary,
            letterSpacing: 0,
          ),
          iconTheme: IconThemeData(
            color: AppColors.primaryDarkMode,
            size: 24,
          ),
        ),

        // 底部导航
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.darkSurface,
          selectedItemColor: AppColors.darkAccent,
          unselectedItemColor: AppColors.darkTextSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 8,
          selectedLabelStyle:
              TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          unselectedLabelStyle: TextStyle(fontSize: 12),
        ),

        // 列表瓦片
        listTileTheme: const ListTileThemeData(
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          minLeadingWidth: 0,
          horizontalTitleGap: 12,
        ),

        // 分割线
        dividerTheme: const DividerThemeData(
          color: AppColors.darkDivider,
          thickness: 0.5,
          space: 0,
        ),

        // 卡片
        cardTheme: CardThemeData(
          color: AppColors.darkCard,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: EdgeInsets.zero,
        ),

        // 输入框
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkInputBackground,
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
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          hintStyle: AppTextStyles.inputHint.copyWith(
            color: AppColors.darkTextSecondary,
          ),
        ),

        // 按钮
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryDarkMode,
            foregroundColor: AppColors.onPrimaryDarkMode,
            disabledBackgroundColor: AppColors.darkInputBackground,
            disabledForegroundColor: AppColors.darkTextDisabled,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: AppTextStyles.buttonPrimary,
          ),
        ),

        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primaryDarkMode,
            foregroundColor: AppColors.onPrimaryDarkMode,
            disabledBackgroundColor: AppColors.darkInputBackground,
            disabledForegroundColor: AppColors.darkTextDisabled,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: AppTextStyles.buttonPrimary,
          ),
        ),

        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primaryDarkMode,
            disabledForegroundColor: AppColors.darkTextDisabled,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            textStyle: AppTextStyles.buttonSecondary,
          ),
        ),

        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryDarkMode,
            disabledForegroundColor: AppColors.darkTextDisabled,
            side: const BorderSide(color: AppColors.primaryDarkModeBorder),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: AppTextStyles.buttonSecondary,
          ),
        ),

        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: AppColors.primaryDarkMode,
            disabledForegroundColor: AppColors.darkTextDisabled,
          ),
        ),

        checkboxTheme: CheckboxThemeData(
          fillColor: _selectedControlColor(
            activeColor: AppColors.darkAccent,
            disabledColor: AppColors.darkTextDisabled,
          ),
          checkColor: WidgetStateProperty.all(AppColors.onPrimaryDarkMode),
        ),

        switchTheme: SwitchThemeData(
          thumbColor: _selectedControlColor(
            activeColor: AppColors.darkAccent,
            disabledColor: AppColors.darkTextDisabled,
          ),
          trackColor: _selectedTrackColor(
            activeColor: AppColors.darkAccent,
            disabledColor: AppColors.darkInputBackground,
          ),
        ),

        sliderTheme: SliderThemeData(
          activeTrackColor: AppColors.darkAccent,
          thumbColor: AppColors.darkAccent,
          inactiveTrackColor: AppColors.darkInputBackground,
          overlayColor: AppColors.darkAccent.withOpacity(0.16),
        ),

        tabBarTheme: const TabBarThemeData(
          labelColor: AppColors.primaryDarkMode,
          unselectedLabelColor: AppColors.darkTextSecondary,
          indicatorColor: AppColors.primaryDarkMode,
          dividerColor: AppColors.darkDivider,
        ),

        // 浮动操作按钮
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primaryDarkMode,
          foregroundColor: AppColors.onPrimaryDarkMode,
          elevation: 4,
          shape: CircleBorder(),
        ),

        // 对话框
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.darkCard,
          elevation: 24,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),

        // 底部弹出
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AppColors.darkSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
        ),

        // Snackbar
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AppColors.darkCard,
          contentTextStyle:
              AppTextStyles.bodyMedium.copyWith(color: Colors.white),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),

        // 文字主题
        textTheme:
            _textTheme(AppColors.darkTextPrimary, AppColors.darkTextSecondary),
      );

  static WidgetStateProperty<Color?> _selectedControlColor({
    required Color activeColor,
    required Color disabledColor,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return disabledColor;
      if (states.contains(WidgetState.selected)) return activeColor;
      return null;
    });
  }

  static WidgetStateProperty<Color?> _selectedTrackColor({
    required Color activeColor,
    required Color disabledColor,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) return disabledColor;
      if (states.contains(WidgetState.selected)) {
        return activeColor.withOpacity(0.36);
      }
      return null;
    });
  }

  // ==================== 文字主题 ====================

  static TextTheme _textTheme(Color primaryColor, Color secondaryColor) {
    return TextTheme(
      displayLarge: AppTextStyles.headline1.copyWith(color: primaryColor),
      displayMedium: AppTextStyles.headline2.copyWith(color: primaryColor),
      displaySmall: AppTextStyles.headline3.copyWith(color: primaryColor),
      headlineLarge: AppTextStyles.headline1.copyWith(color: primaryColor),
      headlineMedium: AppTextStyles.headline2.copyWith(color: primaryColor),
      headlineSmall: AppTextStyles.headline3.copyWith(color: primaryColor),
      titleLarge: AppTextStyles.headline3.copyWith(color: primaryColor),
      titleMedium: AppTextStyles.bodyLarge
          .copyWith(color: primaryColor, fontWeight: FontWeight.w500),
      titleSmall: AppTextStyles.bodyMedium
          .copyWith(color: primaryColor, fontWeight: FontWeight.w500),
      bodyLarge: AppTextStyles.bodyLarge.copyWith(color: primaryColor),
      bodyMedium: AppTextStyles.bodyMedium.copyWith(color: primaryColor),
      bodySmall: AppTextStyles.bodySmall.copyWith(color: secondaryColor),
      labelLarge: AppTextStyles.buttonPrimary.copyWith(color: primaryColor),
      labelMedium: AppTextStyles.buttonSecondary.copyWith(color: primaryColor),
      labelSmall: AppTextStyles.caption.copyWith(color: secondaryColor),
    );
  }
}
