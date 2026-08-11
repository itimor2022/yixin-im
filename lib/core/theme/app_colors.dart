// 文件用途：定义 AppColors 相关主题、颜色或视觉样式，供应用界面统一使用。
// 核心逻辑：定义 AppColors 的颜色、字体或组件样式，供主题构建和系统 UI 适配统一复用。
import 'package:flutter/material.dart';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。

// 关键声明：app colors 统一提供视觉参数或主题对象，避免页面直接写死颜色、字体和尺寸。
/// 风格配色
class AppColors {
  AppColors._();

  // ==================== 石墨黑灰（高级商务感） ====================

  static const Color primary = Color(0xFF0B0D12);
  static const Color primaryLight = Color(0xFF111827);
  static const Color primaryDark = Color(0xFF030712);
  static const Color primaryDarkMode = Color(0xFF5EA1FF);
  static const Color primaryDarkModeContainer = Color(0xFF183456);
  static const Color primaryDarkModeBorder = Color(0xFF3269A8);
  static const Color onPrimaryDarkMode = Color(0xFF0B0D12);
  static const Color darkAccent = Color(0xFF5EA1FF);
  static const Color darkAccentPressed = Color(0xFF8AB9FF);
  static const Color darkControlBackground = Color(0xFF20242B);
  static const Color darkControlBackgroundStrong = Color(0xFF29313A);
  static const Color darkLink = Color(0xFF8AB9FF);
  static const Color darkLinkEmphasis = Color(0xFFB9D7FF);
  static const Color darkEmphasisSoft = Color(0xFF182B44);

  /// 渐变（黑灰渐变）
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0B0D12), Color(0xFF3F3F46)],
  );

  static Color primaryFor(BuildContext context) {
    return Theme.of(context).colorScheme.primary;
  }

  static Color onPrimaryFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? onPrimaryDarkMode
        : Colors.white;
  }

  static Color primaryContainerFor(BuildContext context) {
    return Theme.of(context).colorScheme.primaryContainer;
  }

  static Color primaryBorderFor(BuildContext context) {
    return Theme.of(context).colorScheme.primary.withOpacity(0.5);
  }

  static Color primaryWithOpacity(BuildContext context, double opacity) {
    return primaryFor(context).withOpacity(opacity);
  }

  static Color textPrimaryFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkTextPrimary
        : lightTextPrimary;
  }

  static Color textSecondaryFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkTextSecondary
        : lightTextSecondary;
  }

  static Color textTertiaryFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkTextTertiary
        : lightTextTertiary;
  }

  static Color linkFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark ? darkLink : primary;
  }

  static Color linkEmphasisFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkLinkEmphasis
        : primary;
  }

  static Color inputBackgroundFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkInputBackground
        : lightInputBackground;
  }

  static Color inputIconFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkTextSecondary
        : lightTextSecondary;
  }

  static Color inputHintFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkTextSecondary
        : lightTextSecondary;
  }

  static Color backgroundFor(BuildContext context) {
    return Theme.of(context).scaffoldBackgroundColor;
  }

  static Color surfaceFor(BuildContext context) {
    return Theme.of(context).colorScheme.surface;
  }

  static Color cardFor(BuildContext context) {
    return Theme.of(context).cardColor;
  }

  static Color dividerFor(BuildContext context) {
    return Theme.of(context).dividerColor;
  }

  static Color keyboardBackgroundFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkSurface
        : const Color(0xFFD1D5DB);
  }

  static Color keyboardKeyFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkControlBackgroundStrong
        : lightCard;
  }

  static Color controlActiveFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? primaryDarkMode
        : primary;
  }

  static Color onControlActiveFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? onPrimaryDarkMode
        : Colors.white;
  }

  static Color controlBorderFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? primaryDarkModeBorder
        : lightDivider;
  }

  static Color emphasisSoftFor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? darkEmphasisSoft
        : primary.withOpacity(0.08);
  }

  // ==================== 亮色主题 ====================

  /// 极浅灰背景
  static const Color lightBackground = Color(0xFFF6F7F9);

  /// 列表/卡片背景（与主题背景一致，更协调）
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);

  /// 群组标签背景
  static const Color groupTagBackground = Color(0xFFE3F2E8);
  static const Color groupTagText = Color(0xFF4FAE4E);

  /// 频道标签背景
  static const Color channelTagBackground = Color(0xFFE3EFFB);
  static const Color channelTagText = Color(0xFF0088CC);

  /// 聊天背景
  static const Color lightChatBackground = Color(0xFFDFE7EB);

  /// 消息气泡
  static const Color lightBubbleOutgoing = Color(0xFFF3F4F6);
  static const Color lightBubbleIncoming = Color(0xFFFFFFFF);

  /// 文字
  static const Color lightTextPrimary = Color(0xFF111827);
  static const Color lightTextSecondary = Color(0xFF6B7280);
  static const Color lightTextTertiary = Color(0xFF9CA3AF);

  /// 分割线
  static const Color lightDivider = Color(0xFFE5E5E5);

  /// 输入框
  static const Color lightInputBackground = Color(0xFFF1F2F4);

  // ==================== 暗色主题 (OLED 纯黑) ====================

  static const Color darkBackground = Color(0xFF0E1116);
  static const Color darkSurface = Color(0xFF151920);
  static const Color darkCard = Color(0xFF1B2028);

  static const Color darkChatBackground = Color(0xFF111820);

  // 深色模式气泡 - 更高对比度
  static const Color darkBubbleOutgoing = Color(0xFF243447); // 深蓝灰发送气泡
  static const Color darkBubbleIncoming = Color(0xFF1D242D); // 深灰接收气泡

  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFC3CAD4);
  static const Color darkTextTertiary = Color(0xFF8D97A6);
  static const Color darkTextDisabled = Color(0xFF677281);

  static const Color darkDivider = Color(0xFF2C333D);
  static const Color darkInputBackground = Color(0xFF20252D);

  // ==================== 语义颜色 ====================

  static const Color success = Color(0xFF4FAE4E);
  static const Color warning = Color(0xFFE99917);
  static const Color error = Color(0xFFE53935);
  static const Color info = Color(0xFF0088CC);

  static const Color online = Color(0xFF4FAE4E);
  static const Color offline = Color(0xFF8A8A8A);

  static const Color unreadBadge = Color(0xFF0088CC);
  static const Color mutedBadge = Color(0xFF8A8A8A);

  static const Color messageRead = Color(0xFF4FAE4E);

  // ==================== 通话/会议灰色图标组 ====================

  static const Color callMeetingIcon = Color(0xFF6B7280);
  static const Color callMeetingIconDark = Color(0xFFD1D5DB);
  static const Color callMeetingIconBackground = Color(0xFFF3F4F6);
  static const Color callMeetingIconBackgroundDark = Color(0xFF2C2F33);
  static const Color callMeetingIconBorder = Color(0xFFE5E7EB);
  static const Color callMeetingIconBorderDark = Color(0xFF3F444B);

  // ==================== 头像颜色 (TG 风格) ====================

  /// 未设置头像时的统一默认色（注册默认头像统一风格）
  static const Color defaultAvatarColor = Color(0xFF374151);

  static const List<Color> avatarColors = [
    Color(0xFFE17076), // 红
    Color(0xFFECA749), // 橙
    Color(0xFF7BC862), // 绿
    Color(0xFF65AADD), // 蓝
    Color(0xFF6B7280), // 灰
    Color(0xFF9CA3AF), // 浅灰
    Color(0xFF6EC9CB), // 青
    Color(0xFFFAA774), // 杏
  ];

  static Color getAvatarColor(String odId) {
    final hash = odId.hashCode;
    return avatarColors[hash.abs() % avatarColors.length];
  }

  static List<Color> getAvatarGradient(String odId) {
    final color = getAvatarColor(odId);
    return [color, color.withOpacity(0.8)];
  }

  // ==================== 聊天背景 ====================

  static const List<Color> chatBackgroundOptions = [
    Color(0xFFDFE7EB),
    Color(0xFFCCE5D6),
    Color(0xFFE5DFD0),
    Color(0xFFE5E7EB),
    Color(0xFFD0E0E5),
    Color(0xFFE5D0D8),
  ];

  static const List<LinearGradient> chatBackgroundGradients = [
    LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFFDFE7EB), Color(0xFFC5D6DC)],
    ),
  ];
}
