// 文件用途：实现 BindPhonePage 页面及其交互流程，属于应用设置。
// 核心逻辑：维护 BindPhonePage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/phone_validation.dart';
import '../../../shared/widgets/themed_app_bar.dart';

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
  final _phoneFocus = FocusNode();
  bool _binding = false;

  @override
  void initState() {
    super.initState();
    // 进入页面后自动激活手机号输入框，避免用户再次手动点击
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _phoneFocus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _phoneFocus.dispose();
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

  Future<void> _bind() async {
    final phone = _phoneCtrl.text.trim();
    final phoneError = _validatePhone(phone);
    if (phoneError != null) {
      _showMessage(phoneError);
      return;
    }

    setState(() => _binding = true);
    final res =
        await ref.read(authServiceProvider.notifier).bindPhone(phone);
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
          zhCN: '绑定失败，请稍后重试',
          zhTW: '綁定失敗，請稍後重試',
          en: 'Binding failed. Please try again later.',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: ThemedAppBar(
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
          TextField(
            controller: _phoneCtrl,
            focusNode: _phoneFocus,
            autofocus: true,
            enabled: !_binding,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            maxLength: 11,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) {
              if (!_binding) {
                _bind();
              }
            },
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
          const SizedBox(height: 28),
          FilledButton(
            onPressed: _binding ? null : _bind,
            style: FilledButton.styleFrom(
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