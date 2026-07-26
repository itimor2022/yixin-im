import 'dart:async';
import '../../../core/services/server_discovery.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
import '../../settings/pages/network_settings_page.dart';
import '../../../core/utils/link_utils.dart';
import '../widgets/auth_form_widgets.dart';

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
  bool _agreedToTerms = false;  // 默认未勾选
  String? _errorMessage;
  Timer? _qrLoginPollTimer;
  bool _isQrLoginLoading = false;
  bool _isQrLoginSigningIn = false;
  String _qrLoginStatus = 'idle';
  String? _qrLoginTicket;
  String? _qrLoginSecret;
  String? _qrLoginText;
  String? _qrLoginError;
  bool _showDesktopQrLogin = false;
  String _appName = '';
  final _captchaController = TextEditingController();
  String? _captchaId;
  String? _captchaB64;

  late final int _logoCacheBust = DateTime.now().microsecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() {
          _appName = info.appName;
        });
      }
    });
    _fetchCaptcha();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        ref.invalidate(systemSettingsProvider);
      } catch (e) {
        debugPrint('⚠️ [Login Cache Bypass] 强刷配置异常: $e');
      }
    });
  }

  @override
  void dispose() {
    _qrLoginPollTimer?.cancel();
    _phoneController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final l10n = AppLocalizations(ref.watch(languageProvider));

    if (PlatformUtils.isDesktop || screenWidth >= 600) {
      return AuthDesktopLayout(
        child: _buildLoginContent(isDark),
      );
    }

    return _buildMobileLayout(context, isDark, l10n);
  }

  // ==================== 移动端布局 ====================

  Widget _buildMobileLayout(
    BuildContext context,
    bool isDark,
    AppLocalizations l10n,
  ) {
    final Color bg = isDark ? const Color(0xFF14161E) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Stack(
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    28,
                    20,
                    28,
                    MediaQuery.of(context).viewPadding.bottom + 20,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight - 40,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 36),
                        _buildBrand(isDark),
                        const SizedBox(height: 44),
                        _buildLoginFormMobile(isDark, l10n),
                        const SizedBox(height: 24),
                        _buildVersionText(),
                      ],
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 4,
              right: 4,
              child: _buildCustomerServiceAction(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBrand(bool isDark) {
    final settingsAsync = ref.watch(systemSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    final logoUrl = settings?.logoImageUrl;
    final title = (settings?.systemName ?? '').trim().isNotEmpty
        ? settings!.systemName.trim()
        : (_appName.isNotEmpty ? _appName : '潮商会');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: AuthLogoBadge(
            remoteUrl: logoUrl,
            size: 108,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
      ],
    );
  }

  /// 极简表单：手机号 / 密码 / 图形验证码 / 登录 / 立即注册
  Widget _buildLoginFormMobile(bool isDark, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthInput(
          controller: _phoneController,
          hint: '手机号',
          icon: Icons.phone_iphone_rounded,
          keyboardType: TextInputType.phone,
          isDark: isDark,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => _clearError(),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
        ),
        const SizedBox(height: 14),
        AuthInput(
          controller: _passwordController,
          hint: l10n.passwordLabel,
          icon: Icons.lock_outline_rounded,
          obscureText: _obscurePassword,
          isDark: isDark,
          onChanged: (_) => _clearError(),
          suffix: IconButton(
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            splashRadius: 20,
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: 20,
              color: isDark ? Colors.white38 : kAuthTextHint,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: AuthInput(
                controller: _captchaController,
                hint: '验证码',
                icon: Icons.verified_user_outlined,
                keyboardType: TextInputType.number,
                isDark: isDark,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                onChanged: (_) => _clearError(),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _fetchCaptcha,
              child: Container(
                width: 128,
                height: 54,
                decoration: BoxDecoration(
                  color:
                      isDark ? Colors.white.withOpacity(0.06) : kAuthCardLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: _captchaB64 != null
                    ? Image.memory(
                        Uri.parse(_captchaB64!).data!.contentAsBytes(),
                        fit: BoxFit.contain,
                      )
                    : const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kAuthPrimary,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _errorMessage != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: AppColors.error,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
        const SizedBox(height: 26),
        _buildForgotPasswordEntry(isDark),
        const SizedBox(height: 10),
        _buildLoginRegisterRow(l10n),
      ],
    );
  }

  /// 左右一行的登录/注册按钮组合 + 协议勾选
  Widget _buildLoginRegisterRow(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ✅ 协议勾选框（手动实现）
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _agreedToTerms,
                onChanged: (value) => setState(() => _agreedToTerms = value ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: '我已阅读并同意 ',
                  style: const TextStyle(fontSize: 13),
                  children: [
                    TextSpan(
                      text: '用户协议',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => _openAgreement(AgreementType.userAgreement),
                    ),
                    const TextSpan(text: ' 和 '),
                    TextSpan(
                      text: '隐私政策',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => _openAgreement(AgreementType.privacyPolicy),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: AuthOutlineButton(
                text: '注册',
                onPressed: () => context.goNamed('register'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AuthPrimaryButton(
                text: l10n.login,
                loading: _isLoading,
                onPressed: _agreedToTerms ? () => _login(l10n) : null,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _fetchCaptcha() async {
    // ★ 等待 ServerDiscovery 完成，确保 baseUrl 已就绪
    if (ServerDiscovery.instance.currentNode == null) {
      try {
        await ServerDiscovery.instance.initialize().timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            if (kDebugMode) debugPrint('[Login] ServerDiscovery timeout waiting for captcha');
            return '';
          },
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[Login] ServerDiscovery error: $e');
      }
    }
    if (!mounted) return;
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.post('/auth/captcha');
      if (response.isSuccess && response.data != null) {
        if (!mounted) return;
        setState(() {
          _captchaId = response.data['captchaId']?.toString();
          _captchaB64 = response.data['captchaB64']?.toString();
        });
      }
    } catch (e) {
      debugPrint('获取登录验证码失败: $e');
    }
  }

  /// 登录内容（共享）
  Widget _buildLoginContent(bool isDark) {
    final isDesktop =
        PlatformUtils.isDesktop || MediaQuery.of(context).size.width >= 600;
    final l10n = AppLocalizations(ref.watch(languageProvider));

    final systemSettings = ref.watch(systemSettingsProvider).valueOrNull;

    final remoteLogoUrl = systemSettings?.logoImageUrl;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isDesktop)
          Align(
            alignment: Alignment.centerRight,
            child: _buildCustomerServiceAction(),
          ),

        SizedBox(height: isDesktop ? 28 : 16),

        if (!(PlatformUtils.isDesktop && _showDesktopQrLogin)) ...[
          Builder(builder: (context) {
            final settingsState = ref.watch(systemSettingsProvider);
            if (settingsState.isLoading) {
              return const SizedBox(height: 180 + 32);
            }
            final settings = settingsState.valueOrNull;
            final logoUrl = settings?.logoImageUrl ?? '';
            if (logoUrl.isEmpty) return const SizedBox(height: 32);
            final finalImgUrl = logoUrl.contains('?')
                ? '$logoUrl&_t=$_logoCacheBust'
                : '$logoUrl?_t=$_logoCacheBust';
            return Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Image.network(
                finalImgUrl,
                height: 180,
                fit: BoxFit.contain,
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: const Duration(milliseconds: 200),
                    child: child,
                  );
                },
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox(height: 32),
              ),
            );
          }),
        ],
        if (PlatformUtils.isDesktop && _showDesktopQrLogin)
          _buildDesktopQrLoginSection(isDark, l10n)
        else
          _buildLoginForm(isDark, l10n),

        if (PlatformUtils.isDesktop && _showDesktopQrLogin) ...[
          const SizedBox(height: 12),
          _buildBottom(isDark, l10n),
        ],

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
    return Text(
      appName,
      style: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.bold,
        color: isDark ? Colors.white : Colors.black,
      ),
    );
  }

  Widget _buildLoginForm(bool isDark, AppLocalizations l10n) {
    final showDesktopQrSwitch = PlatformUtils.isDesktop;

    return Column(
      children: [
        _buildUsernameField(isDark, l10n),

        const SizedBox(height: 16),

        _buildPasswordField(isDark, l10n),

        const SizedBox(height: 16),

        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: _buildInputField(
                controller: _captchaController,
                hint: '验证码',
                icon: Icons.verified_user_outlined,
                keyboardType: TextInputType.number,
                isDark: isDark,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                onChanged: (_) => _clearError(),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _fetchCaptcha,
              child: Container(
                width: 128,
                height: 54,
                decoration: BoxDecoration(
                  color:
                      isDark ? Colors.white.withOpacity(0.06) : kAuthCardLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                clipBehavior: Clip.antiAlias,
                child: _captchaB64 != null
                    ? Image.memory(
                        Uri.parse(_captchaB64!).data!.contentAsBytes(),
                        fit: BoxFit.contain,
                      )
                    : const Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: kAuthPrimary,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),

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

        const SizedBox(height: 20),

        _buildForgotPasswordEntry(isDark),
        const SizedBox(height: 10),

        _buildLoginRegisterRow(l10n),
      ],
    );
  }

  void _openNetworkSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NetworkSettingsPage()),
    );
  }

  /// "线路选择" 蓝色下划线
  Widget _buildForgotPasswordEntry(bool isDark) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: _openNetworkSettings,
        child: Text(
          '线路选择',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
            decoration: TextDecoration.underline,
            decorationColor: AppColors.primary,
            decorationThickness: 1.5,
          ),
        ),
      ),
    );
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

  Widget _buildUsernameField(bool isDark, AppLocalizations l10n) {
    return AuthInput(
      controller: _phoneController,
      hint: '手机号',
      icon: Icons.phone_iphone_rounded,
      isDark: isDark,
      keyboardType: TextInputType.phone,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: (_) => _clearError(),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(11),
      ],
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
    return AuthInput(
      controller: controller,
      hint: hint,
      icon: icon,
      isDark: isDark,
      keyboardType: keyboardType,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
    );
  }

  Widget _buildPasswordField(bool isDark, AppLocalizations l10n) {
    return AuthInput(
      controller: _passwordController,
      hint: l10n.passwordLabel,
      icon: Icons.lock_outline_rounded,
      isDark: isDark,
      obscureText: _obscurePassword,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: (_) => _clearError(),
      suffix: IconButton(
        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
        splashRadius: 20,
        icon: Icon(
          _obscurePassword
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          size: 20,
          color: isDark ? Colors.white38 : kAuthTextHint,
        ),
      ),
    );
  }

  Widget _buildButton({
    required VoidCallback onPressed,
    required String text,
  }) {
    return AuthPrimaryButton(
      text: text,
      loading: _isLoading,
      onPressed: onPressed,
    );
  }

  Widget _buildBottom(bool isDark, AppLocalizations l10n) {
    return Column(
      children: [
        TextButton(
          onPressed: () => context.goNamed('register'),
          child: Text(
            '注册',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
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
    final phone = _phoneController.text.trim();

    if (phone.isEmpty) {
      _showError('请输入手机号');
      return;
    }

    if (!RegExp(r'^\d{11}$').hasMatch(phone)) {
      _showError('请输入11位手机号');
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

    if (_captchaController.text.trim().isEmpty) {
      _showError('请输入图形验证码');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    // ★ 等待 ServerDiscovery 完成（最多 5 秒），确保 baseUrl 已就绪
    if (ServerDiscovery.instance.currentNode == null) {
      try {
        await ServerDiscovery.instance.initialize().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            if (kDebugMode) debugPrint('[Login] ServerDiscovery timeout');
            return '';
          },
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[Login] ServerDiscovery error: $e');
      }
    }

    if (!mounted) return;

    final deviceType = DeviceService.getDeviceType();
    final deviceResults = await Future.wait<String>([
      DeviceService.getDeviceId(),
      DeviceService.getDeviceName(),
    ]);
    final deviceId = deviceResults[0];
    final deviceName = deviceResults[1];

    final authService = ref.read(authServiceProvider.notifier);
    final response = await authService.login(
      phone: phone,
      password: _passwordController.text.trim(),
      deviceId: deviceId,
      deviceType: deviceType,
      deviceName: deviceName,
      captchaId: _captchaId ?? '',
      captchaCode: _captchaController.text.trim(),
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
      _fetchCaptcha();
      _captchaController.clear();
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
    HapticFeedback.heavyImpact();
  }

  Widget _buildCustomerServiceAction() {
    return IconButton(
      icon: const Icon(Icons.headset_mic_outlined,
          color: AppColors.primary, size: 24),
      tooltip: '在线客服',
      onPressed: () {
        final settingsAsync = ref.read(systemSettingsProvider);
        var serviceUrl = settingsAsync.asData?.value.customerServiceUrl;
        if (serviceUrl == null || serviceUrl.isEmpty) {
          final service = ref.read(systemSettingsServiceProvider);
          serviceUrl = service.cachedSettings?.customerServiceUrl;
        }
        if (serviceUrl == null || serviceUrl.isEmpty) {
          _showError('客服通道暂未配置');
          return;
        }
        LinkUtils.openLink(context, serviceUrl);
      },
    );
  }

  Widget _buildVersionText() {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final version = snapshot.hasData ? 'v${snapshot.data!.version}' : '';
        return Text(
          version,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFFC9A84C),
          ),
        );
      },
    );
  }
}