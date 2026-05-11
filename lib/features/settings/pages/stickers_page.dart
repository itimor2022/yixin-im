import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/constants/emoji_animations.dart';
import '../../chat/pages/emoji_store_page.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      // 加载已安装的贴纸包
      final installed = prefs.getStringList('installed_sticker_packs') ?? [];
      _installedPackIds = installed.toSet();

      // 如果没有安装过任何包，默认安装内置包
      if (_installedPackIds.isEmpty) {
        _installedPackIds = BuiltInStickerPacks.all.map((p) => p.id).toSet();
        prefs.setStringList(
            'installed_sticker_packs', _installedPackIds.toList());
      }

      // 加载最近使用的表情(使用有动画的)
      _recentEmojis = prefs.getStringList('recent_emojis') ??
          [
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
    await prefs.setStringList(
        'installed_sticker_packs', _installedPackIds.toList());
    await prefs.setStringList('recent_emojis', _recentEmojis);
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
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        surfaceTintColor: Colors.transparent,
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
              unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
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
                      ? Lottie.asset(animated.path, repeat: true)
                      : Center(
                          child: Text(e, style: const TextStyle(fontSize: 28))),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 24),

        // 已安装的贴纸包 - 动态头像
        _SectionTitle(title: '已安装 (${installedPacks.length})', isDark: isDark),
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
                  '还没有安装贴纸包',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _tabController.animateTo(1),
                  child:
                      Text('去发现更多', style: TextStyle(color: AppColors.primary)),
                ),
              ],
            ),
          ),

        const SizedBox(height: 24),

        // 设置
        _SectionTitle(title: '设置', isDark: isDark),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _SettingSwitch(
                title: '发送贴纸时显示动画',
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
                title: '自动播放动态贴纸',
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
                title: '表情包建议',
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
    final availablePacks = BuiltInStickerPacks.all
        .where((p) => !_installedPackIds.contains(p.id))
        .toList();

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
                isInstalled: false,
                onTap: () => _showPackDetail(pack),
                onAction: () => _installPack(pack),
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
                  color: AppColors.primary.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.allPacksInstalled,
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? Colors.white54 : Colors.black54,
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
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.add_rounded,
                        color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '新建贴纸包',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '使用照片创建专属贴纸',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white38 : Colors.black38,
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                      child: Lottie.asset(pack.previewPath, repeat: true),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pack.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                          Text(
                            '${pack.count} 个贴纸',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white54 : Colors.black54,
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
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('安装',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
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
                      child: Lottie.asset(
                        EmojiAnimations.getPath(file),
                        repeat: true,
                      ),
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
      backgroundColor: Colors.transparent,
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
                child: Lottie.asset(pack.previewPath, repeat: true),
              ),
              const SizedBox(height: 8),
              Text(
                pack.name,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('预览'),
                onTap: () {
                  Navigator.pop(context);
                  _showPackDetail(pack);
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined),
                title: const Text('分享'),
                onTap: () => Navigator.pop(context),
              ),
              ListTile(
                leading:
                    Icon(Icons.delete_outline_rounded, color: AppColors.error),
                title: Text('卸载', style: TextStyle(color: AppColors.error)),
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
        color: isDark ? Colors.white54 : Colors.black54,
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
              child: Lottie.asset(pack.previewPath, repeat: true),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        pack.name,
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
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '内置',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${pack.count} 个贴纸',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
            if (isInstalled)
              IconButton(
                icon: Icon(
                  Icons.more_horiz,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                onPressed: onAction,
              )
            else
              TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text(
                  '安装',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500),
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
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
