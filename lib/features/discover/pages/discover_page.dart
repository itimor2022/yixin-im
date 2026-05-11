import 'package:universal_io/io.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/services/api/api_client.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../home/pages/home_desktop_page.dart';
import '../../../shared/widgets/in_app_browser.dart';

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
  final _ = await ref.refresh(discoverEntriesProvider.future);
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
  } catch (_) {
    // 交给下方空列表兜底
  }

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final entries = ref.watch(discoverEntriesProvider);

    return Scaffold(
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
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              16,
              isDesktopSidebar ? 12 : 16,
              16,
              12,
            ),
            sliver: SliverToBoxAdapter(
              child: _SquareHeaderCard(
                onTap: () {
                  if (isDesktopSidebar) {
                    ref.read(desktopNavIndexProvider.notifier).state =
                        kDesktopNavMoments;
                    return;
                  }
                  context.push('/discover/square');
                },
              ),
            ),
          ),
          entries.when(
            data: (items) {
              if (items.isEmpty) {
                return const SliverToBoxAdapter(
                  child: SizedBox.shrink(),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList.separated(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final entry = items[index];
                    return _DiscoverCard(
                      entry: entry,
                      onTap: () => _openDiscoverEntry(context, entry),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                ),
              );
            },
            loading: () => const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const SliverToBoxAdapter(
              child: SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDiscoverEntry(
      BuildContext context, DiscoverEntry entry) async {
    final uri = Uri.tryParse(entry.url);

    if (Platform.isWindows) {
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      return;
    }

    if (entry.openExternally) {
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    await InAppBrowser.open(
      context,
      entry.url,
      title: entry.title,
      hideAddressBar: true,
    );
  }
}

class _SquareHeaderCard extends StatelessWidget {
  final VoidCallback onTap;

  const _SquareHeaderCard({
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
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : AppColors.lightDivider,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.16 : 0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: Image.asset(
                      'assets/icons/tab_moments_active.png',
                      width: 24,
                      height: 24,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '广场',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DiscoverCard extends StatelessWidget {
  final DiscoverEntry entry;
  final VoidCallback onTap;

  const _DiscoverCard({
    required this.entry,
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
              color: isDark
                  ? Colors.white.withOpacity(0.05)
                  : AppColors.lightDivider,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.16 : 0.05),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: entry.accentColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: entry.iconUrl != null && entry.iconUrl!.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            entry.iconUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.explore_rounded,
                              color: entry.accentColor,
                              size: 24,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.explore_rounded,
                          color: entry.accentColor,
                          size: 24,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 22,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
