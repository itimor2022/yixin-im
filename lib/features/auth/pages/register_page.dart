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

import '../../../core/theme/app_colors.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/services/upload_service.dart';
import '../../../core/services/device_service.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/desktop/auth_desktop_layout.dart';
import 'agreement_page.dart';

/// 注册页面
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

  int _currentStep = 0; // 0: 账号信息, 1: 个人资料
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false; // 是否同意协议
  String? _avatarPath;
  Uint8List? _avatarBytes;
  String? _errorMessage; // 错误提示信息

  // 用户名检测状态
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameMessage;
  Timer? _usernameCheckTimer;
  bool _requireInviteCode = false;

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_onUsernameChanged);
    _loadRegisterSettings();
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
    super.dispose();
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
    final bgColor = isDark ? const Color(0xFF0E0E0E) : Colors.white;
    final screenWidth = MediaQuery.of(context).size.width;

    // 桌面端或宽屏使用桌面布局
    if (PlatformUtils.isDesktop || screenWidth >= 600) {
      return AuthDesktopLayout(
        showBackButton: true,
        onBack: _goBack,
        title: '注册账号',
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
        if (PlatformUtils.isDesktop ||
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
          '已有账号？',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
        TextButton(
          onPressed: () => context.goNamed('login'),
          child: Text(
            '立即登录',
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
              '注册账号',
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
                ? AppColors.primary
                : (isDark ? Colors.white24 : Colors.grey.shade300),
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
        color: isActive ? AppColors.primary : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive
              ? AppColors.primary
              : (isDark ? Colors.white24 : Colors.grey.shade300),
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
                  color: isDark ? Colors.white54 : Colors.black45,
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
                      color: isDark ? Colors.white54 : Colors.black45,
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
          child: Lottie.asset(
            'assets/emoji/lottie/hatching_chick.json',
            repeat: true,
          ),
        ),

        const SizedBox(height: 20),

        Text(
          '创建账号',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          '设置您的登录账号和密码',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),

        const SizedBox(height: 32),

        // 用户名（纯英文，禁用中文输入法）
        _buildUsernameField(isDark),

        const SizedBox(height: 16),

        // 密码
        _buildPasswordField(
          controller: _passwordController,
          hint: '密码（6-20位）',
          obscure: _obscurePassword,
          onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
          isDark: isDark,
          onChanged: (_) => _clearError(),
        ),

        const SizedBox(height: 16),

        // 确认密码
        _buildPasswordField(
          controller: _confirmPasswordController,
          hint: '确认密码',
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
          text: '下一步',
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
                    color: AppColors.primary,
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
          '完善资料',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          '设置您的昵称和头像',
          style: TextStyle(
            fontSize: 14,
            color: isDark ? Colors.white54 : Colors.black54,
          ),
        ),

        const SizedBox(height: 32),

        // 昵称（支持中文）
        _buildInputField(
          controller: _nicknameController,
          hint: '昵称',
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
        if (_errorMessage != null && _currentStep == 1) ...[
          const SizedBox(height: 16),
          _buildErrorMessage(isDark),
        ],

        const SizedBox(height: 16),

        // 邀请码
        _buildInputField(
          controller: _inviteCodeController,
          hint: _requireInviteCode ? '邀请码（必填）' : '邀请码（选填）',
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
          text: '完成注册',
        ),
      ],
    );
  }

  /// 用户名输入框 - 完全禁用中文输入
  Widget _buildUsernameField(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
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
          color: isDark ? Colors.white : Colors.black,
        ),
        decoration: InputDecoration(
          hintText: '用户名（3-20位，仅限英文、数字、下划线）',
          hintStyle: TextStyle(
            color: isDark ? Colors.white30 : Colors.black38,
            fontSize: 15,
          ),
          prefixIcon: Icon(
            Icons.alternate_email_rounded,
            color: isDark ? Colors.white30 : Colors.black38,
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
            color: isDark ? Colors.white38 : Colors.black38,
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
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
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
        color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
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
                  '已有账号？',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
                TextButton(
                  onPressed: () => context.goNamed('login'),
                  child: Text(
                    '立即登录',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.primary,
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
      context.goNamed('login');
    }
  }

  void _nextStep() {
    // 验证用户名
    if (_usernameController.text.isEmpty) {
      _showError('请输入用户名');
      return;
    }

    if (_usernameController.text.length < 3) {
      _showError('用户名至少3位');
      return;
    }

    // 检查用户名可用性
    if (_isUsernameAvailable == false) {
      _showError(_usernameMessage ?? '该用户名已被使用');
      return;
    }

    if (_isCheckingUsername) {
      _showError('正在检查用户名可用性...');
      return;
    }

    // 验证密码
    if (_passwordController.text.isEmpty) {
      _showError('请输入密码');
      return;
    }

    if (_passwordController.text.length < 6) {
      _showError('密码至少6位');
      return;
    }

    // 验证确认密码
    if (_confirmPasswordController.text != _passwordController.text) {
      _showError('两次输入的密码不一致');
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _currentStep = 1);
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
          _avatarBytes = bytes;
          _avatarPath = image.path;
        });
      } else {
        setState(() {
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
                const TextSpan(text: '我已阅读并同意'),
                TextSpan(
                  text: '《用户协议》',
                  style: TextStyle(
                    color: AppColors.primary,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => _openAgreement(AgreementType.userAgreement),
                ),
                const TextSpan(text: '和'),
                TextSpan(
                  text: '《隐私政策》',
                  style: TextStyle(
                    color: AppColors.primary,
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
      _showError('请先阅读并同意用户协议和隐私政策');
      return;
    }

    if (_nicknameController.text.isEmpty) {
      _showError('请输入昵称');
      return;
    }

    if (_requireInviteCode && _inviteCodeController.text.trim().isEmpty) {
      _showError('当前注册必须填写邀请码');
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
      username: _usernameController.text,
      password: _passwordController.text,
      nickname: _nicknameController.text,
      deviceId: deviceId,
      deviceType: deviceType,
      deviceName: deviceName,
      inviteCode: _inviteCodeController.text.trim().isNotEmpty
          ? _inviteCodeController.text.trim()
          : null,
    );

    if (!mounted) return;

    if (response.isSuccess) {
      // 注册成功后，如果有头像则上传
      if (_avatarBytes != null) {
        try {
          final uploadService = ref.read(uploadServiceProvider);
          final avatarUrl = await uploadService.uploadImageData(
            _avatarBytes!,
            'avatar.jpg',
          );

          if (avatarUrl != null) {
            final api = ref.read(apiClientProvider);
            await api.put('/user/me', data: {'avatar': avatarUrl});
            await authService.getCurrentUser();
          }
        } catch (e) {
          debugPrint('[Register] Avatar upload failed: $e');
        }
      } else if (_avatarPath != null) {
        try {
          final uploadService = ref.read(uploadServiceProvider);
          final avatarUrl =
              await uploadService.uploadAvatar(XFile(_avatarPath!));

          if (avatarUrl != null) {
            // 更新用户头像
            final api = ref.read(apiClientProvider);
            await api.put('/user/me', data: {'avatar': avatarUrl});

            // 刷新 AuthState 中的用户信息
            await authService.getCurrentUser();
          }
        } catch (e) {
          debugPrint('[Register] Avatar upload failed: $e');
          // 头像上传失败不阻塞注册流程
        }
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
      context.go('/home');
    } else {
      setState(() => _isLoading = false);
      _showError(response.message);
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
