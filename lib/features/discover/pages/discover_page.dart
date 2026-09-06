// 文件用途：实现 DiscoverEntry 页面及其交互流程，属于发现页。
// 核心逻辑：维护 DiscoverEntry 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:async';

import 'package:universal_io/io.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_preset.dart';
import '../../../core/theme/theme_provider.dart'; // ✅ 添加这一行
import '../../../shared/widgets/fancy_refresh_indicator.dart';
import '../../../shared/widgets/in_app_browser.dart';
import '../../home/pages/home_desktop_page.dart';

String _discoverText({
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 关键声明：discover page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
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

  bool get openExternally => openMode == 'external';

  factory DiscoverEntry.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString() ?? '';
    final title = (json['title'] ?? '').toString().trim();
    final rawIconUrl = (json['icon_url'] ?? '').toString().trim();

    return DiscoverEntry(
      id: rawId.isNotEmpty ? rawId : title,
      title: title.isNotEmpty
          ? title
          : _discoverText(
              zhCN: '发现入口',
              zhTW: '發現入口',
              en: 'Discover Entry',
            ),
      url: (json['url'] ?? '').toString().trim(),
      iconUrl: rawIconUrl.isEmpty ? null : ApiConfig.getMediaUrl(rawIconUrl),
      openMode: (json['open_mode'] ?? 'webview').toString(),
      accentColor: _accentColors[
          (rawId.isNotEmpty ? rawId.hashCode : title.hashCode).abs() %
              _accentColors.length],
    );
  }
}

class DiscoverBanner {
  final String id;
  final String title;
  final String url;
  final String imageUrl;

  const DiscoverBanner({
    required this.id,
    required this.title,
    required this.url,
    required this.imageUrl,
  });

  factory DiscoverBanner.fromJson(Map<String, dynamic> json) {
    final rawId = json['id']?.toString() ?? '';
    final title = (json['title'] ?? '').toString().trim();
    final rawImageUrl = (json['image_url'] ?? '').toString().trim();

    return DiscoverBanner(
      id: rawId.isNotEmpty ? rawId : title,
      title: title.isNotEmpty
          ? title
          : _discoverText(
              zhCN: '发现轮播图',
              zhTW: '發現輪播圖',
              en: 'Discover Banner',
            ),
      url: (json['url'] ?? '').toString().trim(),
      imageUrl: ApiConfig.getMediaUrl(rawImageUrl),
    );
  }
}

const _accentColors = <Color>[
  Color(0xFF5E6DF6),
  Color(0xFF00A6B4),
  Color(0xFF11A66A),
  Color(0xFF3B73F6),
  Color(0xFF9B5DE5),
];

Future<void> refreshDiscoverEntries(WidgetRef ref) async {
  final entriesFuture = ref.refresh(discoverEntriesProvider.future);
  final bannersFuture = ref.refresh(discoverBannersProvider.future);
  await Future.wait([entriesFuture, bannersFuture]);
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

final discoverBannersProvider =
    FutureProvider<List<DiscoverBanner>>((ref) async {
  final api = ref.watch(apiClientProvider);

  try {
    final response = await api.get<List<dynamic>>(
      '/app/discovery/banners',
      fromJson: (data) => (data as List<dynamic>? ?? const []),
    );

    if (response.isSuccess && response.data != null) {
      return response.data!
          .whereType<Map<String, dynamic>>()
          .map(DiscoverBanner.fromJson)
          .where((banner) => banner.imageUrl.isNotEmpty)
          .toList();
    }
  } catch (_) {}

  return [];
});

class DiscoverPage extends ConsumerWidget {
  final bool isDesktopSidebar;

  const DiscoverPage({
    super.key,
    this.isDesktopSidebar = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final entries = ref.watch(discoverEntriesProvider);
    final banners = ref.watch(discoverBannersProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final _pc = AppThemePresets.of(ref.watch(appThemePresetProvider));

    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      body: FancyRefreshIndicator(
        topOffset: MediaQuery.of(context).padding.top + 52,
        onRefresh: () => refreshDiscoverEntries(ref),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 0,
              floating: true,
              pinned: true,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              flexibleSpace: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: isDark
                        ? [
                            _pc.primaryA.withOpacity(0.9),
                            _pc.primaryB.withOpacity(0.7)
                          ]
                        : [_pc.primaryA, _pc.primaryB],
                  ),
                ),
              ),
              title: Text(
                l10n.get('discover_title'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: _pc.appBarForeground,
                ),
              ),
              centerTitle: true,
            ),
            entries.when(
              data: (items) {
                final bannerItems = banners.maybeWhen(
                  data: (value) => value,
                  orElse: () => const <DiscoverBanner>[],
                );
                return SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    0,
                    isDesktopSidebar ? 8 : 8,
                    0,
                    24,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _DiscoverGroupCard(
                      entries: items,
                      banners: bannerItems,
                      squareTap: () {
                        if (isDesktopSidebar) {
                          ref.read(desktopNavIndexProvider.notifier).state =
                              kDesktopNavMoments;
                          return;
                        }
                        context.push('/discover/square');
                      },
                      onBannerTap: (banner) => _openDiscoverUrl(
                        context,
                        title: banner.title,
                        rawUrl: banner.url,
                      ),
                      onEntryTap: (entry) => _openDiscoverEntry(context, entry),
                    ),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) =>
                  const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDiscoverEntry(
    BuildContext context,
    DiscoverEntry entry,
  ) async {
    await _openDiscoverUrl(
      context,
      title: entry.title,
      rawUrl: entry.url,
      openExternally: entry.openExternally,
    );
  }

  Future<void> _openDiscoverUrl(
    BuildContext context, {
    required String title,
    required String rawUrl,
    bool openExternally = false,
  }) async {
    final uri = _parseDiscoverUri(rawUrl);
    if (uri == null) {
      _showDiscoverOpenError(context);
      return;
    }

    if (Platform.isWindows || openExternally || !_isWebUri(uri)) {
      final launched = await _launchDiscoverUri(uri);
      if (!launched && context.mounted) {
        _showDiscoverOpenError(context);
      }
      return;
    }

    try {
      await InAppBrowser.open(
        context,
        uri.toString(),
        title: title,
        hideAddressBar: true,
      );
    } catch (_) {
      if (!context.mounted) return;
      final launched = await _launchDiscoverUri(uri);
      if (!launched && context.mounted) {
        _showDiscoverOpenError(context);
      }
    }
  }

  Uri? _parseDiscoverUri(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final parsed = Uri.tryParse(trimmed);
    if (parsed != null && parsed.hasScheme) {
      return parsed;
    }

    return Uri.tryParse('https://$trimmed');
  }

  bool _isWebUri(Uri uri) => uri.scheme == 'http' || uri.scheme == 'https';

  Future<bool> _launchDiscoverUri(Uri uri) async {
    try {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  void _showDiscoverOpenError(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _discoverText(
            zhCN:
                '\u8be5\u5165\u53e3\u6682\u4e0d\u53ef\u7528\uff0c\u8bf7\u5728\u540e\u53f0\u914d\u7f6e\u6709\u6548\u94fe\u63a5',
            zhTW:
                '\u8a72\u5165\u53e3\u66ab\u4e0d\u53ef\u7528\uff0c\u8acb\u5728\u5f8c\u53f0\u914d\u7f6e\u6709\u6548\u9023\u7d50',
            en: 'This entry is unavailable. Configure a valid link in the admin console.',
          ),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _DiscoverGroupCard extends StatelessWidget {
  final List<DiscoverEntry> entries;
  final List<DiscoverBanner> banners;
  final VoidCallback squareTap;
  final ValueChanged<DiscoverBanner> onBannerTap;
  final ValueChanged<DiscoverEntry> onEntryTap;

  const _DiscoverGroupCard({
    required this.entries,
    required this.banners,
    required this.squareTap,
    required this.onBannerTap,
    required this.onEntryTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final listTiles = <Widget>[
      _DiscoverTile(
        title: _discoverText(zhCN: '广场', zhTW: '廣場', en: 'Square'),
        accentColor: AppColors.linkFor(context),
        iconAsset: 'assets/icons/tab_moments_active.png',
        onTap: squareTap,
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceFor(context),
        border: Border.symmetric(
          horizontal: BorderSide(
            color: AppColors.dividerFor(context),
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (banners.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: _DiscoverBannerCarousel(
                banners: banners,
                onTap: onBannerTap,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Divider(
                height: 1,
                thickness: 0.5,
                color: AppColors.dividerFor(context),
              ),
            ),
          ],
          if (entries.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _discoverText(
                    zhCN: '常用应用',
                    zhTW: '常用應用',
                    en: 'Common Apps',
                  ),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
              ),
            ),
            _CommonAppsGrid(
              entries: entries,
              isDark: isDark,
              onTap: onEntryTap,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Divider(
                height: 1,
                thickness: 0.5,
                color: AppColors.dividerFor(context),
              ),
            ),
          ],
          for (var index = 0; index < listTiles.length; index++) ...[
            listTiles[index],
            if (index < listTiles.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 62),
                child: Divider(
                  height: 1,
                  thickness: 0.5,
                  color: AppColors.dividerFor(context),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CommonAppsGrid extends StatelessWidget {
  final List<DiscoverEntry> entries;
  final bool isDark;
  final ValueChanged<DiscoverEntry> onTap;

  const _CommonAppsGrid({
    required this.entries,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.78,
      ),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final accentColor = isDark && entry.iconUrl == null
            ? AppColors.linkFor(context)
            : entry.accentColor;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onTap(entry),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: accentColor.withOpacity(isDark ? 0.18 : 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: _DiscoverIcon(
                        accentColor: accentColor,
                        iconUrl: entry.iconUrl,
                        size: 44,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DiscoverBannerCarousel extends StatefulWidget {
  final List<DiscoverBanner> banners;
  final ValueChanged<DiscoverBanner> onTap;

  const _DiscoverBannerCarousel({
    required this.banners,
    required this.onTap,
  });

  @override
  State<_DiscoverBannerCarousel> createState() =>
      _DiscoverBannerCarouselState();
}

class _DiscoverBannerCarouselState extends State<_DiscoverBannerCarousel> {
  late final PageController _controller;
  Timer? _timer;
  int _index = 0;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _DiscoverBannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.banners.length != widget.banners.length) {
      _index = 0;
      if (_controller.hasClients) {
        _controller.jumpToPage(0);
      }
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    if (widget.banners.length <= 1) return;

    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || !_controller.hasClients || widget.banners.isEmpty) {
        return;
      }
      final next = (_index + 1) % widget.banners.length;
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AspectRatio(
      aspectRatio: 2.7,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF24242A) : const Color(0xFFF1F2F5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: widget.banners.length,
                onPageChanged: (value) => setState(() => _index = value),
                itemBuilder: (context, index) {
                  final banner = widget.banners[index];
                  final canOpen = banner.url.trim().isNotEmpty;

                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: canOpen ? () => widget.onTap(banner) : null,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            banner.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: isDark
                                  ? const Color(0xFF24242A)
                                  : const Color(0xFFF1F2F5),
                              alignment: Alignment.center,
                              child: Icon(
                                Icons.image_not_supported_outlined,
                                size: 30,
                                color: AppColors.textTertiaryFor(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              if (widget.banners.length > 1)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < widget.banners.length; i++)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: i == _index ? 16 : 6,
                          height: 6,
                          margin: const EdgeInsets.only(left: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(
                              i == _index ? 0.95 : 0.55,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoverTile extends StatelessWidget {
  final String title;
  final Color accentColor;
  final String? iconAsset;
  final String? iconUrl;
  final VoidCallback onTap;

  const _DiscoverTile({
    required this.title,
    required this.accentColor,
    this.iconAsset,
    this.iconUrl,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _DiscoverIcon(
                  accentColor: accentColor,
                  iconAsset: iconAsset,
                  iconUrl: iconUrl,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimaryFor(context),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: isDark
                      ? AppColors.darkTextTertiary
                      : const Color(0xFF9A9AA2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscoverIcon extends StatelessWidget {
  final Color accentColor;
  final String? iconAsset;
  final String? iconUrl;
  final double size;

  const _DiscoverIcon({
    required this.accentColor,
    this.iconAsset,
    this.iconUrl,
    this.size = 30,
  });

  @override
  Widget build(BuildContext context) {
    if (iconAsset != null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Image.asset(
            iconAsset!,
            width: size * 0.87,
            height: size * 0.87,
            color: accentColor,
          ),
        ),
      );
    }

    if (iconUrl != null && iconUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          iconUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          cacheWidth: 80,
          cacheHeight: 80,
          errorBuilder: (_, __, ___) => Icon(
            Icons.explore_rounded,
            color: accentColor,
            size: size * 0.93,
          ),
        ),
      );
    }

    return SizedBox(
      width: size,
      height: size,
      child: Icon(
        Icons.explore_rounded,
        color: accentColor,
        size: size * 0.93,
      ),
    );
  }
}
