import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';
import 'package:visibility_detector/visibility_detector.dart';

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

  @override
  void initState() {
    super.initState();
    _visibilityKey = 'visible_lottie_${++_idCounter}';
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
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
    
    // 如果已经可见，开始播放
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
    return VisibilityDetector(
      key: Key(_visibilityKey),
      onVisibilityChanged: _onVisibilityChanged,
      child: Lottie.asset(
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
      setState(() {
        _isVisible = true;
        _hasPlayed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key(_visibilityKey),
      onVisibilityChanged: _onVisibilityChanged,
      child: _isVisible
          ? Lottie.asset(
              widget.path,
              width: widget.width,
              height: widget.height,
              fit: widget.fit,
              repeat: false,
            )
          : SizedBox(
              width: widget.width,
              height: widget.height,
            ),
    );
  }
}
