import { defineStore } from 'pinia'
import { fetchServiceAdminProfile, loginServiceAdmin, logoutServiceAdmin } from '@/service/api/service-admin'
import type { ServiceAdminProfile } from '@/types/service-admin'
import { clearServiceAdminToken, getServiceAdminToken, setServiceAdminToken } from '@/utils/auth'

const defaultProfile: ServiceAdminProfile = {
  nickname: '官方客服小助手',
  phone: '',
  role: 'official_service',
  inviteCode: 'KF2026',
  status: 'enabled'
}

export const useSessionStore = defineStore('serviceAdminSession', {
  state: () => ({
    // 此处只用于启动前的初始占位，main.ts 会在挂载路由前通过 restore 向后端校验。
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
        // Token 先落盘，后续 loadProfile 的统一请求拦截器才能携带认证信息。
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
        // 以 /profile 成功作为会话有效依据；本地 Token 过期时统一回到匿名状态。
        await this.loadProfile()
      } catch {
        this.resetSession()
      }
    },
    async logout() {
      try {
        await logoutServiceAdmin()
      } finally {
        // 服务端登出失败也必须清本地状态，避免用户继续停留在受保护页面。
        this.resetSession()
      }
    }
  }
})
