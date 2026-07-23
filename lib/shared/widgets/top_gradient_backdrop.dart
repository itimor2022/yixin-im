import 'package:flutter/material.dart';

/// 全 App 统一的主色
const Color kAppGradientPrimary = Color(0xFF1A3A6B);
const Color kAppGradientSecondary = Color(0xFFC9A84C);

/// 顶部深蓝色渐变装饰背景（顶部深蓝 → 底部透明）
/// 必须被 IgnorePointer 包裹使用，避免挡住下方内容的点击
class TopGradientBackdrop extends StatelessWidget {
  final double midOpacity;
  final double midStop;

  const TopGradientBackdrop({
    super.key,
    this.midOpacity = 0.22,
    this.midStop = 0.55,
  });

  @override
  Widget build(BuildContext context) {
    final Color midColor = kAppGradientPrimary.withOpacity(midOpacity);
    const Color tailColor = Color(0x001A3A6B); // 深蓝完全透明
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kAppGradientPrimary, kAppGradientPrimary, midColor, tailColor],
          stops: [0.0, 0.35, midStop, 1.0],
        ),
      ),
    );
  }
}
