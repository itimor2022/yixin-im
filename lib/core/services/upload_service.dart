import 'package:universal_io/io.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'api/api_client.dart';

/// 上传服务 Provider
final uploadServiceProvider = Provider<UploadService>((ref) {
  final api = ref.watch(apiClientProvider);
  final service = UploadService(api);
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});

/// 上传服务
class UploadService {
  final ApiClient _api;
  final ImagePicker _picker = ImagePicker();
  bool _isDisposed = false;
  final Set<String> _uploadingFiles = {}; // 防止重复上传

  UploadService(this._api);

  Future<MultipartFile> _toMultipartFile(XFile file) async {
    // 优先使用 XFile 自带的 mimeType；HEIC 等格式系统可能返回
    // application/octet-stream，此时回退到扩展名推断
    final rawMime = file.mimeType ?? '';
    final mimeType = (rawMime.isEmpty || rawMime == 'application/octet-stream')
        ? _mimeTypeFromFilename(file.name)
        : rawMime;
    return MultipartFile.fromBytes(
      await file.readAsBytes(),
      filename: file.name,
      contentType: DioMediaType.parse(mimeType),
    );
  }
  
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
    
    if (images.length > maxImages) {
      return images.sublist(0, maxImages);
    }
    return images;
  }

  /// 从相机拍照
  Future<XFile?> takePhoto() async {
    return await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1920,
    );
  }

  /// 从相册选择视频
  Future<XFile?> pickVideo() async {
    return await _picker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
  }

  /// 从相机录制视频
  Future<XFile?> recordVideo() async {
    return await _picker.pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(minutes: 1),
    );
  }

  /// 上传单张图片
  Future<String?> uploadImage(XFile file) async {
    if (_isDisposed) return null;
    
    // 防止重复上传
    final key = 'image:${file.name}:${file.path}';
    if (_uploadingFiles.contains(key)) {
      return null;
    }
    
    try {
      _uploadingFiles.add(key);
      final formData = FormData.fromMap({
        'file': await _toMultipartFile(file),
      });

      final response = await _api.upload('/upload/image', formData);
      
      if (response.isSuccess && response.data != null) {
        return response.data['url'] as String?;
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Upload] Image error: $e');
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
        'files': await Future.wait(
          files.map((f) => _toMultipartFile(f)),
        ),
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
      if (kDebugMode) debugPrint('[Upload] Images error: $e');
      return [];
    }
  }

  /// 上传视频
  Future<String?> uploadVideo(XFile file) async {
    try {
      final formData = FormData.fromMap({
        'file': await _toMultipartFile(file),
      });

      final response = await _api.upload('/upload/video', formData);
      
      if (response.isSuccess && response.data != null) {
        return response.data['url'] as String?;
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Upload] Video error: $e');
      return null;
    }
  }

  /// 上传头像
  Future<String?> uploadAvatar(XFile file) async {
    try {
      final formData = FormData.fromMap({
        'file': await _toMultipartFile(file),
      });

      final response = await _api.upload('/upload/avatar', formData);
      
      if (response.isSuccess && response.data != null) {
        return response.data['url'] as String?;
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Upload] Avatar error: $e');
      return null;
    }
  }

  /// 上传图片数据（Uint8List）
  Future<String?> uploadImageData(Uint8List data, String filename) async {
    try {
      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          data,
          filename: filename,
          contentType: DioMediaType.parse(_mimeTypeFromFilename(filename)),
        ),
      });

      final response = await _api.upload('/upload/image', formData);
      
      if (response.isSuccess && response.data != null) {
        return response.data['url'] as String?;
      }
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('[Upload] Image data error: $e');
      return null;
    }
  }

  /// 根据文件名扩展名推断 MIME 类型
  /// 用于 uploadImageData 等无法获取 XFile.mimeType 的场景
  String _mimeTypeFromFilename(String filename) {
    final ext = filename.toLowerCase().split('.').last;
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
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'avi':
        return 'video/x-msvideo';
      case 'webm':
        return 'video/webm';
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      default:
        return 'application/octet-stream';
    }
  }
}