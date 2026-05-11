import { defineStore } from 'pinia'
import { fetchServiceAdminProfile, loginServiceAdmin, logoutServiceAdmin } from '@/service/api/service-admin'
import type { ServiceAdminProfile } from '@/types/service-admin'
import { clearServiceAdminToken, getServiceAdminToken, setServiceAdminToken } from '@/utils/auth'

const defaultProfile: ServiceAdminProfile = {
  nickname: '官方客服小助手',
  phone: '',
  role: 'official_service',
  inviteCode: 'KF2026VIP',
  status: 'enabled'
}

export const useSessionStore = defineStore('serviceAdminSession', {
  state: () => ({
    isLoggedIn: Boolean(getServiceAdminToken()),
    profile: defaultProfile,
    loading: false
  }),
  actions: {
    resetSession() {
      clearServiceAdminToken()
      this.isLoggedIn = false
      this.profile = defaultProfile
    },
    async login(payload?: { username: string; password: string }) {
      this.loading = true
      try {
        const result = await loginServiceAdmin(payload)
        if (result?.token) setServiceAdminToken(result.token)
        this.isLoggedIn = true
        await this.loadProfile()
      } catch (error) {
        this.resetSession()
        throw error
      } finally {
        this.loading = false
      }
    },
    async loadProfile() {
      this.profile = await fetchServiceAdminProfile()
      this.isLoggedIn = true
    },
    async refreshProfile() {
      await this.loadProfile()
    },
    async restore() {
      if (!getServiceAdminToken()) return
      try {
        await this.loadProfile()
      } catch {
        this.resetSession()
      }
    },
    async logout() {
      try {
        await logoutServiceAdmin()
      } finally {
        this.resetSession()
      }
    }
  }
})
