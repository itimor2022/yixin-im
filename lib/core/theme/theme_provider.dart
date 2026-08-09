// 文件用途：定义 ThemeModeNotifier 相关主题、颜色或视觉样式，供应用界面统一使用。
// 核心逻辑：定义 ThemeModeNotifier 的颜色、字体或组件样式，供主题构建和系统 UI 适配统一复用。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';

/// 主题模式 Provider
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

// 关键声明：theme provider 统一提供视觉参数或主题对象，避免页面直接写死颜色、字体和尺寸。
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.system) {
    _loadTheme();
  }

  static const String _key = 'theme_mode';

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key);
    if (value != null) {
      state = ThemeMode.values.firstWhere(
        (e) => e.name == value,
        orElse: () => ThemeMode.system,
      );
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, mode.name);
  }

  void toggleTheme() {
    if (state == ThemeMode.light) {
      setThemeMode(ThemeMode.dark);
    } else {
      setThemeMode(ThemeMode.light);
    }
  }
}

/// 聊天背景 Provider
final chatBackgroundProvider =
    StateNotifierProvider<ChatBackgroundNotifier, ChatBackground>((ref) {
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

  /// 默认背景 - 银灰渐变
  static ChatBackground get defaultLight => const ChatBackground(
        type: ChatBackgroundType.gradient,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFE5E7EB),
            Color(0xFFD1D5DB),
            Color(0xFF9CA3AF),
          ],
        ),
      );

  static ChatBackground get defaultDark => const ChatBackground(
        type: ChatBackgroundType.gradient,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF050505),
            Color(0xFF18181B),
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

  // 当前选中的预设索引（默认银灰，索引2）
  int _gradientIndex = 2;
  int get gradientIndex => _gradientIndex;

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
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
    // 黑灰商务
    [Color(0xFFF8FAFC), Color(0xFFF3F4F6), Color(0xFFE5E7EB)],
    [Color(0xFFF6F7F9), Color(0xFFEDEFF3), Color(0xFFDADDE3)],
    [Color(0xFFE5E7EB), Color(0xFFD1D5DB), Color(0xFF9CA3AF)],
    [Color(0xFF111827), Color(0xFF27272A), Color(0xFF3F3F46)],
    // 低饱和蓝灰
    [Color(0xFFEFF6FF), Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
    [Color(0xFFE0F2FE), Color(0xFFBAE6FD), Color(0xFF94A3B8)],
    [Color(0xFF0F172A), Color(0xFF1E293B), Color(0xFF334155)],
    [Color(0xFF020617), Color(0xFF111827), Color(0xFF374151)],
    // 柔和自然
    [Color(0xFFE8F5E9), Color(0xFFC8E6C9), Color(0xFFA5D6A7)],
    [Color(0xFFE0F7FA), Color(0xFFB2EBF2), Color(0xFF9CA3AF)],
    [Color(0xFFFFF8E1), Color(0xFFFFECB3), Color(0xFFE5E7EB)],
    [Color(0xFFFFF1F2), Color(0xFFFFE4E6), Color(0xFFD1D5DB)],
    // 高级质感
    [Color(0xFF2C3E50), Color(0xFF4B5563), Color(0xFF9CA3AF)],
    [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
    [Color(0xFF064E3B), Color(0xFF0F766E), Color(0xFF99F6E4)],
    [Color(0xFF78350F), Color(0xFFD97706), Color(0xFFFDE68A)],
    // 柔和色系
    [Color(0xFFF1F5F9), Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
    [Color(0xFFE3F2FD), Color(0xFFBBDEFB), Color(0xFF90CAF9)],
    [Color(0xFFFEF3C7), Color(0xFFFDE68A), Color(0xFFFCD34D)],
    [Color(0xFFFFEDD5), Color(0xFFFED7AA), Color(0xFFFB923C)],
    // 高级商务
    [Color(0xFF111827), Color(0xFF374151), Color(0xFF6B7280)],
    [Color(0xFF059669), Color(0xFF34D399), Color(0xFFA7F3D0)],
    [Color(0xFFD97706), Color(0xFFFBBF24), Color(0xFFFDE68A)],
    [Color(0xFF334155), Color(0xFF64748B), Color(0xFFCBD5E1)],
  ];

  Future<void> _loadBackground() async {
    final prefs = await SharedPreferences.getInstance();
    if (_isDisposed) return;

    final typeStr = prefs.getString(_typeKey);
    final colorValue = prefs.getInt(_colorKey);
    final imagePath = prefs.getString(_imageKey);
    final gradientIndex = prefs.getInt(_gradientIndexKey) ?? 2;
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
        final colors =
            gradientPresets[gradientIndex.clamp(0, gradientPresets.length - 1)];
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
