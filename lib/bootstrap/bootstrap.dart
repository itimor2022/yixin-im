// 文件用途：定义跨平台启动流程的统一入口，并按运行平台选择具体实现。
// 核心逻辑：围绕 bootstrap 组织，完成输入校验、核心处理和结果回传。
import 'bootstrap_stub.dart'
    if (dart.library.html) 'bootstrap_web.dart'
    if (dart.library.io) 'bootstrap_native.dart' as bootstrap;

// 关键声明：bootstrap 负责平台启动顺序和资源初始化，失败时必须可观测并安全停止后续任务。
// 流程逻辑：`bootstrapApp` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
/// 通过条件导入隔离平台启动流程，业务入口无需直接依赖 `dart:io` 或浏览器 API。
Future<void> bootstrapApp() => bootstrap.bootstrapApp();
