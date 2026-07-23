import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

/// 应用主题模式（扩展 Flutter ThemeMode，增加中国红）
enum AppThemeMode {
  system,
  light,
  dark,
  chineseRed,
  cshBlue;

  /// 映射到 Flutter 原生 ThemeMode
  ThemeMode get flutterThemeMode {
    switch (this) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
      case AppThemeMode.chineseRed:
        return ThemeMode.light;
      case AppThemeMode.cshBlue:
        return ThemeMode.light;
    }
  }
}

/// 主题模式 Provider
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, AppThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<AppThemeMode> {
  ThemeModeNotifier() : super(AppThemeMode.cshBlue) {
    _loadTheme();
  }

  static const String _key = 'app_theme_mode';

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value != null) {
      state = AppThemeMode.values.firstWhere(
        (e) => e.name == value,
        orElse: () => AppThemeMode.system,
      );
    }
  }

  Future<void> setThemeMode(AppThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  void toggleTheme() {
    if (state == AppThemeMode.light) {
      setThemeMode(AppThemeMode.dark);
    } else {
      setThemeMode(AppThemeMode.light);
    }
  }
}

/// 聊天背景 Provider
final chatBackgroundProvider = StateNotifierProvider<ChatBackgroundNotifier, ChatBackground>((ref) {
  return ChatBackgroundNotifier();
});

class ChatBackground {
  final ChatBackgroundType type;
  final Color? solidColor;
  final LinearGradient? gradient;
  final String? imagePath;
  final bool showPattern;

  const ChatBackground({
    this.type = ChatBackgroundType.gradient,
    this.solidColor,
    this.gradient,
    this.imagePath,
    this.showPattern = true,
  });

  /// 默认背景 - 日落橙渐变
  static ChatBackground get defaultLight => const ChatBackground(
    type: ChatBackgroundType.gradient,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFFFE5B4),
        Color(0xFFFFCBA4),
        Color(0xFFFFB088),
      ],
    ),
  );

  static ChatBackground get defaultDark => const ChatBackground(
    type: ChatBackgroundType.gradient,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFF1A1A2E),
        Color(0xFF16213E),
      ],
    ),
  );
}

enum ChatBackgroundType {
  solid,
  gradient,
  image,
  pattern,
}

class ChatBackgroundNotifier extends StateNotifier<ChatBackground> {
  ChatBackgroundNotifier() : super(ChatBackground.defaultLight) {
    _loadBackground();
  }

  // 是否已被释放（用于安全检查）
  bool _isDisposed = false;
  
  // 当前选中的预设索引（默认日落橙，索引10）
  int _gradientIndex = 10;
  int get gradientIndex => _gradientIndex;
  
  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  static const String _typeKey = 'chat_bg_type';
  static const String _colorKey = 'chat_bg_color';
  static const String _imageKey = 'chat_bg_image';
  static const String _gradientIndexKey = 'chat_bg_gradient_index';
  
  // 预设渐变列表（与 chat_settings_page.dart 保持同步）
  static const List<List<Color>> gradientPresets = [
    // 经典 风格
    [Color(0xFFE8D5E0), Color(0xFFD4C5E0), Color(0xFFC5D0E8)],
    [Color(0xFFB8E6CF), Color(0xFFA8D8EA), Color(0xFFB8D4E3)],
    [Color(0xFFFDE2C8), Color(0xFFFAD0C4), Color(0xFFF5C4D4)],
    [Color(0xFFC9D6FF), Color(0xFFD4C5E0), Color(0xFFE2B0FF)],
    // 高级渐变
    [Color(0xFF667EEA), Color(0xFF64B5F6), Color(0xFFA5D6A7)],
    [Color(0xFFFF9A9E), Color(0xFFFECFEF), Color(0xFFFECDD3)],
    [Color(0xFF84FAB0), Color(0xFF8FD3F4), Color(0xFFD4FC79)],
    [Color(0xFFA18CD1), Color(0xFFFBC2EB), Color(0xFFD4C5E0)],
    // 自然色系
    [Color(0xFFFCE4EC), Color(0xFFF8BBD9), Color(0xFFF48FB1)],
    [Color(0xFFE0F7FA), Color(0xFFB2EBF2), Color(0xFF80DEEA)],
    [Color(0xFFFFE5B4), Color(0xFFFFCBA4), Color(0xFFFFB088)],
    [Color(0xFFE6E6FA), Color(0xFFD8BFD8), Color(0xFFDDA0DD)],
    // 高级质感
    [Color(0xFF2C3E50), Color(0xFF4CA1AF), Color(0xFF89CFF0)],
    [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
    [Color(0xFF11998E), Color(0xFF38EF7D), Color(0xFF84FAB0)],
    [Color(0xFFF2994A), Color(0xFFF2C94C), Color(0xFFFFF8DC)],
    // 柔和色系
    [Color(0xFFE8F5E9), Color(0xFFC8E6C9), Color(0xFFA5D6A7)],
    [Color(0xFFE3F2FD), Color(0xFFBBDEFB), Color(0xFF90CAF9)],
    [Color(0xFFFFF8E1), Color(0xFFFFECB3), Color(0xFFFFE082)],
    [Color(0xFFFFE4E1), Color(0xFFFFB6C1), Color(0xFFFFA07A)],
    // 高级商务
    [Color(0xFF6366F1), Color(0xFF818CF8), Color(0xFFC7D2FE)],
    [Color(0xFF059669), Color(0xFF34D399), Color(0xFFA7F3D0)],
    [Color(0xFFD97706), Color(0xFFFBBF24), Color(0xFFFDE68A)],
    [Color(0xFFDB2777), Color(0xFFF472B6), Color(0xFFFBCFE8)],
  ];

  Future<void> _loadBackground() async {
    final prefs = await SharedPreferences.getInstance();
    if (_isDisposed) return;
    
    final typeStr = prefs.getString(_typeKey);
    final colorValue = prefs.getInt(_colorKey);
    final imagePath = prefs.getString(_imageKey);
    final gradientIndex = prefs.getInt(_gradientIndexKey) ?? 0;
    _gradientIndex = gradientIndex;

    if (typeStr != null) {
      final type = ChatBackgroundType.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => ChatBackgroundType.gradient,
      );

      if (type == ChatBackgroundType.solid && colorValue != null) {
        state = ChatBackground(
          type: type,
          solidColor: Color(colorValue),
        );
      } else if (type == ChatBackgroundType.image && imagePath != null) {
        state = ChatBackground(
          type: type,
          imagePath: imagePath,
        );
      } else if (type == ChatBackgroundType.gradient) {
        final colors = gradientPresets[gradientIndex.clamp(0, gradientPresets.length - 1)];
        state = ChatBackground(
          type: type,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: colors,
          ),
        );
      } else {
        state = ChatBackground.defaultLight;
      }
    }
  }

  Future<void> setSolidColor(Color color) async {
    if (_isDisposed) return;
    state = ChatBackground(
      type: ChatBackgroundType.solid,
      solidColor: color,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_typeKey, ChatBackgroundType.solid.name);
    await prefs.setInt(_colorKey, color.value);
  }

  Future<void> setGradient(LinearGradient gradient, {int? presetIndex}) async {
    if (_isDisposed) return;
    state = ChatBackground(
      type: ChatBackgroundType.gradient,
      gradient: gradient,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_typeKey, ChatBackgroundType.gradient.name);
    if (presetIndex != null) {
      _gradientIndex = presetIndex;
      await prefs.setInt(_gradientIndexKey, presetIndex);
    }
  }

  Future<void> setImage(String imagePath) async {
    if (_isDisposed) return;
    state = ChatBackground(
      type: ChatBackgroundType.image,
      imagePath: imagePath,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_typeKey, ChatBackgroundType.image.name);
    await prefs.setString(_imageKey, imagePath);
  }
  
  void setBackground(ChatBackground background) {
    if (_isDisposed) return;
    state = background;
  }
}
