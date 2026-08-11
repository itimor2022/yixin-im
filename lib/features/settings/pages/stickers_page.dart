// 文件用途：实现 StickersPage 页面及其交互流程，属于应用设置。
// 核心逻辑：维护 StickersPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import '../../../shared/widgets/web_safe_lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/constants/emoji_animations.dart';
import '../../../shared/widgets/sticker_image.dart';
import '../../chat/pages/emoji_store_page.dart';
import '../../chat/services/emoji_store_service.dart';
import '../../../shared/widgets/themed_app_bar.dart';

String _stickersText(
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
  String path, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
}) {
  return StickerImage(
    source: path,
    width: width,
    height: height,
    fit: fit,
    errorBuilder: (_, __) => const SizedBox.shrink(),
  );
}

// 关键声明：stickers page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// 贴纸和表情页面
class StickersPage extends ConsumerStatefulWidget {
  final bool isDesktopPanel;

  const StickersPage({
    super.key,
    this.isDesktopPanel = false,
  });

  @override
  ConsumerState<StickersPage> createState() => _StickersPageState();
}

class _StickersPageState extends ConsumerState<StickersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 已安装的贴纸包ID
  Set<String> _installedPackIds = {};

  // 最近使用的表情
  List<String> _recentEmojis = [];

  // 设置
  bool _showAnimationOnSend = true;
  bool _autoPlayStickers = true;
  bool _emojiSuggestions = true;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final emojiData = await EmojiStoreService.loadAll();
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      // 加载已安装的贴纸包
      _installedPackIds = emojiData.installedPackIds.toSet();

      // 默认安装正式内置包；老账号升级后也能立即看到新包。
      // 加载最近使用的表情(使用有动画的)
      _recentEmojis = emojiData.recentEmojis.isNotEmpty
          ? [...emojiData.recentEmojis]
          : [
              '👋',
              '😂',
              '❤️',
              '😎',
              '🤔',
              '👍',
              '🔥',
              '🎉',
              '😍',
              '✨',
              '👏',
              '🙏'
            ];

      // 加载设置
      _showAnimationOnSend = prefs.getBool('show_animation_on_send') ?? true;
      _autoPlayStickers = prefs.getBool('auto_play_stickers') ?? true;
      _emojiSuggestions = prefs.getBool('emoji_suggestions') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await EmojiStoreService.setInstalledPackIds(_installedPackIds.toList());
    await EmojiStoreService.setRecentEmojis(_recentEmojis);
    await prefs.setBool('show_animation_on_send', _showAnimationOnSend);
    await prefs.setBool('auto_play_stickers', _autoPlayStickers);
    await prefs.setBool('emoji_suggestions', _emojiSuggestions);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));

    // 桌面端面板模式：只返回内容，不需要 Scaffold 和 AppBar
    if (widget.isDesktopPanel) {
      return _buildBody(isDark, l10n);
    }

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0D1117) : const Color(0xFFF2F2F7),
      appBar: ThemedAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.stickersEmoji,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(isDark, l10n),
    );
  }

  Widget _buildBody(bool isDark, AppLocalizations l10n) {
    return Column(
      children: [
        // 分段控制器
        Container(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withOpacity(0.08)
                  : const Color(0xFFEFEFF4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: isDark ? const Color(0xFF3A3A3C) : Colors.white,
                borderRadius: BorderRadius.circular(7),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 1,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              indicatorPadding: const EdgeInsets.all(2),
              dividerColor: Colors.transparent,
              labelColor: isDark ? Colors.white : Colors.black,
              unselectedLabelColor: AppColors.textSecondaryFor(context),
              labelStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              unselectedLabelStyle:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              tabs: [
                Tab(text: l10n.installed),
                Tab(text: l10n.discoverMore),
              ],
            ),
          ),
        ),

        // 内容
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildInstalledTab(isDark, l10n),
              _buildDiscoverTab(isDark, l10n),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInstalledTab(bool isDark, AppLocalizations l10n) {
    final language = AppLocalizations.of(context).language;
    final installedPacks = BuiltInStickerPacks.all
        .where((p) => _installedPackIds.contains(p.id))
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 最近使用 - 动态表情
        _SectionTitle(title: l10n.recentlyUsed, isDark: isDark),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: _recentEmojis.map((e) {
              final animated = EmojiAnimations.findByEmoji(e);
              return GestureDetector(
                onTap: () => _onEmojiTap(e),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: animated != null
                      ? WebSafeLottie.asset(animated.path, repeat: true)
                      : Center(
                          child: Text(e, style: const TextStyle(fontSize: 28))),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 24),

        // 已安装的贴纸包 - 动态头像
        _SectionTitle(
          title: _stickersText(
            context,
            zhCN: '已安装 (${installedPacks.length})',
            zhTW: '已安裝 (${installedPacks.length})',
            en: 'Installed (${installedPacks.length})',
          ),
          isDark: isDark,
        ),
        const SizedBox(height: 12),
        ...installedPacks.map((pack) => _AnimatedStickerPackCard(
              pack: pack,
              isDark: isDark,
              isInstalled: true,
              onTap: () => _showPackDetail(pack),
              onAction: () => _showPackOptions(pack),
            )),

        if (installedPacks.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            child: Column(
              children: [
                Icon(
                  Icons.emoji_emotions_outlined,
                  size: 64,
                  color: isDark ? Colors.white24 : Colors.black12,
                ),
                const SizedBox(height: 16),
                Text(
                  _stickersText(
                    context,
                    zhCN: '还没有安装贴纸包',
                    zhTW: '還沒有安裝貼紙包',
                    en: 'No sticker packs installed yet',
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textTertiaryFor(context),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _tabController.animateTo(1),
                  child: Text(
                    _stickersText(
                      context,
                      zhCN: '去发现更多',
                      zhTW: '去發現更多',
                      en: 'Discover More',
                    ),
                    style: TextStyle(color: AppColors.linkFor(context)),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 24),

        // 设置
        _SectionTitle(
          title: _stickersText(
            context,
            zhCN: '设置',
            zhTW: '設定',
            en: 'Settings',
          ),
          isDark: isDark,
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _SettingSwitch(
                title: _stickersText(
                  context,
                  zhCN: '发送贴纸时显示动画',
                  zhTW: '傳送貼紙時顯示動畫',
                  en: 'Play animation when sending stickers',
                ),
                value: _showAnimationOnSend,
                isDark: isDark,
                onChanged: (v) {
                  setState(() => _showAnimationOnSend = v);
                  _saveSettings();
                },
              ),
              Divider(
                  height: 1,
                  indent: 16,
                  color:
                      isDark ? Colors.white10 : Colors.black.withOpacity(0.06)),
              _SettingSwitch(
                title: _stickersText(
                  context,
                  zhCN: '自动播放动态贴纸',
                  zhTW: '自動播放動態貼紙',
                  en: 'Auto-play animated stickers',
                ),
                value: _autoPlayStickers,
                isDark: isDark,
                onChanged: (v) {
                  setState(() => _autoPlayStickers = v);
                  _saveSettings();
                },
              ),
              Divider(
                  height: 1,
                  indent: 16,
                  color:
                      isDark ? Colors.white10 : Colors.black.withOpacity(0.06)),
              _SettingSwitch(
                title: _stickersText(
                  context,
                  zhCN: '表情包建议',
                  zhTW: '表情包建議',
                  en: 'Emoji suggestions',
                ),
                value: _emojiSuggestions,
                isDark: isDark,
                onChanged: (v) {
                  setState(() => _emojiSuggestions = v);
                  _saveSettings();
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDiscoverTab(bool isDark, AppLocalizations l10n) {
    final availablePacks = BuiltInStickerPacks.all;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 可安装的贴纸包
        if (availablePacks.isNotEmpty) ...[
          _SectionTitle(title: l10n.available, isDark: isDark),
          const SizedBox(height: 12),
          ...availablePacks.map((pack) => _AnimatedStickerPackCard(
                pack: pack,
                isDark: isDark,
                isInstalled: _installedPackIds.contains(pack.id),
                onTap: () => _showPackDetail(pack),
                onAction: _installedPackIds.contains(pack.id)
                    ? () => _showPackOptions(pack)
                    : () => _installPack(pack),
              )),
        ],

        // 已全部安装
        if (availablePacks.isEmpty)
          Container(
            padding: const EdgeInsets.all(40),
            child: Column(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 64,
                  color: AppColors.linkFor(context).withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.allPacksInstalled,
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 24),

        // 创建贴纸
        Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _openCreateStickerPack,
            child: Ink(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AppColors.emphasisSoftFor(context),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.add_rounded,
                      color: AppColors.linkFor(context),
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.createStickerPack,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _stickersText(
                            context,
                            zhCN: '使用照片创建专属贴纸',
                            zhTW: '使用照片建立專屬貼圖',
                            en: 'Create a custom sticker pack from photos',
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiaryFor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isDark ? Colors.white24 : Colors.black26,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openCreateStickerPack() async {
    HapticFeedback.selectionClick();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const EmojiStorePage(initialTab: 2),
      ),
    );
  }

  void _onEmojiTap(String emoji) {
    HapticFeedback.selectionClick();
    // 更新最近使用
    setState(() {
      _recentEmojis.remove(emoji);
      _recentEmojis.insert(0, emoji);
      if (_recentEmojis.length > 20) {
        _recentEmojis = _recentEmojis.sublist(0, 20);
      }
    });
    _saveSettings();
  }

  void _showPackDetail(StickerPack pack) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final language = AppLocalizations.of(context).language;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // 拖动条
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 标题 - 动态头像
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: _stickerAssetPreview(pack.previewPath),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pack.localizedName(language),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          Text(
                            _stickersText(
                              context,
                              zhCN: '${pack.count} 个贴纸',
                              zhTW: '${pack.count} 個貼圖',
                              en: '${pack.count} stickers',
                            ),
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondaryFor(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_installedPackIds.contains(pack.id))
                      TextButton(
                        onPressed: () {
                          _installPack(pack);
                          Navigator.pop(context);
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(
                          _stickersText(
                            context,
                            zhCN: '安装',
                            zhTW: '安裝',
                            en: 'Install',
                          ),
                          style: TextStyle(
                            color: AppColors.onPrimaryFor(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // 贴纸网格
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: pack.stickerFiles.length,
                  itemBuilder: (context, index) {
                    final file = pack.stickerFiles[index];
                    return GestureDetector(
                      onTap: () => HapticFeedback.selectionClick(),
                      child:
                          _stickerAssetPreview(EmojiAnimations.getPath(file)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPackOptions(StickerPack pack) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 16),
              SizedBox(
                width: 48,
                height: 48,
                child: _stickerAssetPreview(pack.previewPath),
              ),
              const SizedBox(height: 8),
              Text(
                pack.localizedName(AppLocalizations.of(context).language),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: Text(
                  _stickersText(
                    context,
                    zhCN: '预览',
                    zhTW: '預覽',
                    en: 'Preview',
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showPackDetail(pack);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: Text(
                  _stickersText(
                    context,
                    zhCN: '分享',
                    zhTW: '分享',
                    en: 'Share',
                  ),
                ),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading:
                    Icon(Icons.delete_outline_rounded, color: AppColors.error),
                title: Text(
                  _stickersText(
                    context,
                    zhCN: '卸载',
                    zhTW: '卸載',
                    en: 'Uninstall',
                  ),
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _uninstallPack(pack);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _installPack(StickerPack pack) {
    HapticFeedback.mediumImpact();
    setState(() {
      _installedPackIds.add(pack.id);
    });
    _saveSettings();
  }

  void _uninstallPack(StickerPack pack) {
    HapticFeedback.mediumImpact();
    setState(() {
      _installedPackIds.remove(pack.id);
    });
    _saveSettings();
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final bool isDark;

  const _SectionTitle({required this.title, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondaryFor(context),
      ),
    );
  }
}

/// 动态贴纸包卡片
class _AnimatedStickerPackCard extends StatelessWidget {
  final StickerPack pack;
  final bool isDark;
  final bool isInstalled;
  final VoidCallback onTap;
  final VoidCallback onAction;

  const _AnimatedStickerPackCard({
    required this.pack,
    required this.isDark,
    required this.isInstalled,
    required this.onTap,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            // 动态头像
            SizedBox(
              width: 52,
              height: 52,
              child: _stickerAssetPreview(pack.previewPath),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        pack.localizedName(
                            AppLocalizations.of(context).language),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                      if (pack.isBuiltIn) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.emphasisSoftFor(context),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _stickersText(
                              context,
                              zhCN: '内置',
                              zhTW: '內建',
                              en: 'Built-in',
                            ),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppColors.linkFor(context),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _stickersText(
                      context,
                      zhCN: '${pack.count} 个贴纸',
                      zhTW: '${pack.count} 個貼圖',
                      en: '${pack.count} stickers',
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textTertiaryFor(context),
                    ),
                  ),
                ],
              ),
            ),
            if (isInstalled)
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  backgroundColor:
                      isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  _stickersText(
                    context,
                    zhCN: '已添加',
                    zhTW: '已加入',
                    en: 'Added',
                  ),
                  style: TextStyle(
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
              )
            else
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  _stickersText(
                    context,
                    zhCN: '安装',
                    zhTW: '安裝',
                    en: 'Install',
                  ),
                  style: TextStyle(
                    color: AppColors.onPrimaryFor(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingSwitch extends StatelessWidget {
  final String title;
  final bool value;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const _SettingSwitch({
    required this.title,
    required this.value,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.controlActiveFor(context),
          ),
        ],
      ),
    );
  }
}
