// 文件用途：提供 AnimatedGifImage 可复用界面组件，服务于跨模块共享能力。
// 核心逻辑：根据输入模型和状态渲染 AnimatedGifImage，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'web_safe_lottie.dart';
import 'package:universal_io/io.dart';

import '../../core/services/api/api_client.dart';

// 关键声明：animated gif image 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
class AnimatedGifImage extends StatefulWidget {
  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool repeat;
  final Widget? placeholder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  const AnimatedGifImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.repeat = true,
    this.placeholder,
    this.errorBuilder,
  });

  static bool isGifSource(String? value) {
    if (value == null || value.isEmpty) return false;
    // 只依据 URI path 判断，查询参数不会影响媒体类型识别。
    final path = Uri.tryParse(value)?.path.toLowerCase() ?? value.toLowerCase();
    return path.endsWith('.gif');
  }

  @override
  State<AnimatedGifImage> createState() => _AnimatedGifImageState();
}

class AnimatedStickerImage extends StatelessWidget {
  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool repeat;
  final bool animate;
  final Widget? placeholder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  const AnimatedStickerImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.repeat = true,
    this.animate = true,
    this.placeholder,
    this.errorBuilder,
  });

  static bool isLottieSource(String? value) {
    if (value == null || value.isEmpty) return false;
    final path = Uri.tryParse(value)?.path.toLowerCase() ?? value.toLowerCase();
    return path.endsWith('.json') || path.endsWith('.tgs');
  }

  static bool isTgsSource(String? value) {
    if (value == null || value.isEmpty) return false;
    final path = Uri.tryParse(value)?.path.toLowerCase() ?? value.toLowerCase();
    return path.endsWith('.tgs');
  }

  @override
  Widget build(BuildContext context) {
    final resolvedSource = _resolveSource(source);

    // 同一入口按扩展名分派 GIF、TGS、Lottie；非 Lottie 统一交给帧解码器。
    if (!isLottieSource(resolvedSource)) {
      return AnimatedGifImage(
        source: resolvedSource,
        width: width,
        height: height,
        fit: fit,
        repeat: repeat,
        placeholder: placeholder,
        errorBuilder: errorBuilder,
      );
    }

    if (isTgsSource(resolvedSource)) {
      return _TgsLottieImage(
        source: resolvedSource,
        width: width,
        height: height,
        fit: fit,
        repeat: repeat,
        animate: animate,
        placeholder: placeholder,
        errorBuilder: errorBuilder,
      );
    }

    if (_isRemoteSource(resolvedSource)) {
      return Lottie.network(
        resolvedSource,
        width: width,
        height: height,
        fit: fit,
        repeat: repeat,
        animate: animate,
        errorBuilder: errorBuilder == null
            ? null
            : (context, error, stackTrace) => errorBuilder!(context, error),
      );
    }

    if (!kIsWeb && _isLocalFilePath(resolvedSource)) {
      return Lottie.file(
        File(resolvedSource),
        width: width,
        height: height,
        fit: fit,
        repeat: repeat,
        animate: animate,
        errorBuilder: errorBuilder == null
            ? null
            : (context, error, stackTrace) => errorBuilder!(context, error),
      );
    }

    return WebSafeLottie.asset(
      resolvedSource,
      width: width,
      height: height,
      fit: fit,
      repeat: repeat,
      animate: animate,
      errorBuilder: errorBuilder == null
          ? null
          : (context, error, stackTrace) => errorBuilder!(context, error),
    );
  }

  bool _isLocalFilePath(String value) {
    if (value.startsWith('assets/')) return false;
    if (value.startsWith('/')) return true;
    return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
  }

  static String _resolveSource(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.startsWith('/uploads/') ||
        normalized.startsWith('uploads/')) {
      return ApiConfig.getMediaUrl(normalized);
    }
    return normalized;
  }

  static bool _isRemoteSource(String value) =>
      value.startsWith('http://') || value.startsWith('https://');
}

class _TgsLottieImage extends StatefulWidget {
  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool repeat;
  final bool animate;
  final Widget? placeholder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  const _TgsLottieImage({
    required this.source,
    this.width,
    this.height,
    required this.fit,
    required this.repeat,
    required this.animate,
    this.placeholder,
    this.errorBuilder,
  });

  @override
  State<_TgsLottieImage> createState() => _TgsLottieImageState();
}

class _TgsLottieImageState extends State<_TgsLottieImage> {
  late Future<Uint8List> _future;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _future = _loadTgsJsonBytes(widget.source);
  }

  @override
  void didUpdateWidget(covariant _TgsLottieImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) {
      _future = _loadTgsJsonBytes(widget.source);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return widget.errorBuilder?.call(context, snapshot.error!) ??
              const SizedBox.shrink();
        }
        final data = snapshot.data;
        if (data == null) {
          return widget.placeholder ?? const SizedBox.shrink();
        }
        return Lottie.memory(
          data,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          repeat: widget.repeat,
          animate: widget.animate,
          errorBuilder: widget.errorBuilder == null
              ? null
              : (context, error, stackTrace) =>
                  widget.errorBuilder!(context, error),
        );
      },
    );
  }

  Future<Uint8List> _loadTgsJsonBytes(String source) async {
    // TGS 是 gzip 压缩的 Lottie JSON，解压或解析失败统一进入 errorBuilder。
    final raw = await _loadBytes(source);
    return Uint8List.fromList(gzip.decode(raw));
  }

  Future<Uint8List> _loadBytes(String source) async {
    final resolvedSource = _resolveSource(source);

    if (resolvedSource.startsWith('http://') ||
        resolvedSource.startsWith('https://')) {
      final data = await NetworkAssetBundle(Uri.parse(resolvedSource))
          .load(resolvedSource);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }

    if (!kIsWeb && _isLocalFilePath(resolvedSource)) {
      return File(resolvedSource).readAsBytes();
    }

    final data = await rootBundle.load(resolvedSource);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  bool _isLocalFilePath(String value) {
    if (value.startsWith('assets/')) return false;
    if (value.startsWith('/')) return true;
    return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
  }

  String _resolveSource(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.startsWith('/uploads/') ||
        normalized.startsWith('uploads/')) {
      return ApiConfig.getMediaUrl(normalized);
    }
    return normalized;
  }
}

class _AnimatedGifImageState extends State<AnimatedGifImage> {
  ui.Codec? _codec;
  ui.Image? _image;
  Timer? _timer;
  Object? _error;
  int _generation = 0;
  int _frameIndex = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AnimatedGifImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        oldWidget.repeat != widget.repeat) {
      _load();
    }
  }

  @override
  void dispose() {
    // Codec、当前 ui.Image 和帧定时器都持有原生资源，必须成组释放。
    _generation++;
    _timer?.cancel();
    _codec?.dispose();
    _image?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // 每次 source/repeat 变化递增代次，旧异步加载即使后返回也不能覆盖新内容。
    final generation = ++_generation;
    _timer?.cancel();
    _codec?.dispose();
    _codec = null;
    _image?.dispose();
    _image = null;
    _error = null;
    _frameIndex = 0;
    if (mounted) setState(() {});

    try {
      final bytes = await _loadBytes(widget.source);
      if (!mounted || generation != _generation) return;

      final codec = await ui.instantiateImageCodec(bytes);
      if (!mounted || generation != _generation) {
        codec.dispose();
        return;
      }

      _codec = codec;
      await _showNextFrame(generation);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    }
  }

  Future<Uint8List> _loadBytes(String source) async {
    final resolvedSource = _resolveSource(source);

    if (resolvedSource.startsWith('http://') ||
        resolvedSource.startsWith('https://')) {
      final data = await NetworkAssetBundle(Uri.parse(resolvedSource))
          .load(resolvedSource);
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    }

    if (!kIsWeb && _isLocalFilePath(resolvedSource)) {
      return File(resolvedSource).readAsBytes();
    }

    final data = await rootBundle.load(resolvedSource);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  bool _isLocalFilePath(String value) {
    if (value.startsWith('assets/')) return false;
    if (value.startsWith('/')) return true;
    return RegExp(r'^[A-Za-z]:[\\/]').hasMatch(value);
  }

  String _resolveSource(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.startsWith('/uploads/') ||
        normalized.startsWith('uploads/')) {
      return ApiConfig.getMediaUrl(normalized);
    }
    return normalized;
  }

  Future<void> _showNextFrame(int generation) async {
    final codec = _codec;
    if (codec == null) return;

    final frame = await codec.getNextFrame();
    if (!mounted || generation != _generation) {
      // 过期帧未进入组件所有权，需在丢弃前主动释放。
      frame.image.dispose();
      return;
    }

    // RawImage 不负责这里手动解码图像的生命周期，替换帧前释放上一帧。
    _image?.dispose();
    _image = frame.image;
    _frameIndex++;
    setState(() {});

    if (!widget.repeat && _frameIndex >= codec.frameCount) {
      return;
    }

    if (codec.frameCount <= 1) return;
    final delay = frame.duration > Duration.zero
        ? frame.duration
        : const Duration(milliseconds: 100);
    _timer = Timer(delay, () => _showNextFrame(generation));
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.errorBuilder?.call(context, _error!) ??
          const SizedBox.shrink();
    }

    final image = _image;
    if (image == null) {
      return widget.placeholder ?? const SizedBox.shrink();
    }

    return RawImage(
      image: image,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      filterQuality: FilterQuality.medium,
    );
  }
}
