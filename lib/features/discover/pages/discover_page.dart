import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:url_launcher/url_launcher.dart'; // 需要添加这个依赖

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

/// 每个入口从这里挑一个色调（用于图标背景）
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
///   2. **自定义入口 4 列图标网格**：只显示图标+名称，点击直接打开链接
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
  // 自定义入口 —— 4 列图标网格（只显示图标 + 名称）
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
              crossAxisCount: 4, // 改为4列
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              // 图标+名称，使用更接近正方形的比例
              childAspectRatio: 0.9,
            ),
            itemBuilder: (context, index) {
              final entry = items[index];
              return _EntryTile(
                entry: entry,
                onTap: () => _openEntry(entry),
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

  /// 打开发现项链接
  Future<void> _openEntry(DiscoverEntry entry) async {
    HapticFeedback.selectionClick();
    
    final url = entry.url;
    if (url.isEmpty) return;

    try {
      // 如果 openMode 是 webview，使用应用内 WebView
      if (entry.openMode == 'webview') {
        if (widget.isDesktopSidebar) {
          // 桌面端特殊处理
          // TODO: 实现桌面端 WebView 或新窗口打开
          await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        } else {
          // 移动端使用应用内 WebView
          context.push('/webview', extra: {
            'url': url,
            'title': entry.title,
          });
        }
      } else {
        // 外部浏览器打开
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      // 降级处理：尝试外部浏览器
      try {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } catch (_) {
        // 完全失败时显示提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('无法打开链接: $url'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.black.withOpacity(0.85),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    }
  }
}

/// 单格入口瓦片 —— 极简风格：只显示图标 + 名称
///
/// 结构：
///   · 图标（圆形背景 + 图标/网络图片）
///   · 名称（居中，最多1行）
///   · 点击直接打开链接
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
    final hasIcon = entry.iconUrl != null && entry.iconUrl!.isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: base.withOpacity(0.12),
        highlightColor: base.withOpacity(0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 图标 - 圆形背景
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: hasIcon ? Colors.white : base.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: hasIcon ? const Color(0xFFEDEFF2) : Colors.transparent,
                    width: 0.8,
                  ),
                ),
                alignment: Alignment.center,
                clipBehavior: Clip.antiAlias,
                child: hasIcon
                    ? Image.network(
                        entry.iconUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.explore_rounded,
                          color: base,
                          size: 28,
                        ),
                      )
                    : Icon(
                        Icons.explore_rounded,
                        color: base,
                        size: 28,
                      ),
              ),
              const SizedBox(height: 6),
              // 名称
              Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: _kTileTitle,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
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