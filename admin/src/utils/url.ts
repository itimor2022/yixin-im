/**
 * URL 相关工具函数
 *
 * @module utils/url
 */

/**
 * 获取后端 API 基础地址（不含 /api/v1）
 * 用于处理相对路径的图片等资源
 */
export function getApiBaseUrl(): string {
  // 开发环境使用代理目标地址
  if (import.meta.env.VITE_API_PROXY_URL) {
    return import.meta.env.VITE_API_PROXY_URL
  }
  // 生产环境从 API URL 中提取基础地址
  const apiUrl = import.meta.env.VITE_API_URL || '/api/v1'
  if (apiUrl.startsWith('http')) {
    // 从 https://api.example.com/api/v1 提取 https://api.example.com
    try {
      const url = new URL(apiUrl)
      return `${url.protocol}//${url.host}`
    } catch {
      return ''
    }
  }
  return ''
}

// 缓存基础地址，避免重复计算
const API_BASE_URL = getApiBaseUrl()

/**
 * 修复图片 URL
 * 将相对路径或 localhost 地址转换为正确的服务器地址
 */
export function fixImageUrl(url: string | null | undefined): string {
  if (!url) return ''
  if (url.startsWith('/uploads/') || url.startsWith('uploads/')) {
    return `${API_BASE_URL}${url.startsWith('/') ? url : '/' + url}`
  }
  if (url.includes('localhost')) {
    return url.replace(/http:\/\/localhost:\d+/, API_BASE_URL)
  }
  return url
}

/**
 * 获取头像 URL
 * 如果有头像则修复 URL，否则使用 Dicebear 生成默认头像
 */
export function getLocalAvatarDataUrl(seed: string | number | null | undefined): string {
  const text = String(seed ?? '?')
  let hash = 0
  for (let i = 0; i < text.length; i++) {
    hash = (hash * 31 + text.charCodeAt(i)) >>> 0
  }

  const colors = ['#2563EB', '#059669', '#DC2626', '#7C3AED', '#D97706', '#0891B2']
  const bg = colors[hash % colors.length]
  const label = (text.trim().charAt(0).toUpperCase() || '?')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96"><rect width="96" height="96" rx="24" fill="${bg}"/><text x="48" y="58" text-anchor="middle" font-family="Arial, sans-serif" font-size="36" font-weight="700" fill="#fff">${label}</text></svg>`
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`
}

export function getAvatarUrl(avatar: string | null | undefined, seed: string): string {
  if (avatar) return fixImageUrl(avatar)
  return getLocalAvatarDataUrl(seed)
}
