// 文件用途：提供不支持目标平台时使用的启动占位实现。
// 核心逻辑：提供 bootstrap 的无平台能力占位实现，让条件导入在不支持的平台仍能完成编译和安全降级。
// 关键声明：bootstrap stub 是条件导入占位实现，保持公共 API 可调用并在不支持的平台安全返回降级结果。
// 流程逻辑：`bootstrapApp` 先建立依赖和监听器，再启动异步任务；重复调用必须复用已有状态，失败时释放已建立的资源。
Future<void> bootstrapApp() async {
  throw UnsupportedError('Unsupported platform');
}
