// 文件用途：提供 web rsa keygen 的跨平台占位实现，供条件导入在不支持的平台使用。
// 核心逻辑：提供 web rsa keygen 的无平台能力占位实现，让条件导入在不支持的平台仍能完成编译和安全降级。
// 关键声明：web rsa keygen stub 是条件导入占位实现，保持公共 API 可调用并在不支持的平台安全返回降级结果。
// 流程逻辑：本文件没有可执行方法，关键行为由导出的常量、条件实现或模块声明决定；修改时需保持公共导出契约稳定。
/// 非 Web 平台不通过 Web Crypto 生成密钥；上层收到 null 后使用平台实现。
Future<Map<String, String>?> tryGenerateWebRsaJwkKeyPair() async {
  return null;
}
