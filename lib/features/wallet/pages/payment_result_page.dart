// 文件用途：实现 PaymentResultPage 页面及其交互流程，属于钱包与支付。
// 核心逻辑：维护 PaymentResultPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/wallet_provider.dart';
import '../services/wallet_service.dart';

String _paymentResultText(
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

// 关键声明：payment result page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class PaymentResultPage extends ConsumerStatefulWidget {
  const PaymentResultPage({super.key});

  @override
  ConsumerState<PaymentResultPage> createState() => _PaymentResultPageState();
}

class _PaymentResultPageState extends ConsumerState<PaymentResultPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _order;
  Timer? _pollTimer;
  Timer? _successRedirectTimer;
  int _redirectSeconds = 3;
  String get _currency => ref.read(walletCurrencyProvider);

  String get _outTradeNo {
    final uri = GoRouterState.of(context).uri;
    return (uri.queryParameters['out_trade_no'] ?? '').trim();
  }

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _loadOrder(initial: true));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _successRedirectTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadOrder({bool initial = false}) async {
    final outTradeNo = _outTradeNo;
    if (outTradeNo.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _paymentResultText(
          context,
          zhCN: '缺少订单号，请返回钱包查看交易记录',
          zhTW: '缺少訂單號，請返回錢包查看交易記錄',
          en: 'Missing order number. Please return to Wallet and check transaction history.',
        );
      });
      return;
    }

    if (initial && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final resp =
          await ref.read(walletServiceProvider).getOnlinePayOrder(outTradeNo);
      if (!mounted) return;
      if (!resp.isSuccess || resp.data == null) {
        setState(() {
          _loading = false;
          _error = localizeServerMessage(
            resp.message,
            fallbackZhCN: '订单查询失败',
            fallbackZhTW: '訂單查詢失敗',
            fallbackEn: 'Failed to query order',
          );
        });
        return;
      }

      final status = (resp.data!['status'] ?? '').toString();
      setState(() {
        _loading = false;
        _error = null;
        _order = resp.data;
      });

      if (status == 'paid') {
        _pollTimer?.cancel();
        _startSuccessRedirect();
        await ref.read(walletProvider.notifier).loadWallet(silent: true);
      } else {
        _successRedirectTimer?.cancel();
        _successRedirectTimer = null;
        if (mounted && _redirectSeconds != 3) {
          setState(() {
            _redirectSeconds = 3;
          });
        }
        _startPolling();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _paymentResultText(
          context,
          zhCN: '订单查询失败',
          zhTW: '訂單查詢失敗',
          en: 'Failed to query order',
        );
      });
    }
  }

  void _startPolling() {
    _pollTimer ??= Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      final status = (_order?['status'] ?? '').toString();
      if (status == 'paid') {
        _pollTimer?.cancel();
        _pollTimer = null;
        return;
      }
      await _loadOrder();
    });
  }

  void _startSuccessRedirect() {
    if (_successRedirectTimer != null) return;
    setState(() {
      _redirectSeconds = 3;
    });
    _successRedirectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_redirectSeconds <= 1) {
        timer.cancel();
        _successRedirectTimer = null;
        context.go('/wallet/transactions');
        return;
      }
      setState(() {
        _redirectSeconds -= 1;
      });
    });
  }

  ({IconData icon, Color color, String title, String subtitle}) _statusMeta(
      bool isDark) {
    final status = (_order?['status'] ?? '').toString();
    switch (status) {
      case 'paid':
        return (
          icon: Icons.check_circle,
          color: const Color(0xFF07C160),
          title: _paymentResultText(
            context,
            zhCN: '支付成功',
            zhTW: '支付成功',
            en: 'Payment Successful',
          ),
          subtitle: _paymentResultText(
            context,
            zhCN: '充值金额已到账，3 秒后将自动跳转到交易记录。',
            zhTW: '充值金額已到帳，3 秒後將自動跳轉到交易記錄。',
            en: 'The recharge amount has arrived. Redirecting to transaction history in 3 seconds.',
          ),
        );
      case 'failed':
        return (
          icon: Icons.cancel,
          color: const Color(0xFFE5484D),
          title: _paymentResultText(
            context,
            zhCN: '支付失败',
            zhTW: '支付失敗',
            en: 'Payment Failed',
          ),
          subtitle: _paymentResultText(
            context,
            zhCN: '订单支付未成功，请返回充值页重新发起。',
            zhTW: '訂單支付未成功，請返回充值頁重新發起。',
            en: 'The payment was not successful. Please return to the recharge page and try again.',
          ),
        );
      case 'closed':
        return (
          icon: Icons.remove_circle,
          color: AppColors.textSecondaryFor(context),
          title: _paymentResultText(
            context,
            zhCN: '订单已关闭',
            zhTW: '訂單已關閉',
            en: 'Order Closed',
          ),
          subtitle: _paymentResultText(
            context,
            zhCN: '该订单已关闭，如仍需充值请重新创建支付订单。',
            zhTW: '該訂單已關閉，如仍需充值請重新建立支付訂單。',
            en: 'This order has been closed. Create a new payment order if you still need to recharge.',
          ),
        );
      default:
        return (
          icon: Icons.hourglass_bottom,
          color: const Color(0xFFF59E0B),
          title: _paymentResultText(
            context,
            zhCN: '支付处理中',
            zhTW: '支付處理中',
            en: 'Processing Payment',
          ),
          subtitle: _paymentResultText(
            context,
            zhCN: '支付宝已返回应用，系统正在确认支付结果，请稍候。',
            zhTW: '支付寶已返回應用，系統正在確認支付結果，請稍候。',
            en: 'The app has returned from Alipay. The system is confirming the payment result. Please wait.',
          ),
        );
    }
  }

  String _channelLabel() {
    final channel = (_order?['channel'] ?? '').toString();
    switch (channel) {
      case 'alipay':
        return _paymentResultText(
          context,
          zhCN: '支付宝',
          zhTW: '支付寶',
          en: 'Alipay',
        );
      case 'wechat':
        return _paymentResultText(
          context,
          zhCN: '微信支付',
          zhTW: '微信支付',
          en: 'WeChat Pay',
        );
      default:
        return channel.isEmpty ? '-' : channel;
    }
  }

  String _amountLabel() {
    final amount = _order?['amount'];
    if (amount is num) {
      return '$_currency${amount.toStringAsFixed(2)}';
    }
    return '-';
  }

  String _displayAmountLabel() {
    final amount = _order?['amount'];
    if (amount is num) {
      return '$_currency${amount.toStringAsFixed(2)}';
    }
    return '-';
  }

  String _timeLabel(String key) {
    final raw = _order?[key]?.toString() ?? '';
    if (raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    final hh = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    final ss = local.second.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd $hh:$mi:$ss';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(walletCurrencyProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark ? Colors.white60 : const Color(0xFF6B7280);
    final cardColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F7);
    final meta = _statusMeta(isDark);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        elevation: 0,
        centerTitle: true,
        title: Text(
          _paymentResultText(
            context,
            zhCN: '支付结果',
            zhTW: '支付結果',
            en: 'Payment Result',
          ),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: textColor),
          onPressed: () => context.go('/wallet'),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(24),
              boxShadow: isDark
                  ? null
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
            ),
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: meta.color.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(meta.icon, size: 38, color: meta.color),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        _error == null
                            ? meta.title
                            : _paymentResultText(
                                context,
                                zhCN: '暂时无法确认支付结果',
                                zhTW: '暫時無法確認支付結果',
                                en: 'Unable to confirm payment result for now',
                              ),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _error ?? meta.subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: subColor,
                        ),
                      ),
                      if (_error == null &&
                          (_order?['status'] ?? '').toString() == 'paid') ...[
                        const SizedBox(height: 10),
                        Text(
                          _paymentResultText(
                            context,
                            zhCN: '$_redirectSeconds 秒后自动跳转到交易记录',
                            zhTW: '$_redirectSeconds 秒後自動跳轉到交易記錄',
                            en: 'Redirecting to transaction history in $_redirectSeconds seconds',
                          ),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: meta.color,
                          ),
                        ),
                      ],
                      if (_order != null) ...[
                        const SizedBox(height: 24),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF232326)
                                : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              _infoRow(
                                _paymentResultText(
                                  context,
                                  zhCN: '订单号',
                                  zhTW: '訂單號',
                                  en: 'Order No.',
                                ),
                                _outTradeNo,
                                textColor,
                                subColor,
                              ),
                              const SizedBox(height: 12),
                              _infoRow(
                                _paymentResultText(
                                  context,
                                  zhCN: '支付方式',
                                  zhTW: '支付方式',
                                  en: 'Payment Method',
                                ),
                                _channelLabel(),
                                textColor,
                                subColor,
                              ),
                              const SizedBox(height: 12),
                              _infoRow(
                                _paymentResultText(
                                  context,
                                  zhCN: '充值金额',
                                  zhTW: '充值金額',
                                  en: 'Recharge Amount',
                                ),
                                _displayAmountLabel(),
                                textColor,
                                subColor,
                              ),
                              const SizedBox(height: 12),
                              _infoRow(
                                _paymentResultText(
                                  context,
                                  zhCN: '创建时间',
                                  zhTW: '建立時間',
                                  en: 'Created At',
                                ),
                                _timeLabel('created_at'),
                                textColor,
                                subColor,
                              ),
                              if ((_order?['paid_at']?.toString() ?? '')
                                  .isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _infoRow(
                                  _paymentResultText(
                                    context,
                                    zhCN: '支付时间',
                                    zhTW: '支付時間',
                                    en: 'Paid At',
                                  ),
                                  _timeLabel('paid_at'),
                                  textColor,
                                  subColor,
                                ),
                              ],
                              const SizedBox(height: 12),
                              _infoRow(
                                _paymentResultText(
                                  context,
                                  zhCN: '当前状态',
                                  zhTW: '目前狀態',
                                  en: 'Current Status',
                                ),
                                meta.title,
                                textColor,
                                subColor,
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => context.go('/wallet/transactions'),
                          icon: Icon(
                            (_order?['status'] ?? '').toString() == 'paid'
                                ? Icons.receipt_long
                                : Icons.refresh,
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                (_order?['status'] ?? '').toString() == 'paid'
                                    ? const Color(0xFF07C160)
                                    : AppColors.controlActiveFor(context),
                            foregroundColor:
                                (_order?['status'] ?? '').toString() == 'paid'
                                    ? Colors.white
                                    : AppColors.onControlActiveFor(context),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          label: Text(
                            (_order?['status'] ?? '').toString() == 'paid'
                                ? _paymentResultText(
                                    context,
                                    zhCN: '立即查看交易记录',
                                    zhTW: '立即查看交易記錄',
                                    en: 'View Transaction History Now',
                                  )
                                : _paymentResultText(
                                    context,
                                    zhCN: '查看交易记录',
                                    zhTW: '查看交易記錄',
                                    en: 'View Transaction History',
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => _loadOrder(initial: true),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            _paymentResultText(
                              context,
                              zhCN: '刷新状态',
                              zhTW: '重新整理狀態',
                              en: 'Refresh Status',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => context.go('/wallet'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Text(
                            (_order?['status'] ?? '').toString() == 'paid'
                                ? _paymentResultText(
                                    context,
                                    zhCN: '完成',
                                    zhTW: '完成',
                                    en: 'Done',
                                  )
                                : _paymentResultText(
                                    context,
                                    zhCN: '返回钱包',
                                    zhTW: '返回錢包',
                                    en: 'Back to Wallet',
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

  Widget _infoRow(String label, String value, Color textColor, Color subColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: subColor),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }
}
