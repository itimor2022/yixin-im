import 'package:flutter/material.dart';

/// 全 App 统一的主色
///
/// 与 [AppColors.primary] / 底部导航保持一致。抽到这里方便渐变背景
/// 在多个 Tab（聊天 / 联系人 / 我的）里复用同一份颜色源。
const Color kAppGradientPrimary = Color(0xFFFF6B6B);

/// 顶部主色渐变**装饰背景**（三段式）
///
/// 从 `#009fff` → 浅主色 → 完全透明，垂直渐变。用途：叠在页面顶层做
/// header + 搜索栏的背景，尾巴淡出到透明后自然融进下方页面主体。
///
/// 特性：
///   - 无状态、无内容，只画一层 [BoxDecoration]
///   - **必须**被 [IgnorePointer] 包起来使用 —— 否则会挡住下方列表的点击 / 长按 / 左滑
///   - 深浅主题共用同一组颜色（尾巴 stop 完全透明，下面的 Scaffold 会自然显现）
class TopGradientBackdrop extends StatelessWidget {
  /// 中段的主色透明度（默认 0.22，与聊天页一致）
  final double midOpacity;

  /// 中段颜色停止位置（默认 0.55）
  final double midStop;

  const TopGradientBackdrop({
    super.key,
    this.midOpacity = 0.22,
    this.midStop = 0.55,
  });

  @override
  Widget build(BuildContext context) {
    final Color midColor = kAppGradientPrimary.withOpacity(midOpacity);
    const Color tailColor = Color(0x00009CFF); // primary 完全透明
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // stops:
          //   0.00 → 主色（顶部 status bar / header：纯蓝）
          //   midStop → 主色 × midOpacity（大致落在搜索栏中部，周围带淡蓝）
          //   1.00 → 完全透明（尾巴末端 —— 位于页面主体的中部之下）
          colors: [kAppGradientPrimary, midColor, tailColor],
          stops: [0.0, midStop, 1.0],
        ),
      ),
    );
  }
}
