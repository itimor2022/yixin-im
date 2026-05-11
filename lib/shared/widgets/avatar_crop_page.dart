import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:crop_your_image/crop_your_image.dart';

import '../../core/theme/app_colors.dart';
import 'avatar_crop_io.dart' if (dart.library.html) 'avatar_crop_web.dart'
    as crop_io;

/// Web 端裁剪后的字节数据，调用方通过此变量获取
Uint8List? lastCroppedImageBytes;

/// 显示头像裁剪对话框
/// Native: 传 [imagePath]，返回裁剪后的文件路径
/// Web: 传 [imageBytes]，返回 'web_cropped'，通过 [lastCroppedImageBytes] 获取裁剪结果
Future<String?> showAvatarCropDialog({
  required BuildContext context,
  String? imagePath,
  Uint8List? imageBytes,
  String title = '裁剪头像',
}) async {
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

class _AvatarCropDialog extends StatefulWidget {
  final Uint8List imageData;
  final String title;

  const _AvatarCropDialog({
    required this.imageData,
    this.title = '裁剪头像',
  });

  @override
  State<_AvatarCropDialog> createState() => _AvatarCropDialogState();
}

class _AvatarCropDialogState extends State<_AvatarCropDialog> {
  final _cropController = CropController();
  bool _isCropping = false;

  Future<void> _onCrop() async {
    if (_isCropping) return;
    setState(() => _isCropping = true);
    _cropController.crop();
  }

  Future<void> _onCropped(Uint8List croppedData) async {
    try {
      if (kIsWeb) {
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
          SnackBar(content: Text('裁剪失败: $e')),
        );
      }
    }
  }

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
          child: const Text('取消',
              style: TextStyle(color: Colors.white, fontSize: 16)),
        ),
        leadingWidth: 80,
        title: Text(
          widget.title,
          style: const TextStyle(
              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isCropping ? null : _onCrop,
            child: _isCropping
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text('保存',
                    style: TextStyle(
                        color: AppColors.primary,
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
              cornerDotBuilder: (size, edgeAlignment) =>
                  const SizedBox.shrink(),
              interactive: true,
              fixCropRect: false,
              progressIndicator: const Center(
                child:
                    CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            child: Text(
              '拖动和缩放来调整头像',
              style: TextStyle(
                  color: Colors.white.withOpacity(0.6), fontSize: 14),
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }
}
