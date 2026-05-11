import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/services/api/system_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/home/pages/home_desktop_page.dart';

final desktopDynamicAboutInfoProvider =
    FutureProvider<({PackageInfo packageInfo, SystemSettings settings})>(
        (ref) async {
  final packageInfo = await PackageInfo.fromPlatform();
  final settings = await ref.watch(systemSettingsProvider.future);
  return (packageInfo: packageInfo, settings: settings);
});

class DesktopDynamicAboutPanel extends ConsumerWidget {
  const DesktopDynamicAboutPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final aboutInfoAsync = ref.watch(desktopDynamicAboutInfoProvider);
    final fallbackName =
        ref.watch(systemSettingsProvider).valueOrNull?.displayName ?? '壹信IM';

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: AppColors.primary),
          onPressed: () {
            ref.read(desktopProfileProvider.notifier).state =
                DesktopProfileInfo.none;
          },
        ),
        title: Text(
          '关于',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: aboutInfoAsync.when(
          data: (aboutInfo) {
            final configuredVersion = aboutInfo.settings.systemVersion.trim();
            final versionText = configuredVersion.isNotEmpty
                ? configuredVersion
                : aboutInfo.packageInfo.version;
            return _AboutBody(
              isDark: isDark,
              appName: aboutInfo.settings.displayName,
              versionText: 'v$versionText',
            );
          },
          loading: () => _AboutBody(
            isDark: isDark,
            appName: fallbackName,
            versionText: '加载中...',
          ),
          error: (_, __) => _AboutBody(
            isDark: isDark,
            appName: fallbackName,
            versionText: 'v--',
          ),
        ),
      ),
    );
  }
}

class _AboutBody extends StatelessWidget {
  final bool isDark;
  final String appName;
  final String versionText;

  const _AboutBody({
    required this.isDark,
    required this.appName,
    required this.versionText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(
            Icons.info_outline_rounded,
            size: 48,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          appName,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          versionText,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
        const SizedBox(height: 32),
        Text(
          '© 2024 壹信网络',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    );
  }
}
