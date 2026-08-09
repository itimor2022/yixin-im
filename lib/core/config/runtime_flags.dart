// 文件用途：实现 RuntimeFlags 相关逻辑，服务于运行配置。
// 核心逻辑：围绕 RuntimeFlags 组织，完成输入校验、核心处理和结果回传。
// 关键声明：runtime flags 是运行配置入口，负责集中读取并暴露启动阶段需要的功能开关。
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
class RuntimeFlags {
  const RuntimeFlags._();

  static const bool smokeTest = bool.fromEnvironment('GENERIC_IM_SMOKE_TEST');

  /// Keeps the startup gate functional while suppressing bundled and remote
  /// splash artwork for customer builds that should open on a plain surface.
  static const bool disableSplashImage = bool.fromEnvironment(
    'GENERIC_IM_DISABLE_SPLASH_IMAGE',
  );
}
