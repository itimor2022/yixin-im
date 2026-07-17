import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/device_service.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/desktop/auth_desktop_layout.dart';
import '../widgets/auth_form_widgets.dart';

/// 注册页面
class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _inviteCodeController = TextEditingController();

  String? _captchaId;
  String? _captchaB64;
  final _captchaController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;
  String _appName = '';

  // 邀请码是否必填：从后端 /app/settings 的 require_invite_code 字段读取
  // 后端同一开关也会在注册接口里再校验一次（服务器权威），前端只是提前提示。
  // 拉取失败时保持默认 false（选填），避免因网络抖动直接把注册流程卡死。
  bool _requireInviteCode = false;

  // 用户名检测状态
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameMessage;
  Timer? _usernameCheckTimer;

  @override
  void initState() {
    super.initState();
    _loadRegisterSettings();
    _fetchCaptcha();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appName = info.appName);
    });
  }

  Future<void> _loadRegisterSettings() async {
    try {
      final settings =
          await ref.read(systemSettingsServiceProvider).getSettings();
      if (!mounted) return;
      setState(() {
        _requireInviteCode = settings.requireInviteCode;
      });
    } catch (_) {
      // 使用默认值（邀请码选填），静默失败
    }
  }

  Future<void> _fetchCaptcha() async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.post('/auth/captcha');

      if (!mounted) return;

      if (response.isSuccess && response.data != null) {
        setState(() {
          _captchaId = response.data['captchaId'];
          _captchaB64 = response.data['captchaB64'];
          _captchaController.clear();
        });
      }
    } catch (e) {
      if (kDebugMode) debugPrint('获取验证码失败: $e');
    }
  }

  @override
  void dispose() {
    _usernameCheckTimer?.cancel();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nicknameController.dispose();
    _inviteCodeController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    final username = _phoneController.text.trim();

    // 取消之前的定时器
    _usernameCheckTimer?.cancel();

    // 重置状态
    if (username.isEmpty || username.length < 3) {
      setState(() {
        _isUsernameAvailable = null;
        _usernameMessage = null;
        _isCheckingUsername = false;
      });
      return;
    }

    // 防抖：500ms 后检测
    _usernameCheckTimer = Timer(const Duration(milliseconds: 500), () {
      _checkUsernameAvailability(username);
    });
  }

  Future<void> _checkUsernameAvailability(String username) async {
    if (username.length < 3) return;

    setState(() => _isCheckingUsername = true);

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.post('/auth/check-username', data: {
        'username': username,
      });

      if (!mounted) return;

      if (response.isSuccess && response.data != null) {
        setState(() {
          _isUsernameAvailable = response.data['available'] == true;
          _usernameMessage = response.data['message'] as String?;
          _isCheckingUsername = false;
        });
      } else {
        setState(() {
          _isUsernameAvailable = null;
          _usernameMessage = null;
          _isCheckingUsername = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUsernameAvailable = null;
        _usernameMessage = null;
        _isCheckingUsername = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;

    // 桌面端或宽屏使用桌面布局（保留原有实现）
    if (PlatformUtils.isDesktop || screenWidth >= 600) {
      return AuthDesktopLayout(
        showBackButton: true,
        onBack: _goBack,
        title: '注册账号',
        child: _buildRegisterContent(isDark),
      );
    }

    return _buildMobileLayout(isDark);
  }

  // ==================== 移动端全新布局（极简风格） ====================
  //
  // 与登录页保持一致：白底 / 无蓝色渐变 / logo + app 名称居中 /
  // 表单纯净，没有协议勾选。邀请码框始终显示，是否必填由后端
  // `require_invite_code` 系统开关下发（见 _requireInviteCode）。
  // 左上角保留返回按钮。

  Widget _buildMobileLayout(bool isDark) {
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
                        const SizedBox(height: 44),
                        _buildBrand(isDark),
                        const SizedBox(height: 32),
                        _buildSingleStep(isDark),
                      ],
                    ),
                  ),
                );
              },
            ),
            // 左上返回
            Positioned(
              top: 4,
              left: 4,
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _goBack,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 20,
                      color: isDark ? Colors.white70 : kAuthTextPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Logo + app 名称
  Widget _buildBrand(bool isDark) {
    final logoUrl = ref.watch(systemSettingsProvider).valueOrNull?.logoImageUrl;
    final settings = ref.watch(systemSettingsProvider).valueOrNull;
    final title = (settings?.systemName ?? '').trim().isNotEmpty
        ? settings!.systemName.trim()
        : (_appName.isNotEmpty ? _appName : '锦绣汇');
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: AuthLogoBadge(
            remoteUrl: logoUrl,
            size: 96,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            color: isDark ? Colors.white : kAuthTextPrimary,
          ),
        ),
      ],
    );
  }

  /// 单步注册：手机号 + 昵称 + 密码 + 确认密码 + 邀请码 + 图形验证码 + 注册
  ///
  /// 邀请码由后端 `require_invite_code` 系统开关控制是否必填。
  /// hint 文案会根据开关切换成「（必填）/（选填）」。
  Widget _buildSingleStep(bool isDark) {
    return Column(
      key: const ValueKey('single'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildUsernameField(isDark),
        const SizedBox(height: 14),
        _buildInputField(
          controller: _nicknameController,
          hint: '昵称',
          icon: Icons.face_rounded,
          keyboardType: TextInputType.text,
          isDark: isDark,
          inputFormatters: [
            LengthLimitingTextInputFormatter(50),
          ],
          enableIME: true,
          onChanged: (_) => _clearError(),
        ),
        const SizedBox(height: 14),
        _buildPasswordField(
          controller: _passwordController,
          hint: '密码（6-20位）',
          obscure: _obscurePassword,
          onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
          isDark: isDark,
          onChanged: (_) => _clearError(),
        ),
        const SizedBox(height: 14),
        _buildPasswordField(
          controller: _confirmPasswordController,
          hint: '确认密码',
          obscure: _obscureConfirmPassword,
          onToggle: () => setState(
              () => _obscureConfirmPassword = !_obscureConfirmPassword),
          isDark: isDark,
          onChanged: (_) => _clearError(),
        ),
        const SizedBox(height: 14),
        // 邀请码字段。是否必填由 _requireInviteCode 控制（后端下发）。
        // 后端 auth_handler.go 的注册接口对同一开关做二次强校验，前端只做提示。
        _buildInputField(
          controller: _inviteCodeController,
          hint: _requireInviteCode ? '邀请码（必填）' : '邀请码（选填）',
          icon: Icons.card_giftcard_rounded,
          keyboardType: TextInputType.text,
          isDark: isDark,
          inputFormatters: [
            LengthLimitingTextInputFormatter(32),
          ],
          onChanged: (_) => _clearError(),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _buildInputField(
                controller: _captchaController,
                hint: '验证码',
                icon: Icons.verified_user_outlined,
                keyboardType: TextInputType.number,
                isDark: isDark,
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
                        // contain：保持源图纵横比，防止拉伸让数字看起来大小不一
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
        if (_errorMessage != null) ...[
          const SizedBox(height: 14),
          _buildErrorMessage(isDark),
        ],
        const SizedBox(height: 24),
        _buildLoginRegisterRow(),
      ],
    );
  }

  /// 左右一行的登录/注册按钮组合。
  ///   - 左：登录（次要，OutlineButton）返回登录页
  ///   - 右：注册（主色，PrimaryButton）触发注册动作
  Widget _buildLoginRegisterRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: AuthOutlineButton(
            text: '登录',
            onPressed: () => context.goNamed('login'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: AuthPrimaryButton(
            text: '注册',
            loading: _isLoading,
            onPressed: _register,
          ),
        ),
      ],
    );
  }

  /// 注册内容（桌面端/宽屏共享，单步）
  ///
  /// "登录"入口已合并到 [_buildLoginRegisterRow] 里的左右并排按钮，
  /// 不再需要底部单独的"已有账号? 立即登录"链接。
  Widget _buildRegisterContent(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),
        _buildSingleStep(isDark),
        const SizedBox(height: 40),
      ],
    );
  }

  /// 手机号输入框（可用性检测状态显示在 suffix）
  Widget _buildUsernameField(bool isDark) {
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
      suffix: _buildUsernameStatusIcon(isDark),
    );
  }

  /// 用户名可用性状态图标（保留原业务逻辑）
  Widget? _buildUsernameStatusIcon(bool isDark) {
    if (_phoneController.text.trim().length < 7) {
      return null;
    }
    if (_isCheckingUsername) {
      return const Padding(
        padding: EdgeInsets.only(right: 14),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: kAuthPrimary,
          ),
        ),
      );
    }
    if (_isUsernameAvailable == true) {
      return Padding(
        padding: const EdgeInsets.only(right: 14),
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 300),
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Transform.scale(
              scale: value.clamp(0.0, 1.2),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Color(0xFF22C55E),
                size: 22,
              ),
            );
          },
        ),
      );
    }
    if (_isUsernameAvailable == false) {
      return Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Icon(
          Icons.cancel_rounded,
          color: AppColors.error,
          size: 22,
        ),
      );
    }
    return null;
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required TextInputType keyboardType,
    required bool isDark,
    List<TextInputFormatter>? inputFormatters,
    bool enableIME = false,
    ValueChanged<String>? onChanged,
  }) {
    return AuthInput(
      controller: controller,
      hint: hint,
      icon: icon,
      isDark: isDark,
      keyboardType: enableIME ? TextInputType.text : keyboardType,
      autocorrect: enableIME,
      enableSuggestions: enableIME,
      onChanged: onChanged,
      inputFormatters: inputFormatters,
    );
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    required bool isDark,
    ValueChanged<String>? onChanged,
  }) {
    return AuthInput(
      controller: controller,
      hint: hint,
      icon: Icons.lock_outline_rounded,
      isDark: isDark,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: onChanged,
      inputFormatters: [LengthLimitingTextInputFormatter(20)],
      suffix: IconButton(
        onPressed: onToggle,
        splashRadius: 20,
        icon: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          size: 20,
          color: isDark ? Colors.white38 : kAuthTextHint,
        ),
      ),
    );
  }

  Widget _buildErrorMessage(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.error.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 18),
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
    );
  }

  void _goBack() {
    HapticFeedback.selectionClick();
    context.goNamed('login');
  }

  void _register() async {
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
      _showError('请输入密码');
      return;
    }
    if (_passwordController.text.length < 6) {
      _showError('密码至少6位');
      return;
    }
    if (_confirmPasswordController.text != _passwordController.text) {
      _showError('两次输入的密码不一致');
      return;
    }
    if (_nicknameController.text.isEmpty) {
      _showError('请输入昵称');
      return;
    }
    // 邀请码必填校验：由后端 require_invite_code 开关决定
    if (_requireInviteCode && _inviteCodeController.text.trim().isEmpty) {
      _showError('当前注册必须填写邀请码');
      return;
    }
    if (_captchaController.text.trim().isEmpty) {
      _showError('请输入图形验证码');
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

    // 调用后端 API 注册
    final authService = ref.read(authServiceProvider.notifier);
    final response = await authService.register(
      phone: _phoneController.text.trim(),
      password: _passwordController.text,
      nickname: _nicknameController.text,
      deviceId: deviceId,
      deviceType: deviceType,
      deviceName: deviceName,
      captchaId: _captchaId ?? '',
      captchaCode: _captchaController.text.trim(),
      inviteCode: _inviteCodeController.text.trim().isNotEmpty
          ? _inviteCodeController.text.trim()
          : null,
    );

    if (!mounted) return;

    if (response.isSuccess) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      context.go('/home');
    } else {
      setState(() => _isLoading = false);
      _showError(response.message);
      _fetchCaptcha();
    }
  }

  void _clearError() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }
  }

  void _showError(String message) {
    setState(() => _errorMessage = message);
    HapticFeedback.heavyImpact();
  }
}
