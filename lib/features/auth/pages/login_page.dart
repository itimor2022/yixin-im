// 文件用途：实现 LoginPage 页面及其交互流程，属于用户认证。
// 核心逻辑：收集账号凭证并执行登录，处理验证码/设备校验、加载态和失败提示，成功后交给会话协调器完成跳转。
import 'dart:async';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme_preset.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/hot_update_sdk_adapter.dart';
import '../../../core/router/redirect_utils.dart';
import '../../../core/services/device_service.dart';
import '../../../core/utils/link_utils.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/desktop/auth_desktop_layout.dart';
import 'agreement_page.dart';
import 'forgot_password_page.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../settings/pages/network_settings_page.dart';
import '../../../core/services/server_discovery.dart';

final _loginAppVersionProvider = FutureProvider<PackageInfo>((ref) async {
  return PackageInfo.fromPlatform();
});

/// 登录页面
String _loginText(
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

// 关键声明：login page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _agreedToTerms = false; // 是否同意协议
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
  String? _quickRegisterRequestId;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
  }


  void _openNetworkSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NetworkSettingsPage()),
    );
  }
  @override
  void dispose() {
    _qrLoginPollTimer?.cancel();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _postLoginLocation() {
    final redirect = GoRouterState.of(context).uri.queryParameters['redirect'];
    return safeInAppRedirect(redirect) ?? '/home';
  }

  void _goAfterLogin() {
    final location = _postLoginLocation();
    debugPrint('[Login] Navigating to $location');
    context.go(location);
  }

  void _goToRegister() {
    final redirect = safeInAppRedirect(
      GoRouterState.of(context).uri.queryParameters['redirect'],
    );
    context.go(
      redirect == null
          ? '/register'
          : '/register?redirect=${Uri.encodeComponent(redirect)}',
    );
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBackground : AppColors.lightSurface;
    final screenWidth = MediaQuery.of(context).size.width;

    // 桌面端或宽屏使用桌面布局
    if (PlatformUtils.isPhysicalDesktop || screenWidth >= 600) {
      return AuthDesktopLayout(
        child: _buildLoginContent(isDark),
      );
    }

    // 移动端：主题渐变背景 + 毛玻璃卡片
    final preset = ref.watch(appThemePresetProvider);
    final colors = AppThemePresets.of(preset);
    final gradient = isDark ? colors.loginGradientDark : colors.loginGradientLight;

    return Scaffold(
      backgroundColor: colors.primaryA,
      body: Stack(
        children: [
          // 主题渐变背景
          Positioned.fill(
            child: Container(decoration: BoxDecoration(gradient: gradient)),
          ),
          // 装饰圆圈 - 左上
          Positioned(
            top: -80,
            right: -50,
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(isDark ? 0.05 : 0.15),
              ),
            ),
          ),
          // 装饰圆圈 - 右下
          Positioned(
            bottom: 8,
            left: 0,
            right: 0,
            child: Consumer(
              builder: (context, ref, _) {
                final versionAsync = ref.watch(_loginAppVersionProvider);
                return versionAsync.when(
                  data: (info) => Text(
                    '${info.appName} v${info.version}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
            ),
          ),
          Positioned(
            bottom: 60,
            left: -90,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(isDark ? 0.03 : 0.10),
              ),
            ),
          ),
          // 装饰小圆圈
          Positioned(
            top: 160,
            left: 30,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.primaryB.withOpacity(isDark ? 0.3 : 0.4),
              ),
            ),
          ),
          // 内容区
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 56),
                  // Logo
                  _buildLogo(),
                  const SizedBox(height: 28),
                  // 毛玻璃表单卡片
                  ClipRRect(
                    borderRadius: BorderRadius.circular(32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(28, 36, 28, 28),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.black.withOpacity(0.50)
                              : Colors.white.withOpacity(0.80),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: Colors.white.withOpacity(isDark ? 0.10 : 0.60),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: colors.primaryA.withOpacity(0.25),
                              blurRadius: 40,
                              offset: const Offset(0, 20),
                            ),
                          ],
                        ),
                        child: _buildLoginContent(isDark),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 底部链接放在卡片外，显示在渐变背景上
                  _buildBottom(isDark, AppLocalizations(ref.watch(languageProvider))),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 登录内容（共享）
  Widget _buildLoginContent(bool isDark) {
    final isDesktop = PlatformUtils.isPhysicalDesktop ||
        MediaQuery.of(context).size.width >= 600;
    final l10n = AppLocalizations(ref.watch(languageProvider));
    final appName =
        ref.watch(systemSettingsProvider).valueOrNull?.displayName ??
            defaultAppDisplayName();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: isDesktop ? 40 : 0),

        // Logo（桌面端隐藏，移动端已在卡片外显示）
        if (isDesktop) ...[
          _buildLogo(),
          const SizedBox(height: 24),
        ],

        if (!(isDesktop && _showDesktopQrLogin)) ...[
          _buildTitle(isDark, l10n, appName),
          const SizedBox(height: 36),
        ],

        // 登录表单
        if (isDesktop && _showDesktopQrLogin)
          _buildDesktopQrLoginSection(isDark, l10n)
        else
          _buildLoginForm(isDark, l10n),

        SizedBox(
          height: isDesktop && _showDesktopQrLogin ? 12 : 24,
        ),

        // 桌面端显示底部，移动端底部已移到卡片外
        if (isDesktop) _buildBottom(isDark, l10n),
        if (isDesktop) const SizedBox(height: 40),
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
    final patchNumber =
        ref.watch(shorebirdCurrentPatchNumberProvider).valueOrNull;

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
        if (patchNumber != null) ...[
          const SizedBox(height: 8),
          Text(
            _loginText(
              context,
              zhCN: '热更新已生效 · Patch #$patchNumber',
              zhTW: '熱更新已生效 · Patch #$patchNumber',
              en: 'Hot update active · Patch #$patchNumber',
            ),
            style: TextStyle(
              fontSize: 15,
              color: AppColors.textSecondaryFor(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLoginForm(bool isDark, AppLocalizations l10n) {
    final showDesktopQrSwitch = PlatformUtils.useDesktopLayout(context);
    final allowQuickRegister =
        ref.watch(systemSettingsProvider).valueOrNull?.allowQuickRegister ==
            true;
    final authError = ref.watch(
      authServiceProvider.select((state) => state.error),
    );
    final displayError = _errorMessage ?? authError;

    return Column(
      children: [
        // 用户名输入（完全禁用中文输入法）
        _buildUsernameField(isDark, l10n),

        const SizedBox(height: 16),

        // 密码输入
        _buildPasswordField(isDark, l10n),

        const SizedBox(height: 10),
        // 一左一右：左侧在线客服，右侧切换线路（样式保持一致）
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildForgotPasswordEntry(isDark),
            _buildNetworkSettingsEntry(isDark),
          ],
        ),

        if (showDesktopQrSwitch) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: Tooltip(
              message: _loginText(
                context,
                zhCN: '扫码登录',
                zhTW: '掃碼登入',
                en: 'Scan to sign in',
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _openDesktopQrLogin,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.emphasisSoftFor(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.qr_code_2_rounded,
                    color: AppColors.linkFor(context),
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
          child: displayError != null
              ? Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    displayError,
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

        if (allowQuickRegister) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Divider(color: AppColors.dividerFor(context))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _loginText(
                    context,
                    zhCN: '或者',
                    zhTW: '或者',
                    en: 'OR',
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiaryFor(context),
                  ),
                ),
              ),
              Expanded(child: Divider(color: AppColors.dividerFor(context))),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              key: const Key('quick_register_button'),
              onPressed: _isLoading ? null : _quickRegister,
              icon: const Icon(Icons.flash_on_rounded, size: 20),
              label: Text(
                _loginText(
                  context,
                  zhCN: '一键注册登录',
                  zhTW: '一鍵註冊登入',
                  en: 'One-Tap Registration',
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primaryFor(context),
                side: BorderSide(color: AppColors.primaryFor(context)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _loginText(
              context,
              zhCN: '无需填写资料，直接创建正式账号',
              zhTW: '無需填寫資料，直接建立正式帳號',
              en: 'Create a full account without filling out a form',
            ),
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textTertiaryFor(context),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildForgotPasswordEntry(bool isDark) {
    final settings = ref.read(systemSettingsProvider).valueOrNull;
    final url = settings?.onlineSupportUrl ?? '';

    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () {
          if (url.isNotEmpty) {
            LinkUtils.openLink(context, url);
          }
        },
        icon: Icon(Icons.headset_mic_outlined, size: 17,
            color: AppColors.textSecondaryFor(context)),
        label: Text(
          _loginText(
            context,
            zhCN: '在线客服',
            zhTW: '線上客服',
            en: 'Online Support',
          ),
          style: TextStyle(fontSize: 13),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
    );
  }
  /// 切换线路入口（样式与「在线客服」保持一致，位于右侧）
  Widget _buildNetworkSettingsEntry(bool isDark) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton.icon(
        onPressed: _openNetworkSettings,
        icon: Icon(Icons.swap_horiz_rounded, size: 17,
            color: AppColors.textSecondaryFor(context)),
        label: Text(
          _loginText(
            context,
            zhCN: '切换线路',
            zhTW: '切換線路',
            en: 'Switch Line',
          ),
          style: TextStyle(fontSize: 13),
        ),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
        ),
      ),
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
        _usernameController.text = username;
        _clearError();
      }
    }
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
    ref.read(authServiceProvider.notifier).clearError();
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

  /// 用户名输入框 - 完全禁用中文输入
  Widget _buildUsernameField(bool isDark, AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBackgroundFor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        key: const Key('login_username_field'),
        controller: _usernameController,
        keyboardType: TextInputType.visiblePassword,
        autocorrect: false,
        enableSuggestions: false,
        enableIMEPersonalizedLearning: false,
        onChanged: (_) => _clearError(),
        style: TextStyle(
          fontSize: 16,
          color: AppColors.textPrimaryFor(context),
        ),
        decoration: InputDecoration(
          hintText: l10n.usernameLabel,
          hintStyle: TextStyle(
            color: AppColors.inputHintFor(context),
          ),
          prefixIcon: Icon(
            Icons.person_outline_rounded,
            color: AppColors.inputIconFor(context),
            size: 22,
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
        color: AppColors.inputBackgroundFor(context),
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
          color: AppColors.textPrimaryFor(context),
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: AppColors.inputHintFor(context),
          ),
          prefixIcon: Icon(
            icon,
            color: AppColors.inputIconFor(context),
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
        color: AppColors.inputBackgroundFor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        key: const Key('login_password_field'),
        controller: _passwordController,
        obscureText: _obscurePassword,
        onChanged: (_) => _clearError(),
        style: TextStyle(
          fontSize: 16,
          color: AppColors.textPrimaryFor(context),
        ),
        decoration: InputDecoration(
          hintText: l10n.passwordLabel,
          hintStyle: TextStyle(
            color: AppColors.inputHintFor(context),
          ),
          prefixIcon: Icon(
            Icons.lock_outline_rounded,
            color: AppColors.inputIconFor(context),
            size: 22,
          ),
          suffixIcon: IconButton(
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
            icon: Icon(
              _obscurePassword
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
        key: const Key('login_submit_button'),
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryFor(context),
          foregroundColor: AppColors.onPrimaryFor(context),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.onPrimaryFor(context),
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
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              l10n.get('no_account_yet') ??
                  _loginText(
                    context,
                    zhCN: '还没有账号？',
                    zhTW: '還沒有帳號？',
                    en: "Don't have an account yet?",
                  ),
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondaryFor(context),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: _goToRegister,
              child: Text(
                l10n.registerNow,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.linkFor(context),
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
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  key: const Key('login_terms_checkbox'),
                  value: _agreedToTerms,
                  onChanged: (value) {
                    _setAgreement(value ?? false);
                  },
                  activeColor: AppColors.controlActiveFor(context),
                  checkColor: AppColors.onControlActiveFor(context),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  side: BorderSide(
                    color: AppColors.controlBorderFor(context),
                    width: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondaryFor(context),
                      height: 1.2,
                    ),
                    children: [
                      TextSpan(text: l10n.agreeTermsPrefix),
                      TextSpan(
                        text: _loginText(
                          context,
                          zhCN: '《用户协议》',
                          zhTW: '《使用者協議》',
                          en: 'User Agreement',
                        ),
                        style: TextStyle(
                          color: AppColors.linkFor(context),
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap =
                              () => _openAgreement(AgreementType.userAgreement),
                      ),
                      TextSpan(
                        text: _loginText(
                          context,
                          zhCN: '和',
                          zhTW: '和',
                          en: ' and ',
                        ),
                      ),
                      TextSpan(
                        text: _loginText(
                          context,
                          zhCN: '《隐私政策》',
                          zhTW: '《隱私政策》',
                          en: 'Privacy Policy',
                        ),
                        style: TextStyle(
                          color: AppColors.linkFor(context),
                        ),
                        recognizer: TapGestureRecognizer()
                          ..onTap =
                              () => _openAgreement(AgreementType.privacyPolicy),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopQrLoginSection(bool isDark, AppLocalizations l10n) {
    final cardColor =
        isDark ? AppColors.darkCard : AppColors.lightInputBackground;
    final borderColor =
        isDark ? Colors.white10 : Colors.black.withOpacity(0.06);
    final secondaryTextColor = AppColors.textSecondaryFor(context);
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
                    _loginText(
                      context,
                      zhCN: '扫码登录',
                      zhTW: '掃碼登入',
                      en: 'QR Login',
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimaryFor(context),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: (!_agreedToTerms || _isQrLoginLoading)
                        ? null
                        : _createDesktopQrLogin,
                    tooltip: _loginText(
                      context,
                      zhCN: '刷新二维码',
                      zhTW: '重新整理 QR 碼',
                      en: 'Refresh QR Code',
                    ),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _loginText(
                  context,
                  zhCN: '打开手机应用，使用扫一扫确认登录这台桌面设备',
                  zhTW: '打開手機應用，使用掃一掃確認登入這台桌面設備',
                  en: 'Open the mobile app and scan to confirm login on this desktop device',
                ),
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
                Text(
                  _loginText(
                    context,
                    zhCN: '请先阅读并同意用户协议和隐私政策',
                    zhTW: '請先閱讀並同意使用者協議和隱私政策',
                    en: 'Please read and agree to the Terms and Privacy Policy first',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.error,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else if (_isQrLoginSigningIn)
                Text(
                  _loginText(
                    context,
                    zhCN: '登录确认中...',
                    zhTW: '登入確認中...',
                    en: 'Signing in...',
                  ),
                  style: TextStyle(
                    color: AppColors.linkFor(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (_qrLoginStatus == 'expired')
                Text(
                  _loginText(
                    context,
                    zhCN: '二维码已过期，请点击右上角刷新',
                    zhTW: 'QR 碼已過期，請點擊右上角重新整理',
                    en: 'The QR code has expired. Tap refresh in the top-right corner.',
                  ),
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
                  _loginText(
                    context,
                    zhCN: '二维码有效期 2 分钟',
                    zhTW: 'QR 碼有效期 2 分鐘',
                    en: 'QR code valid for 2 minutes',
                  ),
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
            style: TextStyle(
              fontSize: 14,
              color: AppColors.linkFor(context),
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
    if (!PlatformUtils.useDesktopLayout(context)) return;

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
        _qrLoginError = _serverMessage(
          raw: response.message,
          zhCN: '二维码生成失败',
          zhTW: 'QR 碼生成失敗',
          en: 'Failed to generate QR code',
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isQrLoginLoading = false;
        _qrLoginStatus = 'error';
        _qrLoginError = _loginText(
          context,
          zhCN: '二维码生成失败',
          zhTW: 'QR 碼生成失敗',
          en: 'Failed to generate QR code',
        );
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
          _goAfterLogin();
          return;
        }

        setState(() {
          _isQrLoginSigningIn = false;
          _qrLoginStatus = 'error';
          _qrLoginError = _loginText(
            context,
            zhCN: '二维码登录失败，请刷新后重试',
            zhTW: 'QR 碼登入失敗，請重新整理後再試',
            en: 'QR login failed. Please refresh and try again.',
          );
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

    final username = _usernameController.text.trim();

    if (username.isEmpty) {
      _showError(l10n.pleaseEnterUsername);
      return;
    }

    // 验证用户名格式（只允许英文、数字、下划线）
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(username)) {
      _showError(
        l10n.get('username_format_error') ??
            _loginText(
              context,
              zhCN: '用户名只能包含英文、数字和下划线',
              zhTW: '使用者名稱只能包含英文、數字和底線',
              en: 'Username can only contain letters, numbers, and underscores',
            ),
      );
      return;
    }

    if (username.length < 3) {
      _showError(
        l10n.get('username_min_length') ??
            _loginText(
              context,
              zhCN: '用户名至少 3 位',
              zhTW: '使用者名稱至少 3 位',
              en: 'Username must be at least 3 characters',
            ),
      );
      return;
    }

    if (_passwordController.text.isEmpty) {
      _showError(l10n.pleaseEnterPassword);
      return;
    }

    if (_passwordController.text.length < 6) {
      _showError(
        l10n.get('password_min_length') ??
            _loginText(
              context,
              zhCN: '密码至少 6 位',
              zhTW: '密碼至少 6 位',
              en: 'Password must be at least 6 characters',
            ),
      );
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isLoading = true);

    try {
      // 获取持久化设备信息。DeviceService 内部会对首次启动存储异常降级。
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
        username: username,
        password: _passwordController.text.trim(),
        deviceId: deviceId,
        deviceType: deviceType,
        deviceName: deviceName,
      );

      if (!mounted) return;
      debugPrint('[Login] response.code: ${response.code}');
      debugPrint('[Login] response.isSuccess: ${response.isSuccess}');
      debugPrint('[Login] response.message: ${response.message}');

      if (response.isSuccess) {
        _goAfterLogin();
      } else if (response.code == 1001) {
        await _handleDeviceLockChallenge(response);
      } else if (response.code == 1007) {
        await _handleTwoStepChallenge(response);
      } else if (response.code == 1008) {
        await _showAccountBannedDialog(response);
      } else {
        debugPrint('[Login] Login failed: ${response.message}');
        _showError(
          _serverMessage(
            raw: response.message,
            zhCN: '登录失败，请稍后重试',
            zhTW: '登入失敗，請稍後重試',
            en: 'Login failed. Please try again later.',
          ),
        );
      }
    } catch (e) {
      debugPrint('[Login] Unexpected login error: $e');
      if (mounted) {
        _showError(
          _loginText(
            context,
            zhCN: '登录初始化失败，请直接重试',
            zhTW: '登入初始化失敗，請直接重試',
            en: 'Login initialization failed. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showAccountBannedDialog(ApiResponse response) async {
    final rawData = response.data;
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : const <String, dynamic>{};
    final reason = data['reason']?.toString().trim();
    final settings = ref.read(systemSettingsProvider).valueOrNull;
    final supportUrl = settings?.onlineSupportUrl ?? '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_loginText(
          dialogContext,
          zhCN: '账号已被封禁',
          zhTW: '帳號已被封禁',
          en: 'Account banned',
        )),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_loginText(
              dialogContext,
              zhCN: '原因：${reason?.isNotEmpty == true ? reason : '违反平台使用规则'}',
              zhTW: '原因：${reason?.isNotEmpty == true ? reason : '違反平台使用規則'}',
              en: 'Reason: ${reason?.isNotEmpty == true ? reason : 'Policy violation'}',
            )),
            const SizedBox(height: 10),
            Text(_loginText(
              dialogContext,
              zhCN: '期限：永久，直至管理员解除',
              zhTW: '期限：永久，直至管理員解除',
              en: 'Duration: Until an administrator lifts the ban',
            )),
            const SizedBox(height: 10),
            Text(_loginText(
              dialogContext,
              zhCN: '如有异议，可联系在线客服提交申诉。',
              zhTW: '如有異議，可聯絡線上客服提交申訴。',
              en: 'Contact support to submit an appeal.',
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_loginText(
              dialogContext,
              zhCN: '关闭',
              zhTW: '關閉',
              en: 'Close',
            )),
          ),
          TextButton.icon(
            key: const ValueKey('banned_account_appeal'),
            onPressed: () async {
              if (supportUrl.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_loginText(
                      context,
                      zhCN: '客服信息暂未配置，请稍后重试',
                      zhTW: '客服資訊暫未設定，請稍後重試',
                      en: 'Support is not configured yet. Please try later.',
                    )),
                  ),
                );
                return;
              }
              Navigator.pop(dialogContext);
              await LinkUtils.openLink(context, supportUrl);
            },
            icon: const Icon(Icons.support_agent_rounded),
            label: Text(_loginText(
              dialogContext,
              zhCN: '联系客服申诉',
              zhTW: '聯絡客服申訴',
              en: 'Contact support',
            )),
          ),
        ],
      ),
    );
  }

  Future<void> _quickRegister() async {
    if (!_agreedToTerms) {
      _showError(AppLocalizations.of(context).pleaseAgreeTerms);
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    _quickRegisterRequestId ??= const Uuid().v4();
    final deviceResults = await Future.wait<String>([
      DeviceService.getDeviceId(),
      DeviceService.getDeviceName(),
    ]);
    final response = await ref.read(authServiceProvider.notifier).quickRegister(
          deviceId: deviceResults[0],
          requestId: _quickRegisterRequestId!,
          deviceType: DeviceService.getDeviceType(),
          deviceName: deviceResults[1],
        );

    if (!mounted) return;
    setState(() => _isLoading = false);
    if (response.isSuccess) {
      _goAfterLogin();
      return;
    }
    _showError(
      _serverMessage(
        raw: response.message,
        zhCN: '一键注册失败，请稍后重试',
        zhTW: '一鍵註冊失敗，請稍後重試',
        en: 'Quick registration failed. Please try again later.',
      ),
    );
  }

  Future<void> _handleDeviceLockChallenge(ApiResponse response) async {
    final raw = response.data;
    if (raw is! Map) {
      _showError(
        _loginText(
          context,
          zhCN: '设备锁验证信息异常，请重试',
          zhTW: '裝置鎖驗證資訊異常，請重試',
          en: 'Device lock verification data is invalid. Please try again.',
        ),
      );
      return;
    }
    final data = Map<String, dynamic>.from(raw);
    final ticket = data['verify_ticket']?.toString() ?? '';
    if (ticket.isEmpty) {
      _showError(
        _loginText(
          context,
          zhCN: '设备锁验证信息异常，请重试',
          zhTW: '裝置鎖驗證資訊異常，請重試',
          en: 'Device lock verification data is invalid. Please try again.',
        ),
      );
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
              title: Text(
                _loginText(
                  context,
                  zhCN: '新设备登录验证',
                  zhTW: '新裝置登入驗證',
                  en: 'New Device Verification',
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _loginText(
                      context,
                      zhCN: '请输入短信验证码完成设备验证',
                      zhTW: '請輸入簡訊驗證碼完成裝置驗證',
                      en: 'Enter the SMS verification code to complete device verification',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      hintText: _loginText(
                        context,
                        zhCN: '6位验证码',
                        zhTW: '6 位驗證碼',
                        en: '6-digit code',
                      ),
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
                  child: Text(
                    _loginText(
                      context,
                      zhCN: '取消',
                      zhTW: '取消',
                      en: 'Cancel',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final code = codeController.text.trim();
                          if (code.length < 4) {
                            setStateDialog(
                              () => localError = _loginText(
                                context,
                                zhCN: '请输入正确的验证码',
                                zhTW: '請輸入正確的驗證碼',
                                en: 'Enter a valid verification code',
                              ),
                            );
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
                          if (verifyResp.code == 1007) {
                            Navigator.pop(context, false);
                            await Future<void>.delayed(Duration.zero);
                            if (mounted) {
                              await _handleTwoStepChallenge(verifyResp);
                            }
                            return;
                          }
                          setStateDialog(() {
                            isSubmitting = false;
                            localError = _serverMessage(
                              raw: verifyResp.message,
                              zhCN: '验证失败',
                              zhTW: '驗證失敗',
                              en: 'Verification failed.',
                            );
                          });
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _loginText(
                            context,
                            zhCN: '验证',
                            zhTW: '驗證',
                            en: 'Verify',
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
    codeController.dispose();

    if (verified == true && mounted) {
      _goAfterLogin();
    }
  }

  Future<void> _handleTwoStepChallenge(ApiResponse response) async {
    final raw = response.data;
    if (raw is! Map) {
      _showError(
        _loginText(
          context,
          zhCN: '两步验证信息异常，请重新登录',
          zhTW: '兩步驗證資訊異常，請重新登入',
          en: 'Two-step verification data is invalid. Please sign in again.',
        ),
      );
      return;
    }
    final data = Map<String, dynamic>.from(raw);
    final ticket = data['verify_ticket']?.toString() ?? '';
    final hint = data['password_hint']?.toString().trim() ?? '';
    if (ticket.isEmpty) {
      _showError(
        _loginText(
          context,
          zhCN: '两步验证已过期，请重新登录',
          zhTW: '兩步驗證已過期，請重新登入',
          en: 'Two-step verification expired. Please sign in again.',
        ),
      );
      return;
    }

    final passwordController = TextEditingController();
    bool isSubmitting = false;
    bool obscurePassword = true;
    String? localError;
    final verified = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: Text(
            _loginText(
              dialogContext,
              zhCN: '两步验证',
              zhTW: '兩步驗證',
              en: 'Two-Step Verification',
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _loginText(
                  dialogContext,
                  zhCN: '请输入你设置的二次登录密码。验证成功前不会进入账号。',
                  zhTW: '請輸入你設定的二次登入密碼。驗證成功前不會進入帳號。',
                  en: 'Enter your secondary sign-in password. Your account stays locked until it is verified.',
                ),
              ),
              if (hint.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _loginText(
                    dialogContext,
                    zhCN: '密码提示：$hint',
                    zhTW: '密碼提示：$hint',
                    en: 'Password hint: $hint',
                  ),
                  style: TextStyle(
                    color: AppColors.textSecondaryFor(dialogContext),
                    fontSize: 13,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  hintText: _loginText(
                    dialogContext,
                    zhCN: '二次登录密码',
                    zhTW: '二次登入密碼',
                    en: 'Secondary sign-in password',
                  ),
                  suffixIcon: IconButton(
                    onPressed: () => setStateDialog(
                      () => obscurePassword = !obscurePassword,
                    ),
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              if (localError != null) ...[
                const SizedBox(height: 8),
                Text(
                  localError!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: isSubmitting
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: Text(
                _loginText(
                  dialogContext,
                  zhCN: '取消登录',
                  zhTW: '取消登入',
                  en: 'Cancel Sign-In',
                ),
              ),
            ),
            TextButton(
              onPressed: isSubmitting
                  ? null
                  : () async {
                      final password = passwordController.text;
                      if (password.length < 6) {
                        setStateDialog(
                          () => localError = _loginText(
                            dialogContext,
                            zhCN: '请输入至少6位二次登录密码',
                            zhTW: '請輸入至少 6 位二次登入密碼',
                            en: 'Enter at least 6 characters.',
                          ),
                        );
                        return;
                      }
                      setStateDialog(() {
                        isSubmitting = true;
                        localError = null;
                      });
                      final verifyResponse = await ref
                          .read(authServiceProvider.notifier)
                          .verifyTwoStepLogin(
                            ticket: ticket,
                            password: password,
                          );
                      if (!mounted || !dialogContext.mounted) return;
                      if (verifyResponse.isSuccess) {
                        Navigator.pop(dialogContext, true);
                        return;
                      }
                      setStateDialog(() {
                        isSubmitting = false;
                        localError = _serverMessage(
                          raw: verifyResponse.message,
                          zhCN: '两步验证失败',
                          zhTW: '兩步驗證失敗',
                          en: 'Two-step verification failed.',
                        );
                      });
                    },
              child: isSubmitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _loginText(
                        dialogContext,
                        zhCN: '验证并登录',
                        zhTW: '驗證並登入',
                        en: 'Verify and Sign In',
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
    passwordController.dispose();
    if (verified == true && mounted) {
      _goAfterLogin();
    }
  }

  void _showError(String message) {
    setState(() => _errorMessage = message);
    // 同时震动反馈
    HapticFeedback.heavyImpact();
  }
}
