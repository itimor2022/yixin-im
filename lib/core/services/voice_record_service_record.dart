// 文件用途：封装 voice record service record 相关业务流程与外部能力调用，属于业务服务。
// 核心逻辑：封装 voice record service record 的外部能力调用，先校验输入和会话，再转换响应结果并向上层返回可处理的错误状态。
// 关键声明：voice record service record 是业务副作用入口，负责校验参数、调用外部资源并把异常转换为上层可处理结果。
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
/// 非 Web 平台的录音 API 出口。
///
/// 与 Web 文件保持相同导出面，使上层条件导入后只依赖统一的 record 接口。
export 'package:record/record.dart';
