export type ConversationQueue = 'waiting' | 'serving' | 'follow_up' | 'closed'

export type ConversationPriority = 'normal' | 'urgent'

export interface ServiceCustomer {
  id: string
  name: string
  account: string
  avatarText: string
  phone: string
  region: string
  registeredAt: string
  lastActiveAt: string
  vipLevel: string
  balance: string
  orderCount: number
  totalPaid: string
  tags: string[]
  note: string
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

export interface ServiceConversation {
  id: string
  queue: ConversationQueue
  backendStatus?: 'waiting' | 'assigned' | 'serving' | 'pending' | 'closed'
  priority: ConversationPriority
  customer: ServiceCustomer
  subject: string
  lastMessage: string
  lastAt: string
  unread: number
  waitingMinutes: number
  agentId?: number
  agentName?: string
  channel: 'app' | 'web'
}

export type MessageSender = 'customer' | 'agent' | 'system' | 'ai'

export interface ServiceMessage {
  id: string
  sender: MessageSender
  content: string
  time: string
  status?: 'sending' | 'sent' | 'failed'
}
