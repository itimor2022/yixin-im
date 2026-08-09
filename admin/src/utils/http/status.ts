/**
 * 接口状态码
 * 适配 通用IM后端
 */
export enum ApiStatus {
  success = 0, // 成功 (后端使用 0 表示成功)
  error = 400, // 错误
  unauthorized = 401, // 未授权
  forbidden = 403, // 禁止访问
  notFound = 404, // 未找到
  methodNotAllowed = 405, // 方法不允许
  requestTimeout = 408, // 请求超时
  internalServerError = 500, // 服务器错误
  notImplemented = 501, // 未实现
  badGateway = 502, // 网关错误
  serviceUnavailable = 503, // 服务不可用
  gatewayTimeout = 504, // 网关超时
  httpVersionNotSupported = 505 // HTTP版本不支持
}
