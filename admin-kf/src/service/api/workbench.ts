import { mockConversations, mockMessages } from '@/service/mock/workbench'
import type {
  ConversationQueue,
  ServiceConversation,
  ServiceMessage
} from '@/types/customer-service'
import { request } from '@/utils/request'

const useMock = import.meta.env.VITE_USE_MOCK === 'true'

export interface ServiceAgentPresence {
  id: number
  user_id: number
  uuid: string
  nickname: string
  avatar: string
  presence: 'online' | 'busy' | 'offline'
  current_serving: number
  max_concurrent: number
  auto_assign_enabled: boolean
}

interface ServiceConversationResponse {
  uuid: string
  chat_uuid: string
  status: 'waiting' | 'assigned' | 'serving' | 'pending' | 'closed'
  priority: number
  source: string
  customer: {
    id: number
    uuid: string
    username: string
    nickname: string
    avatar: string
    phone: string
    registered_at: string
    tags: string[]
    note: string
    vip_level: string
    balance: number
    order_count: number
    total_paid: number
  }
  assigned_agent?: ServiceAgentPresence
  last_message_id: string
  last_message_text: string
  last_message_type: number
  last_message_at?: string
  unread_count: number
  waiting_seconds: number
  ai_status: string
}

interface ConversationListResponse {
  list: ServiceConversationResponse[]
  total: number
  page: number
  limit: number
}

interface MessageResponse {
  msg_id: string
  sender_id: string
  sender_name: string
  operator_type?: string
  operator_id?: string
  type: number
  content?: { text?: string; system?: { action?: string } }
  status: number
  created_at: string
}

const queueToAPIStatus: Record<ConversationQueue, string> = {
  waiting: 'waiting',
  serving: 'serving',
  follow_up: 'pending',
  closed: 'closed'
}

function apiStatusToQueue(status: ServiceConversationResponse['status']): ConversationQueue {
  // 后端 assigned/serving 都属于前端“接待中”队列，backendStatus 另行保留以控制接受按钮。
  if (status === 'waiting') return 'waiting'
  if (status === 'pending') return 'follow_up'
  if (status === 'closed') return 'closed'
  return 'serving'
}

function formatConversationTime(value?: string) {
  if (!value) return '-'
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return '-'
  const now = new Date()
  if (date.toDateString() === now.toDateString()) {
    return date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
  }
  return date.toLocaleDateString('zh-CN', { month: '2-digit', day: '2-digit' })
}

function toConversation(item: ServiceConversationResponse): ServiceConversation {
  // API DTO 在此转换为工作台展示模型；金额、时间和队列语义不再散落到组件中处理。
  const nickname = item.customer.nickname || item.customer.username || '未命名客户'
  return {
    id: item.uuid,
    queue: apiStatusToQueue(item.status),
    backendStatus: item.status,
    priority: item.priority >= 2 ? 'urgent' : 'normal',
    customer: {
      id: item.customer.uuid,
      name: nickname,
      account: item.customer.username || item.customer.uuid,
      avatarText: nickname.slice(0, 1),
      phone: item.customer.phone || '-',
      region: '暂未获取',
      registeredAt: item.customer.registered_at || '-',
      lastActiveAt: item.last_message_at ? formatConversationTime(item.last_message_at) : '-',
      vipLevel: item.customer.vip_level || '普通用户',
      balance: `¥${Number(item.customer.balance || 0).toFixed(2)}`,
      orderCount: item.customer.order_count || 0,
      totalPaid: `¥${Number(item.customer.total_paid || 0).toFixed(2)}`,
      tags: item.customer.tags || [],
      note: item.customer.note || ''
    },
    subject: item.last_message_type === 1 ? '在线咨询' : '媒体消息咨询',
    lastMessage: item.last_message_text || '[新消息]',
    lastAt: formatConversationTime(item.last_message_at),
    unread: item.unread_count,
    waitingMinutes: Math.max(0, Math.ceil(item.waiting_seconds / 60)),
    agentId: item.assigned_agent?.id,
    agentName: item.assigned_agent?.nickname,
    channel: 'app'
  }
}

export interface ServiceQuickReply {
  uuid: string
  category: string
  title: string
  content: string
  shortcut: string
  keywords: string
  sort_order: number
  enabled: boolean
  created_at: string
  updated_at: string
}

export interface ServiceFollowUp {
  uuid: string
  content: string
  due_at: string
  status: 'pending' | 'done' | 'canceled'
  agent_id: number
  agent_name: string
  completed_at?: string
  created_at: string
}

export interface ServiceCustomerSummaryResponse {
  id: number
  uuid: string
  username: string
  nickname: string
  avatar: string
  phone: string
  registered_at: string
  tags: string[]
  note: string
  vip_level: string
  balance: number
  order_count: number
  total_paid: number
}

export interface ServiceCustomerDirectoryItem {
  customer: ServiceCustomerSummaryResponse
  conversation_count: number
  last_conversation_uuid: string
  last_conversation_at: string
  last_conversation_status: ServiceConversationResponse['status']
  pending_follow_up?: ServiceFollowUp
}

export interface ServiceCustomerDirectoryResult {
  list: ServiceCustomerDirectoryItem[]
  total: number
  page: number
  limit: number
}

export interface ServiceQuickReplyInput {
  category: string
  title: string
  content: string
  shortcut: string
  keywords: string
  sort_order: number
  enabled: boolean
}

let mockQuickReplyRows: ServiceQuickReply[] = [
  { uuid: 'mock-hello', category: '通用', title: '欢迎咨询', content: '您好，我是本次为您服务的客服，请问有什么可以帮您？', shortcut: '/hello', keywords: '欢迎,您好', sort_order: 100, enabled: true, created_at: '', updated_at: '' },
  { uuid: 'mock-info', category: '排查', title: '收集问题信息', content: '为了更快定位问题，请您提供设备型号、客户端版本和问题发生时间。', shortcut: '/info', keywords: '版本,设备,排查', sort_order: 90, enabled: true, created_at: '', updated_at: '' }
]

export async function fetchServiceQuickReplies(options: { keyword?: string; category?: string; includeDisabled?: boolean } = {}): Promise<ServiceQuickReply[]> {
  if (useMock) {
    const keyword = options.keyword?.trim().toLowerCase() || ''
    return structuredClone(mockQuickReplyRows.filter((item) => {
      if (!options.includeDisabled && !item.enabled) return false
      if (options.category && item.category !== options.category) return false
      return !keyword || [item.title, item.content, item.shortcut, item.keywords].some((value) => value.toLowerCase().includes(keyword))
    }))
  }
  return request<ServiceQuickReply[]>({
    url: '/service-admin/quick-replies', method: 'GET',
    query: { keyword: options.keyword, category: options.category, include_disabled: options.includeDisabled }
  })
}

export async function createServiceQuickReply(input: ServiceQuickReplyInput): Promise<ServiceQuickReply> {
  if (useMock) {
    const row: ServiceQuickReply = { ...input, uuid: crypto.randomUUID(), created_at: new Date().toISOString(), updated_at: new Date().toISOString() }
    mockQuickReplyRows = [row, ...mockQuickReplyRows]
    return structuredClone(row)
  }
  return request<ServiceQuickReply>({ url: '/service-admin/quick-replies', method: 'POST', body: input })
}

export async function updateServiceQuickReply(uuid: string, input: ServiceQuickReplyInput): Promise<ServiceQuickReply> {
  if (useMock) {
    const index = mockQuickReplyRows.findIndex((item) => item.uuid === uuid)
    const row = { ...mockQuickReplyRows[index], ...input, updated_at: new Date().toISOString() }
    mockQuickReplyRows.splice(index, 1, row)
    return structuredClone(row)
  }
  return request<ServiceQuickReply>({ url: `/service-admin/quick-replies/${uuid}`, method: 'PUT', body: input })
}

export async function deleteServiceQuickReply(uuid: string): Promise<void> {
  if (useMock) {
    mockQuickReplyRows = mockQuickReplyRows.filter((item) => item.uuid !== uuid)
    return
  }
  await request({ url: `/service-admin/quick-replies/${uuid}`, method: 'DELETE' })
}

export async function fetchServiceCustomers(keyword = '', page = 1, pageSize = 30): Promise<ServiceCustomerDirectoryResult> {
  if (useMock) {
    const rows: ServiceCustomerDirectoryItem[] = mockConversations.map((item) => ({
      customer: {
        id: Number(item.customer.id.replace(/\D/g, '')) || 1, uuid: item.customer.id,
        username: item.customer.account, nickname: item.customer.name, avatar: '', phone: item.customer.phone,
        registered_at: item.customer.registeredAt, tags: item.customer.tags, note: item.customer.note,
        vip_level: item.customer.vipLevel, balance: 0, order_count: item.customer.orderCount, total_paid: 0
      },
      conversation_count: 1, last_conversation_uuid: item.id, last_conversation_at: new Date().toISOString(),
      last_conversation_status: item.backendStatus || 'serving'
    }))
    return { list: rows, total: rows.length, page: 1, limit: pageSize }
  }
  return request<ServiceCustomerDirectoryResult>({
    url: '/service-admin/customers', method: 'GET', query: { keyword, page, page_size: pageSize }
  })
}

export async function updateServiceCustomerProfile(customerUuid: string, tags: string[], note: string): Promise<ServiceCustomerSummaryResponse> {
  if (useMock) {
    const conversation = mockConversations.find((item) => item.customer.id === customerUuid)
    if (conversation) {
      conversation.customer.tags = tags
      conversation.customer.note = note
    }
    return {
      id: 1, uuid: customerUuid, username: conversation?.customer.account || '', nickname: conversation?.customer.name || '',
      avatar: '', phone: conversation?.customer.phone || '', registered_at: conversation?.customer.registeredAt || '', tags, note,
      vip_level: conversation?.customer.vipLevel || '普通用户', balance: 0, order_count: 0, total_paid: 0
    }
  }
  return request<ServiceCustomerSummaryResponse>({
    url: `/service-admin/customers/${customerUuid}/profile`, method: 'PUT', body: { tags, note }
  })
}

export async function fetchServiceFollowUps(customerUuid?: string, status?: ServiceFollowUp['status']): Promise<ServiceFollowUp[]> {
  if (useMock) return []
  return request<ServiceFollowUp[]>({
    url: '/service-admin/follow-ups', method: 'GET', query: { customer_uuid: customerUuid, status }
  })
}

export async function createServiceFollowUp(customerUuid: string, input: { conversation_uuid?: string; content: string; due_at: string }): Promise<ServiceFollowUp> {
  if (useMock) return { uuid: crypto.randomUUID(), content: input.content, due_at: input.due_at, status: 'pending', agent_id: 1, agent_name: '官方客服', created_at: new Date().toISOString() }
  return request<ServiceFollowUp>({
    url: `/service-admin/customers/${customerUuid}/follow-ups`, method: 'POST', body: input
  })
}

export async function updateServiceFollowUp(uuid: string, input: { content?: string; due_at?: string; status?: ServiceFollowUp['status'] }): Promise<ServiceFollowUp> {
  if (useMock) return { uuid, content: input.content || '', due_at: input.due_at || new Date().toISOString(), status: input.status || 'pending', agent_id: 1, agent_name: '官方客服', created_at: new Date().toISOString() }
  return request<ServiceFollowUp>({ url: `/service-admin/follow-ups/${uuid}`, method: 'PATCH', body: input })
}

function mockAgent(id: number, nickname: string, currentServing: number): ServiceAgentPresence {
  return {
    id,
    user_id: id,
    uuid: `mock-agent-${id}`,
    nickname,
    avatar: '',
    presence: 'online',
    current_serving: currentServing,
    max_concurrent: 5,
    auto_assign_enabled: true
  }
}

export async function fetchServicePresence(): Promise<ServiceAgentPresence> {
  if (useMock) return mockAgent(1, '官方客服小助手', 2)
  return request<ServiceAgentPresence>({ url: '/service-admin/presence', method: 'GET' })
}

export async function updateServicePresence(presence: ServiceAgentPresence['presence']): Promise<ServiceAgentPresence> {
  if (useMock) return { ...mockAgent(1, '官方客服小助手', 2), presence }
  return request<ServiceAgentPresence>({
    url: '/service-admin/presence', method: 'PUT', body: { presence }
  })
}

export async function heartbeatServicePresence(): Promise<ServiceAgentPresence> {
  if (useMock) return mockAgent(1, '官方客服小助手', 2)
  return request<ServiceAgentPresence>({ url: '/service-admin/presence/heartbeat', method: 'POST' })
}

export async function fetchAvailableServiceAgents(): Promise<ServiceAgentPresence[]> {
  if (useMock) return [mockAgent(2, '客服小安', 2), mockAgent(3, '客服可可', 3)]
  return request<ServiceAgentPresence[]>({ url: '/service-admin/agents/available', method: 'GET' })
}

export async function fetchServiceConversations(queue: ConversationQueue, keyword = ''): Promise<ServiceConversation[]> {
  if (useMock) {
    const normalized = keyword.trim().toLowerCase()
    return structuredClone(mockConversations.filter((item) => {
      if (item.queue !== queue) return false
      if (!normalized) return true
      return [item.customer.name, item.customer.account, item.subject, item.lastMessage]
        .some((value) => value.toLowerCase().includes(normalized))
    }))
  }
  const result = await request<ConversationListResponse>({
    url: '/service-admin/conversations',
    method: 'GET',
    query: { status: queueToAPIStatus[queue], keyword, page_size: 100 }
  })
  // 服务端分页列表保留原顺序，页面按四个队列并行加载后再合并。
  return result.list.map(toConversation)
}

export async function fetchServiceConversationMessages(conversation: ServiceConversation): Promise<ServiceMessage[]> {
  if (useMock) return structuredClone(mockMessages[conversation.id] || [])
  const result = await request<MessageResponse[]>({
    url: `/service-admin/conversations/${conversation.id}/messages`, method: 'GET', query: { limit: 100 }
  })
  // 接口可能按倒序返回，工作台消息流统一转换为从旧到新的显示顺序。
  return [...result].sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime()).map((item) => {
    let sender: ServiceMessage['sender'] = item.sender_id === conversation.customer.id ? 'customer' : 'agent'
    if (item.operator_type === 'ai') sender = 'ai'
    if (item.type === 99) sender = 'system'
    return {
      id: item.msg_id,
      sender,
      content: item.content?.text || (item.type === 99 ? '系统消息' : '[暂不支持预览的消息]'),
      time: formatConversationTime(item.created_at),
      status: item.status === 0 ? 'sending' : 'sent'
    }
  })
}

export async function claimServiceConversation(uuid: string) {
  if (useMock) return
  return request({ url: `/service-admin/conversations/${uuid}/claim`, method: 'POST' })
}

export async function acceptServiceConversation(uuid: string) {
  if (useMock) return
  return request({ url: `/service-admin/conversations/${uuid}/accept`, method: 'POST' })
}

export async function closeServiceConversation(uuid: string, reason = '客服已解决') {
  if (useMock) return
  return request({ url: `/service-admin/conversations/${uuid}/close`, method: 'POST', body: { reason } })
}

export async function reopenServiceConversation(uuid: string) {
  if (useMock) return
  return request({ url: `/service-admin/conversations/${uuid}/reopen`, method: 'POST' })
}

export async function transferServiceConversation(uuid: string, agentId: number, reason: string) {
  if (useMock) return
  return request({
    url: `/service-admin/conversations/${uuid}/transfer`, method: 'POST', body: { agent_id: agentId, reason }
  })
}

export async function markServiceConversationRead(uuid: string) {
  if (useMock) return
  return request({ url: `/service-admin/conversations/${uuid}/read`, method: 'POST' })
}

export async function sendServiceConversationText(uuid: string, text: string): Promise<ServiceMessage> {
  if (useMock) {
    return {
      id: `m-agent-${Date.now()}`,
      sender: 'agent',
      content: text,
      time: new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' }),
      status: 'sent'
    }
  }
  const result = await request<MessageResponse>({
    url: `/service-admin/conversations/${uuid}/messages`,
    method: 'POST',
    // 客户端生成 msg_id 作为消息唯一标识，服务端回包后再用正式状态更新页面。
    body: { text, msg_id: crypto.randomUUID() }
  })
  return {
    id: result.msg_id,
    sender: 'agent',
    content: result.content?.text || text,
    time: formatConversationTime(result.created_at),
    status: result.status === 0 ? 'sending' : 'sent'
  }
}
