// 文件用途：提供 AndroidWebViewSupport 相关工具函数与通用转换逻辑，属于通用工具。
// 核心逻辑：提供 AndroidWebViewSupport 的无状态转换或校验函数，集中处理平台差异、空值、格式和边界输入。
import 'dart:async';
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

// 关键声明：android webview support 提供无状态工具逻辑，集中处理格式、平台差异和边界输入，调用方无需重复实现校验。
class AndroidWebViewSupport {
  const AndroidWebViewSupport._();

  static final ImagePicker _imagePicker = ImagePicker();

  static void configure(
    WebViewController controller, {
    String logTag = 'WebView',
  }) {
    // 非 Android 控制器保持平台默认行为；注册过程无需阻塞首个页面加载。
    if (controller.platform is! AndroidWebViewController) return;

    final androidController = controller.platform as AndroidWebViewController;
    unawaited(androidController.setMediaPlaybackRequiresUserGesture(false));
    unawaited(
      androidController.setOnShowFileSelector(
        (params) => _handleFileSelection(params, logTag: logTag),
      ),
    );
    unawaited(
      androidController.setOnPlatformPermissionRequest(
        (request) => _handlePermissionRequest(request, logTag: logTag),
      ),
    );
  }

  static Future<List<String>> _handleFileSelection(
    FileSelectorParams params, {
    required String logTag,
  }) async {
    try {
      final allowMultiple = params.mode == FileSelectorMode.openMultiple;
      final acceptedTypes = params.acceptTypes
          .map((type) => type.trim().toLowerCase())
          .where((type) => type.isNotEmpty)
          .toList();

      // accept/capture 来自网页，仅是选择器提示；空 accept 按兼容策略优先允许拍照。
      final wantsImage = acceptedTypes.isEmpty ||
          acceptedTypes.any((type) => type.startsWith('image/'));
      final wantsVideo = acceptedTypes.any((type) => type.startsWith('video/'));

      if (params.isCaptureEnabled && !allowMultiple) {
        if (wantsImage) {
          final capturedFile = await _imagePicker.pickImage(
            source: ImageSource.camera,
            imageQuality: 90,
            maxWidth: 1920,
            maxHeight: 1920,
          );
          return capturedFile == null
              ? <String>[]
              : <String>[capturedFile.path];
        }

        if (wantsVideo) {
          final capturedFile = await _imagePicker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(minutes: 5),
          );
          return capturedFile == null
              ? <String>[]
              : <String>[capturedFile.path];
        }
      }

      final isImageOnly = acceptedTypes.isNotEmpty &&
          acceptedTypes.every(
            (type) =>
                type.startsWith('image/') ||
                type == '.jpg' ||
                type == '.jpeg' ||
                type == '.png' ||
                type == '.gif' ||
                type == '.webp',
          );

      final extensions =
          isImageOnly ? <String>[] : _extractAllowedExtensions(acceptedTypes);
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: allowMultiple,
        type: isImageOnly
            ? FileType.image
            : extensions.isEmpty
                ? FileType.any
                : FileType.custom,
        allowedExtensions:
            !isImageOnly && extensions.isNotEmpty ? extensions : null,
      );

      if (result == null || result.files.isEmpty) {
        // WebView 约定空列表表示用户取消或本次选择失败。
        return <String>[];
      }

      return result.files.map((file) => file.path).whereType<String>().toList();
    } catch (error) {
      debugPrint('[$logTag] Android file selection failed: $error');
      return <String>[];
    }
  }

  static List<String> _extractAllowedExtensions(List<String> acceptedTypes) {
    final extensions = <String>{};
    for (final type in acceptedTypes) {
      if (type.startsWith('.')) {
        extensions.add(type.substring(1));
      }
    }
    return extensions.toList();
  }

  static Future<void> _handlePermissionRequest(
    PlatformWebViewPermissionRequest request, {
    required String logTag,
  }) async {
    try {
      final types = request.types;
      final needsCamera = types.contains(WebViewPermissionResourceType.camera);
      final needsMicrophone =
          types.contains(WebViewPermissionResourceType.microphone);

      final unsupportedTypes = types.where(
        (type) =>
            type != WebViewPermissionResourceType.camera &&
            type != WebViewPermissionResourceType.microphone,
      );
      if (unsupportedTypes.isNotEmpty) {
        // 权限集合必须整体可支持，不能只授权其中一部分后让网页误判能力完整。
        debugPrint('[$logTag] Denied unsupported WebView permission: $types');
        await request.deny();
        return;
      }

      final permissions = <Permission>[
        if (needsCamera) Permission.camera,
        if (needsMicrophone) Permission.microphone,
      ];

      for (final permission in permissions) {
        // 操作系统权限通过后仍需显式 grant 本次 WebView 请求；两层授权缺一不可。
        final status = await permission.request();
        if (!status.isGranted) {
          await request.deny();
          return;
        }
      }

      await request.grant();
    } catch (error) {
      debugPrint('[$logTag] Android WebView permission failed: $error');
      await request.deny();
    }
  }
}
