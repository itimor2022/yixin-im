import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// 根据后端 `/wallet/online-pay/create` 返回结果调起支付或展示二维码。
Future<void> launchOnlinePayPayload(
  BuildContext context,
  Map<String, dynamic> data, {
  required Future<void> Function() onPaidRefresh,
}) async {
  final h5 = data['wechat_h5_url'] as String?;
  final page = data['alipay_pay_url'] as String?;
  if (h5 != null && h5.isNotEmpty) {
    await _openExternal(Uri.parse(h5));
    if (context.mounted) await _pollPaidDialog(context, data, onPaidRefresh);
    return;
  }
  if (page != null && page.isNotEmpty) {
    await _openExternal(Uri.parse(page));
    if (context.mounted) await _pollPaidDialog(context, data, onPaidRefresh);
    return;
  }

  final wc = data['wechat_code_url'] as String?;
  final aq = data['alipay_qr_code'] as String?;
  if ((wc != null && wc.isNotEmpty) || (aq != null && aq.isNotEmpty)) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('扫码支付'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(data: wc ?? aq!, size: 200, backgroundColor: Colors.white),
                const SizedBox(height: 12),
                SelectableText(wc ?? aq!, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: wc ?? aq!));
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('已复制码内容')));
              },
              child: const Text('复制'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
          ],
        ),
      );
    }
    if (context.mounted) await _pollPaidDialog(context, data, onPaidRefresh);
    return;
  }

  final aliOrder = data['alipay_order_string'] as String?;
  final wechatApp = data['wechat_app'] as Map<String, dynamic>?;
  if (context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('调起 App 支付'),
        content: SingleChildScrollView(
          child: Text(
            aliOrder != null && aliOrder.isNotEmpty
                ? '已生成支付宝订单串，请在工程内接入 tobias（或官方 SDK）并传入 alipay_order_string 调起支付宝客户端。'
                : wechatApp != null
                    ? '已生成微信 App 支付参数（wechat_app），请在工程内接入 fluwx 并调用 payWithWeChatChat。'
                    : '无法识别支付参数，请检查后端配置。',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
        actions: [
          if (wechatApp != null && wechatApp.isNotEmpty)
            TextButton(
              onPressed: () {
                final json = const JsonEncoder.withIndent('  ').convert(wechatApp);
                Clipboard.setData(ClipboardData(text: json));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制微信 App 支付参数 JSON')));
              },
              child: const Text('复制微信 JSON'),
            ),
          if (aliOrder != null && aliOrder.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: aliOrder));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制支付宝 orderString')));
              },
              child: const Text('复制支付宝串'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('知道了')),
        ],
      ),
    );
  }
  if (context.mounted) await _pollPaidDialog(context, data, onPaidRefresh);
}

Future<void> _openExternal(Uri u) async {
  if (await canLaunchUrl(u)) {
    await launchUrl(u, mode: LaunchMode.externalApplication);
  }
}

Future<void> _pollPaidDialog(
  BuildContext context,
  Map<String, dynamic> data,
  Future<void> Function() onPaidRefresh,
) async {
  final out = data['out_trade_no'] as String?;
  if (out == null || out.isEmpty) return;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('支付结果'),
      content: const Text('支付完成后请点击「我已完成支付」刷新余额。若未及时到账请稍后在钱包流水查看。'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('稍后')),
        FilledButton(
          onPressed: () async {
            await onPaidRefresh();
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('我已完成支付'),
        ),
      ],
    ),
  );
}
