/**
 * 认证 API
 *
 * 管理员登录、获取用户信息等
 */
import { adminLogin, getAdminMe, AdminLoginParams, AdminInfo } from './admin'

/** 登录参数 */
export interface LoginParams {
  username: string
  password: string
}

/** 登录响应 */
export interface LoginResponse {
  token: string
  admin: AdminInfo
}

/** 用户信息 */
export interface UserInfo {
  userId: number
  userName: string
  nickName: string
  email: string
  avatar: string
  roles: string[]
  buttons: string[]
}

/**
 * 登录
 * @param params 登录参数
 * @returns 登录响应
 */
export function fetchLogin(params: LoginParams) {
  return adminLogin(params as AdminLoginParams)
}

/**
 * 获取用户信息
 * @returns 用户信息
 */
export async function fetchGetUserInfo(): Promise<UserInfo> {
  const admin = await getAdminMe()

  // 转换角色为内部格式
  const getRoleCode = (role: string): string => {
    switch (role) {
      case 'super_admin':
        return 'R_SUPER'
      case 'admin':
      case 'operator':
        return 'R_ADMIN'
      case 'demo_admin':
        return 'R_DEMO'
      default:
        // 未知角色默认降级为只读，避免前端误放开写操作
        return 'R_DEMO'
    }
  }

  return {
    userId: admin.id,
    userName: admin.username,
    nickName: admin.nickname,
    email: admin.email,
    avatar: admin.avatar,
    roles: [getRoleCode(admin.role)],
    buttons: [] // 管理后台暂不使用按钮权限
  }
}
