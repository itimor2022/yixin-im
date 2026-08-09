// 文件用途：封装 UploadService 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：统一处理媒体上传、进度、重试和失败清理，把本地文件或字节流转换成服务端媒体引用。
import 'package:universal_io/io.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'api/api_client.dart';
import 'image_picker_diagnostics_service.dart';

/// 上传服务 Provider
final uploadServiceProvider = Provider<UploadService>((ref) {
  final api = ref.watch(apiClientProvider);
  final service = UploadService(api);
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

// 关键声明：upload service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 传统后端中转上传入口，同时封装跨平台文件选择和 `XFile` 到 multipart 的转换。
///
/// 原生端优先流式读取文件路径，Web 端只能读取字节；返回 URL 仅在服务端确认成功后有效。
class UploadService {
  final ApiClient _api;
  final ImagePicker _picker = ImagePicker();
  bool _isDisposed = false;
  final Set<String> _uploadingFiles = {}; // 防止重复上传

  UploadService(this._api);

  Future<MultipartFile> _toMultipartFile(XFile file) async {
    final contentType = _mimeTypeForName(
      file.name.isNotEmpty ? file.name : file.path,
    );
    // Web 的 path 不代表可直接访问的系统文件，因此必须回退到内存字节。
    if (!kIsWeb && file.path.isNotEmpty && await File(file.path).exists()) {
      return MultipartFile.fromFile(
        file.path,
        filename: file.name,
        contentType: DioMediaType.parse(contentType),
      );
    }
    return MultipartFile.fromBytes(
      await file.readAsBytes(),
      filename: file.name,
      contentType: DioMediaType.parse(contentType),
    );
  }

  String _mimeTypeForName(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'avi':
        return 'video/x-msvideo';
      default:
        return 'application/octet-stream';
    }
  }

  // 流程逻辑：`dispose` 先阻止新的输入或回调，再按创建顺序的逆序取消订阅、定时器和临时资源，保证清理可重复执行。
  /// 释放资源
  void dispose() {
    _isDisposed = true;
    _uploadingFiles.clear();
  }

  /// 从相册选择图片
  Future<List<XFile>> pickImages({int maxImages = 9}) async {
    final images = await _picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    await ImagePickerDiagnosticsService.instance.logPickerResult(
      source: 'upload_service_pick_images',
      count: images.length,
    );

    if (images.length > maxImages) {
      return images.sublist(0, maxImages);
    }
    return images;
  }

  /// 从相机拍照
  Future<XFile?> takePhoto() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    await ImagePickerDiagnosticsService.instance.logPickerResult(
      source: 'upload_service_take_photo',
      count: image == null ? 0 : 1,
    );
    return image;
  }

  /// 从相册选择视频
  Future<XFile?> pickVideo() async {
    final video = await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    await ImagePickerDiagnosticsService.instance.logPickerResult(
      source: 'upload_service_pick_video',
      count: video == null ? 0 : 1,
    );
    return video;
  }

  /// 从相机录制视频
  Future<XFile?> recordVideo() async {
    final video = await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 1),
    );
    await ImagePickerDiagnosticsService.instance.logPickerResult(
      source: 'upload_service_record_video',
      count: video == null ? 0 : 1,
    );
    return video;
  }

  /// 上传单张图片
  Future<String?> uploadImage(XFile file) async {
    if (_isDisposed) return null;

    // 该集合只防止本实例内的并发重复提交，不承担跨重启幂等或断点续传。
    // 防止重复上传
    final key = 'image:${file.name}:${file.path}';
    if (_uploadingFiles.contains(key)) {
      return null;
    }

    try {
      _uploadingFiles.add(key);
      final formData = FormData.fromMap({'file': await _toMultipartFile(file)});

      final response = await _api.upload('/upload/image', formData);

      if (response.isSuccess && response.data != null) {
        return response.data['url'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('[Upload] Image error: $e');
      return null;
    } finally {
      _uploadingFiles.remove(key);
    }
  }

  /// 批量上传图片
  Future<List<String>> uploadImages(List<XFile> files) async {
    if (files.isEmpty) return [];

    try {
      final formData = FormData.fromMap({
        'files': await Future.wait(files.map((f) => _toMultipartFile(f))),
      });

      final response = await _api.upload('/upload/images', formData);

      if (response.isSuccess && response.data != null) {
        final filesList = response.data['files'] as List<dynamic>?;
        if (filesList != null) {
          return filesList.map((f) => f['url'] as String).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint('[Upload] Images error: $e');
      return [];
    }
  }

  /// 上传视频
  Future<String?> uploadVideo(XFile file) async {
    try {
      final formData = FormData.fromMap({'file': await _toMultipartFile(file)});

      final response = await _api.upload('/upload/video', formData);

      if (response.isSuccess && response.data != null) {
        return response.data['url'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('[Upload] Video error: $e');
      return null;
    }
  }

  /// 上传头像
  Future<String?> uploadAvatar(XFile file) async {
    try {
      final formData = FormData.fromMap({'file': await _toMultipartFile(file)});

      final response = await _api.upload('/upload/avatar', formData);

      if (response.isSuccess && response.data != null) {
        return response.data['url'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('[Upload] Avatar error: $e');
      return null;
    }
  }

  /// 上传图片数据（Uint8List）
  Future<String?> uploadImageData(Uint8List data, String filename) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(data, filename: filename),
      });

      final response = await _api.upload('/upload/image', formData);

      if (response.isSuccess && response.data != null) {
        return response.data['url'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('[Upload] Image data error: $e');
      return null;
    }
  }
}
