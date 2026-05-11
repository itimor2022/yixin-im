import 'package:flutter/material.dart';

/// 风格配色
class AppColors {
  AppColors._();

  // ====================  靛蓝紫（高级科技感） ====================
  
  static const Color primary = Color(0xFF6366F1);
  static const Color primaryLight = Color(0xFF818CF8);
  static const Color primaryDark = Color(0xFF4F46E5);
  
  /// 渐变（蓝紫渐变，非常高级）
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
  );

  // ==================== 亮色主题 ====================
  
  /// 极浅灰背景
  static const Color lightBackground = Color(0xFFF7F7F7);
  /// 列表/卡片背景（与主题背景一致，更协调）
  static const Color lightSurface = Color(0xFFF7F7F7);
  static const Color lightCard = Color(0xFFF7F7F7);
  
  /// 群组标签背景
  static const Color groupTagBackground = Color(0xFFE3F2E8);
  static const Color groupTagText = Color(0xFF4FAE4E);
  
  /// 频道标签背景
  static const Color channelTagBackground = Color(0xFFE3EFFB);
  static const Color channelTagText = Color(0xFF0088CC);
  
  /// 聊天背景
  static const Color lightChatBackground = Color(0xFFDFE7EB);
  
  /// 消息气泡
  static const Color lightBubbleOutgoing = Color(0xFFEFFEDD);
  static const Color lightBubbleIncoming = Color(0xFFFFFFFF);
  
  /// 文字
  static const Color lightTextPrimary = Color(0xFF000000);
  static const Color lightTextSecondary = Color(0xFF8A8A8A);
  static const Color lightTextTertiary = Color(0xFFAAAAAA);
  
  /// 分割线
  static const Color lightDivider = Color(0xFFE5E5E5);
  
  /// 输入框
  static const Color lightInputBackground = Color(0xFFF0F0F0);

  // ==================== 暗色主题 (OLED 纯黑) ====================
  
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF0D0D0D);
  static const Color darkCard = Color(0xFF0D0D0D);
  
  static const Color darkChatBackground = Color(0xFF000000);
  
  // 深色模式气泡 - 更高对比度
  static const Color darkBubbleOutgoing = Color(0xFF2B5278);   // 深蓝色发送气泡
  static const Color darkBubbleIncoming = Color(0xFF1E1E1E);   // 深灰色接收气泡（稍亮一点）
  
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFF8A8A8A);
  static const Color darkTextTertiary = Color(0xFF555555);
  
  static const Color darkDivider = Color(0xFF2A2A2A);
  static const Color darkInputBackground = Color(0xFF1A1A1A);

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

  // ==================== 头像颜色 (TG 风格) ====================
  
  /// 未设置头像时的统一默认色（注册默认头像统一风格）
  static const Color defaultAvatarColor = Color(0xFF65AADD);

  static const List<Color> avatarColors = [
    Color(0xFFE17076),  // 红
    Color(0xFFECA749),  // 橙
    Color(0xFF7BC862),  // 绿
    Color(0xFF65AADD),  // 蓝
    Color(0xFFA695E7),  // 紫
    Color(0xFFEE7AAE),  // 粉
    Color(0xFF6EC9CB),  // 青
    Color(0xFFFAA774),  // 杏
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
    Color(0xFFD8D0E5),
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
