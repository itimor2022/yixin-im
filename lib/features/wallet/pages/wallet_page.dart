// 文件用途：实现 WalletPage 页面及其交互流程，属于钱包与支付。
// 核心逻辑：维护 WalletPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/system_ui_styles.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/utils/platform_utils.dart';
import '../providers/wallet_provider.dart';
import '../services/wallet_service.dart';
import 'set_pay_password_page.dart';
import 'recharge_page.dart';
import 'withdraw_page.dart';
import 'transaction_list_page.dart';

String _walletText(
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

// 关键声明：wallet page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
/// 钱包主页
class WalletPage extends ConsumerStatefulWidget {
  const WalletPage({super.key});

  @override
  ConsumerState<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends ConsumerState<WalletPage> {
  bool _isBalanceVisible = true;
  String _walletNotice = '';
  List<Map<String, dynamic>> _rechargeOrders = [];
  Set<String> _dismissedOrderIds = {};
  static const _dismissedKey = 'wallet_dismissed_order_ids';

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(walletProvider.notifier).loadWallet();
      _loadSettings();
      _loadDismissedThenOrders();
    });
  }

  /// 先加载已删除的 ID，再加载订单（加载后自动过滤）
  Future<void> _loadDismissedThenOrders() async {
    if (!_walletRechargeAllowed()) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _dismissedOrderIds = (prefs.getStringList(_dismissedKey) ?? []).toSet();
    } catch (_) {}
    _loadOrders();
  }

  bool _walletRechargeAllowed() {
    if (!PlatformUtils.isIOS) return true;
    final settings = ref.read(systemSettingsProvider).valueOrNull;
    return settings?.iosCompliance.allowsWalletRecharge ?? false;
  }

  /// 永久记住已删除的订单 ID
  Future<void> _dismissOrder(String orderId) async {
    _dismissedOrderIds.add(orderId);
    setState(() {
      _rechargeOrders.removeWhere((item) => _getOrderId(item) == orderId);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_dismissedKey, _dismissedOrderIds.toList());
    } catch (_) {}
  }

  String _getOrderId(Map<String, dynamic> o) =>
      o['id']?.toString() ??
      o['order_id']?.toString() ??
      o['uuid']?.toString() ??
      '';

  Future<void> _loadSettings() async {
    try {
      final settings = await ref.read(walletSettingsProvider.future);
      if (mounted) {
        setState(() => _walletNotice = settings.walletNotice);
      }
    } catch (_) {}
  }

  Future<void> _loadOrders() async {
    try {
      final svc = ref.read(walletServiceProvider);
      final resp = await svc.getRechargeOrders();
      if (resp.isSuccess && resp.data != null && mounted) {
        // 过滤掉已被用户滑动删除的订单
        final filtered = resp.data!
            .where((o) => !_dismissedOrderIds.contains(_getOrderId(o)))
            .toList();
        setState(() => _rechargeOrders = filtered);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(walletCurrencyProvider);
    final rechargeAllowed = !PlatformUtils.isIOS ||
        (ref
                .watch(systemSettingsProvider)
                .valueOrNull
                ?.iosCompliance
                .allowsWalletRecharge ??
            false);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final walletState = ref.watch(walletProvider);
    final wallet = walletState.wallet;

    return Scaffold(
      backgroundColor: AppColors.backgroundFor(context),
      appBar: AppBar(
        backgroundColor: AppColors.primaryFor(context),
        systemOverlayStyle: AppSystemUiStyles.onWalletBackground,
        flexibleSpace: Column(
          children: [
            SizedBox(
              height: MediaQuery.paddingOf(context).top,
              child: const ColoredBox(
                color: AppSystemUiStyles.walletStatusBarColor,
              ),
            ),
            Expanded(
              child: ColoredBox(color: AppColors.primaryFor(context)),
            ),
          ],
        ),
        elevation: 0,
        title: Text(
          _walletText(
            context,
            zhCN: '钱包',
            zhTW: '錢包',
            en: 'Wallet',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, size: 20, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(walletProvider.notifier).refresh(),
        color: AppColors.controlActiveFor(context),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // 余额卡片
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                decoration: BoxDecoration(
                  color: AppColors.primaryFor(context),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题行
                    Row(
                      children: [
                        Text(
                          _walletText(
                            context,
                            zhCN: '账户余额',
                            zhTW: '帳戶餘額',
                            en: 'Balance',
                          ),
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _isBalanceVisible = !_isBalanceVisible;
                            });
                          },
                          child: Icon(
                            _isBalanceVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            size: 18,
                            color: Colors.white.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // 余额显示（只有首次加载无数据时才显示 loading）
                    walletState.isLoading && wallet == null
                        ? const SizedBox(
                            height: 48,
                            child: Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            ),
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                currency,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _isBalanceVisible
                                    ? (wallet?.balance ?? 0).toStringAsFixed(2)
                                    : '****',
                                style: const TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  letterSpacing: 1,
                                ),
                              ),
                            ],
                          ),

                    const SizedBox(height: 28),

                    // 操作按钮
                    Row(
                      children: [
                        if (rechargeAllowed) ...[
                          Expanded(
                            child: _buildActionButton(
                              icon: Icons.add,
                              label: _walletText(
                                context,
                                zhCN: '充值',
                                zhTW: '充值',
                                en: 'Top Up',
                              ),
                              onTap: () => _navigateToRecharge(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: _buildActionButton(
                            icon: Icons.arrow_upward,
                            label: _walletText(
                              context,
                              zhCN: '提现',
                              zhTW: '提現',
                              en: 'Withdraw',
                            ),
                            onTap: () => _navigateToWithdraw(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildActionButton(
                            icon: Icons.receipt_long,
                            label: _walletText(
                              context,
                              zhCN: '账单',
                              zhTW: '帳單',
                              en: 'Transactions',
                            ),
                            onTap: () => _navigateToTransactions(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 钱包公告
              if (_walletNotice.isNotEmpty) ...[
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.cardFor(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.controlBorderFor(context),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.campaign_outlined,
                          color: AppColors.linkFor(context),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _walletNotice,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondaryFor(context),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // 充值/提现进度
              if (rechargeAllowed)
                ..._rechargeOrders
                    .where((o) {
                      final s = o['status'] as String? ?? '';
                      return s == 'pending' ||
                          s == 'approved' ||
                          s == 'rejected';
                    })
                    .take(3)
                    .map((o) {
                      final status = o['status'] as String? ?? '';
                      final amount = (o['amount'] as num?)?.toDouble() ?? 0;
                      final method = o['method_name'] as String? ??
                          _walletText(
                            context,
                            zhCN: '充值',
                            zhTW: '充值',
                            en: 'Top Up',
                          );
                      final remark = o['remark'] as String? ?? '';
                      final createdAt = o['created_at']?.toString() ?? '';

                      Color statusColor;
                      IconData statusIcon;
                      String statusText;
                      String subtitle;

                      if (status == 'pending') {
                        statusColor = const Color(0xFFE6A23C);
                        statusIcon = Icons.schedule;
                        statusText = _walletText(
                          context,
                          zhCN: '审核中',
                          zhTW: '審核中',
                          en: 'Pending',
                        );
                        subtitle = _walletText(
                          context,
                          zhCN: '等待管理员审核',
                          zhTW: '等待管理員審核',
                          en: 'Waiting for admin review',
                        );
                      } else if (status == 'approved') {
                        statusColor = const Color(0xFF67C23A);
                        statusIcon = Icons.check_circle;
                        statusText = _walletText(
                          context,
                          zhCN: '已到账',
                          zhTW: '已到帳',
                          en: 'Completed',
                        );
                        subtitle = _walletText(
                          context,
                          zhCN: '充值成功',
                          zhTW: '充值成功',
                          en: 'Top-up completed',
                        );
                      } else {
                        statusColor = const Color(0xFFF56C6C);
                        statusIcon = Icons.cancel;
                        statusText = _walletText(
                          context,
                          zhCN: '已拒绝',
                          zhTW: '已拒絕',
                          en: 'Rejected',
                        );
                        subtitle = remark.isNotEmpty
                            ? remark
                            : _walletText(
                                context,
                                zhCN: '充值被拒绝',
                                zhTW: '充值被拒絕',
                                en: 'Top-up rejected',
                              );
                      }

                      final orderId = _getOrderId(o);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: Dismissible(
                          key: ValueKey('order_$orderId'),
                          direction: DismissDirection.endToStart,
                          movementDuration: const Duration(milliseconds: 200),
                          resizeDuration: const Duration(milliseconds: 250),
                          dismissThresholds: const {
                            DismissDirection.endToStart: 0.3,
                          },
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 24),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF6B6B), Color(0xFFEE5A24)],
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  _walletText(
                                    context,
                                    zhCN: '删除',
                                    zhTW: '刪除',
                                    en: 'Delete',
                                  ),
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          onDismissed: (_) => _dismissOrder(orderId),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.cardFor(context),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    statusIcon,
                                    color: statusColor,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$method · $currency${amount.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color:
                                              AppColors.textPrimaryFor(context),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        subtitle,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textTertiaryFor(
                                              context),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),

              const SizedBox(height: 20),

              // 安全设置
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildSecurityCard(context, isDark, wallet),
              ),

              // 底部安全区间距，防止内容被系统导航条/Home Indicator 遮挡
              SizedBox(height: MediaQuery.of(context).padding.bottom + 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: Colors.white),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityCard(
    BuildContext context,
    bool isDark,
    WalletInfo? wallet,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardFor(context),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 支付密码
          _buildSettingTile(
            context,
            icon: Icons.lock_outline,
            title: _walletText(
              context,
              zhCN: '支付密码',
              zhTW: '支付密碼',
              en: 'Payment Password',
            ),
            subtitle: wallet?.hasPayPassword == true
                ? _walletText(
                    context,
                    zhCN: '已设置',
                    zhTW: '已設置',
                    en: 'Set',
                  )
                : _walletText(
                    context,
                    zhCN: '未设置',
                    zhTW: '未設置',
                    en: 'Not Set',
                  ),
            subtitleColor: wallet?.hasPayPassword == true
                ? const Color(0xFF34C759)
                : Colors.orange,
            isDark: isDark,
            onTap: () => _navigateToSetPayPassword(
              context,
              wallet?.hasPayPassword ?? false,
            ),
          ),

          Divider(
            height: 1,
            indent: 56,
            endIndent: 16,
            color: AppColors.dividerFor(context),
          ),

          // 关于钱包
          _buildSettingTile(
            context,
            icon: Icons.info_outline,
            title: _walletText(
              context,
              zhCN: '关于钱包',
              zhTW: '關於錢包',
              en: 'About Wallet',
            ),
            subtitle: '',
            isDark: isDark,
            onTap: () => _showAboutDialog(context, isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    Color? subtitleColor,
    required bool isDark,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap?.call();
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.emphasisSoftFor(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: AppColors.linkFor(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: subtitleColor ?? AppColors.textSecondaryFor(context),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: AppColors.textTertiaryFor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToRecharge(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RechargePage()),
    );
  }

  void _navigateToWithdraw(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WithdrawPage()),
    );
  }

  void _navigateToTransactions(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TransactionListPage()),
    );
  }

  void _navigateToSetPayPassword(BuildContext context, bool hasPassword) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SetPayPasswordPage(isUpdate: hasPassword),
      ),
    );
  }

  void _showAboutDialog(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.cardFor(context),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.emphasisSoftFor(context),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.account_balance_wallet,
                  size: 32,
                  color: AppColors.linkFor(context),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _walletText(
                  context,
                  zhCN: '钱包',
                  zhTW: '錢包',
                  en: 'Wallet',
                ),
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimaryFor(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'v1.0.0',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondaryFor(context),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                _walletText(
                  context,
                  zhCN: '本钱包仅用于应用内虚拟积分收发，不涉及真实资金交易。',
                  zhTW: '本錢包僅用於應用內虛擬積分收發，不涉及真實資金交易。',
                  en: 'This wallet is only for in-app virtual points and does not involve real-money transactions.',
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondaryFor(context),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryFor(context),
                    foregroundColor: AppColors.onPrimaryFor(context),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _walletText(
                      context,
                      zhCN: '我知道了',
                      zhTW: '我知道了',
                      en: 'Got It',
                    ),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
