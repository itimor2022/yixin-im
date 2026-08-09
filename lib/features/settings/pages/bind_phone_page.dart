// 文件用途：实现 BindPhonePage 页面及其交互流程，属于应用设置。
// 核心逻辑：维护 BindPhonePage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_validation.dart';

String _bindPhoneText(
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

// 关键声明：bind phone page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class BindPhonePage extends ConsumerStatefulWidget {
  const BindPhonePage({super.key});

  @override
  ConsumerState<BindPhonePage> createState() => _BindPhonePageState();
}

class _BindPhonePageState extends ConsumerState<BindPhonePage> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  int _cooldown = 0;
  Timer? _timer;
  bool _sendingCode = false;
  bool _binding = false;

  bool get _isBusy => _sendingCode || _binding;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  String _serverMessage({
    required String? raw,
    required String zhCN,
    String? zhTW,
    required String en,
  }) {
    return localizeServerMessage(
      raw,
      fallbackZhCN: zhCN,
      fallbackZhTW: zhTW,
      fallbackEn: en,
    );
  }

  bool _isValidPhone(String phone) => isValidMainlandChinaMobile(phone);

  bool _isValidCode(String code) => RegExp(r'^\d{4,8}$').hasMatch(code);

  String? _validatePhone(String phone) {
    if (phone.isEmpty) {
      return _bindPhoneText(
        context,
        zhCN: '请输入手机号',
        zhTW: '請輸入手機號',
        en: 'Please enter your phone number',
      );
    }
    if (!_isValidPhone(phone)) {
      return _bindPhoneText(
        context,
        zhCN: '请输入正确的 11 位手机号',
        zhTW: '請輸入正確的 11 位手機號',
        en: 'Enter a valid 11-digit phone number',
      );
    }
    return null;
  }

  String? _validateCode(String code) {
    if (code.isEmpty) {
      return _bindPhoneText(
        context,
        zhCN: '请输入短信验证码',
        zhTW: '請輸入簡訊驗證碼',
        en: 'Please enter the SMS code',
      );
    }
    if (!_isValidCode(code)) {
      return _bindPhoneText(
        context,
        zhCN: '验证码格式不正确',
        zhTW: '驗證碼格式不正確',
        en: 'The verification code format is invalid',
      );
    }
    return null;
  }

  void _startCooldown() {
    setState(() => _cooldown = 60);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) {
          timer.cancel();
        }
      });
    });
  }

  Future<void> _sendCode() async {
    final phone = _phoneCtrl.text.trim();
    final phoneError = _validatePhone(phone);
    if (phoneError != null) {
      _showMessage(phoneError);
      return;
    }
    if (_cooldown > 0 || _sendingCode) return;

    setState(() => _sendingCode = true);
    final res =
        await ref.read(authServiceProvider.notifier).sendPhoneBindCode(phone);
    if (!mounted) return;
    setState(() => _sendingCode = false);

    if (res.isSuccess) {
      _showMessage(
        _bindPhoneText(
          context,
          zhCN: '验证码已发送，请注意查收',
          zhTW: '驗證碼已發送，請注意查收',
          en: 'Verification code sent',
        ),
      );
      _startCooldown();
    } else {
      _showMessage(
        _serverMessage(
          raw: res.message,
          zhCN: '验证码发送失败',
          zhTW: '驗證碼發送失敗',
          en: 'Failed to send verification code',
        ),
      );
    }
  }

  Future<void> _bind() async {
    final phone = _phoneCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final phoneError = _validatePhone(phone);
    if (phoneError != null) {
      _showMessage(phoneError);
      return;
    }
    final codeError = _validateCode(code);
    if (codeError != null) {
      _showMessage(codeError);
      return;
    }

    setState(() => _binding = true);
    final res =
        await ref.read(authServiceProvider.notifier).bindPhone(phone, code);
    if (!mounted) return;
    setState(() => _binding = false);

    if (res.isSuccess) {
      _showMessage(
        _bindPhoneText(
          context,
          zhCN: '手机号绑定成功',
          zhTW: '手機號綁定成功',
          en: 'Phone number linked successfully',
        ),
      );
      final navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(true);
      } else {
        context.go('/home');
      }
    } else {
      _showMessage(
        _serverMessage(
          raw: res.message,
          zhCN: '绑定失败，请检查验证码后重试',
          zhTW: '綁定失敗，請檢查驗證碼後重試',
          en: 'Binding failed. Check the code and try again.',
        ),
      );
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // 流程逻辑：`build` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  @override
  Widget build(BuildContext context) {
    final asyncSettings = ref.watch(systemSettingsProvider);
    final ready = asyncSettings.maybeWhen(
      data: (settings) => settings.smsBindReady,
      orElse: () => false,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _bindPhoneText(
            context,
            zhCN: '绑定手机号',
            zhTW: '綁定手機號',
            en: 'Link Phone Number',
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _HeaderCard(isDark: isDark),
          const SizedBox(height: 16),
          if (!ready) ...[
            _SmsDisabledNotice(isDark: isDark),
            const SizedBox(height: 16),
          ],
          TextField(
            controller: _phoneCtrl,
            enabled: !_binding,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            maxLength: 11,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: _bindPhoneText(
                context,
                zhCN: '手机号',
                zhTW: '手機號',
                en: 'Phone Number',
              ),
              hintText: _bindPhoneText(
                context,
                zhCN: '请输入 11 位手机号',
                zhTW: '請輸入 11 位手機號',
                en: 'Enter an 11-digit phone number',
              ),
              counterText: '',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _codeCtrl,
                  enabled: !_binding,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  maxLength: 8,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: (_) {
                    if (ready && !_isBusy) {
                      _bind();
                    }
                  },
                  decoration: InputDecoration(
                    labelText: _bindPhoneText(
                      context,
                      zhCN: '验证码',
                      zhTW: '驗證碼',
                      en: 'Verification Code',
                    ),
                    hintText: _bindPhoneText(
                      context,
                      zhCN: '短信验证码',
                      zhTW: '簡訊驗證碼',
                      en: 'SMS code',
                    ),
                    counterText: '',
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 132,
                height: 56,
                child: FilledButton(
                  onPressed:
                      (!ready || _isBusy || _cooldown > 0) ? null : _sendCode,
                  child: _sendingCode
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _cooldown > 0
                                ? '${_cooldown}s'
                                : _bindPhoneText(
                                    context,
                                    zhCN: '获取验证码',
                                    zhTW: '獲取驗證碼',
                                    en: 'Send Code',
                                  ),
                            maxLines: 1,
                            textAlign: TextAlign.center,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          FilledButton(
            onPressed: (!ready || _isBusy) ? null : _bind,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryFor(context),
              foregroundColor: AppColors.onPrimaryFor(context),
              minimumSize: const Size(double.infinity, 48),
            ),
            child: _binding
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _bindPhoneText(
                      context,
                      zhCN: '确认绑定',
                      zhTW: '確認綁定',
                      en: 'Confirm',
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardFor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.dividerFor(context),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.phone_iphone_rounded,
            color: AppColors.linkFor(context),
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _bindPhoneText(
                    context,
                    zhCN: '用于账号安全验证',
                    zhTW: '用於帳號安全驗證',
                    en: 'Used for account security',
                  ),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimaryFor(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _bindPhoneText(
                    context,
                    zhCN: '绑定后可用于登录保护、找回密码和账号安全校验。',
                    zhTW: '綁定後可用於登入保護、找回密碼和帳號安全驗證。',
                    en: 'After linking, it can be used for login protection, password recovery, and account verification.',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SmsDisabledNotice extends StatelessWidget {
  const _SmsDisabledNotice({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(isDark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.withOpacity(isDark ? 0.3 : 0.18),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Colors.orange.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _bindPhoneText(
                context,
                zhCN: '当前服务器未启用短信服务，暂时无法发送验证码。请联系管理员配置短信网关。',
                zhTW: '目前伺服器未啟用簡訊服務，暫時無法發送驗證碼。請聯絡管理員配置簡訊閘道。',
                en: 'SMS service is not enabled on this server. Contact an administrator to configure an SMS gateway.',
              ),
              style: TextStyle(
                color: isDark ? Colors.orange.shade200 : Colors.orange.shade900,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
