import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';
import 'package:universal_io/io.dart';

import '../../../core/constants/emoji_animations.dart';
import '../../../core/theme/app_colors.dart';
import '../services/emoji_store_service.dart';

class EmojiStorePage extends StatefulWidget {
  final int initialTab;

  const EmojiStorePage({
    super.key,
    this.initialTab = 0,
  });

  @override
  State<EmojiStorePage> createState() => _EmojiStorePageState();
}

class _EmojiStorePageState extends State<EmojiStorePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedCustomIds = <String>{};

  List<String> _installedPackIds = <String>[];
  List<String> _favoriteCodes = <String>[];
  List<CustomEmojiItem> _customEmojis = <CustomEmojiItem>[];
  List<StickerPack> _packCatalog = BuiltInStickerPacks.all;
  bool _isLoading = true;
  bool _customEditMode = false;

  List<StickerPack> get _installedPacks {
    final map = {
      for (final p in _packCatalog) p.id: p,
    };
    return _installedPackIds
        .map((id) => map[id])
        .whereType<StickerPack>()
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    if (widget.initialTab >= 0 && widget.initialTab <= 2) {
      _tabController.index = widget.initialTab;
    }
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
      _isLoading = false;
    });
  }

  Future<void> _addPack(StickerPack pack) async {
    await EmojiStoreService.addPack(pack.id);
    await _loadData();
  }

  Future<void> _removePack(StickerPack pack) async {
    await EmojiStoreService.removePack(pack.id);
    await _loadData();
  }

  Future<void> _toggleFavoritePackPreview(StickerPack pack) async {
    await EmojiStoreService.toggleFavoriteEmoji(pack.previewEmoji);
    await _loadData();
  }

  bool _isFavoriteEmoji(String emoji) {
    return _favoriteCodes
        .contains(EmojiStoreService.favoriteCodeForEmoji(emoji));
  }

  Future<void> _pickCustomEmoji() async {
    final picker = ImagePicker();
    final x = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (x == null) return;

    final item = await EmojiStoreService.addCustomEmojiFromPath(x.path);
    if (item == null || !mounted) return;

    await _loadData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('自定义表情已保存')),
    );
  }

  Future<void> _deleteSelectedCustom() async {
    if (_selectedCustomIds.isEmpty) return;
    await EmojiStoreService.deleteCustomEmojis(_selectedCustomIds);
    if (!mounted) return;
    setState(() => _selectedCustomIds.clear());
    await _loadData();
  }

  Future<void> _reorderInstalled(int oldIndex, int newIndex) async {
    final list = [..._installedPackIds];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    await EmojiStoreService.setInstalledPackIds(list);
    await _loadData();
  }

  Future<void> _reorderCustom(int oldIndex, int newIndex) async {
    final list = [..._customEmojis];
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex, item);
    await EmojiStoreService.saveCustomEmojis(list);
    await _loadData();
  }

  Future<void> _toggleFavoriteCustom(CustomEmojiItem item) async {
    await EmojiStoreService.toggleFavoriteCustom(item.id);
    await _loadData();
  }

  void _openPackDetail(StickerPack pack) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final installed = _installedPackIds.contains(pack.id);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: 420,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  leading: SizedBox(
                    width: 42,
                    height: 42,
                    child: Lottie.asset(pack.previewPath, repeat: true),
                  ),
                  title: Text(pack.name),
                  subtitle: Text('${pack.count} 个表情'),
                  trailing: IconButton(
                    icon: Icon(
                      _isFavoriteEmoji(pack.previewEmoji)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: _isFavoriteEmoji(pack.previewEmoji)
                          ? Colors.red
                          : null,
                    ),
                    onPressed: () => _toggleFavoritePackPreview(pack),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    pack.description,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 6,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: pack.stickerFiles.length,
                    itemBuilder: (_, index) {
                      final file = pack.stickerFiles[index];
                      return Lottie.asset(
                        EmojiAnimations.getPath(file),
                        repeat: true,
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        if (installed) {
                          await _removePack(pack);
                        } else {
                          await _addPack(pack);
                        }
                        if (!mounted) return;
                        Navigator.of(this.context).pop();
                      },
                      child: Text(installed ? '移除' : '添加'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final query = _searchController.text.trim().toLowerCase();
    final shopPacks = _packCatalog.where((p) {
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) ||
          p.description.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('表情商店'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '商店'),
            Tab(text: '我的表情'),
            Tab(text: '制作表情'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildShopTab(isDark, shopPacks),
                _buildMyPacksTab(isDark),
                _buildCustomTab(isDark),
              ],
            ),
    );
  }

  Widget _buildShopTab(bool isDark, List<StickerPack> packs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '搜索表情包',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              filled: true,
              fillColor:
                  isDark ? Colors.white10 : Colors.black.withOpacity(0.04),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: packs.length,
            itemBuilder: (_, index) {
              final pack = packs[index];
              final installed = _installedPackIds.contains(pack.id);

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  onTap: () => _openPackDetail(pack),
                  leading: SizedBox(
                    width: 40,
                    height: 40,
                    child: Lottie.asset(pack.previewPath, repeat: true),
                  ),
                  title: Text(pack.name),
                  subtitle: Text('${pack.count} 个表情'),
                  trailing: FilledButton.tonal(
                    onPressed: () async {
                      HapticFeedback.selectionClick();
                      if (installed) {
                        await _removePack(pack);
                      } else {
                        await _addPack(pack);
                      }
                    },
                    child: Text(installed ? '已添加' : '添加'),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMyPacksTab(bool isDark) {
    if (_installedPacks.isEmpty) {
      return const Center(
        child: Text('还没有添加表情包，请到商店添加'),
      );
    }

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _installedPacks.length,
      onReorder: _reorderInstalled,
      itemBuilder: (_, index) {
        final pack = _installedPacks[index];
        return Card(
          key: ValueKey(pack.id),
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: SizedBox(
              width: 40,
              height: 40,
              child: Lottie.asset(pack.previewPath, repeat: true),
            ),
            title: Text(pack.name),
            subtitle: const Text('长按右侧拖动可排序'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () => _removePack(pack),
                  icon: const Icon(Icons.delete_outline),
                  color: AppColors.error,
                ),
                const Icon(Icons.drag_handle),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomTab(bool isDark) {
    final hasSelection = _selectedCustomIds.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              FilledButton.icon(
                onPressed: _pickCustomEmoji,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('从相册制作'),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _customEditMode = !_customEditMode;
                    _selectedCustomIds.clear();
                  });
                },
                child: Text(_customEditMode ? '完成' : '整理'),
              ),
              const Spacer(),
              if (_customEditMode)
                TextButton.icon(
                  onPressed: hasSelection ? _deleteSelectedCustom : null,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除选中'),
                ),
            ],
          ),
        ),
        Expanded(
          child: _customEmojis.isEmpty
              ? const Center(child: Text('暂无自定义表情'))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: _customEmojis.length,
                  onReorder: _reorderCustom,
                  itemBuilder: (_, index) {
                    final item = _customEmojis[index];
                    final isFavorite = _favoriteCodes.contains(
                      EmojiStoreService.favoriteCodeForCustom(item.id),
                    );

                    return Card(
                      key: ValueKey(item.id),
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        onTap: _customEditMode
                            ? () {
                                setState(() {
                                  if (_selectedCustomIds.contains(item.id)) {
                                    _selectedCustomIds.remove(item.id);
                                  } else {
                                    _selectedCustomIds.add(item.id);
                                  }
                                });
                              }
                            : null,
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: EmojiStoreService.isHttpUrl(item.path)
                              ? Image.network(
                                  item.path,
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) {
                                    return Container(
                                      width: 42,
                                      height: 42,
                                      color: isDark
                                          ? Colors.white10
                                          : Colors.black12,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                          Icons.broken_image_outlined),
                                    );
                                  },
                                )
                              : Image.file(
                                  File(item.path),
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) {
                                    return Container(
                                      width: 42,
                                      height: 42,
                                      color: isDark
                                          ? Colors.white10
                                          : Colors.black12,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                          Icons.broken_image_outlined),
                                    );
                                  },
                                ),
                        ),
                        title: Text(
                          '自定义表情 ${index + 1}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          '长按右侧拖动排序',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.white54 : Colors.black45,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_customEditMode)
                              Checkbox(
                                value: _selectedCustomIds.contains(item.id),
                                onChanged: (_) {
                                  setState(() {
                                    if (_selectedCustomIds.contains(item.id)) {
                                      _selectedCustomIds.remove(item.id);
                                    } else {
                                      _selectedCustomIds.add(item.id);
                                    }
                                  });
                                },
                              )
                            else
                              IconButton(
                                onPressed: () => _toggleFavoriteCustom(item),
                                icon: Icon(
                                  isFavorite
                                      ? Icons.favorite
                                      : Icons.favorite_border,
                                  color: isFavorite ? Colors.red : null,
                                ),
                              ),
                            const Icon(Icons.drag_handle),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
