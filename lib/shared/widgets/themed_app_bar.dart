import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme_preset.dart';
import '../../core/theme/theme_provider.dart';

/// 全局统一主题渐变 AppBar
class ThemedAppBar extends ConsumerWidget implements PreferredSizeWidget {
  final Widget? title;
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;
  final double elevation;
  final PreferredSizeWidget? bottom;
  // 兼容原始 AppBar 参数（忽略，由主题统一管理）
  final Color? backgroundColor;
  final Color? foregroundColor;
  final Color? surfaceTintColor;

  const ThemedAppBar({
    super.key,
    this.title,
    this.actions,
    this.leading,
    this.centerTitle = true,
    this.elevation = 0,
    this.bottom,
    this.backgroundColor,
    this.foregroundColor,
    this.surfaceTintColor,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        kToolbarHeight + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pc = AppThemePresets.of(ref.watch(appThemePresetProvider));
    final fg = pc.appBarForeground;

    return AppBar(
      backgroundColor: Colors.transparent,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDark
                ? [pc.primaryA.withOpacity(0.9), pc.primaryB.withOpacity(0.7)]
                : [pc.primaryA, pc.primaryB],
          ),
        ),
      ),
      surfaceTintColor: Colors.transparent,
      elevation: elevation,
      centerTitle: centerTitle,
      iconTheme: IconThemeData(color: fg, size: 24),
      actionsIconTheme: IconThemeData(color: fg, size: 24),
      title: title != null
          ? DefaultTextStyle.merge(
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
              child: title!,
            )
          : null,
      actions: actions,
      leading: leading,
      bottom: bottom,
    );
  }
}
