// 文件用途：提供 _MessageBubbleAlbum 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _MessageBubbleAlbum，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble album 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
extension _MessageBubbleAlbum on MessageBubble {
  // 流程逻辑：`_buildImageAlbumBubble` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  Widget _buildImageAlbumBubble(
    BuildContext context,
    Color timeColor,
    bool isOutgoing,
  ) {
    final items = albumMessages.reversed.toList(growable: false);
    final visibleItems = items.take(4).toList(growable: false);
    final extraCount = items.length - visibleItems.length;

    return ClipRRect(
      borderRadius: _getBubbleRadius(isOutgoing),
      child: SizedBox(
        width: 280,
        height: items.length == 2 ? 150 : 280,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _buildAlbumGrid(context, visibleItems, extraCount),
            Positioned(
              right: 8,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.45),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('HH:mm')
                            .format(toCurrentLocalTime(message.createdAt)),
                        style: AppTextStyles.timestamp.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      if (message.isOutgoing) ...[
                        const SizedBox(width: 3),
                        _buildStatusIcon(Colors.white),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumGrid(
    BuildContext context,
    List<MessageItem> items,
    int extraCount,
  ) {
    const gap = 2.0;
    if (items.length == 2) {
      return Row(
        children: [
          Expanded(child: _buildAlbumTile(context, items[0])),
          const SizedBox(width: gap),
          Expanded(child: _buildAlbumTile(context, items[1])),
        ],
      );
    }

    if (items.length == 3) {
      return Row(
        children: [
          Expanded(
            flex: 2,
            child: _buildAlbumTile(context, items[0]),
          ),
          const SizedBox(width: gap),
          Expanded(
            child: Column(
              children: [
                Expanded(child: _buildAlbumTile(context, items[1])),
                const SizedBox(height: gap),
                Expanded(child: _buildAlbumTile(context, items[2])),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildAlbumTile(context, items[0])),
              const SizedBox(width: gap),
              Expanded(child: _buildAlbumTile(context, items[1])),
            ],
          ),
        ),
        const SizedBox(height: gap),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildAlbumTile(context, items[2])),
              const SizedBox(width: gap),
              Expanded(
                child: _buildAlbumTile(
                  context,
                  items[3],
                  overflowCount: extraCount > 0 ? extraCount : null,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAlbumTile(
    BuildContext context,
    MessageItem item, {
    int? overflowCount,
  }) {
    final source = _albumImageSource(item);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openAlbumImagePreview(context, item),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildAlbumImage(source),
          if (overflowCount != null)
            Container(
              color: Colors.black.withOpacity(0.45),
              alignment: Alignment.center,
              child: Text(
                '+$overflowCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAlbumImage(String source) {
    if (source.isEmpty) {
      return _buildAlbumFallback();
    }

    if (source.startsWith('data:image/')) {
      final bytes = _decodeDataImage(source);
      if (bytes != null) {
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      }
      return _buildAlbumFallback();
    }

    if (ChatMediaCacheManager.isLocalPath(source)) {
      final file = File(source);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover, gaplessPlayback: true);
      }
      return _buildAlbumFallback();
    }

    final imageUrl = ChatMediaCacheManager.normalizeUrl(source);
    if (imageUrl.isEmpty) {
      return _buildAlbumFallback();
    }

    return CachedNetworkImage(
      imageUrl: imageUrl,
      cacheManager: ChatMediaCacheManager.instance,
      fit: BoxFit.cover,
      memCacheWidth: 560,
      memCacheHeight: 560,
      maxWidthDiskCache: 900,
      maxHeightDiskCache: 900,
      placeholder: (_, __) => Container(color: Colors.black12),
      errorWidget: (_, __, ___) => _buildAlbumFallback(),
    );
  }

  Widget _buildAlbumFallback() {
    return Container(
      color: Colors.black12,
      alignment: Alignment.center,
      child: const Icon(Icons.broken_image_outlined, color: Colors.white70),
    );
  }

  String _albumImageSource(MessageItem item) {
    final localPath = item.localPath;
    if (ChatMediaCacheManager.isLocalPath(localPath) &&
        File(localPath!).existsSync()) {
      return localPath;
    }
    final mediaUrl = item.mediaUrl ?? '';
    if (AnimatedGifImage.isGifSource(mediaUrl)) return mediaUrl;
    return item.thumbnail ?? mediaUrl;
  }

  Uint8List? _decodeDataImage(String value) {
    final comma = value.indexOf(',');
    if (comma < 0 || comma == value.length - 1) return null;
    try {
      return base64Decode(value.substring(comma + 1));
    } catch (_) {
      return null;
    }
  }

  void _openAlbumImagePreview(BuildContext context, MessageItem item) {
    final albumItems = albumMessages.reversed.toList(growable: false);
    final previewItems = <_PreviewImageItem>[];
    var initialIndex = 0;

    for (final albumItem in albumItems) {
      final source = _albumImageSource(albumItem).trim();
      if (source.isEmpty) continue;
      if (source.startsWith('data:image/') &&
          _decodeDataImage(source) == null) {
        continue;
      }

      final previewItem = _PreviewImageItem.fromSource(source);
      if (previewItem.source.isEmpty) continue;

      if (albumItem.id == item.id) {
        initialIndex = previewItems.length;
      }
      previewItems.add(previewItem);
    }

    if (previewItems.isEmpty) return;
    final current = previewItems[initialIndex];

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (ctx, animation, secondaryAnimation) {
          return _ImagePreviewPage(
            imageUrl: current.source,
            isLocalFile: current.isLocalFile,
            galleryItems: previewItems,
            initialIndex: initialIndex,
          );
        },
        transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}
