// 文件用途：实现 _ChatMediaPickerResult 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 _ChatMediaPickerResult 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
part of 'chat_detail_page.dart';

// 关键声明：chat detail media picker 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class _ChatMediaPickerResult {
  const _ChatMediaPickerResult({
    required this.items,
    required this.sendOriginal,
  });

  final List<_ChatPickedMedia> items;
  final bool sendOriginal;
}

enum _ChatPickedMediaType { image, video }

class _ChatPickedMedia {
  const _ChatPickedMedia({
    required this.file,
    required this.type,
    required this.assetId,
    this.durationMilliseconds,
  });

  final XFile file;
  final _ChatPickedMediaType type;
  final String assetId;
  final int? durationMilliseconds;
}

extension _ChatDetailMediaPickerActions on _ChatDetailPageState {
  Future<_ChatMediaPickerResult?> _openChatMediaPicker() async {
    const requestOption = PermissionRequestOption(
      androidPermission: AndroidPermission(
        type: RequestType.common,
        mediaLocation: false,
      ),
    );
    final permission = await PhotoManager.requestPermissionExtend(
      requestOption: requestOption,
    );
    if (!permission.hasAccess) {
      if (mounted) {
        AppSnackBar.warning(
          context,
          _localizedText(
            zhCN: '需要相册权限才能选择图片或视频',
            zhTW: '需要相簿權限才能選擇圖片或影片',
            en: 'Photo library permission is required to choose media',
          ),
        );
      }
      return null;
    }
    if (!mounted) return null;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Navigator.of(context).push<_ChatMediaPickerResult>(
      MaterialPageRoute(
        builder: (_) => _ChatMediaPickerPage(
          isDark: isDark,
          maxCount: 9,
          limitedAccess: permission.isLimited,
        ),
      ),
    );
  }
}

class _ChatMediaPickerPage extends StatefulWidget {
  const _ChatMediaPickerPage({
    required this.isDark,
    required this.maxCount,
    required this.limitedAccess,
  });

  final bool isDark;
  final int maxCount;
  final bool limitedAccess;

  @override
  State<_ChatMediaPickerPage> createState() => _ChatMediaPickerPageState();
}

class _ChatMediaPickerPageState extends State<_ChatMediaPickerPage> {
  List<AssetPathEntity> _albums = const [];
  List<AssetEntity> _assets = const [];
  AssetPathEntity? _currentAlbum;
  final List<AssetEntity> _selectedAssets = [];
  final Set<String> _selectedIds = {};
  final Map<String, Future<Uint8List?>> _thumbnailFutures = {};
  bool _loading = true;
  bool _confirming = false;
  bool _sendOriginal = false;
  late bool _limitedAccess;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _limitedAccess = widget.limitedAccess;
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
      );
      if (!mounted) return;
      if (albums.isEmpty) {
        setState(() {
          _albums = const [];
          _assets = const [];
          _loading = false;
        });
        return;
      }

      _albums = albums;
      _currentAlbum = albums.first;
      await _loadAssets(albums.first);
    } catch (error, stackTrace) {
      debugPrint('[ChatMediaPicker] Failed to load albums: $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 8);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAssets(AssetPathEntity album) async {
    if (mounted) setState(() => _loading = true);
    try {
      final assets = await album.getAssetListRange(start: 0, end: 2000);
      if (!mounted || _currentAlbum?.id != album.id) return;
      final imageCount =
          assets.where((asset) => asset.type == AssetType.image).length;
      final videoCount =
          assets.where((asset) => asset.type == AssetType.video).length;
      debugPrint(
        '[ChatMediaPicker] album=${album.name} total=${assets.length} '
        'images=$imageCount videos=$videoCount limited=$_limitedAccess',
      );
      setState(() {
        _assets = assets;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('[ChatMediaPicker] Failed to load assets: $error');
      debugPrintStack(stackTrace: stackTrace, maxFrames: 8);
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Uint8List?> _thumbnailFor(AssetEntity asset) {
    return _thumbnailFutures.putIfAbsent(
      asset.id,
      () => asset.thumbnailDataWithSize(
        const ThumbnailSize(360, 360),
        quality: 82,
      ),
    );
  }

  void _toggleSelection(AssetEntity asset) {
    GlobalHaptics.selection();
    setState(() {
      if (_selectedIds.remove(asset.id)) {
        _selectedAssets.removeWhere((item) => item.id == asset.id);
        if (_selectedAssets.every((item) => item.type != AssetType.image)) {
          _sendOriginal = false;
        }
        return;
      }
      if (_selectedAssets.length >= widget.maxCount) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _pickerText(
                context,
                zhCN: '最多选择 ${widget.maxCount} 个图片或视频',
                zhTW: '最多選擇 ${widget.maxCount} 個圖片或影片',
                en: 'Select up to ${widget.maxCount} photos or videos',
              ),
            ),
            duration: const Duration(seconds: 1),
          ),
        );
        return;
      }
      _selectedIds.add(asset.id);
      _selectedAssets.add(asset);
    });
  }

  Future<void> _confirmSelection() async {
    if (_selectedAssets.isEmpty || _confirming) return;
    setState(() => _confirming = true);
    GlobalHaptics.medium();

    final items = <_ChatPickedMedia>[];
    for (final asset in _selectedAssets) {
      try {
        File? file;
        if (_sendOriginal && asset.type == AssetType.image) {
          file = await asset.originFile;
        }
        file ??= await asset.file;
        file ??= await asset.originFile;
        if (file == null || !await file.exists()) continue;
        items.add(
          _ChatPickedMedia(
            file: XFile(
              file.path,
              name: asset.title ?? file.uri.pathSegments.last,
            ),
            type: asset.type == AssetType.video
                ? _ChatPickedMediaType.video
                : _ChatPickedMediaType.image,
            assetId: asset.id,
            durationMilliseconds: asset.type == AssetType.video
                ? asset.duration * Duration.millisecondsPerSecond
                : null,
          ),
        );
      } catch (error, stackTrace) {
        debugPrint('[ChatMediaPicker] Failed to resolve ${asset.id}: $error');
        debugPrintStack(stackTrace: stackTrace, maxFrames: 8);
      }
    }

    if (!mounted) return;
    if (items.isEmpty) {
      setState(() => _confirming = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _pickerText(
              context,
              zhCN: '未能读取所选图片或视频，请重试',
              zhTW: '未能讀取所選圖片或影片，請重試',
              en: 'Could not read the selected media. Please try again.',
            ),
          ),
        ),
      );
      return;
    }

    Navigator.pop(
      context,
      _ChatMediaPickerResult(
        items: items,
        sendOriginal: _sendOriginal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final background = widget.isDark ? const Color(0xFF111111) : Colors.white;
    final foreground = widget.isDark ? Colors.white : const Color(0xFF111111);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: background,
        foregroundColor: foreground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _showAlbumPicker,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _currentAlbum?.name ??
                      _pickerText(
                        context,
                        zhCN: '最近项目',
                        zhTW: '最近項目',
                        en: 'Recents',
                      ),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
            ],
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_assets.isEmpty) {
      return Center(
        child: Text(
          _pickerText(
            context,
            zhCN: '相册中暂无图片或视频',
            zhTW: '相簿中暫無圖片或影片',
            en: 'No photos or videos',
          ),
          style: TextStyle(color: AppColors.textSecondaryFor(context)),
        ),
      );
    }

    return Column(
      children: [
        if (_limitedAccess) _buildLimitedAccessBanner(),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(1),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              crossAxisSpacing: 1,
              mainAxisSpacing: 1,
            ),
            cacheExtent: 700,
            itemCount: _assets.length,
            itemBuilder: (context, index) {
              final asset = _assets[index];
              final selectedIndex = _selectedAssets.indexWhere(
                (item) => item.id == asset.id,
              );
              return _ChatMediaPickerTile(
                asset: asset,
                thumbnail: _thumbnailFor(asset),
                selectedIndex: selectedIndex,
                onTap: () => _toggleSelection(asset),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLimitedAccessBanner() {
    return Material(
      color: widget.isDark ? const Color(0xFF252525) : const Color(0xFFF3F3F3),
      child: InkWell(
        onTap: _manageLimitedAccess,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            children: [
              const Icon(Icons.info_outline_rounded, size: 19),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _pickerText(
                    context,
                    zhCN: '当前仅显示已授权的部分图片和视频',
                    zhTW: '目前僅顯示已授權的部分圖片和影片',
                    en: 'Only selected photos and videos are available',
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text(
                _pickerText(
                  context,
                  zhCN: '管理',
                  zhTW: '管理',
                  en: 'Manage',
                ),
                style: const TextStyle(
                  color: Color(0xFF07C160),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _manageLimitedAccess() async {
    await PhotoManager.presentLimited(type: RequestType.common);
    const requestOption = PermissionRequestOption(
      androidPermission: AndroidPermission(
        type: RequestType.common,
        mediaLocation: false,
      ),
    );
    final permission = await PhotoManager.getPermissionState(
      requestOption: requestOption,
    );
    if (!mounted) return;
    setState(() => _limitedAccess = permission.isLimited);
    await _loadAlbums();
  }

  Future<void> _showPreview() async {
    if (_selectedAssets.isEmpty) return;
    final result = await Navigator.of(context).push<_ChatMediaPreviewResult>(
      MaterialPageRoute(
        builder: (_) => _ChatMediaPreviewPage(
          assets: List<AssetEntity>.from(_selectedAssets),
          selectedIds: Set<String>.from(_selectedIds),
          sendOriginal: _sendOriginal,
          isDark: widget.isDark,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedAssets.removeWhere(
        (asset) => !result.selectedIds.contains(asset.id),
      );
      _selectedIds
        ..clear()
        ..addAll(result.selectedIds);
      _sendOriginal = result.sendOriginal &&
          _selectedAssets.any((asset) => asset.type == AssetType.image);
    });
  }

  Widget _buildBottomBar() {
    final hasSelectedImage =
        _selectedAssets.any((asset) => asset.type == AssetType.image);
    final canSend = _selectedAssets.isNotEmpty && !_confirming;
    final isDark = widget.isDark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1B1B) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : const Color(0xFFE8E8E8),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              const SizedBox(width: 6),
              TextButton(
                onPressed: _selectedAssets.isNotEmpty ? _showPreview : null,
                child: Text(
                  _pickerText(
                    context,
                    zhCN: '预览',
                    zhTW: '預覽',
                    en: 'Preview',
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: hasSelectedImage
                    ? () {
                        GlobalHaptics.selection();
                        setState(() => _sendOriginal = !_sendOriginal);
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _sendOriginal
                              ? const Color(0xFF07C160)
                              : Colors.transparent,
                          border: Border.all(
                            width: 1.5,
                            color: _sendOriginal
                                ? const Color(0xFF07C160)
                                : (hasSelectedImage
                                    ? (isDark
                                        ? Colors.white54
                                        : const Color(0xFF777777))
                                    : (isDark
                                        ? Colors.white24
                                        : const Color(0xFFC8C8C8))),
                          ),
                        ),
                        child: _sendOriginal
                            ? const Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: Colors.white,
                              )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _pickerText(
                          context,
                          zhCN: '原图',
                          zhTW: '原圖',
                          en: 'Original',
                        ),
                        style: TextStyle(
                          fontSize: 15,
                          color: hasSelectedImage
                              ? (isDark ? Colors.white : Colors.black87)
                              : (isDark ? Colors.white24 : Colors.black26),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 38,
                child: FilledButton(
                  onPressed: canSend ? _confirmSelection : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF07C160),
                    disabledBackgroundColor: isDark
                        ? const Color(0xFF25583A)
                        : const Color(0xFFA5DBBB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: _confirming
                      ? const SizedBox(
                          width: 17,
                          height: 17,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _selectedAssets.isEmpty
                              ? _pickerText(
                                  context,
                                  zhCN: '发送',
                                  zhTW: '傳送',
                                  en: 'Send',
                                )
                              : _pickerText(
                                  context,
                                  zhCN: '发送(${_selectedAssets.length})',
                                  zhTW: '傳送(${_selectedAssets.length})',
                                  en: 'Send (${_selectedAssets.length})',
                                ),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                ),
              ),
              const SizedBox(width: 14),
            ],
          ),
        ),
      ),
    );
  }

  void _showAlbumPicker() {
    if (_albums.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
          ),
          decoration: BoxDecoration(
            color: widget.isDark ? const Color(0xFF202020) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 10),
            itemCount: _albums.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              indent: 76,
              color: widget.isDark ? Colors.white10 : const Color(0xFFEDEDED),
            ),
            itemBuilder: (_, index) {
              final album = _albums[index];
              final selected = album.id == _currentAlbum?.id;
              return ListTile(
                leading: _AlbumCover(
                  album: album,
                  isDark: widget.isDark,
                ),
                title: Text(
                  album.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: FutureBuilder<int>(
                  future: album.assetCountAsync,
                  builder: (_, snapshot) => Text('${snapshot.data ?? 0}'),
                ),
                trailing: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Color(0xFF07C160),
                      )
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  if (selected) return;
                  setState(() {
                    _currentAlbum = album;
                    _assets = const [];
                  });
                  _loadAssets(album);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _ChatMediaPreviewResult {
  const _ChatMediaPreviewResult({
    required this.selectedIds,
    required this.sendOriginal,
  });

  final Set<String> selectedIds;
  final bool sendOriginal;
}

class _ChatMediaPreviewPage extends StatefulWidget {
  const _ChatMediaPreviewPage({
    required this.assets,
    required this.selectedIds,
    required this.sendOriginal,
    required this.isDark,
  });

  final List<AssetEntity> assets;
  final Set<String> selectedIds;
  final bool sendOriginal;
  final bool isDark;

  @override
  State<_ChatMediaPreviewPage> createState() => _ChatMediaPreviewPageState();
}

class _ChatMediaPreviewPageState extends State<_ChatMediaPreviewPage> {
  late final Set<String> _selectedIds;
  late bool _sendOriginal;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.selectedIds);
    _sendOriginal = widget.sendOriginal;
  }

  AssetEntity get _currentAsset => widget.assets[_pageIndex];

  void _toggleCurrentSelection() {
    GlobalHaptics.selection();
    setState(() {
      if (!_selectedIds.remove(_currentAsset.id)) {
        _selectedIds.add(_currentAsset.id);
      }
      final hasSelectedImage = widget.assets.any(
        (asset) =>
            _selectedIds.contains(asset.id) && asset.type == AssetType.image,
      );
      if (!hasSelectedImage) _sendOriginal = false;
    });
  }

  void _complete() {
    Navigator.pop(
      context,
      _ChatMediaPreviewResult(
        selectedIds: Set<String>.from(_selectedIds),
        sendOriginal: _sendOriginal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasSelectedImage = widget.assets.any(
      (asset) =>
          _selectedIds.contains(asset.id) && asset.type == AssetType.image,
    );
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        systemOverlayStyle: AppSystemUiStyles.onDarkBackground,
        surfaceTintColor: Colors.transparent,
        title: Text('${_pageIndex + 1}/${widget.assets.length}'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _toggleCurrentSelection,
            icon: Icon(
              _selectedIds.contains(_currentAsset.id)
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: _selectedIds.contains(_currentAsset.id)
                  ? const Color(0xFF07C160)
                  : Colors.white70,
            ),
          ),
        ],
      ),
      body: PageView.builder(
        itemCount: widget.assets.length,
        onPageChanged: (index) => setState(() => _pageIndex = index),
        itemBuilder: (_, index) => _ChatMediaPreviewItem(
          key: ValueKey(widget.assets[index].id),
          asset: widget.assets[index],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: const Color(0xFF161616),
          child: Row(
            children: [
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: hasSelectedImage
                    ? () {
                        GlobalHaptics.selection();
                        setState(() => _sendOriginal = !_sendOriginal);
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _sendOriginal
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: _sendOriginal
                            ? const Color(0xFF07C160)
                            : (hasSelectedImage
                                ? Colors.white70
                                : Colors.white24),
                        size: 23,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        _pickerText(
                          context,
                          zhCN: '原图',
                          zhTW: '原圖',
                          en: 'Original',
                        ),
                        style: TextStyle(
                          color:
                              hasSelectedImage ? Colors.white : Colors.white24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _complete,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF07C160),
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  _pickerText(
                    context,
                    zhCN: '完成(${_selectedIds.length})',
                    zhTW: '完成(${_selectedIds.length})',
                    en: 'Done (${_selectedIds.length})',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatMediaPreviewItem extends StatefulWidget {
  const _ChatMediaPreviewItem({super.key, required this.asset});

  final AssetEntity asset;

  @override
  State<_ChatMediaPreviewItem> createState() => _ChatMediaPreviewItemState();
}

class _ChatMediaPreviewItemState extends State<_ChatMediaPreviewItem> {
  Future<Uint8List?>? _imageBytes;
  VideoPlayerController? _videoController;
  Future<void>? _videoInitialization;

  @override
  void initState() {
    super.initState();
    if (widget.asset.type == AssetType.video) {
      _videoInitialization = _initializeVideo();
    } else {
      _imageBytes = _loadImage();
    }
  }

  Future<Uint8List?> _loadImage() async {
    final originBytes = await widget.asset.originBytes;
    if (originBytes != null) return originBytes;
    return widget.asset.thumbnailDataWithSize(
      const ThumbnailSize(1600, 1600),
      quality: 92,
    );
  }

  Future<void> _initializeVideo() async {
    final file = await widget.asset.file ?? await widget.asset.originFile;
    if (file == null || !await file.exists()) return;
    final controller = VideoPlayerController.file(
      file,
      viewType: PlatformUtils.isAndroid
          ? VideoViewType.platformView
          : VideoViewType.textureView,
    );
    _videoController = controller;
    await controller.initialize();
    await controller.setLooping(true);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.asset.type == AssetType.video) {
      return FutureBuilder<void>(
        future: _videoInitialization,
        builder: (_, snapshot) {
          final controller = _videoController;
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError ||
              controller == null ||
              controller.value.hasError ||
              !controller.value.isInitialized) {
            return _buildVideoFallback(context);
          }
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              setState(() {
                if (controller.value.isPlaying) {
                  controller.pause();
                } else {
                  controller.play();
                }
              });
            },
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: controller.value.aspectRatio,
                    child: VideoPlayer(controller),
                  ),
                ),
                if (!controller.value.isPlaying)
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black54,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
              ],
            ),
          );
        },
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _imageBytes,
      builder: (_, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return InteractiveViewer(
          minScale: 1,
          maxScale: 5,
          child: Center(child: Image.memory(bytes, fit: BoxFit.contain)),
        );
      },
    );
  }

  Widget _buildVideoFallback(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: widget.asset.thumbnailDataWithSize(
        const ThumbnailSize(1280, 1280),
        quality: 88,
      ),
      builder: (_, snapshot) {
        return Stack(
          fit: StackFit.expand,
          children: [
            if (snapshot.data != null)
              Image.memory(snapshot.data!, fit: BoxFit.contain)
            else
              const ColoredBox(color: Colors.black),
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 28),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.64),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _pickerText(
                    context,
                    zhCN: '此视频无法预览，仍可正常发送',
                    zhTW: '此影片無法預覽，仍可正常傳送',
                    en: 'Preview unavailable. You can still send it.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChatMediaPickerTile extends StatelessWidget {
  const _ChatMediaPickerTile({
    required this.asset,
    required this.thumbnail,
    required this.selectedIndex,
    required this.onTap,
  });

  final AssetEntity asset;
  final Future<Uint8List?> thumbnail;
  final int selectedIndex;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = selectedIndex >= 0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List?>(
            future: thumbnail,
            builder: (_, snapshot) {
              final data = snapshot.data;
              if (data == null) {
                return Container(color: const Color(0xFFE8E8E8));
              }
              return Image.memory(data,
                  fit: BoxFit.cover, gaplessPlayback: true);
            },
          ),
          if (selected) Container(color: Colors.black.withOpacity(0.18)),
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? const Color(0xFF07C160) : Colors.black26,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: selected
                  ? Text(
                      '${selectedIndex + 1}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
          ),
          if (asset.type == AssetType.video)
            Positioned(
              left: 5,
              right: 5,
              bottom: 4,
              child: Row(
                children: [
                  const Icon(
                    Icons.videocam_rounded,
                    color: Colors.white,
                    size: 15,
                  ),
                  const Spacer(),
                  Text(
                    _formatMediaDuration(asset.duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      shadows: [Shadow(blurRadius: 3, color: Colors.black87)],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AlbumCover extends StatelessWidget {
  const _AlbumCover({required this.album, required this.isDark});

  final AssetPathEntity album;
  final bool isDark;

  Future<Uint8List?> _load() async {
    final assets = await album.getAssetListRange(start: 0, end: 1);
    if (assets.isEmpty) return null;
    return assets.first.thumbnailDataWithSize(const ThumbnailSize(120, 120));
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 50,
        height: 50,
        child: FutureBuilder<Uint8List?>(
          future: _load(),
          builder: (_, snapshot) {
            final data = snapshot.data;
            if (data != null) return Image.memory(data, fit: BoxFit.cover);
            return ColoredBox(
              color: isDark ? Colors.white10 : const Color(0xFFF0F0F0),
              child: const Icon(Icons.photo_library_outlined),
            );
          },
        ),
      ),
    );
  }
}

String _formatMediaDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remaining = seconds % 60;
  return '$minutes:${remaining.toString().padLeft(2, '0')}';
}

String _pickerText(
  BuildContext context, {
  required String zhCN,
  required String zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW;
    case AppLanguage.zhCN:
      return zhCN;
  }
}
