import 'dart:async';
import 'dart:typed_data';
import 'package:universal_io/io.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lottie/lottie.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/premium_theme_tokens.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/utils/qr_payload.dart';
import '../../../core/services/upload_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/avatar_crop_page.dart';
import '../../../shared/widgets/premium_widgets.dart';
import '../../home/pages/home_desktop_page.dart';
import 'personalization_page.dart';
import 'bind_phone_page.dart';

/// 个人资料页面
class ProfilePage extends ConsumerStatefulWidget {
  final bool isDesktopPanel;

  const ProfilePage({super.key, this.isDesktopPanel = false});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  late TextEditingController _nameController;
  late TextEditingController _usernameController;
  late TextEditingController _bioController;
  bool _isLoading = false;

  // 用户名验证状态
  String? _originalUsername;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameMessage;
  Timer? _usernameCheckTimer;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authServiceProvider).user;
    _nameController = TextEditingController(text: user?.nickname ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
    _originalUsername = user?.username ?? '';

    // 监听用户名变化
    _usernameController.addListener(_onUsernameChanged);
  }

  @override
  void dispose() {
    _usernameCheckTimer?.cancel();
    _usernameController.removeListener(_onUsernameChanged);
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  /// 用户名变化时触发验证
  void _onUsernameChanged() {
    final username = _usernameController.text.trim();

    // 取消之前的定时器
    _usernameCheckTimer?.cancel();

    // 如果用户名没变，重置状态
    if (username == _originalUsername) {
      setState(() {
        _isUsernameAvailable = null;
        _usernameMessage = null;
        _isCheckingUsername = false;
      });
      return;
    }

    // 设置正在检查状态
    setState(() {
      _isCheckingUsername = true;
      _isUsernameAvailable = null;
    });

    // 延迟 500ms 后检查（防抖）
    _usernameCheckTimer = Timer(const Duration(milliseconds: 500), () {
      _checkUsernameAvailability(username);
    });
  }

  /// 检查用户名可用性
  Future<void> _checkUsernameAvailability(String username) async {
    if (username.isEmpty) {
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = null;
      });
      return;
    }

    try {
      final api = ref.read(apiClientProvider);
      final response = await api.post(
        '/user/check-username',
        data: {'username': username},
      );

      if (!mounted) return;

      if (response.isSuccess && response.data != null) {
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = response.data['available'] == true;
          _usernameMessage = response.data['message'];
        });
      } else {
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = false;
          _usernameMessage = response.message;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingUsername = false;
        _isUsernameAvailable = null;
      });
    }
  }

  /// 格式化手机号
  String _formatPhone(String? phone, AppLocalizations l10n) {
    if (phone == null || phone.isEmpty) return l10n.noPhoneBound;
    if (phone.length >= 11) {
      return '+86 ${phone.substring(0, 3)}****${phone.substring(phone.length - 4)}';
    }
    return phone;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF000000) : Colors.white;
    final cardColor =
        isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final l10n = AppLocalizations(ref.watch(languageProvider));

    final authState = ref.watch(authServiceProvider);
    final user = authState.user;
    final displayName = user?.nickname ?? user?.username ?? l10n.get('offline');
    final avatar = user?.avatar;
    final phoneDisplay = _formatPhone(user?.phone, l10n);

    // 桌面面板模式：内容 + 顶部"完成"操作栏
    if (widget.isDesktopPanel) {
      return Column(
        children: [
          // 桌面面板顶部操作栏，模拟 AppBar 的 actions
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: TextButton(
                onPressed: _saveProfile,
                child: Text(
                  l10n.done,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _buildBody(
              context,
              isDark,
              cardColor,
              user,
              displayName,
              avatar,
              phoneDisplay,
              l10n,
            ),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: AppColors.primary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l10n.editProfile,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _saveProfile,
            child: Text(
              l10n.done,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w400,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
      body: _buildBody(
        context,
        isDark,
        cardColor,
        user,
        displayName,
        avatar,
        phoneDisplay,
        l10n,
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    bool isDark,
    Color cardColor,
    dynamic user,
    String displayName,
    String? avatar,
    String phoneDisplay,
    AppLocalizations l10n,
  ) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          const SizedBox(height: 20),

          if (user?.premiumType != null &&
              (user!.premiumType as String).isNotEmpty)
            PremiumCard(
              isDark: isDark,
              premiumType: user.premiumType,
              padding: const EdgeInsets.all(18),
              borderRadius: BorderRadius.circular(24),
              colors: PremiumThemeTokens.isYearly(user.premiumType)
                  ? const [
                      Color(0xFF111827),
                      Color(0xFF7C2D12),
                      Color(0xFFF59E0B),
                    ]
                  : user.premiumType == 'quarterly'
                      ? const [
                          Color(0xFF1E1B4B),
                          Color(0xFF4338CA),
                          Color(0xFF06B6D4),
                        ]
                      : const [
                          Color(0xFF0F172A),
                          Color(0xFF312E81),
                          Color(0xFF7C3AED),
                        ],
              child: Row(
                children: [
                  const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Premium Identity',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '你的头像、昵称与聊天消息已启用高级会员视觉效果。',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.82),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // 头像
          Center(
            child: GestureDetector(
              onTap: _changeAvatar,
              child: Column(
                children: [
                  AvatarWidget(
                    name: displayName,
                    avatar: avatar,
                    size: 90,
                    premiumType: user?.premiumType,
                  ),
                  const SizedBox(height: 12),
                  ColoredNameWidget(
                    name: displayName,
                    nicknameColor: user?.nicknameColor,
                    premiumType: user?.premiumType,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    defaultColor: isDark ? Colors.white : Colors.black,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.setNewPhoto,
                    style: TextStyle(fontSize: 16, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // 名字输入框
          _buildInputCard(
            child: TextField(
              controller: _nameController,
              style: TextStyle(
                fontSize: 17,
                color: isDark ? Colors.white : Colors.black,
              ),
              decoration: InputDecoration(
                hintText: l10n.name,
                hintStyle: TextStyle(
                  fontSize: 17,
                  color: isDark ? Colors.white30 : Colors.black26,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            isDark: isDark,
            cardColor: cardColor,
          ),

          const SizedBox(height: 8),

          _buildHintText(l10n.enterYourName, isDark),

          const SizedBox(height: 24),

          // 用户名输入框
          _buildInputCard(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _usernameController,
                    keyboardType: TextInputType.visiblePassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[a-zA-Z0-9_]'),
                      ),
                      LengthLimitingTextInputFormatter(20),
                    ],
                    style: TextStyle(
                      fontSize: 17,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    decoration: InputDecoration(
                      prefixText: '@',
                      prefixStyle: TextStyle(
                        fontSize: 17,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                      hintText: l10n.username,
                      hintStyle: TextStyle(
                        fontSize: 17,
                        color: isDark ? Colors.white30 : Colors.black26,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                // 用户名验证状态图标
                if (_usernameController.text.trim() != _originalUsername) ...[
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _buildUsernameStatusIcon(),
                  ),
                ],
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Clipboard.setData(
                      ClipboardData(text: '@${_usernameController.text}'),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.usernameCopied),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(
                      Icons.copy_rounded,
                      size: 20,
                      color: isDark ? Colors.white38 : Colors.black26,
                    ),
                  ),
                ),
              ],
            ),
            isDark: isDark,
            cardColor: cardColor,
          ),

          const SizedBox(height: 8),

          _buildHintText(l10n.usernameHint, isDark),

          const SizedBox(height: 24),

          // 简介输入框
          _buildInputCard(
            child: TextField(
              controller: _bioController,
              maxLines: 3,
              style: TextStyle(
                fontSize: 17,
                color: isDark ? Colors.white : Colors.black,
              ),
              decoration: InputDecoration(
                hintText: l10n.bio,
                hintStyle: TextStyle(
                  fontSize: 17,
                  color: isDark ? Colors.white30 : Colors.black26,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
            isDark: isDark,
            cardColor: cardColor,
          ),

          const SizedBox(height: 8),

          _buildHintText(l10n.bioHint, isDark),

          const SizedBox(height: 24),

          // 手机号
          _buildInputCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      phoneDisplay,
                      style: TextStyle(
                        fontSize: 17,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _changePhone,
                    child: Text(
                      user?.phone != null && user!.phone!.isNotEmpty
                          ? l10n.change
                          : l10n.bind,
                      style: TextStyle(fontSize: 17, color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            isDark: isDark,
            cardColor: cardColor,
          ),

          const SizedBox(height: 32),

          // 您的颜色
          _buildActionCard(
            children: [
              _ActionItem(
                icon: Icons.palette_outlined,
                iconBg: const Color(0xFFFF2D55),
                title: l10n.yourColor,
                isDark: isDark,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PersonalizationPage(),
                  ),
                ),
              ),
            ],
            isDark: isDark,
            cardColor: cardColor,
          ),

          const SizedBox(height: 16),

          // 二维码和邀请
          _buildActionCard(
            children: [
              _ActionItem(
                icon: Icons.qr_code_2_rounded,
                iconBg: AppColors.primary,
                title: l10n.qrCode,
                isDark: isDark,
                onTap: _showQRCode,
              ),
              _buildDivider(isDark),
              _ActionItem(
                icon: Icons.person_add_alt_rounded,
                iconBg: const Color(0xFF34C759),
                title: l10n.inviteFriends,
                isDark: isDark,
                onTap: _copyInviteLink,
              ),
            ],
            isDark: isDark,
            cardColor: cardColor,
          ),

          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildInputCard({
    required Widget child,
    required bool isDark,
    required Color cardColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }

  Widget _buildActionCard({
    required List<Widget> children,
    required bool isDark,
    required Color cardColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Container(
      margin: const EdgeInsets.only(left: 56),
      height: 0.5,
      color: isDark
          ? Colors.white.withOpacity(0.1)
          : Colors.black.withOpacity(0.1),
    );
  }

  /// 用户名验证状态图标
  Widget _buildUsernameStatusIcon() {
    if (_isCheckingUsername) {
      return SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: AppColors.primary,
        ),
      );
    }

    if (_isUsernameAvailable == true) {
      // 绿色对号动画
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 300),
        curve: Curves.elasticOut,
        builder: (context, value, child) {
          return Transform.scale(
            scale: value,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 14),
            ),
          );
        },
      );
    }

    if (_isUsernameAvailable == false) {
      // 红色叉号
      return Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: AppColors.error,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 14),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _buildHintText(String text, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.35,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
      ),
    );
  }

  void _changeAvatar() {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              const SizedBox(height: 16),
              _SheetItem(
                title: '拍照',
                icon: Icons.camera_alt_rounded,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatarFromCamera();
                },
              ),
              _SheetItem(
                title: '相册',
                icon: Icons.photo_rounded,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatarFromGallery();
                },
              ),
              _SheetItem(
                title: '删除照片',
                icon: Icons.delete_rounded,
                isDark: isDark,
                isDestructive: true,
                onTap: () {
                  Navigator.pop(context);
                  _deleteAvatar();
                },
              ),
              Container(
                height: 8,
                color: isDark ? Colors.black26 : const Color(0xFFF2F2F7),
              ),
              _SheetItem(
                title: '取消',
                isDark: isDark,
                onTap: () => Navigator.pop(context),
                isBold: true,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAvatarFromCamera() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1200,
      maxHeight: 1200,
    );

    if (image != null) {
      await _cropAndUploadAvatar(image);
    }
  }

  Future<void> _pickAvatarFromGallery() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 1200,
      maxHeight: 1200,
    );

    if (image != null) {
      await _cropAndUploadAvatar(image);
    }
  }

  Future<void> _cropAndUploadAvatar(XFile image) async {
    final imageBytes = await image.readAsBytes();
    final croppedPath = await showAvatarCropDialog(
      context: context,
      imagePath: kIsWeb ? null : image.path,
      imageBytes: imageBytes,
      title: '裁剪头像',
    );

    if (croppedPath != null) {
      if (kIsWeb &&
          croppedPath == 'web_cropped' &&
          lastCroppedImageBytes != null) {
        await _uploadAvatarBytes(lastCroppedImageBytes!);
        lastCroppedImageBytes = null;
      } else {
        await _uploadAvatar(XFile(croppedPath));
      }
    }
  }

  Future<void> _uploadAvatarBytes(Uint8List bytes) async {
    setState(() => _isLoading = true);
    final oldAvatarUrl = ref.read(authServiceProvider).user?.avatar;
    try {
      final uploadService = ref.read(uploadServiceProvider);
      final xfile = XFile.fromData(
        bytes,
        name: 'avatar.jpg',
        mimeType: 'image/jpeg',
      );
      final avatarUrl = await uploadService.uploadAvatar(xfile);
      if (avatarUrl != null) {
        if (oldAvatarUrl != null && oldAvatarUrl.isNotEmpty) {
          try {
            await AvatarCacheManager.removeFile(oldAvatarUrl);
          } catch (_) {}
        }
        final response = await ref
            .read(authServiceProvider.notifier)
            .updateProfile(avatar: avatarUrl);
        if (response != null && mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('头像更新成功')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('上传失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _uploadAvatar(XFile image) async {
    setState(() => _isLoading = true);

    // 获取旧头像URL，用于后续清除缓存
    final oldAvatarUrl = ref.read(authServiceProvider).user?.avatar;

    try {
      final uploadService = ref.read(uploadServiceProvider);
      final avatarUrl = await uploadService.uploadAvatar(image);

      if (avatarUrl != null) {
        // 只清除当前用户旧头像缓存，不清空所有人缓存
        if (oldAvatarUrl != null && oldAvatarUrl.isNotEmpty) {
          try {
            await AvatarCacheManager.removeFile(oldAvatarUrl);
          } catch (_) {}
        }

        // 更新用户头像（auth 内会 remove 旧 + prefetch 新，保证实时刷新）
        final response = await ref
            .read(authServiceProvider.notifier)
            .updateProfile(avatar: avatarUrl);

        if (mounted && !response.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? '更新头像失败'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        } else if (response.isSuccess) {
          // 新头像用完整 URL 预取，设置页/个人资料等立即从缓存读
          final fullUrl = ApiConfig.getMediaUrl(avatarUrl) ?? avatarUrl;
          AvatarCacheManager.prefetch(fullUrl);
        }
        // 成功时不显示提醒，UI 会自动更新显示新头像
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('上传头像失败'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('上传失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _deleteAvatar() async {
    setState(() => _isLoading = true);

    try {
      final response = await ref
          .read(authServiceProvider.notifier)
          .updateProfile(avatar: '');

      if (mounted) {
        if (response.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('头像已删除'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (_isLoading) return;

    final newUsername = _usernameController.text.trim();
    final usernameChanged =
        newUsername != _originalUsername && newUsername.isNotEmpty;

    // 如果用户名改变且不可用，阻止保存
    if (usernameChanged && _isUsernameAvailable != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_usernameMessage ?? '请先验证用户名'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.error,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    // 如果用户名改变，显示确认对话框
    if (usernameChanged) {
      final confirmed = await _showUsernameChangeConfirm();
      if (!confirmed) return;
    }

    HapticFeedback.mediumImpact();

    setState(() => _isLoading = true);

    try {
      final response =
          await ref.read(authServiceProvider.notifier).updateProfile(
                nickname: _nameController.text.trim(),
                username: newUsername,
                bio: _bioController.text.trim(),
              );

      if (mounted) {
        if (response.isSuccess) {
          // 从服务器拉取最新用户信息，保证设置页和个人资料页实时显示昵称、颜色、头像等
          await ref.read(authServiceProvider.notifier).getCurrentUser();
          if (!mounted) return;
          // 更新原始用户名
          _originalUsername = newUsername;
          if (mounted) {
            setState(() {
              _isLoading = false;
              _isUsernameAvailable = null;
              _usernameMessage = null;
            });
          }

          // 桌面面板模式：关闭面板；移动端/Web push 模式：pop 返回
          if (widget.isDesktopPanel) {
            // 使用 addPostFrameCallback 确保当前帧渲染完成后再关闭面板，避免 rebuild 冲突
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.read(desktopProfileProvider.notifier).state =
                  DesktopProfileInfo.none;
            });
          } else {
            Navigator.of(context, rootNavigator: true).pop();
          }
          return; // 成功路径提前返回，finally 不再重置 _isLoading
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.message ?? '更新失败'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('更新失败: $e'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppColors.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      // 失败/异常路径重置加载状态；成功路径已在上方重置并 return
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 显示用户名修改确认对话框
  Future<bool> _showUsernameChangeConfirm() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final result = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '确认修改',
      barrierColor: Colors.black.withOpacity(0.5),
      transitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: ScaleTransition(
            scale: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.85,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.12)
                        : Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withOpacity(0.2)
                          : Colors.black.withOpacity(0.05),
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 警告图标
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppColors.warning.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.warning_amber_rounded,
                            color: AppColors.warning,
                            size: 30,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '确认修改用户名？',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '修改用户名后，您的登录账号也会随之改变。\n\n新用户名: @${_usernameController.text.trim()}',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  backgroundColor: isDark
                                      ? Colors.white.withOpacity(0.1)
                                      : Colors.black.withOpacity(0.05),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  '取消',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  backgroundColor: AppColors.primary,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  '确认修改',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    return result ?? false;
  }

  void _changePhone() {
    HapticFeedback.selectionClick();
    final user = ref.read(authServiceProvider).user;
    if (user?.phone != null && user!.phone!.isNotEmpty) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('更换手机号'),
          content: const Text('已绑定手机号的更换流程需联系管理员处理。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute<bool>(builder: (_) => const BindPhonePage()))
        .then((ok) {
      if (ok == true && mounted) setState(() {});
    });
  }

  void _showQRCode() {
    HapticFeedback.selectionClick();
    Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        barrierDismissible: true,
        pageBuilder: (context, animation, _) =>
            _QRCodePage(animation: animation),
        transitionsBuilder: (context, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  Future<void> _copyInviteLink() async {
    HapticFeedback.mediumImpact();
    final user = ref.read(authServiceProvider).user;
    final username = user?.username ?? 'user';
    final l10n = AppLocalizations(ref.read(languageProvider));
    SystemSettings? settings = ref.read(systemSettingsProvider).valueOrNull;

    try {
      settings ??= await ref.read(systemSettingsProvider.future);
    } catch (_) {
      settings = await ref
          .read(systemSettingsServiceProvider)
          .getSettings(forceRefresh: false);
    }

    if (!mounted) return;
    final inviteLink = (settings ?? SystemSettings()).buildInviteLink(username);
    if (inviteLink.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('请先在后台配置邀请注册链接域名'),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    await Clipboard.setData(
      ClipboardData(text: inviteLink),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.linkCopied),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final String title;
  final bool isDark;
  final VoidCallback onTap;

  const _ActionItem({
    required this.icon,
    required this.iconBg,
    required this.title,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: Colors.white, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: isDark ? Colors.white24 : Colors.black26,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetItem extends StatelessWidget {
  final String title;
  final IconData? icon;
  final bool isDark;
  final bool isDestructive;
  final bool isBold;
  final VoidCallback onTap;

  const _SheetItem({
    required this.title,
    this.icon,
    required this.isDark,
    this.isDestructive = false,
    this.isBold = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive
        ? AppColors.error
        : (isDark ? Colors.white : Colors.black);
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 24, color: color),
              const SizedBox(width: 16),
            ],
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: isBold ? FontWeight.w600 : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QRCodePage extends ConsumerStatefulWidget {
  final Animation<double> animation;

  const _QRCodePage({required this.animation});

  @override
  ConsumerState<_QRCodePage> createState() => _QRCodePageState();
}

class _QRCodePageState extends ConsumerState<_QRCodePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authServiceProvider);
    final user = authState.user;
    final displayName = user?.nickname ?? user?.username ?? '未登录';
    final username = user?.username ?? '';
    final qrPayload = user?.uuid != null && user!.uuid.isNotEmpty
        ? buildUserQrPayload(user.uuid)
        : '';
    final avatar = user?.avatar;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primary,
              AppColors.primary.withOpacity(0.8),
              const Color(0xFF1A73E8),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部栏
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 48),
                    const Text(
                      '我的二维码',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 36,
                        height: 36,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              // 二维码卡片
              ScaleTransition(
                scale: CurvedAnimation(
                  parent: widget.animation,
                  curve: Curves.easeOutBack,
                ),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 40,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 32),
                      // 头像
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary,
                              const Color(0xFF1A73E8),
                            ],
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: AvatarWidget(
                            name: displayName,
                            avatar: avatar,
                            size: 72,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 名字
                      Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 用户名
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Clipboard.setData(ClipboardData(text: '@$username'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('用户名已复制'),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '@$username',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // 真实二维码
                      SizedBox(
                        width: 240,
                        height: 240,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 动态光点边框（不旋转边框本身）
                            AnimatedBuilder(
                              animation: _rotationController,
                              builder: (context, child) {
                                return CustomPaint(
                                  painter: _AnimatedQRBorderPainter(
                                    progress: _rotationController.value,
                                    primaryColor: AppColors.primary,
                                  ),
                                  size: const Size(240, 240),
                                );
                              },
                            ),
                            // 二维码内容
                            Container(
                              width: 200,
                              height: 200,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: qrPayload.isEmpty
                                  ? const Center(
                                      child: Icon(
                                        Icons.qr_code_2_rounded,
                                        size: 96,
                                        color: Colors.black26,
                                      ),
                                    )
                                  : QrImageView(
                                      data: qrPayload,
                                      version: QrVersions.auto,
                                      eyeStyle: QrEyeStyle(
                                        eyeShape: QrEyeShape.square,
                                        color: AppColors.primary,
                                      ),
                                      dataModuleStyle: QrDataModuleStyle(
                                        dataModuleShape:
                                            QrDataModuleShape.square,
                                        color: AppColors.primary,
                                      ),
                                      backgroundColor: Colors.white,
                                      padding: const EdgeInsets.all(10),
                                    ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // 提示文字
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.qr_code_scanner_rounded,
                            size: 16,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '扫描二维码添加好友',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
              const Spacer(flex: 2),
              // 底部按钮
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Expanded(
                      child: _QRActionButton(
                        icon: Icons.share_rounded,
                        label: '分享',
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          Navigator.pop(context);
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _QRActionButton(
                        icon: Icons.download_rounded,
                        label: '保存图片',
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          Navigator.pop(context);
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _QRActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QRActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModernQRPainter extends CustomPainter {
  final Color primaryColor;

  _ModernQRPainter({required this.primaryColor});

  @override
  void paint(Canvas canvas, Size size) {
    const int qrSize = 25; // 25x25 模块
    final m = size.width / qrSize; // 每个模块的大小

    // 主色渐变
    final gradientPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [primaryColor, const Color(0xFF1A73E8)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    // 绘制圆角方块
    void drawModule(int x, int y) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x * m + m * 0.05, y * m + m * 0.05, m * 0.9, m * 0.9),
        Radius.circular(m * 0.25),
      );
      canvas.drawRRect(rect, gradientPaint);
    }

    // 绘制定位图案（圆角风格）
    void drawPositionPattern(int px, int py) {
      // 外框 7x7
      final outerRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(px * m, py * m, 7 * m, 7 * m),
        Radius.circular(m * 1.2),
      );
      canvas.drawRRect(outerRect, gradientPaint);

      // 白色内框 5x5
      final innerWhite = RRect.fromRectAndRadius(
        Rect.fromLTWH((px + 1) * m, (py + 1) * m, 5 * m, 5 * m),
        Radius.circular(m * 0.8),
      );
      canvas.drawRRect(innerWhite, Paint()..color = Colors.white);

      // 内部实心 3x3
      final innerRect = RRect.fromRectAndRadius(
        Rect.fromLTWH((px + 2) * m, (py + 2) * m, 3 * m, 3 * m),
        Radius.circular(m * 0.6),
      );
      canvas.drawRRect(innerRect, gradientPaint);
    }

    // 三个定位图案
    drawPositionPattern(0, 0); // 左上
    drawPositionPattern(qrSize - 7, 0); // 右上
    drawPositionPattern(0, qrSize - 7); // 左下

    // 时序图案（第6行和第6列的交替黑白）
    for (int i = 8; i < qrSize - 8; i++) {
      if (i % 2 == 0) {
        drawModule(6, i);
        drawModule(i, 6);
      }
    }

    // 对齐图案（右下角小定位点）
    final alignX = qrSize - 9;
    final alignY = qrSize - 9;
    final alignOuter = RRect.fromRectAndRadius(
      Rect.fromLTWH(alignX * m, alignY * m, 5 * m, 5 * m),
      Radius.circular(m * 0.8),
    );
    canvas.drawRRect(alignOuter, gradientPaint);
    final alignInner = RRect.fromRectAndRadius(
      Rect.fromLTWH((alignX + 1) * m, (alignY + 1) * m, 3 * m, 3 * m),
      Radius.circular(m * 0.5),
    );
    canvas.drawRRect(alignInner, Paint()..color = Colors.white);
    final alignCenter = RRect.fromRectAndRadius(
      Rect.fromLTWH((alignX + 2) * m, (alignY + 2) * m, 1 * m, 1 * m),
      Radius.circular(m * 0.3),
    );
    canvas.drawRRect(alignCenter, gradientPaint);

    // 模拟数据区域 - 完整填充
    final data = [
      // 行 0-6 已被左上和右上定位图案占用
      // 行 7: 时序和数据
      [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        1,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ],
      // 行 8-16: 数据区域
      [
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ],
      [
        0,
        1,
        0,
        1,
        1,
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        1,
        0,
        0,
        1,
        1,
        1,
        0,
        1,
        1,
        0,
        1,
      ],
      [
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
        1,
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        0,
        1,
        1,
        0,
      ],
      [
        0,
        1,
        1,
        0,
        0,
        1,
        0,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        1,
        0,
        0,
        1,
      ],
      [
        1,
        0,
        0,
        1,
        1,
        0,
        1,
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        0,
        1,
        1,
        0,
      ],
      [
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        0,
        1,
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        0,
        1,
      ],
      [
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
      ],
      [
        0,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        1,
      ],
      [
        1,
        1,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        0,
        1,
        1,
        0,
        0,
        1,
        0,
        1,
        0,
        0,
      ],
      // 行 17: 数据
      [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ],
      // 行 18-24: 左下定位图案占用部分 + 数据
      [
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ],
      [
        0,
        1,
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        1,
        0,
        1,
      ],
      [
        1,
        0,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
      ],
      [
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        1,
      ],
      [
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        0,
      ],
      [
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        0,
        1,
        0,
        0,
        1,
      ],
    ];

    // 绘制数据区域
    for (int row = 0; row < data.length; row++) {
      final y = row + 7; // 从第7行开始
      if (y >= qrSize) continue;

      for (int col = 0; col < data[row].length; col++) {
        if (col >= qrSize) continue;

        // 跳过定位图案区域
        if (col < 8 && y < 8) continue; // 左上
        if (col >= qrSize - 8 && y < 8) continue; // 右上
        if (col < 8 && y >= qrSize - 8) continue; // 左下
        // 跳过对齐图案
        if (col >= alignX && col < alignX + 5 && y >= alignY && y < alignY + 5)
          continue;
        // 跳过时序线
        if (col == 6 || y == 6) continue;

        if (data[row][col] == 1) {
          drawModule(col, y);
        }
      }
    }

    // 补充顶部和左侧数据
    final topData = [
      [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        1,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ],
      [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ],
      [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        1,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ],
      [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        0,
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ],
      [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
        1,
        0,
        1,
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ],
      [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        1,
        1,
        0,
        0,
        1,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ],
    ];

    for (int row = 0; row < topData.length; row++) {
      for (int col = 8; col < qrSize - 8; col++) {
        if (topData[row][col] == 1) {
          drawModule(col, row);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 动态二维码边框
class _AnimatedQRBorderPainter extends CustomPainter {
  final double progress;
  final Color primaryColor;

  _AnimatedQRBorderPainter({
    required this.progress,
    required this.primaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rectSize = size.width - 8;
    final cornerRadius = 20.0;

    // 静态边框（淡色）
    final borderPaint = Paint()
      ..color = primaryColor.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: center, width: rectSize, height: rectSize),
      Radius.circular(cornerRadius),
    );
    canvas.drawRRect(rrect, borderPaint);

    // 计算光点在矩形边框上的位置
    final perimeter =
        4 * (rectSize - 2 * cornerRadius) + 2 * math.pi * cornerRadius;
    final currentPos = progress * perimeter;
    final glowPos = _getPointOnRoundedRect(
      center: center,
      size: rectSize,
      radius: cornerRadius,
      distance: currentPos,
      perimeter: perimeter,
    );

    // 发光拖尾效果
    for (int i = 0; i < 8; i++) {
      final tailProgress = (progress - i * 0.015).clamp(0.0, 1.0);
      final tailPos = tailProgress * perimeter;
      final tailPoint = _getPointOnRoundedRect(
        center: center,
        size: rectSize,
        radius: cornerRadius,
        distance: tailPos,
        perimeter: perimeter,
      );

      final tailPaint = Paint()
        ..color = primaryColor.withOpacity((1 - i / 8) * 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + i * 1.0);
      canvas.drawCircle(tailPoint, 4 - i * 0.3, tailPaint);
    }

    // 主发光点
    final glowPaint = Paint()
      ..color = primaryColor
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(glowPos, 8, glowPaint);

    // 核心亮点
    final corePaint = Paint()..color = Colors.white;
    canvas.drawCircle(glowPos, 4, corePaint);
  }

  /// 计算圆角矩形边框上的点
  Offset _getPointOnRoundedRect({
    required Offset center,
    required double size,
    required double radius,
    required double distance,
    required double perimeter,
  }) {
    final half = size / 2;
    final straight = size - 2 * radius;
    final cornerArc = math.pi / 2 * radius;

    double d = distance % perimeter;

    // 上边（从左上角圆弧结束到右上角圆弧开始）
    if (d < straight) {
      return Offset(center.dx - half + radius + d, center.dy - half);
    }
    d -= straight;

    // 右上角圆弧
    if (d < cornerArc) {
      final angle = -math.pi / 2 + d / radius;
      return Offset(
        center.dx + half - radius + radius * math.cos(angle),
        center.dy - half + radius + radius * math.sin(angle),
      );
    }
    d -= cornerArc;

    // 右边
    if (d < straight) {
      return Offset(center.dx + half, center.dy - half + radius + d);
    }
    d -= straight;

    // 右下角圆弧
    if (d < cornerArc) {
      final angle = d / radius;
      return Offset(
        center.dx + half - radius + radius * math.cos(angle),
        center.dy + half - radius + radius * math.sin(angle),
      );
    }
    d -= cornerArc;

    // 下边
    if (d < straight) {
      return Offset(center.dx + half - radius - d, center.dy + half);
    }
    d -= straight;

    // 左下角圆弧
    if (d < cornerArc) {
      final angle = math.pi / 2 + d / radius;
      return Offset(
        center.dx - half + radius + radius * math.cos(angle),
        center.dy + half - radius + radius * math.sin(angle),
      );
    }
    d -= cornerArc;

    // 左边
    if (d < straight) {
      return Offset(center.dx - half, center.dy + half - radius - d);
    }
    d -= straight;

    // 左上角圆弧
    final angle = math.pi + d / radius;
    return Offset(
      center.dx - half + radius + radius * math.cos(angle),
      center.dy - half + radius + radius * math.sin(angle),
    );
  }

  @override
  bool shouldRepaint(covariant _AnimatedQRBorderPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
