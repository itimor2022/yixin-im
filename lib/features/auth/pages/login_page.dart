import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/device_service.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/desktop/auth_desktop_layout.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'agreement_page.dart';
import 'forgot_password_page.dart';
import '../../settings/pages/network_settings_page.dart';

/// 登录页面
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _agreedToTerms = true; // 是否同意协议（默认勾选）
  String? _errorMessage; // 错误提示信息
  Timer? _qrLoginPollTimer;
  bool _isQrLoginLoading = false;
  bool _isQrLoginSigningIn = false;
  String _qrLoginStatus = 'idle';
  String? _qrLoginTicket;
  String? _qrLoginSecret;
  String? _qrLoginText;
  String? _qrLoginError;
  bool _showDesktopQrLogin = false;
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = info.version);
    });
  }

  @override
  void dispose() {
    _qrLoginPollTimer?.cancel();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0E0E0E) : Colors.white;
    final screenWidth = MediaQuery.of(context).size.width;

    // 桌面端或宽屏使用桌面布局
    if (PlatformUtils.isDesktop || screenWidth >= 600) {
      return AuthDesktopLayout(
        child: _buildLoginContent(isDark),
      );
    }

    // 移动端使用原始布局
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: _buildLoginContent(isDark),
        ),
      ),
    );
  }

  /// 登录内容（共享）
  Widget _buildLoginContent(bool isDark) {
    final isDesktop =
        PlatformUtils.isDesktop || MediaQuery.of(context).size.width >= 600;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final appName =
        ref.watch(systemSettingsProvider).valueOrNull?.displayName ??
            kDefaultAppDisplayName;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: isDesktop ? 28 : 56),

        // Logo（桌面端隐藏，因为左侧已有）
        if (!isDesktop) ...[
          _buildLogo(),
          const SizedBox(height: 24),
        ],

        if (!(PlatformUtils.isDesktop && _showDesktopQrLogin)) ...[
          _buildTitle(isDark, l10n, appName),
          const SizedBox(height: 48),
        ],

        // 登录表单
        if (PlatformUtils.isDesktop && _showDesktopQrLogin)
          _buildDesktopQrLoginSection(isDark, l10n)
        else
          _buildLoginForm(isDark, l10n),

        SizedBox(
          height: PlatformUtils.isDesktop && _showDesktopQrLogin ? 12 : 18,
        ),

        // 底部
        _buildBottom(isDark, l10n),

        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildLogo() {
    return Image.asset(
      'assets/logo.png',
      width: 120,
      height: 120,
    ).animate().fadeIn(duration: 400.ms).scale(
          begin: const Offset(0.9, 0.9),
          curve: Curves.easeOut,
          duration: 400.ms,
        );
  }

  Widget _buildTitle(bool isDark, AppLocalizations l10n, String appName) {
    return Column(
      children: [
        Text(
          appName,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.loginToAccount,
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginForm(bool isDark, AppLocalizations l10n) {
    final showDesktopQrSwitch = PlatformUtils.isDesktop;

    return Column(
      children: [
        // 用户名输入（完全禁用中文输入法）
        _buildUsernameField(isDark, l10n),

        const SizedBox(height: 16),

        // 密码输入
        _buildPasswordField(isDark, l10n),

        const SizedBox(height: 10),
        _buildForgotPasswordEntry(isDark),

        if (showDesktopQrSwitch) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Tooltip(
              message: '扫码登录',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _openDesktopQrLogin,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.qr_code_2_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],

        // 错误提示 - TG 风格
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _errorMessage != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: AppColors.error,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              : const SizedBox.shrink(),
        ),

        const SizedBox(height: 24),

        // 登录按钮
        _buildButton(
          onPressed: () => _login(l10n),
          text: l10n.login,
        ),
      ],
    );
  }

  void _openNetworkSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NetworkSettingsPage()),
    );
  }

  Widget _buildForgotPasswordEntry(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        TextButton.icon(
          onPressed: _openNetworkSettings,
          icon: const Icon(Icons.swap_horiz_rounded, size: 17),
          label: const Text('切换线路'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: _openForgotPassword,
          icon: const Icon(Icons.contact_support_rounded, size: 17),
          label: const Text('找回账号密码'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _openForgotPassword() async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const ForgotPasswordPage(),
      ),
    );
    if (!mounted) return;
    if (result is Map && result['username'] is String) {
      final username = (result['username'] as String).trim();
      if (username.isNotEmpty) {
        _phoneController.text = username;
        _clearError();
      }
    }
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  void _setAgreement(bool value) {
    setState(() {
      _agreedToTerms = value;

      if (!value && _showDesktopQrLogin) {
        _qrLoginPollTimer?.cancel();
        _isQrLoginLoading = false;
        _isQrLoginSigningIn = false;
        _qrLoginStatus = 'idle';
        _qrLoginTicket = null;
        _qrLoginSecret = null;
        _qrLoginText = null;
        _qrLoginError = null;
      }
    });

    if (value &&
        _showDesktopQrLogin &&
        ((_qrLoginText ?? '').isEmpty) &&
        !_isQrLoginLoading) {
      _createDesktopQrLogin();
    }
  }

  void _openDesktopQrLogin() {
    _qrLoginPollTimer?.cancel();
    setState(() {
      _showDesktopQrLogin = true;
      _qrLoginError = null;
    });
    if (_agreedToTerms) {
      _createDesktopQrLogin();
    }
  }

  void _closeDesktopQrLogin() {
    _qrLoginPollTimer?.cancel();
    setState(() {
      _showDesktopQrLogin = false;
      _isQrLoginLoading = false;
      _isQrLoginSigningIn = false;
      _qrLoginStatus = 'idle';
      _qrLoginTicket = null;
      _qrLoginSecret = null;
      _qrLoginText = null;
      _qrLoginError = null;
    });
  }

  /// 手机号输入框
  Widget _buildUsernameField(bool isDark, AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        onChanged: (_) => _clearError(),
        style: TextStyle(
          fontSize: 16,
          color: isDark ? Colors.white : Colors.black,
        ),
        decoration: InputDecoration(
          hintText: '请输入手机号',
          hintStyle: TextStyle(
            color: isDark ? Colors.white30 : Colors.black38,
          ),
          prefixIcon: Icon(
            Icons.phone_outlined,
            color: isDark ? Colors.white30 : Colors.black38,
            size: 22,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(15),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required TextInputType keyboardType,
    required bool isDark,
    List<TextInputFormatter>? inputFormatters,
    bool autocorrect = true,
    bool enableSuggestions = true,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        onChanged: onChanged,
        style: TextStyle(
          fontSize: 16,
          color: isDark ? Colors.white : Colors.black,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: isDark ? Colors.white30 : Colors.black38,
          ),
          prefixIcon: Icon(
            icon,
            color: isDark ? Colors.white30 : Colors.black38,
            size: 22,
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        inputFormatters: inputFormatters,
      ),
    );
  }

  Widget _buildPasswordField(bool isDark, AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        onChanged: (_) => _clearError(),
        style: TextStyle(
          fontSize: 16,
          color: isDark ? Colors.white : Colors.black,
        ),
        decoration: InputDecoration(
          hintText: l10n.passwordLabel,
          hintStyle: TextStyle(
            color: isDark ? Colors.white30 : Colors.black38,
          ),
          prefixIcon: Icon(
            Icons.lock_outline_rounded,
            color: isDark ? Colors.white30 : Colors.black38,
            size: 22,
          ),
          suffixIcon: IconButton(
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(
              _obscurePassword
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
      ),
    );
  }

  Widget _buildButton({
    required VoidCallback onPressed,
    required String text,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                text,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }

  Widget _buildBottom(bool isDark, AppLocalizations l10n) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.get('no_account_yet') ?? '还没有账号？',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ),
            TextButton(
              onPressed: () => context.goNamed('register'),
              child: Text(
                l10n.registerNow,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () {
            _setAgreement(!_agreedToTerms);
          },
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: _agreedToTerms,
                  onChanged: (value) {
                    _setAgreement(value ?? false);
                  },
                  activeColor: AppColors.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  side: BorderSide(
                    color: isDark ? Colors.white38 : Colors.black26,
                    width: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.black38,
                    height: 1.2,
                  ),
                  children: [
                    TextSpan(text: l10n.agreeTermsPrefix),
                    TextSpan(
                      text: '《用户协议》',
                      style: TextStyle(
                        color: AppColors.primary,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap =
                            () => _openAgreement(AgreementType.userAgreement),
                    ),
                    const TextSpan(text: '和'),
                    TextSpan(
                      text: '《隐私政策》',
                      style: TextStyle(
                        color: AppColors.primary,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap =
                            () => _openAgreement(AgreementType.privacyPolicy),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_appVersion.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'v$_appVersion',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDesktopQrLoginSection(bool isDark, AppLocalizations l10n) {
    final cardColor =
        isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100;
    final borderColor =
        isDark ? Colors.white10 : Colors.black.withOpacity(0.06);
    final secondaryTextColor = isDark ? Colors.white54 : Colors.black54;
    final shouldShowAgreementError = !_agreedToTerms;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    '扫码登录',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: (!_agreedToTerms || _isQrLoginLoading)
                        ? null
                        : _createDesktopQrLogin,
                    tooltip: '刷新二维码',
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '打开手机应用，使用扫一扫确认登录这台桌面设备',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: secondaryTextColor,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 196,
                height: 196,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: _buildDesktopQrContent(),
              ),
              const SizedBox(height: 12),
              if (shouldShowAgreementError)
                const Text(
                  '请先阅读并同意用户协议和隐私政策',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else if (_isQrLoginSigningIn)
                const Text(
                  '登录确认中...',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (_qrLoginStatus == 'expired')
                Text(
                  '二维码已过期，请点击右上角刷新',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                  ),
                )
              else if (_qrLoginError != null)
                Text(
                  _qrLoginError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                  ),
                )
              else
                Text(
                  '二维码有效期 2 分钟',
                  style: TextStyle(
                    fontSize: 12,
                    color: secondaryTextColor,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        TextButton(
          onPressed: _closeDesktopQrLogin,
          child: Text(
            l10n.login,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopQrContent() {
    if (!_agreedToTerms) {
      return const Center(
        child: Icon(
          Icons.qr_code_2_rounded,
          size: 72,
          color: Colors.grey,
        ),
      );
    }

    if (_isQrLoginLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_qrLoginText != null && _qrLoginText!.isNotEmpty) {
      return QrImageView(
        data: _qrLoginText!,
        version: QrVersions.auto,
        gapless: true,
        backgroundColor: Colors.white,
      );
    }

    return const Center(
      child: Icon(
        Icons.qr_code_2_rounded,
        size: 72,
        color: Colors.grey,
      ),
    );
  }

  Future<void> _createDesktopQrLogin() async {
    if (!PlatformUtils.isDesktop) return;

    _qrLoginPollTimer?.cancel();
    setState(() {
      _isQrLoginLoading = true;
      _isQrLoginSigningIn = false;
      _qrLoginStatus = 'loading';
      _qrLoginError = null;
      _qrLoginTicket = null;
      _qrLoginSecret = null;
      _qrLoginText = null;
    });

    try {
      final deviceId = await DeviceService.getDeviceId();
      final deviceType = DeviceService.getDeviceType();
      final deviceName = await DeviceService.getDeviceName();
      final api = ref.read(apiClientProvider);

      final response = await api.post<Map<String, dynamic>>(
        '/auth/qr-login/create',
        data: {
          'device_id': deviceId,
          'device_type': deviceType,
          'device_name': deviceName,
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (!mounted) return;

      if (response.isSuccess && response.data != null) {
        final data = response.data!;
        setState(() {
          _qrLoginTicket = data['ticket']?.toString();
          _qrLoginSecret = data['secret']?.toString();
          _qrLoginText = data['qr_text']?.toString();
          _qrLoginStatus = (data['status'] ?? 'pending').toString();
          _isQrLoginLoading = false;
        });
        _startDesktopQrPolling();
        return;
      }

      setState(() {
        _isQrLoginLoading = false;
        _qrLoginStatus = 'error';
        _qrLoginError =
            response.message.isNotEmpty ? response.message : '二维码生成失败';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isQrLoginLoading = false;
        _qrLoginStatus = 'error';
        _qrLoginError = '二维码生成失败';
      });
    }
  }

  void _startDesktopQrPolling() {
    _qrLoginPollTimer?.cancel();
    if ((_qrLoginTicket ?? '').isEmpty || (_qrLoginSecret ?? '').isEmpty) {
      return;
    }

    _qrLoginPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollDesktopQrStatus(),
    );
  }

  Future<void> _pollDesktopQrStatus() async {
    if (_isQrLoginSigningIn ||
        (_qrLoginTicket ?? '').isEmpty ||
        (_qrLoginSecret ?? '').isEmpty) {
      return;
    }

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.get<Map<String, dynamic>>(
        '/auth/qr-login/status/${_qrLoginTicket!}',
        queryParameters: {'secret': _qrLoginSecret},
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (!mounted || !response.isSuccess || response.data == null) return;

      final data = response.data!;
      final status = (data['status'] ?? 'expired').toString();

      if (status == 'pending') return;

      if (status == 'expired') {
        _qrLoginPollTimer?.cancel();
        setState(() {
          _qrLoginStatus = 'expired';
        });
        return;
      }

      if (status == 'confirmed') {
        final token = (data['token'] ?? '').toString();
        if (token.isEmpty) return;

        _qrLoginPollTimer?.cancel();
        setState(() {
          _isQrLoginSigningIn = true;
          _qrLoginStatus = 'confirmed';
          _qrLoginError = null;
        });

        final authService = ref.read(authServiceProvider.notifier);
        final success = await authService.loginWithToken(token);
        if (!mounted) return;

        if (success) {
          context.go('/home');
          return;
        }

        setState(() {
          _isQrLoginSigningIn = false;
          _qrLoginStatus = 'error';
          _qrLoginError = '二维码登录失败，请刷新后重试';
        });
      }
    } catch (_) {
      // 轮询失败时静默等待下一次轮询
    }
  }

  /// 打开协议页面
  void _openAgreement(AgreementType type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AgreementPage(type: type),
      ),
    );
  }

  void _login(AppLocalizations l10n) async {
    // 检查是否同意协议
    if (!_agreedToTerms) {
      _showError(l10n.pleaseAgreeTerms);
      return;
    }

    final phone = _phoneController.text.trim();

    if (phone.isEmpty) {
      _showError('请输入手机号');
      return;
    }

    // 验证手机号格式（只允许数字）
    if (!RegExp(r'^[0-9]+$').hasMatch(phone)) {
      _showError(l10n.get('phone_format_error') ?? '手机号只能包含数字');
      return;
    }

    if (phone.length < 7) {
      _showError(l10n.get('phone_min_length') ?? '手机号位数至少11位');
      return;
    }

    if (_passwordController.text.isEmpty) {
      _showError(l10n.pleaseEnterPassword);
      return;
    }

    if (_passwordController.text.length < 6) {
      _showError(l10n.get('password_min_length') ?? '密码至少6位');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    // 获取持久化设备信息
    final deviceType = DeviceService.getDeviceType();
    final deviceResults = await Future.wait<String>([
      DeviceService.getDeviceId(),
      DeviceService.getDeviceName(),
    ]);
    final deviceId = deviceResults[0];
    final deviceName = deviceResults[1];

    // 调用后端 API 登录
    final authService = ref.read(authServiceProvider.notifier);
    final response = await authService.login(
      phone: phone,
      password: _passwordController.text.trim(),
      deviceId: deviceId,
      deviceType: deviceType,
      deviceName: deviceName,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (kDebugMode) debugPrint('[Login] response.code: ${response.code}');
    if (kDebugMode)
      debugPrint('[Login] response.isSuccess: ${response.isSuccess}');
    if (kDebugMode) debugPrint('[Login] response.message: ${response.message}');

    if (response.isSuccess) {
      if (kDebugMode) debugPrint('[Login] Navigating to /home');
      context.go('/home');
    } else if (response.code == 1001) {
      await _handleDeviceLockChallenge(response);
    } else {
      if (kDebugMode) debugPrint('[Login] Login failed: ${response.message}');
      _showError(response.message);
    }
  }

  Future<void> _handleDeviceLockChallenge(ApiResponse response) async {
    final raw = response.data;
    if (raw is! Map) {
      _showError('设备锁验证信息异常，请重试');
      return;
    }
    final data = Map<String, dynamic>.from(raw);
    final ticket = data['verify_ticket']?.toString() ?? '';
    if (ticket.isEmpty) {
      _showError('设备锁验证信息异常，请重试');
      return;
    }

    final codeController = TextEditingController();
    bool isSubmitting = false;
    String? localError;

    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('新设备登录验证'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('请输入短信验证码完成设备验证'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: const InputDecoration(
                      hintText: '6位验证码',
                      counterText: '',
                    ),
                  ),
                  if (localError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      localError!,
                      style:
                          const TextStyle(color: AppColors.error, fontSize: 13),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSubmitting ? null : () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final code = codeController.text.trim();
                          if (code.length < 4) {
                            setStateDialog(() => localError = '请输入正确的验证码');
                            return;
                          }
                          setStateDialog(() {
                            isSubmitting = true;
                            localError = null;
                          });
                          final authService =
                              ref.read(authServiceProvider.notifier);
                          final verifyResp =
                              await authService.verifyDeviceLockLogin(
                            ticket: ticket,
                            code: code,
                          );
                          if (!mounted) return;
                          if (verifyResp.isSuccess) {
                            Navigator.pop(context, true);
                            return;
                          }
                          setStateDialog(() {
                            isSubmitting = false;
                            localError = verifyResp.message;
                          });
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('验证'),
                ),
              ],
            );
          },
        );
      },
    );
    codeController.dispose();

    if (verified == true && mounted) {
      context.go('/home');
    }
  }

  void _showError(String message) {
    setState(() => _errorMessage = message);
    // 同时震动反馈
    HapticFeedback.heavyImpact();
  }
}
