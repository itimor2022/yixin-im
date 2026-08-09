// 文件用途：提供 avatar crop 在原生平台的实现，服务于跨模块共享能力。
// 核心逻辑：实现 avatar crop 的原生平台分支，封装系统权限或文件能力，并保持跨平台调用契约一致。
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';

// 关键声明：avatar crop io 是原生平台实现，集中处理系统权限、文件或窗口能力，避免业务层散落平台判断。
// 流程逻辑：`readFileBytes` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
Future<Uint8List> readFileBytes(String path) async {
  return await File(path).readAsBytes();
}

Future<String> saveCroppedFile(Uint8List data) async {
  // 裁剪结果写入系统临时目录，仅用于后续上传/预览，不是长期用户文件。
  final tempDir = await getTemporaryDirectory();
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final file = File('${tempDir.path}/cropped_avatar_$timestamp.png');
  await file.writeAsBytes(data);
  return file.path;
}
