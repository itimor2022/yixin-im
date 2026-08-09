/**
 * 系统管理 API
 *
 * 用户管理、会话管理等
 */
import {
  getUserList,
  updateUser,
  updateUserStatus,
  kickUser,
  banUser,
  unbanUser,
  getUserStats,
  getChatList,
  getGroupList,
  getChannelList,
  updateChatStatus,
  deleteChat,
  UserSearchParams,
  ChatSearchParams
} from './admin'
import request from '@/utils/http'

// ==================== 用户管理 ====================

/** 搜索参数（兼容 useTable） */
export interface UserTableSearchParams {
  current?: number
  size?: number
  userName?: string
  searchMode?: 'exact' | 'fuzzy'
  userPhone?: string
  userEmail?: string
  status?: string
  gender?: 'male' | 'female' | 'unknown' | ''
  registerSource?: 'manual' | 'quick' | ''
  credentialsStatus?: 'initialized' | 'pending' | ''
  onlineOnly?: boolean
}

/** 用户列表响应（兼容 useTable） */
export interface UserTableList {
  records: UserTableListItem[]
  current: number
  size: number
  total: number
}

/** 用户列表项（兼容原有组件） */
export interface UserTableListItem {
  id: number
  uuid: string
  userName: string // 显示名称（昵称优先）
  username: string // 真实用户名
  nickname: string // 昵称
  phone: string // 手机号
  bio: string // 个人简介
  userPhone: string
  userEmail: string
  avatar: string
  userGender: string
  registerSource: 'manual' | 'quick'
  credentialsInitialized: boolean
  status: string
  isOnline: boolean
  lastSeen: string
  deviceType: string
  deviceName: string
  deviceIp: string
  pushChannel: string
  pushTokenBound: boolean
  pushTokenLength: number
  createTime: string
  banReason: string // 封禁原因
  bannedAt: string // 封禁时间
  serviceUserId?: number
  serviceUsername?: string
  serviceNickname?: string
  serviceInviteCode?: string
}

/** 获取用户列表（兼容 useTable） */
export async function fetchGetUserList(params: UserTableSearchParams): Promise<UserTableList> {
  // 在这里集中适配 useTable 的驼峰分页字段与后端 snake_case 协议。
  const searchParams: UserSearchParams = {
    page: params.current || 1,
    page_size: params.size || 20,
    keyword: params.userName || params.userPhone || params.userEmail,
    search_mode: params.searchMode || 'exact',
    status: params.status,
    gender: params.gender || undefined,
    register_source: params.registerSource || undefined,
    credentials_status: params.credentialsStatus || undefined,
    online_only: params.onlineOnly
  }

  const response = await getUserList(searchParams)

  // 转换响应格式
  const records: UserTableListItem[] = response.list.map((item: any) => ({
    id: item.id,
    uuid: item.uuid,
    userName: item.nickname || item.username, // 显示用名称
    username: item.username, // 真实用户名
    nickname: item.nickname || '', // 昵称
    phone: item.phone || '', // 手机号
    bio: item.bio || '', // 个人简介
    userPhone: item.phone || '-',
    userEmail: '-', // 后端暂未返回
    avatar: item.avatar || '',
    userGender:
      item.gender === 'male' || item.gender === 'female' ? item.gender : 'unknown',
    registerSource: item.register_source === 'quick' ? 'quick' : 'manual',
    credentialsInitialized: item.credentials_initialized !== false,
    status: String(item.status),
    isOnline: item.is_online,
    lastSeen: item.last_seen || '-',
    deviceType: item.device_type || '-',
    deviceName: item.device_name || '-',
    deviceIp: item.device_ip || '-',
    pushChannel: item.push_channel || '-',
    pushTokenBound: !!item.push_token_bound,
    pushTokenLength: Number(item.push_token_length || 0),
    createTime: item.created_at,
    banReason: item.ban_reason || '',
    bannedAt: item.banned_at || '',
    serviceUserId: item.service_user_id,
    serviceUsername: item.service_username || '',
    serviceNickname: item.service_nickname || '',
    serviceInviteCode: item.service_invite_code || ''
  }))

  return {
    records,
    current: response.page,
    size: response.page_size,
    total: response.total
  }
}

/** 更新用户 */
export { updateUser, updateUserStatus, kickUser, banUser, unbanUser, getUserStats }

// ==================== 会话管理 ====================

/** 会话搜索参数（兼容 useTable） */
export interface ChatTableSearchParams {
  current?: number
  size?: number
  keyword?: string
  type?: number
  status?: number
}

/** 会话列表响应（兼容 useTable） */
export interface ChatTableList {
  records: ChatTableListItem[]
  current: number
  size: number
  total: number
}

/** 私聊成员信息 */
export interface ChatMemberInfo {
  user_id: number
  uuid: string
  nickname: string
  avatar: string
}

/** 会话列表项 */
export interface ChatTableListItem {
  id: number
  uuid: string
  type: number
  typeName: string
  name: string
  avatar: string
  description: string
  ownerId: number
  ownerName: string
  ownerAvatar: string
  memberCount: number
  isPublic: boolean
  status: number
  createTime: string
  members?: ChatMemberInfo[] // 私聊时的参与者
}

/** 获取会话列表（兼容 useTable） */
export async function fetchGetChatList(params: ChatTableSearchParams): Promise<ChatTableList> {
  // 保持页面层只依赖 useTable 数据结构，后端字段映射统一收敛在 API 适配层。
  const searchParams: ChatSearchParams = {
    page: params.current || 1,
    page_size: params.size || 20,
    keyword: params.keyword,
    type: params.type,
    status: params.status
  }

  const response = await getChatList(searchParams)

  const typeNames = ['', '私聊', '群聊', '频道']
  const records: ChatTableListItem[] = response.list.map((item: any) => ({
    id: item.id,
    uuid: item.uuid,
    type: item.type,
    typeName: typeNames[item.type] || '未知',
    name: item.name,
    avatar: item.avatar,
    description: item.description,
    ownerId: item.owner_id,
    ownerName: item.owner_name || '',
    ownerAvatar: item.owner_avatar || '',
    memberCount: item.member_count,
    isPublic: item.is_public,
    status: item.status,
    createTime: item.created_at,
    members: item.members || []
  }))

  return {
    records,
    current: response.page,
    size: response.page_size,
    total: response.total
  }
}

/** 获取群组列表 */
export async function fetchGetGroupList(params: ChatTableSearchParams): Promise<ChatTableList> {
  const searchParams: ChatSearchParams = {
    page: params.current || 1,
    page_size: params.size || 20,
    keyword: params.keyword,
    status: params.status
  }

  const response = await getGroupList(searchParams)

  const records: ChatTableListItem[] = response.list.map((item: any) => ({
    id: item.id,
    uuid: item.uuid,
    type: 2,
    typeName: '群聊',
    name: item.name,
    avatar: item.avatar,
    description: item.description,
    ownerId: item.owner_id,
    ownerName: item.owner_name || '',
    ownerAvatar: item.owner_avatar || '',
    memberCount: item.member_count,
    isPublic: item.is_public,
    status: item.status,
    createTime: item.created_at
  }))

  return {
    records,
    current: response.page,
    size: response.page_size,
    total: response.total
  }
}

/** 获取频道列表 */
export async function fetchGetChannelList(params: ChatTableSearchParams): Promise<ChatTableList> {
  const searchParams: ChatSearchParams = {
    page: params.current || 1,
    page_size: params.size || 20,
    keyword: params.keyword,
    status: params.status
  }

  const response = await getChannelList(searchParams)

  const records: ChatTableListItem[] = response.list.map((item: any) => ({
    id: item.id,
    uuid: item.uuid,
    type: 3,
    typeName: '频道',
    name: item.name,
    avatar: item.avatar,
    description: item.description,
    ownerId: item.owner_id,
    ownerName: item.owner_name || '',
    ownerAvatar: item.owner_avatar || '',
    memberCount: item.member_count,
    isPublic: item.is_public,
    status: item.status,
    createTime: item.created_at
  }))

  return {
    records,
    current: response.page,
    size: response.page_size,
    total: response.total
  }
}

/** 更新会话状态 */
export { updateChatStatus, deleteChat }

/** 封禁/解封会话 */
export { banChat, unbanChat } from './admin'

// ==================== 角色管理（保留空实现） ====================

export interface RoleSearchParams {
  current?: number
  size?: number
}

export interface RoleList {
  records: any[]
  current: number
  size: number
  total: number
}

export async function fetchGetRoleList(params: RoleSearchParams): Promise<RoleList> {
  void params
  return {
    records: [],
    current: 1,
    size: 20,
    total: 0
  }
}

// ==================== 菜单列表（保留空实现） ====================

export async function fetchGetMenuList() {
  return []
}

// ==================== 发现管理 ====================

export interface DiscoverItem {
  id: number
  title: string
  icon_url: string
  url: string
  sort: number
  enabled: boolean
  created_at: string
  updated_at: string
}

export interface DiscoverItemPayload {
  title: string
  icon_url?: string
  url: string
  sort?: number
  enabled?: boolean
}

export async function getDiscoverItems() {
  return request.get<DiscoverItem[]>({
    url: '/admin/settings/discover-items'
  })
}

export async function createDiscoverItem(data: DiscoverItemPayload) {
  return request.post<DiscoverItem>({
    url: '/admin/settings/discover-items',
    params: data
  })
}

export async function updateDiscoverItem(id: number, data: DiscoverItemPayload) {
  return request.put<DiscoverItem>({
    url: `/admin/settings/discover-items/${id}`,
    params: data
  })
}

export async function deleteDiscoverItem(id: number) {
  return request.del({
    url: `/admin/settings/discover-items/${id}`
  })
}

export interface DiscoverBanner {
  id: number
  title: string
  image_url: string
  url: string
  sort: number
  enabled: boolean
  created_at: string
  updated_at: string
}

export interface DiscoverBannerPayload {
  title: string
  image_url: string
  url?: string
  sort?: number
  enabled?: boolean
}

export async function getDiscoverBanners() {
  return request.get<DiscoverBanner[]>({
    url: '/admin/settings/discover-banners'
  })
}

export async function createDiscoverBanner(data: DiscoverBannerPayload) {
  return request.post<DiscoverBanner>({
    url: '/admin/settings/discover-banners',
    params: data
  })
}

export async function updateDiscoverBanner(id: number, data: DiscoverBannerPayload) {
  return request.put<DiscoverBanner>({
    url: `/admin/settings/discover-banners/${id}`,
    params: data
  })
}

export async function deleteDiscoverBanner(id: number) {
  return request.del({
    url: `/admin/settings/discover-banners/${id}`
  })
}
