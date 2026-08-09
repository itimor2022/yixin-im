// 文件用途：提供 PlatformBlur 可复用界面组件，服务于跨模块共享能力。
// 核心逻辑：根据输入模型和状态渲染 PlatformBlur，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:universal_io/io.dart';
import 'dart:ui';
import 'package:flutter/material.dart';

// 关键声明：platform blur 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 跨平台模糊组件
/// - iOS: 使用 BackdropFilter 毛玻璃效果
/// - Android: 使用半透明背景（性能更好）
class PlatformBlur extends StatelessWidget {
  final Widget child;
  final double blurSigma;
  final Color? backgroundColor;
  final BorderRadius? borderRadius;

  const PlatformBlur({
    super.key,
    required this.child,
    this.blurSigma = 20,
    this.backgroundColor,
    this.borderRadius,
  });

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Android 上使用更高不透明度的纯色背景
    if (Platform.isAndroid) {
      final bgColor = backgroundColor ?? 
          (isDark ? Colors.black.withOpacity(0.92) : Colors.white.withOpacity(0.95));
      
      return Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: borderRadius,
        ),
        child: child,
      );
    }
    
    // iOS 使用毛玻璃效果
    final bgColor = backgroundColor ?? 
        (isDark ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.8));
    
    Widget blurWidget = BackdropFilter(
      filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: borderRadius,
        ),
        child: child,
      ),
    );
    
    if (borderRadius != null) {
      blurWidget = ClipRRect(
        borderRadius: borderRadius!,
        child: blurWidget,
      );
    }
    
    return blurWidget;
  }
}

/// 简化版：用于按钮等小组件
class BlurButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final BorderRadius borderRadius;
  final Color? backgroundColor;

  const BlurButton({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Android: 简单背景
    if (Platform.isAndroid) {
      final bgColor = backgroundColor ?? 
          (isDark ? Colors.grey[850]! : Colors.grey[200]!);
      
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: borderRadius,
          ),
          child: child,
        ),
      );
    }
    
    // iOS: 毛玻璃
    final bgColor = backgroundColor ?? 
        (isDark ? Colors.white.withOpacity(0.15) : Colors.black.withOpacity(0.05));
    
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: borderRadius,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
