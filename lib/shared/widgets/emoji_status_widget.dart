// 文件用途：提供 EmojiStatusWidget 可复用界面组件，服务于跨模块共享能力。
// 核心逻辑：根据输入模型和状态渲染 EmojiStatusWidget，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'web_safe_lottie.dart';
import 'package:universal_io/io.dart';

import '../../core/constants/emoji_animations.dart';
import '../../core/services/api/api_client.dart';
import 'animated_gif_image.dart';

const String _customEmojiLocalPrefix = '__custom_emoji__:';
const String _customEmojiUrlPrefix = '__custom_emoji_url__:';

// 关键声明：emoji status widget 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 表情状态显示组件（支持动态表情）
class EmojiStatusWidget extends StatelessWidget {
  final String emoji;
  final double size;

  const EmojiStatusWidget({
    super.key,
    required this.emoji,
    this.size = 20,
  });

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  @override
  Widget build(BuildContext context) {
    if (emoji.isEmpty) return const SizedBox.shrink();

    final animatedEmoji = EmojiAnimations.findByEmoji(emoji);

    if (animatedEmoji != null) {
      if (kIsWeb) {
        return SizedBox(
          width: size,
          height: size,
          child: Center(
            child: Text(
              emoji,
              style: TextStyle(fontSize: size * 0.82),
            ),
          ),
        );
      }
      return SizedBox(
        width: size,
        height: size,
        child: WebSafeLottie.asset(
          animatedEmoji.path,
          repeat: true,
          animate: true,
          fit: BoxFit.contain,
        ),
      );
    }

    final imagePath = _resolveImagePath(emoji);
    if (imagePath != null && imagePath.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: SizedBox(
          width: size,
          height: size,
          child: _buildStickerOrImage(imagePath),
        ),
      );
    }

    return Text(
      emoji,
      style: TextStyle(fontSize: size * 0.85),
    );
  }

  String? _resolveImagePath(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    if (value.startsWith(_customEmojiLocalPrefix)) {
      return value.substring(_customEmojiLocalPrefix.length);
    }
    if (value.startsWith(_customEmojiUrlPrefix)) {
      final url = value.substring(_customEmojiUrlPrefix.length);
      return _resolveRemotePath(url);
    }
    if (_isRemoteStickerFile(value)) {
      return _resolveRemotePath(value);
    }
    if (_looksLikeLocalImagePath(value)) {
      return value;
    }
    return null;
  }

  bool _isRemoteStickerFile(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    return normalized.startsWith('http://') ||
        normalized.startsWith('https://') ||
        normalized.startsWith('/uploads/') ||
        normalized.startsWith('uploads/') ||
        normalized.startsWith('assets/stickers/');
  }

  String _resolveRemotePath(String value) {
    final normalized = value.trim().replaceAll('\\', '/');
    if (normalized.startsWith('http://') || normalized.startsWith('https://')) {
      return normalized;
    }
    if (normalized.startsWith('/uploads/') ||
        normalized.startsWith('uploads/')) {
      return ApiConfig.getMediaUrl(normalized);
    }
    return normalized;
  }

  bool _looksLikeLocalImagePath(String value) {
    final lower = value.toLowerCase();
    final hasImageExt = lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.json') ||
        lower.endsWith('.tgs');
    if (!hasImageExt) return false;
    return value.contains('/') || value.contains('\\');
  }

  Widget _buildStickerOrImage(String path) {
    if (AnimatedStickerImage.isLottieSource(path) ||
        AnimatedGifImage.isGifSource(path)) {
      return AnimatedStickerImage(
        source: path,
        fit: BoxFit.contain,
        errorBuilder: (_, __) => _fallbackIcon(),
      );
    }
    return _buildImage(path);
  }

  Widget _buildImage(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: path,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _fallbackIcon(),
      );
    }
    final file = File(path);
    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _fallbackIcon(),
    );
  }

  Widget _fallbackIcon() {
    return Icon(
      Icons.image_not_supported_outlined,
      size: size * 0.72,
      color: Colors.grey,
    );
  }
}
