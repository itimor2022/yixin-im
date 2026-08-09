// 文件用途：提供 IOSPage 可复用界面组件，服务于跨模块共享能力。
// 核心逻辑：根据输入模型和状态渲染 IOSPage，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:universal_io/io.dart' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// 关键声明：page transitions 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 自适应页面：iOS/macOS 保留系统返回手势，其余平台使用 Material 路由。
class IOSPage<T> extends Page<T> {
  final Widget child;
  final bool maintainState;
  final bool fullscreenDialog;

  const IOSPage({
    required this.child,
    this.maintainState = true,
    this.fullscreenDialog = false,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  });

  @override
  Route<T> createRoute(BuildContext context) {
    // maintainState=false 会在页面被覆盖后释放子树，适合可重新加载的重资源页面。
    if (Platform.isIOS || Platform.isMacOS) {
      return CupertinoPageRoute<T>(
        settings: this,
        maintainState: maintainState,
        fullscreenDialog: fullscreenDialog,
        builder: (context) => child,
      );
    }
    // 其他平台使用 MaterialPageRoute
    return MaterialPageRoute<T>(
      settings: this,
      maintainState: maintainState,
      fullscreenDialog: fullscreenDialog,
      builder: (context) => child,
    );
  }
}

/// iOS 风格从底部弹出的页面（modal）
class IOSModalPage<T> extends Page<T> {
  final Widget child;

  const IOSModalPage({
    required this.child,
    super.key,
    super.name,
    super.arguments,
  });

  @override
  Route<T> createRoute(BuildContext context) {
    if (Platform.isIOS || Platform.isMacOS) {
      return CupertinoPageRoute<T>(
        settings: this,
        fullscreenDialog: true,
        builder: (context) => child,
      );
    }
    return MaterialPageRoute<T>(
      settings: this,
      fullscreenDialog: true,
      builder: (context) => child,
    );
  }
}

// 流程逻辑：`fadeTransition` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
/// 淡入淡出过渡
Widget fadeTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  return FadeTransition(
    opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
    child: child,
  );
}

/// 无过渡（瞬间切换，适用于 Tab 页面）
Widget noTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  // 只移除视觉动画，不改变路由焦点、返回栈和子组件语义。
  return child;
}

/// 从右侧滑入
Widget slideFromRightTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final tween = Tween(begin: const Offset(1.0, 0.0), end: Offset.zero);
  final curvedAnimation = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  
  return SlideTransition(
    position: tween.animate(curvedAnimation),
    child: child,
  );
}

/// 从底部滑入
Widget slideFromBottomTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final tween = Tween(begin: const Offset(0.0, 1.0), end: Offset.zero);
  final curvedAnimation = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  
  return SlideTransition(
    position: tween.animate(curvedAnimation),
    child: child,
  );
}

/// 创建支持左滑返回的页面路由
PageRoute<T> createPageRoute<T>({
  required Widget Function(BuildContext) builder,
  bool fullscreenDialog = false,
}) {
  if (Platform.isIOS || Platform.isMacOS) {
    return CupertinoPageRoute<T>(
      builder: builder,
      fullscreenDialog: fullscreenDialog,
    );
  }
  return MaterialPageRoute<T>(
    builder: builder,
    fullscreenDialog: fullscreenDialog,
  );
}

/// 缩放过渡
Widget scaleTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final curvedAnimation = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutBack,
  );
  
  return ScaleTransition(
    scale: Tween(begin: 0.9, end: 1.0).animate(curvedAnimation),
    child: FadeTransition(
      opacity: animation,
      child: child,
    ),
  );
}

/// 共享元素风格过渡（仿 iOS）
Widget sharedAxisTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  // animation 驱动新页面入场，secondaryAnimation 驱动当前页面在下一路由
  // 覆盖时退出；两者不能互换，否则返回动画方向会错误。
  final curvedAnimation = CurvedAnimation(
    parent: animation,
    curve: Curves.easeOutCubic,
  );
  
  final secondaryCurvedAnimation = CurvedAnimation(
    parent: secondaryAnimation,
    curve: Curves.easeOutCubic,
  );
  
  return SlideTransition(
    position: Tween(
      begin: const Offset(0.3, 0.0),
      end: Offset.zero,
    ).animate(curvedAnimation),
    child: FadeTransition(
      opacity: Tween(begin: 0.0, end: 1.0).animate(curvedAnimation),
      child: SlideTransition(
        position: Tween(
          begin: Offset.zero,
          end: const Offset(-0.3, 0.0),
        ).animate(secondaryCurvedAnimation),
        child: child,
      ),
    ),
  );
}
