// 文件用途：实现 ForgotPasswordPage 页面及其交互流程，属于用户认证。
// 核心逻辑：维护 ForgotPasswordPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/api/auth_service.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/utils/phone_validation.dart';
import '../../../shared/widgets/desktop/auth_desktop_layout.dart';

String _forgotPasswordText(
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

// 关键声明：forgot password page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class ForgotPasswordPage extends ConsumerStatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  ConsumerState<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends ConsumerState<ForgotPasswordPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  Timer? _timer;
  int _secondsLeft = 0;
  bool _isSending = false;
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _timer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

  // 流程逻辑：`build` 根据输入状态生成页面片段或触发回调，交互副作用由页面状态边界统一处理。
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    if (PlatformUtils.isPhysicalDesktop || screenWidth >= 600) {
      return AuthDesktopLayout(
        showBackButton: true,
        onBack: _goBack,
        title: _forgotPasswordText(
          context,
          zhCN: '找回账号密码',
          zhTW: '找回帳號密碼',
          en: 'Recover Account Password',
        ),
        child: _buildContent(isDark),
      );
    }

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightSurface,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(isDark),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: _buildContent(isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          IconButton(
            onPressed: _goBack,
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: isDark ? Colors.white : Colors.black,
              size: 20,
            ),
          ),
          Expanded(
            child: Text(
              _forgotPasswordText(
                context,
                zhCN: '找回账号密码',
                zhTW: '找回帳號密碼',
                en: 'Recover Account Password',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 36),
        Icon(
          Icons.lock_reset_rounded,
          size: 64,
          color: AppColors.linkFor(context),
        ),
        const SizedBox(height: 20),
        Text(
          _forgotPasswordText(
            context,
            zhCN: '重置登录密码',
            zhTW: '重置登入密碼',
            en: 'Reset Login Password',
          ),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _forgotPasswordText(
            context,
            zhCN: '使用已绑定手机号接收验证码',
            zhTW: '使用已綁定手機號接收驗證碼',
            en: 'Use your bound phone number to receive the verification code',
          ),
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondaryFor(context),
          ),
        ),
        const SizedBox(height: 32),
        _buildPhoneField(isDark),
        const SizedBox(height: 16),
        _buildCodeField(isDark),
        const SizedBox(height: 16),
        _buildPasswordField(
          controller: _passwordController,
          hint: _forgotPasswordText(
            context,
            zhCN: '新密码（6-20位）',
            zhTW: '新密碼（6-20位）',
            en: 'New password (6-20 chars)',
          ),
          obscure: _obscurePassword,
          onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
          isDark: isDark,
        ),
        const SizedBox(height: 16),
        _buildPasswordField(
          controller: _confirmPasswordController,
          hint: _forgotPasswordText(
            context,
            zhCN: '确认新密码',
            zhTW: '確認新密碼',
            en: 'Confirm new password',
          ),
          obscure: _obscureConfirmPassword,
          onToggle: () => setState(
            () => _obscureConfirmPassword = !_obscureConfirmPassword,
          ),
          isDark: isDark,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          child: _message == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _message!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color:
                          _messageIsError ? AppColors.error : AppColors.success,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
        ),
        const SizedBox(height: 24),
        _buildSubmitButton(),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _goBack,
          child: Text(
            _forgotPasswordText(
              context,
              zhCN: '返回登录',
              zhTW: '返回登入',
              en: 'Back to Login',
            ),
            style: TextStyle(
              color: AppColors.linkFor(context),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildPhoneField(bool isDark) {
    return _inputShell(
      isDark: isDark,
      child: TextField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        onChanged: (_) => _clearMessage(),
        style: TextStyle(
          fontSize: 16,
          color: AppColors.textPrimaryFor(context),
        ),
        decoration: InputDecoration(
          hintText: _forgotPasswordText(
            context,
            zhCN: '手机号',
            zhTW: '手機號',
            en: 'Phone Number',
          ),
          hintStyle: TextStyle(color: AppColors.inputHintFor(context)),
          prefixIcon: Icon(
            Icons.phone_iphone_rounded,
            color: AppColors.inputIconFor(context),
            size: 22,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(11),
        ],
      ),
    );
  }

  Widget _buildCodeField(bool isDark) {
    return _inputShell(
      isDark: isDark,
      child: TextField(
        controller: _codeController,
        keyboardType: TextInputType.number,
        onChanged: (_) => _clearMessage(),
        style: TextStyle(
          fontSize: 16,
          color: AppColors.textPrimaryFor(context),
        ),
        decoration: InputDecoration(
          hintText: _forgotPasswordText(
            context,
            zhCN: '短信验证码',
            zhTW: '短信驗證碼',
            en: 'SMS Verification Code',
          ),
          hintStyle: TextStyle(color: AppColors.inputHintFor(context)),
          prefixIcon: Icon(
            Icons.sms_outlined,
            color: AppColors.inputIconFor(context),
            size: 22,
          ),
          suffixIcon: TextButton(
            onPressed: (_secondsLeft > 0 || _isSending) ? null : _sendCode,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.linkFor(context),
              disabledForegroundColor: AppColors.textTertiaryFor(context),
            ),
            child: _isSending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _secondsLeft > 0
                        ? '${_secondsLeft}s'
                        : _forgotPasswordText(
                            context,
                            zhCN: '获取验证码',
                            zhTW: '獲取驗證碼',
                            en: 'Send Code',
                          ),
                  ),
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
      ),
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    required bool isDark,
  }) {
    return _inputShell(
      isDark: isDark,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        onChanged: (_) => _clearMessage(),
        style: TextStyle(
          fontSize: 16,
          color: AppColors.textPrimaryFor(context),
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: AppColors.inputHintFor(context)),
          prefixIcon: Icon(
            Icons.lock_outline_rounded,
            color: AppColors.inputIconFor(context),
            size: 22,
          ),
          suffixIcon: IconButton(
            onPressed: onToggle,
            icon: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: AppColors.inputIconFor(context),
              size: 20,
            ),
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        inputFormatters: [
          LengthLimitingTextInputFormatter(20),
        ],
      ),
    );
  }

  Widget _inputShell({required bool isDark, required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBackgroundFor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : _submit,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryFor(context),
          foregroundColor: AppColors.onPrimaryFor(context),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isSubmitting
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.onPrimaryFor(context),
                ),
              )
            : Text(
                _forgotPasswordText(
                  context,
                  zhCN: '重置密码',
                  zhTW: '重置密碼',
                  en: 'Reset Password',
                ),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (!_isValidPhone(phone)) {
      _showMessage(
        _forgotPasswordText(
          context,
          zhCN: '请输入正确的手机号',
          zhTW: '請輸入正確的手機號',
          en: 'Please enter a valid phone number',
        ),
        true,
      );
      return;
    }

    setState(() {
      _isSending = true;
      _message = null;
    });

    final response = await ref
        .read(authServiceProvider.notifier)
        .sendPasswordResetCode(phone);
    if (!mounted) return;

    setState(() => _isSending = false);
    if (response.isSuccess) {
      _startCountdown();
      _showMessage(
        _forgotPasswordText(
          context,
          zhCN: '验证码已发送',
          zhTW: '驗證碼已發送',
          en: 'Verification code sent',
        ),
        false,
      );
    } else {
      _showMessage(
        _serverMessage(
          raw: response.message,
          zhCN: '发送失败',
          zhTW: '發送失敗',
          en: 'Send failed.',
        ),
        true,
      );
    }
  }

  Future<void> _submit() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (!_isValidPhone(phone)) {
      _showMessage(
        _forgotPasswordText(
          context,
          zhCN: '请输入正确的手机号',
          zhTW: '請輸入正確的手機號',
          en: 'Please enter a valid phone number',
        ),
        true,
      );
      return;
    }
    if (code.length < 4) {
      _showMessage(
        _forgotPasswordText(
          context,
          zhCN: '请输入短信验证码',
          zhTW: '請輸入短信驗證碼',
          en: 'Please enter the SMS verification code',
        ),
        true,
      );
      return;
    }
    if (password.length < 6 || password.length > 20) {
      _showMessage(
        _forgotPasswordText(
          context,
          zhCN: '新密码需要6-20位',
          zhTW: '新密碼需要 6-20 位',
          en: 'The new password must be 6-20 characters',
        ),
        true,
      );
      return;
    }
    if (password != confirmPassword) {
      _showMessage(
        _forgotPasswordText(
          context,
          zhCN: '两次输入的密码不一致',
          zhTW: '兩次輸入的密碼不一致',
          en: 'The two passwords do not match',
        ),
        true,
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isSubmitting = true;
      _message = null;
    });

    final response =
        await ref.read(authServiceProvider.notifier).resetPasswordByCode(
              phone: phone,
              code: code,
              newPassword: password,
            );
    if (!mounted) return;

    setState(() => _isSubmitting = false);
    if (response.isSuccess) {
      final data = response.data;
      String username = '';
      if (data is Map) {
        username = (data['username'] ?? '').toString().trim();
      }
      final successMessage = username.isEmpty
          ? _forgotPasswordText(
              context,
              zhCN: '密码已重置，请重新登录',
              zhTW: '密碼已重置，請重新登入',
              en: 'Password reset. Please log in again',
            )
          : _forgotPasswordText(
              context,
              zhCN: '密码已重置，账号：$username',
              zhTW: '密碼已重置，帳號：$username',
              en: 'Password reset. Account: $username',
            );
      _showMessage(successMessage, false);
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop({
            if (username.isNotEmpty) 'username': username,
          });
        } else {
          context.goNamed('login');
        }
      });
    } else {
      _showMessage(
        _serverMessage(
          raw: response.message,
          zhCN: '重置失败',
          zhTW: '重置失敗',
          en: 'Reset failed.',
        ),
        true,
      );
    }
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  bool _isValidPhone(String phone) {
    return isValidMainlandChinaMobile(phone);
  }

  void _clearMessage() {
    if (_message != null) {
      setState(() => _message = null);
    }
  }

  void _showMessage(String message, bool isError) {
    setState(() {
      _message = message.isEmpty
          ? (isError
              ? _forgotPasswordText(
                  context,
                  zhCN: '操作失败',
                  zhTW: '操作失敗',
                  en: 'Action failed',
                )
              : _forgotPasswordText(
                  context,
                  zhCN: '操作成功',
                  zhTW: '操作成功',
                  en: 'Action succeeded',
                ))
          : message;
      _messageIsError = isError;
    });
    if (isError) {
      HapticFeedback.heavyImpact();
    }
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.goNamed('login');
  }
}
