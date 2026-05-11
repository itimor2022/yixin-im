import {
  mockGetDashboard,
  mockGetInviteCode,
  mockGetInvitees,
  mockGetProfile,
  mockGetWelcomeMessage,
  mockLogin,
  mockLogout,
  mockSaveWelcomeMessage
} from '@/service/mock/service-admin'
import type {
  ServiceAdminDashboard,
  ServiceAdminInviteCode,
  ServiceAdminInvitee,
  ServiceAdminProfile,
  ServiceAdminWelcomeMessage
} from '@/types/service-admin'
import { request } from '@/utils/request'

const useMock = import.meta.env.VITE_USE_MOCK !== 'false'

export async function loginServiceAdmin(payload?: { username: string; password: string }) {
  if (useMock) return mockLogin()

  return request<{ token: string }>({
    url: '/service-admin/auth/login',
    method: 'POST',
    body: {
      username: payload?.username || '',
      password: payload?.password || '',
      device_id: 'service-admin-web',
      device_type: 'web',
      device_name: 'service-admin-web'
    }
  })
}

export async function fetchServiceAdminProfile(): Promise<ServiceAdminProfile> {
  if (useMock) return mockGetProfile()

  return request<ServiceAdminProfile>({
    url: '/service-admin/profile',
    method: 'GET'
  })
}

export async function fetchServiceAdminDashboard(): Promise<ServiceAdminDashboard> {
  if (useMock) return mockGetDashboard()

  return request<ServiceAdminDashboard>({
    url: '/service-admin/dashboard',
    method: 'GET'
  })
}

export async function fetchServiceAdminInviteCode(): Promise<ServiceAdminInviteCode> {
  if (useMock) return mockGetInviteCode()

  return request<ServiceAdminInviteCode>({
    url: '/service-admin/invite-code',
    method: 'GET'
  })
}

export async function fetchServiceAdminInvitees(): Promise<ServiceAdminInvitee[]> {
  if (useMock) return mockGetInvitees()

  return request<ServiceAdminInvitee[]>({
    url: '/service-admin/invitees',
    method: 'GET'
  })
}

export async function fetchServiceAdminWelcomeMessage(): Promise<ServiceAdminWelcomeMessage> {
  if (useMock) return mockGetWelcomeMessage()

  return request<ServiceAdminWelcomeMessage>({
    url: '/service-admin/welcome-message',
    method: 'GET'
  })
}

export async function saveServiceAdminWelcomeMessage(message: string) {
  if (useMock) return mockSaveWelcomeMessage(message)

  return request<{ success: boolean; message: string; length: number }>({
    url: '/service-admin/welcome-message',
    method: 'PATCH',
    body: { message }
  })
}

export async function updateServiceAdminPassword(payload: { oldPassword: string; newPassword: string }) {
  return request<{ success: boolean }>({
    url: '/service-admin/password',
    method: 'PUT',
    body: {
      old_password: payload.oldPassword,
      new_password: payload.newPassword
    }
  })
}

export async function sendServiceAdminPhoneBindCode(phone: string) {
  return request<{ message: string; expires_in: number }>({
    url: '/service-admin/phone/send-bind-code',
    method: 'POST',
    body: { phone }
  })
}

export async function bindServiceAdminPhone(payload: { phone: string; code: string }) {
  return request<{ phone: string; success: boolean }>({
    url: '/service-admin/phone/bind',
    method: 'POST',
    body: payload
  })
}

export async function logoutServiceAdmin() {
  if (useMock) return mockLogout()

  return request<{ success: boolean }>({
    url: '/service-admin/auth/logout',
    method: 'POST'
  })
}
