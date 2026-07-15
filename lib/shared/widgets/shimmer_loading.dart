import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Shimmer 加载效果组件
class ShimmerLoading extends StatefulWidget {
  final Widget child;
  final Color? baseColor;
  final Color? highlightColor;
  final Duration duration;

  const ShimmerLoading({
    super.key,
    required this.child,
    this.baseColor,
    this.highlightColor,
    this.duration = const Duration(milliseconds: 1500),
  });

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..repeat();
    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = widget.baseColor ??
        (isDark ? Colors.grey.shade800 : Colors.grey.shade300);
    final highlightColor = widget.highlightColor ??
        (isDark ? Colors.grey.shade700 : Colors.grey.shade100);

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
              stops: [
                0.0,
                0.5 + _animation.value * 0.15,
                1.0,
              ],
              transform: _SlidingGradientTransform(_animation.value),
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform(this.slidePercent);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}

/// 骨架屏占位容器
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double borderRadius;
  final bool isCircle;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.borderRadius = 4,
    this.isCircle = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.grey.shade800 : Colors.grey.shade300;

    return Container(
      width: isCircle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// 聊天列表骨架屏项 —— 匹配 v4 **扁平** 列表样式
///
/// 无卡片、无阴影、无边框，直接在白色 Scaffold 上呈现。
class ChatListSkeletonItem extends StatelessWidget {
  const ChatListSkeletonItem({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBox(width: 52, height: 52, borderRadius: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      SkeletonBox(width: 120, height: 16),
                      Spacer(),
                      SkeletonBox(width: 40, height: 12),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const SkeletonBox(width: 220, height: 14),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 消息列表骨架屏项
class MessageSkeletonItem extends StatelessWidget {
  final bool isMe;

  const MessageSkeletonItem({super.key, this.isMe = false});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          mainAxisAlignment:
              isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe) ...[
              const SkeletonBox(height: 36, isCircle: true),
              const SizedBox(width: 8),
            ],
            Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                SkeletonBox(
                  width: 150 + (isMe ? 0 : 50),
                  height: 40,
                  borderRadius: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 联系人列表骨架屏项
class ContactSkeletonItem extends StatelessWidget {
  const ContactSkeletonItem({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const SkeletonBox(height: 48, isCircle: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(width: 100, height: 16),
                  const SizedBox(height: 4),
                  SkeletonBox(width: 60, height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 动态列表骨架屏项
class MomentSkeletonItem extends StatelessWidget {
  const MomentSkeletonItem({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部
            Row(
              children: [
                const SkeletonBox(height: 40, isCircle: true),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 80, height: 14),
                    const SizedBox(height: 4),
                    SkeletonBox(width: 60, height: 12),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 内容
            SkeletonBox(width: double.infinity, height: 14),
            const SizedBox(height: 8),
            SkeletonBox(width: 200, height: 14),
            const SizedBox(height: 12),
            // 图片
            SkeletonBox(width: double.infinity, height: 150, borderRadius: 8),
          ],
        ),
      ),
    );
  }
}
