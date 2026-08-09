// 文件用途：实现 RechargePage 页面及其交互流程，属于钱包与支付。
// 核心逻辑：维护 RechargePage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/system_ui_styles.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/services/api/api_client.dart'
    show ApiConfig, ApiResponse, apiClientProvider;
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../settings/pages/bind_phone_page.dart';
import '../../../core/services/upload_service.dart';
import '../providers/wallet_provider.dart';
import '../services/wallet_service.dart';
import '../utils/online_pay_launch.dart';

String _rechargeText(
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

bool _rechargeContainsHan(String value) {
  return RegExp(r'[\u4e00-\u9fff]').hasMatch(value);
}

String _localizedRechargeMethodName(
    BuildContext context, RechargeMethod method) {
  if (AppLocalizations.of(context).language != AppLanguage.en) {
    return method.name;
  }
  final rawName = method.name.trim();
  final type = method.type.trim().toLowerCase();
  final fingerprint = '$rawName $type'.toLowerCase();
  if (fingerprint.contains('alipay') || rawName.contains('支付宝')) {
    return 'Alipay';
  }
  if (fingerprint.contains('wechat') ||
      fingerprint.contains('weixin') ||
      rawName.contains('微信')) {
    return 'WeChat Pay';
  }
  if (fingerprint.contains('bank') || rawName.contains('银行')) {
    return 'Bank Transfer';
  }
  if (fingerprint.contains('qrcode') || fingerprint.contains('qr')) {
    return 'QR Code Payment';
  }
  if (rawName.isNotEmpty && !_rechargeContainsHan(rawName)) {
    return rawName;
  }
  return type == 'bank'
      ? 'Bank Transfer'
      : type == 'qrcode'
          ? 'QR Code Payment'
          : 'Payment Method';
}

// 关键声明：recharge page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class RechargePage extends ConsumerStatefulWidget {
  const RechargePage({super.key});
  @override
  ConsumerState<RechargePage> createState() => _RechargePageState();
}

class _RechargePageState extends ConsumerState<RechargePage> {
  final _amountController = TextEditingController();
  final _remarkController = TextEditingController();
  int _selectedAmountIndex = -1;
  bool _isLoading = false;
  bool _isLoadingData = true;
  bool _isUploading = false;

  List<RechargeMethod> _methods = [];
  RechargeMethod? _selectedMethod;
  String _rechargeNotice = '';
  String? _proofImageUrl;

  bool _onlineEnabled = false;
  bool _onlineWechat = false;
  bool _onlineAlipay = false;

  /// 与后端 `/wallet/online-pay/options` 的 require_phone_bind 一致（不依赖仅系统设置接口）
  bool _onlineOptionsRequirePhone = false;

  final _quickAmounts = [10, 50, 100, 200, 500, 1000];
  String get _currency => ref.read(walletCurrencyProvider);

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _remarkController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final svc = ref.read(walletServiceProvider);
    try {
      try {
        await ref.read(systemSettingsProvider.future);
      } catch (_) {}
      final results = await Future.wait([
        svc.getWalletSettings(),
        svc.getRechargeMethods(),
        svc.getOnlinePayOptions(),
      ]);
      if (!mounted) return;
      final sr = results[0] as ApiResponse<WalletSettings>;
      final mr = results[1] as ApiResponse<List<RechargeMethod>>;
      final or = results[2] as ApiResponse<Map<String, dynamic>>;
      setState(() {
        if (sr.isSuccess && sr.data != null)
          _rechargeNotice = sr.data!.rechargeNotice;
        if (mr.isSuccess && mr.data != null) {
          _methods = mr.data!;
          if (_methods.isNotEmpty) _selectedMethod = _methods.first;
        }
        if (or.isSuccess && or.data != null) {
          final d = or.data!;
          _onlineEnabled = d['enabled'] == true;
          _onlineWechat = d['wechat_enabled'] == true;
          _onlineAlipay = d['alipay_enabled'] == true;
          _onlineOptionsRequirePhone = d['require_phone_bind'] == true;
        }
        _isLoadingData = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingData = false);
    }
  }

  double get _amount {
    if (_selectedAmountIndex >= 0)
      return _quickAmounts[_selectedAmountIndex].toDouble();
    return double.tryParse(_amountController.text) ?? 0;
  }

  Future<void> _pickProofImage() async {
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;
    setState(() => _isUploading = true);
    try {
      final url =
          await UploadService(ref.read(apiClientProvider)).uploadImage(file);
      if (url != null && mounted) {
        setState(() => _proofImageUrl = url);
      } else {
        _msg(
          _rechargeText(
            context,
            zhCN: '上传失败',
            zhTW: '上傳失敗',
            en: 'Upload failed',
          ),
        );
      }
    } catch (_) {
      _msg(
        _rechargeText(
          context,
          zhCN: '上传失败',
          zhTW: '上傳失敗',
          en: 'Upload failed',
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _submit() async {
    if (_amount <= 0) {
      _msg(
        _rechargeText(
          context,
          zhCN: '请输入充值金额',
          zhTW: '請輸入充值金額',
          en: 'Enter a recharge amount',
        ),
      );
      return;
    }
    if (_methods.isNotEmpty && _selectedMethod == null) {
      _msg(
        _rechargeText(
          context,
          zhCN: '请选择充值方式',
          zhTW: '請選擇充值方式',
          en: 'Select a recharge method',
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    if (_methods.isNotEmpty && _selectedMethod != null) {
      try {
        final resp = await ref.read(walletServiceProvider).createRechargeOrder(
              methodId: _selectedMethod!.id,
              amount: _amount,
              proofImage: _proofImageUrl,
              remark: _remarkController.text.trim(),
            );
        if (mounted) {
          setState(() => _isLoading = false);
          if (resp.isSuccess)
            _showSuccess();
          else
            _msg(resp.message);
        }
      } catch (_) {
        if (mounted) {
          setState(() => _isLoading = false);
          _msg(
            _rechargeText(
              context,
              zhCN: '提交失败',
              zhTW: '提交失敗',
              en: 'Submit failed',
            ),
          );
        }
      }
    } else {
      // 无充值方式时禁止提交，避免绕过审核直接加余额
      setState(() => _isLoading = false);
      _msg(
        _rechargeText(
          context,
          zhCN: '暂无可用充值方式，请联系管理员配置',
          zhTW: '暫無可用充值方式，請聯絡管理員設定',
          en: 'No recharge methods are available. Contact the administrator.',
        ),
      );
    }
  }

  void _msg(String s) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(s),
        behavior: SnackBarBehavior.floating,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))));
  }

  void _showSuccess() {
    final dk = Theme.of(context).brightness == Brightness.dark;
    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                      color: dk ? const Color(0xFF2C2C2E) : Colors.white,
                      borderRadius: BorderRadius.circular(20)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                            color: const Color(0xFF34C759).withOpacity(0.1),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.check,
                            size: 32, color: Color(0xFF34C759))),
                    const SizedBox(height: 14),
                    Text(
                      _rechargeText(
                        context,
                        zhCN: '充值申请已提交',
                        zhTW: '充值申請已提交',
                        en: 'Recharge request submitted',
                      ),
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: dk ? Colors.white : Colors.black87),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _rechargeText(
                        context,
                        zhCN: '等待管理员审核，通过后自动到账',
                        zhTW: '等待管理員審核，通過後自動到帳',
                        en: 'Waiting for admin approval. The balance will update automatically after approval.',
                      ),
                      style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondaryFor(context)),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryFor(context),
                                foregroundColor:
                                    AppColors.onPrimaryFor(context),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                elevation: 0),
                            child: Text(
                              _rechargeText(
                                context,
                                zhCN: '完成',
                                zhTW: '完成',
                                en: 'Done',
                              ),
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600),
                            ))),
                  ])),
            ));
  }

  void _previewImage(String url) {
    Navigator.of(context).push(PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (_, __, ___) => DarkSystemUiScope(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Scaffold(
                  backgroundColor: Colors.black87,
                  body: Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4,
                      child: Image.network(url, fit: BoxFit.contain),
                    ),
                  ),
                ),
              ),
            )));
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.lightImpact();
    _msg(
      _rechargeText(
        context,
        zhCN: '$label 已复制',
        zhTW: '$label 已複製',
        en: '$label copied',
      ),
    );
  }

  Future<void> _startOnlinePay(String channel) async {
    final asyncSt = ref.read(systemSettingsProvider);
    final settings = asyncSt.valueOrNull;
    final user = ref.read(authServiceProvider).user;
    final needPhone = _onlineOptionsRequirePhone ||
        (settings != null && settings.requirePhoneBind);
    final noPhone = user == null || (user.phone ?? '').trim().isEmpty;
    if (needPhone && noPhone) {
      final smsReady = settings?.smsBindReady ?? false;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final dk = Theme.of(ctx).brightness == Brightness.dark;
          return AlertDialog(
            backgroundColor: dk ? const Color(0xFF2C2C2E) : Colors.white,
            title: Text(
              _rechargeText(
                ctx,
                zhCN: '需要绑定手机',
                zhTW: '需要綁定手機',
                en: 'Phone Binding Required',
              ),
              style: TextStyle(color: dk ? Colors.white : Colors.black87),
            ),
            content: Text(
              smsReady
                  ? _rechargeText(
                      ctx,
                      zhCN: '根据系统设置，使用在线支付前需先绑定手机号。',
                      zhTW: '根據系統設定，使用線上支付前需先綁定手機號。',
                      en: 'Based on system settings, you must bind a phone number before using online payment.',
                    )
                  : _rechargeText(
                      ctx,
                      zhCN: '系统要求绑定手机号后才能在线支付，但短信服务未就绪，请联系管理员开启短信网关。',
                      zhTW: '系統要求綁定手機號後才能線上支付，但簡訊服務尚未就緒，請聯絡管理員開啟簡訊網關。',
                      en: 'Online payment requires a bound phone number, but SMS service is not ready. Contact the administrator.',
                    ),
              style: TextStyle(
                  color: dk ? Colors.white70 : Colors.black87, height: 1.35),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  _rechargeText(
                    ctx,
                    zhCN: '取消',
                    zhTW: '取消',
                    en: 'Cancel',
                  ),
                ),
              ),
              if (smsReady)
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    _rechargeText(
                      ctx,
                      zhCN: '去绑定',
                      zhTW: '去綁定',
                      en: 'Bind Now',
                    ),
                  ),
                ),
            ],
          );
        },
      );
      if (go == true && mounted) {
        final bound = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const BindPhonePage()),
        );
        if (bound == true && mounted) {
          await ref.read(authServiceProvider.notifier).getCurrentUser();
        }
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final r = await ref.read(walletServiceProvider).createOnlinePay(
            amount: _amount,
            channel: channel,
            clientPlatform: PlatformUtils.deviceType,
          );
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (!r.isSuccess || r.data == null) {
        _msg(r.message);
        return;
      }
      await launchOnlinePayPayload(
        context,
        r.data!,
        onPaidRefresh: () =>
            ref.read(walletProvider.notifier).loadWallet(silent: true),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
        _msg(
          _rechargeText(
            context,
            zhCN: '支付发起失败',
            zhTW: '支付發起失敗',
            en: 'Failed to start payment',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(walletCurrencyProvider);
    final dk = Theme.of(context).brightness == Brightness.dark;
    final bg = dk ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final card = dk ? const Color(0xFF2C2C2E) : Colors.white;
    final sub = AppColors.textSecondaryFor(context);
    final txt = dk ? Colors.white : const Color(0xFF1C1C1E);
    final bal = ref.watch(walletProvider).wallet?.balance ?? 0;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
          backgroundColor: dk ? const Color(0xFF1C1C1E) : Colors.white,
          elevation: 0,
          centerTitle: true,
          title: Text(
            _rechargeText(
              context,
              zhCN: '充值',
              zhTW: '充值',
              en: 'Recharge',
            ),
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, color: txt),
          ),
          leading: IconButton(
              icon: Icon(Icons.arrow_back_ios, size: 20, color: txt),
              onPressed: () => Navigator.pop(context))),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // 公告
                if (_rechargeNotice.isNotEmpty) ...[
                  Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline,
                                color: Color(0xFFE6A23C), size: 15),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(_rechargeNotice,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: Color(0xFF996600),
                                        height: 1.4))),
                          ])),
                  const SizedBox(height: 12),
                ],

                // 充值方式
                if (_methods.isNotEmpty) ...[
                  _label(
                    _rechargeText(
                      context,
                      zhCN: '选择充值方式',
                      zhTW: '選擇充值方式',
                      en: 'Select Recharge Method',
                    ),
                    sub,
                  ),
                  const SizedBox(height: 8),
                  _card(card, child: _methodSelector(dk, card, txt, sub)),
                  const SizedBox(height: 16),
                ],

                // 收款信息
                if (_selectedMethod != null) ...[
                  _card(card,
                      child: _paymentInfo(_selectedMethod!, dk, txt, sub)),
                  const SizedBox(height: 16),
                ],

                // 金额
                _label(
                  _rechargeText(
                    context,
                    zhCN: '充值金额',
                    zhTW: '充值金額',
                    en: 'Recharge Amount',
                  ),
                  sub,
                ),
                const SizedBox(height: 8),
                _card(card,
                    child: Column(children: [
                      // 快捷金额
                      Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: List.generate(_quickAmounts.length, (i) {
                            final sel = _selectedAmountIndex == i;
                            return GestureDetector(
                              onTap: () => setState(() {
                                _selectedAmountIndex = i;
                                _amountController.clear();
                              }),
                              child: Container(
                                width: (MediaQuery.of(context).size.width -
                                        32 -
                                        32 -
                                        20) /
                                    3,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: sel
                                      ? AppColors.emphasisSoftFor(context)
                                      : (dk
                                          ? Colors.white.withOpacity(0.05)
                                          : const Color(0xFFF5F5F5)),
                                  borderRadius: BorderRadius.circular(10),
                                  border: sel
                                      ? Border.all(
                                          color: AppColors.controlActiveFor(
                                              context),
                                          width: 1.5)
                                      : null,
                                ),
                                child: Center(
                                    child: Text('$_currency${_quickAmounts[i]}',
                                        style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: sel
                                                ? AppColors.linkFor(context)
                                                : txt))),
                              ),
                            );
                          })),
                      const SizedBox(height: 12),
                      // 自定义
                      Container(
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                            color: dk
                                ? Colors.white.withOpacity(0.05)
                                : const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(10)),
                        child: Row(children: [
                          Text(_currency,
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.linkFor(context))),
                          const SizedBox(width: 8),
                          Expanded(
                              child: TextField(
                                  controller: _amountController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: txt),
                                  decoration: InputDecoration(
                                      border: InputBorder.none,
                                      hintText: _rechargeText(
                                        context,
                                        zhCN: '输入其他金额',
                                        zhTW: '輸入其他金額',
                                        en: 'Enter another amount',
                                      ),
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                      hintStyle: TextStyle(
                                          color: sub,
                                          fontWeight: FontWeight.normal,
                                          fontSize: 15)),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.allow(
                                        RegExp(r'^\d*\.?\d{0,2}'))
                                  ],
                                  onChanged: (v) {
                                    if (v.isNotEmpty)
                                      setState(() => _selectedAmountIndex = -1);
                                  })),
                        ]),
                      ),
                    ])),

                if (_onlineEnabled && (_onlineWechat || _onlineAlipay)) ...[
                  const SizedBox(height: 16),
                  _label(
                    _rechargeText(
                      context,
                      zhCN: '在线支付（微信 / 支付宝）',
                      zhTW: '線上支付（微信 / 支付寶）',
                      en: 'Online Payment (WeChat / Alipay)',
                    ),
                    sub,
                  ),
                  const SizedBox(height: 8),
                  _card(card,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _rechargeText(
                              context,
                              zhCN:
                                  '直达官方收银台，适用于 ${PlatformUtils.platformName}；需已设置支付密码',
                              zhTW:
                                  '直達官方收銀台，適用於 ${PlatformUtils.platformName}；需已設定支付密碼',
                              en: 'Go directly to the official cashier for ${PlatformUtils.platformName}; a payment password must be set.',
                            ),
                            style: TextStyle(
                                fontSize: 13, color: sub, height: 1.35),
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            if (_onlineWechat)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _amount <= 0 || _isLoading
                                      ? null
                                      : () => _startOnlinePay('wechat'),
                                  icon:
                                      const Icon(Icons.chat_rounded, size: 18),
                                  label: Text(
                                    _rechargeText(
                                      context,
                                      zhCN: '微信支付',
                                      zhTW: '微信支付',
                                      en: 'WeChat Pay',
                                    ),
                                  ),
                                ),
                              ),
                            if (_onlineWechat && _onlineAlipay)
                              const SizedBox(width: 10),
                            if (_onlineAlipay)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _amount <= 0 || _isLoading
                                      ? null
                                      : () => _startOnlinePay('alipay'),
                                  icon: const Icon(
                                      Icons.account_balance_wallet_outlined,
                                      size: 18),
                                  label: Text(
                                    _rechargeText(
                                      context,
                                      zhCN: '支付宝',
                                      zhTW: '支付寶',
                                      en: 'Alipay',
                                    ),
                                  ),
                                ),
                              ),
                          ]),
                        ],
                      )),
                ],

                // 付款信息
                if (_methods.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _label(
                    _rechargeText(
                      context,
                      zhCN: '付款凭证',
                      zhTW: '付款憑證',
                      en: 'Payment Proof',
                    ),
                    sub,
                  ),
                  const SizedBox(height: 8),
                  _card(card,
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 截图上传
                            GestureDetector(
                              onTap: _isUploading ? null : _pickProofImage,
                              child: _proofImageUrl != null
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Stack(children: [
                                        GestureDetector(
                                            onTap: () => _previewImage(
                                                ApiConfig.getMediaUrl(
                                                    _proofImageUrl!)),
                                            child: Image.network(
                                                ApiConfig.getMediaUrl(
                                                    _proofImageUrl!),
                                                width: double.infinity,
                                                height: 160,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    const SizedBox(
                                                        height: 160,
                                                        child: Center(
                                                            child: Icon(Icons
                                                                .broken_image))))),
                                        Positioned(
                                            top: 6,
                                            right: 6,
                                            child: GestureDetector(
                                                onTap: () => setState(() =>
                                                    _proofImageUrl = null),
                                                child: Container(
                                                    padding:
                                                        const EdgeInsets.all(5),
                                                    decoration: BoxDecoration(
                                                        color: Colors.black
                                                            .withOpacity(0.5),
                                                        shape: BoxShape.circle),
                                                    child: const Icon(
                                                        Icons.close,
                                                        size: 14,
                                                        color: Colors.white)))),
                                      ]))
                                  : SizedBox(
                                      height: 64,
                                      child: _isUploading
                                          ? const Center(
                                              child: SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2)))
                                          : Row(children: [
                                              Container(
                                                  width: 48,
                                                  height: 48,
                                                  decoration: BoxDecoration(
                                                      color: dk
                                                          ? Colors.white
                                                              .withOpacity(0.05)
                                                          : const Color(
                                                              0xFFF0F0F0),
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8)),
                                                  child: Icon(
                                                      Icons
                                                          .add_a_photo_outlined,
                                                      size: 22,
                                                      color: sub)),
                                              const SizedBox(width: 12),
                                              Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      _rechargeText(
                                                        context,
                                                        zhCN: '上传付款截图',
                                                        zhTW: '上傳付款截圖',
                                                        en: 'Upload Payment Screenshot',
                                                      ),
                                                      style: TextStyle(
                                                          fontSize: 15,
                                                          color: txt),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      _rechargeText(
                                                        context,
                                                        zhCN: '支持 jpg、png 格式',
                                                        zhTW: '支援 jpg、png 格式',
                                                        en: 'Supports JPG and PNG',
                                                      ),
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: sub),
                                                    ),
                                                  ]),
                                            ])),
                            ),
                            const SizedBox(height: 12),
                            // 备注
                            Container(
                              height: 44,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: dk
                                    ? Colors.white.withOpacity(0.05)
                                    : const Color(0xFFF5F5F5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(children: [
                                Icon(Icons.edit_note_rounded,
                                    size: 18, color: sub),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: TextField(
                                        controller: _remarkController,
                                        style:
                                            TextStyle(fontSize: 14, color: txt),
                                        decoration: InputDecoration(
                                            border: InputBorder.none,
                                            hintText: _rechargeText(
                                              context,
                                              zhCN: '转账备注（选填）',
                                              zhTW: '轉帳備註（選填）',
                                              en: 'Transfer note (optional)',
                                            ),
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                            hintStyle: TextStyle(
                                                fontSize: 14, color: sub)))),
                              ]),
                            ),
                          ])),
                ],

                // 底部
                const SizedBox(height: 20),
                Text(
                  _rechargeText(
                    context,
                    zhCN: '当前余额 $_currency${bal.toStringAsFixed(2)}',
                    zhTW: '目前餘額 $_currency${bal.toStringAsFixed(2)}',
                    en: 'Current Balance $_currency${bal.toStringAsFixed(2)}',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: sub),
                ),
                const SizedBox(height: 12),
                SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isLoading || _amount <= 0 ? null : _submit,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryFor(context),
                          foregroundColor: AppColors.onPrimaryFor(context),
                          disabledBackgroundColor:
                              dk ? Colors.white12 : const Color(0xFFD0D0D0),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: 0),
                      child: _isLoading
                          ? SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.onPrimaryFor(context)))
                          : Text(
                              _amount > 0
                                  ? _rechargeText(
                                      context,
                                      zhCN:
                                          '充值 $_currency${_amount.toStringAsFixed(2)}',
                                      zhTW:
                                          '充值 $_currency${_amount.toStringAsFixed(2)}',
                                      en: 'Recharge $_currency${_amount.toStringAsFixed(2)}',
                                    )
                                  : _rechargeText(
                                      context,
                                      zhCN: '充值',
                                      zhTW: '充值',
                                      en: 'Recharge',
                                    ),
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                    )),
                const SizedBox(height: 30),
              ],
            ),
    );
  }

  Widget _label(String s, Color c) => Text(s,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c));

  Widget _card(Color c, {required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration:
            BoxDecoration(color: c, borderRadius: BorderRadius.circular(14)),
        child: child,
      );

  // 充值方式下拉
  Widget _methodSelector(bool dk, Color card, Color txt, Color sub) {
    return GestureDetector(
      onTap: () => _showMethodPicker(dk, card, txt, sub),
      child: Row(children: [
        Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
                color: AppColors.emphasisSoftFor(context),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(_mIcon(_selectedMethod?.type ?? ''),
                color: AppColors.linkFor(context), size: 18)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            (_selectedMethod != null
                    ? _localizedRechargeMethodName(context, _selectedMethod!)
                    : null) ??
                _rechargeText(
                  context,
                  zhCN: '请选择',
                  zhTW: '請選擇',
                  en: 'Please Select',
                ),
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w500, color: txt),
          ),
          if (_selectedMethod?.remark?.isNotEmpty == true)
            Text(_selectedMethod!.remark!,
                style: TextStyle(fontSize: 12, color: sub), maxLines: 1),
        ])),
        Icon(Icons.chevron_right_rounded, color: sub, size: 22),
      ]),
    );
  }

  void _showMethodPicker(bool dk, Color card, Color txt, Color sub) {
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => Container(
              decoration: BoxDecoration(
                  color: card,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20))),
              child: SafeArea(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                        color: dk ? Colors.white24 : Colors.grey[300],
                        borderRadius: BorderRadius.circular(2))),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _rechargeText(
                      context,
                      zhCN: '选择充值方式',
                      zhTW: '選擇充值方式',
                      en: 'Select Recharge Method',
                    ),
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600, color: txt),
                  ),
                ),
                ..._methods.map((m) {
                  final sel = _selectedMethod?.id == m.id;
                  return InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _selectedMethod = m);
                        Navigator.pop(context);
                      },
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 13),
                          child: Row(children: [
                            Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                    color: sel
                                        ? AppColors.emphasisSoftFor(context)
                                        : (dk
                                            ? Colors.white10
                                            : const Color(0xFFF0F0F0)),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Icon(_mIcon(m.type),
                                    color:
                                        sel ? AppColors.linkFor(context) : sub,
                                    size: 18)),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Text(
                                    _localizedRechargeMethodName(context, m),
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: txt))),
                            if (sel)
                              Icon(Icons.check_circle,
                                  color: AppColors.controlActiveFor(context),
                                  size: 20),
                          ])));
                }),
                const SizedBox(height: 16),
              ])),
            ));
  }

  IconData _mIcon(String t) => t == 'qrcode'
      ? Icons.qr_code_2
      : t == 'bank'
          ? Icons.account_balance
          : Icons.payment;

  // 收款信息
  Widget _paymentInfo(RechargeMethod m, bool dk, Color txt, Color sub) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        _rechargeText(
          context,
          zhCN: '${m.name} 收款信息',
          zhTW: '${m.name} 收款資訊',
          en: '${_localizedRechargeMethodName(context, m)} Payment Info',
        ),
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: txt),
      ),
      const SizedBox(height: 10),
      if (m.type == 'qrcode' && m.qrcodeUrl?.isNotEmpty == true) ...[
        Center(
          child: GestureDetector(
            onTap: () => _previewImage(ApiConfig.getMediaUrl(m.qrcodeUrl!)),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.network(
                ApiConfig.getMediaUrl(m.qrcodeUrl!),
                width: 180,
                height: 180,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => SizedBox(
                  width: 180,
                  height: 180,
                  child: Center(
                    child: Text(
                      _rechargeText(
                        context,
                        zhCN: '加载失败',
                        zhTW: '載入失敗',
                        en: 'Load failed',
                      ),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            _rechargeText(
              context,
              zhCN: '点击查看大图',
              zhTW: '點擊查看大圖',
              en: 'Tap to view full image',
            ),
            style: TextStyle(fontSize: 12, color: sub),
          ),
        ),
      ],
      if (m.accountInfo?.isNotEmpty == true)
        _accountRows(m.accountInfo!, dk, txt, sub),
      const SizedBox(height: 8),
      Text(
        _rechargeText(
          context,
          zhCN:
              '限额 $_currency${m.minAmount.toStringAsFixed(0)} - $_currency${m.maxAmount.toStringAsFixed(0)}',
          zhTW:
              '限額 $_currency${m.minAmount.toStringAsFixed(0)} - $_currency${m.maxAmount.toStringAsFixed(0)}',
          en: 'Limit $_currency${m.minAmount.toStringAsFixed(0)} - $_currency${m.maxAmount.toStringAsFixed(0)}',
        ),
        style: TextStyle(fontSize: 12, color: sub),
      ),
    ]);
  }

  Widget _accountRows(String json, bool dk, Color txt, Color sub) {
    final labels = {
      'bank': _rechargeText(
        context,
        zhCN: '开户银行',
        zhTW: '開戶銀行',
        en: 'Bank',
      ),
      'account': _rechargeText(
        context,
        zhCN: '收款账号',
        zhTW: '收款帳號',
        en: 'Account',
      ),
      'name': _rechargeText(
        context,
        zhCN: '收款人',
        zhTW: '收款人',
        en: 'Payee',
      ),
      'address': _rechargeText(
        context,
        zhCN: '钱包地址',
        zhTW: '錢包地址',
        en: 'Wallet Address',
      ),
      'network': _rechargeText(
        context,
        zhCN: '转账网络',
        zhTW: '轉帳網路',
        en: 'Transfer Network',
      ),
      'chain': _rechargeText(
        context,
        zhCN: '链',
        zhTW: '鏈',
        en: 'Chain',
      ),
      'remark': _rechargeText(
        context,
        zhCN: '备注',
        zhTW: '備註',
        en: 'Remark',
      ),
      'branch': _rechargeText(
        context,
        zhCN: '支行',
        zhTW: '支行',
        en: 'Branch',
      ),
    };
    try {
      final d = jsonDecode(json);
      if (d is Map<String, dynamic>) {
        return Column(
            children: d.entries.map((e) {
          final l = labels[e.key] ?? e.key;
          return Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(
                    width: 68,
                    child: Text(l, style: TextStyle(fontSize: 13, color: sub))),
                Expanded(
                    child: Text(e.value.toString(),
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: txt))),
                GestureDetector(
                    onTap: () => _copy(e.value.toString(), l),
                    child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                            color: AppColors.emphasisSoftFor(context),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          _rechargeText(
                            context,
                            zhCN: '复制',
                            zhTW: '複製',
                            en: 'Copy',
                          ),
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.linkFor(context),
                              fontWeight: FontWeight.w500),
                        ))),
              ]));
        }).toList());
      }
    } catch (_) {}
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(
              child: Text(json, style: TextStyle(fontSize: 14, color: txt))),
          GestureDetector(
              onTap: () => _copy(json,
                  _rechargeText(context, zhCN: '信息', zhTW: '資訊', en: 'Info')),
              child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: AppColors.emphasisSoftFor(context),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(
                    _rechargeText(
                      context,
                      zhCN: '复制',
                      zhTW: '複製',
                      en: 'Copy',
                    ),
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.linkFor(context),
                        fontWeight: FontWeight.w500),
                  ))),
        ]));
  }
}
