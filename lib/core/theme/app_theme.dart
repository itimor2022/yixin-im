import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

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
      onSecondary: Colors.white,
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
        letterSpacing: -0.3,
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
      selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
    
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        textStyle: AppTextStyles.buttonSecondary,
      ),
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
      contentTextStyle: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    
    // 文字主题
    textTheme: _textTheme(AppColors.lightTextPrimary, AppColors.lightTextSecondary),
  );

  // ==================== 暗色主题 ====================
  
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    
    // 颜色方案
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      primaryContainer: AppColors.primaryDark,
      secondary: AppColors.primary,
      secondaryContainer: AppColors.primaryDark,
      surface: AppColors.darkSurface,
      error: AppColors.error,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
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
        letterSpacing: -0.3,
      ),
      iconTheme: IconThemeData(
        color: AppColors.primary,
        size: 24,
      ),
    ),
    
    // 底部导航
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.darkSurface,
      selectedItemColor: AppColors.primary,
      unselectedItemColor: AppColors.darkTextSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      selectedLabelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      hintStyle: AppTextStyles.inputHint.copyWith(
        color: AppColors.darkTextSecondary,
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
    
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        textStyle: AppTextStyles.buttonSecondary,
      ),
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
      contentTextStyle: AppTextStyles.bodyMedium.copyWith(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
    ),
    
    // 文字主题
    textTheme: _textTheme(AppColors.darkTextPrimary, AppColors.darkTextSecondary),
  );

  // ==================== 中国风主题（故宫·宣纸·朱砂·水墨）====================

  static ThemeData get chineseRed => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,

    colorScheme: const ColorScheme.light(
      primary:            AppColors.chineseRedPrimary,
      primaryContainer:   AppColors.chineseRedPrimaryLight,
      secondary:          AppColors.chineseGold,
      secondaryContainer: AppColors.chineseGoldLight,
      surface:            AppColors.chineseRedSurface,
      error:              AppColors.error,
      onPrimary:          Colors.white,
      onSecondary:        Colors.white,
      onSurface:          AppColors.chineseRedTextPrimary,
      onError:            Colors.white,
      outline:            AppColors.chineseRedDivider,
    ),

    scaffoldBackgroundColor: AppColors.chineseRedBackground,

    // AppBar：深朱砂宫墙色，白字白图标，营造故宫大门感
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      backgroundColor: AppColors.chineseRedAppBar,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shadowColor: Color(0x408E1B15),
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        letterSpacing: 2.0,   // 中文标题加字距，更有书法感
      ),
      iconTheme: IconThemeData(color: Colors.white, size: 24),
    ),

    // 底部导航：宣纸底色，朱砂选中，墨色未选
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.chineseRedNavBar,
      selectedItemColor: AppColors.chineseRedPrimary,
      unselectedItemColor: AppColors.chineseRedTextSecondary,
      type: BottomNavigationBarType.fixed,
      elevation: 8,
      selectedLabelStyle:   TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      unselectedLabelStyle: TextStyle(fontSize: 12),
    ),

    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minLeadingWidth: 0,
      horizontalTitleGap: 12,
      tileColor: Colors.transparent,
    ),

    // 分割线：竹色细线
    dividerTheme: const DividerThemeData(
      color: AppColors.chineseRedDivider,
      thickness: 0.5,
      space: 0,
    ),

    // 卡片：暖白宣纸色，圆角保留，加极细朱砂描边
    cardTheme: CardThemeData(
      color: AppColors.chineseRedCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.chineseRedDivider, width: 0.5),
      ),
      margin: EdgeInsets.zero,
      shadowColor: const Color(0x20C0392B),
    ),

    // 输入框：宣纸底+竹色边框，聚焦变朱砂
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.chineseRedInputBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.chineseRedDivider, width: 0.8),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.chineseRedDivider, width: 0.8),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: AppColors.chineseRedPrimary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: AppTextStyles.inputHint.copyWith(
        color: AppColors.chineseRedTextTertiary,
      ),
    ),

    // 主按钮：朱砂红，无圆角（方正感），白字
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.chineseRedPrimary,
        foregroundColor: Colors.white,
        elevation: 2,
        shadowColor: const Color(0x60922B21),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
        ),
      ),
    ),

    // 文字按钮：朱砂色
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.chineseRedPrimary,
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),

    // 开关：朱砂色
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? AppColors.chineseRedPrimary
              : AppColors.chineseRedTextTertiary),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? AppColors.chineseRedPrimaryLight.withOpacity(0.5)
              : AppColors.chineseRedDivider),
    ),

    // 复选框：朱砂
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? AppColors.chineseRedPrimary
              : Colors.transparent),
      checkColor: WidgetStateProperty.all(Colors.white),
      side: const BorderSide(color: AppColors.chineseRedDivider, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),

    // Chip：宣纸底，朱砂边
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.chineseRedCard,
      selectedColor: AppColors.chineseRedPrimary.withOpacity(0.15),
      side: const BorderSide(color: AppColors.chineseRedDivider),
      labelStyle: const TextStyle(color: AppColors.chineseRedTextPrimary),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),

    // Snackbar：墨色底，白字
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: Color(0xFF2C1A10),
      contentTextStyle: TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      behavior: SnackBarBehavior.floating,
    ),

    // Dialog：宣纸白，细边
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.chineseRedCard,
      elevation: 8,
      shadowColor: const Color(0x40922B21),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.chineseRedDivider, width: 0.5),
      ),
      titleTextStyle: const TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: AppColors.chineseRedTextPrimary,
        letterSpacing: 1.0,
      ),
    ),

    // BottomSheet：宣纸色
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.chineseRedCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),

    // Tab：朱砂选中指示器
    tabBarTheme: const TabBarThemeData(
      labelColor: AppColors.chineseRedPrimary,
      unselectedLabelColor: AppColors.chineseRedTextSecondary,
      indicatorColor: AppColors.chineseRedPrimary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.chineseRedDivider,
    ),

    // 进度条：朱砂
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.chineseRedPrimary,
    ),

    // 文字主题：墨色系
    textTheme: _textTheme(
      AppColors.chineseRedTextPrimary,
      AppColors.chineseRedTextSecondary,
    ),

    // 图标：朱砂
    iconTheme: const IconThemeData(
      color: AppColors.chineseRedPrimary,
      size: 24,
    ),

    // 选中高亮：朱砂淡
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.chineseRedPrimary,
      selectionColor: Color(0x40C0392B),
      selectionHandleColor: AppColors.chineseRedPrimary,
    ),
  );

    static TextTheme _textTheme(Color primaryColor, Color secondaryColor) {
    return TextTheme(
      displayLarge: AppTextStyles.headline1.copyWith(color: primaryColor),
      displayMedium: AppTextStyles.headline2.copyWith(color: primaryColor),
      displaySmall: AppTextStyles.headline3.copyWith(color: primaryColor),
      headlineLarge: AppTextStyles.headline1.copyWith(color: primaryColor),
      headlineMedium: AppTextStyles.headline2.copyWith(color: primaryColor),
      headlineSmall: AppTextStyles.headline3.copyWith(color: primaryColor),
      titleLarge: AppTextStyles.headline3.copyWith(color: primaryColor),
      titleMedium: AppTextStyles.bodyLarge.copyWith(color: primaryColor, fontWeight: FontWeight.w500),
      titleSmall: AppTextStyles.bodyMedium.copyWith(color: primaryColor, fontWeight: FontWeight.w500),
      bodyLarge: AppTextStyles.bodyLarge.copyWith(color: primaryColor),
      bodyMedium: AppTextStyles.bodyMedium.copyWith(color: primaryColor),
      bodySmall: AppTextStyles.bodySmall.copyWith(color: secondaryColor),
      labelLarge: AppTextStyles.buttonPrimary.copyWith(color: primaryColor),
      labelMedium: AppTextStyles.buttonSecondary.copyWith(color: primaryColor),
      labelSmall: AppTextStyles.caption.copyWith(color: secondaryColor),
    );
  }
}
