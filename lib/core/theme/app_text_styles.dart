// 文件用途：定义 AppTextStyles 相关主题、颜色或视觉样式，供应用界面统一使用。
// 核心逻辑：定义 AppTextStyles 的颜色、字体或组件样式，供主题构建和系统 UI 适配统一复用。
import 'package:flutter/material.dart';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。

// 关键声明：app text styles 统一提供视觉参数或主题对象，避免页面直接写死颜色、字体和尺寸。
/// 现代风格文字样式
class AppTextStyles {
  AppTextStyles._();

  // 使用系统默认字体（iOS: SF Pro, Android: Roboto）
  static const String? _fontFamily = null;

  // ==================== 标题样式 ====================
  
  /// 大标题 - 用于页面标题
  static const TextStyle headline1 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 34,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.5,
    height: 1.2,
  );

  /// 中标题 - 用于导航栏标题
  static const TextStyle headline2 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.3,
    height: 1.3,
  );

  /// 小标题 - 用于列表项标题
  static const TextStyle headline3 = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.3,
  );

  // ==================== 正文样式 ====================
  
  /// 大正文
  static const TextStyle bodyLarge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.normal,
    letterSpacing: -0.2,
    height: 1.4,
  );

  /// 中正文 - 消息内容
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.normal,
    letterSpacing: -0.1,
    height: 1.4,
  );

  /// 小正文
  static const TextStyle bodySmall = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.normal,
    letterSpacing: 0,
    height: 1.4,
  );

  // ==================== 辅助样式 ====================
  
  /// 副标题 - 聊天列表预览
  static const TextStyle subtitle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.normal,
    letterSpacing: -0.1,
    height: 1.3,
  );

  /// 标签文字
  static const TextStyle caption = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 13,
    fontWeight: FontWeight.normal,
    letterSpacing: 0,
    height: 1.3,
  );

  /// 时间戳
  static const TextStyle timestamp = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.normal,
    letterSpacing: 0,
    height: 1.2,
  );

  /// 角标数字
  static const TextStyle badge = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
    height: 1.0,
  );

  // ==================== 按钮样式 ====================
  
  /// 主按钮
  static const TextStyle buttonPrimary = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.2,
  );

  /// 次按钮
  static const TextStyle buttonSecondary = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    letterSpacing: -0.1,
    height: 1.2,
  );

  // ==================== 输入框样式 ====================
  
  /// 输入框文字
  static const TextStyle input = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.normal,
    letterSpacing: -0.2,
    height: 1.4,
  );

  /// 输入框提示
  static const TextStyle inputHint = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.normal,
    letterSpacing: -0.2,
    height: 1.4,
  );

  // ==================== 特殊样式 ====================
  
  /// 链接
  static const TextStyle link = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.normal,
    letterSpacing: -0.1,
    height: 1.4,
    decoration: TextDecoration.none,
  );

  /// 代码
  static const TextStyle code = TextStyle(
    fontFamily: 'SF Mono',
    fontSize: 14,
    fontWeight: FontWeight.normal,
    letterSpacing: 0,
    height: 1.5,
  );

  /// 聊天名称
  static const TextStyle chatName = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
    height: 1.2,
  );

  /// 消息发送者名称（群聊）
  static const TextStyle senderName = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
    height: 1.2,
  );
}
