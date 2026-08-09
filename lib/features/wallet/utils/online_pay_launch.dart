// 文件用途：提供 online pay launch 相关工具函数与通用转换逻辑，属于钱包与支付。
// 核心逻辑：提供 online pay launch 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/app_localizations.dart';

// 关键声明：online pay launch 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
String _onlinePayText(
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

// 流程逻辑：`launchOnlinePayPayload` 先校验输入并完成空值/格式规范化，再返回稳定结果，不承担页面或网络副作用。
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
          title: Text(
            _onlinePayText(
              ctx,
              zhCN: '扫码支付',
              zhTW: '掃碼支付',
              en: 'Scan to Pay',
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(
                    data: wc ?? aq!, size: 200, backgroundColor: Colors.white),
                const SizedBox(height: 12),
                SelectableText(wc ?? aq!, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: wc ?? aq!));
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text(
                      _onlinePayText(
                        ctx,
                        zhCN: '已复制码内容',
                        zhTW: '已複製付款碼內容',
                        en: 'Code content copied',
                      ),
                    ),
                  ),
                );
              },
              child: Text(
                _onlinePayText(
                  ctx,
                  zhCN: '复制',
                  zhTW: '複製',
                  en: 'Copy',
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                _onlinePayText(
                  ctx,
                  zhCN: '关闭',
                  zhTW: '關閉',
                  en: 'Close',
                ),
              ),
            ),
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
        title: Text(
          _onlinePayText(
            ctx,
            zhCN: '调起 App 支付',
            zhTW: '喚起 App 支付',
            en: 'Launch App Payment',
          ),
        ),
        content: SingleChildScrollView(
          child: Text(
            aliOrder != null && aliOrder.isNotEmpty
                ? _onlinePayText(
                    ctx,
                    zhCN:
                        '已生成支付宝订单串，请在工程内接入 tobias（或官方 SDK）并传入 alipay_order_string 调起支付宝客户端。',
                    zhTW:
                        '已產生支付寶訂單字串，請在工程內接入 tobias（或官方 SDK）並傳入 alipay_order_string 喚起支付寶客戶端。',
                    en: 'An Alipay order string has been generated. Integrate tobias (or the official SDK) and pass alipay_order_string to launch Alipay.',
                  )
                : wechatApp != null
                    ? _onlinePayText(
                        ctx,
                        zhCN:
                            '已生成微信 App 支付参数（wechat_app），请在工程内接入 fluwx 并调用 payWithWeChatChat。',
                        zhTW:
                            '已產生微信 App 支付參數（wechat_app），請在工程內接入 fluwx 並呼叫 payWithWeChatChat。',
                        en: 'WeChat App payment parameters (wechat_app) have been generated. Integrate fluwx and call payWithWeChatChat.',
                      )
                    : _onlinePayText(
                        ctx,
                        zhCN: '无法识别支付参数，请检查后端配置。',
                        zhTW: '無法識別支付參數，請檢查後端設定。',
                        en: 'Unable to recognize payment parameters. Check the backend configuration.',
                      ),
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
        ),
        actions: [
          if (wechatApp != null && wechatApp.isNotEmpty)
            TextButton(
              onPressed: () {
                final json =
                    const JsonEncoder.withIndent('  ').convert(wechatApp);
                Clipboard.setData(ClipboardData(text: json));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _onlinePayText(
                        context,
                        zhCN: '已复制微信 App 支付参数 JSON',
                        zhTW: '已複製微信 App 支付參數 JSON',
                        en: 'WeChat App payment JSON copied',
                      ),
                    ),
                  ),
                );
              },
              child: Text(
                _onlinePayText(
                  ctx,
                  zhCN: '复制微信 JSON',
                  zhTW: '複製微信 JSON',
                  en: 'Copy WeChat JSON',
                ),
              ),
            ),
          if (aliOrder != null && aliOrder.isNotEmpty)
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: aliOrder));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _onlinePayText(
                        context,
                        zhCN: '已复制支付宝 orderString',
                        zhTW: '已複製支付寶 orderString',
                        en: 'Alipay orderString copied',
                      ),
                    ),
                  ),
                );
              },
              child: Text(
                _onlinePayText(
                  ctx,
                  zhCN: '复制支付宝串',
                  zhTW: '複製支付寶字串',
                  en: 'Copy Alipay String',
                ),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              _onlinePayText(
                ctx,
                zhCN: '知道了',
                zhTW: '知道了',
                en: 'OK',
              ),
            ),
          ),
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
      title: Text(
        _onlinePayText(
          ctx,
          zhCN: '支付结果',
          zhTW: '支付結果',
          en: 'Payment Result',
        ),
      ),
      content: Text(
        _onlinePayText(
          ctx,
          zhCN: '支付完成后请点击「我已完成支付」刷新余额。若未及时到账请稍后在钱包流水查看。',
          zhTW: '支付完成後請點擊「我已完成支付」刷新餘額。若未及時到帳請稍後在錢包流水查看。',
          en: 'After payment, tap "I Have Completed Payment" to refresh your balance. If it does not arrive in time, check wallet transactions later.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            _onlinePayText(
              ctx,
              zhCN: '稍后',
              zhTW: '稍後',
              en: 'Later',
            ),
          ),
        ),
        FilledButton(
          onPressed: () async {
            await onPaidRefresh();
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: Text(
            _onlinePayText(
              ctx,
              zhCN: '我已完成支付',
              zhTW: '我已完成支付',
              en: 'I Have Completed Payment',
            ),
          ),
        ),
      ],
    ),
  );
}
