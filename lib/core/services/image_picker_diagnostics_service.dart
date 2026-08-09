// 文件用途：封装 ImagePickerDiagnosticsService 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 ImagePickerDiagnosticsService 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
import 'dart:developer' as developer;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../utils/platform_utils.dart';

// 关键声明：image picker diagnostics service 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
/// 收集图片选择器在 Android 上的诊断信息。
///
/// Android 可能在系统选择器打开期间回收应用进程，[retrieveLostDataOnStartup]
/// 用于记录插件遗留结果，便于定位厂商兼容性问题；它不负责恢复或继续上传文件。
class ImagePickerDiagnosticsService {
  ImagePickerDiagnosticsService._();

  static final ImagePickerDiagnosticsService instance =
      ImagePickerDiagnosticsService._();

  final ImagePicker _picker = ImagePicker();
  bool _lostDataChecked = false;

  // 流程逻辑：`retrieveLostDataOnStartup` 负责一次完整的外部调用边界，包含参数准备、响应转换、异常归一化和必要的重试/清理。
  Future<void> retrieveLostDataOnStartup() async {
    if (!PlatformUtils.isAndroid || _lostDataChecked) return;
    // 每个进程只读取一次，避免插件遗留结果被重复诊断。
    _lostDataChecked = true;

    try {
      final response = await _picker.retrieveLostData();
      final files = response.files ??
          (response.file == null ? const <XFile>[] : <XFile>[response.file!]);
      final exception = response.exception;
      await logPickerResult(
        source: 'startup_retrieve_lost_data',
        count: files.length,
        error: exception == null
            ? null
            : '${exception.code}: ${exception.message ?? ''}',
        extra:
            'isEmpty=${response.isEmpty} type=${response.type?.name ?? '-'} files=${_fileSummary(files)}',
      );
    } catch (e, st) {
      await logPickerResult(
        source: 'startup_retrieve_lost_data',
        count: 0,
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> logPickerResult({
    required String source,
    required int count,
    Object? error,
    StackTrace? stackTrace,
    String? extra,
  }) async {
    // 设备信息读取失败时仍记录选择结果，诊断能力不能影响媒体主流程。
    final device = await _androidDeviceSummary();
    final message = '[ImagePicker] source=$source count=$count '
        'device=$device${extra == null || extra.isEmpty ? '' : ' $extra'}';
    if (error == null) {
      _log(message);
    } else {
      _log('$message error=$error', error: error, stackTrace: stackTrace);
    }
  }

  Future<String> _androidDeviceSummary() async {
    if (!PlatformUtils.isAndroid) return PlatformUtils.platformName;
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      return '${info.manufacturer}/${info.brand} ${info.model} '
          'sdk=${info.version.sdkInt} release=${info.version.release}';
    } catch (e) {
      return 'android device_info_error=$e';
    }
  }

  String _fileSummary(List<XFile> files) {
    if (files.isEmpty) return '-';
    // 最多记录五个文件，且只记录文件名和路径是否存在，不输出完整本地路径。
    return files.take(5).map((file) {
      final name = file.name.isEmpty ? '<unnamed>' : file.name;
      return '$name:path=${file.path.isEmpty ? 'empty' : 'present'}';
    }).join(',');
  }

  void _log(String message, {Object? error, StackTrace? stackTrace}) {
    debugPrint(message);
    developer.log(
      message,
      name: 'ImagePickerDiagnostics',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
