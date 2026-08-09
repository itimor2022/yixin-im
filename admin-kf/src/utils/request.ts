export interface RequestOptions extends Omit<RequestInit, 'body'> {
  url: string
  query?: Record<string, string | number | boolean | undefined | null>
  body?: unknown
}

import { clearServiceAdminToken, getServiceAdminToken, redirectToServiceAdminLogin } from '@/utils/auth'

export class ServiceRequestError extends Error {
  readonly status: number

  constructor(message: string, status: number) {
    super(message)
    this.name = 'ServiceRequestError'
    this.status = status
  }
}

export function isServiceRequestErrorStatus(error: unknown, status: number) {
  return error instanceof ServiceRequestError && error.status === status
}

function buildUrl(url: string, query?: RequestOptions['query']) {
  const baseUrl = import.meta.env.VITE_API_BASE_URL || '/api/v1'
  const fullUrl = `${baseUrl}${url}`
  if (!query) return fullUrl

  const params = new URLSearchParams()
  Object.entries(query).forEach(([key, value]) => {
    if (value === undefined || value === null || value === '') return
    params.append(key, String(value))
  })

  const queryString = params.toString()
  return queryString ? `${fullUrl}?${queryString}` : fullUrl
}

function handleUnauthorized() {
  clearServiceAdminToken()
  redirectToServiceAdminLogin()
}

function fallbackMessageByStatus(status: number) {
  if (status === 401) return '登录状态已失效，请重新登录'
  if (status === 403) return '无权限执行此操作'
  if (status >= 500) return '服务器繁忙，请稍后重试'
  if (status === 404) return '请求的资源不存在'
  return `请求失败（${status}）`
}

async function resolveErrorMessage(response: Response) {
  const fallback = fallbackMessageByStatus(response.status)
  const contentType = response.headers.get('content-type') || ''
  if (!contentType.includes('application/json')) {
    return fallback
  }

  try {
    const data = await response.clone().json()
    const message = data?.message || data?.msg
    return typeof message === 'string' && message.trim() ? message.trim() : fallback
  } catch {
    return fallback
  }
}

export async function request<T>(options: RequestOptions): Promise<T> {
  const { url, query, headers, body, ...rest } = options
  const token = getServiceAdminToken()

  const response = await fetch(buildUrl(url, query), {
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...headers
    },
    body: body ? JSON.stringify(body) : undefined,
    ...rest
  })

  if (response.status === 401) {
    handleUnauthorized()
  }

  if (!response.ok) {
    throw new ServiceRequestError(await resolveErrorMessage(response), response.status)
  }

  const data = await response.json()
  if (data?.code && data.code !== 0) {
    const code = Number(data.code)
    if (code === 401) {
      handleUnauthorized()
    }
    const message =
      typeof data.message === 'string' && data.message.trim()
        ? data.message.trim()
        : '请求失败'
    throw new ServiceRequestError(message, code || response.status)
  }
  return data.data ?? data
}
