import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

class PremiumThemeTokens {
  PremiumThemeTokens._();

  static bool isPremium(String? premiumType) =>
      premiumType == 'yearly' || premiumType == 'quarterly';

  static bool isSemanticState(String? premiumType) =>
      premiumType == 'warning' || premiumType == 'neutral';

  static bool hasThemedStyle(String? premiumType) =>
      isPremium(premiumType) || isSemanticState(premiumType);

  static bool isYearly(String? premiumType) => premiumType == 'yearly';

  static bool isQuarterly(String? premiumType) => premiumType == 'quarterly';

  static Color accent(String? premiumType) {
    if (premiumType == 'yearly') return const Color(0xFFE7C469);
    if (premiumType == 'quarterly') return const Color(0xFF7C7CFF);
    if (premiumType == 'warning') return const Color(0xFFF59E0B);
    if (premiumType == 'neutral') return const Color(0xFF64748B);
    return AppColors.primary;
  }

  static Color glow(String? premiumType) {
    if (premiumType == 'yearly') return const Color(0xFFD4A64A);
    if (premiumType == 'quarterly') return const Color(0xFF5B5FFB);
    if (premiumType == 'warning') return const Color(0xFFF59E0B);
    if (premiumType == 'neutral') return const Color(0xFF94A3B8);
    return AppColors.primary;
  }

  static List<Color> avatarRingGradient(String? premiumType) {
    if (premiumType == 'yearly') {
      return const [
        Color(0xFFFFF1B8),
        Color(0xFFFFD76A),
        Color(0xFFFFB800),
        Color(0xFF8A5A00),
      ];
    }
    if (premiumType == 'quarterly') {
      return const [
        Color(0xFFB8A8FF),
        Color(0xFF7C7CFF),
        Color(0xFF4F46E5),
        Color(0xFF00C2FF),
      ];
    }
    if (premiumType == 'warning') {
      return const [
        Color(0xFFFDE68A),
        Color(0xFFF59E0B),
        Color(0xFFFB923C),
      ];
    }
    if (premiumType == 'neutral') {
      return const [
        Color(0xFFE2E8F0),
        Color(0xFF94A3B8),
        Color(0xFF64748B),
      ];
    }
    return const [Color(0xFF60A5FA), Color(0xFF22D3EE), Color(0xFFA78BFA)];
  }

  static List<Color> inlineChipGradient(String? premiumType) {
    if (premiumType == 'yearly') {
      return const [Color(0x44E7C469), Color(0x24B78A32), Color(0x160D0A05)];
    }
    if (premiumType == 'quarterly') {
      return const [Color(0x227C7CFF), Color(0x1A4F46E5), Color(0x1600C2FF)];
    }
    if (premiumType == 'warning') {
      return const [Color(0x26F59E0B), Color(0x1EFB923C)];
    }
    if (premiumType == 'neutral') {
      return const [Color(0x2494A3B8), Color(0x1A64748B)];
    }
    return const [Color(0x1A6366F1), Color(0x1438BDF8)];
  }

  static List<Color> bubbleGradient(String? premiumType, Color baseColor) {
    if (premiumType == 'yearly') {
      return [
        baseColor,
        const Color(0xFFE7C469).withOpacity(0.14),
        const Color(0xFF9A7428).withOpacity(0.08),
      ];
    }
    if (premiumType == 'quarterly') {
      return [
        baseColor,
        const Color(0xFF7C7CFF).withOpacity(0.22),
        const Color(0xFF00C2FF).withOpacity(0.14),
      ];
    }
    if (premiumType == 'warning') {
      return [
        baseColor,
        const Color(0xFFF59E0B).withOpacity(0.18),
        const Color(0xFFFB923C).withOpacity(0.12),
      ];
    }
    if (premiumType == 'neutral') {
      return [
        baseColor,
        const Color(0xFF94A3B8).withOpacity(0.18),
        const Color(0xFFCBD5E1).withOpacity(0.12),
      ];
    }
    return [baseColor, const Color(0xFF818CF8).withOpacity(0.26)];
  }

  static List<Color> cardGradient(String? premiumType, Color baseColor) {
    if (premiumType == 'yearly') {
      return [
        baseColor,
        const Color(0x0E000000),
        const Color(0x16E7C469),
        const Color(0x129A7428),
      ];
    }
    if (premiumType == 'quarterly') {
      return [
        baseColor,
        const Color(0x227C7CFF),
        const Color(0x184F46E5),
        const Color(0x1400C2FF),
      ];
    }
    if (premiumType == 'warning') {
      return [
        baseColor,
        const Color(0x1EFDE68A),
        const Color(0x18F59E0B),
        const Color(0x12FB923C),
      ];
    }
    if (premiumType == 'neutral') {
      return [
        baseColor,
        const Color(0x1EE2E8F0),
        const Color(0x1894A3B8),
        const Color(0x1264748B),
      ];
    }
    return [baseColor, const Color(0x1A818CF8)];
  }

  static Color badgeFill(String? premiumType) {
    if (premiumType == 'yearly') return const Color(0x36E7C469);
    if (premiumType == 'quarterly') return const Color(0x227C7CFF);
    if (premiumType == 'warning') return const Color(0x26F59E0B);
    if (premiumType == 'neutral') return const Color(0x2494A3B8);
    return accent(premiumType).withOpacity(0.14);
  }
}
