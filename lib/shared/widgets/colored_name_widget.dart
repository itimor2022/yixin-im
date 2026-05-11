import 'package:flutter/material.dart';

import '../../core/theme/premium_theme_tokens.dart';
import 'premium_widgets.dart';

/// 带颜色的名称显示组件
class ColoredNameWidget extends StatelessWidget {
  final String name;
  final String? nicknameColor;
  final double fontSize;
  final FontWeight fontWeight;
  final Color? defaultColor;
  final int? maxLines;
  final TextOverflow? overflow;
  final String? premiumType;

  const ColoredNameWidget({
    super.key,
    required this.name,
    this.nicknameColor,
    this.fontSize = 16,
    this.fontWeight = FontWeight.w500,
    this.defaultColor,
    this.maxLines,
    this.overflow,
    this.premiumType,
  });

  // 昵称颜色列表（与 personalization_page.dart 保持一致）
  static const List<dynamic> _nameColors = [
    Color(0xFF3390EC), // 蓝色
    Color(0xFF4FAE4E), // 绿色
    Color(0xFFF5A623), // 橙色
    Color(0xFFE05656), // 红色
    Color(0xFF9B7CE0), // 紫色
    Color(0xFF50B6C5), // 青色
    Color(0xFFFF7EB3), // 粉色
    Color(0xFF7D8B99), // 灰色
    // 双色渐变
    [Color(0xFF5B9EE1), Color(0xFF54C7A6)],
    [Color(0xFF54C7A6), Color(0xFFB8E986)],
    [Color(0xFFF5A623), Color(0xFFE05656)],
    [Color(0xFF9B7CE0), Color(0xFF50B6C5)],
    [Color(0xFF50B6C5), Color(0xFF5B9EE1)],
    [Color(0xFFFF7EB3), Color(0xFFF5A623)],
    [Color(0xFF5B9EE1), Color(0xFF9B7CE0)],
    [Color(0xFFE05656), Color(0xFF9B7CE0)],
  ];

  /// 解析昵称颜色
  dynamic _getNameColor() {
    if (nicknameColor == null || nicknameColor!.isEmpty) return null;

    final parts = nicknameColor!.split(',');
    for (final part in parts) {
      if (part.startsWith('name:')) {
        final index = int.tryParse(part.substring(5)) ?? 0;
        final clampedIndex = index.clamp(0, _nameColors.length - 1);
        return _nameColors[clampedIndex];
      }
    }
    return null;
  }

  String? _normalizePremiumType() {
    final type = premiumType?.trim();
    if (type == null || type.isEmpty) return null;
    if (PremiumThemeTokens.isPremium(type)) return type;

    final normalized = type.toLowerCase();
    if (normalized.contains('year') || normalized.contains('annual')) {
      return 'yearly';
    }
    if (normalized.contains('quarter') || normalized.contains('season')) {
      return 'quarterly';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final normalizedPremiumType = _normalizePremiumType();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorItem = _getNameColor();
    final fallbackColor =
        defaultColor ?? (isDark ? Colors.white : Colors.black);

    Widget nameWidget;
    if (colorItem == null) {
      nameWidget = Text(
        name,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: fallbackColor,
        ),
        maxLines: maxLines,
        overflow: overflow,
      );
    } else {
      final isGradient = colorItem is List<Color>;
      if (isGradient) {
        nameWidget = ShaderMask(
          shaderCallback: (bounds) =>
              LinearGradient(colors: colorItem).createShader(bounds),
          child: Text(
            name,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              color: Colors.white,
            ),
            maxLines: maxLines,
            overflow: overflow,
          ),
        );
      } else {
        nameWidget = Text(
          name,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: colorItem as Color,
          ),
          maxLines: maxLines,
          overflow: overflow,
        );
      }
    }

    if (!PremiumThemeTokens.isPremium(normalizedPremiumType)) {
      return nameWidget;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: nameWidget),
        const SizedBox(width: 4),
        PremiumChip(
          label: 'PRO',
          premiumType: normalizedPremiumType,
          fontSize: 10,
        ),
      ],
    );
  }
}
