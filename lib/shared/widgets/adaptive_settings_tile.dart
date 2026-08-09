// 文件用途：提供 AdaptiveSettingsTapTile 可复用界面组件，服务于跨模块共享能力。
// 核心逻辑：根据输入模型和状态渲染 AdaptiveSettingsTapTile，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 关键声明：adaptive settings tile 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// A settings row that keeps short status text inline and automatically moves
/// long/localized text below the title before either side becomes unreadable.
class AdaptiveSettingsTapTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final TextStyle titleStyle;
  final TextStyle subtitleStyle;
  final Color chevronColor;
  final VoidCallback? onTap;
  final bool isLoading;
  final bool showChevron;
  final bool forceSubtitleBelowTitle;
  final EdgeInsetsGeometry padding;

  const AdaptiveSettingsTapTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.titleStyle,
    required this.subtitleStyle,
    required this.chevronColor,
    required this.onTap,
    this.isLoading = false,
    this.showChevron = true,
    this.forceSubtitleBelowTitle = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  });

  double _singleLineWidth(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  @override
  Widget build(BuildContext context) {
    final effectiveSubtitle = subtitle?.trim();
    final hasSubtitle = effectiveSubtitle?.isNotEmpty == true;

    return InkWell(
      onTap: isLoading || onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasTrailing = isLoading || showChevron;
            final contentWidth = constraints.maxWidth -
                (hasTrailing ? 28 : 0) -
                (hasTrailing ? 8 : 0);
            final shouldStack = hasSubtitle &&
                (forceSubtitleBelowTitle ||
                    _singleLineWidth(context, title, titleStyle) +
                            _singleLineWidth(
                              context,
                              effectiveSubtitle!,
                              subtitleStyle,
                            ) +
                            16 >
                        contentWidth);

            final textContent = shouldStack
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: titleStyle,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        effectiveSubtitle!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: subtitleStyle,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                      ),
                      if (hasSubtitle) ...[
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            effectiveSubtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: subtitleStyle,
                          ),
                        ),
                      ],
                    ],
                  );

            return Row(
              crossAxisAlignment: shouldStack
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Expanded(child: textContent),
                if (hasTrailing) const SizedBox(width: 8),
                if (isLoading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: subtitleStyle.color,
                    ),
                  )
                else if (showChevron)
                  Icon(Icons.chevron_right, size: 20, color: chevronColor),
              ],
            );
          },
        ),
      ),
    );
  }
}
