// 文件用途：实现 ProfilePage 页面及其交互流程，属于应用设置。
// 核心逻辑：维护 ProfilePage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'dart:async';
import 'dart:typed_data';
import 'package:universal_io/io.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lottie/lottie.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/system_settings_service.dart';
import '../../../core/utils/qr_payload.dart';
import '../../../core/services/upload_service.dart';
import '../../../shared/widgets/avatar_widget.dart';
import '../../../shared/widgets/colored_name_widget.dart';
import '../../../shared/widgets/avatar_crop_page.dart';
import '../../home/pages/home_desktop_page.dart';
import 'personalization_page.dart';
import 'bind_phone_page.dart';
import '../../../shared/widgets/themed_app_bar.dart';

String _profileText(
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

String _profileServerMessage(
  String? raw, {
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

// 关键声明：profile page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
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
  String _selectedGender = '';
  bool _isLoading = false;
  bool _isAvatarOperationInProgress = false;
  bool _saveAfterAvatarOperation = false;

  // 用户名验证状态
  String? _originalUsername;
  bool _isCheckingUsername = false;
  bool? _isUsernameAvailable;
  String? _usernameMessage;
  Timer? _usernameCheckTimer;

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
  @override
  void initState() {
    super.initState();
    final user = ref.read(authServiceProvider).user;
    _nameController = TextEditingController(text: user?.nickname ?? '');
    _usernameController = TextEditingController(text: user?.username ?? '');
    _bioController = TextEditingController(text: user?.bio ?? '');
    _selectedGender =
        user?.gender == 'male' || user?.gender == 'female' ? user!.gender! : '';
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
          _usernameMessage = localizeServerMessage(
            response.data['message']?.toString(),
            fallbackZhCN: '用户名状态获取失败',
            fallbackZhTW: '取得使用者名稱狀態失敗',
            fallbackEn: 'Failed to check username status.',
          );
        });
      } else {
        setState(() {
          _isCheckingUsername = false;
          _isUsernameAvailable = false;
          _usernameMessage = _profileServerMessage(
            response.message,
            zhCN: '用户名状态获取失败',
            zhTW: '取得使用者名稱狀態失敗',
            en: 'Failed to check username status.',
          );
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

    final user = ref.watch(authServiceProvider.select((s) => s.user));
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
                    color: AppColors.linkFor(context),
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
      appBar: ThemedAppBar(
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: AppColors.linkFor(context),
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
                color: AppColors.linkFor(context),
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

          // 头像 + 昵称 + 邀请码（只点头像才弹拍照 sheet；邀请码独立可点击复制）
          Center(
            child: Column(
              children: [
                GestureDetector(
                  onTap: _changeAvatar,
                  child: AvatarWidget(
                    name: displayName,
                    avatar: avatar,
                    size: 90,
                    isCircle: true,
                  ),
                ),
                const SizedBox(height: 12),
                ColoredNameWidget(
                  name: displayName,
                  nicknameColor: user?.nicknameColor,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  defaultColor: AppColors.textPrimaryFor(context),
                ),
                const SizedBox(height: 8),
                _buildInviteCodeRow(context, user),
              ],
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
                  color: AppColors.inputHintFor(context),
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
                        color: AppColors.inputHintFor(context),
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
                      color: AppColors.textTertiaryFor(context),
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

          _buildInputCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      _profileText(
                        context,
                        zhCN: '性别',
                        zhTW: '性別',
                        en: 'Gender',
                      ),
                      style: TextStyle(
                        fontSize: 17,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                          value: 'male',
                          label: Text(_profileText(
                            context,
                            zhCN: '男生',
                            zhTW: '男生',
                            en: 'Male',
                          )),
                        ),
                        ButtonSegment(
                          value: 'female',
                          label: Text(_profileText(
                            context,
                            zhCN: '女生',
                            zhTW: '女生',
                            en: 'Female',
                          )),
                        ),
                      ],
                      selected: _selectedGender.isEmpty
                          ? <String>{}
                          : {_selectedGender},
                      emptySelectionAllowed: true,
                      showSelectedIcon: false,
                      onSelectionChanged: (values) {
                        setState(() {
                          _selectedGender = values.isEmpty ? '' : values.first;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            isDark: isDark,
            cardColor: cardColor,
          ),

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
                  color: AppColors.inputHintFor(context),
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

          // _buildHintText(l10n.bioHint, isDark),

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
                      style: TextStyle(
                        fontSize: 17,
                        color: AppColors.linkFor(context),
                      ),
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
                iconBg: AppColors.primaryFor(context),
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
          color: AppColors.linkFor(context),
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
          color: AppColors.textTertiaryFor(context),
        ),
      ),
    );
  }

  /// 渲染头像下方的邀请码行：用户点击即复制自己的 10 位个人邀请码到剪贴板。
  /// 旧账号 / 后端尚未下发 invite_code 时显示占位文案且不可点击。
  Widget _buildInviteCodeRow(BuildContext context, dynamic user) {
    final inviteCode = user?.inviteCode is String
        ? (user.inviteCode as String).trim()
        : '';
    final hasCode = inviteCode.isNotEmpty;
    final label = hasCode
        ? inviteCode
        : _profileText(
            context,
            zhCN: '暂未生成',
            zhTW: '暫未生成',
            en: 'Not generated',
          );

    void onTap() {
      if (!hasCode) return;
      HapticFeedback.lightImpact();
      Clipboard.setData(ClipboardData(text: inviteCode));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _profileText(
              context,
              zhCN: '邀请码已复制',
              zhTW: '邀請碼已複製',
              en: 'Invite code copied',
            ),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: hasCode ? onTap : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: hasCode
                  ? AppColors.linkFor(context)
                  : AppColors.textTertiaryFor(context),
              letterSpacing: hasCode ? 1.2 : 0,
            ),
          ),
          if (hasCode) ...[
            const SizedBox(width: 6),
            Icon(
              Icons.copy_rounded,
              size: 14,
              color: AppColors.linkFor(context),
            ),
          ],
        ],
      ),
    );
  }

  void _changeAvatar() {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
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
                  color: AppColors.dividerFor(context),
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              const SizedBox(height: 16),
              _SheetItem(
                title: _profileText(
                  context,
                  zhCN: '拍照',
                  zhTW: '拍照',
                  en: 'Take Photo',
                ),
                icon: Icons.camera_alt_rounded,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatarFromCamera();
                },
              ),
              _SheetItem(
                title: _profileText(
                  context,
                  zhCN: '相册',
                  zhTW: '相簿',
                  en: 'Photo Library',
                ),
                icon: Icons.photo_rounded,
                isDark: isDark,
                onTap: () {
                  Navigator.pop(context);
                  _pickAvatarFromGallery();
                },
              ),
              _SheetItem(
                title: _profileText(
                  context,
                  zhCN: '删除照片',
                  zhTW: '刪除照片',
                  en: 'Delete Photo',
                ),
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
                title: _profileText(
                  context,
                  zhCN: '取消',
                  zhTW: '取消',
                  en: 'Cancel',
                ),
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
      title: _profileText(
        context,
        zhCN: '裁剪头像',
        zhTW: '裁剪頭像',
        en: 'Crop Avatar',
      ),
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
    setState(() {
      _isLoading = true;
      _isAvatarOperationInProgress = true;
    });
    final oldAvatarUrl = ref.read(authServiceProvider).user?.avatar;
    var updated = false;
    try {
      final uploadService = ref.read(uploadServiceProvider);
      final xfile = XFile.fromData(
        bytes,
        name: 'avatar.png',
        mimeType: 'image/png',
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
        updated = response.isSuccess;
        if (response.isSuccess && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _profileText(
                  context,
                  zhCN: '头像更新成功',
                  zhTW: '頭像更新成功',
                  en: 'Avatar updated successfully',
                ),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _profileText(
                context,
                zhCN: '上传失败，请重试',
                zhTW: '上傳失敗，請重試',
                en: 'Upload failed. Please try again.',
              ),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isAvatarOperationInProgress = false;
        });
      }
      await _continuePendingSaveAfterAvatarOperation(updated);
    }
  }

  Future<void> _uploadAvatar(XFile image) async {
    setState(() {
      _isLoading = true;
      _isAvatarOperationInProgress = true;
    });
    var updated = false;

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
              content: Text(
                _profileServerMessage(
                  response.message,
                  zhCN: '更新头像失败',
                  zhTW: '更新頭像失敗',
                  en: 'Failed to update avatar',
                ),
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        } else if (response.isSuccess) {
          updated = true;
          // 新头像用完整 URL 预取，设置页/个人资料等立即从缓存读
          final fullUrl = ApiConfig.getMediaUrl(avatarUrl) ?? avatarUrl;
          AvatarCacheManager.prefetch(fullUrl);
        }
        // 成功时不显示提醒，UI 会自动更新显示新头像
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _profileText(
                  context,
                  zhCN: '上传头像失败',
                  zhTW: '上傳頭像失敗',
                  en: 'Avatar upload failed',
                ),
              ),
              behavior: SnackBarBehavior.floating,
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
            content: Text(
              _profileText(
                context,
                zhCN: '上传失败，请重试',
                zhTW: '上傳失敗，請重試',
                en: 'Upload failed. Please try again.',
              ),
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isAvatarOperationInProgress = false;
        });
      }
      await _continuePendingSaveAfterAvatarOperation(updated);
    }
  }

  Future<void> _deleteAvatar() async {
    setState(() {
      _isLoading = true;
      _isAvatarOperationInProgress = true;
    });
    var updated = false;

    try {
      final response = await ref
          .read(authServiceProvider.notifier)
          .updateProfile(avatar: '');
      updated = response.isSuccess;

      if (mounted) {
        if (response.isSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _profileText(
                  context,
                  zhCN: '头像已删除',
                  zhTW: '頭像已刪除',
                  en: 'Avatar removed',
                ),
              ),
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
        setState(() {
          _isLoading = false;
          _isAvatarOperationInProgress = false;
        });
      }
      await _continuePendingSaveAfterAvatarOperation(updated);
    }
  }

  Future<void> _continuePendingSaveAfterAvatarOperation(bool updated) async {
    if (!_saveAfterAvatarOperation) return;
    _saveAfterAvatarOperation = false;
    if (!updated || !mounted) return;
    await _saveProfile();
  }

  void _closeProfilePage() {
    if (!mounted) return;
    final routeSettings = ModalRoute.of(context)?.settings;
    if (routeSettings is Page && context.canPop()) {
      context.pop();
      return;
    }
    Navigator.of(context).maybePop();
  }

  Future<void> _saveProfile() async {
    if (_isAvatarOperationInProgress) {
      _saveAfterAvatarOperation = true;
      return;
    }
    if (_isLoading) return;

    final newUsername = _usernameController.text.trim();
    final usernameChanged =
        newUsername != _originalUsername && newUsername.isNotEmpty;

    if (_selectedGender != 'male' && _selectedGender != 'female') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _profileText(
              context,
              zhCN: '请选择性别',
              zhTW: '請選擇性別',
              en: 'Please select a gender',
            ),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      return;
    }

    // 如果用户名改变且不可用，阻止保存
    if (usernameChanged && _isUsernameAvailable != true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _usernameMessage ??
                _profileText(
                  context,
                  zhCN: '请先验证用户名',
                  zhTW: '請先驗證使用者名稱',
                  en: 'Please verify the username first',
                ),
          ),
          behavior: SnackBarBehavior.floating,
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
                gender: _selectedGender,
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
            _closeProfilePage();
          }
          return; // 成功路径提前返回，finally 不再重置 _isLoading
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _profileServerMessage(
                  response.message,
                  zhCN: '更新失败',
                  zhTW: '更新失敗',
                  en: 'Update failed',
                ),
              ),
              behavior: SnackBarBehavior.floating,
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
            content: Text(
              _profileText(
                context,
                zhCN: '更新失败，请重试',
                zhTW: '更新失敗，請重試',
                en: 'Update failed. Please try again.',
              ),
            ),
            behavior: SnackBarBehavior.floating,
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
      barrierLabel: _profileText(
        context,
        zhCN: '确认修改',
        zhTW: '確認修改',
        en: 'Confirm change',
      ),
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
                          _profileText(
                            context,
                            zhCN: '确认修改用户名？',
                            zhTW: '確認修改使用者名稱？',
                            en: 'Confirm username change?',
                          ),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${_profileText(
                            context,
                            zhCN: '修改用户名后，您的登录账号也会随之改变。',
                            zhTW: '修改使用者名稱後，您的登入帳號也會隨之改變。',
                            en: 'After changing your username, your login account will change as well.',
                          )}\n\n${_profileText(
                            context,
                            zhCN: '新用户名',
                            zhTW: '新使用者名稱',
                            en: 'New username',
                          )}: @${_usernameController.text.trim()}',
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
                                  _profileText(
                                    context,
                                    zhCN: '取消',
                                    zhTW: '取消',
                                    en: 'Cancel',
                                  ),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textSecondaryFor(context),
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
                                  backgroundColor:
                                      AppColors.primaryFor(context),
                                  foregroundColor:
                                      AppColors.onPrimaryFor(context),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: Text(
                                  _profileText(
                                    context,
                                    zhCN: '确认修改',
                                    zhTW: '確認修改',
                                    en: 'Confirm',
                                  ),
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
          title: Text(
            _profileText(
              context,
              zhCN: '更换手机号',
              zhTW: '更換手機號',
              en: 'Change Phone Number',
            ),
          ),
          content: Text(
            _profileText(
              context,
              zhCN: '已绑定手机号的更换流程需联系管理员处理。',
              zhTW: '已綁定手機號的更換流程需聯繫管理員處理。',
              en: 'Changing a linked phone number currently requires administrator assistance.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                _profileText(
                  context,
                  zhCN: '知道了',
                  zhTW: '知道了',
                  en: 'OK',
                ),
              ),
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
        opaque: true,
        pageBuilder: (context, animation, _) =>
            ProfileQRCodePage(animation: animation),
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
          content: Text(
            _profileText(
              context,
              zhCN: '请先在后台配置邀请注册链接域名',
              zhTW: '請先在後台配置邀請註冊連結網域',
              en: 'Configure the invite registration domain in the admin panel first',
            ),
          ),
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
              color: AppColors.textTertiaryFor(context),
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

class ProfileQRCodePage extends ConsumerStatefulWidget {
  final Animation<double>? animation;
  final String? userUuid;
  final String? displayName;
  final String? username;
  final String? avatar;
  final bool? isSelfEntry;

  const ProfileQRCodePage({
    super.key,
    this.animation,
    this.userUuid,
    this.displayName,
    this.username,
    this.avatar,
    this.isSelfEntry,
  });

  @override
  ConsumerState<ProfileQRCodePage> createState() => _QRCodePageState();
}

class _QrCardStyle {
  final String label;
  final String emoji;
  final Color primary;
  final Color secondary;
  final Color backgroundStart;
  final Color backgroundEnd;

  const _QrCardStyle({
    required this.label,
    required this.emoji,
    required this.primary,
    required this.secondary,
    required this.backgroundStart,
    required this.backgroundEnd,
  });
}

const List<_QrCardStyle> _qrCardStyles = [
  _QrCardStyle(
    label: 'Classic',
    emoji: '🏠',
    primary: Color(0xFF69B45B),
    secondary: Color(0xFF2E9678),
    backgroundStart: Color(0xFFE9F5B8),
    backgroundEnd: Color(0xFF96D3A6),
  ),
  _QrCardStyle(
    label: 'Fresh',
    emoji: '🐤',
    primary: Color(0xFF75B95D),
    secondary: Color(0xFF3A9D7D),
    backgroundStart: Color(0xFFE4F7C9),
    backgroundEnd: Color(0xFFAAD9B6),
  ),
  _QrCardStyle(
    label: 'Ice',
    emoji: '⛄',
    primary: Color(0xFF64A7E8),
    secondary: Color(0xFF7B84E8),
    backgroundStart: Color(0xFFE2F4FF),
    backgroundEnd: Color(0xFFC2D5FF),
  ),
  _QrCardStyle(
    label: 'Gem',
    emoji: '💎',
    primary: Color(0xFFC48BE8),
    secondary: Color(0xFF8FA7F8),
    backgroundStart: Color(0xFFF2DDF8),
    backgroundEnd: Color(0xFFD4E9FF),
  ),
  _QrCardStyle(
    label: 'Ocean',
    emoji: '🌊',
    primary: Color(0xFF4AA8C8),
    secondary: Color(0xFF3D8CE1),
    backgroundStart: Color(0xFFDDF6F8),
    backgroundEnd: Color(0xFFAED8F2),
  ),
];

class _QRCodePageState extends ConsumerState<ProfileQRCodePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
  final GlobalKey _qrCardKey = GlobalKey();
  int _selectedStyleIndex = 0;
  bool _isSharing = false;

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

  String _shortUserId(String value) {
    final text = value.trim();
    if (text.length <= 8) return text;
    return text.substring(0, 6);
  }

  String _fallbackTargetName(BuildContext context, String userUuid) {
    final shortId = _shortUserId(userUuid);
    if (shortId.isEmpty) {
      return _profileText(
        context,
        zhCN: '\u8be5\u7528\u6237',
        zhTW: '\u8a72\u7528\u6236',
        en: 'This user',
      );
    }
    return _profileText(
      context,
      zhCN: '\u7528\u6237 $shortId',
      zhTW: '\u7528\u6236 $shortId',
      en: 'User $shortId',
    );
  }

  String _qrPageTitle(
    BuildContext context, {
    required bool isSelfEntry,
    required String targetName,
  }) {
    if (isSelfEntry) {
      return _profileText(
        context,
        zhCN: '\u6211\u7684\u4e8c\u7ef4\u7801',
        zhTW: '\u6211\u7684\u4e8c\u7dad\u78bc',
        en: 'My QR Code',
      );
    }
    final name = targetName.trim();
    if (name.isEmpty) {
      return _profileText(
        context,
        zhCN: '\u4e8c\u7ef4\u7801\u540d\u7247',
        zhTW: '\u4e8c\u7dad\u78bc\u540d\u7247',
        en: 'QR Contact Card',
      );
    }
    switch (AppLocalizations.of(context).language) {
      case AppLanguage.en:
        return "$name's QR Code";
      case AppLanguage.zhTW:
        return '$name\u7684\u4e8c\u7dad\u78bc';
      case AppLanguage.zhCN:
        return '$name\u7684\u4e8c\u7ef4\u7801';
    }
  }

  String _qrHintText(
    BuildContext context, {
    required bool isSelfEntry,
    required String targetName,
  }) {
    if (isSelfEntry) {
      return _profileText(
        context,
        zhCN:
            '\u626b\u63cf\u4e8c\u7ef4\u7801\u6dfb\u52a0\u6211\u4e3a\u597d\u53cb',
        zhTW: '\u6383\u63cf\u4e8c\u7dad\u78bc\u52a0\u6211\u70ba\u597d\u53cb',
        en: 'Scan the QR code to add me as a friend',
      );
    }
    final name = targetName.trim();
    if (name.isEmpty) {
      return _profileText(
        context,
        zhCN:
            '\u626b\u63cf\u4e8c\u7ef4\u7801\u6dfb\u52a0\u8be5\u7528\u6237\u4e3a\u597d\u53cb',
        zhTW:
            '\u6383\u63cf\u4e8c\u7dad\u78bc\u65b0\u589e\u8a72\u7528\u6236\u70ba\u597d\u53cb',
        en: 'Scan the QR code to add this user as a friend',
      );
    }
    switch (AppLocalizations.of(context).language) {
      case AppLanguage.en:
        return 'Scan the QR code to add $name as a friend';
      case AppLanguage.zhTW:
        return '\u6383\u63cf\u4e8c\u7dad\u78bc\u65b0\u589e $name \u70ba\u597d\u53cb';
      case AppLanguage.zhCN:
        return '\u626b\u63cf\u4e8c\u7ef4\u7801\u6dfb\u52a0 $name \u4e3a\u597d\u53cb';
    }
  }

  String _shareText({
    required BuildContext context,
    required bool isSelfEntry,
    required String displayName,
    required String qrPayload,
  }) {
    if (isSelfEntry) {
      return _profileText(
        context,
        zhCN: '$displayName\u7684\u4e8c\u7ef4\u7801\u540d\u7247\n$qrPayload',
        zhTW: '$displayName\u7684\u4e8c\u7dad\u78bc\u540d\u7247\n$qrPayload',
        en: "$displayName's QR contact card\n$qrPayload",
      );
    }
    return _profileText(
      context,
      zhCN: '$displayName\u7684\u4e8c\u7ef4\u7801\u540d\u7247\n$qrPayload',
      zhTW: '$displayName\u7684\u4e8c\u7dad\u78bc\u540d\u7247\n$qrPayload',
      en: "$displayName's QR contact card\n$qrPayload",
    );
  }

  Future<void> _shareQrCard({
    required bool isSelfEntry,
    required String displayName,
    required String qrPayload,
  }) async {
    if (_isSharing) return;
    HapticFeedback.mediumImpact();

    final shareText = _shareText(
      context: context,
      isSelfEntry: isSelfEntry,
      displayName: displayName,
      qrPayload: qrPayload,
    );

    if (qrPayload.isEmpty) {
      await Share.share(shareText);
      return;
    }

    setState(() => _isSharing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _qrCardKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        await Share.share(shareText);
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ImageByteFormat.png);
      final bytes = byteData?.buffer.asUint8List();
      if (bytes == null || bytes.isEmpty) {
        await Share.share(shareText);
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final safeName = displayName
          .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
          .replaceAll(RegExp(r'_+'), '_');
      final file = File(
        '${tempDir.path}/genericim_qr_${safeName.isEmpty ? 'user' : safeName}_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: shareText,
      );
    } catch (e) {
      debugPrint('[ProfileQRCode] Share failed: $e');
      await Share.share(shareText);
    } finally {
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authServiceProvider.select((s) => s.user));
    String? nonEmpty(String? value) {
      final text = value?.trim() ?? '';
      return text.isEmpty ? null : text;
    }

    String? usernameValue(String? value) {
      final text = nonEmpty(value);
      if (text == null) return null;
      return text.startsWith('@') ? nonEmpty(text.substring(1)) : text;
    }

    final explicitUserUuid = nonEmpty(widget.userUuid);
    final isSelfEntry = widget.isSelfEntry ?? explicitUserUuid == null;
    final authUserUuid = nonEmpty(user?.uuid);
    final userUuid = isSelfEntry
        ? (authUserUuid ?? explicitUserUuid ?? '')
        : (explicitUserUuid ?? '');
    final fallbackName = isSelfEntry
        ? _profileText(
            context,
            zhCN: '未登录',
            zhTW: '未登入',
            en: 'Not signed in',
          )
        : _fallbackTargetName(context, userUuid);
    final displayName = isSelfEntry
        ? (nonEmpty(widget.displayName) ??
            nonEmpty(user?.nickname) ??
            usernameValue(user?.username) ??
            fallbackName)
        : (nonEmpty(widget.displayName) ??
            usernameValue(widget.username) ??
            fallbackName);
    final username = isSelfEntry
        ? (usernameValue(widget.username) ?? usernameValue(user?.username))
        : usernameValue(widget.username);
    // 自己：展示个人邀请码（10 位数字）—— 用于名片下方文字与点击复制。
    // 非自己：拿不到对方的 invite_code，fallback 到短 UUID 片段。
    final inviteCode = isSelfEntry ? nonEmpty(user?.inviteCode) : null;
    final qrPayload = userUuid.isNotEmpty ? buildUserQrPayload(userUuid) : '';
    final avatar = isSelfEntry
        ? (nonEmpty(widget.avatar) ?? user?.avatar)
        : nonEmpty(widget.avatar);
    final secondaryText = inviteCode ??
        (username != null
            ? '@$username'
            : (userUuid.isNotEmpty ? _shortUserId(userUuid) : displayName));
    final titleText = _qrPageTitle(
      context,
      isSelfEntry: isSelfEntry,
      targetName: displayName,
    );
    final hintText = _qrHintText(
      context,
      isSelfEntry: isSelfEntry,
      targetName: displayName,
    );
    final pageAnimation =
        widget.animation ?? const AlwaysStoppedAnimation<double>(1);
    final selectedStyle =
        _qrCardStyles[_selectedStyleIndex.clamp(0, _qrCardStyles.length - 1)];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              selectedStyle.backgroundStart,
              selectedStyle.backgroundEnd,
            ],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _QrDoodleBackgroundPainter(
                  color: Colors.white.withOpacity(0.28),
                ),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final pageWidth = constraints.maxWidth;
                  final isNarrowScreen = pageWidth < 360;
                  final isShortScreen = constraints.maxHeight < 720;
                  final horizontalGutter = pageWidth < 320
                      ? 10.0
                      : (pageWidth * 0.055).clamp(16.0, 28.0);
                  final cardWidth = math.min(
                    400.0,
                    math.max(0.0, pageWidth - horizontalGutter * 2),
                  );
                  final qrSize = math.min(
                    isShortScreen ? 232.0 : 268.0,
                    math.max(
                      0.0,
                      cardWidth - (isNarrowScreen ? 48 : 64),
                    ),
                  );
                  final avatarFrameSize =
                      isShortScreen || isNarrowScreen ? 66.0 : 74.0;
                  final avatarSize = avatarFrameSize - 12;
                  final compactGap = isShortScreen ? 10.0 : 16.0;

                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                            children: [
                              // 顶部栏
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const SizedBox(width: 48),
                                    Expanded(
                                      child: Text(
                                        titleText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF182033),
                                        ),
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => Navigator.pop(context),
                                      child: Container(
                                        width: 36,
                                        height: 36,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withOpacity(0.06),
                                              blurRadius: 12,
                                              offset: const Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          color: Color(0xFF5D6A85),
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: isShortScreen ? 2 : 8),
                              // 二维码卡片
                              ScaleTransition(
                                scale: CurvedAnimation(
                                  parent: pageAnimation,
                                  curve: Curves.easeOutBack,
                                ),
                                child: RepaintBoundary(
                                  key: _qrCardKey,
                                  child: Container(
                                    width: cardWidth,
                                    margin: EdgeInsets.only(
                                      top: isShortScreen ? 8 : 14,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(
                                        isNarrowScreen ? 24 : 30,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.12),
                                          blurRadius: 24,
                                          offset: const Offset(0, 12),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Transform.translate(
                                          offset: Offset(
                                            0,
                                            -(avatarFrameSize * 0.3),
                                          ),
                                          child: Container(
                                            width: avatarFrameSize,
                                            height: avatarFrameSize,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: selectedStyle.primary,
                                                width: 4,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: selectedStyle.primary
                                                      .withOpacity(0.24),
                                                  blurRadius: 16,
                                                  offset: const Offset(0, 8),
                                                ),
                                              ],
                                            ),
                                            child: Padding(
                                              padding: const EdgeInsets.all(3),
                                              child: AvatarWidget(
                                                name: displayName,
                                                avatar: avatar,
                                                size: avatarSize,
                                                isCircle: true,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Transform.translate(
                                          offset: Offset(
                                            0,
                                            isShortScreen ? -9 : -11,
                                          ),
                                          child: const SizedBox.shrink(),
                                        ),
                                        SizedBox(
                                          height: isShortScreen ? 0 : 2,
                                        ),
                                        // 名字
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                          ),
                                          child: Text(
                                            displayName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: isShortScreen ? 20 : 22,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        // 邀请码 / 用户名（点击复制到剪贴板）
                                        GestureDetector(
                                          onTap: secondaryText.isEmpty
                                              ? null
                                              : () {
                                                  HapticFeedback.lightImpact();
                                                  Clipboard.setData(
                                                    ClipboardData(
                                                        text: secondaryText),
                                                  );
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        _profileText(
                                                          context,
                                                          zhCN: inviteCode != null
                                                              ? '邀请码已复制'
                                                              : '用户名已复制',
                                                          zhTW: inviteCode != null
                                                              ? '邀請碼已複製'
                                                              : '使用者名稱已複製',
                                                          en: inviteCode != null
                                                              ? 'Invite code copied'
                                                              : 'Username copied',
                                                        ),
                                                      ),
                                                      behavior: SnackBarBehavior
                                                          .floating,
                                                      duration: const Duration(
                                                          seconds: 1),
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(10),
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
                                              color: AppColors.emphasisSoftFor(
                                                context,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Text(
                                              secondaryText,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14,
                                                color:
                                                    AppColors.linkFor(context),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: compactGap),
                                        // 真实二维码
                                        SizedBox(
                                          width: qrSize,
                                          child: AspectRatio(
                                            aspectRatio: 1,
                                            child: Container(
                                              padding: EdgeInsets.all(
                                                isNarrowScreen ? 8 : 10,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                  isNarrowScreen ? 20 : 24,
                                                ),
                                                border: Border.all(
                                                  color: selectedStyle.primary
                                                      .withOpacity(0.12),
                                                ),
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
                                                        eyeShape:
                                                            QrEyeShape.circle,
                                                        color: selectedStyle
                                                            .primary,
                                                      ),
                                                      dataModuleStyle:
                                                          QrDataModuleStyle(
                                                        dataModuleShape:
                                                            QrDataModuleShape
                                                                .square,
                                                        color: selectedStyle
                                                            .secondary,
                                                      ),
                                                      backgroundColor:
                                                          Colors.white,
                                                      padding:
                                                          const EdgeInsets.all(
                                                        6,
                                                      ),
                                                      gapless: true,
                                                      semanticsLabel: hintText,
                                                    ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          height: isShortScreen ? 8 : 12,
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                          ),
                                          child: Text(
                                            username != null
                                                ? '@${username.toUpperCase()}'
                                                : '@GENERICIM',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize:
                                                  isNarrowScreen ? 20 : 22,
                                              letterSpacing: 0.3,
                                              color: selectedStyle.secondary,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        SizedBox(height: compactGap),
                                        // 提示文字
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 20,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Icon(
                                                Icons.qr_code_scanner_rounded,
                                                size: 16,
                                                color: Colors.grey[400],
                                              ),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: Text(
                                                  hintText,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey[500],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        SizedBox(
                                          height: isShortScreen ? 20 : 26,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              SizedBox(height: isShortScreen ? 12 : 18),
                              _QRStylePicker(
                                styles: _qrCardStyles,
                                selectedIndex: _selectedStyleIndex,
                                onSelected: (index) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _selectedStyleIndex = index);
                                },
                              ),
                              SizedBox(height: isShortScreen ? 10 : 14),
                              Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: horizontalGutter + 4,
                                ),
                                child: _QRPrimaryButton(
                                  label: _profileText(
                                    context,
                                    zhCN: '分享二维码',
                                    zhTW: '分享二維碼',
                                    en: 'Share QR Code',
                                  ),
                                  isLoading: _isSharing,
                                  onTap: () => _shareQrCard(
                                    isSelfEntry: isSelfEntry,
                                    displayName: displayName,
                                    qrPayload: qrPayload,
                                  ),
                                ),
                              ),
                              SizedBox(height: isShortScreen ? 10 : 18),
                              TextButton.icon(
                                onPressed: () {
                                  HapticFeedback.selectionClick();
                                  // 关掉「我的二维码」页，进入扫码页；不可仅 pop
                                  // 否则用户会误以为「点了没反应」。
                                  final outerContext = context;
                                  Navigator.of(outerContext).pop();
                                  outerContext.push('/scan');
                                },
                                icon: Icon(
                                  Icons.qr_code_scanner_rounded,
                                  color: selectedStyle.primary,
                                ),
                                label: Text(
                                  _profileText(
                                    context,
                                    zhCN: '扫描二维码',
                                    zhTW: '掃描二維碼',
                                    en: 'Scan QR Code',
                                  ),
                                  style: TextStyle(
                                    color: selectedStyle.primary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              const SizedBox(height: 14),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
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
          color: AppColors.inputBackgroundFor(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.controlBorderFor(context),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6F8FD8).withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppColors.linkFor(context), size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: AppColors.linkFor(context),
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

class _QRPrimaryButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onTap;

  const _QRPrimaryButton({
    required this.label,
    this.isLoading = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.controlActiveFor(context),
      borderRadius: BorderRadius.circular(28),
      child: InkWell(
        borderRadius: BorderRadius.circular(28),
        onTap: isLoading ? null : onTap,
        child: SizedBox(
          height: 58,
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.onControlActiveFor(context),
                      ),
                    ),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      color: AppColors.onControlActiveFor(context),
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _QRStylePicker extends StatelessWidget {
  final List<_QrCardStyle> styles;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const _QRStylePicker({
    required this.styles,
    required this.selectedIndex,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _profileText(
                  context,
                  zhCN: '二维码',
                  zhTW: '二維碼',
                  en: 'QR Code',
                ),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF15171A),
                ),
              ),
              const Spacer(),
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  color: Color(0xFFF4F7FA),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.nights_stay_rounded,
                  color: Color(0xFF4EA3E5),
                  size: 22,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: styles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final style = styles[index];
                return _QRStyleThumbnail(
                  style: style,
                  selected: index == selectedIndex,
                  onTap: () => onSelected(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QRStyleThumbnail extends StatelessWidget {
  final _QrCardStyle style;
  final bool selected;
  final VoidCallback onTap;

  const _QRStyleThumbnail({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 86,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected ? const Color(0xFF4EA3E5) : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [style.backgroundStart, style.backgroundEnd],
                    ),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.92),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.qr_code_2_rounded,
                        color: style.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      style.emoji,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrDoodleBackgroundPainter extends CustomPainter {
  final Color color;

  const _QrDoodleBackgroundPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;

    const spacing = 92.0;
    for (double y = -20; y < size.height + spacing; y += spacing) {
      for (double x = -24; x < size.width + spacing; x += spacing) {
        final shift = ((x + y) ~/ spacing).isEven ? 0.0 : 36.0;
        final center = Offset(x + shift, y);
        canvas.drawCircle(center, 16, paint);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: center + const Offset(42, 24),
              width: 28,
              height: 18,
            ),
            const Radius.circular(6),
          ),
          paint,
        );
        final path = Path()
          ..moveTo(center.dx - 28, center.dy + 36)
          ..quadraticBezierTo(
            center.dx - 8,
            center.dy + 18,
            center.dx + 10,
            center.dy + 38,
          )
          ..quadraticBezierTo(
            center.dx + 24,
            center.dy + 54,
            center.dx + 42,
            center.dy + 34,
          );
        canvas.drawPath(path, paint);
        canvas.drawLine(
          center + const Offset(-42, -18),
          center + const Offset(-22, -34),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _QrDoodleBackgroundPainter oldDelegate) {
    return oldDelegate.color != color;
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
