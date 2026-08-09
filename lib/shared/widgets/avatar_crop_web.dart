// 文件用途：提供 avatar crop 在 Web 平台的实现，服务于跨模块共享能力。
// 核心逻辑：实现 avatar crop 的 Web 平台分支，适配浏览器 API 和资源生命周期，并保持与原生实现相同的调用契约。
import 'dart:typed_data';

// 关键声明：avatar crop web 是 Web 平台实现，负责把浏览器资源和异步生命周期适配为跨平台接口。
// 流程逻辑：`readFileBytes` 根据输入状态生成组件 UI，并通过回调向上层报告交互结果，不在构建阶段直接修改全局状态。
Future<Uint8List> readFileBytes(String path) async {
  // Web 构建保留同一接口以满足条件导入，实际数据必须由浏览器选择器提供字节。
  throw UnsupportedError('File reading not supported on web');
}

Future<String> saveCroppedFile(Uint8List data) async {
  // 浏览器没有可返回给原生调用方的本地文件路径，结果由页面的字节桥接传递。
  throw UnsupportedError('File saving not supported on web');
}
