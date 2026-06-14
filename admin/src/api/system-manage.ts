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
  userPhone?: string
  userEmail?: string
  status?: string
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
  // 会员信息
  isMember: boolean
  badgeText: string
  badgeColor: string
}

/** 获取用户列表（兼容 useTable） */
export async function fetchGetUserList(params: UserTableSearchParams): Promise<UserTableList> {
  // 转换参数
  const searchParams: UserSearchParams = {
    page: params.current || 1,
    page_size: params.size || 20,
    keyword: params.userName || params.userPhone || params.userEmail,
    status: params.status,
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
    userGender: '-',
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
    isMember: !!item.is_member,
    badgeText: item.badge_text || '',
    badgeColor: item.badge_color || '',
    serviceInviteCode: item.service_invite_code || '',
    isMember: !!item.is_member,
    badgeText: item.badge_text || '',
    badgeColor: item.badge_color || '#3390EC'
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
  onlineCount: number
  isPublic: boolean
  status: number
  createTime: string
  members?: ChatMemberInfo[] // 私聊时的参与者
  // 群组权限
  canSendMessage: boolean
  canSendMedia: boolean
  canSendLinks: boolean
  canAddMembers: boolean
  canPinMessages: boolean
  memberProtection: boolean
  joinApproval: boolean
  // 待审核加入申请
  pendingRequest?: boolean
  pendingRequestCount?: number
}

/** 获取会话列表（兼容 useTable） */
export async function fetchGetChatList(params: ChatTableSearchParams): Promise<ChatTableList> {
  const searchParams: ChatSearchParams = {
    page: params.current || 1,
    page_size: params.size || 20,
    keyword: params.keyword,
    type: params.type
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
    onlineCount: item.online_count || 0,
    isPublic: item.is_public,
    status: item.status,
    createTime: item.created_at,
    members: item.members || [],
    canSendMessage: item.can_send_message ?? true,
    canSendMedia: item.can_send_media ?? true,
    canSendLinks: item.can_send_links ?? true,
    canAddMembers: item.can_add_members ?? false,
    canPinMessages: item.can_pin_messages ?? false,
    memberProtection: item.member_protection ?? false,
    joinApproval: item.join_approval ?? false,
    pendingRequest: item.pending_request,
    pendingRequestCount: item.pending_request_count
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
    keyword: params.keyword
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
    onlineCount: item.online_count || 0,
    isPublic: item.is_public,
    status: item.status,
    createTime: item.created_at,
    canSendMessage: item.can_send_message ?? true,
    canSendMedia: item.can_send_media ?? true,
    canSendLinks: item.can_send_links ?? true,
    canAddMembers: item.can_add_members ?? false,
    canPinMessages: item.can_pin_messages ?? false,
    memberProtection: item.member_protection ?? false,
    joinApproval: item.join_approval ?? false,
    pendingRequest: item.pending_request,
    pendingRequestCount: item.pending_request_count
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
    keyword: params.keyword
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
    onlineCount: item.online_count || 0,
    isPublic: item.is_public,
    status: item.status,
    createTime: item.created_at,
    canSendMessage: item.can_send_message ?? true,
    canSendMedia: item.can_send_media ?? true,
    canSendLinks: item.can_send_links ?? true,
    canAddMembers: item.can_add_members ?? false,
    canPinMessages: item.can_pin_messages ?? false,
    memberProtection: item.member_protection ?? false,
    joinApproval: item.join_approval ?? false,
    pendingRequest: item.pending_request,
    pendingRequestCount: item.pending_request_count
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

// ==================== 会员管理 ====================

export interface MembershipPayload {
  is_member: boolean
  badge_text: string
  badge_color: string
}

export async function setMembership(userId: number, data: MembershipPayload) {
  return request.put({
    url: `/admin/users/${userId}/membership`,
    data: data
  })
}


// ==================== 签到记录 ====================

export interface CheckinTableSearchParams {
  current?: number
  size?: number
  keyword?: string
  date?: string
}

export interface CheckinTableListItem {
  id: number
  userId: number
  uuid: string
  username: string
  nickname: string
  avatar: string
  checkinDate: string
  createdAt: string
}

export interface CheckinTableList {
  records: CheckinTableListItem[]
  current: number
  size: number
  total: number
}

export async function fetchGetCheckinList(
  params: CheckinTableSearchParams
): Promise<CheckinTableList> {
  const res = await request.get<any>({
    url: '/admin/checkins/list',
    params: {
      page: params.current || 1,
      page_size: params.size || 20,
      keyword: params.keyword,
      date: params.date
    }
  })
  const records: CheckinTableListItem[] = (res.list || []).map((item: any) => ({
    id: item.id,
    userId: item.user_id,
    uuid: item.uuid || '',
    username: item.username || '',
    nickname: item.nickname || '',
    avatar: item.avatar || '',
    checkinDate: item.checkin_date,
    createdAt: item.created_at
  }))
  return {
    records,
    current: res.page,
    size: res.page_size,
    total: res.total
  }
}

// ==================== 弹窗公告（启动公告） ====================

export interface PopupAnnouncement {
  id: number
  title: string
  content: string
  image_url: string
  link_url: string
  enabled: number
  created_at: string
  updated_at: string
}

export interface PopupAnnouncementPayload {
  title: string
  content: string
  image_url?: string
  link_url?: string
  enabled?: boolean
}

export async function fetchPopupAnnouncements(params?: { page?: number; page_size?: number }) {
  return request.get<{ list: PopupAnnouncement[]; total: number }>({
    url: '/admin/popup-announcements',
    params
  })
}

export async function createPopupAnnouncement(data: PopupAnnouncementPayload) {
  return request.post<PopupAnnouncement>({
    url: '/admin/popup-announcements',
    params: data
  })
}

export async function updatePopupAnnouncement(id: number, data: PopupAnnouncementPayload) {
  return request.put<PopupAnnouncement>({
    url: `/admin/popup-announcements/${id}`,
    params: data
  })
}

export async function deletePopupAnnouncement(id: number) {
  return request.del({
    url: `/admin/popup-announcements/${id}`
  })
}
