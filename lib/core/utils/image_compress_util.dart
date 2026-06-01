import 'package:universal_io/io.dart';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';

/// 图片压缩工具类
/// 
/// 功能：
/// - 自动压缩大图到合理尺寸
/// - 保持图片质量的同时减少体积
/// - 支持 JPEG/PNG/WebP 格式
class ImageCompressUtil {
  /// 最大图片宽度（像素）
  static const int maxWidth = 1920;
  
  /// 最大图片高度（像素）
  static const int maxHeight = 1920;
  
  /// 压缩质量（0-100）
  static const int quality = 85;
  
  /// 需要压缩的文件大小阈值（1MB）
  static const int compressThreshold = 1024 * 1024;
  
  /// 压缩图片文件
  /// 
  /// [filePath] 原始图片路径
  /// [targetWidth] 目标宽度（可选，默认使用 maxWidth）
  /// [targetHeight] 目标高度（可选，默认使用 maxHeight）
  /// [targetQuality] 目标质量（可选，默认使用 quality）
  /// 
  /// 返回压缩后的文件路径，如果不需要压缩则返回原路径
  static Future<String> compressImage(
    String filePath, {
    int? targetWidth,
    int? targetHeight,
    int? targetQuality,
  }) async {
    if (kIsWeb) return filePath;
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return filePath;
      }
      
      final fileSize = await file.length();
      
      // 小于阈值的图片不压缩
      if (fileSize < compressThreshold) {
        if (kDebugMode) debugPrint('[ImageCompress] Skip: file size ${_formatSize(fileSize)} < threshold');
        return filePath;
      }
      
      if (kDebugMode) debugPrint('[ImageCompress] Compressing: ${_formatSize(fileSize)}');
      
      // 获取临时目录
      final tempDir = await getTemporaryDirectory();
      final targetPath = '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      
      // 执行压缩
      final result = await FlutterImageCompress.compressAndGetFile(
        filePath,
        targetPath,
        minWidth: targetWidth ?? maxWidth,
        minHeight: targetHeight ?? maxHeight,
        quality: targetQuality ?? quality,
        format: CompressFormat.jpeg,
        keepExif: false, // 移除 EXIF 信息以减少体积
      );
      
      if (result == null) {
        if (kDebugMode) debugPrint('[ImageCompress] Failed, using original');
        return filePath;
      }
      
      final compressedSize = await result.length();
      final ratio = ((1 - compressedSize / fileSize) * 100).toStringAsFixed(1);
      
      if (kDebugMode) debugPrint('[ImageCompress] Done: ${_formatSize(fileSize)} -> ${_formatSize(compressedSize)} (-$ratio%)');
      
      // 如果压缩后反而更大，返回原图
      if (compressedSize >= fileSize) {
        if (kDebugMode) debugPrint('[ImageCompress] Compressed larger, using original');
        await File(targetPath).delete().catchError((_) {});
        return filePath;
      }
      
      return result.path;
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageCompress] Error: $e');
      return filePath; // 出错时返回原图
    }
  }
  
  /// 压缩图片为字节数组
  static Future<Uint8List?> compressImageToBytes(
    String filePath, {
    int? targetWidth,
    int? targetHeight,
    int? targetQuality,
  }) async {
    if (kIsWeb) return null;
    try {
      final result = await FlutterImageCompress.compressWithFile(
        filePath,
        minWidth: targetWidth ?? maxWidth,
        minHeight: targetHeight ?? maxHeight,
        quality: targetQuality ?? quality,
        format: CompressFormat.jpeg,
      );
      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageCompress] Error: $e');
      return null;
    }
  }
  
  /// 格式化文件大小
  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
