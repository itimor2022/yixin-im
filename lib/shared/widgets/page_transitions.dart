import 'package:universal_io/io.dart' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// iOS 风格页面（支持左滑返回）
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
    // iOS 使用 CupertinoPageRoute 支持左滑返回
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
