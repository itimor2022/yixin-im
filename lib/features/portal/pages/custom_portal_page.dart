// 文件用途：实现 CustomPortalPage 页面及其交互流程，属于门户内容。
// 核心逻辑：维护 CustomPortalPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import 'custom_portal_content.dart';

// 关键声明：custom portal page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class CustomPortalPage extends ConsumerWidget {
  final bool isDesktopSidebar;

  const CustomPortalPage({super.key, this.isDesktopSidebar = false});

  // 流程逻辑：`build` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
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
        actions: [
          if (!isDesktopSidebar)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton.icon(
                key: const ValueKey('custom-portal-close-button'),
                onPressed: () => context.go('/home'),
                icon: const Icon(Icons.close_rounded, size: 20),
                label: Text(l10n.close),
              ),
            ),
        ],
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
              color: AppColors.textSecondaryFor(context),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryFor(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSecondaryFor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
