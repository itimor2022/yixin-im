export interface ServiceAdminProfile {
  nickname: string
  phone: string
  role: string
  inviteCode: string
  status: 'enabled' | 'disabled'
  username?: string
  avatar?: string
  userId?: number
  userUuid?: string
}

export interface ServiceAdminTrendItem {
  date: string
  count: number
}

export interface ServiceAdminRecentInvitee {
  name: string
  uuid: string
  registeredAt: string
}

export interface ServiceAdminDashboard {
  inviteCode: string
  inviteeCount: number
  inviteeToday: number
  serviceStatusText: string
  weeklyConversion?: number
  usedCount?: number
  registerUrl?: string
  recentTrend?: ServiceAdminTrendItem[]
  recentInvitees?: ServiceAdminRecentInvitee[]
}

export interface ServiceAdminInviteCode {
  code: string
  updatedAt: string
  statusText: string
  registerUrl: string
  usedCount: number
  weeklyConversion: number
}

export interface ServiceAdminInvitee {
  id: number
  name: string
  uuid: string
  registeredAt: string
  active: boolean
}

export interface ServiceAdminWelcomeMessage {
  message: string
}
