import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../core/services/api/api_client.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../shared/widgets/top_gradient_backdrop.dart';
import '../../home/pages/home_desktop_page.dart';

/// 主色 —— 与"我的"页 / 底部导航保持统一
const Color _kPrimary = Color(0xFFFF6B6B);
const Color _kBg = Color(0xFFF7F8FA);

/// 顶部渐变节奏（与"我的" / "联系人" 页保持一致的视觉节奏）：
///   · header 视觉高度 = 10 (top pad) + 44 (content) + 6 (bottom pad) = 60
///   · 内容缓冲 12dp
///   · 渐变尾巴高度 = 80 —— 淡出到 Hero 卡背景下面，形成"渐变自然穿过卡片上沿"
const double _kDiscoverHeaderContentHeight = 60;
const double _kDiscoverGradientBufferHeight = 12;
const double _kDiscoverGradientFadeTail = 80;

/// 广场 hero 渐变色（深蓝 → 天蓝，与主色 #009CFF 对齐）
const Color _kHeroStart = Color(0xFF0070FF);
const Color _kHeroEnd = Color(0xFF00B4FF);

/// 入口瓦片相关的浅色系
const Color _kTileBg = Colors.white;
const Color _kTileBorder = Color(0xFFEDEFF2);
const Color _kTileTitle = Color(0xFF111827);
const Color _kTileUrl = Color(0xFF9CA3AF);

final discoverBannerProvider =
    FutureProvider.autoDispose<String?>((ref) async {
  final settingsAsync = ref.watch(systemSettingsProvider);
  return settingsAsync.valueOrNull?.discoverTopImageUrl;
});

class DiscoverEntry {
  final String id;
  final String title;
  final String url;
  final String? iconUrl;
  final String openMode;
  final Color accentColor;

  const DiscoverEntry({
    required this.id,
    required this.title,
    required this.url,
    this.iconUrl,
    this.openMode = 'webview',
    required this.accentColor,
  });

  factory DiscoverEntry.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString() ?? '';
    final title = (json['title'] ?? '').toString().trim();
    final rawIconUrl = (json['icon_url'] ?? '').toString().trim();

    return DiscoverEntry(
      id: rawId.isNotEmpty ? rawId : title,
      title: title.isNotEmpty ? title : '发现入口',
      url: (json['url'] ?? '').toString().trim(),
      iconUrl: rawIconUrl.isEmpty ? null : ApiConfig.getMediaUrl(rawIconUrl),
      openMode: (json['open_mode'] ?? 'webview').toString(),
      accentColor: _accentColors[
          (rawId.isNotEmpty ? rawId.hashCode : title.hashCode).abs() %
              _accentColors.length],
    );
  }
}

/// 每个入口从这里挑一个色调（用于 2 列彩色瓦片网格的渐变背景）
const _accentColors = <Color>[
  Color(0xFFFF6B6B), // sky
  Color(0xFF34C759), // green
  Color(0xFFFF9500), // orange
  Color(0xFF7C3AED), // purple
  Color(0xFFFF3B30), // red
  Color(0xFF00B4A6), // teal
  Color(0xFFFF6FA9), // pink
];

Future<void> refreshDiscoverEntries(WidgetRef ref) async {
  try {
    ref.invalidate(systemSettingsProvider);
    ref.invalidate(discoverEntriesProvider);
    await ref.refresh(systemSettingsProvider.future);
    await ref.refresh(discoverEntriesProvider.future);
  } catch (_) {}
}

final discoverEntriesProvider =
    FutureProvider<List<DiscoverEntry>>((ref) async {
  final api = ref.watch(apiClientProvider);
  try {
    final response = await api.get<List<dynamic>>(
      '/app/discovery',
      fromJson: (data) => (data as List<dynamic>? ?? const []),
    );

    if (response.isSuccess && response.data != null) {
      return response.data!
          .whereType<Map<String, dynamic>>()
          .map(DiscoverEntry.fromJson)
          .where((entry) => entry.url.isNotEmpty)
          .toList();
    }
  } catch (_) {}
  return [];
});

/// 发现页 —— 颠覆式重设计版：
///
/// 三层 Stack 布局，与"我的" / "联系人"页保持一致：
///   · 底层：SingleChildScrollView，顶部预留 `gradientOpaqueHeight`
///   · 中层：主色渐变，被 IgnorePointer 包住，不拦截手势
///   · 顶层：SafeArea + 交互式左对齐白字标题"发现"
///
/// 主体内容（自上而下）：
///   1. **顶部一行 = 广场 Hero + 公告图（左右并排）**：有公告图时，一行两半，
///      左侧广场 Hero（蓝色渐变 + "广场" + 副标题 + 箭头），右侧后台下发的
///      公告图纯图卡；没有公告图时广场 Hero 占满整行（16:9 aspect）。
///   2. **自定义入口 2 列瓦片网格**：白底 · 轻边框 · 左上 accent 色浅底图标芯片,
///      右上圆形"复制"芯片，底部标题 + URL + 复制小图标 —— 把"点击=复制链接"
///      的意图直接表达在瓦片上。
class DiscoverPage extends ConsumerStatefulWidget {
  final bool isDesktopSidebar;

  const DiscoverPage({
    super.key,
    this.isDesktopSidebar = false,
  });

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  String _refreshKey = DateTime.now().microsecondsSinceEpoch.toString();
  bool _hasRefreshedInThisWindow = false;

  Future<void> _triggerPhysicalNetworkFetch() async {
    if (!mounted) return;
    try {
      ref.invalidate(systemSettingsProvider);
      ref.invalidate(discoverEntriesProvider);
      await ref.refresh(systemSettingsProvider.future);
      await ref.refresh(discoverEntriesProvider.future);
      if (mounted) {
        setState(() {
          _refreshKey = DateTime.now().microsecondsSinceEpoch.toString();
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final entries = ref.watch(discoverEntriesProvider);
    final bannerAsync = ref.watch(discoverBannerProvider);

    final double topPad = MediaQuery.of(context).padding.top;
    final double gradientOpaqueHeight = topPad +
        _kDiscoverHeaderContentHeight +
        _kDiscoverGradientBufferHeight;

    return VisibilityDetector(
      key: const Key('discover_page_visibility_key'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction == 1.0) {
          if (!_hasRefreshedInThisWindow) {
            _hasRefreshedInThisWindow = true;
            _triggerPhysicalNetworkFetch();
          }
        } else if (info.visibleFraction == 0.0) {
          _hasRefreshedInThisWindow = false;
        }
      },
      child: Scaffold(
        backgroundColor: _kBg,
        // 3 层 Stack，与"我的" / "聊天"页视觉节奏一致
        body: Stack(
          children: [
            // ============ 底层：滚动内容 ============
            Positioned.fill(
              child: RefreshIndicator(
                color: _kPrimary,
                onRefresh: _triggerPhysicalNetworkFetch,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding:
                      EdgeInsets.only(top: gradientOpaqueHeight, bottom: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTopRow(bannerAsync),
                      const SizedBox(height: 12),
                      _buildEntriesGrid(entries),
                    ],
                  ),
                ),
              ),
            ),

            // ============ 中层：纯装饰渐变（IgnorePointer） ============
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: topPad +
                  _kDiscoverHeaderContentHeight +
                  _kDiscoverGradientBufferHeight +
                  _kDiscoverGradientFadeTail,
              child: const IgnorePointer(
                child: TopGradientBackdrop(),
              ),
            ),

            // ============ 顶层：左对齐白字标题 ============
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle.light,
                child: SafeArea(
                  bottom: false,
                  child: _buildTitleBar(l10n),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 左对齐白字标题栏 —— 视觉高度 60（10 + 44 + 6）
  Widget _buildTitleBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: SizedBox(
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l10n.get('discover_title'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 顶部一行：广场 Hero + 公告图 左右并排
  //   · 有公告图 → SizedBox(height: 170) + 两个 Expanded 各占一半
  //   · 无公告图 → AspectRatio 16:9，Hero 占满整行
  // ---------------------------------------------------------------------------

  Widget _buildTopRow(AsyncValue<String?> bannerAsync) {
    final imageUrl = bannerAsync.valueOrNull;
    final hasAnnouncement = imageUrl != null && imageUrl.isNotEmpty;

    if (!hasAnnouncement) {
      // 没有公告图 —— Hero 卡完整宽度
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: _HeroSquareCard(
            compact: false,
            onTap: _openSquare,
          ),
        ),
      );
    }

    final cleanUrl =
        '$imageUrl${imageUrl.contains('?') ? '&' : '?'}_t=$_refreshKey';

    // 左右并排 —— 固定 170 高度，两个 Expanded 各占一半
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: SizedBox(
        height: 170,
        child: Row(
          children: [
            Expanded(
              child: _HeroSquareCard(
                compact: true,
                onTap: _openSquare,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _AnnouncementCard(imageUrl: cleanUrl),
            ),
          ],
        ),
      ),
    );
  }

  void _openSquare() {
    HapticFeedback.selectionClick();
    if (widget.isDesktopSidebar) {
      ref.read(desktopNavIndexProvider.notifier).state = kDesktopNavMoments;
      return;
    }
    context.push('/discover/square');
  }

  // ---------------------------------------------------------------------------
  // 自定义入口 —— 2 列清爽白色瓦片网格（白底 · 轻边框 · accent 色浅底图标）
  // ---------------------------------------------------------------------------

  Widget _buildEntriesGrid(AsyncValue<List<DiscoverEntry>> entries) {
    return entries.when(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              // 瓦片内容自上而下：图标 42 + spacer + 标题 + URL，
              // 用 1.25 让 URL 有足够空间且整体不显得过高。
              childAspectRatio: 1.25,
            ),
            itemBuilder: (context, index) {
              final entry = items[index];
              return _EntryTile(
                entry: entry,
                onTap: () => _copyEntry(entry),
              );
            },
          ),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  void _copyEntry(DiscoverEntry entry) {
    HapticFeedback.selectionClick();
    // 用户要求：只复制网址，不带"名称:"和"网址:"前缀，方便直接粘到浏览器。
    Clipboard.setData(ClipboardData(text: entry.url));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              color: Colors.greenAccent,
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              '已复制 ${entry.title} 的网址',
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        width: 280,
        backgroundColor: Colors.black.withOpacity(0.85),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}

/// 单格入口瓦片 —— 简洁清爽风格 + 显式复制意图。
///
/// 结构：
///   · 白色背景 + 0.8px 轻边框（#EDEFF2）
///   · 顶行：左侧 42×42 accent 色浅底图标芯片；右侧 28×28 accent 色浅底
///     "复制"圆芯片（含 `content_copy` 图标）—— 一眼就能看出这个卡片
///     "点一下会把链接复制到剪贴板"
///   · 底部：深色标题（1 行）+ 灰色 URL 副文本（1 行 · 自动去 http/https 前缀）
class _EntryTile extends StatelessWidget {
  final DiscoverEntry entry;
  final VoidCallback onTap;

  const _EntryTile({
    required this.entry,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final base = entry.accentColor;
    return Material(
      color: _kTileBg,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        splashColor: base.withOpacity(0.08),
        highlightColor: base.withOpacity(0.04),
        child: Ink(
          decoration: BoxDecoration(
            color: _kTileBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kTileBorder, width: 0.8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TileIconChip(iconUrl: entry.iconUrl, tint: base),
                    const Spacer(),
                    _CopyAffordanceChip(tint: base),
                  ],
                ),
                const Spacer(),
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: _kTileTitle,
                    letterSpacing: 0.2,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _prettifyUrl(entry.url),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: _kTileUrl,
                    fontWeight: FontWeight.w500,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 展示用 URL —— 去掉协议头 / 末尾斜杠，让链接更清爽好读
  String _prettifyUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('https://')) {
      u = u.substring(8);
    } else if (u.startsWith('http://')) {
      u = u.substring(7);
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }
}

/// 瓦片右上角的复制圆芯片 —— accent 色 10% 浅底 + 细描边 + `content_copy` 图标。
///
/// 这是让用户"一眼看出这是可复制的链接卡片"的关键视觉锚点。
class _CopyAffordanceChip extends StatelessWidget {
  final Color tint;

  const _CopyAffordanceChip({required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: tint.withOpacity(0.10),
        border: Border.all(color: tint.withOpacity(0.18), width: 0.6),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.content_copy_rounded,
        color: tint,
        size: 13,
      ),
    );
  }
}

/// 瓦片左上角的图标芯片 —— accent 色 12% 浅底 + accent 色图标。
///
/// 有自定义 iconUrl 时显示网络图标（白底看着不脏）；失败或没有时显示 explore
/// 图标，颜色跟随条目的 accentColor。
class _TileIconChip extends StatelessWidget {
  final String? iconUrl;
  final Color tint;

  const _TileIconChip({
    required this.iconUrl,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final hasIcon = iconUrl != null && iconUrl!.isNotEmpty;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        // 有自定义 iconUrl 时用白底（让彩色 logo 干净展示），否则用 accent 浅底
        color: hasIcon ? Colors.white : tint.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: hasIcon
          ? Image.network(
              iconUrl!,
              width: 42,
              height: 42,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Icon(
                Icons.explore_rounded,
                color: tint,
                size: 22,
              ),
            )
          : Icon(
              Icons.explore_rounded,
              color: tint,
              size: 22,
            ),
    );
  }
}

/// 广场 Hero 卡片 —— 蓝色斜向渐变 + 装饰圆 + 前景 "广场" 文案。
///
/// [compact] 用于紧凑模式（在 Row 里跟公告图并排时），会调低字号 / 装饰尺寸,
/// 保证半宽卡片也能塞下所有内容。
class _HeroSquareCard extends StatelessWidget {
  final bool compact;
  final VoidCallback onTap;

  const _HeroSquareCard({
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final double titleSize = compact ? 24 : 28;
    final double subtitleSize = compact ? 11.5 : 13;
    final double padding = compact ? 16 : 20;
    final double arrowChip = compact ? 28 : 32;
    final double arrowIcon = compact ? 15 : 18;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white.withOpacity(0.16),
        highlightColor: Colors.white.withOpacity(0.08),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_kHeroEnd, _kHeroStart],
                ),
              ),
            ),
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: compact ? 110 : 140,
                height: compact ? 110 : 140,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              right: 24,
              bottom: -40,
              child: Container(
                width: compact ? 90 : 120,
                height: compact ? 90 : 120,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.07),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(padding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(
                        Icons.public_rounded,
                        color: Colors.white.withOpacity(0.9),
                        size: compact ? 20 : 22,
                      ),
                      Container(
                        width: arrowChip,
                        height: arrowChip,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.25),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: arrowIcon,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    '广场',
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.6,
                      height: 1.05,
                    ),
                  ),
                  SizedBox(height: compact ? 4 : 6),
                  Text(
                    '看看大家都在聊什么',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: subtitleSize,
                      color: Colors.white.withOpacity(0.88),
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 公告图片卡片 —— 纯图无覆盖文字，圆角剪裁，加载 / 出错都有兜底。
class _AnnouncementCard extends StatelessWidget {
  final String imageUrl;

  const _AnnouncementCard({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Image.network(
        imageUrl,
        key: ValueKey(imageUrl),
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: const Color(0xFFF1F2F4),
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (_, __, ___) => Container(
          color: const Color(0xFFF1F2F4),
          alignment: Alignment.center,
          child: const Icon(
            Icons.image_outlined,
            color: Color(0xFFC1C7CD),
            size: 32,
          ),
        ),
      ),
    );
  }
}
