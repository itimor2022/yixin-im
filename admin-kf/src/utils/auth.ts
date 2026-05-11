const tokenKey = 'service-admin-token'

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
  if (window.location.hash !== '#/login') {
    window.location.hash = '/login'
  }
}
