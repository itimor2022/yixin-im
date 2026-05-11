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
  const apiUrl = import.meta.env.VITE_API_URL || ''
  if (apiUrl.startsWith('http')) {
    // 从 https://imapi.yixin.com/api/v1 提取 https://imapi.yixin.com
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
export function fixImageUrl(url: string | null): string {
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
export function getAvatarUrl(avatar: string | null, seed: string): string {
  if (avatar) return fixImageUrl(avatar)
  return `https://api.dicebear.com/7.x/identicon/svg?seed=${seed}`
}
