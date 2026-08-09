// 文件用途：提供 _VideoPlayerPage 可复用界面组件，服务于聊天与消息。
// 核心逻辑：根据输入模型和状态渲染 _VideoPlayerPage，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
part of 'message_bubble.dart';

const messageVideoPlaybackOrientations = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown,
  DeviceOrientation.landscapeLeft,
  DeviceOrientation.landscapeRight,
];

const messageVideoRestoredOrientations = <DeviceOrientation>[
  DeviceOrientation.portraitUp,
  DeviceOrientation.portraitDown,
];

// 关键声明：message bubble video player 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
/// Telegram 风格视频播放页面
class _VideoPlayerPage extends StatefulWidget {
  final String videoUrl;
  final bool isLocal;
  final String? thumbnailUrl;

  const _VideoPlayerPage({
    required this.videoUrl,
    this.isLocal = false,
    this.thumbnailUrl,
  });

  @override
  State<_VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<_VideoPlayerPage>
    with SingleTickerProviderStateMixin {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showControls = true;
  bool _isBuffering = false;
  bool _hasError = false;
  double _currentPosition = 0;
  double _totalDuration = 0;
  bool _isDragging = false;
  bool _isSaving = false;
  bool _isSaved = false;
  bool _hasController = false;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _initializeVideo();
    unawaited(
      SystemChrome.setPreferredOrientations(messageVideoPlaybackOrientations),
    );
    // 隐藏状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _initializeVideo() async {
    if (mounted) {
      setState(() {
        _isInitialized = false;
        _isPlaying = false;
        _isBuffering = false;
        _hasError = false;
        _currentPosition = 0;
        _totalDuration = 0;
        _isDragging = false;
      });
    }

    if (_hasController) {
      await _controller.dispose();
      _hasController = false;
    }

    final viewType = PlatformUtils.isAndroid
        ? VideoViewType.platformView
        : VideoViewType.textureView;
    final controller = widget.isLocal && !PlatformUtils.isWeb
        ? VideoPlayerController.file(
            File(widget.videoUrl),
            viewType: viewType,
          )
        : VideoPlayerController.networkUrl(
            Uri.parse(widget.videoUrl),
            viewType: viewType,
          );
    _controller = controller;
    _hasController = true;

    controller.addListener(() {
      if (!mounted) return;
      if (!identical(_controller, controller)) return;

      setState(() {
        _isPlaying = controller.value.isPlaying;
        _isBuffering = controller.value.isBuffering;
        if (!_isDragging) {
          _currentPosition =
              controller.value.position.inMilliseconds.toDouble();
        }
        _totalDuration = controller.value.duration.inMilliseconds.toDouble();
      });
    });

    try {
      await controller.initialize().timeout(const Duration(seconds: 30));
      if (mounted && identical(_controller, controller)) {
        setState(() {
          _isInitialized = true;
          _totalDuration = controller.value.duration.inMilliseconds.toDouble();
        });
        await controller.seekTo(Duration.zero);
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted && identical(_controller, controller)) {
          controller.play();
        }
      }
    } catch (e) {
      debugPrint('视频初始化失败: $e');
      if (mounted && identical(_controller, controller)) {
        setState(() => _hasError = true);
      }
    }
  }

  @override
  void dispose() {
    if (_hasController) {
      _controller.dispose();
    }
    // 恢复状态栏
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    unawaited(
      SystemChrome.setPreferredOrientations(messageVideoRestoredOrientations),
    );
    super.dispose();
  }

  void _togglePlayPause() {
    if (!_hasController) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  Future<void> _saveVideo() async {
    if (PlatformUtils.isWeb) return;
    if (_isSaving || _isSaved) return;

    setState(() => _isSaving = true);

    try {
      // 请求相册权限
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          if (mounted) {
            setState(() => _isSaving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.warning_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      _localizedUiText(
                        context,
                        zhCN: '需要相册权限才能保存视频',
                        zhTW: '需要相簿權限才能儲存影片',
                        en: 'Photo library permission is required to save videos',
                      ),
                    ),
                  ],
                ),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }
      }

      // 下载视频到临时目录
      final tempDir = await getTemporaryDirectory();
      final fileName = 'video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final savePath = '${tempDir.path}/$fileName';

      final dio = Dio();
      await dio.download(widget.videoUrl, savePath);

      // 保存到相册
      await Gal.putVideo(savePath);

      if (mounted) {
        setState(() {
          _isSaving = false;
          _isSaved = true;
        });

        // 显示成功提示
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  _localizedUiText(
                    context,
                    zhCN: '视频已保存到相册',
                    zhTW: '影片已儲存到相簿',
                    en: 'Video saved to album',
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.black87,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // 清理临时文件
      try {
        await File(savePath).delete();
      } catch (_) {}
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                SizedBox(width: 8),
                Text(
                  _localizedUiText(
                    context,
                    zhCN: '保存失败，请重启应用后重试',
                    zhTW: '儲存失敗，請重新啟動應用後再試',
                    en: 'Save failed. Restart the app and try again.',
                  ),
                ),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    return DarkSystemUiScope(
      child: PopScope(
        canPop: true,
        child: GestureDetector(
          onHorizontalDragEnd: (details) {
            // 左滑返回
            if (details.primaryVelocity != null &&
                details.primaryVelocity! > 300) {
              Navigator.pop(context);
            }
          },
          child: Scaffold(
            key: const ValueKey('message_video_player_page'),
            backgroundColor: Colors.black,
            body: GestureDetector(
              onTap: _toggleControls,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 封面/视频
                  Center(
                    child: _isInitialized
                        ? AspectRatio(
                            aspectRatio: _controller.value.aspectRatio,
                            child: VideoPlayer(_controller),
                          )
                        : _buildThumbnailCover(),
                  ),

                  if (_hasError)
                    Center(
                      child: GestureDetector(
                        onTap: () {
                          setState(() => _hasError = false);
                          _initializeVideo();
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.white,
                              size: 40,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _localizedUiText(
                                context,
                                zhCN: '加载失败，点击重试',
                                zhTW: '載入失敗，點擊重試',
                                en: 'Load failed. Tap to retry.',
                              ),
                              style:
                                  TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (!_isInitialized || _isBuffering)
                    Center(child: _buildLoadingIndicator()),

                  // 控制层
                  AnimatedOpacity(
                    opacity: _showControls ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withOpacity(0.5),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withOpacity(0.7),
                          ],
                          stops: const [0.0, 0.2, 0.8, 1.0],
                        ),
                      ),
                    ),
                  ),

                  // 顶部栏
                  if (_showControls)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.arrow_back_ios_rounded),
                                color: Colors.white,
                                iconSize: 24,
                              ),
                              const Spacer(),
                              // 保存按钮
                              if (!PlatformUtils.isWeb)
                                IconButton(
                                  onPressed: _isSaving ? null : _saveVideo,
                                  icon: _isSaving
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          _isSaved
                                              ? Icons.check_circle_rounded
                                              : Icons.download_rounded,
                                          color: _isSaved
                                              ? Colors.green
                                              : Colors.white,
                                        ),
                                  iconSize: 24,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // 中央播放/暂停按钮
                  if (_showControls && _isInitialized && !_isBuffering)
                    Center(
                      child: GestureDetector(
                        onTap: _togglePlayPause,
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 40,
                          ),
                        ),
                      ),
                    ),

                  // 底部控制栏
                  if (_showControls && _isInitialized)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 进度条
                              SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14,
                                  ),
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor: Colors.white.withOpacity(
                                    0.3,
                                  ),
                                  thumbColor: Colors.white,
                                  overlayColor: Colors.white.withOpacity(0.2),
                                ),
                                child: Slider(
                                  value: _currentPosition.clamp(
                                    0,
                                    _totalDuration,
                                  ),
                                  max: _totalDuration > 0 ? _totalDuration : 1,
                                  onChangeStart: (_) {
                                    setState(() => _isDragging = true);
                                  },
                                  onChanged: (value) {
                                    setState(() => _currentPosition = value);
                                  },
                                  onChangeEnd: (value) {
                                    setState(() => _isDragging = false);
                                    _controller.seekTo(
                                      Duration(milliseconds: value.toInt()),
                                    );
                                  },
                                ),
                              ),

                              // 时间显示
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(
                                        Duration(
                                          milliseconds:
                                              _currentPosition.toInt(),
                                        ),
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      _formatDuration(
                                        Duration(
                                          milliseconds: _totalDuration.toInt(),
                                        ),
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
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
          ),
        ),
      ),
    );
  }

  /// 构建封面缩略图
  Widget _buildThumbnailCover() {
    if (widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty) {
      // 本地文件
      if (!PlatformUtils.isWeb &&
          ChatMediaCacheManager.isLocalPath(widget.thumbnailUrl)) {
        return Image.file(
          File(widget.thumbnailUrl!),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        );
      }
      // 网络图片
      final thumbnailUrl = ChatMediaCacheManager.normalizeUrl(
        widget.thumbnailUrl,
      );
      if (thumbnailUrl.isEmpty || !thumbnailUrl.startsWith('http')) {
        return _buildPlaceholder();
      }
      return CachedNetworkImage(
        key: ValueKey<String>(thumbnailUrl),
        imageUrl: thumbnailUrl,
        cacheManager: ChatMediaCacheManager.instance,
        fit: BoxFit.contain,
        placeholder: (_, __) => _buildPlaceholder(),
        errorWidget: (_, __, ___) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  /// 封面占位
  Widget _buildPlaceholder() {
    return const ColoredBox(color: Colors.black);
  }

  Widget _buildLoadingIndicator() {
    return Column(
      key: const ValueKey('message_video_loading_indicator'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 2,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _localizedUiText(
            context,
            zhCN: '正在加载视频...',
            zhTW: '正在載入影片...',
            en: 'Loading video...',
          ),
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}
