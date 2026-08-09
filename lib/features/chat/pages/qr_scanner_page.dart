// 文件用途：实现 QRScannerPage 页面及其交互流程，属于聊天与消息。
// 核心逻辑：维护 QRScannerPage 页面状态，响应用户操作并调用 Provider/Service；同时处理加载、成功、失败和返回导航。
import 'package:universal_io/io.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/services/api/api_client.dart';
import '../../../core/services/api/auth_service.dart';
import '../../../core/i18n/app_localizations.dart';
import '../../../core/i18n/server_message_localizer.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/system_ui_styles.dart';
import '../../../core/utils/platform_utils.dart';
import '../../../core/utils/qr_payload.dart';
import '../../settings/pages/device_login_confirm_page.dart';
import '../providers/chat_provider.dart';
import '../../contacts/providers/contact_provider.dart';
import '../services/qr_image_decoder.dart'
    if (dart.library.html) '../services/qr_image_decoder_web.dart';

String _qrText(
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

String _qrRuntimeText({
  required String zhCN,
  String? zhTW,
  required String en,
}) {
  switch (AppLocalizations.currentLanguage) {
    case AppLanguage.en:
      return en;
    case AppLanguage.zhTW:
      return zhTW ?? zhCN;
    case AppLanguage.zhCN:
      return zhCN;
  }
}

// 关键声明：二维码 scanner page 是页面入口，负责组装局部状态、监听用户操作并把副作用交给 Provider/Service。
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

  // 流程逻辑：`initState` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
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
        _showMessage(
          _qrText(
            context,
            zhCN: '无法识别',
            zhTW: '無法識別',
            en: 'Unable to recognize QR code',
          ),
        );
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
        _showMessage(
          _qrText(
            context,
            zhCN: '无法识别',
            zhTW: '無法識別',
            en: 'Unable to recognize QR code',
          ),
        );
        await _resumeScanner();
        return;
      }

      final currentUser = ref.read(authServiceProvider).user;
      if (currentUser?.uuid == payload.id) {
        _showMessage(
          _qrText(
            context,
            zhCN: '这是你自己的二维码',
            zhTW: '這是你自己的二維碼',
            en: 'This is your own QR code',
          ),
        );
        await _resumeScanner();
        return;
      }

      final scannedUser = await _fetchScannedUser(payload.id);
      if (scannedUser == null) {
        _showMessage(
          _qrText(
            context,
            zhCN: '无法识别',
            zhTW: '無法識別',
            en: 'Unable to recognize QR code',
          ),
        );
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
          _showMessage(
            success
                ? _qrText(
                    context,
                    zhCN: '已将 ${scannedUser.name} 添加到联系人',
                    zhTW: '已將 ${scannedUser.name} 加入聯絡人',
                    en: 'Added ${scannedUser.name} to contacts',
                  )
                : _qrText(
                    context,
                    zhCN: '添加失败，请重试',
                    zhTW: '新增失敗，請重試',
                    en: 'Failed to add contact. Please try again.',
                  ),
          );
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
      _showMessage(
        _qrText(
          context,
          zhCN: '已确认登录桌面设备',
          zhTW: '已確認登入桌面裝置',
          en: 'Desktop login approved',
        ),
      );
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
        _serverMessage(
          raw: response.message,
          zhCN: '打开聊天失败，请重试',
          zhTW: '開啟聊天失敗，請重試',
          en: 'Failed to open chat. Please try again.',
        ),
      );
      await _resumeScanner();
    } catch (_) {
      _showMessage(
        _qrText(
          context,
          zhCN: '打开聊天失败，请重试',
          zhTW: '開啟聊天失敗，請重試',
          en: 'Failed to open chat. Please try again.',
        ),
      );
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
            _serverMessage(
              raw: response.message,
              zhCN: '已提交加入申请，请等待管理员审批',
              zhTW: '已提交加入申請，請等待管理員審批',
              en: 'Join request submitted. Please wait for approval.',
            ),
          );
          await _resumeScanner();
          return;
        }
        final chatId = data['chat_id']?.toString() ?? '';
        if (chatId.isEmpty) {
          _showMessage(
            _qrText(
              context,
              zhCN: '加入群组失败，请重试',
              zhTW: '加入群組失敗，請重試',
              en: 'Failed to join group. Please try again.',
            ),
          );
          await _resumeScanner();
          return;
        }

        final chatName = (data['chat_name'] ??
                _qrText(
                  context,
                  zhCN: '群组',
                  zhTW: '群組',
                  en: 'Group',
                ))
            .toString();
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
        _serverMessage(
          raw: response.message,
          zhCN: '加入群组失败，请重试',
          zhTW: '加入群組失敗，請重試',
          en: 'Failed to join group. Please try again.',
        ),
      );
      await _resumeScanner();
    } catch (_) {
      _showMessage(
        _qrText(
          context,
          zhCN: '加入群组失败，请重试',
          zhTW: '加入群組失敗，請重試',
          en: 'Failed to join group. Please try again.',
        ),
      );
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
      final String? rawValue;
      if (PlatformUtils.isWeb) {
        if (!isQrImageDecodeSupported()) {
          _showMessage(
            _qrText(
              context,
              zhCN: '当前浏览器不支持相册识别二维码',
              zhTW: '目前瀏覽器不支援相簿識別二維碼',
              en: 'This browser does not support QR recognition from images.',
            ),
          );
          await _resumeScanner();
          return;
        }

        rawValue = await decodeQrImageBytes(
          await file.readAsBytes(),
          mimeType: file.mimeType ?? 'image/png',
        );
      } else {
        final capture = await _controller.analyzeImage(file.path);
        rawValue = capture?.barcodes
            .map((code) => code.rawValue?.trim())
            .whereType<String>()
            .firstWhere(
              (value) => value.isNotEmpty,
              orElse: () => '',
            );
      }

      if (rawValue == null || rawValue.isEmpty) {
        _showMessage(
          _qrText(
            context,
            zhCN: '无法识别',
            zhTW: '無法識別',
            en: 'Unable to recognize QR code',
          ),
        );
        await _resumeScanner();
        return;
      }

      await _processRawValue(rawValue);
    } catch (_) {
      _showMessage(
        _qrText(
          context,
          zhCN: '无法识别',
          zhTW: '無法識別',
          en: 'Unable to recognize QR code',
        ),
      );
      await _resumeScanner();
      if (mounted) {
        setState(() => _isProcessing = false);
      } else {
        _isProcessing = false;
      }
    }
  }

  Future<void> _toggleTorch() async {
    if (PlatformUtils.isWeb) {
      _showMessage(
        _qrText(
          context,
          zhCN: '浏览器暂不支持闪光灯控制',
          zhTW: '瀏覽器暫不支援閃光燈控制',
          en: 'Flashlight control is not supported in the browser.',
        ),
      );
      return;
    }
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
        return _qrText(
          context,
          zhCN: '相机权限被拒绝，请到系统设置里允许相机权限',
          zhTW: '相機權限被拒絕，請到系統設定允許相機權限',
          en: 'Camera permission denied. Please enable it in system settings.',
        );
      case MobileScannerErrorCode.unsupported:
        return _qrText(
          context,
          zhCN: '当前设备不支持扫码功能',
          zhTW: '目前裝置不支援掃碼功能',
          en: 'This device does not support QR scanning.',
        );
      case MobileScannerErrorCode.controllerUninitialized:
      case MobileScannerErrorCode.controllerInitializing:
      case MobileScannerErrorCode.controllerNotAttached:
        return _qrText(
          context,
          zhCN: '扫码器尚未准备好，请稍后重试',
          zhTW: '掃碼器尚未準備好，請稍後重試',
          en: 'Scanner is not ready yet. Please try again shortly.',
        );
      case MobileScannerErrorCode.controllerAlreadyInitialized:
        return _qrText(
          context,
          zhCN: '扫码器正在初始化，请稍后重试',
          zhTW: '掃碼器正在初始化，請稍後重試',
          en: 'Scanner is initializing. Please try again shortly.',
        );
      case MobileScannerErrorCode.controllerDisposed:
        return _qrText(
          context,
          zhCN: '扫码器已关闭，请重新进入页面',
          zhTW: '掃碼器已關閉，請重新進入頁面',
          en: 'Scanner has been closed. Please reopen this page.',
        );
      case MobileScannerErrorCode.genericError:
        return _qrText(
          context,
          zhCN: '相机初始化失败，请重试或使用相册识别',
          zhTW: '相機初始化失敗，請重試或使用相簿識別',
          en: 'Camera initialization failed. Retry or use gallery recognition.',
        );
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
                  child: Text(
                    _qrText(
                      context,
                      zhCN: '重试',
                      zhTW: '重試',
                      en: 'Retry',
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: _pickFromGallery,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryFor(context),
                    foregroundColor: AppColors.onPrimaryFor(context),
                  ),
                  child: Text(
                    _qrText(
                      context,
                      zhCN: '相册识别',
                      zhTW: '相簿識別',
                      en: 'Scan from Gallery',
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

  @override
  Widget build(BuildContext context) {
    final overlayColor = Colors.black.withOpacity(0.6);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: Theme.of(
          context,
        ).textTheme.titleLarge?.copyWith(color: Colors.white),
        systemOverlayStyle: AppSystemUiStyles.onDarkBackground,
        title: Text(
          _qrText(
            context,
            zhCN: '扫描二维码',
            zhTW: '掃描二維碼',
            en: 'Scan QR Code',
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _qrText(
              context,
              zhCN: '相册识别',
              zhTW: '相簿識別',
              en: 'Scan from Gallery',
            ),
            onPressed: _pickFromGallery,
            icon: const Icon(Icons.photo_library_outlined),
          ),
          if (!PlatformUtils.isWeb)
            IconButton(
              tooltip: _torchEnabled
                  ? _qrText(
                      context,
                      zhCN: '关闭闪光灯',
                      zhTW: '關閉閃光燈',
                      en: 'Turn off flashlight',
                    )
                  : _qrText(
                      context,
                      zhCN: '打开闪光灯',
                      zhTW: '打開閃光燈',
                      en: 'Turn on flashlight',
                    ),
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
            errorBuilder: (context, error) {
              return _buildScannerErrorWidget(error);
              /*
              return Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Text(
                    _qrText(
                      context,
                      zhCN: '扫码功能暂不可用，请检查相机权限或使用相册识别',
                      zhTW: '掃碼功能暫不可用，請檢查相機權限或使用相簿識別',
                      en: 'QR scanning is temporarily unavailable. Check camera permission or use gallery recognition.',
                    ),
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
                  _qrText(
                    context,
                    zhCN: '将二维码放入框内即可自动识别',
                    zhTW: '將二維碼放入框內即可自動識別',
                    en: 'Place the QR code inside the frame to scan',
                  ),
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
                    Platform.isIOS || Platform.isAndroid
                        ? _qrText(
                            context,
                            zhCN: '支持扫描好友二维码，识别后可直接加好友或查看资料',
                            zhTW: '支援掃描好友二維碼，識別後可直接加好友或查看資料',
                            en: 'Scan a friend QR code to add them or view their profile',
                          )
                        : _qrText(
                            context,
                            zhCN: '可通过相册选择二维码图片进行识别',
                            zhTW: '可透過相簿選擇二維碼圖片進行識別',
                            en: 'Choose a QR image from the gallery to scan',
                          ),
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
      name: (json['nickname'] ??
              json['username'] ??
              _qrRuntimeText(
                zhCN: '用户',
                zhTW: '使用者',
                en: 'User',
              ))
          .toString(),
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
        color: AppColors.cardFor(context),
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
                  color: AppColors.dividerFor(context),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 20),
              CircleAvatar(
                radius: 34,
                backgroundColor: AppColors.primaryWithOpacity(context, 0.12),
                backgroundImage:
                    user.avatar != null ? NetworkImage(user.avatar!) : null,
                child: user.avatar == null
                    ? Text(
                        user.name.isNotEmpty ? user.name[0] : 'U',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryFor(context),
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
                  color: AppColors.textPrimaryFor(context),
                ),
              ),
              if (user.username != null && user.username!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '@${user.username}',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.linkFor(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (user.bio != null && user.bio!.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  user.bio!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondaryFor(context),
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
                          color: AppColors.dividerFor(context),
                        ),
                      ),
                      child: Text(
                        _qrText(
                          context,
                          zhCN: '查看资料',
                          zhTW: '查看資料',
                          en: 'View Profile',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, _ScanAction.addFriend),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        backgroundColor: AppColors.primaryFor(context),
                        foregroundColor: AppColors.onPrimaryFor(context),
                      ),
                      child: Text(
                        _qrText(
                          context,
                          zhCN: '添加好友',
                          zhTW: '新增好友',
                          en: 'Add Contact',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context, _ScanAction.cancel),
                child: Text(
                  _qrText(
                    context,
                    zhCN: '取消',
                    zhTW: '取消',
                    en: 'Cancel',
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
