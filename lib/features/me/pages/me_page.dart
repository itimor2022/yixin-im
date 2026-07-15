import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/top_gradient_backdrop.dart';
import '../../chat/providers/chat_provider.dart';
import '../../contacts/providers/contact_provider.dart';
import '../../settings/pages/profile_page.dart';
import '../../settings/pages/checkin_page.dart';
import '../../wallet/pages/wallet_page.dart';
import '../../settings/pages/notification_settings_page.dart';
// ── 隐私 / 数据 / 聊天 三个设置入口已下线，import 一并注释掉，
//   避免 lint 报未使用；下次恢复时同步取消注释。
// import '../../settings/pages/privacy_settings_page.dart';
// import '../../settings/pages/data_storage_page.dart';
// import '../../settings/pages/chat_settings_page.dart';
import '../../settings/pages/devices_page.dart';
import '../../settings/pages/network_settings_page.dart';
import '../../settings/pages/stickers_page.dart';

/// 主色调（海洋蓝，与 AppColors.primary / 底部导航保持一致）
const Color _kPrimary = Color(0xFFFF6B6B);

/// 顶部渐变区结构尺寸（与"聊天"页保持一致的视觉节奏）：
///   · header 视觉高度 = 10 (top pad) + 44 (content) + 6 (bottom pad) = 60
///   · "我的" 页没有搜索栏，所以中段（header 到内容之间）留 12dp 缓冲，
///     然后是 80dp 的淡出尾巴 —— 尾巴叠到用户卡片上方，实现"渐变延伸到
///     卡片上半部分"的效果，跟聊天页视觉一致。
const double _kMeHeaderContentHeight = 60;
const double _kMeGradientBufferHeight = 12;
const double _kMeGradientFadeTail = 80;

/// 我的主页 —— 头像卡 + 原程序 10 项列表。
///
/// 布局自上而下：
///  1. 大标题 "我的"
///  2. 用户卡片（头像 + 昵称 + 个性签名 + 右侧 QR 图标）
///     - 头像 / 昵称 tap 进入 [ProfilePage]（个人信息）
///     - QR 图标 tap 进入 [ProfilePage] 并自动打开其内部"我的二维码"子页
///  3. 一整张白色列表卡片：原程序设置 10 项
class MePage extends ConsumerWidget {
  const MePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final authState = ref.watch(authServiceProvider);
    final user = authState.user;

    final displayName = user?.nickname.isNotEmpty == true
        ? user!.nickname
        : (user?.username ?? '未登录');
    final bio = (user?.bio ?? '').trim().isNotEmpty
        ? user!.bio!.trim()
        : '个性签名';
    final avatar = user?.avatar;

    final double topPad = MediaQuery.of(context).padding.top;
    // 渐变**不透明**部分的高度 = status bar + 标题栏 + 缓冲区
    // ScrollView 顶部需要预留这么多，让用户卡片上半部分落到渐变尾巴里
    final double gradientOpaqueHeight =
        topPad + _kMeHeaderContentHeight + _kMeGradientBufferHeight;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      // 3 层 Stack 结构，与"聊天"页完全一致：
      //   · 底层：SingleChildScrollView，顶部预留 `gradientOpaqueHeight`
      //   · 中层：主色渐变，被 IgnorePointer 包住，不拦截手势
      //   · 顶层：SafeArea + 交互式左对齐标题
      body: Stack(
        children: [
          // ==================== 底层：滚动内容 ====================
          Positioned.fill(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(top: gradientOpaqueHeight, bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildProfileCard(context, displayName, bio, avatar),
                  const SizedBox(height: 14),
                  _buildMenuCard(context, ref, l10n),
                  const SizedBox(height: 20),
                  _buildLogoutCard(context, ref),
                ],
              ),
            ),
          ),

          // ==================== 中层：纯装饰渐变（IgnorePointer） ====================
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topPad + _kMeHeaderContentHeight +
                _kMeGradientBufferHeight + _kMeGradientFadeTail,
            child: const IgnorePointer(
              child: TopGradientBackdrop(),
            ),
          ),

          // ==================== 顶层：交互式标题（左对齐白字） ====================
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
    );
  }

  /// 左对齐白字标题栏 —— 与"聊天"页 header 保持视觉一致
  ///
  /// 视觉高度 = 10 (top pad) + 44 (content) + 6 (bottom pad) = [_kMeHeaderContentHeight]
  Widget _buildTitleBar(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
      child: SizedBox(
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            l10n.tabMe,
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

  Widget _buildProfileCard(
    BuildContext context,
    String displayName,
    String bio,
    String? avatar,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context, rootNavigator: true).push(
              MaterialPageRoute(builder: (_) => ProfilePage()),
            );
          },
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            child: Row(
              children: [
                AvatarWidget(
                  name: displayName,
                  avatar: avatar,
                  size: 64,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827),
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        bio,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF9CA3AF),
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      Navigator.of(context, rootNavigator: true).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              ProfilePage(autoShowQrCode: true),
                        ),
                      );
                    },
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.qr_code_rounded,
                        size: 26,
                        color: Color(0xFF374151),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) {
    // 按"修改之前原程序内容"排列 —— 与旧版 SettingsPage 10 项一一对应
    final items = <_MeMenuData>[
      // 签到（受系统开关控制，未启用则隐藏）
      _MeMenuData(
        icon: Icons.local_fire_department_rounded,
        iconColor: const Color(0xFFFF9500),
        title: '签到',
        onTap: () => _push(context, const CheckinPage()),
        visibleSelector: (s) => s?.checkinEnabled == true,
      ),
      // 钱包（受系统开关控制，未启用则隐藏）
      _MeMenuData(
        icon: Icons.account_balance_wallet_outlined,
        iconColor: const Color(0xFF10B981),
        title: '我的钱包',
        onTap: () => _push(context, const WalletPage()),
        visibleSelector: (s) => s?.walletEnabled == true,
      ),
      _MeMenuData(
        icon: Icons.notifications_active_outlined,
        iconColor: const Color(0xFFFF3B30),
        title: '通知',
        onTap: () => _push(context, const NotificationSettingsPage()),
      ),
      // ── 「隐私 / 数据 / 聊天」三个入口应产品要求暂时下线；相关设置页保留，只是
      //   不再从「我的」菜单里跳转。等下次需要恢复时把三个 _MeMenuData 块重新加回来即可。
      _MeMenuData(
        icon: Icons.devices_other_outlined,
        iconColor: const Color(0xFF5856D6),
        title: l10n.devices,
        onTap: () => _push(context, const DevicesPage()),
      ),
      _MeMenuData(
        icon: Icons.public_outlined,
        iconColor: const Color(0xFF00A896),
        title: '网络',
        onTap: () => _push(context, const NetworkSettingsPage()),
      ),
      _MeMenuData(
        icon: Icons.emoji_emotions_outlined,
        iconColor: const Color(0xFFFFCC00),
        title: '表情',
        onTap: () => _push(context, const StickersPage()),
      ),
    ];

    // 根据 systemSettings 过滤可见项（签到项由后端开关控制）
    final systemSettings = ref.watch(systemSettingsProvider).valueOrNull;
    final visibleItems = items.where((e) {
      final selector = e.visibleSelector;
      return selector == null || selector(systemSettings);
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: List.generate(
            visibleItems.length * 2 - 1,
            (index) {
              if (index.isOdd) return const _MeDivider();
              final item = visibleItems[index ~/ 2];
              return _MeMenuItem(
                icon: item.icon,
                iconColor: item.iconColor,
                title: item.title,
                titleColor: item.titleColor,
                onTap: item.onTap,
              );
            },
          ),
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) {
    HapticFeedback.selectionClick();
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  /// 独立的"退出登录"红色卡片，位于菜单最下方
  Widget _buildLogoutCard(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _confirmLogout(context, ref),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  SizedBox(
                    width: 26,
                    height: 26,
                    child: Icon(
                      Icons.logout_rounded,
                      color: AppColors.error,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      '退出登录',
                      style: TextStyle(
                        fontSize: 15.5,
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 退出登录二次确认弹窗
  void _confirmLogout(BuildContext context, WidgetRef ref) {
    HapticFeedback.selectionClick();
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '退出登录',
      barrierColor: Colors.black.withOpacity(0.4),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim, __) => const SizedBox.shrink(),
      transitionBuilder: (ctx, anim, __, child) {
        return Opacity(
          opacity: anim.value,
          child: Transform.scale(
            scale: 0.95 + 0.05 * anim.value,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Material(
                  color: Colors.transparent,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 340),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 30,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 顶部图标
                        const SizedBox(height: 24),
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.10),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.logout_rounded,
                            color: AppColors.error,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          '退出登录',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            '确定要退出当前账号吗？退出后将清除本地会话缓存。',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: Color(0xFF6B7280),
                              height: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Divider(
                          height: 1,
                          thickness: 0.6,
                          color: const Color(0xFFEDEFF2),
                        ),
                        SizedBox(
                          height: 48,
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => Navigator.of(ctx).pop(),
                                  child: const Center(
                                    child: Text(
                                      '取消',
                                      style: TextStyle(
                                        fontSize: 15.5,
                                        color: Color(0xFF6B7280),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Container(
                                width: 0.6,
                                color: const Color(0xFFEDEFF2),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    Navigator.of(ctx).pop();
                                    _performLogout(context, ref);
                                  },
                                  child: Center(
                                    child: Text(
                                      '退出',
                                      style: TextStyle(
                                        fontSize: 15.5,
                                        color: AppColors.error,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 执行退出登录：清理会话/联系人缓存 → 调用 AuthService.logout → 跳转 /login
  Future<void> _performLogout(BuildContext context, WidgetRef ref) async {
    HapticFeedback.mediumImpact();
    try {
      ref.read(chatListProvider.notifier).reset();
      ref.read(contactListProvider.notifier).reset();
      await ref.read(authServiceProvider.notifier).logout();
      if (!context.mounted) return;
      context.go('/login');
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('退出失败: $e'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }
}

/// 单项菜单描述（用于列表数据驱动生成）
class _MeMenuData {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? titleColor;
  final VoidCallback onTap;

  /// 可选：系统设置过滤器，返回 false 时该项不显示
  final bool Function(SystemSettings? settings)? visibleSelector;

  const _MeMenuData({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onTap,
    this.titleColor,
    this.visibleSelector,
  });
}

/// 分隔线（左缩进 56，模拟参考图效果）
class _MeDivider extends StatelessWidget {
  const _MeDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 56, right: 16),
      child: Divider(
        height: 1,
        thickness: 0.6,
        color: Color(0xFFEDEFF2),
      ),
    );
  }
}

/// 列表项：图标 + 标题 + 右箭头
class _MeMenuItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Color? titleColor;
  final VoidCallback onTap;

  const _MeMenuItem({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.titleColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              SizedBox(
                width: 26,
                height: 26,
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15.5,
                    color: titleColor ?? const Color(0xFF111827),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                size: 22,
                color: Color(0xFFBDBDBD),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
