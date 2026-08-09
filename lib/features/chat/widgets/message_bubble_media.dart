// 文件用途：提供 _MessageBubbleMedia 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _MessageBubbleMedia，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble media 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
extension _MessageBubbleMedia on MessageBubble {
  // 流程逻辑：`_buildSizedMedia` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  /// 根据已知的 mediaWidth/mediaHeight 预计算显示尺寸，避免图片加载后闪烁
  Widget _buildSizedMedia(double maxW, double maxH) {
    final mw = message.mediaWidth;
    final mh = message.mediaHeight;

    if (mw != null && mh != null && mw > 0 && mh > 0) {
      double w = mw.toDouble();
      double h = mh.toDouble();

      // 始终使用统一缩放因子，保证外层缩略图容器与图片真实比例一致。
      final shrinkScale = math.min(maxW / w, maxH / h);
      if (shrinkScale < 1) {
        w *= shrinkScale;
        h *= shrinkScale;
      }

      // 仅在图片整体都太小时才按比例整体放大，避免比例失真。
      if (w < 100 && h < 80) {
        final growScale = math.min(maxW / w, maxH / h);
        final desiredScale = math.max(100 / w, 80 / h);
        final finalScale = math.min(growScale, desiredScale);
        if (finalScale > 1) {
          w *= finalScale;
          h *= finalScale;
        }
      }

      return SizedBox(width: w, height: h, child: _buildMediaImage());
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxW,
        maxHeight: maxH,
        minWidth: 100,
        minHeight: 80,
      ),
      child: _buildMediaImage(),
    );
  }

  /// 构建媒体图片（处理本地文件和网络URL）
  Widget _buildMediaImage() {
    final localPath = message.localPath;
    final remoteMediaUrl = message.mediaUrl?.trim();
    final isRemoteGif = remoteMediaUrl != null &&
        remoteMediaUrl.isNotEmpty &&
        AnimatedGifImage.isGifSource(
          ChatMediaCacheManager.normalizeUrl(remoteMediaUrl),
        );
    final thumbnailUrl = message.thumbnail?.trim();
    final remoteDisplayUrl =
        !isRemoteGif && thumbnailUrl != null && thumbnailUrl.isNotEmpty
            ? thumbnailUrl
            : remoteMediaUrl;
    final rawUrl = ChatMediaCacheManager.isLocalPath(localPath) &&
            File(localPath!).existsSync()
        ? localPath
        : remoteDisplayUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      return Container(
        width: 200,
        height: 150,
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.image, size: 40, color: Colors.grey[400]),
      );
    }

    final isSticker = message.type == MessageItemType.sticker;
    final url = isSticker
        ? EmojiStoreService.resolveStickerDisplayPath(rawUrl)
        : ChatMediaCacheManager.normalizeUrl(rawUrl);
    final isGif = AnimatedGifImage.isGifSource(url);
    final imageFit = isSticker || isGif ? BoxFit.contain : BoxFit.fill;

    if (isSticker) {
      return StickerImage(
        source: url,
        fit: imageFit,
        errorBuilder: (context, nativeError) {
          debugPrint(
            '[MessageImage] sticker image failed: $url error=$nativeError',
          );
          return Container(
            width: 200,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.broken_image,
              size: 40,
              color: Colors.grey[400],
            ),
          );
        },
      );
    }

    if (ChatMediaCacheManager.isLocalPath(url)) {
      if (isGif) {
        return AnimatedGifImage(source: url, fit: imageFit);
      }

      final file = File(url);
      return Image.file(
        file,
        fit: imageFit,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            width: 200,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.broken_image, size: 40, color: Colors.grey[400]),
          );
        },
      );
    }

    final imageUrl = url;

    if (isGif) {
      return AnimatedGifImage(
        source: imageUrl,
        fit: imageFit,
        errorBuilder: (context, nativeError) {
          debugPrint(
            '[MessageImage] gif image failed: $imageUrl error=$nativeError',
          );
          return Container(
            width: 200,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.broken_image,
              size: 40,
              color: Colors.grey[400],
            ),
          );
        },
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth > 0
                ? (constraints.maxWidth * 2).round().clamp(200, 560)
                : 280;
        final maxHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight > 0
                ? (constraints.maxHeight * 2).round().clamp(200, 560)
                : 280;

        return CachedNetworkImage(
          key: ValueKey<String>(imageUrl),
          imageUrl: imageUrl,
          cacheKey: _mediaImageCacheKey(),
          cacheManager: ChatMediaCacheManager.instance,
          fit: imageFit,
          memCacheWidth: maxWidth,
          memCacheHeight: maxHeight,
          maxWidthDiskCache: 800,
          maxHeightDiskCache: 800,
          fadeInDuration: const Duration(milliseconds: 150),
          fadeOutDuration: const Duration(milliseconds: 150),
          placeholder: (context, url) => Container(
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
          errorWidget: (context, url, error) {
            debugPrint('[MessageImage] cached image failed: $url error=$error');
            return Image.network(
              imageUrl,
              key: ValueKey<String>('native:$imageUrl'),
              fit: imageFit,
              cacheWidth: maxWidth,
              cacheHeight: maxHeight,
              errorBuilder: (context, nativeError, stackTrace) {
                debugPrint(
                  '[MessageImage] native image failed: $imageUrl '
                  'error=$nativeError',
                );
                return Container(
                  width: 200,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.broken_image,
                    size: 40,
                    color: Colors.grey[400],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String? _mediaImageCacheKey() {
    final thumbnailMediaId = message.thumbnailMediaId?.trim() ?? '';
    if (thumbnailMediaId.isNotEmpty) return 'media:$thumbnailMediaId';
    final mediaId = message.mediaId?.trim() ?? '';
    return mediaId.isEmpty ? null : 'media:$mediaId';
  }
}
