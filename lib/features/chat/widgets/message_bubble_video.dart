// 文件用途：提供 _VideoBubbleWidget 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _VideoBubbleWidget，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble video 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// 视频气泡组件 - Telegram 风格
class _VideoBubbleWidget extends StatefulWidget {
  final MessageItem message;
  final bool isOutgoing;
  final BorderRadius Function(bool) getBubbleRadius;
  final Widget Function(Color) buildStatusIcon;

  const _VideoBubbleWidget({
    required this.message,
    required this.isOutgoing,
    required this.getBubbleRadius,
    required this.buildStatusIcon,
  });

  @override
  State<_VideoBubbleWidget> createState() => _VideoBubbleWidgetState();
}

class _VideoBubbleWidgetState extends State<_VideoBubbleWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;
  bool _isPressed = false;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  String _formatDuration(int? milliseconds) {
    if (milliseconds == null || milliseconds == 0) return '0:00';
    final seconds = (milliseconds / 1000).round();
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '$min:${sec.toString().padLeft(2, '0')}';
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes == 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  String? _getThumbnailUrl() {
    final thumbnail = widget.message.thumbnail;
    if (thumbnail == null || thumbnail.isEmpty) return null;
    final normalized = ChatMediaCacheManager.normalizeUrl(thumbnail);
    if (normalized.isNotEmpty) return normalized;

    // 如果已经是完整URL
    if (thumbnail.startsWith('http')) return thumbnail;

    // 如果是服务器相对路径 (/uploads/...)
    if (thumbnail.startsWith('/uploads/')) {
      return ApiConfig.getMediaUrl(thumbnail);
    }

    // 如果是本地文件路径 (iOS: /var/..., /Users/..., Android: /data/..., /storage/...)
    if (thumbnail.startsWith('/var/') ||
        thumbnail.startsWith('/Users/') ||
        thumbnail.startsWith('/data/') ||
        thumbnail.startsWith('/storage/') ||
        thumbnail.contains('/Library/') ||
        thumbnail.contains('/Caches/') ||
        thumbnail.contains('/tmp/')) {
      return thumbnail;
    }

    // 其他情况拼接服务器地址
    return ApiConfig.getMediaUrl(thumbnail);
  }

  void _onTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _scaleController.reverse();
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _scaleController.forward();
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _scaleController.forward();
  }

  Future<void> _playVideo() async {
    final localPath = widget.message.localPath;
    final canUseLocalPath = !PlatformUtils.isWeb &&
        ChatMediaCacheManager.isLocalPath(localPath) &&
        File(localPath!).existsSync();
    final videoUrl = canUseLocalPath ? localPath : widget.message.mediaUrl;
    if (videoUrl == null || videoUrl.isEmpty) return;

    // 判断是本地文件还是网络 URL
    var isLocal =
        !PlatformUtils.isWeb && ChatMediaCacheManager.isLocalPath(videoUrl);
    var fullUrl =
        isLocal ? videoUrl : ChatMediaCacheManager.normalizeUrl(videoUrl);
    if (fullUrl.isEmpty) return;
    if (!PlatformUtils.isWeb && !isLocal && fullUrl.startsWith('http')) {
      try {
        final cached =
            await ChatMediaCacheManager.instance.getFileFromCache(fullUrl);
        final file = cached?.file;
        if (file != null && await file.exists()) {
          fullUrl = file.path;
          isLocal = true;
        } else {
          ChatMediaCacheManager.prefetchFile(fullUrl);
        }
      } catch (_) {
        ChatMediaCacheManager.prefetchFile(fullUrl);
      }
    }
    final thumbnailUrl = _getThumbnailUrl();

    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _VideoPlayerPage(
            videoUrl: fullUrl,
            isLocal: isLocal,
            thumbnailUrl: thumbnailUrl,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thumbnailUrl = _getThumbnailUrl();
    final duration = widget.message.mediaDuration;
    final fileSize = widget.message.mediaSize;

    // 计算宽高比
    double aspectRatio = 16 / 9;
    if (widget.message.mediaWidth != null &&
        widget.message.mediaHeight != null &&
        widget.message.mediaHeight! > 0) {
      aspectRatio = widget.message.mediaWidth! / widget.message.mediaHeight!;
    }

    // 限制宽高比范围
    aspectRatio = aspectRatio.clamp(0.5, 2.0);

    // 预计算视频显示尺寸
    double displayW = 280;
    double displayH = displayW / aspectRatio;
    if (widget.message.mediaWidth != null &&
        widget.message.mediaHeight != null &&
        widget.message.mediaWidth! > 0 &&
        widget.message.mediaHeight! > 0) {
      displayW = widget.message.mediaWidth!.toDouble();
      displayH = widget.message.mediaHeight!.toDouble();
      if (displayW > 280) {
        displayH = displayH * 280 / displayW;
        displayW = 280;
      }
      if (displayH > 400) {
        displayW = displayW * 400 / displayH;
        displayH = 400;
      }
      if (displayW < 180) {
        displayH = displayH * 180 / displayW;
        displayW = 180;
      }
    }

    return GestureDetector(
      key: const ValueKey('message_video_bubble'),
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: _playVideo,
      child: AnimatedBuilder(
        animation: _scaleController,
        builder: (context, child) =>
            Transform.scale(scale: _scaleController.value, child: child),
        child: SizedBox(
          width: displayW.clamp(180, 280),
          height: displayH.clamp(100, 400),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: widget.getBubbleRadius(widget.isOutgoing),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: widget.getBubbleRadius(widget.isOutgoing),
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildThumbnail(thumbnailUrl),
                    _buildGradientOverlay(),
                    if (widget.message.status == MessageStatus.sending &&
                        widget.message.uploadProgress != null &&
                        widget.message.uploadProgress! < 1.0)
                      _buildUploadProgress(widget.message.uploadProgress!)
                    else
                      _buildPlayButton(),
                    if (duration != null && duration > 0)
                      Positioned(
                        left: 10,
                        top: 10,
                        child: _buildInfoChip(
                          icon: Icons.play_arrow_rounded,
                          text: _formatDuration(duration),
                        ),
                      ),
                    if (fileSize != null && fileSize > 0)
                      Positioned(
                        right: 10,
                        top: 10,
                        child: _buildInfoChip(text: _formatFileSize(fileSize)),
                      ),
                    Positioned(
                      right: 8,
                      bottom: 6,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat(
                              'HH:mm',
                            ).format(
                              toCurrentLocalTime(widget.message.createdAt),
                            ),
                            style: AppTextStyles.timestamp.copyWith(
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withOpacity(0.5),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          if (widget.isOutgoing) ...[
                            const SizedBox(width: 3),
                            widget.buildStatusIcon(Colors.white),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 构建视频缩略图
  /// 性能优化：使用 LayoutBuilder 动态调整缓存尺寸
  Widget _buildThumbnail(String? thumbnailUrl) {
    if (thumbnailUrl == null) {
      return _buildPlaceholder();
    }

    // 本地文件路径 (不是 http:// 开头的)
    if (!PlatformUtils.isWeb &&
        ChatMediaCacheManager.isLocalPath(thumbnailUrl)) {
      return Image.file(
        File(thumbnailUrl),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    }

    // 网络图片 - 使用 LayoutBuilder 优化缓存
    final imageUrl = ChatMediaCacheManager.normalizeUrl(thumbnailUrl);
    if (imageUrl.isEmpty || !imageUrl.startsWith('http')) {
      return _buildPlaceholder();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据实际约束计算缓存尺寸
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
          cacheKey: widget.message.thumbnailMediaId?.trim().isNotEmpty == true
              ? 'media:${widget.message.thumbnailMediaId!.trim()}'
              : null,
          cacheManager: ChatMediaCacheManager.instance,
          fit: BoxFit.cover,
          // 性能优化：根据实际显示尺寸动态调整内存缓存大小
          memCacheWidth: maxWidth,
          memCacheHeight: maxHeight,
          // 磁盘缓存限制
          maxWidthDiskCache: 800,
          maxHeightDiskCache: 800,
          fadeInDuration: const Duration(milliseconds: 200),
          fadeOutDuration: const Duration(milliseconds: 200),
          placeholder: (_, __) => _buildPlaceholder(),
          errorWidget: (_, __, ___) => _buildPlaceholder(),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFF2C2C2E),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videocam_rounded,
              color: Colors.white.withOpacity(0.3),
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context).video,
              style: TextStyle(
                color: Colors.white.withOpacity(0.3),
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGradientOverlay() {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withOpacity(0.3),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withOpacity(0.4),
            ],
            stops: const [0.0, 0.2, 0.7, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadProgress(double progress) {
    final pct = (progress * 100).toInt();
    return Center(
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.5),
          shape: BoxShape.circle,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                color: Colors.white,
                backgroundColor: Colors.white.withOpacity(0.3),
              ),
            ),
            Text(
              '$pct%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayButton() {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: _isPressed ? 54 : 60,
        height: _isPressed ? 54 : 60,
        decoration: BoxDecoration(
          color: _isPressed
              ? Colors.white.withOpacity(0.9)
              : Colors.white.withOpacity(0.85),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(
          Icons.play_arrow_rounded,
          color: Colors.black.withOpacity(0.8),
          size: _isPressed ? 32 : 36,
        ),
      ),
    );
  }

  Widget _buildInfoChip({IconData? icon, required String text}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: icon != null ? 6 : 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.5),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 2),
          ],
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
