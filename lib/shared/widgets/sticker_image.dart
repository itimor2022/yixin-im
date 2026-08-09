// 文件用途：提供 StickerImage 可复用界面组件，服务于跨模块共享能力。
// 核心逻辑：根据输入模型和状态渲染 StickerImage，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:universal_io/io.dart';

import '../../features/chat/services/emoji_store_service.dart';
import 'animated_gif_image.dart';

// 关键声明：sticker image 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
class StickerImage extends StatelessWidget {
  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool repeat;
  final bool animate;
  final Widget? placeholder;
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  const StickerImage({
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

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  @override
  Widget build(BuildContext context) {
    final resolvedSource = EmojiStoreService.resolveStickerDisplayPath(source);
    if (_isAnimatedSource(resolvedSource)) {
      return AnimatedStickerImage(
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
      return CachedNetworkImage(
        imageUrl: resolvedSource,
        width: width,
        height: height,
        fit: fit,
        placeholder: placeholder == null ? null : (_, __) => placeholder!,
        errorWidget: errorBuilder == null
            ? null
            : (context, _, error) => errorBuilder!(context, error),
      );
    }

    if (_isAssetPath(resolvedSource)) {
      return Image.asset(
        resolvedSource,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: errorBuilder == null
            ? null
            : (context, error, _) => errorBuilder!(context, error),
      );
    }

    return Image.file(
      File(resolvedSource),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: errorBuilder == null
          ? null
          : (context, error, _) => errorBuilder!(context, error),
    );
  }

  static bool _isAnimatedSource(String value) {
    return AnimatedStickerImage.isLottieSource(value) ||
        AnimatedGifImage.isGifSource(value);
  }

  static bool _isRemoteSource(String value) {
    return value.startsWith('http://') || value.startsWith('https://');
  }

  static bool _isAssetPath(String value) {
    return value.startsWith('assets/');
  }
}
