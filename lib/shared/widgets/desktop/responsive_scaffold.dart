// 文件用途：实现 ResponsiveScaffold 相关逻辑，服务于跨模块共享能力。
// 核心逻辑：围绕 ResponsiveScaffold 组织，完成输入校验、核心处理和结果回传。
import 'package:flutter/material.dart';

import '../../../core/utils/platform_utils.dart';

// 关键声明：responsive scaffold 把桌面系统能力封装成应用接口，处理窗口、托盘或快捷键生命周期并避免泄漏监听器。
/// 响应式脚手架
/// 根据平台和屏幕宽度自动选择移动端或桌面端布局
class ResponsiveScaffold extends StatelessWidget {
  /// 移动端 Scaffold body
  final Widget mobileBody;

  /// 桌面端布局（可选，默认使用 mobileBody）
  final Widget? desktopBody;

  /// 响应式断点（默认 768）
  final double breakpoint;

  /// AppBar（仅移动端显示）
  final PreferredSizeWidget? appBar;

  /// 底部导航栏（仅移动端显示）
  final Widget? bottomNavigationBar;

  /// FAB（仅移动端显示）
  final Widget? floatingActionButton;

  /// 背景色
  final Color? backgroundColor;

  const ResponsiveScaffold({
    super.key,
    required this.mobileBody,
    this.desktopBody,
    this.breakpoint = 768,
    this.appBar,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.backgroundColor,
  });

  // 流程逻辑：`build` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useDesktop =
            PlatformUtils.useDesktopLayoutForWidth(constraints.maxWidth);

        if (useDesktop && desktopBody != null) {
          // 桌面端布局：不使用 Scaffold 的导航元素
          return Container(
            color: backgroundColor ?? Theme.of(context).scaffoldBackgroundColor,
            child: desktopBody!,
          );
        }

        // 移动端布局：使用标准 Scaffold
        return Scaffold(
          appBar: appBar,
          body: mobileBody,
          bottomNavigationBar: bottomNavigationBar,
          floatingActionButton: floatingActionButton,
          backgroundColor: backgroundColor,
        );
      },
    );
  }
}

/// 根据平台返回不同的 Widget
class PlatformWidget extends StatelessWidget {
  /// 移动端 Widget
  final Widget mobile;

  /// 桌面端 Widget（可选，默认使用 mobile）
  final Widget? desktop;

  /// Web Widget（可选，默认使用 desktop 或 mobile）
  final Widget? web;

  const PlatformWidget({
    super.key,
    required this.mobile,
    this.desktop,
    this.web,
  });

  @override
  Widget build(BuildContext context) {
    if (PlatformUtils.isWeb && web != null) {
      return web!;
    }
    if (PlatformUtils.useDesktopLayout(context) && desktop != null) {
      return desktop!;
    }
    return mobile;
  }
}

/// 条件显示 Widget
class PlatformVisibility extends StatelessWidget {
  final Widget child;

  /// 仅在移动端显示
  final bool mobileOnly;

  /// 仅在桌面端显示
  final bool desktopOnly;

  const PlatformVisibility({
    super.key,
    required this.child,
    this.mobileOnly = false,
    this.desktopOnly = false,
  });

  /// 仅移动端可见
  const PlatformVisibility.mobileOnly({
    super.key,
    required this.child,
  })  : mobileOnly = true,
        desktopOnly = false;

  /// 仅桌面端可见
  const PlatformVisibility.desktopOnly({
    super.key,
    required this.child,
  })  : mobileOnly = false,
        desktopOnly = true;

  @override
  Widget build(BuildContext context) {
    if (mobileOnly && !PlatformUtils.isMobile) {
      return const SizedBox.shrink();
    }
    if (desktopOnly && !PlatformUtils.isPhysicalDesktop) {
      return const SizedBox.shrink();
    }
    return child;
  }
}

/// 自适应间距
class AdaptivePadding extends StatelessWidget {
  final Widget child;
  final EdgeInsets mobilePadding;
  final EdgeInsets desktopPadding;

  const AdaptivePadding({
    super.key,
    required this.child,
    this.mobilePadding = const EdgeInsets.all(16),
    this.desktopPadding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: PlatformUtils.useDesktopLayout(context)
          ? desktopPadding
          : mobilePadding,
      child: child,
    );
  }
}
