// 文件用途：实现 AuthDesktopLayout 相关逻辑，服务于跨模块共享能力。
// 核心逻辑：围绕 AuthDesktopLayout 组织，完成输入校验、核心处理和结果回传。
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/platform_utils.dart';

String _authDesktopText(
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

// 关键声明：auth desktop layout 把桌面系统能力封装成应用接口，处理窗口、托盘或快捷键生命周期并避免泄漏监听器。
/// 桌面端认证页面布局
/// Telegram 风格 - 左侧品牌展示 + 右侧表单
class AuthDesktopLayout extends ConsumerWidget {
  /// 表单内容
  final Widget child;

  /// 是否显示返回按钮
  final bool showBackButton;

  /// 返回按钮回调
  final VoidCallback? onBack;

  /// 标题
  final String? title;

  const AuthDesktopLayout({
    super.key,
    required this.child,
    this.showBackButton = false,
    this.onBack,
    this.title,
  });

  // 流程逻辑：`build` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    // 桌面端使用双栏布局
    if (PlatformUtils.isPhysicalDesktop || screenWidth >= 900) {
      return _buildDesktopLayout(context, isDark, ref);
    }

    // 平板使用居中卡片布局
    if (screenWidth >= 600) {
      return _buildTabletLayout(context, isDark);
    }

    // 移动端使用原始布局
    return child;
  }

  /// 桌面端双栏布局
  Widget _buildDesktopLayout(BuildContext context, bool isDark, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      body: Row(
        children: [
          // 左侧品牌区域
          Expanded(flex: 5, child: _buildBrandingSection(context, isDark, ref)),

          // 右侧表单区域
          Expanded(flex: 4, child: _buildFormSection(context, isDark)),
        ],
      ),
    );
  }

  /// 平板居中卡片布局
  Widget _buildTabletLayout(BuildContext context, bool isDark) {
    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      body: Center(
        child: Container(
          width: 480,
          margin: const EdgeInsets.symmetric(vertical: 40),
          decoration: BoxDecoration(
            color: AppColors.cardFor(context),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showBackButton || title != null)
                  _buildCardHeader(context, isDark),
                Flexible(child: SingleChildScrollView(child: child)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 卡片头部（带返回按钮）
  Widget _buildCardHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.dividerFor(context),
          ),
        ),
      ),
      child: Row(
        children: [
          if (showBackButton)
            IconButton(
              onPressed: onBack,
              icon: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: AppColors.textPrimaryFor(context),
                size: 20,
              ),
            )
          else
            const SizedBox(width: 48),
          Expanded(
            child: Text(
              title ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimaryFor(context),
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  /// 左侧品牌展示区
  Widget _buildBrandingSection(
      BuildContext context, bool isDark, WidgetRef ref) {
    final appName =
        ref.watch(systemSettingsProvider).valueOrNull?.displayName ??
            defaultAppDisplayName();
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primaryWithOpacity(context, 0.9),
            AppColors.primaryFor(context),
            AppColors.primaryWithOpacity(context, 0.8),
          ],
        ),
      ),
      child: Stack(
        children: [
          // 装饰性圆圈
          Positioned(
            top: -80,
            left: -80,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -40,
            right: -40,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
          Positioned(
            top: 100,
            right: -30,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.05),
              ),
            ),
          ),

          // 内容
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Image.asset('assets/logo.png'),
                    ).animate().fadeIn(duration: 500.ms).scale(
                          begin: const Offset(0.8, 0.8),
                          curve: Curves.easeOut,
                          duration: 500.ms,
                        ),

                    const SizedBox(height: 28),

                    // 标题
                    Text(
                      appName,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ).animate().fadeIn(delay: 200.ms, duration: 400.ms),

                    const SizedBox(height: 8),

                    // 副标题
                    Text(
                      _authDesktopText(
                        context,
                        zhCN: '安全、快速、跨平台的即时通讯',
                        zhTW: '安全、快速、跨平台的即時通訊',
                        en: 'Secure, fast, cross-platform messaging',
                      ),
                      style: TextStyle(
                        fontSize: 15,
                        color: Colors.white.withOpacity(0.85),
                      ),
                    ).animate().fadeIn(delay: 300.ms, duration: 400.ms),

                    const SizedBox(height: 40),

                    // 特性列表
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _buildFeatureItem(
                            context,
                            Icons.security_rounded,
                            _authDesktopText(
                              context,
                              zhCN: '端到端加密',
                              zhTW: '端到端加密',
                              en: 'End-to-end encryption',
                            ),
                            _authDesktopText(
                              context,
                              zhCN: '保护您的每一条消息',
                              zhTW: '保護您的每一則訊息',
                              en: 'Protect every message you send',
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Divider(
                              color: Colors.white.withOpacity(0.1),
                              height: 1,
                            ),
                          ),
                          _buildFeatureItem(
                            context,
                            Icons.devices_rounded,
                            _authDesktopText(
                              context,
                              zhCN: '多端同步',
                              zhTW: '多端同步',
                              en: 'Multi-device sync',
                            ),
                            _authDesktopText(
                              context,
                              zhCN: '手机、平板、电脑无缝切换',
                              zhTW: '手機、平板、電腦無縫切換',
                              en: 'Move seamlessly across phone, tablet, and desktop',
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: Divider(
                              color: Colors.white.withOpacity(0.1),
                              height: 1,
                            ),
                          ),
                          _buildFeatureItem(
                            context,
                            Icons.speed_rounded,
                            _authDesktopText(
                              context,
                              zhCN: '快速传输',
                              zhTW: '快速傳輸',
                              en: 'Fast transfer',
                            ),
                            _authDesktopText(
                              context,
                              zhCN: '文件、图片秒速送达',
                              zhTW: '檔案、圖片快速送達',
                              en: 'Files and images delivered in seconds',
                            ),
                          ),
                        ],
                      ),
                    ).animate().fadeIn(delay: 400.ms).slideY(begin: 0.1),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 特性项
  Widget _buildFeatureItem(
    BuildContext _,
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withOpacity(0.75),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 右侧表单区域
  Widget _buildFormSection(BuildContext context, bool isDark) {
    return Container(
      color: AppColors.backgroundFor(context),
      child: Column(
        children: [
          // 顶部栏（带窗口控制按钮占位）
          if (showBackButton || title != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                children: [
                  if (showBackButton)
                    IconButton(
                      onPressed: onBack,
                      icon: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: AppColors.textPrimaryFor(context),
                        size: 20,
                      ),
                    )
                  else
                    const SizedBox(width: 48),
                  Expanded(
                    child: Text(
                      title ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimaryFor(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            )
          else
            // macOS 红绿灯按钮占位
            SizedBox(height: PlatformUtils.isApple ? 32 : 16),

          // 表单内容
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 40,
                    vertical: 24,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
