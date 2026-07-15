import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/constants/emoji_animations.dart';
import '../../../shared/widgets/settings_ui.dart';
import '../../chat/pages/emoji_store_page.dart';

/// 贴纸和表情页面 v3
///
/// 复用全局 [SettingsScaffold]（蓝色渐变 + 左对齐白字标题），把原来的两段
/// [TabController]+[TabBarView] 拆成本页内部的枚举切换，以便所有内容都能
/// 在 [SettingsScaffold] 的 `ListView` 里一起滚动。
class StickersPage extends ConsumerStatefulWidget {
  final bool isDesktopPanel;

  const StickersPage({
    super.key,
    this.isDesktopPanel = false,
  });

  @override
  ConsumerState<StickersPage> createState() => _StickersPageState();
}

enum _StickerTab { installed, discover }

class _StickersPageState extends ConsumerState<StickersPage> {
  _StickerTab _tab = _StickerTab.installed;

  // 已安装的贴纸包 ID
  Set<String> _installedPackIds = {};

  // 最近使用的表情
  List<String> _recentEmojis = [];

  // 设置项
  bool _showAnimationOnSend = true;
  bool _autoPlayStickers = true;
  bool _emojiSuggestions = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final installed = prefs.getStringList('installed_sticker_packs') ?? [];
      _installedPackIds = installed.toSet();

      // 无安装记录时，默认全部安装内置包
      if (_installedPackIds.isEmpty) {
        _installedPackIds = BuiltInStickerPacks.all.map((p) => p.id).toSet();
        prefs.setStringList(
            'installed_sticker_packs', _installedPackIds.toList());
      }

      _recentEmojis = prefs.getStringList('recent_emojis') ??
          [
            '👋', '😂', '❤️', '😎', '🤔', '👍',
            '🔥', '🎉', '😍', '✨', '👏', '🙏',
          ];

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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations(ref.watch(languageProvider));
    return SettingsScaffold(
      title: l10n.stickersEmoji,
      isDesktopPanel: widget.isDesktopPanel,
      children: [
        _buildSegmentedControl(l10n),
        const SizedBox(height: 6),
        if (_tab == _StickerTab.installed)
          ..._buildInstalledChildren(l10n)
        else
          ..._buildDiscoverChildren(l10n),
      ],
    );
  }

  // ============================================================================
  // 顶部分段控件 —— 已安装 / 发现更多
  // ============================================================================
  Widget _buildSegmentedControl(AppLocalizations l10n) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          _SegBtn(
            label: l10n.installed,
            selected: _tab == _StickerTab.installed,
            isDark: isDark,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _tab = _StickerTab.installed);
            },
          ),
          const SizedBox(width: 24),
          _SegBtn(
            label: l10n.discoverMore,
            selected: _tab == _StickerTab.discover,
            isDark: isDark,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _tab = _StickerTab.discover);
            },
          ),
        ],
      ),
    );
  }

  // ============================================================================
  // 已安装 Tab
  // ============================================================================
  List<Widget> _buildInstalledChildren(AppLocalizations l10n) {
    final installedPacks = BuiltInStickerPacks.all
        .where((p) => _installedPackIds.contains(p.id))
        .toList();

    return [
      // 最近使用（Lottie 表情网格）
      SettingsSection(l10n.recentlyUsed),
      SettingsLooseCard(
        padding: const EdgeInsets.all(12),
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
                        child:
                            Text(e, style: const TextStyle(fontSize: 28))),
              ),
            );
          }).toList(),
        ),
      ),

      // 已安装的贴纸包
      SettingsSection('已安装 (${installedPacks.length})'),
      if (installedPacks.isEmpty)
        SettingsLooseCard(
          padding: const EdgeInsets.symmetric(vertical: 28),
          child: _EmptyPacks(
            onGoDiscover: () =>
                setState(() => _tab = _StickerTab.discover),
          ),
        )
      else
        ...installedPacks.map(
          (pack) => SettingsCustomIsland(
            padding: const EdgeInsets.symmetric(vertical: 10),
            onTap: () => _showPackDetail(pack),
            child: _StickerPackRow(
              pack: pack,
              isInstalled: true,
              onAction: () => _showPackOptions(pack),
            ),
          ),
        ),

      // 设置
      SettingsSection('设置'),
      SettingsSwitchIsland(
        icon: Icons.emoji_events_outlined,
        iconColor: const Color(0xFFFF9500),
        label: '发送贴纸时显示动画',
        value: _showAnimationOnSend,
        onChanged: (v) {
          setState(() => _showAnimationOnSend = v);
          _saveSettings();
        },
      ),
      SettingsSwitchIsland(
        icon: Icons.play_circle_outline_rounded,
        iconColor: const Color(0xFF34C759),
        label: '自动播放动态贴纸',
        value: _autoPlayStickers,
        onChanged: (v) {
          setState(() => _autoPlayStickers = v);
          _saveSettings();
        },
      ),
      SettingsSwitchIsland(
        icon: Icons.tips_and_updates_outlined,
        iconColor: const Color(0xFF5AC8FA),
        label: '表情包建议',
        value: _emojiSuggestions,
        onChanged: (v) {
          setState(() => _emojiSuggestions = v);
          _saveSettings();
        },
      ),
    ];
  }

  // ============================================================================
  // 发现更多 Tab
  // ============================================================================
  List<Widget> _buildDiscoverChildren(AppLocalizations l10n) {
    final availablePacks = BuiltInStickerPacks.all
        .where((p) => !_installedPackIds.contains(p.id))
        .toList();

    return [
      if (availablePacks.isNotEmpty) ...[
        SettingsSection(l10n.available),
        ...availablePacks.map(
          (pack) => SettingsCustomIsland(
            padding: const EdgeInsets.symmetric(vertical: 10),
            onTap: () => _showPackDetail(pack),
            child: _StickerPackRow(
              pack: pack,
              isInstalled: false,
              onAction: () => _installPack(pack),
            ),
          ),
        ),
      ] else
        SettingsLooseCard(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: 56,
                color: AppColors.primary.withOpacity(0.6),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.allPacksInstalled,
                style: TextStyle(
                  fontSize: 14.5,
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white60
                      : const Color(0xFF6B7280),
                ),
              ),
            ],
          ),
        ),

      SettingsSection('创建'),
      SettingsChoiceIsland(
        icon: Icons.add_rounded,
        iconColor: AppColors.primary,
        label: '新建贴纸包',
        subtitle: '使用照片创建专属贴纸',
        onTap: _openCreateStickerPack,
      ),
    ];
  }

  // ============================================================================
  // Actions & modals（沿用旧逻辑）
  // ============================================================================
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
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
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
                              color:
                                  isDark ? Colors.white54 : Colors.black54,
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
              Expanded(
                child: GridView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
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
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(12)),
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
                leading: Icon(Icons.delete_outline_rounded,
                    color: AppColors.error),
                title:
                    Text('卸载', style: TextStyle(color: AppColors.error)),
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

// ============================================================================
// 顶部分段按钮
// ============================================================================
/// 极简文字 tab —— 选中态下方用主色 2dp 短线暗示，无填充无卡片
class _SegBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  const _SegBtn({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = selected
        ? AppColors.primary
        : (isDark ? Colors.white70 : const Color(0xFF6B7280));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 6),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: 2,
                width: selected ? 24 : 0,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 单条贴纸包行（在 SettingsCustomIsland 内使用）
// ============================================================================
class _StickerPackRow extends StatelessWidget {
  final StickerPack pack;
  final bool isInstalled;
  final VoidCallback onAction;

  const _StickerPackRow({
    required this.pack,
    required this.isInstalled,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        SizedBox(
          width: 46,
          height: 46,
          child: Lottie.asset(pack.previewPath, repeat: true),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      pack.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white
                            : const Color(0xFF111827),
                      ),
                    ),
                  ),
                  if (pack.isBuiltIn) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '内置',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 3),
              Text(
                '${pack.count} 个贴纸',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white54 : const Color(0xFF9CA3AF),
                ),
              ),
            ],
          ),
        ),
        if (isInstalled)
          IconButton(
            icon: Icon(
              Icons.more_horiz,
              color: isDark ? Colors.white54 : const Color(0xFF9CA3AF),
            ),
            onPressed: onAction,
          )
        else
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999)),
            ),
            child: const Text(
              '安装',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
      ],
    );
  }
}

// ============================================================================
// 空态：还没安装任何包
// ============================================================================
class _EmptyPacks extends StatelessWidget {
  final VoidCallback onGoDiscover;
  const _EmptyPacks({required this.onGoDiscover});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        Icon(
          Icons.emoji_emotions_outlined,
          size: 56,
          color: isDark ? Colors.white24 : const Color(0xFFDDE1E7),
        ),
        const SizedBox(height: 12),
        Text(
          '还没有安装贴纸包',
          style: TextStyle(
            fontSize: 14.5,
            color: isDark ? Colors.white60 : const Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: onGoDiscover,
          child: Text(
            '去发现更多',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
