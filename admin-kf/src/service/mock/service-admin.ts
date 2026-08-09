import type {
  ServiceAdminDashboard,
  ServiceAdminInviteCode,
  ServiceAdminInvitee,
  ServiceAdminProfile,
  ServiceAdminWelcomeMessage,
  ServiceAdminWelcomeMessageSaveResult
} from '@/types/service-admin'

// 模块级变量模拟服务端持久状态，使保存后再次读取能看到同一轮会话内的变化。
let profile: ServiceAdminProfile = {
  nickname: '官方客服小助手',
  phone: '138****2026',
  role: 'official_service',
  inviteCode: 'KF2026',
  status: 'enabled'
}

let welcomeMessage = '您好，欢迎来到通用IM。我是您的专属官方客服，后续有任何问题都可以直接联系我。'

const invitees: ServiceAdminInvitee[] = [
  { id: 1, name: '小夏', uuid: '7f0f-32aa-91d1', registeredAt: '2026-04-12 11:08', active: true },
  { id: 2, name: '阿木', uuid: '3ac2-12dd-77ff', registeredAt: '2026-04-12 15:42', active: true },
  { id: 3, name: '晚风', uuid: '9bc1-89ke-11aa', registeredAt: '2026-04-13 09:15', active: false }
]

function wait<T>(data: T, delay = 120): Promise<T> {
  return new Promise((resolve) => setTimeout(() => resolve(data), delay))
}

export function mockLogin() {
  return wait({ token: 'service-admin-demo-token' })
}

export function mockGetProfile() {
  // 返回浅拷贝，避免表单直接修改 Mock 数据源的顶层字段。
  return wait({ ...profile })
}

export function mockGetDashboard(): Promise<ServiceAdminDashboard> {
  return wait({
    inviteCode: profile.inviteCode,
    inviteeCount: 1284,
    inviteeToday: 36,
    serviceStatusText: profile.status === 'enabled' ? '启用' : '停用'
  })
}

export function mockGetInviteCode(): Promise<ServiceAdminInviteCode> {
  return wait({
    code: profile.inviteCode,
    updatedAt: '2026-04-13 10:18',
    statusText: '可用',
    registerUrl: `https://example.com/register?code=${profile.inviteCode}`,
    usedCount: 1284,
    weeklyConversion: 96
  })
}

export function mockGetInvitees() {
  // 列表逐项复制，调用方排序或更新行对象时不会污染共享夹具。
  return wait(invitees.map((item) => ({ ...item })))
}

export function mockGetWelcomeMessage(): Promise<ServiceAdminWelcomeMessage> {
  return wait({ message: welcomeMessage })
}

export function mockSaveWelcomeMessage(message: string): Promise<ServiceAdminWelcomeMessageSaveResult> {
  welcomeMessage = message
  return wait({ success: true, message: welcomeMessage, length: welcomeMessage.length })
}

export function mockLogout() {
  return wait({ success: true })
}
