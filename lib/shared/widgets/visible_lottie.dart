// 文件用途：提供 VisibleLottie 可复用界面组件，服务于跨模块共享能力。
// 核心逻辑：根据输入模型和状态渲染 VisibleLottie，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../core/constants/emoji_animations.dart';
import 'web_safe_lottie.dart';

String _webLottieFallbackEmoji(String path) {
  for (final emoji in EmojiAnimations.all) {
    if (emoji.path == path) return emoji.emoji;
  }
  return '*';
}

Widget _buildWebLottieFallback({
  required String path,
  double? width,
  double? height,
}) {
  return SizedBox(
    width: width,
    height: height,
    child: Center(
      child: Text(
        _webLottieFallbackEmoji(path),
        style: TextStyle(fontSize: (width ?? height ?? 24) * 0.72),
      ),
    ),
  );
}

// 关键声明：visible lottie 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 可见性感知的 Lottie 动画组件
///
/// 只在组件可见时播放动画，不可见时暂停，优化性能
class VisibleLottie extends StatefulWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool repeat;
  final double visibilityThreshold;

  const VisibleLottie({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.repeat = true,
    // visibleFraction 达到该阈值才播放，调用方应传 0 到 1 之间的比例。
    this.visibilityThreshold = 0.1, // 10% 可见时开始播放
  });

  @override
  State<VisibleLottie> createState() => _VisibleLottieState();
}

class _VisibleLottieState extends State<VisibleLottie>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isVisible = false;
  bool _isLoaded = false;

  // 用于生成唯一的 key
  static int _idCounter = 0;
  late final String _visibilityKey;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _visibilityKey = 'visible_lottie_${++_idCounter}';
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    // AnimationController 持有 ticker，离开列表后必须释放以停止逐帧回调。
    _controller.dispose();
    super.dispose();
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    // 检查是否已 dispose，避免在 dispose 后调用 controller
    if (!mounted) return;

    final wasVisible = _isVisible;
    _isVisible = info.visibleFraction >= widget.visibilityThreshold;

    if (_isVisible != wasVisible && _isLoaded) {
      if (_isVisible) {
        if (widget.repeat) {
          _controller.repeat();
        } else {
          _controller.forward();
        }
      } else {
        _controller.stop();
      }
    }
  }

  void _onLoaded(LottieComposition composition) {
    if (!mounted) return;

    _isLoaded = true;
    _controller.duration = composition.duration;

    // 可见性回调可能早于资源解析完成，加载后需补一次启动判断。
    if (_isVisible) {
      if (widget.repeat) {
        _controller.repeat();
      } else {
        _controller.forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebLottieFallback(
        path: widget.path,
        width: widget.width,
        height: widget.height,
      );
    }
    return VisibilityDetector(
      key: Key(_visibilityKey),
      onVisibilityChanged: _onVisibilityChanged,
      child: WebSafeLottie.asset(
        widget.path,
        controller: _controller,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        onLoaded: _onLoaded,
      ),
    );
  }
}

/// 简化版：仅在首次可见时播放一次
class VisibleLottieOnce extends StatefulWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;

  const VisibleLottieOnce({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
  });

  @override
  State<VisibleLottieOnce> createState() => _VisibleLottieOnceState();
}

class _VisibleLottieOnceState extends State<VisibleLottieOnce> {
  bool _hasPlayed = false;
  bool _isVisible = false;

  static int _idCounter = 0;
  late final String _visibilityKey;

  @override
  void initState() {
    super.initState();
    _visibilityKey = 'visible_lottie_once_${++_idCounter}';
  }

  void _onVisibilityChanged(VisibilityInfo info) {
    if (!_hasPlayed && info.visibleFraction > 0.1) {
      // 一旦达到阈值便永久标记，本组件滚出再进入时不会重新播放。
      setState(() {
        _isVisible = true;
        _hasPlayed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _buildWebLottieFallback(
        path: widget.path,
        width: widget.width,
        height: widget.height,
      );
    }
    return VisibilityDetector(
      key: Key(_visibilityKey),
      onVisibilityChanged: _onVisibilityChanged,
      child: _isVisible
          ? WebSafeLottie.asset(
              widget.path,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              repeat: false,
            )
          // 加载前保留调用方给定尺寸，避免列表首次可见时发生布局跳动。
          : SizedBox(
              width: widget.width,
              height: widget.height,
            ),
    );
  }
}
