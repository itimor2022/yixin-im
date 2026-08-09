// 文件用途：实现 _PresetAvatar 页面及其交互流程，属于用户认证。
// 核心逻辑：分阶段校验注册字段和验证码，提交注册请求后建立会话，并处理协议勾选和重复账号反馈。
import 'dart:async';
import 'package:universal_io/io.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lottie/lottie.dart';
import '../../../shared/widgets/web_safe_lottie.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/router/redirect_utils.dart';
import '../../../core/services/upload_service.dart';
import '../../../core/services/device_service.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/utils/phone_validation.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/desktop/auth_desktop_layout.dart';
import 'agreement_page.dart';

/// 注册页面
String _registerText(
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

// 关键声明：register page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
class _PresetAvatar {
  final String id;
  final String assetPath;
  final String gender;

  const _PresetAvatar(this.id, this.assetPath, this.gender);
}

const _presetAvatars = <_PresetAvatar>[
  _PresetAvatar('blue', 'assets/images/default_avatars/avatar_1.png', 'male'),
  _PresetAvatar('mint', 'assets/images/default_avatars/avatar_2.png', 'female'),
  _PresetAvatar('coral', 'assets/images/default_avatars/avatar_3.png', 'male'),
  _PresetAvatar(
    'lavender',
    'assets/images/default_avatars/avatar_4.png',
    'female',
  ),
  _PresetAvatar('amber', 'assets/images/default_avatars/avatar_5.png', 'male'),
  _PresetAvatar('teal', 'assets/images/default_avatars/avatar_6.png', 'female'),
];

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});

  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _inviteCodeController = TextEditingController();
  final _phoneController = TextEditingController();
  final _smsCodeController = TextEditingController();
  final _emailController = TextEditingController();
  final _emailCodeController = TextEditingController();

  int _currentStep = 0; // 0: 账号信息, 1: 个人资料
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false; // 是否同意协议
  String _selectedGender = _presetAvatars.first.gender;
  String? _avatarPath;
  Uint8List? _avatarBytes;
  _PresetAvatar? _selectedPresetAvatar = _presetAvatars.first;
  String? _errorMessage; // 错误提示信息

  // 用户名检测状态
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameMessage;
  Timer? _usernameCheckTimer;
  bool _requireInviteCode = false;
  bool _smsRegistrationReady = false;
  bool _emailRegistrationReady = false;
  String _registrationChannel = 'phone';
  bool _isSendingSMS = false;
  int _smsCountdown = 0;
  Timer? _smsTimer;
  bool _isSendingEmail = false;
  int _emailCountdown = 0;
  Timer? _emailTimer;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_onUsernameChanged);
    _loadRegisterSettings();
  }

  Future<void> _loadRegisterSettings() async {
    try {
      final settings = await ref
          .read(systemSettingsServiceProvider)
          .getSettings(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _requireInviteCode = settings.requireInviteCode;
        _smsRegistrationReady = settings.smsBindReady;
        _emailRegistrationReady = settings.emailRegistrationReady;
        if (!settings.smsBindReady && settings.emailRegistrationReady) {
          _registrationChannel = 'email';
        }
      });
    } catch (_) {
      // 使用默认值（邀请码选填）
    }
  }

  @override
  void dispose() {
    _usernameCheckTimer?.cancel();
    _usernameController.removeListener(_onUsernameChanged);
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nicknameController.dispose();
    _inviteCodeController.dispose();
    _phoneController.dispose();
    _smsCodeController.dispose();
    _emailController.dispose();
    _emailCodeController.dispose();
    _smsTimer?.cancel();
    _emailTimer?.cancel();
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

  String _loginLocation() {
    final redirect = safeInAppRedirect(
      GoRouterState.of(context).uri.queryParameters['redirect'],
    );
    if (redirect == null) return '/login';
    return '/login?redirect=${Uri.encodeComponent(redirect)}';
  }

  void _goToLogin() {
    context.go(_loginLocation());
  }

  void _onUsernameChanged() {
    final username = _usernameController.text.trim();

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
          _usernameMessage = localizeServerMessage(
            response.data['message'] as String?,
            fallbackZhCN: '用户名状态获取失败',
            fallbackZhTW: '取得使用者名稱狀態失敗',
            fallbackEn: 'Failed to check username status.',
          );
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
    final bgColor = isDark ? AppColors.darkBackground : AppColors.lightSurface;
    final screenWidth = MediaQuery.of(context).size.width;

    // 桌面端或宽屏使用桌面布局
    if (PlatformUtils.isPhysicalDesktop || screenWidth >= 600) {
      return AuthDesktopLayout(
        showBackButton: true,
        onBack: _goBack,
        title: _registerText(
          context,
          zhCN: '注册账号',
          zhTW: '註冊帳號',
          en: 'Create Account',
        ),
        child: _buildRegisterContent(isDark),
      );
    }

    // 移动端使用原始布局
    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            // 顶部区域
            _buildHeader(isDark),

            // 主内容区
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: _buildRegisterContent(isDark),
              ),
            ),

            // 底部
            _buildBottom(isDark),
          ],
        ),
      ),
    );
  }

  /// 注册内容（共享）
  Widget _buildRegisterContent(bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 20),

        // 步骤指示器
        _buildStepIndicator(isDark),

        const SizedBox(height: 40),

        // 表单内容
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _currentStep == 0
              ? _buildAccountStep(isDark)
              : _buildProfileStep(isDark),
        ),

        // 桌面端底部
        if (PlatformUtils.isPhysicalDesktop ||
            MediaQuery.of(context).size.width >= 600) ...[
          const SizedBox(height: 24),
          _buildBottomLink(isDark),
          const SizedBox(height: 40),
        ],
      ],
    );
  }

  /// 底部链接（仅桌面端在表单内显示）
  Widget _buildBottomLink(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          _registerText(
            context,
            zhCN: '已有账号？',
            zhTW: '已有帳號？',
            en: 'Already have an account?',
          ),
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondaryFor(context),
          ),
        ),
        TextButton(
          onPressed: _goToLogin,
          child: Text(
            _registerText(
              context,
              zhCN: '立即登录',
              zhTW: '立即登入',
              en: 'Log in now',
            ),
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
              _registerText(
                context,
                zhCN: '注册账号',
                zhTW: '註冊帳號',
                en: 'Create Account',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          const SizedBox(width: 48), // 平衡返回按钮
        ],
      ),
    );
  }

  Widget _buildStepIndicator(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 步骤1
        _buildStepDot(0, isDark),
        // 连接线
        Container(
          width: 60,
          height: 2,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: _currentStep >= 1
                ? AppColors.controlActiveFor(context)
                : AppColors.dividerFor(context),
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        // 步骤2
        _buildStepDot(1, isDark),
      ],
    );
  }

  Widget _buildStepDot(int step, bool isDark) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;

    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color:
            isActive ? AppColors.controlActiveFor(context) : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive
              ? AppColors.controlActiveFor(context)
              : AppColors.dividerFor(context),
          width: 2,
        ),
      ),
      child: Center(
        child: isCurrent && !isActive
            ? Text(
                '${step + 1}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondaryFor(context),
                ),
              )
            : isActive
                ? const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 18,
                  )
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondaryFor(context),
                    ),
                  ),
      ),
    );
  }

  Widget _buildAccountStep(bool isDark) {
    return Column(
      key: const ValueKey('account'),
      children: [
        // 小鸡破壳动画
        SizedBox(
          width: 100,
          height: 100,
          child: WebSafeLottie.asset(
            'assets/emoji/lottie/hatching_chick.json',
            repeat: true,
          ),
        ),

        const SizedBox(height: 20),

        Text(
          _registerText(
            context,
            zhCN: '创建账号',
            zhTW: '建立帳號',
            en: 'Create Your Account',
          ),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          _registerText(
            context,
            zhCN: '设置您的登录账号和密码',
            zhTW: '設定您的登入帳號和密碼',
            en: 'Set your login account and password',
          ),
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondaryFor(context),
          ),
        ),

        const SizedBox(height: 32),

        // 用户名（纯英文，禁用中文输入法）
        _buildUsernameField(isDark),

        if (_smsRegistrationReady || _emailRegistrationReady) ...[
          const SizedBox(height: 16),
          if (_smsRegistrationReady && _emailRegistrationReady) ...[
            _buildRegistrationChannelSelector(),
            const SizedBox(height: 12),
          ],
          if (_registrationChannel == 'email')
            _buildEmailRegistrationFields(isDark)
          else
            _buildPhoneRegistrationFields(isDark),
        ],

        const SizedBox(height: 16),

        // 密码
        _buildPasswordField(
          controller: _passwordController,
          hint: _registerText(
            context,
            zhCN: '密码（6-20位）',
            zhTW: '密碼（6-20位）',
            en: 'Password (6-20 chars)',
          ),
          obscure: _obscurePassword,
          onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
          isDark: isDark,
          onChanged: (_) => _clearError(),
        ),

        const SizedBox(height: 16),

        // 确认密码
        _buildPasswordField(
          controller: _confirmPasswordController,
          hint: _registerText(
            context,
            zhCN: '确认密码',
            zhTW: '確認密碼',
            en: 'Confirm password',
          ),
          obscure: _obscureConfirmPassword,
          onToggle: () => setState(
              () => _obscureConfirmPassword = !_obscureConfirmPassword),
          isDark: isDark,
          onChanged: (_) => _clearError(),
        ),

        // 错误提示
        if (_errorMessage != null && _currentStep == 0) ...[
          const SizedBox(height: 16),
          _buildErrorMessage(isDark),
        ],

        const SizedBox(height: 24),

        _buildButton(
          onPressed: _nextStep,
          text: _registerText(
            context,
            zhCN: '下一步',
            zhTW: '下一步',
            en: 'Next',
          ),
        ),
      ],
    );
  }

  Widget _buildProfileStep(bool isDark) {
    return Column(
      key: const ValueKey('profile'),
      children: [
        // 头像
        GestureDetector(
          onTap: _pickAvatar,
          child: Stack(
            children: [
              _avatarBytes != null
                  ? ClipOval(
                      child: Image.memory(
                        _avatarBytes!,
                        width: 100,
                        height: 100,
                        fit: BoxFit.cover,
                      ),
                    )
                  : _avatarPath != null
                      ? CircleAvatar(
                          radius: 50,
                          backgroundImage: FileImage(File(_avatarPath!)),
                        )
                      : _selectedPresetAvatar != null
                          ? ClipOval(
                              child: Image.asset(
                                _selectedPresetAvatar!.assetPath,
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                              ),
                            )
                          : AvatarWidget(
                              name: _nicknameController.text.isEmpty
                                  ? '?'
                                  : _nicknameController.text,
                              size: 100,
                            ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.controlActiveFor(context),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? const Color(0xFF0E0E0E) : Colors.white,
                      width: 3,
                    ),
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ).animate().fadeIn().scale(
              begin: const Offset(0.9, 0.9),
              curve: Curves.easeOut,
              duration: 300.ms,
            ),

        const SizedBox(height: 24),

        Text(
          _registerText(
            context,
            zhCN: '完善资料',
            zhTW: '完善資料',
            en: 'Complete Profile',
          ),
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          _registerText(
            context,
            zhCN: '设置您的昵称和头像',
            zhTW: '設定您的暱稱和頭像',
            en: 'Set your nickname and avatar',
          ),
          style: TextStyle(
            fontSize: 14,
            color: AppColors.textSecondaryFor(context),
          ),
        ),

        const SizedBox(height: 20),

        _buildPresetAvatarPicker(isDark),

        const SizedBox(height: 28),

        // 昵称（支持中文）
        _buildInputField(
          controller: _nicknameController,
          hint: _registerText(
            context,
            zhCN: '昵称',
            zhTW: '暱稱',
            en: 'Nickname',
          ),
          icon: Icons.face_rounded,
          keyboardType: TextInputType.text,
          isDark: isDark,
          inputFormatters: [
            LengthLimitingTextInputFormatter(50),
          ],
          enableIME: true, // 启用中文输入法
          onChanged: (_) => _clearError(),
        ),

        // 错误提示
        const SizedBox(height: 16),

        if (_errorMessage != null && _currentStep == 1) ...[
          const SizedBox(height: 16),
          _buildErrorMessage(isDark),
        ],

        const SizedBox(height: 16),

        // 邀请码
        _buildInputField(
          controller: _inviteCodeController,
          hint: _requireInviteCode
              ? _registerText(
                  context,
                  zhCN: '邀请码（必填）',
                  zhTW: '邀請碼（必填）',
                  en: 'Invite code (required)',
                )
              : _registerText(
                  context,
                  zhCN: '邀请码（选填）',
                  zhTW: '邀請碼（選填）',
                  en: 'Invite code (optional)',
                ),
          icon: Icons.card_giftcard_rounded,
          keyboardType: TextInputType.text,
          isDark: isDark,
        ),

        const SizedBox(height: 20),

        // 协议勾选
        _buildAgreementCheckbox(isDark),

        const SizedBox(height: 20),

        _buildButton(
          onPressed: _register,
          text: _registerText(
            context,
            zhCN: '完成注册',
            zhTW: '完成註冊',
            en: 'Finish Registration',
          ),
        ),
      ],
    );
  }

  /// 用户名输入框 - 完全禁用中文输入
  Widget _buildUsernameField(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBackgroundFor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _usernameController,
        // 使用 ASCII 类型完全禁用中文输入法
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
          hintText: _registerText(
            context,
            zhCN: '用户名（3-20位，仅限英文、数字、下划线）',
            zhTW: '用戶名（3-20位，僅限英文、數字、下劃線）',
            en: 'Username (3-20 chars, letters/numbers/underscores only)',
          ),
          hintStyle: TextStyle(
            color: AppColors.inputHintFor(context),
            fontSize: 15,
          ),
          prefixIcon: Icon(
            Icons.alternate_email_rounded,
            color: AppColors.inputIconFor(context),
            size: 22,
          ),
          suffixIcon: _buildUsernameStatusIcon(isDark),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9_]')),
          LengthLimitingTextInputFormatter(20),
        ],
      ),
    );
  }

  /// 用户名状态图标
  Widget? _buildUsernameStatusIcon(bool isDark) {
    if (_usernameController.text.trim().length < 3) {
      return null;
    }

    if (_isCheckingUsername) {
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.textTertiaryFor(context),
          ),
        ),
      );
    }

    if (_isUsernameAvailable == true) {
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 300),
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Transform.scale(
              scale: value.clamp(0.0, 1.2),
              child: Icon(
                Icons.check_circle_rounded,
                color: Colors.green,
                size: 22,
              ),
            );
          },
        ),
      );
    }

    if (_isUsernameAvailable == false) {
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Icon(
          Icons.cancel_rounded,
          color: Colors.red,
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
    bool enableIME = false, // 是否启用中文输入法
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBackgroundFor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        keyboardType: enableIME ? TextInputType.text : keyboardType,
        autocorrect: enableIME,
        enableSuggestions: enableIME,
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

  Widget _buildPhoneRegistrationFields(bool isDark) {
    return Column(
      children: [
        _buildInputField(
          controller: _phoneController,
          hint: _registerText(
            context,
            zhCN: '手机号',
            zhTW: '手機號碼',
            en: 'Phone number',
          ),
          icon: Icons.phone_android_rounded,
          keyboardType: TextInputType.phone,
          isDark: isDark,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          onChanged: (_) => _clearError(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildInputField(
                controller: _smsCodeController,
                hint: _registerText(
                  context,
                  zhCN: '短信验证码',
                  zhTW: '短信驗證碼',
                  en: 'SMS code',
                ),
                icon: Icons.sms_outlined,
                keyboardType: TextInputType.number,
                isDark: isDark,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (_) => _clearError(),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 52,
              child: FilledButton.tonal(
                key: const ValueKey('register_send_sms_code'),
                onPressed: (_isSendingSMS || _smsCountdown > 0)
                    ? null
                    : _sendRegistrationCode,
                child: _isSendingSMS
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _smsCountdown > 0
                            ? '${_smsCountdown}s'
                            : _registerText(
                                context,
                                zhCN: '获取验证码',
                                zhTW: '取得驗證碼',
                                en: 'Send code',
                              ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRegistrationChannelSelector() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<String>(
        key: const ValueKey('register_channel_selector'),
        segments: [
          ButtonSegment<String>(
            value: 'phone',
            icon: const Icon(Icons.phone_android_rounded, size: 18),
            label: Text(_registerText(
              context,
              zhCN: '手机',
              zhTW: '手機',
              en: 'Phone',
            )),
          ),
          ButtonSegment<String>(
            value: 'email',
            icon: const Icon(Icons.email_outlined, size: 18),
            label: Text(_registerText(
              context,
              zhCN: '邮箱',
              zhTW: '電子信箱',
              en: 'Email',
            )),
          ),
        ],
        selected: {_registrationChannel},
        showSelectedIcon: false,
        onSelectionChanged: (selection) {
          setState(() {
            _registrationChannel = selection.first;
            _errorMessage = null;
          });
        },
      ),
    );
  }

  Widget _buildEmailRegistrationFields(bool isDark) {
    return Column(
      children: [
        _buildInputField(
          controller: _emailController,
          hint: _registerText(
            context,
            zhCN: '邮箱地址',
            zhTW: '電子信箱地址',
            en: 'Email address',
          ),
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          isDark: isDark,
          inputFormatters: [LengthLimitingTextInputFormatter(254)],
          onChanged: (_) => _clearError(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildInputField(
                controller: _emailCodeController,
                hint: _registerText(
                  context,
                  zhCN: '邮箱验证码',
                  zhTW: '電子信箱驗證碼',
                  en: 'Email code',
                ),
                icon: Icons.mark_email_read_outlined,
                keyboardType: TextInputType.number,
                isDark: isDark,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                onChanged: (_) => _clearError(),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 52,
              child: FilledButton.tonal(
                key: const ValueKey('register_send_email_code'),
                onPressed: (_isSendingEmail || _emailCountdown > 0)
                    ? null
                    : _sendRegistrationEmailCode,
                child: _isSendingEmail
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _emailCountdown > 0
                            ? '${_emailCountdown}s'
                            : _registerText(
                                context,
                                zhCN: '获取验证码',
                                zhTW: '取得驗證碼',
                                en: 'Send code',
                              ),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _sendRegistrationCode() async {
    final phone = _phoneController.text.trim();
    if (!isValidMainlandChinaMobile(phone)) {
      _showError(_registerText(
        context,
        zhCN: '请输入有效的手机号',
        zhTW: '請輸入有效的手機號碼',
        en: 'Enter a valid phone number',
      ));
      return;
    }
    setState(() => _isSendingSMS = true);
    final response = await ref
        .read(authServiceProvider.notifier)
        .sendRegistrationCode(phone);
    if (!mounted) return;
    setState(() => _isSendingSMS = false);
    if (!response.isSuccess) {
      _showError(response.message ?? '');
      return;
    }
    _smsTimer?.cancel();
    setState(() => _smsCountdown = 60);
    _smsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _smsCountdown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _smsCountdown = 0);
        return;
      }
      setState(() => _smsCountdown--);
    });
  }

  Future<void> _sendRegistrationEmailCode() async {
    final email = _emailController.text.trim();
    if (!_isValidEmail(email)) {
      _showError(_registerText(
        context,
        zhCN: '请输入有效的邮箱地址',
        zhTW: '請輸入有效的電子信箱地址',
        en: 'Enter a valid email address',
      ));
      return;
    }
    setState(() => _isSendingEmail = true);
    final response = await ref
        .read(authServiceProvider.notifier)
        .sendRegistrationEmailCode(email);
    if (!mounted) return;
    setState(() => _isSendingEmail = false);
    if (!response.isSuccess) {
      _showError(response.message ?? '');
      return;
    }
    _emailTimer?.cancel();
    setState(() => _emailCountdown = 60);
    _emailTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _emailCountdown <= 1) {
        timer.cancel();
        if (mounted) setState(() => _emailCountdown = 0);
        return;
      }
      setState(() => _emailCountdown--);
    });
  }

  bool _isValidEmail(String value) {
    return RegExp(
      r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$",
    ).hasMatch(value);
  }

  Widget _buildPasswordField({
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    required bool isDark,
    ValueChanged<String>? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.inputBackgroundFor(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
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

  Widget _buildErrorMessage(bool isDark) {
    // TG 风格 - 简洁的红色文字
    return Text(
      _errorMessage!,
      style: TextStyle(
        color: AppColors.error,
        fontSize: 14,
        fontWeight: FontWeight.w400,
      ),
      textAlign: TextAlign.center,
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

  Widget _buildBottom(bool isDark) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _registerText(
                    context,
                    zhCN: '已有账号？',
                    zhTW: '已有帳號？',
                    en: 'Already have an account?',
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondaryFor(context),
                  ),
                ),
                TextButton(
                  onPressed: _goToLogin,
                  child: Text(
                    _registerText(
                      context,
                      zhCN: '立即登录',
                      zhTW: '立即登入',
                      en: 'Log in now',
                    ),
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.linkFor(context),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _goBack() {
    HapticFeedback.selectionClick();
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      _goToLogin();
    }
  }

  Future<void> _nextStep() async {
    // 验证用户名
    final username = _usernameController.text.trim();
    if (username.isEmpty) {
      _showError(
        _registerText(
          context,
          zhCN: '请输入用户名',
          zhTW: '請輸入用戶名',
          en: 'Please enter a username',
        ),
      );
      return;
    }

    if (username.length < 3) {
      _showError(
        _registerText(
          context,
          zhCN: '用户名至少 3 位',
          zhTW: '用戶名至少 3 位',
          en: 'Username must be at least 3 characters',
        ),
      );
      return;
    }

    // 检查用户名可用性
    if (_isUsernameAvailable == false) {
      _showError(
        _usernameMessage ??
            _registerText(
              context,
              zhCN: '该用户名已被使用',
              zhTW: '該用戶名已被使用',
              en: 'This username is already taken',
            ),
      );
      return;
    }

    if (_isCheckingUsername) {
      _showError(
        _registerText(
          context,
          zhCN: '正在检查用户名可用性...',
          zhTW: '正在檢查用戶名可用性...',
          en: 'Checking username availability...',
        ),
      );
      return;
    }

    // 验证密码
    if (_passwordController.text.isEmpty) {
      _showError(
        _registerText(
          context,
          zhCN: '请输入密码',
          zhTW: '請輸入密碼',
          en: 'Please enter a password',
        ),
      );
      return;
    }

    if (_passwordController.text.length < 6) {
      _showError(
        _registerText(
          context,
          zhCN: '密码至少 6 位',
          zhTW: '密碼至少 6 位',
          en: 'Password must be at least 6 characters',
        ),
      );
      return;
    }

    // 验证确认密码
    if (_confirmPasswordController.text != _passwordController.text) {
      _showError(
        _registerText(
          context,
          zhCN: '两次输入的密码不一致',
          zhTW: '兩次輸入的密碼不一致',
          en: 'The two passwords do not match',
        ),
      );
      return;
    }

    if (_registrationChannel == 'phone' && _smsRegistrationReady) {
      final phone = _phoneController.text.trim();
      final smsCode = _smsCodeController.text.trim();
      if (!isValidMainlandChinaMobile(phone) ||
          !RegExp(r'^\d{6}$').hasMatch(smsCode)) {
        _showError(_registerText(
          context,
          zhCN: '请填写有效手机号和6位短信验证码',
          zhTW: '請填寫有效手機號和6位短信驗證碼',
          en: 'Enter a valid phone number and 6-digit SMS code',
        ));
        return;
      }

      setState(() => _isLoading = true);
      final response = await ref
          .read(authServiceProvider.notifier)
          .verifyRegistrationCode(phone: phone, smsCode: smsCode);
      if (!mounted) return;
      setState(() => _isLoading = false);
      if (_registrationChannel != 'phone' ||
          _phoneController.text.trim() != phone ||
          _smsCodeController.text.trim() != smsCode) {
        _showError(
          _registerText(
            context,
            zhCN: '手机号或验证码已修改，请重新校验',
            zhTW: '手機號碼或驗證碼已修改，請重新校驗',
            en: 'The phone number or code changed. Please verify it again.',
          ),
        );
        return;
      }
      if (!response.isSuccess) {
        _showError(
          _serverMessage(
            raw: response.message,
            zhCN: '短信验证码校验失败，请重新输入',
            zhTW: '短信驗證碼校驗失敗，請重新輸入',
            en: 'The SMS code could not be verified. Please try again.',
          ),
        );
        return;
      }
    }
    if (_registrationChannel == 'email' && _emailRegistrationReady) {
      if (!_isValidEmail(_emailController.text.trim()) ||
          !RegExp(r'^\d{6}$').hasMatch(_emailCodeController.text.trim())) {
        _showError(_registerText(
          context,
          zhCN: '请填写有效邮箱和6位邮箱验证码',
          zhTW: '請填寫有效電子信箱和6位驗證碼',
          en: 'Enter a valid email and 6-digit email code',
        ));
        return;
      }
    }

    HapticFeedback.mediumImpact();
    setState(() => _currentStep = 1);
  }

  Widget _buildPresetAvatarPicker(bool isDark) {
    return Column(
      children: [
        Text(
          _registerText(
            context,
            zhCN: '选择一个头像',
            zhTW: '選擇一個頭像',
            en: 'Choose an avatar',
          ),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: _presetAvatars.map((avatar) {
            final isSelected = _selectedPresetAvatar == avatar;
            return Semantics(
              label: _registerText(
                context,
                zhCN: '预设头像 ${_presetAvatars.indexOf(avatar) + 1}',
                zhTW: '預設頭像 ${_presetAvatars.indexOf(avatar) + 1}',
                en: 'Preset avatar ${_presetAvatars.indexOf(avatar) + 1}',
              ),
              selected: isSelected,
              button: true,
              child: GestureDetector(
                key: ValueKey('register_preset_avatar_${avatar.id}'),
                onTap: () {
                  if (PlatformUtils.isMobile) {
                    HapticFeedback.selectionClick();
                  }
                  setState(() {
                    _selectedPresetAvatar = avatar;
                    _selectedGender = avatar.gender;
                    _avatarBytes = null;
                    _avatarPath = null;
                  });
                },
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 52,
                      height: 52,
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? AppColors.controlActiveFor(context)
                              : (isDark ? Colors.white24 : Colors.black12),
                          width: isSelected ? 3 : 1,
                        ),
                      ),
                      child: ClipOval(
                        child: Image.asset(avatar.assetPath, fit: BoxFit.cover),
                      ),
                    ),
                    if (isSelected)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: AppColors.controlActiveFor(context),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF0E0E0E)
                                  : Colors.white,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            size: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _pickAvatar,
          icon: const Icon(Icons.photo_library_outlined, size: 18),
          label: Text(
            _registerText(
              context,
              zhCN: '从相册选择',
              zhTW: '從相簿選擇',
              en: 'Choose from gallery',
            ),
          ),
        ),
      ],
    );
  }

  void _pickAvatar() async {
    if (PlatformUtils.isMobile) {
      HapticFeedback.selectionClick();
    }
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      if (kIsWeb) {
        final bytes = await image.readAsBytes();
        setState(() {
          _selectedPresetAvatar = null;
          _avatarBytes = bytes;
          _avatarPath = image.path;
        });
      } else {
        setState(() {
          _selectedPresetAvatar = null;
          _avatarBytes = null;
          _avatarPath = image.path;
        });
      }
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

  /// 构建协议勾选框
  Widget _buildAgreementCheckbox(bool isDark) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _agreedToTerms = !_agreedToTerms;
        });
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
                setState(() {
                  _agreedToTerms = value ?? false;
                });
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
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondaryFor(context),
                height: 1.2,
              ),
              children: [
                TextSpan(
                  text: _registerText(
                    context,
                    zhCN: '我已阅读并同意',
                    zhTW: '我已閱讀並同意',
                    en: 'I have read and agree to ',
                  ),
                ),
                TextSpan(
                  text: _registerText(
                    context,
                    zhCN: '《用户协议》',
                    zhTW: '《用戶協議》',
                    en: '《User Agreement》',
                  ),
                  style: TextStyle(
                    color: AppColors.linkFor(context),
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => _openAgreement(AgreementType.userAgreement),
                ),
                TextSpan(
                  text: _registerText(
                    context,
                    zhCN: '和',
                    zhTW: '和',
                    en: ' and ',
                  ),
                ),
                TextSpan(
                  text: _registerText(
                    context,
                    zhCN: '《隐私政策》',
                    zhTW: '《隱私政策》',
                    en: '《Privacy Policy》',
                  ),
                  style: TextStyle(
                    color: AppColors.linkFor(context),
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => _openAgreement(AgreementType.privacyPolicy),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _register() async {
    // 检查是否同意协议
    if (!_agreedToTerms) {
      _showError(
        _registerText(
          context,
          zhCN: '请先阅读并同意用户协议和隐私政策',
          zhTW: '請先閱讀並同意用戶協議和隱私政策',
          en: 'Please read and agree to the User Agreement and Privacy Policy',
        ),
      );
      return;
    }

    if (_registrationChannel == 'phone' && _smsRegistrationReady) {
      final phone = _phoneController.text.trim();
      final code = _smsCodeController.text.trim();
      if (!isValidMainlandChinaMobile(phone) ||
          !RegExp(r'^\d{6}$').hasMatch(code)) {
        _showError(_registerText(
          context,
          zhCN: '请填写有效手机号和6位短信验证码',
          zhTW: '請填寫有效手機號碼和6位短信驗證碼',
          en: 'Enter a valid phone number and 6-digit SMS code',
        ));
        return;
      }
    }
    if (_registrationChannel == 'email' && _emailRegistrationReady) {
      final email = _emailController.text.trim();
      final code = _emailCodeController.text.trim();
      if (!_isValidEmail(email) || !RegExp(r'^\d{6}$').hasMatch(code)) {
        _showError(_registerText(
          context,
          zhCN: '请填写有效邮箱和6位邮箱验证码',
          zhTW: '請填寫有效電子信箱和6位驗證碼',
          en: 'Enter a valid email and 6-digit email code',
        ));
        return;
      }
    }

    if (_nicknameController.text.trim().isEmpty) {
      _showError(
        _registerText(
          context,
          zhCN: '请输入昵称',
          zhTW: '請輸入暱稱',
          en: 'Please enter a nickname',
        ),
      );
      return;
    }

    if (_requireInviteCode && _inviteCodeController.text.trim().isEmpty) {
      _showError(
        _registerText(
          context,
          zhCN: '当前注册必须填写邀请码',
          zhTW: '目前註冊必須填寫邀請碼',
          en: 'An invite code is required for registration',
        ),
      );
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

    if (!mounted) return;

    // 注册会立即触发全局路由跳转，先保存服务引用，避免上传完成后页面已销毁。
    final uploadService = ref.read(uploadServiceProvider);
    final api = ref.read(apiClientProvider);

    // 调用后端 API 注册
    final authService = ref.read(authServiceProvider.notifier);
    final response = await authService.register(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      nickname: _nicknameController.text.trim(),
      gender: _selectedGender,
      deviceId: deviceId,
      deviceType: deviceType,
      deviceName: deviceName,
      inviteCode: _inviteCodeController.text.trim().isNotEmpty
          ? _inviteCodeController.text.trim()
          : null,
      phone: _registrationChannel == 'phone' && _smsRegistrationReady
          ? _phoneController.text.trim()
          : null,
      smsCode: _registrationChannel == 'phone' && _smsRegistrationReady
          ? _smsCodeController.text.trim()
          : null,
      email: _registrationChannel == 'email' && _emailRegistrationReady
          ? _emailController.text.trim()
          : null,
      emailCode: _registrationChannel == 'email' && _emailRegistrationReady
          ? _emailCodeController.text.trim()
          : null,
    );

    if (response.isSuccess) {
      Future<void> saveAvatarUrl(String? avatarUrl) async {
        if (avatarUrl == null || avatarUrl.trim().isEmpty) {
          throw StateError('Avatar upload returned an empty URL');
        }
        final updateResponse =
            await api.put('/user/me', data: {'avatar': avatarUrl});
        if (!updateResponse.isSuccess) {
          throw StateError(
            'Avatar profile update failed: ${updateResponse.message}',
          );
        }
        await authService.getCurrentUser();
      }

      // 注册成功后，如果有头像则上传
      if (_avatarBytes != null) {
        try {
          final avatarUrl = await uploadService.uploadImageData(
            _avatarBytes!,
            'avatar.jpg',
          );
          await saveAvatarUrl(avatarUrl);
        } catch (e) {
          debugPrint('[Register] Avatar upload failed: $e');
        }
      } else if (_avatarPath != null) {
        try {
          final avatarUrl =
              await uploadService.uploadAvatar(XFile(_avatarPath!));
          await saveAvatarUrl(avatarUrl);
        } catch (e) {
          debugPrint('[Register] Avatar upload failed: $e');
          // 头像上传失败不阻塞注册流程
        }
      } else if (_selectedPresetAvatar != null) {
        try {
          final avatarData =
              await rootBundle.load(_selectedPresetAvatar!.assetPath);
          final avatarBytes = avatarData.buffer.asUint8List(
            avatarData.offsetInBytes,
            avatarData.lengthInBytes,
          );
          final avatarUrl = await uploadService.uploadImageData(
            avatarBytes,
            'avatar_${_selectedPresetAvatar!.id}.png',
          );
          await saveAvatarUrl(avatarUrl);
        } catch (e) {
          debugPrint('[Register] Preset avatar upload failed: $e');
          // 预设头像上传失败不阻塞注册流程
        }
      }

      // AuthService publishes authenticated only after persisting the complete
      // session. GoRouter owns the single post-registration transition. A
      // second context.go here can race that redirect and render a blank first
      // frame on iOS.
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } else {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(
        _serverMessage(
          raw: response.message,
          zhCN: '注册失败，请稍后重试',
          zhTW: '註冊失敗，請稍後重試',
          en: 'Registration failed. Please try again later.',
        ),
      );
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
