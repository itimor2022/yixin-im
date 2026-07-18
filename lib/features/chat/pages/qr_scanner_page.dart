import 'package:flutter/foundation.dart';
import 'package:universal_io/io.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/platform_utils.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/qr_payload.dart';
import '../../settings/pages/device_login_confirm_page.dart';
import '../providers/chat_provider.dart';
import '../../contacts/providers/contact_provider.dart';

class QRScannerPage extends ConsumerStatefulWidget {
  const QRScannerPage({super.key});

  @override
  ConsumerState<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends ConsumerState<QRScannerPage>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  final ImagePicker _imagePicker = ImagePicker();

  bool _isProcessing = false;
  bool _torchEnabled = false;
  String? _lastHandledValue;
  DateTime? _lastHandledAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.value.isInitialized) {
      return;
    }

    switch (state) {
      case AppLifecycleState.resumed:
        if (!_isProcessing) {
          _controller.start();
        }
        break;
      case AppLifecycleState.inactive:
        _controller.stop();
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        break;
    }
  }

  bool _shouldIgnore(String value) {
    final now = DateTime.now();
    if (_lastHandledValue == value &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < const Duration(seconds: 2)) {
      return true;
    }
    _lastHandledValue = value;
    _lastHandledAt = now;
    return false;
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final rawValue = capture.barcodes
        .map((code) => code.rawValue?.trim())
        .whereType<String>()
        .firstWhere(
          (value) => value.isNotEmpty,
          orElse: () => '',
        );

    if (rawValue.isEmpty || _shouldIgnore(rawValue)) return;

    await _processRawValue(rawValue);
  }

  Future<void> _processRawValue(String rawValue) async {
    setState(() => _isProcessing = true);
    await _controller.stop();

    try {
      final payload = parseOneChatQrPayload(rawValue);
      if (payload == null) {
        _showMessage('无法识别');
        await _resumeScanner();
        return;
      }

      if (payload.type == OneChatQrType.login) {
        await _confirmDesktopLogin(payload.id);
        return;
      }

      if (payload.type == OneChatQrType.group) {
        await _joinGroupByInviteLink(payload.id);
        return;
      }

      if (payload.type != OneChatQrType.user) {
        _showMessage('无法识别');
        await _resumeScanner();
        return;
      }

      final currentUser = ref.read(authServiceProvider).user;
      if (currentUser?.uuid == payload.id) {
        _showMessage('这是你自己的二维码');
        await _resumeScanner();
        return;
      }

      final scannedUser = await _fetchScannedUser(payload.id);
      if (scannedUser == null) {
        _showMessage('无法识别');
        await _resumeScanner();
        return;
      }

      await ref.read(contactListProvider.notifier).loadFromServer();
      final contacts = ref.read(contactListProvider);
      final isFriend = contacts.any(
        (contact) =>
            contact.uuid == scannedUser.uuid || contact.id == scannedUser.uuid,
      );

      if (isFriend) {
        await _openPrivateChat(scannedUser);
        return;
      }

      if (!mounted) return;
      final action = await showModalBottomSheet<_ScanAction>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => _ScannedUserSheet(
          user: scannedUser,
        ),
      );

      if (!mounted) return;

      switch (action) {
        case _ScanAction.addFriend:
          final success = await ref
              .read(contactListProvider.notifier)
              .addContact(scannedUser.uuid);
          _showMessage(success ? '已将 ${scannedUser.name} 添加到联系人' : '添加失败，请重试');
          await _resumeScanner();
          break;
        case _ScanAction.viewProfile:
          final avatarParam =
              scannedUser.avatar != null && scannedUser.avatar!.isNotEmpty
                  ? '&avatar=${Uri.encodeComponent(scannedUser.avatar!)}'
                  : '';
          if (!mounted) return;
          context.pushReplacement(
            '/user/${scannedUser.uuid}?name=${Uri.encodeComponent(scannedUser.name)}$avatarParam',
          );
          break;
        case _ScanAction.cancel:
        case null:
          await _resumeScanner();
          break;
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      } else {
        _isProcessing = false;
      }
    }
  }

  Future<void> _confirmDesktopLogin(String ticket) async {
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DeviceLoginConfirmPage(ticket: ticket),
      ),
    );

    if (!mounted) return;

    if (confirmed == true) {
      _showMessage('已确认登录桌面设备');
      context.pop();
      return;
    }

    await _resumeScanner();
  }

  Future<_ScannedUser?> _fetchScannedUser(String userUuid) async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.get<Map<String, dynamic>>(
        '/user/$userUuid',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (response.isSuccess && response.data != null) {
        return _ScannedUser.fromJson(response.data!);
      }
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<void> _openPrivateChat(_ScannedUser user) async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.post<Map<String, dynamic>>(
        '/chat/create',
        data: {
          'type': 1,
          'member_ids': [user.uuid],
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (!mounted) return;

      if (response.isSuccess && response.data != null) {
        final chatId = response.data!['uuid']?.toString();
        if (chatId != null && chatId.isNotEmpty) {
          final avatarParam = user.avatar != null && user.avatar!.isNotEmpty
              ? '&avatar=${Uri.encodeComponent(user.avatar!)}'
              : '';
          context.pushReplacement(
            '/chat/$chatId?name=${Uri.encodeComponent(user.name)}&type=private$avatarParam',
          );
          return;
        }
      }

      _showMessage(
          response.message.isNotEmpty ? response.message : '打开聊天失败，请重试');
      await _resumeScanner();
    } catch (_) {
      _showMessage('打开聊天失败，请重试');
      await _resumeScanner();
    }
  }

  Future<void> _joinGroupByInviteLink(String inviteLink) async {
    try {
      final api = ref.read(apiClientProvider);
      final response = await api.post<Map<String, dynamic>>(
        '/chat/invite/$inviteLink/join',
        fromJson: (data) => data as Map<String, dynamic>,
      );

      if (!mounted) return;

      if (response.isSuccess && response.data != null) {
        final data = response.data!;
        final requiresApproval = data['requires_approval'] == true;
        if (requiresApproval) {
          _showMessage(
            response.message.isNotEmpty ? response.message : '已提交加入申请，请等待管理员审批',
          );
          await _resumeScanner();
          return;
        }
        final chatId = data['chat_id']?.toString() ?? '';
        if (chatId.isEmpty) {
          _showMessage('加入群组失败，请重试');
          await _resumeScanner();
          return;
        }

        final chatName = (data['chat_name'] ?? '群组').toString();
        final rawAvatar = data['chat_avatar']?.toString();
        final chatAvatar = rawAvatar != null && rawAvatar.isNotEmpty
            ? ApiConfig.getMediaUrl(rawAvatar)
            : null;
        final chatTypeValue =
            int.tryParse(data['chat_type']?.toString() ?? '2') ?? 2;
        final routeType = chatTypeValue == 3 ? 'channel' : 'group';

        await ref.read(chatListProvider.notifier).refresh();
        if (!mounted) return;

        final avatarParam = chatAvatar != null && chatAvatar.isNotEmpty
            ? '&avatar=${Uri.encodeComponent(chatAvatar)}'
            : '';
        context.pushReplacement(
          '/chat/$chatId?name=${Uri.encodeComponent(chatName)}&type=$routeType$avatarParam',
        );
        return;
      }

      _showMessage(
        response.message.isNotEmpty ? response.message : '加入群组失败，请重试',
      );
      await _resumeScanner();
    } catch (_) {
      _showMessage('加入群组失败，请重试');
      await _resumeScanner();
    }
  }

  Future<void> _resumeScanner() async {
    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    await _controller.start();
  }

  Future<void> _pickFromGallery() async {
    if (_isProcessing) return;

    final file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    setState(() => _isProcessing = true);
    await _controller.stop();

    try {
      final capture = await _controller.analyzeImage(file.path);
      final rawValue = capture?.barcodes
          .map((code) => code.rawValue?.trim())
          .whereType<String>()
          .firstWhere(
            (value) => value.isNotEmpty,
            orElse: () => '',
          );

      if (rawValue == null || rawValue.isEmpty) {
        _showMessage('无法识别');
        await _resumeScanner();
        return;
      }

      await _processRawValue(rawValue);
    } catch (_) {
      _showMessage('无法识别');
      await _resumeScanner();
      if (mounted) {
        setState(() => _isProcessing = false);
      } else {
        _isProcessing = false;
      }
    }
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (!mounted) return;
    setState(() => _torchEnabled = !_torchEnabled);
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _scannerErrorText(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return '相机权限被拒绝，请到系统设置里允许相机权限';
      case MobileScannerErrorCode.unsupported:
        return '当前设备不支持扫码功能';
      case MobileScannerErrorCode.controllerUninitialized:
        return '扫码器尚未准备好，请稍后重试';
      case MobileScannerErrorCode.controllerAlreadyInitialized:
        return '扫码器正在初始化，请稍后重试';
      case MobileScannerErrorCode.controllerDisposed:
        return '扫码器已关闭，请重新进入页面';
      case MobileScannerErrorCode.genericError:
        return '相机初始化失败，请重试或使用相册识别';
    }
  }

  Widget _buildScannerErrorWidget(MobileScannerException error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.qr_code_scanner_rounded,
              color: Colors.white,
              size: 42,
            ),
            const SizedBox(height: 16),
            Text(
              _scannerErrorText(error),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withOpacity(0.92),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (error.errorDetails?.message?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                error.errorDetails!.message!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.65),
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  onPressed: () => _controller.start(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                  ),
                  child: const Text('重试'),
                ),
                FilledButton(
                  onPressed: _pickFromGallery,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('相册识别'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Web 端不支持摄像头扫码，显示上传图片识别界面
    if (kIsWeb) {
      return _buildWebFallback(context);
    }

    final overlayColor = Colors.black.withOpacity(0.6);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('扫描二维码'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '相册识别',
            onPressed: _pickFromGallery,
            icon: const Icon(Icons.photo_library_outlined),
          ),
          IconButton(
            tooltip: _torchEnabled ? '关闭闪光灯' : '打开闪光灯',
            onPressed: _toggleTorch,
            icon: Icon(_torchEnabled
                ? Icons.flash_on_rounded
                : Icons.flash_off_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            fit: BoxFit.cover,
            onDetect: _handleDetect,
            errorBuilder: (context, error, child) {
              return _buildScannerErrorWidget(error);
              /*
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    '扫码功能暂不可用，请检查相机权限或使用相册识别',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
              */
            },
          ),
          CustomPaint(
            painter: _ScannerOverlayPainter(
              overlayColor: overlayColor,
            ),
            child: const SizedBox.expand(),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 52,
            child: Column(
              children: [
                if (_isProcessing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                Text(
                  '将二维码放入框内即可自动识别',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Text(
                    PlatformUtils.isMobile
                        ? '支持扫描好友二维码，识别后可直接加好友或查看资料'
                        : '可通过相册选择二维码图片进行识别',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Web 端降级：不支持摄像头扫码，提供图片上传识别
  Widget _buildWebFallback(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        title: const Text('扫描二维码'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 52,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Web 端扫码',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Web 端不支持摄像头扫码\n请上传包含二维码的图片进行识别',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.white54 : Colors.black54,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 36),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _pickFromGallery,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.photo_library_outlined),
                  label: Text(_isProcessing ? '识别中...' : '从图片识别二维码'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannedUser {
  final String uuid;
  final String name;
  final String? username;
  final String? avatar;
  final String? bio;

  const _ScannedUser({
    required this.uuid,
    required this.name,
    this.username,
    this.avatar,
    this.bio,
  });

  factory _ScannedUser.fromJson(Map<String, dynamic> json) {
    final avatar = (json['avatar'] ?? '').toString().trim();
    return _ScannedUser(
      uuid: (json['id'] ?? '').toString(),
      name: (json['nickname'] ?? json['username'] ?? '用户').toString(),
      username: json['username']?.toString(),
      avatar: avatar.isEmpty ? null : ApiConfig.getMediaUrl(avatar),
      bio: json['bio']?.toString(),
    );
  }
}

enum _ScanAction {
  addFriend,
  viewProfile,
  cancel,
}

class _ScannedUserSheet extends StatelessWidget {
  final _ScannedUser user;

  const _ScannedUserSheet({
    required this.user,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 34,
                backgroundColor: AppColors.primary.withOpacity(0.12),
                backgroundImage:
                    user.avatar != null ? NetworkImage(user.avatar!) : null,
                child: user.avatar == null
                    ? Text(
                        user.name.isNotEmpty ? user.name[0] : 'U',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                user.name,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              // if (user.username != null && user.username!.isNotEmpty) ...[
              //   const SizedBox(height: 6),
              //   Text(
              //     '@${user.username}',
              //     style: const TextStyle(
              //       fontSize: 14,
              //       color: AppColors.primary,
              //       fontWeight: FontWeight.w500,
              //     ),
              //   ),
              // ],
              if (user.bio != null && user.bio!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  user.bio!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.black54,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.pop(context, _ScanAction.viewProfile),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        side: BorderSide(
                          color: isDark ? Colors.white24 : Colors.black12,
                        ),
                      ),
                      child: const Text('查看资料'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, _ScanAction.addFriend),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        backgroundColor: AppColors.primary,
                      ),
                      child: const Text('添加好友'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context, _ScanAction.cancel),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  final Color overlayColor;

  const _ScannerOverlayPainter({
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const scanSize = 260.0;
    final scanRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 40),
      width: scanSize,
      height: scanSize,
    );

    final background = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutout = Path()
      ..addRRect(
        RRect.fromRectAndRadius(scanRect, const Radius.circular(24)),
      );

    canvas.drawPath(
      Path.combine(PathOperation.difference, background, cutout),
      Paint()..color = overlayColor,
    );

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    canvas.drawRRect(
      RRect.fromRectAndRadius(scanRect, const Radius.circular(24)),
      borderPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.overlayColor != overlayColor;
  }
}
