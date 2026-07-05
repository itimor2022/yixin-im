import 'package:universal_io/io.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart'; 
import 'package:visibility_detector/visibility_detector.dart';

import '../../../core/services/api/api_client.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/pages/home_desktop_page.dart';
import '../../../core/services/api/system_settings_service.dart';

final discoverBannerProvider = FutureProvider.autoDispose<String?>((ref) async {
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

const _accentColors = <Color>[
  Color(0xFF2D6CDF),
  Color(0xFF0F9D58),
  Color(0xFFE67E22),
  Color(0xFF8E44AD),
  Color(0xFF0097A7),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final entries = ref.watch(discoverEntriesProvider);
    final bannerAsync = ref.watch(discoverBannerProvider);

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
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 0,
              floating: true,
              pinned: true,
              backgroundColor:
                  isDark ? AppColors.darkBackground : AppColors.lightBackground,
              surfaceTintColor: Colors.transparent,
              title: Text(
                l10n.get('discover_title'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              centerTitle: true,
            ),
            bannerAsync.when(
              data: (imageUrl) {
                if (imageUrl == null || imageUrl.isEmpty) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }
                final cleanUrl = '$imageUrl${imageUrl.contains('?') ? '&' : '?'}_t=$_refreshKey';

                return SliverToBoxAdapter(
                  child: Container(
                    width: double.infinity,
                    height: 180,
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        cleanUrl,
                        key: ValueKey(cleanUrl),
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        },
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
            
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, widget.isDesktopSidebar ? 12 : 16, 16, 12),
              sliver: SliverToBoxAdapter(
                child: _BeautifulNavCard(
                  title: '广场',
                  url: widget.isDesktopSidebar ? 'kDesktopNavMoments' : '/discover/square',
                  iconWidget: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/icons/tab_moments_active.png',
                        width: 22,
                        height: 22,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  onTap: () {
                    if (widget.isDesktopSidebar) {
                      ref.read(desktopNavIndexProvider.notifier).state = kDesktopNavMoments;
                      return;
                    }
                    context.push('/discover/square');
                  },
                ),
              ),
            ),
            
            entries.when(
              data: (items) {
                if (items.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
                return SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final entry = items[index];
                      return _BeautifulCopyCard(
                        title: entry.title,
                        url: entry.url,
                        iconWidget: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: entry.accentColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: entry.iconUrl != null && entry.iconUrl!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    entry.iconUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Icon(Icons.explore_rounded, color: entry.accentColor, size: 22),
                                  ),
                                )
                              : Icon(Icons.explore_rounded, color: entry.accentColor, size: 22),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                  ),
                );
              },
              loading: () => const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
              error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
          ],
        ),
      ),
    );
  }
}

class _BeautifulNavCard extends StatelessWidget {
  final String title;
  final String url; 
  final Widget iconWidget;
  final VoidCallback onTap;

  const _BeautifulNavCard({
    required this.title,
    required this.url,
    required this.iconWidget,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.06) : AppColors.lightDivider,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.12 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                iconWidget,
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isDark ? Colors.white54 : Colors.black45,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BeautifulCopyCard extends StatefulWidget {
  final String title;
  final String url;
  final Widget iconWidget;

  const _BeautifulCopyCard({
    required this.title,
    required this.url,
    required this.iconWidget,
  });

  @override
  State<_BeautifulCopyCard> createState() => _BeautifulCopyCardState();
}

class _BeautifulCopyCardState extends State<_BeautifulCopyCard> {
  bool _isCopied = false;

  void _copyToClipboard() {
    if (_isCopied) return;
    
    final copyText = '名称: ${widget.title}\n网址: ${widget.url}';
    Clipboard.setData(ClipboardData(text: copyText));

    setState(() {
      _isCopied = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 18),
            const SizedBox(width: 8),
            Text('已成功复制 ${widget.title} 的信息', style: const TextStyle(fontSize: 13)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        width: 280,
        backgroundColor: Colors.black.withOpacity(0.85),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() {
          _isCopied = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _copyToClipboard,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? Colors.white.withOpacity(0.06) : AppColors.lightDivider,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.12 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                widget.iconWidget,
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        widget.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                    child: _isCopied
                        ? const Icon(Icons.check_rounded, key: ValueKey('check'), color: Colors.green, size: 20)
                        : Icon(
                            Icons.copy_all_rounded,
                            key: const Key('copy'),
                            color: isDark ? Colors.white54 : Colors.black45,
                            size: 20,
                          ),
                  ),
                  onPressed: _copyToClipboard,
                  splashRadius: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}