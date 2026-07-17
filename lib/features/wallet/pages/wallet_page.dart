import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/wallet_provider.dart';
import '../services/wallet_service.dart';
import 'set_pay_password_page.dart';
import 'recharge_page.dart';
import 'withdraw_page.dart';
import 'transaction_list_page.dart';

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
    try {
      final prefs = await SharedPreferences.getInstance();
      _dismissedOrderIds = (prefs.getStringList(_dismissedKey) ?? []).toSet();
    } catch (_) {}
    _loadOrders();
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
      final svc = ref.read(walletServiceProvider);
      final resp = await svc.getWalletSettings();
      if (resp.isSuccess && resp.data != null && mounted) {
        setState(() => _walletNotice = resp.data!.walletNotice);
      }
    } catch (_) {}
  }

  Future<void> _loadOrders() async {
    // Web 端不支持充值，跳过加载订单
    if (kIsWeb) return;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final walletState = ref.watch(walletProvider);
    final wallet = walletState.wallet;

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F7),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        title: const Text(
          '钱包',
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
        color: AppColors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // 余额卡片
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                decoration: BoxDecoration(
                  color: AppColors.primary,
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
                          '账户余额',
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
                                '¥',
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

                    // ===== 修改部分：只显示提现和账单按钮 =====
                    Row(
                      children: [
                        // 充值按钮
                        // Expanded(
                        //   child: _buildActionButton(
                        //     icon: Icons.arrow_downward,
                        //     label: '充值',
                        //     onTap: () => _navigateToRecharge(context),
                        //   ),
                        // ),
                        // 提现按钮
                        Expanded(
                          child: _buildActionButton(
                            icon: Icons.arrow_upward,
                            label: '提现',
                            onTap: () => _navigateToWithdraw(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 账单按钮
                        Expanded(
                          child: _buildActionButton(
                            icon: Icons.receipt_long,
                            label: '账单',
                            onTap: () => _navigateToTransactions(context),
                          ),
                        ),
                      ],
                    ),
                    // ===== 修改结束 =====
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
                      color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.campaign_outlined,
                          color: AppColors.primary,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _walletNotice,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? Colors.white70 : Colors.black87,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // 充值/提现进度（Web 端隐藏）
              if (!kIsWeb)
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
                      final method = o['method_name'] as String? ?? '充值';
                      final remark = o['remark'] as String? ?? '';
                      final createdAt = o['created_at']?.toString() ?? '';

                      Color statusColor;
                      IconData statusIcon;
                      String statusText;
                      String subtitle;

                      if (status == 'pending') {
                        statusColor = const Color(0xFFE6A23C);
                        statusIcon = Icons.schedule;
                        statusText = '审核中';
                        subtitle = '等待管理员审核';
                      } else if (status == 'approved') {
                        statusColor = const Color(0xFF67C23A);
                        statusIcon = Icons.check_circle;
                        statusText = '已到账';
                        subtitle = '充值成功';
                      } else {
                        statusColor = const Color(0xFFF56C6C);
                        statusIcon = Icons.cancel;
                        statusText = '已拒绝';
                        subtitle = remark.isNotEmpty ? remark : '充值被拒绝';
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
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.delete_outline,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  '删除',
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
                              color: isDark
                                  ? const Color(0xFF2C2C2E)
                                  : Colors.white,
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
                                        '$method · ¥${amount.toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        subtitle,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? Colors.white38
                                              : Colors.grey,
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
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
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
            title: '支付密码',
            subtitle: wallet?.hasPayPassword == true ? '已设置' : '未设置',
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
            color: isDark ? Colors.white10 : Colors.grey[100],
          ),

          // 关于钱包
          _buildSettingTile(
            context,
            icon: Icons.info_outline,
            title: '关于钱包',
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
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
              if (subtitle.isNotEmpty) ...[
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: subtitleColor ??
                        (isDark ? Colors.white54 : Colors.grey[500]),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                Icons.arrow_forward_ios,
                size: 14,
                color: isDark ? Colors.white24 : Colors.grey[400],
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
            color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.account_balance_wallet,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '锦绣汇钱包',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'v1.0.0',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white54 : Colors.grey[500],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '本钱包仅用于应用内虚拟积分收发，不涉及真实资金交易。',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white60 : Colors.grey[600],
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
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    '我知道了',
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
