import { onBeforeUnmount, ref } from 'vue'
import { getServiceAdminToken } from '@/utils/auth'

export interface ServiceSocketEvent {
  type: string
  event_id?: string
  conversation_uuid?: string
  status?: string
  updated_at?: string
  [key: string]: unknown
}

function buildServiceWebSocketURL() {
  const configured = String(import.meta.env.VITE_API_BASE_URL || '/api/v1').replace(/\/$/, '')
  const token = encodeURIComponent(getServiceAdminToken())
  // 绝对 API 地址沿用其主机；相对地址沿用当前页面主机，并按页面协议选择 ws/wss。
  if (/^https?:\/\//i.test(configured)) {
    return `${configured.replace(/^http/i, 'ws')}/ws?token=${token}&device_type=service-admin-web`
  }
  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
  const path = configured.startsWith('/') ? configured : `/${configured}`
  return `${protocol}//${window.location.host}${path}/ws?token=${token}&device_type=service-admin-web`
}

export function useServiceWebSocket(onEvent: (event: ServiceSocketEvent) => void) {
  const state = ref<'idle' | 'connecting' | 'connected' | 'reconnecting' | 'closed'>('idle')
  let socket: WebSocket | undefined
  let reconnectTimer: number | undefined
  let reconnectAttempt = 0
  let manuallyClosed = false

  const scheduleReconnect = () => {
    if (manuallyClosed || reconnectTimer) return
    state.value = 'reconnecting'
    // 指数退避上限 15 秒；成功连接后 reconnectAttempt 会归零。
    const delay = Math.min(15_000, 1000 * 2 ** Math.min(reconnectAttempt, 4))
    reconnectAttempt += 1
    reconnectTimer = window.setTimeout(() => {
      reconnectTimer = undefined
      connect()
    }, delay)
  }

  const connect = () => {
    if (import.meta.env.VITE_USE_MOCK === 'true') {
      state.value = 'connected'
      return
    }
    const token = getServiceAdminToken()
    if (!token || socket?.readyState === WebSocket.OPEN || socket?.readyState === WebSocket.CONNECTING) return
    manuallyClosed = false
    state.value = reconnectAttempt ? 'reconnecting' : 'connecting'
    socket = new WebSocket(buildServiceWebSocketURL())
    socket.onopen = () => {
      reconnectAttempt = 0
      state.value = 'connected'
    }
    socket.onmessage = (message) => {
      try {
        const event = JSON.parse(String(message.data)) as ServiceSocketEvent
        // type 是客服工作台分发实时事件的唯一必需字段，其余字段按事件类型按需读取。
        if (event && typeof event.type === 'string') onEvent(event)
      } catch {
        // 忽略非 JSON 的协议噪声，队列最终仍以 HTTP 数据为准。
      }
    }
    socket.onerror = () => socket?.close()
    socket.onclose = () => {
      socket = undefined
      scheduleReconnect()
    }
  }

  const disconnect = () => {
    // 手动关闭会同时取消待执行的重连；组件卸载时必须走这里，避免后台页面残留连接。
    manuallyClosed = true
    state.value = 'closed'
    if (reconnectTimer) window.clearTimeout(reconnectTimer)
    reconnectTimer = undefined
    socket?.close()
    socket = undefined
  }

  // Composable 的连接所有权属于调用组件，生命周期结束时不保留全局 Socket。
  onBeforeUnmount(disconnect)
  return { state, connect, disconnect }
}
