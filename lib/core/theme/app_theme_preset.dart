import 'package:flutter/material.dart';

/// 主题预设枚举
enum AppThemePreset {
  ocean,      // 🔵 海洋蓝（默认）
  blueGold,   // 🟡 蓝金（csh风格）
  sakura,     // 🌸 樱花粉
  forest,     // 🌿 墨绿
  cyberpunk,  // 🌙 暗夜紫
  chinaRed,   // 🔴 中国红
}

/// 每套主题的色板定义
class AppThemeColors {
  final String name;
  final String nameEn;
  final String emoji;

  // 主色（双色渐变）
  final Color primaryA;
  final Color primaryB;

  // 亮色模式
  final Color lightBackground;
  final Color lightSurface;
  final Color lightCard;
  final Color lightAppBar;
  final Color lightNavBar;
  final Color lightBubbleOutgoing;
  final Color lightBubbleIncoming;
  final Color lightChatBackground;
  final Color lightInputBackground;
  final Color lightDivider;
  final Color lightTextPrimary;
  final Color lightTextSecondary;
  final Color lightTextTertiary;
  final Color lightOnPrimary;

  // 暗色模式
  final Color darkBackground;
  final Color darkSurface;
  final Color darkCard;
  final Color darkAppBar;
  final Color darkNavBar;
  final Color darkBubbleOutgoing;
  final Color darkBubbleIncoming;
  final Color darkChatBackground;
  final Color darkInputBackground;
  final Color darkDivider;
  final Color darkTextPrimary;
  final Color darkTextSecondary;
  final Color darkOnPrimary;

  const AppThemeColors({
    required this.name,
    required this.nameEn,
    required this.emoji,
    required this.primaryA,
    required this.primaryB,
    required this.lightBackground,
    required this.lightSurface,
    required this.lightCard,
    required this.lightAppBar,
    required this.lightNavBar,
    required this.lightBubbleOutgoing,
    required this.lightBubbleIncoming,
    required this.lightChatBackground,
    required this.lightInputBackground,
    required this.lightDivider,
    required this.lightTextPrimary,
    required this.lightTextSecondary,
    required this.lightTextTertiary,
    required this.lightOnPrimary,
    required this.darkBackground,
    required this.darkSurface,
    required this.darkCard,
    required this.darkAppBar,
    required this.darkNavBar,
    required this.darkBubbleOutgoing,
    required this.darkBubbleIncoming,
    required this.darkChatBackground,
    required this.darkInputBackground,
    required this.darkDivider,
    required this.darkTextPrimary,
    required this.darkTextSecondary,
    required this.darkOnPrimary,
  });

  /// 主色渐变
  LinearGradient get primaryGradient => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primaryA, primaryB],
      );

  /// 亮色模式下的主色（用 primaryA）
  Color get lightPrimary => primaryA;

  /// 暗色模式下的主色（用 primaryB，更亮一点）
  Color get darkPrimary => primaryB;

  /// 登录页渐变（亮色模式）
  LinearGradient get loginGradientLight => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryA, primaryB, primaryA.withOpacity(0.7)],
    stops: const [0.0, 0.55, 1.0],
  );

  /// 登录页渐变（暗色模式）
  LinearGradient get loginGradientDark => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      primaryA.withOpacity(0.9),
      primaryB.withOpacity(0.5),
      const Color(0xFF080A0E),
    ],
    stops: const [0.0, 0.5, 1.0],
  );

  /// AppBar 渐变
  LinearGradient get appBarGradient => LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [primaryA, primaryB],
  );

  /// AppBar 前景色（根据主色亮暗自动选白/深）
  Color get appBarForeground {
    final luminance = primaryA.computeLuminance();
    return luminance > 0.35 ? const Color(0xFF111827) : const Color(0xFFFFFFFF);
  }
}

/// 所有主题预设
class AppThemePresets {
  AppThemePresets._();

  static const Map<AppThemePreset, AppThemeColors> all = {
    // ─────────────────────────────────────────────────────────
    // 🔵 海洋蓝（默认）：天蓝 + 深蓝，干净现代
    // ─────────────────────────────────────────────────────────
    AppThemePreset.ocean: AppThemeColors(
      name: '海洋蓝',
      nameEn: 'Ocean Blue',
      emoji: '🔵',
      primaryA: Color(0xFF0088CC),
      primaryB: Color(0xFF00B4D8),
      lightBackground: Color(0xFFF6F7F9),
      lightSurface: Color(0xFFFFFFFF),
      lightCard: Color(0xFFFFFFFF),
      lightAppBar: Color(0xFFF6F7F9),
      lightNavBar: Color(0xFFFFFFFF),
      lightBubbleOutgoing: Color(0xFFD0EEFF),
      lightBubbleIncoming: Color(0xFFFFFFFF),
      lightChatBackground: Color(0xFFDFE7EB),
      lightInputBackground: Color(0xFFF1F2F4),
      lightDivider: Color(0xFFE5E5E5),
      lightTextPrimary: Color(0xFF111827),
      lightTextSecondary: Color(0xFF6B7280),
      lightTextTertiary: Color(0xFF9CA3AF),
      lightOnPrimary: Color(0xFFFFFFFF),
      darkBackground: Color(0xFF0E1116),
      darkSurface: Color(0xFF151920),
      darkCard: Color(0xFF1B2028),
      darkAppBar: Color(0xFF0E1116),
      darkNavBar: Color(0xFF151920),
      darkBubbleOutgoing: Color(0xFF003A5C),
      darkBubbleIncoming: Color(0xFF1D242D),
      darkChatBackground: Color(0xFF111820),
      darkInputBackground: Color(0xFF20252D),
      darkDivider: Color(0xFF2C333D),
      darkTextPrimary: Color(0xFFFFFFFF),
      darkTextSecondary: Color(0xFFC3CAD4),
      darkOnPrimary: Color(0xFFFFFFFF),
    ),

    // ─────────────────────────────────────────────────────────
    // 🟡 蓝金（csh风格）：深海蓝 + 皇金色
    // ─────────────────────────────────────────────────────────
    AppThemePreset.blueGold: AppThemeColors(
      name: '蓝金',
      nameEn: 'Blue & Gold',
      emoji: '🟡',
      primaryA: Color(0xFF1A3A6B),
      primaryB: Color(0xFFC9A84C),
      lightBackground: Color(0xFFF5F3EE),
      lightSurface: Color(0xFFFAF9F5),
      lightCard: Color(0xFFFAF9F5),
      lightAppBar: Color(0xFF1A3A6B),
      lightNavBar: Color(0xFFFAF9F5),
      lightBubbleOutgoing: Color(0xFFE8D9A8),
      lightBubbleIncoming: Color(0xFFFAF9F5),
      lightChatBackground: Color(0xFFEAE6DA),
      lightInputBackground: Color(0xFFEFECE4),
      lightDivider: Color(0xFFDDD8C8),
      lightTextPrimary: Color(0xFF0D1B2A),
      lightTextSecondary: Color(0xFF4A5568),
      lightTextTertiary: Color(0xFF8A95A3),
      lightOnPrimary: Color(0xFFFFFFFF),
      darkBackground: Color(0xFF0A0E14),
      darkSurface: Color(0xFF111620),
      darkCard: Color(0xFF18202C),
      darkAppBar: Color(0xFF0F1923),
      darkNavBar: Color(0xFF111620),
      darkBubbleOutgoing: Color(0xFF2A3A1A),
      darkBubbleIncoming: Color(0xFF18202C),
      darkChatBackground: Color(0xFF0D1520),
      darkInputBackground: Color(0xFF1C2433),
      darkDivider: Color(0xFF2A3344),
      darkTextPrimary: Color(0xFFF0E8D0),
      darkTextSecondary: Color(0xFFB8A878),
      darkOnPrimary: Color(0xFF0D1B2A),
    ),

    // ─────────────────────────────────────────────────────────
    // 🌸 樱花粉：玫红 + 珊瑚橙，温柔清新
    // ─────────────────────────────────────────────────────────
    AppThemePreset.sakura: AppThemeColors(
      name: '樱花粉',
      nameEn: 'Sakura Pink',
      emoji: '🌸',
      primaryA: Color(0xFFE91E8C),
      primaryB: Color(0xFFFF6B6B),
      lightBackground: Color(0xFFFFF5F8),
      lightSurface: Color(0xFFFFFFFF),
      lightCard: Color(0xFFFFFFFF),
      lightAppBar: Color(0xFFFFF5F8),
      lightNavBar: Color(0xFFFFFFFF),
      lightBubbleOutgoing: Color(0xFFFFD6E8),
      lightBubbleIncoming: Color(0xFFFFFFFF),
      lightChatBackground: Color(0xFFF5E6EC),
      lightInputBackground: Color(0xFFF8EDF3),
      lightDivider: Color(0xFFF0D5E2),
      lightTextPrimary: Color(0xFF2D1B24),
      lightTextSecondary: Color(0xFF7A4F62),
      lightTextTertiary: Color(0xFFB08898),
      lightOnPrimary: Color(0xFFFFFFFF),
      darkBackground: Color(0xFF120A0E),
      darkSurface: Color(0xFF1E1018),
      darkCard: Color(0xFF261520),
      darkAppBar: Color(0xFF120A0E),
      darkNavBar: Color(0xFF1E1018),
      darkBubbleOutgoing: Color(0xFF4A1530),
      darkBubbleIncoming: Color(0xFF261520),
      darkChatBackground: Color(0xFF180D14),
      darkInputBackground: Color(0xFF2C1A24),
      darkDivider: Color(0xFF3D2030),
      darkTextPrimary: Color(0xFFFFEEF4),
      darkTextSecondary: Color(0xFFD4A0B8),
      darkOnPrimary: Color(0xFFFFFFFF),
    ),

    // ─────────────────────────────────────────────────────────
    // 🌿 墨绿：深森绿 + 薄荷绿，自然沉稳
    // ─────────────────────────────────────────────────────────
    AppThemePreset.forest: AppThemeColors(
      name: '墨绿',
      nameEn: 'Forest Green',
      emoji: '🌿',
      primaryA: Color(0xFF1B5E3B),
      primaryB: Color(0xFF4CAF50),
      lightBackground: Color(0xFFF2F8F4),
      lightSurface: Color(0xFFFFFFFF),
      lightCard: Color(0xFFFFFFFF),
      lightAppBar: Color(0xFF1B5E3B),
      lightNavBar: Color(0xFFFFFFFF),
      lightBubbleOutgoing: Color(0xFFC8E6C9),
      lightBubbleIncoming: Color(0xFFFFFFFF),
      lightChatBackground: Color(0xFFDCEBDF),
      lightInputBackground: Color(0xFFECF4EE),
      lightDivider: Color(0xFFD4E8D8),
      lightTextPrimary: Color(0xFF0D2014),
      lightTextSecondary: Color(0xFF3D6649),
      lightTextTertiary: Color(0xFF7A9E82),
      lightOnPrimary: Color(0xFFFFFFFF),
      darkBackground: Color(0xFF090E0A),
      darkSurface: Color(0xFF111A12),
      darkCard: Color(0xFF172019),
      darkAppBar: Color(0xFF0D1A0F),
      darkNavBar: Color(0xFF111A12),
      darkBubbleOutgoing: Color(0xFF0F3318),
      darkBubbleIncoming: Color(0xFF172019),
      darkChatBackground: Color(0xFF0C160E),
      darkInputBackground: Color(0xFF1A261C),
      darkDivider: Color(0xFF243328),
      darkTextPrimary: Color(0xFFE8F5E9),
      darkTextSecondary: Color(0xFF90C49A),
      darkOnPrimary: Color(0xFFFFFFFF),
    ),

    // ─────────────────────────────────────────────────────────
    // 🌙 暗夜紫：靛紫 + 电光蓝，赛博未来感
    // ─────────────────────────────────────────────────────────
    AppThemePreset.cyberpunk: AppThemeColors(
      name: '暗夜紫',
      nameEn: 'Cyber Purple',
      emoji: '🌙',
      primaryA: Color(0xFF6C63FF),
      primaryB: Color(0xFF00D4FF),
      lightBackground: Color(0xFFF4F3FF),
      lightSurface: Color(0xFFFFFFFF),
      lightCard: Color(0xFFFFFFFF),
      lightAppBar: Color(0xFF6C63FF),
      lightNavBar: Color(0xFFFFFFFF),
      lightBubbleOutgoing: Color(0xFFDDD9FF),
      lightBubbleIncoming: Color(0xFFFFFFFF),
      lightChatBackground: Color(0xFFEAE8FF),
      lightInputBackground: Color(0xFFF0EEFF),
      lightDivider: Color(0xFFDDD9FF),
      lightTextPrimary: Color(0xFF1A1040),
      lightTextSecondary: Color(0xFF5B5280),
      lightTextTertiary: Color(0xFF9B96C0),
      lightOnPrimary: Color(0xFFFFFFFF),
      darkBackground: Color(0xFF08060F),
      darkSurface: Color(0xFF100E1E),
      darkCard: Color(0xFF18152C),
      darkAppBar: Color(0xFF08060F),
      darkNavBar: Color(0xFF100E1E),
      darkBubbleOutgoing: Color(0xFF2A1A5E),
      darkBubbleIncoming: Color(0xFF18152C),
      darkChatBackground: Color(0xFF0C0A1A),
      darkInputBackground: Color(0xFF1E1A35),
      darkDivider: Color(0xFF2C2650),
      darkTextPrimary: Color(0xFFEEECFF),
      darkTextSecondary: Color(0xFFA89FD8),
      darkOnPrimary: Color(0xFFFFFFFF),
    ),

    // ─────────────────────────────────────────────────────────
    // 🔴 中国红：朱砂红 + 金色，传统国风
    // ─────────────────────────────────────────────────────────
    AppThemePreset.chinaRed: AppThemeColors(
      name: '中国红',
      nameEn: 'China Red',
      emoji: '🔴',
      primaryA: Color(0xFFC0392B),
      primaryB: Color(0xFFE8B84B),
      lightBackground: Color(0xFFFFF8F5),
      lightSurface: Color(0xFFFFFFFF),
      lightCard: Color(0xFFFFFFFF),
      lightAppBar: Color(0xFFC0392B),
      lightNavBar: Color(0xFFFFFFFF),
      lightBubbleOutgoing: Color(0xFFFFDAD4),
      lightBubbleIncoming: Color(0xFFFFFFFF),
      lightChatBackground: Color(0xFFF5E6E0),
      lightInputBackground: Color(0xFFF8EEEA),
      lightDivider: Color(0xFFEDD5CC),
      lightTextPrimary: Color(0xFF2D0A06),
      lightTextSecondary: Color(0xFF7A3328),
      lightTextTertiary: Color(0xFFB07068),
      lightOnPrimary: Color(0xFFFFFFFF),
      darkBackground: Color(0xFF120402),
      darkSurface: Color(0xFF1E0804),
      darkCard: Color(0xFF280C06),
      darkAppBar: Color(0xFF1A0503),
      darkNavBar: Color(0xFF1E0804),
      darkBubbleOutgoing: Color(0xFF4A0F08),
      darkBubbleIncoming: Color(0xFF280C06),
      darkChatBackground: Color(0xFF180604),
      darkInputBackground: Color(0xFF300E08),
      darkDivider: Color(0xFF461510),
      darkTextPrimary: Color(0xFFFFF0EE),
      darkTextSecondary: Color(0xFFD4906A),
      darkOnPrimary: Color(0xFFFFFFFF),
    ),
  };

  static AppThemeColors of(AppThemePreset preset) => all[preset]!;

  static AppThemePreset fromString(String? value) {
    return AppThemePreset.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AppThemePreset.ocean,
    );
  }
}
