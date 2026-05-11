import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../providers/wallet_provider.dart';
import '../services/wallet_service.dart';

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

  String get _outTradeNo {
    final uri = GoRouterState.of(context).uri;
    return (uri.queryParameters['out_trade_no'] ?? '').trim();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOrder(initial: true));
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
        _error = '缺少订单号，请返回钱包查看交易记录';
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
      final resp = await ref.read(walletServiceProvider).getOnlinePayOrder(outTradeNo);
      if (!mounted) return;
      if (!resp.isSuccess || resp.data == null) {
        setState(() {
          _loading = false;
          _error = resp.message.isNotEmpty ? resp.message : '订单查询失败';
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
        _error = '订单查询失败';
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

  ({IconData icon, Color color, String title, String subtitle}) _statusMeta(bool isDark) {
    final status = (_order?['status'] ?? '').toString();
    switch (status) {
      case 'paid':
        return (
          icon: Icons.check_circle,
          color: const Color(0xFF07C160),
          title: '支付成功',
          subtitle: '充值金额已到账，3 秒后将自动跳转到交易记录。',
        );
      case 'failed':
        return (
          icon: Icons.cancel,
          color: const Color(0xFFE5484D),
          title: '支付失败',
          subtitle: '订单支付未成功，请返回充值页重新发起。',
        );
      case 'closed':
        return (
          icon: Icons.remove_circle,
          color: isDark ? Colors.white54 : const Color(0xFF6B7280),
          title: '订单已关闭',
          subtitle: '该订单已关闭，如仍需充值请重新创建支付订单。',
        );
      default:
        return (
          icon: Icons.hourglass_bottom,
          color: const Color(0xFFF59E0B),
          title: '支付处理中',
          subtitle: '支付宝已返回应用，系统正在确认支付结果，请稍候。',
        );
    }
  }

  String _channelLabel() {
    final channel = (_order?['channel'] ?? '').toString();
    switch (channel) {
      case 'alipay':
        return '支付宝';
      case 'wechat':
        return '微信支付';
      default:
        return channel.isEmpty ? '-' : channel;
    }
  }

  String _amountLabel() {
    final amount = _order?['amount'];
    if (amount is num) {
      return '¥${amount.toStringAsFixed(2)}';
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
          '支付结果',
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
                        _error == null ? meta.title : '暂时无法确认支付结果',
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
                      if (_error == null && (_order?['status'] ?? '').toString() == 'paid') ...[
                        const SizedBox(height: 10),
                        Text(
                          '$_redirectSeconds 秒后自动跳转到交易记录',
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
                            color: isDark ? const Color(0xFF232326) : const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            children: [
                              _infoRow('订单号', _outTradeNo, textColor, subColor),
                              const SizedBox(height: 12),
                              _infoRow('支付方式', _channelLabel(), textColor, subColor),
                              const SizedBox(height: 12),
                              _infoRow('充值金额', _amountLabel(), textColor, subColor),
                              const SizedBox(height: 12),
                              _infoRow('创建时间', _timeLabel('created_at'), textColor, subColor),
                              if ((_order?['paid_at']?.toString() ?? '').isNotEmpty) ...[
                                const SizedBox(height: 12),
                                _infoRow('支付时间', _timeLabel('paid_at'), textColor, subColor),
                              ],
                              const SizedBox(height: 12),
                              _infoRow('当前状态', meta.title, textColor, subColor),
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
                            backgroundColor: (_order?['status'] ?? '').toString() == 'paid'
                                ? const Color(0xFF07C160)
                                : AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          label: Text(
                            (_order?['status'] ?? '').toString() == 'paid'
                                ? '立即查看交易记录'
                                : '查看交易记录',
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
                          child: const Text('刷新状态'),
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
                            (_order?['status'] ?? '').toString() == 'paid' ? '完成' : '返回钱包',
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
