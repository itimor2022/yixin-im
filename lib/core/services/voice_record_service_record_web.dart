// 文件用途：提供 voice record service record 在 Web 平台的实现，服务于业务服务。
// 核心逻辑：实现 voice record service record 的 Web 平台分支，适配浏览器 API 和资源生命周期，并保持与原生实现相同的调用契约。
// 关键声明：voice record service record web 是 Web 平台实现，负责把浏览器资源和异步生命周期适配为跨平台接口。
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
/// Web 平台的录音 API 出口。
///
/// 单独保留适配文件，避免上层服务感知 record 包的平台实现差异。
export 'package:record/record.dart';
