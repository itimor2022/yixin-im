const tokenKey = 'service-admin-token'

// 客服后台与主管理后台使用独立存储键，避免同域部署时两套身份令牌互相覆盖。
export function getServiceAdminToken() {
  return localStorage.getItem(tokenKey) || ''
}

export function setServiceAdminToken(token: string) {
  localStorage.setItem(tokenKey, token)
}

export function clearServiceAdminToken() {
  localStorage.removeItem(tokenKey)
}

export function redirectToServiceAdminLogin() {
  // 该后台使用 Hash 路由；认证失效时直接改 hash，可在请求层之外完成兜底跳转。
  if (window.location.hash !== '#/login') {
    window.location.hash = '/login'
  }
}
