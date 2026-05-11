import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:universal_io/io.dart';

import '../../../core/constants/emoji_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../pages/emoji_store_page.dart';
import '../services/emoji_store_service.dart';

/// 聊天输入区表情面板
class TGEmojiPicker extends StatefulWidget {
  final Function(String emoji, {bool isAnimated}) onEmojiSelected;
  final VoidCallback? onStickerTap;
  final VoidCallback? onGifTap;
  final double height;

  const TGEmojiPicker({
    super.key,
    required this.onEmojiSelected,
    this.onStickerTap,
    this.onGifTap,
    this.height = 280,
  });

  @override
  State<TGEmojiPicker> createState() => _TGEmojiPickerState();
}

class _TGEmojiPickerState extends State<TGEmojiPicker> {
  late final PageController _pageController;

  bool _isLoaded = false;
  int _currentIndex = 0;
  List<String> _installedPackIds = <String>[];
  List<String> _favoriteCodes = <String>[];
  List<CustomEmojiItem> _customEmojis = <CustomEmojiItem>[];
  List<StickerPack> _packCatalog = BuiltInStickerPacks.all;

  List<StickerPack> get _installedPacks {
    final map = {
      for (final p in _packCatalog) p.id: p,
    };
    return _installedPackIds
        .map((id) => map[id])
        .whereType<StickerPack>()
        .toList();
  }

  List<_PanelTab> get _tabs => [
        const _PanelTab.emoji(),
        const _PanelTab.favorites(),
        ..._installedPacks.map(_PanelTab.pack),
      ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _loadData();
  }

  Future<void> _loadData() async {
    final results = await Future.wait<dynamic>([
      EmojiStoreService.loadAll(),
      EmojiStoreService.loadPackCatalog(),
    ]);
    final data = results[0] as EmojiStoreData;
    final catalog = results[1] as List<StickerPack>;
    if (!mounted) return;

    setState(() {
      _installedPackIds = data.installedPackIds;
      _favoriteCodes = data.favoriteCodes;
      _customEmojis = data.customEmojis;
      _packCatalog = catalog.isEmpty ? BuiltInStickerPacks.all : catalog;
      _isLoaded = true;
      if (_currentIndex >= _tabs.length) {
        _currentIndex = 0;
      }
    });
  }

  Future<void> _openStore({int initialTab = 0}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EmojiStorePage(initialTab: initialTab),
      ),
    );
    await _loadData();
  }

  Future<void> _toggleEmojiFavorite(String emoji) async {
    await EmojiStoreService.toggleFavoriteEmoji(emoji);
    await _loadData();
  }

  Future<void> _toggleCustomFavorite(CustomEmojiItem item) async {
    await EmojiStoreService.toggleFavoriteCustom(item.id);
    await _loadData();
  }

  bool _isFavoriteEmoji(String emoji) {
    return _favoriteCodes
        .contains(EmojiStoreService.favoriteCodeForEmoji(emoji));
  }

  bool _isFavoriteCustom(String id) {
    return _favoriteCodes.contains(EmojiStoreService.favoriteCodeForCustom(id));
  }

  void _selectAnimatedEmoji(String emoji) {
    HapticFeedback.selectionClick();
    widget.onEmojiSelected(emoji, isAnimated: true);
    EmojiStoreService.addRecentEmoji(emoji);
  }

  void _selectCustomEmoji(CustomEmojiItem item) {
    HapticFeedback.selectionClick();
    if (item.hasLocalPath) {
      widget.onEmojiSelected(
        '${EmojiStoreService.customEmojiSendPrefix}${item.path}',
        isAnimated: false,
      );
      return;
    }
    final remote = item.remoteUrl ?? item.path;
    if (remote.isNotEmpty) {
      widget.onEmojiSelected(
        '${EmojiStoreService.customEmojiSendUrlPrefix}$remote',
        isAnimated: false,
      );
    }
  }

  void _goPage(int index) {
    if (index < 0 || index >= _tabs.length) return;
    setState(() => _currentIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (!_isLoaded) {
      return SizedBox(
        height: widget.height,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        children: [
          _buildTopBar(isDark),
          _buildSearchEntry(isDark),
          Container(
            height: 0.5,
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentIndex = index),
              itemCount: _tabs.length,
              itemBuilder: (_, index) {
                final tab = _tabs[index];
                if (tab.type == _PanelTabType.emoji) {
                  return _buildEmojiGrid();
                }
                if (tab.type == _PanelTabType.favorites) {
                  return _buildFavoritesGrid(isDark);
                }
                return _buildPackGrid(tab.pack!);
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    return SizedBox(
      height: 42,
      child: Row(
        children: [
          IconButton(
            tooltip: '表情商店',
            onPressed: () => _openStore(initialTab: 0),
            icon: Icon(
              Icons.storefront_outlined,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _tabs.length,
              itemBuilder: (_, index) {
                final tab = _tabs[index];
                final selected = _currentIndex == index;
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _goPage(index);
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(
                      color: selected
                          ? (isDark
                              ? Colors.white12
                              : AppColors.primary.withOpacity(0.1))
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(child: _buildTabIcon(tab, selected, isDark)),
                  ),
                );
              },
            ),
          ),
          IconButton(
            tooltip: '删除',
            onPressed: () =>
                widget.onEmojiSelected('BACKSPACE', isAnimated: false),
            icon: Icon(
              Icons.backspace_outlined,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabIcon(_PanelTab tab, bool selected, bool isDark) {
    switch (tab.type) {
      case _PanelTabType.emoji:
        return Icon(
          Icons.emoji_emotions_outlined,
          size: 20,
          color: selected
              ? AppColors.primary
              : (isDark ? Colors.white54 : Colors.black38),
        );
      case _PanelTabType.favorites:
        return Icon(
          Icons.favorite_border_rounded,
          size: 20,
          color: selected
              ? Colors.redAccent
              : (isDark ? Colors.white54 : Colors.black38),
        );
      case _PanelTabType.pack:
        return SizedBox(
          width: 22,
          height: 22,
          child: Lottie.asset(
            tab.pack!.previewPath,
            repeat: selected,
            animate: true,
          ),
        );
    }
  }

  Widget _buildSearchEntry(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openStore(initialTab: 0),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                Icons.search,
                size: 16,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              const SizedBox(width: 6),
              Text(
                '搜索表情商店',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => _openStore(initialTab: 1),
                child: const Text('我的表情'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmojiGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: EmojiAnimations.all.length,
      itemBuilder: (_, index) {
        final item = EmojiAnimations.all[index];
        final favorite = _isFavoriteEmoji(item.emoji);
        return _EmojiTile(
          lottiePath: item.path,
          favorite: favorite,
          onTap: () => _selectAnimatedEmoji(item.emoji),
          onLongPress: () => _toggleEmojiFavorite(item.emoji),
        );
      },
    );
  }

  Widget _buildFavoritesGrid(bool isDark) {
    final customMap = {
      for (final c in _customEmojis) c.id: c,
    };

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
      ),
      itemCount: _favoriteCodes.length + 1,
      itemBuilder: (_, index) {
        if (index == 0) {
          return _CreateEmojiTile(
            onTap: () => _openStore(initialTab: 2),
          );
        }

        final code = _favoriteCodes[index - 1];
        if (EmojiStoreService.isEmojiFavoriteCode(code)) {
          final emoji = EmojiStoreService.emojiFromFavoriteCode(code);
          final animated = EmojiAnimations.findByEmoji(emoji);
          return _EmojiTile(
            lottiePath: animated?.path,
            text: animated == null ? emoji : null,
            favorite: true,
            onTap: () => _selectAnimatedEmoji(emoji),
            onLongPress: () => _toggleEmojiFavorite(emoji),
          );
        }

        if (EmojiStoreService.isCustomFavoriteCode(code)) {
          final customId = EmojiStoreService.customIdFromFavoriteCode(code);
          final custom = customMap[customId];
          if (custom == null) {
            return const SizedBox.shrink();
          }
          return _CustomEmojiTile(
            item: custom,
            favorite: _isFavoriteCustom(custom.id),
            onTap: () => _selectCustomEmoji(custom),
            onLongPress: () => _toggleCustomFavorite(custom),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildPackGrid(StickerPack pack) {
    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 6,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: pack.stickerFiles.length,
      itemBuilder: (_, index) {
        final file = pack.stickerFiles[index];
        final animated = EmojiAnimations.all.firstWhere(
          (e) => e.file == file,
          orElse: () => EmojiAnimations.all.first,
        );
        return _EmojiTile(
          lottiePath: EmojiAnimations.getPath(file),
          favorite: _isFavoriteEmoji(animated.emoji),
          onTap: () => _selectAnimatedEmoji(animated.emoji),
          onLongPress: () => _toggleEmojiFavorite(animated.emoji),
        );
      },
    );
  }
}

enum _PanelTabType { emoji, favorites, pack }

class _PanelTab {
  final _PanelTabType type;
  final StickerPack? pack;

  const _PanelTab.emoji()
      : type = _PanelTabType.emoji,
        pack = null;
  const _PanelTab.favorites()
      : type = _PanelTabType.favorites,
        pack = null;
  const _PanelTab.pack(this.pack) : type = _PanelTabType.pack;
}

class _EmojiTile extends StatelessWidget {
  final String? lottiePath;
  final String? text;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _EmojiTile({
    this.lottiePath,
    this.text,
    required this.favorite,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
              ),
              child: lottiePath != null
                  ? Lottie.asset(lottiePath!, repeat: true)
                  : Center(
                      child: Text(
                        text ?? '',
                        style: const TextStyle(fontSize: 24),
                      ),
                    ),
            ),
          ),
          if (favorite)
            const Positioned(
              top: 2,
              right: 2,
              child: Icon(Icons.favorite, size: 12, color: Colors.redAccent),
            ),
        ],
      ),
    );
  }
}

class _CreateEmojiTile extends StatelessWidget {
  final VoidCallback onTap;

  const _CreateEmojiTile({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.3),
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_photo_alternate_outlined, size: 20),
            SizedBox(height: 2),
            Text('制作', style: TextStyle(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _CustomEmojiTile extends StatelessWidget {
  final CustomEmojiItem item;
  final bool favorite;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _CustomEmojiTile({
    required this.item,
    required this.favorite,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: EmojiStoreService.isHttpUrl(item.path)
                  ? Image.network(
                      item.path,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: isDark ? Colors.white10 : Colors.black12,
                        alignment: Alignment.center,
                        child:
                            const Icon(Icons.broken_image_outlined, size: 16),
                      ),
                    )
                  : Image.file(
                      File(item.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: isDark ? Colors.white10 : Colors.black12,
                        alignment: Alignment.center,
                        child:
                            const Icon(Icons.broken_image_outlined, size: 16),
                      ),
                    ),
            ),
          ),
          if (favorite)
            const Positioned(
              top: 2,
              right: 2,
              child: Icon(Icons.favorite, size: 12, color: Colors.redAccent),
            ),
        ],
      ),
    );
  }
}
