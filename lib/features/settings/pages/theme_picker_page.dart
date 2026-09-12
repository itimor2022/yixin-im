import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_theme_preset.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/themed_app_bar.dart';

class ThemePickerPage extends ConsumerWidget {
  const ThemePickerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentPreset = ref.watch(appThemePresetProvider);
    final currentMode = ref.watch(themeModeProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final isEnglish = l10n.language == AppLanguage.en;

    return Scaffold(
      appBar: ThemedAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(l10n.themePickerTitle),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionTitle(title: l10n.themeModeSection),
          const SizedBox(height: 8),
          _ModeSelector(currentMode: currentMode),
          const SizedBox(height: 28),
          _SectionTitle(title: l10n.themeColorSection),
          const SizedBox(height: 12),
          ...AppThemePreset.values.map((preset) {
            final colors = AppThemePresets.of(preset);
            final isSelected = currentPreset == preset;
            return _ThemePresetCard(
              colors: colors,
              isSelected: isSelected,
              isDark: isDark,
              isEnglish: isEnglish,
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(appThemePresetProvider.notifier).setPreset(preset);
              },
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ── 标题 ────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.textSecondaryFor(context),
        ),
      ),
    );
  }
}

// ── 亮暗模式选择器 ──────────────────────────────────────────
class _ModeSelector extends ConsumerWidget {
  final ThemeMode currentMode;
  const _ModeSelector({required this.currentMode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = Theme.of(context).colorScheme.primary;
    final l10n = AppLocalizations.of(context);
    final options = [
      (ThemeMode.light, Icons.light_mode_rounded, l10n.themeModeLight),
      (ThemeMode.system, Icons.brightness_auto_rounded, l10n.themeModeSystem),
      (ThemeMode.dark, Icons.dark_mode_rounded, l10n.themeModeDark),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: options.map((opt) {
          final (mode, icon, label) = opt;
          final isSelected = currentMode == mode;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(themeModeProvider.notifier).setThemeMode(mode);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 22,
                      color: isSelected
                          ? Colors.white
                          : AppColors.textSecondaryFor(context),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected
                            ? Colors.white
                            : AppColors.textSecondaryFor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── 主题预设卡片 ────────────────────────────────────────────
class _ThemePresetCard extends StatelessWidget {
  final AppThemeColors colors;
  final bool isSelected;
  final bool isDark;
  final bool isEnglish;
  final VoidCallback onTap;

  const _ThemePresetCard({
    required this.colors,
    required this.isSelected,
    required this.isDark,
    required this.isEnglish,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryC = isDark ? colors.darkPrimary : colors.lightPrimary;
    final bgC = isDark ? colors.darkBackground : colors.lightBackground;
    final appBarC = isDark ? colors.darkAppBar : colors.lightAppBar;
    final bubbleOut =
        isDark ? colors.darkBubbleOutgoing : colors.lightBubbleOutgoing;
    final bubbleIn =
        isDark ? colors.darkBubbleIncoming : colors.lightBubbleIncoming;
    final navC = isDark ? colors.darkNavBar : colors.lightNavBar;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? primaryC : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            // ── 预览 mockup ──
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: _PreviewMockup(
                bgColor: bgC,
                appBarColor: appBarC,
                bubbleOutColor: bubbleOut,
                bubbleInColor: bubbleIn,
                primaryColor: primaryC,
                accentColor: colors.primaryB,
                navColor: navC,
              ),
            ),

            // ── 名称行 ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: colors.primaryGradient,
                    ),
                    child: Center(
                      child: Text(
                        colors.emoji,
                        style: const TextStyle(fontSize: 15),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEnglish ? colors.nameEn : colors.name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimaryFor(context),
                        ),
                      ),
                      Text(
                        isEnglish ? colors.name : colors.nameEn,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondaryFor(context),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  AnimatedScale(
                    scale: isSelected ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: colors.primaryGradient,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 手机界面 Mockup ─────────────────────────────────────────
class _PreviewMockup extends StatelessWidget {
  final Color bgColor;
  final Color appBarColor;
  final Color bubbleOutColor;
  final Color bubbleInColor;
  final Color primaryColor;
  final Color accentColor;
  final Color navColor;

  const _PreviewMockup({
    required this.bgColor,
    required this.appBarColor,
    required this.bubbleOutColor,
    required this.bubbleInColor,
    required this.primaryColor,
    required this.accentColor,
    required this.navColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      color: bgColor,
      child: Column(
        children: [
          // AppBar
          Container(
            height: 32,
            color: appBarColor,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.3),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 60,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const Spacer(),
                Icon(Icons.more_vert,
                    size: 14, color: Colors.white.withOpacity(0.7)),
              ],
            ),
          ),

          // 聊天内容
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // 对方气泡（左）
                  Row(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accentColor.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _Bubble(
                          color: bubbleInColor,
                          width: 70,
                          align: Alignment.centerLeft),
                    ],
                  ),
                  // 自己气泡（右）
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _Bubble(
                          color: bubbleOutColor,
                          width: 55,
                          align: Alignment.centerRight),
                    ],
                  ),
                  // 对方气泡（左，短）
                  Row(
                    children: [
                      const SizedBox(width: 22),
                      _Bubble(
                          color: bubbleInColor,
                          width: 45,
                          align: Alignment.centerLeft),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 底部输入框
          Container(
            height: 22,
            color: navColor,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [primaryColor, accentColor],
                    ),
                  ),
                  child: const Icon(Icons.send_rounded,
                      size: 9, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Color color;
  final double width;
  final Alignment align;
  const _Bubble(
      {required this.color, required this.width, required this.align});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
    );
  }
}
