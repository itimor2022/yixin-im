import type {
  ServiceAdminDashboard,
  ServiceAdminInviteCode,
  ServiceAdminInvitee,
  ServiceAdminProfile,
  ServiceAdminWelcomeMessage
} from '@/types/service-admin'

let profile: ServiceAdminProfile = {
  nickname: '官方客服小助手',
  phone: '138****2026',
  role: 'official_service',
  inviteCode: 'KF2026VIP',
  status: 'enabled'
}

let welcomeMessage = '您好，欢迎来到壹信。我是您的专属官方客服，后续有任何问题都可以直接联系我。'

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
  return wait(invitees.map((item) => ({ ...item })))
}

export function mockGetWelcomeMessage(): Promise<ServiceAdminWelcomeMessage> {
  return wait({ message: welcomeMessage })
}

export function mockSaveWelcomeMessage(message: string) {
  welcomeMessage = message
  return wait({ success: true })
}

export function mockLogout() {
  return wait({ success: true })
}
