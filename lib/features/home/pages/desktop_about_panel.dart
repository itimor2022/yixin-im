// 文件用途：实现 DesktopDynamicAboutPanel 页面及其交互流程，属于应用首页。
// 核心逻辑：维护 DesktopDynamicAboutPanel 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../features/home/pages/home_desktop_page.dart';

String _aboutText(
  BuildContext context, {
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.of(context).language) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

final desktopDynamicAboutInfoProvider =
    FutureProvider<({PackageInfo packageInfo, SystemSettings settings})>(
        (ref) async {
  final packageInfo = await PackageInfo.fromPlatform();
  final settings = await ref.watch(systemSettingsProvider.future);
  return (packageInfo: packageInfo, settings: settings);
});

// 关键声明：desktop about panel 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class DesktopDynamicAboutPanel extends ConsumerWidget {
  const DesktopDynamicAboutPanel({super.key});

  // 流程逻辑：`build` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final aboutInfoAsync = ref.watch(desktopDynamicAboutInfoProvider);
    final fallbackName =
        ref.watch(systemSettingsProvider).valueOrNull?.displayName ??
            defaultAppDisplayName();

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBackground : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios,
              size: 20, color: AppColors.primaryFor(context)),
          onPressed: () {
            ref.read(desktopProfileProvider.notifier).state =
                DesktopProfileInfo.none;
          },
        ),
        title: Text(
          _aboutText(
            context,
            zhCN: '关于',
            zhTW: '關於',
            en: 'About',
          ),
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
            versionText: _aboutText(
              context,
              zhCN: '加载中...',
              zhTW: '載入中...',
              en: 'Loading...',
            ),
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
            color: AppColors.primaryWithOpacity(context, 0.1),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Icon(
            Icons.info_outline_rounded,
            size: 48,
            color: AppColors.primaryFor(context),
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
          _aboutText(
            context,
            zhCN: '通用版本',
            zhTW: '通用版本',
            en: 'Generic edition',
          ),
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white38 : Colors.black38,
          ),
        ),
      ],
    );
  }
}
