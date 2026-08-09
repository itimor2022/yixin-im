// 文件用途：提供 VipAvatarFrame 可复用界面组件，服务于会员权益。
// 核心逻辑：根据输入模型和状态渲染 VipAvatarFrame，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'dart:math' as math;

import 'package:flutter/material.dart';

// 关键声明：VIP avatar frame 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
class VipAvatarFrame extends StatelessWidget {
  const VipAvatarFrame({
    super.key,
    required this.level,
    required this.size,
    required this.child,
    this.animated = false,
    this.frameWidth,
    this.borderRadius,
    this.isCircle = false,
  });

  final int level;
  final double size;
  final Widget child;
  final bool animated;
  final double? frameWidth;
  final double? borderRadius;
  final bool isCircle;

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  @override
  Widget build(BuildContext context) {
    if (level <= 0) {
      return child;
    }

    final isSvip = level >= 2;
    final frame = frameWidth ?? (isSvip ? 6.0 : 5.0);
    final totalSize = size + frame * 2;
    final effectiveBorderRadius = isCircle
        ? size / 2
        : math.min(borderRadius ?? size * 0.22, size * 0.28);
    final outerRadius = effectiveBorderRadius + frame;
    final ringColors = isSvip
        ? const [
            Color(0xFFFFE7A8),
            Color(0xFFB9852D),
            Color(0xFFFFF4C8),
            Color(0xFFD4A245),
          ]
        : const [
            Color(0xFFDDE4EE),
            Color(0xFF8EA1B7),
            Color(0xFFF5F7FA),
            Color(0xFF9AAABD),
          ];

    return RepaintBoundary(
      child: SizedBox(
        width: totalSize,
        height: totalSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: totalSize,
              height: totalSize,
              decoration: BoxDecoration(
                shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius:
                    isCircle ? null : BorderRadius.circular(outerRadius),
                gradient: SweepGradient(colors: ringColors),
                boxShadow: [
                  BoxShadow(
                    color: (isSvip
                            ? const Color(0xFFB9852D)
                            : const Color(0xFF8EA1B7))
                        .withOpacity(0.16),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
            Container(
              width: size + 3,
              height: size + 3,
              decoration: BoxDecoration(
                shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: isCircle
                    ? null
                    : BorderRadius.circular(effectiveBorderRadius + 1.5),
                color: Theme.of(context).scaffoldBackgroundColor,
                border: Border.all(
                  color: Colors.white.withOpacity(0.96),
                  width: 2,
                ),
              ),
            ),
            SizedBox(
              width: size,
              height: size,
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}
