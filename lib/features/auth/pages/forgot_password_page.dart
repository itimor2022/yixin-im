import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:url_launcher/url_launcher.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/desktop/auth_desktop_layout.dart';

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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    if (PlatformUtils.isDesktop || screenWidth >= 600) {
      return AuthDesktopLayout(
        showBackButton: true,
        onBack: _goBack,
        title: '找回账号密码',
        child: _buildContent(isDark),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E0E0E) : Colors.white,
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
              '找回账号密码',
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
          Icons.support_agent_rounded,
          size: 64,
          color: AppColors.primary.withOpacity(0.95),
        ),
        const SizedBox(height: 20),
        Text(
          '找回账号密码',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          '如需找回账号或重置密码，请联系在线客服协助处理',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _contactService,
            icon: const Icon(Icons.headset_mic_rounded, size: 20),
            label: const Text(
              '联系在线客服',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _goBack,
          child: const Text('返回登录'),
        ),
      ],
    );
  }

  Future<void> _contactService() async {
    final url = ref
            .read(systemSettingsProvider)
            .valueOrNull
            ?.customerServiceUrl
            .trim() ??
        '';
    if (url.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('客服暂未配置，请稍后再试')),
        );
      }
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('客服地址无效')),
        );
      }
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开客服链接')),
        );
      }
    }
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
          color: isDark ? Colors.white : Colors.black,
        ),
        decoration: InputDecoration(
          hintText: '手机号',
          hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
          prefixIcon: Icon(
            Icons.phone_iphone_rounded,
            color: isDark ? Colors.white30 : Colors.black38,
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
          color: isDark ? Colors.white : Colors.black,
        ),
        decoration: InputDecoration(
          hintText: '短信验证码',
          hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
          prefixIcon: Icon(
            Icons.sms_outlined,
            color: isDark ? Colors.white30 : Colors.black38,
            size: 22,
          ),
          suffixIcon: TextButton(
            onPressed: (_secondsLeft > 0 || _isSending) ? null : _sendCode,
            child: _isSending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_secondsLeft > 0 ? '${_secondsLeft}s' : '获取验证码'),
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
          color: isDark ? Colors.white : Colors.black,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: isDark ? Colors.white30 : Colors.black38),
          prefixIcon: Icon(
            Icons.lock_outline_rounded,
            color: isDark ? Colors.white30 : Colors.black38,
            size: 22,
          ),
          suffixIcon: IconButton(
            onPressed: onToggle,
            icon: Icon(
              obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              color: isDark ? Colors.white30 : Colors.black38,
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
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
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
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                '重置密码',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
      ),
    );
  }

  Future<void> _sendCode() async {
    final phone = _phoneController.text.trim();
    if (!_isValidPhone(phone)) {
      _showMessage('请输入正确的手机号', true);
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
      _showMessage('验证码已发送', false);
    } else {
      _showMessage(response.message, true);
    }
  }

  Future<void> _submit() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (!_isValidPhone(phone)) {
      _showMessage('请输入正确的手机号', true);
      return;
    }
    if (code.length < 4) {
      _showMessage('请输入短信验证码', true);
      return;
    }
    if (password.length < 6 || password.length > 20) {
      _showMessage('新密码需要6-20位', true);
      return;
    }
    if (password != confirmPassword) {
      _showMessage('两次输入的密码不一致', true);
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
      final successMessage =
          username.isEmpty ? '密码已重置，请重新登录' : '密码已重置，账号：$username';
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
      _showMessage(response.message, true);
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
    return RegExp(r'^1\d{10}$').hasMatch(phone);
  }

  void _clearMessage() {
    if (_message != null) {
      setState(() => _message = null);
    }
  }

  void _showMessage(String message, bool isError) {
    setState(() {
      _message = message.isEmpty ? (isError ? '操作失败' : '操作成功') : message;
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
