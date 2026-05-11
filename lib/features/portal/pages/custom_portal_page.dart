import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import 'custom_portal_content.dart';

class CustomPortalPage extends ConsumerWidget {
  final bool isDesktopSidebar;

  const CustomPortalPage({super.key, this.isDesktopSidebar = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final settingsAsync = ref.watch(systemSettingsProvider);
    final configuredTitle = settingsAsync.valueOrNull?.portalTitle ?? '';
    final pageTitle =
        configuredTitle.isNotEmpty ? configuredTitle : l10n.tabPortal;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor:
            isDark ? AppColors.darkBackground : AppColors.lightBackground,
        surfaceTintColor: Colors.transparent,
        title: Text(pageTitle),
        centerTitle: true,
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _PortalUnavailable(
          title: l10n.get('portal_unavailable'),
          subtitle: l10n.get('portal_disabled_hint'),
        ),
        data: (settings) {
          if (!settings.hasCustomPortal) {
            return _PortalUnavailable(
              title: l10n.get('portal_unavailable'),
              subtitle: l10n.get('portal_disabled_hint'),
            );
          }

          final title = settings.portalTitle;
          final url = settings.portalUrl;
          return CustomPortalContent(
            url: url,
            title: title,
            isDesktopSidebar: isDesktopSidebar,
          );
        },
      ),
    );
  }
}

class _PortalUnavailable extends StatelessWidget {
  final String title;
  final String subtitle;

  const _PortalUnavailable({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.language_outlined,
              size: 42,
              color: isDark
                  ? AppColors.darkTextSecondary
                  : AppColors.lightTextSecondary,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
