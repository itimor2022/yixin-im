import 'package:flutter/material.dart';

/// 会员徽章 Widget
/// 在昵称旁边显示彩色徽章，如 [PREMIUM] [VIP] 等
class MemberBadgeWidget extends StatelessWidget {
  final bool isMember;
  final String? badgeText;
  final String? badgeColor;
  final double fontSize;
  final EdgeInsets? margin;

  const MemberBadgeWidget({
    super.key,
    required this.isMember,
    this.badgeText,
    this.badgeColor,
    this.fontSize = 10,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    if (!isMember || badgeText == null || badgeText!.isEmpty) {
      return const SizedBox.shrink();
    }

    Color bgColor = const Color(0xFF3390EC);
    try {
      final hex = (badgeColor ?? '#3390EC').replaceAll('#', '');
      if (hex.length == 6) {
        bgColor = Color(int.parse('FF$hex', radix: 16));
      } else if (hex.length == 8) {
        bgColor = Color(int.parse(hex, radix: 16));
      }
    } catch (_) {}

    return Container(
      margin: margin ?? const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        badgeText!,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.2,
        ),
      ),
    );
  }
}
