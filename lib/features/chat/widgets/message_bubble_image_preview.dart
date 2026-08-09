// 文件用途：提供 _PreviewImageItem 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _PreviewImageItem，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

// 关键声明：message bubble image preview 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
class _PreviewImageItem {
  final String source;
  final bool isLocalFile;

  const _PreviewImageItem({
    required this.source,
    required this.isLocalFile,
  });

  factory _PreviewImageItem.fromSource(String value) {
    final normalized = ChatMediaCacheManager.normalizeUrl(value.trim());
    return _PreviewImageItem(
      source: normalized,
      isLocalFile: ChatMediaCacheManager.isLocalPath(normalized),
    );
  }

  ImageProvider<Object> get imageProvider {
    if (source.startsWith('data:image/')) {
      final bytes = _decodePreviewDataImage(source);
      if (bytes != null) return MemoryImage(bytes);
    }
    if (isLocalFile) return FileImage(File(source));
    return CachedNetworkImageProvider(
      source,
      cacheManager: ChatMediaCacheManager.instance,
    );
  }

  bool get isGif => AnimatedGifImage.isGifSource(source);
}

Uint8List? _decodePreviewDataImage(String value) {
  final comma = value.indexOf(',');
  if (comma < 0 || comma == value.length - 1) return null;
  try {
    return base64Decode(value.substring(comma + 1));
  } catch (_) {
    return null;
  }
}

/// TG-style image preview. Supports horizontal paging and drag-to-dismiss.
class _ImagePreviewPage extends StatefulWidget {
  final String imageUrl;
  final bool isLocalFile;
  final List<_PreviewImageItem>? galleryItems;
  final int initialIndex;

  const _ImagePreviewPage({
    required this.imageUrl,
    required this.isLocalFile,
    this.galleryItems,
    this.initialIndex = 0,
  });

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  double _scale = 1.0;
  double _opacity = 1.0;
  bool _isDragging = false;
  bool _showControls = true;

  late final List<_PreviewImageItem> _items;
  late final PageController _pageController;
  late final AnimationController _animController;
  late Animation<double> _resetAnimation;
  late int _currentIndex;

  _PreviewImageItem get _currentItem => _items[_currentIndex];

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    final suppliedItems = widget.galleryItems
        ?.where((item) => item.source.trim().isNotEmpty)
        .toList(growable: false);
    _items = suppliedItems != null && suppliedItems.isNotEmpty
        ? suppliedItems
        : [
            _PreviewImageItem(
              source: widget.imageUrl,
              isLocalFile: widget.isLocalFile,
            ),
          ];

    _currentIndex = widget.initialIndex;
    if (_currentIndex < 0) {
      _currentIndex = 0;
    } else if (_currentIndex >= _items.length) {
      _currentIndex = _items.length - 1;
    }

    _pageController = PageController(initialPage: _currentIndex);
    _animController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animController.dispose();
    super.dispose();
  }

  void _onVerticalDragStart(DragStartDetails details) {
    setState(() => _isDragging = true);
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      final progress = (_dragOffset.abs() / 300).clamp(0.0, 1.0);
      _scale = 1.0 - (progress * 0.3);
      _opacity = 1.0 - (progress * 0.5);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dy;

    if (_dragOffset.abs() > 100 || velocity.abs() > 500) {
      Navigator.of(context).pop();
    } else {
      _resetAnimation = Tween<double>(begin: _dragOffset, end: 0).animate(
        CurvedAnimation(
          parent: _animController,
          curve: Curves.easeOutCubic,
        ),
      )..addListener(() {
          setState(() {
            _dragOffset = _resetAnimation.value;
            final progress = (_dragOffset.abs() / 300).clamp(0.0, 1.0);
            _scale = 1.0 - (progress * 0.3);
            _opacity = 1.0 - (progress * 0.5);
          });
        });
      _animController.forward(from: 0);
    }
    setState(() => _isDragging = false);
  }

  @override
  Widget build(BuildContext context) {
    return DarkSystemUiScope(
      child: Scaffold(
        backgroundColor: Colors.black.withOpacity(_opacity * 0.92),
        body: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _showControls = !_showControls),
                behavior: HitTestBehavior.opaque,
                child: Container(color: Colors.transparent),
              ),
            ),
            Positioned.fill(
              child: GestureDetector(
                onVerticalDragStart: _onVerticalDragStart,
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                child: Transform.translate(
                  offset: Offset(0, _dragOffset),
                  child: Transform.scale(
                    scale: _scale,
                    child: PhotoViewGallery.builder(
                      itemCount: _items.length,
                      pageController: _pageController,
                      backgroundDecoration:
                          const BoxDecoration(color: Colors.transparent),
                      wantKeepAlive: true,
                      gaplessPlayback: true,
                      scrollPhysics: const BouncingScrollPhysics(),
                      onPageChanged: (index) {
                        setState(() {
                          _currentIndex = index;
                          _showControls = true;
                        });
                      },
                      loadingBuilder: (context, progress) => const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                      builder: (context, index) {
                        final item = _items[index];
                        if (item.isGif) {
                          return PhotoViewGalleryPageOptions.customChild(
                            child: AnimatedGifImage(
                              source: item.source,
                              fit: BoxFit.contain,
                              placeholder: const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                ),
                              ),
                              errorBuilder: (context, error) => const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  size: 100,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            initialScale: PhotoViewComputedScale.contained,
                            minScale: PhotoViewComputedScale.contained,
                            maxScale: PhotoViewComputedScale.covered * 4,
                            onTapUp: (context, details, controllerValue) {
                              setState(
                                () => _showControls = !_showControls,
                              );
                            },
                          );
                        }
                        return PhotoViewGalleryPageOptions(
                          imageProvider: item.imageProvider,
                          initialScale: PhotoViewComputedScale.contained,
                          minScale: PhotoViewComputedScale.contained,
                          maxScale: PhotoViewComputedScale.covered * 4,
                          onTapUp: (context, details, controllerValue) {
                            setState(
                              () => _showControls = !_showControls,
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.broken_image,
                                size: 100,
                                color: Colors.white,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _isDragging || !_showControls ? 0 : 1,
                duration: const Duration(milliseconds: 150),
                child: IgnorePointer(
                  ignoring: _isDragging || !_showControls,
                  child: SafeArea(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          Expanded(
                            child: Text(
                              _items.length > 1
                                  ? '${_currentIndex + 1}/${_items.length}'
                                  : '',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.download,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: () => _saveImage(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveImage(BuildContext context) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 12),
              Text(
                _localizedUiText(
                  context,
                  zhCN: '正在保存...',
                  zhTW: '正在儲存...',
                  en: 'Saving...',
                ),
              ),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      final item = _currentItem;
      String savePath;

      if (item.isLocalFile) {
        savePath = item.source;
      } else if (item.source.startsWith('data:image/')) {
        final bytes = _decodePreviewDataImage(item.source);
        if (bytes == null) throw StateError('Invalid image data.');
        final tempDir = await getTemporaryDirectory();
        final extension = detectImageFileExtension(
          bytes,
          source: item.source,
        );
        final fileName =
            'GenericIM_${DateTime.now().millisecondsSinceEpoch}$extension';
        savePath = '${tempDir.path}/$fileName';
        await File(savePath).writeAsBytes(bytes);
      } else {
        final tempDir = await getTemporaryDirectory();
        final response = await Dio().get<List<int>>(
          item.source,
          options: Options(responseType: ResponseType.bytes),
        );
        final responseBytes = response.data;
        if (responseBytes == null || responseBytes.isEmpty) {
          throw StateError('Downloaded image is empty.');
        }
        final bytes = Uint8List.fromList(responseBytes);
        final extension = detectImageFileExtension(
          bytes,
          source: item.source,
        );
        final fileName =
            'GenericIM_${DateTime.now().millisecondsSinceEpoch}$extension';
        savePath = '${tempDir.path}/$fileName';
        await File(savePath).writeAsBytes(bytes);
      }

      await Gal.putImage(savePath);

      if (!mounted) return;

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text(
                _localizedUiText(
                  context,
                  zhCN: '已保存到相册',
                  zhTW: '已儲存到相簿',
                  en: 'Saved to album',
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _localizedUiText(
                    context,
                    zhCN: '保存失败，请重试',
                    zhTW: '儲存失敗，請重試',
                    en: 'Save failed. Please try again.',
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class _LocalImagePreviewPage extends StatefulWidget {
  final String imagePath;
  final String fileName;

  const _LocalImagePreviewPage({
    required this.imagePath,
    required this.fileName,
  });

  @override
  State<_LocalImagePreviewPage> createState() => _LocalImagePreviewPageState();
}

class _LocalImagePreviewPageState extends State<_LocalImagePreviewPage> {
  double _dragOffset = 0.0;
  double _scale = 1.0;

  void _onVerticalDragStart(DragStartDetails details) {
    setState(() {});
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      _scale = (1.0 - (_dragOffset.abs() / 500)).clamp(0.5, 1.0);
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_dragOffset.abs() > 100 ||
        details.velocity.pixelsPerSecond.dy.abs() > 500) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _dragOffset = 0.0;
        _scale = 1.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DarkSystemUiScope(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.opaque,
                child: Container(color: Colors.transparent),
              ),
            ),
            Center(
              child: GestureDetector(
                onVerticalDragStart: _onVerticalDragStart,
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                child: Transform.translate(
                  offset: Offset(0, _dragOffset),
                  child: Transform.scale(
                    scale: _scale,
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: Image.file(
                        File(widget.imagePath),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image_rounded,
                                size: 64,
                                color: Colors.white54,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _localizedUiText(
                                  context,
                                  zhCN: '无法加载图片',
                                  zhTW: '無法載入圖片',
                                  en: 'Unable to load image',
                                ),
                                style: TextStyle(color: Colors.white54),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                      Expanded(
                        child: Text(
                          widget.fileName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Share.shareXFiles([XFile(widget.imagePath)]);
                        },
                        icon: const Icon(
                          Icons.share_rounded,
                          color: Colors.white,
                        ),
                      ),
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
}
