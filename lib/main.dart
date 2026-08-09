// 文件用途：作为 Flutter 应用入口，完成运行前初始化并启动根应用。
// 核心逻辑：按平台执行启动初始化，建立依赖注入和错误边界后调用根应用入口，保证服务启动顺序稳定。
import 'bootstrap/bootstrap.dart';
import 'core/services/deep_link_service.dart';

// 关键声明：应用入口只负责启动编排，不承载页面业务；所有异步初始化都在启动阶段集中捕获错误并交给统一错误边界。
// 流程逻辑：`main` 先保存启动参数，再调用统一启动流程；启动异常由 bootstrap 层集中处理。
Future<void> main(List<String> arguments) {
  // 桌面端协议唤起参数必须先保存，后续路由和 Provider 初始化时才能消费同一份启动上下文。
  DeepLinkService.instance.setLaunchArguments(arguments);
  return bootstrapApp();
}
