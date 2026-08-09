// 文件用途：提供 _AvatarCropDialog 可复用界面组件，服务于跨模块共享能力。
// 核心逻辑：根据输入模型和状态渲染 _AvatarCropDialog，通过回调向上层提交交互；组件本身不直接持久化跨页面业务数据。
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';

import '../../core/i18n/app_localizations.dart';
import '../../core/theme/app_colors.dart';
import 'avatar_crop_io.dart' if (dart.library.html) 'avatar_crop_web.dart'
    as crop_io;

String _avatarCropText(
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

/// Web 端最近一次裁剪结果。
///
/// 这是兼容现有字符串返回值的单槽位桥接，不支持并发裁剪；调用方收到
/// `web_cropped` 后应立即读取并复制所需字节。
Uint8List? lastCroppedImageBytes;

/// 显示头像裁剪对话框
/// Native: 传 [imagePath]，返回裁剪后的文件路径
/// Web: 传 [imageBytes]，返回 'web_cropped'，通过 [lastCroppedImageBytes] 获取裁剪结果
Future<String?> showAvatarCropDialog({
  required BuildContext context,
  String? imagePath,
  Uint8List? imageBytes,
  String? title,
}) async {
  // imageBytes 优先；原生端缺少字节时才读取 imagePath，Web 不接受本地文件路径。
  Uint8List? bytes = imageBytes;

  if (bytes == null && imagePath != null) {
    if (kIsWeb) return null;
    try {
      bytes = await crop_io.readFileBytes(imagePath);
    } catch (e) {
      debugPrint('Failed to read file: $e');
      return null;
    }
  }

  if (bytes == null) return null;

  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: false,
    barrierLabel: '',
    barrierColor: Colors.black,
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return _AvatarCropDialog(imageData: bytes!, title: title);
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        )),
        child: child,
      );
    },
  );
}

// 关键声明：avatar crop page 只负责将输入状态渲染为界面，并通过回调把交互结果交还页面或状态层。
class _AvatarCropDialog extends StatefulWidget {
  final Uint8List imageData;
  final String? title;

  const _AvatarCropDialog({
    required this.imageData,
    this.title,
  });

  @override
  State<_AvatarCropDialog> createState() => _AvatarCropDialogState();
}

class _AvatarCropDialogState extends State<_AvatarCropDialog> {
  final _cropController = CropController();
  bool _isCropping = false;
  bool _isCropReady = false;
  Timer? _cropTimeoutTimer;

  @override
  void dispose() {
    _cropTimeoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _onCrop() async {
    if (_isCropping || !_isCropReady) return;
    setState(() => _isCropping = true);
    _cropTimeoutTimer?.cancel();
    // 超时只恢复交互和提示错误，底层裁剪库没有可取消任务句柄。
    _cropTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      _handleCropFailure(
        _avatarCropText(
          context,
          zhCN: '裁剪超时，请重试',
          zhTW: '裁剪逾時，請重試',
          en: 'Crop timed out. Please try again.',
        ),
      );
    });

    runZonedGuarded(
      () => _cropController.cropCircle(),
      (error, stack) => _handleCropFailure(error),
    );
  }

  Future<void> _onCropped(Uint8List croppedData) async {
    _cropTimeoutTimer?.cancel();
    try {
      if (kIsWeb) {
        // Web 无文件路径语义，通过模块级字节槽位把结果交还旧调用接口。
        lastCroppedImageBytes = croppedData;
        if (mounted) Navigator.pop(context, 'web_cropped');
        return;
      }

      final path = await crop_io.saveCroppedFile(croppedData);
      if (mounted) Navigator.pop(context, path);
    } catch (e) {
      if (mounted) {
        setState(() => _isCropping = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _avatarCropText(
                context,
                zhCN: '裁剪失败: $e',
                zhTW: '裁剪失敗: $e',
                en: 'Crop failed: $e',
              ),
            ),
          ),
        );
      }
    }
  }

  void _handleCropFailure(Object error) {
    _cropTimeoutTimer?.cancel();
    if (!mounted) return;
    setState(() => _isCropping = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error is String
              ? error
              : _avatarCropText(
                  context,
                  zhCN: '裁剪失败，请重试',
                  zhTW: '裁剪失敗，請重試',
                  en: 'Crop failed. Please try again.',
                ),
        ),
      ),
    );
  }

  void _onStatusChanged(CropStatus status) {
    if (!mounted) return;
    final ready = status == CropStatus.ready;
    if (_isCropReady == ready || _isCropping) return;
    setState(() => _isCropReady = ready);
  }

  // 流程逻辑：`build` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            _avatarCropText(
              context,
              zhCN: '取消',
              zhTW: '取消',
              en: 'Cancel',
            ),
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
        leadingWidth: 80,
        title: Text(
          widget.title ??
              _avatarCropText(
                context,
                zhCN: '裁剪头像',
                zhTW: '裁剪頭像',
                en: 'Crop Avatar',
              ),
          style: const TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isCropping || !_isCropReady ? null : _onCrop,
            child: _isCropping
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(
                    _avatarCropText(
                      context,
                      zhCN: '保存',
                      zhTW: '儲存',
                      en: 'Done',
                    ),
                    style: TextStyle(
                        color: _isCropReady
                            ? AppColors.darkLink
                            : Colors.white.withOpacity(0.35),
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Crop(
              controller: _cropController,
              image: widget.imageData,
              onCropped: _onCropped,
              aspectRatio: 1,
              initialSize: 0.8,
              withCircleUi: true,
              baseColor: Colors.black,
              maskColor: Colors.black.withOpacity(0.7),
              onStatusChanged: _onStatusChanged,
              cornerDotBuilder: (size, edgeAlignment) =>
                  const SizedBox.shrink(),
              interactive: true,
              fixCropRect: true,
              progressIndicator: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            child: Text(
              _avatarCropText(
                context,
                zhCN: '拖动和缩放来调整头像',
                zhTW: '拖曳和縮放來調整頭像',
                en: 'Drag and zoom to adjust the avatar',
              ),
              style:
                  TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 14),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
