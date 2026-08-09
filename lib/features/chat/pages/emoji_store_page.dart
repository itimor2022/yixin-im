// 文件用途：实现 EmojiStorePage 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 EmojiStorePage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';

import '../../../core/constants/emoji_animations.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/sticker_image.dart';
import '../services/emoji_store_service.dart';

String _emojiStoreText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

Widget _stickerAssetPreview(
  String file, {
  BoxFit fit = BoxFit.contain,
  bool repeat = true,
}) {
  return StickerImage(
    source: file,
    fit: fit,
    repeat: repeat,
    animate: repeat,
    errorBuilder: (_, __) => const SizedBox.shrink(),
  );
}

// 关键声明：emoji store page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
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

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
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
      SnackBar(
        content: Text(
          _emojiStoreText(
            context,
            zhCN: '自定义表情已保存',
            zhTW: '自訂表情已儲存',
            en: 'Custom emoji saved',
          ),
        ),
      ),
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
                    child: _stickerAssetPreview(pack.previewFile),
                  ),
                  title: Text(
                    pack.localizedName(AppLocalizations.of(context).language),
                  ),
                  subtitle: Text(
                    _emojiStoreText(
                      context,
                      zhCN: '${pack.count} 个表情',
                      zhTW: '${pack.count} 個表情',
                      en: '${pack.count} stickers',
                    ),
                  ),
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
                    pack.localizedDescription(
                      AppLocalizations.of(context).language,
                    ),
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
                      return _stickerAssetPreview(file);
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
                      child: Text(
                        installed
                            ? _emojiStoreText(
                                context,
                                zhCN: '移除',
                                zhTW: '移除',
                                en: 'Remove',
                              )
                            : _emojiStoreText(
                                context,
                                zhCN: '添加',
                                zhTW: '新增',
                                en: 'Add',
                              ),
                      ),
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
        title: Text(
          _emojiStoreText(
            context,
            zhCN: '表情商店',
            zhTW: '表情商店',
            en: 'Sticker Store',
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              text: _emojiStoreText(
                context,
                zhCN: '商店',
                zhTW: '商店',
                en: 'Store',
              ),
            ),
            Tab(
              text: _emojiStoreText(
                context,
                zhCN: '我的表情',
                zhTW: '我的表情',
                en: 'My Stickers',
              ),
            ),
            Tab(
              text: _emojiStoreText(
                context,
                zhCN: '制作表情',
                zhTW: '製作表情',
                en: 'Create',
              ),
            ),
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
              hintText: _emojiStoreText(
                context,
                zhCN: '搜索表情包',
                zhTW: '搜尋表情包',
                en: 'Search sticker packs',
              ),
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
                    child: _stickerAssetPreview(pack.previewFile),
                  ),
                  title: Text(
                    pack.localizedName(AppLocalizations.of(context).language),
                  ),
                  subtitle: Text(
                    _emojiStoreText(
                      context,
                      zhCN: '${pack.count} 个表情',
                      zhTW: '${pack.count} 個表情',
                      en: '${pack.count} stickers',
                    ),
                  ),
                  trailing: FilledButton.tonal(
                    onPressed: () async {
                      HapticFeedback.selectionClick();
                      if (installed) {
                        await _removePack(pack);
                      } else {
                        await _addPack(pack);
                      }
                    },
                    child: Text(
                      installed
                          ? _emojiStoreText(
                              context,
                              zhCN: '已添加',
                              zhTW: '已新增',
                              en: 'Added',
                            )
                          : _emojiStoreText(
                              context,
                              zhCN: '添加',
                              zhTW: '新增',
                              en: 'Add',
                            ),
                    ),
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
      return Center(
        child: Text(
          _emojiStoreText(
            context,
            zhCN: '还没有添加表情包，请到商店添加',
            zhTW: '還沒有新增表情包，請到商店新增',
            en: 'No sticker packs added yet. Open the store to add one.',
          ),
        ),
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
              child: _stickerAssetPreview(pack.previewFile),
            ),
            title: Text(
              pack.localizedName(AppLocalizations.of(context).language),
            ),
            subtitle: Text(
              _emojiStoreText(
                context,
                zhCN: '长按右侧拖动可排序',
                zhTW: '長按右側拖動可排序',
                en: 'Long press and drag on the right to reorder',
              ),
            ),
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
                label: Text(
                  _emojiStoreText(
                    context,
                    zhCN: '从相册制作',
                    zhTW: '從相簿製作',
                    en: 'Create from Album',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _customEditMode = !_customEditMode;
                    _selectedCustomIds.clear();
                  });
                },
                child: Text(
                  _customEditMode
                      ? _emojiStoreText(
                          context,
                          zhCN: '完成',
                          zhTW: '完成',
                          en: 'Done',
                        )
                      : _emojiStoreText(
                          context,
                          zhCN: '整理',
                          zhTW: '整理',
                          en: 'Organize',
                        ),
                ),
              ),
              const Spacer(),
              if (_customEditMode)
                TextButton.icon(
                  onPressed: hasSelection ? _deleteSelectedCustom : null,
                  icon: const Icon(Icons.delete_outline),
                  label: Text(
                    _emojiStoreText(
                      context,
                      zhCN: '删除选中',
                      zhTW: '刪除選取',
                      en: 'Delete Selected',
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _customEmojis.isEmpty
              ? Center(
                  child: Text(
                    _emojiStoreText(
                      context,
                      zhCN: '暂无自定义表情',
                      zhTW: '暫無自訂表情',
                      en: 'No custom emoji yet',
                    ),
                  ),
                )
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
                          child: StickerImage(
                            source: item.displayPath ?? item.path,
                            width: 42,
                            height: 42,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __) {
                              return Container(
                                width: 42,
                                height: 42,
                                color: isDark ? Colors.white10 : Colors.black12,
                                alignment: Alignment.center,
                                child: const Icon(Icons.broken_image_outlined),
                              );
                            },
                          ),
                        ),
                        title: Text(
                          _emojiStoreText(
                            context,
                            zhCN: '自定义表情 ${index + 1}',
                            zhTW: '自訂表情 ${index + 1}',
                            en: 'Custom Emoji ${index + 1}',
                          ),
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          _emojiStoreText(
                            context,
                            zhCN: '长按右侧拖动排序',
                            zhTW: '長按右側拖動排序',
                            en: 'Long press and drag on the right to reorder',
                          ),
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
