import request from '@/utils/http'

// 本文件类型按后端 JSON 原字段建模（snake_case），页面层不要擅自改成 camelCase，
// 否则表单回填、请求透传以及后端新增字段的兼容逻辑会产生隐式映射。
export interface AdminLoginParams {
  username: string
  password: string
}
export interface AdminLoginResponse {
  token: string
  admin: AdminInfo
}
export interface AdminInfo {
  id: number
  username: string
  nickname: string
  email: string
  avatar: string
  role: 'super_admin' | 'admin' | 'operator' | 'demo_admin'
  status: number
  last_login_at: string
  last_login_ip: string
  created_at: string
}

export interface AdminCreateParams {
  username: string
  password: string
  nickname: string
  email?: string
  role: 'admin' | 'operator' | 'demo_admin'
}

export type AdminRoleKey = 'super_admin' | 'admin' | 'operator' | 'demo_admin'

export interface RolePermissionConfig {
  enabled: boolean
  roles: Partial<Record<AdminRoleKey, string[]>>
}
export interface UserListItem {
  id: number
  uuid: string
  username: string
  nickname: string
  gender: 'male' | 'female' | 'unknown'
  register_source: 'manual' | 'quick'
  credentials_initialized: boolean
  phone: string | null
  avatar: string | null
  bio: string | null
  status: number
  is_online: boolean
  last_seen: string | null
  created_at: string
  device_type: string | null
  device_name: string | null
  device_ip: string | null
  service_user_id?: number | null
  service_username?: string | null
  service_nickname?: string | null
  service_invite_code?: string | null
  invite_code?: string | null
  bind_id?: number | null
  bind_username?: string | null
  bind_nickname?: string | null
  recommender_id?: number | null
  recommender_username?: string | null
  recommender_nickname?: string | null
  recommender_invite_code?: string | null
  subordinates_count?: number
}
export interface UserListResponse {
  list: UserListItem[]
  total: number
  page: number
  page_size: number
}

export interface UserDiagnosticCheck {
  level: 'ok' | 'info' | 'warning' | 'error'
  title: string
  detail: string
}

export interface UserDiagnosticDevice {
  id: number
  device_id: string
  device_type: string
  device_name: string
  device_ip: string
  push_channel: string
  push_token_bound: boolean
  push_token_length: number
  last_active: string
  active_recently: boolean
  created_at: string
  last_push?: UserDiagnosticPushLog
}

export interface UserDiagnosticPushLog {
  id: number
  device_id: number
  device_key: string
  channel: string
  success: boolean
  error: string
  title: string
  body: string
  occurred_at: string
}

export interface UserDiagnosticSession {
  id: number
  device_id: string
  device_type: string
  device_name: string
  ip: string
  location: string
  last_active: string
  created_at: string
}

export interface UserDiagnosticRecentChat {
  chat_id: number
  target_id: number
  last_msg_seq: number
  last_msg_text: string
  last_msg_type: number
  last_msg_sender: string
  last_msg_time: string
  unread_count: number
  is_muted: boolean
  is_pinned: boolean
}

export interface UserDiagnosticResponse {
  user: UserListItem & {
    ban_reason?: string
    banned_at?: string | null
    updated_at?: string
  }
  summary: {
    device_count: number
    active_device_count: number
    push_bound_count: number
    session_count: number
    contact_count: number
    chat_count: number
    unread_total: number
    push_setting_found: boolean
    push_show_preview: boolean
    diagnosed_at: string
  }
  devices: UserDiagnosticDevice[]
  sessions: UserDiagnosticSession[]
  recent_chats: UserDiagnosticRecentChat[]
  push_logs: UserDiagnosticPushLog[]
  checks: UserDiagnosticCheck[]
}

export interface UserSearchParams {
  page?: number
  page_size?: number
  keyword?: string
  search_mode?: 'exact' | 'fuzzy'
  status?: string
  gender?: 'male' | 'female' | 'unknown'
  register_source?: 'manual' | 'quick'
  credentials_status?: 'initialized' | 'pending'
  online_only?: boolean
  invite_code?: string
  recommender_id?: number
}
export interface ClientEndpointConfig {
  id: string
  url: string
  priority: number
  region?: string
  health_path?: string
}

export interface ClientBootstrapConfig {
  enabled: boolean
  version: number
  ttl_seconds: number
  api_endpoints: ClientEndpointConfig[]
  ws_endpoints: ClientEndpointConfig[]
  media_base_urls: string[]
  strategy: {
    connect_timeout_ms: number
    health_timeout_ms: number
    fail_threshold: number
    cooldown_seconds: number
    prefer_last_success: boolean
  }
}

export interface UserStats {
  total_users: number
  active_users: number
  new_users_today: number
  online_users: number
}
export interface UserStatsDetail {
  daily_new_users: { date: string; count: number }[]
}
export interface ChatListItem {
  id: number
  uuid: string
  type: number // 1: 私聊, 2: 群聊, 3: 频道
  name: string
  avatar: string
  description: string
  owner_id: number
  owner_name?: string
  owner_avatar?: string
  member_count: number
  max_members?: number
  is_public: boolean
  username?: string
  status: number
  ban_reason?: string
  banned_at?: string
  can_send_message?: boolean
  can_send_media?: boolean
  can_send_links?: boolean
  can_add_members?: boolean
  can_pin_messages?: boolean
  member_protection?: boolean
  join_approval?: boolean
  created_at: string
}
export interface ChatListResponse {
  list: ChatListItem[]
  total: number
  page: number
  page_size: number
}
export interface ChatSearchParams {
  page?: number
  page_size?: number
  keyword?: string
  type?: number
  status?: number
}
export interface ChatMemberSearchParams {
  page?: number
  page_size?: number
  keyword?: string
}
export interface ChatDetailResponse {
  chat: ChatListItem
  owner: UserListItem | null
  members: ChatMemberItem[]
}
export interface ChatMemberItem {
  id: number
  chat_id: number
  user_id: number
  user_uuid: string
  username: string
  nickname: string
  nickname_in_chat?: string
  avatar: string
  role: number // 1: member, 2: admin, 3: owner
  is_muted?: boolean
  mute_end_time?: string | null
  joined_at: string
  last_online_at: string | null
}
export interface ChatJoinRequestItem {
  id: number
  chat_id: number
  user_id: number
  user_uuid: string
  username: string
  nickname: string
  avatar: string
  message: string
  status: number
  status_text: string
  reviewed_at?: string | null
  created_at: string
  updated_at: string
}
export interface ChatMembersResponse {
  list: ChatMemberItem[]
  total: number
  page: number
  page_size: number
}
export interface ChatJoinRequestsResponse {
  list: ChatJoinRequestItem[]
  total: number
  page: number
  page_size: number
}
export interface ChatStatsResponse {
  group_count: number
  channel_count: number
  banned_count: number
  group_banned_count: number
  channel_banned_count: number
  today_group_count: number
  today_channel_count: number
  hot_groups: ChatListItem[]
  hot_channels: ChatListItem[]
}

export interface UpdateChatInfoParams {
  name?: string
  avatar?: string
  description?: string
  username?: string
  max_members?: number
  is_public?: boolean
  can_send_message?: boolean
  can_send_media?: boolean
  can_send_links?: boolean
  can_add_members?: boolean
  can_pin_messages?: boolean
  member_protection?: boolean
  join_approval?: boolean
}
export interface AddChatMembersParams {
  user_ids?: number[]
  user_uuids?: string[]
  usernames?: string[]
  identifiers?: string[]
}

export type CloudStorageProvider = 'local' | 'aliyun' | 'qiniu' | 's3'

// 后端返回完整 provider 结构用于切换供应商时保留表单值；真正生效的配置由 provider 指定。
export interface CloudStorageConfig {
  provider: CloudStorageProvider
  local: {
    base_url: string
  }
  aliyun: {
    endpoint: string
    bucket: string
    access_key_id: string
    access_key_secret: string
    public_base_url: string
    use_https: boolean
  }
  qiniu: {
    upload_url: string
    bucket: string
    access_key: string
    secret_key: string
    public_base_url: string
    use_https: boolean
  }
  s3: {
    region: string
    bucket: string
    access_key_id: string
    secret_access_key: string
    public_base_url: string
    endpoint: string
    use_path_style: boolean
  }
}

export interface DashboardStats {
  total_users: number
  online_users: number
  new_users_today: number
  total_groups: number
  total_channels: number
  total_messages: number
  messages_today: number
}
export interface RuntimeStatus {
  server_time: string
  started_at: string
  uptime_seconds: number
  uptime_text: string
  go_version: string
  os: string
  arch: string
  goroutines: number
  cpu_num: number
  memory_alloc_mb: number
  memory_sys_mb: number
  heap_inuse_mb: number
  gc_count: number
  mysql_status: 'ok' | 'error'
  mysql_error: string
  mongo_status: 'ok' | 'error'
  mongo_error: string
  redis_status: 'ok' | 'error'
  redis_error: string
  queue_message_send: number
  queue_message_sync: number
  queue_push_notify: number
  queue_delayed: number
  queue_dead: number
}

export type HealthStatus = 'ok' | 'warning' | 'error'

export interface StorageStatusResponse {
  provider: CloudStorageProvider | string
  source: string
  valid: boolean
  public_base_url: string
  bucket: string
  endpoint: string
  local_base_url: string
  masked: boolean
  // 阶段指标是服务进程启动后的内存累计值，只用于定位上传链路瓶颈，不是历史审计记录。
  upload_stages?: {
    started_at: string
    stages: Array<{
      stage: string
      count: number
      failed: number
      average_ms: number
      max_ms: number
      last_ms: number
      last_success: boolean
      last_recorded_at: string
    }>
  }
  aliyun?: {
    endpoint: string
    bucket: string
    public_base_url: string
    use_https: boolean
    access_key_id_set: boolean
    access_key_secret_set: boolean
  }
  qiniu?: {
    upload_url: string
    bucket: string
    public_base_url: string
    use_https: boolean
    access_key_set: boolean
    secret_key_set: boolean
  }
  s3?: {
    region: string
    bucket: string
    public_base_url: string
    endpoint: string
    use_path_style: boolean
    access_key_id_set: boolean
    secret_access_key_set: boolean
    credentials_source: string
  }
  access_key_configured?: boolean
  access_secret_configured?: boolean
  secret_key_configured?: boolean
  status?: HealthStatus
  error?: string
}

export interface StorageTestUploadResponse {
  ok: boolean
  provider: CloudStorageProvider | string
  source: string
  url: string
  http_status: number
  duration_ms: number
  cleaned: boolean
  error?: string
}

export interface HealthComponent {
  name: string
  status: HealthStatus
  error?: string
  [key: string]: unknown
}

export interface SystemHealthDetailResponse {
  status: HealthStatus
  server_time: string
  started_at: string
  uptime_text: string
  runtime: {
    go_version: string
    os: string
    arch: string
    goroutines: number
    cpu_num: number
    memory_alloc_mb: number
    memory_sys_mb: number
    heap_inuse_mb: number
    gc_count: number
  }
  components: HealthComponent[]
  summary: {
    mysql_status: HealthStatus
    mongo_status: HealthStatus
    redis_status: HealthStatus
    storage: HealthComponent
    upload: HealthComponent
    websocket: HealthComponent
    push: HealthComponent
    queue: HealthComponent
    check_window: string
  }
}

export interface HealthMetricSnapshotItem {
  id: number
  status: HealthStatus
  mysql_status: HealthStatus
  mongo_status: HealthStatus
  redis_status: HealthStatus
  storage_status: HealthStatus
  upload_status: HealthStatus
  websocket_status: HealthStatus
  push_status: HealthStatus
  queue_status: HealthStatus
  queue_message_send: number
  queue_message_sync: number
  queue_push_notify: number
  queue_delayed: number
  queue_dead: number
  upload_total: number
  upload_failed: number
  push_total: number
  push_failed: number
  ws_online_connections: number
  ws_online_users: number
  ws_total_disconnects: number
  ws_dropped_messages: number
  goroutines: number
  memory_alloc_mb: number
  created_at: string
}

export interface HealthTrendResponse {
  hours: number
  sample_interval_minutes: number
  list: HealthMetricSnapshotItem[]
}

export interface AdminLoginLogItem {
  id: number
  admin_id: number
  username: string
  ip: string
  user_agent: string
  status: 0 | 1
  failure_reason: string
  throttle_applied: boolean
  created_at: string
}

export interface AdminLoginLogListResponse {
  list: AdminLoginLogItem[]
  total: number
  page: number
  page_size: number
  summary: {
    total_24h: number
    success_24h: number
    failed_24h: number
    throttled_24h: number
  }
  throttle_policy: {
    window_minutes: number
    ip_limit: number
    account_limit: number
  }
}

export interface UploadLogItem {
  id: number
  actor_type: string
  user_id: number
  admin_id: number
  media_type: string
  provider: string
  object_key: string
  url: string
  file_name: string
  content_type: string
  size: number
  success: boolean
  error: string
  duration_ms: number
  ip: string
  created_at: string
}

export interface UploadLogListResponse {
  list: UploadLogItem[]
  total: number
  page: number
  page_size: number
}

export interface AdminSecurityEventItem {
  id: number
  admin_id: number
  admin_username: string
  admin_role: string
  event_type: string
  action: string
  target: string
  success: boolean
  error: string
  metadata: string
  ip: string
  user_agent: string
  created_at: string
}

export interface AdminSecurityEventListResponse {
  list: AdminSecurityEventItem[]
  total: number
  page: number
  page_size: number
}

export function adminLogin(params: AdminLoginParams) {
  return request.post<AdminLoginResponse>({
    url: '/admin/login',
    params
  })
}
export function getAdminMe() {
  return request.get<AdminInfo>({
    url: '/admin/me'
  })
}
export function getAdminList() {
  return request.get<AdminInfo[]>({
    url: '/admin/list'
  })
}
export function createAdmin(params: AdminCreateParams) {
  return request.post<AdminInfo>({
    url: '/admin/create',
    params
  })
}
export function deleteAdmin(id: number) {
  return request.del({
    url: `/admin/${id}`
  })
}
export function updateAdminPassword(params: { old_password: string; new_password: string }) {
  return request.put({
    url: '/admin/password',
    params
  })
}
export function getAdminLoginLogs(params?: {
  page?: number
  page_size?: number
  username?: string
  ip?: string
  status?: string
  throttled?: string
}) {
  return request.get<AdminLoginLogListResponse>({
    url: '/admin/login-logs',
    params
  })
}

export function getUploadLogs(params?: {
  page?: number
  page_size?: number
  media_type?: string
  provider?: string
  success?: string
  user_id?: number | string
  actor_type?: string
}) {
  return request.get<UploadLogListResponse>({
    url: '/admin/upload/logs',
    params
  })
}

export function getAdminSecurityEvents(params?: {
  page?: number
  page_size?: number
  event_type?: string
  action?: string
  admin_username?: string
  success?: string
}) {
  return request.get<AdminSecurityEventListResponse>({
    url: '/admin/security-events',
    params
  })
}
export function getUserList(params: UserSearchParams) {
  return request.get<UserListResponse>({
    url: '/admin/users/list',
    params
  })
}
export function updateUser(id: number, params: Partial<UserListItem>) {
  return request.put<UserListItem>({
    url: `/admin/users/${id}`,
    params
  })
}
export function updateUserStatus(id: number, status: number) {
  return request.put({
    url: `/admin/users/${id}/status`,
    params: { status }
  })
}
export function kickUser(id: number) {
  return request.post({
    url: `/admin/users/${id}/kick`
  })
}
export function banUser(id: number, reason: string) {
  return request.post({
    url: `/admin/users/${id}/ban`,
    params: { reason }
  })
}
export function unbanUser(id: number) {
  return request.post({
    url: `/admin/users/${id}/unban`
  })
}
export function getUserStats() {
  return request.get<UserStats>({
    url: '/admin/users/stats'
  })
}

export function getUserDiagnostics(id: number) {
  return request.get<UserDiagnosticResponse>({
    url: `/admin/users/${id}/diagnostics`
  })
}
export function sendUserTestPush(id: number) {
  return request.post<{
    user_id: number
    uuid: string
    push_device_count: number
    submitted_at: string
  }>({
    url: `/admin/users/${id}/test-push`
  })
}

export function getChatList(params: ChatSearchParams) {
  return request.get<ChatListResponse>({
    url: '/admin/chats/list',
    params
  })
}
export function getGroupList(params: ChatSearchParams) {
  return request.get<ChatListResponse>({
    url: '/admin/chats/groups',
    params
  })
}
export function getChannelList(params: ChatSearchParams) {
  return request.get<ChatListResponse>({
    url: '/admin/chats/channels',
    params
  })
}
export function updateChatStatus(id: number, status: number) {
  return request.put({
    url: `/admin/chats/${id}/status`,
    params: { status }
  })
}
export function updateChatInfo(id: number, params: UpdateChatInfoParams) {
  return request.put<ChatListItem>({
    url: `/admin/chats/${id}`,
    params
  })
}
export function deleteChat(id: number) {
  return request.del({
    url: `/admin/chats/${id}`
  })
}
export function getChatDetail(id: number) {
  return request.get<ChatDetailResponse>({
    url: `/admin/chats/${id}`
  })
}
export function banChat(id: number, reason?: string) {
  return request.post({
    url: `/admin/chats/${id}/ban`,
    params: { reason }
  })
}
export function unbanChat(id: number) {
  return request.post({
    url: `/admin/chats/${id}/unban`
  })
}
export function dissolveChat(id: number) {
  return request.post({
    url: `/admin/chats/${id}/dissolve`
  })
}
export function getChatMembers(id: number, params?: ChatMemberSearchParams) {
  return request.get<ChatMembersResponse>({
    url: `/admin/chats/${id}/members`,
    params
  })
}
export function getChatJoinRequests(
  id: number,
  params?: ChatMemberSearchParams & { status?: number }
) {
  return request.get<ChatJoinRequestsResponse>({
    url: `/admin/chats/${id}/join-requests`,
    params
  })
}
export function reviewChatJoinRequest(chatId: number, requestId: number, approve: boolean) {
  return request.post({
    url: `/admin/chats/${chatId}/join-requests/${requestId}/review`,
    params: { approve }
  })
}
export function addChatMembers(id: number, params: AddChatMembersParams) {
  return request.post<{
    message: string
    added_count: number
    skipped_count: number
  }>({
    url: `/admin/chats/${id}/members`,
    params
  })
}
export function removeChatMember(chatId: number, memberId: number) {
  return request.del({
    url: `/admin/chats/${chatId}/members/${memberId}`
  })
}
export function updateChatMemberRole(chatId: number, memberId: number, role: 1 | 2) {
  return request.put({
    url: `/admin/chats/${chatId}/members/${memberId}/role`,
    params: { role }
  })
}
export function updateChatMemberMute(
  chatId: number,
  memberId: number,
  params: { is_muted: boolean; minutes?: number }
) {
  return request.put({
    url: `/admin/chats/${chatId}/members/${memberId}/mute`,
    params
  })
}
export function transferChatOwner(chatId: number, memberId: number) {
  return request.put({
    url: `/admin/chats/${chatId}/owner`,
    params: { member_id: memberId }
  })
}
export function getChatStats() {
  return request.get<ChatStatsResponse>({
    url: '/admin/chats/stats'
  })
}
export function getDashboardStats() {
  return request.get<DashboardStats>({
    url: '/admin/stats/dashboard'
  })
}
export function getRuntimeStatus() {
  return request.get<RuntimeStatus>({
    url: '/admin/stats/runtime'
  })
}

export function getUserStatsDetail(days?: number) {
  return request.get<UserStatsDetail>({
    url: '/admin/stats/users',
    params: days ? { days } : undefined
  })
}
export function getMessageStats() {
  return request.get({
    url: '/admin/stats/messages'
  })
}
export interface MomentListItem {
  id: number
  uuid: string
  user_id: number
  user_name: string
  user_avatar: string | null
  content: string
  content_type: number
  media_urls: string[]
  topics: string[]
  visibility: number
  status: number
  status_text?: string
  review_reason?: string
  reviewed_by?: number
  reviewed_by_name?: string
  reviewed_at?: string
  like_count: number
  comment_count: number
  view_count: number
  created_at: string
}
export interface MomentListResponse {
  list: MomentListItem[]
  total: number
  page: number
  page_size: number
}
export interface MomentSearchParams {
  page?: number
  page_size?: number
  keyword?: string
  status?: number
  user_id?: number
  only_pending?: boolean
  with_review_reason?: boolean
}
export function getMomentList(params: MomentSearchParams) {
  return request.get<MomentListResponse>({
    url: '/admin/moments/list',
    params
  })
}
export function updateMomentStatus(id: number, status: number, reason?: string) {
  return request.put({
    url: `/admin/moments/${id}/status`,
    params: { status, reason }
  })
}
export function deleteMoment(id: number) {
  return request.del({
    url: `/admin/moments/${id}`
  })
}
export function getMomentStats() {
  return request.get({
    url: '/admin/moments/stats'
  })
}
export interface Topic {
  id: number
  name: string
  description: string
  icon: string
  cover_image: string
  post_count: number
  follow_count: number
  is_hot: boolean
  is_official: boolean
  status: number
  sort: number
  created_at: string
  updated_at: string
}
export interface TopicListResponse {
  list: Topic[]
  total: number
  page: number
  page_size: number
}
export function getTopicList(params: { page?: number; page_size?: number; keyword?: string }) {
  return request.get<TopicListResponse>({
    url: '/admin/topics/list',
    params
  })
}
export function createTopic(data: Partial<Topic>) {
  return request.post<Topic>({
    url: '/admin/topics/create',
    params: data
  })
}
export function updateTopic(id: number, data: Partial<Topic>) {
  return request.put<Topic>({
    url: `/admin/topics/${id}`,
    params: data
  })
}
export function deleteTopic(id: number) {
  return request.del({
    url: `/admin/topics/${id}`
  })
}
export interface BannedWord {
  id: number
  word: string
  category: string
  level: number
  replacement: string
  status: number
  hit_count: number
  created_at: string
  updated_at: string
}
export interface BannedWordListResponse {
  list: BannedWord[]
  total: number
  page: number
  page_size: number
}
export function getBannedWordList(params: {
  page?: number
  page_size?: number
  keyword?: string
  category?: string
}) {
  return request.get<BannedWordListResponse>({
    url: '/admin/banned-words/list',
    params
  })
}
export function createBannedWord(data: Partial<BannedWord>) {
  return request.post<BannedWord>({
    url: '/admin/banned-words/create',
    params: data
  })
}
export function batchCreateBannedWords(words: string[], category: string, level: number) {
  return request.post({
    url: '/admin/banned-words/batch',
    params: { words, category, level }
  })
}
export function updateBannedWord(id: number, data: Partial<BannedWord>) {
  return request.put<BannedWord>({
    url: `/admin/banned-words/${id}`,
    params: data
  })
}
export function deleteBannedWord(id: number) {
  return request.del({
    url: `/admin/banned-words/${id}`
  })
}
export interface ChatAttachmentMenuSettings {
  enabled: boolean
  album: boolean
  camera: boolean
  call: boolean
  location: boolean
  red_packet: boolean
  transfer: boolean
  favorite: boolean
  file: boolean
}

export interface IOSComplianceSettings {
  enabled: boolean
  vip_enabled: boolean
  wallet_enabled: boolean
  wallet_recharge_enabled: boolean
  moment_video_enabled: boolean
  custom_portal_enabled: boolean
  checkin_enabled?: boolean
}

export interface SystemSettings {
  app_version_ios: string
  app_version_android: string
  latest_version_ios?: string
  latest_version_android?: string
  register_base_url?: string
  support_online_url?: string
  support_qq?: string
  app_force_update: boolean
  app_update_url: string
  app_update_url_ios?: string
  app_update_url_android?: string
  min_supported_version_ios?: string
  min_supported_version_android?: string
  app_update_message: string
  splash_enabled?: boolean
  splash_image_url?: string
  splash_duration_ms?: number
  allow_register: boolean
  allow_quick_register: boolean
  quick_register_device_limit: number
  quick_register_ip_limit: number
  force_keep_alive_enabled?: boolean
  require_invite_code: boolean
  require_gender_on_register: boolean
  require_phone_bind: boolean
  user_invite_code_length: number
  enable_moment_post: boolean
  moment_post_review_enabled?: boolean
  new_user_follow_official: boolean
  invite_register_bind_only: boolean
  new_user_join_group: boolean
  new_user_join_channel: boolean
  group_invite_require_friend: boolean
  // 可选字段用于兼容尚未返回该配置的旧后端，页面回填时统一降级为 approval。
  friend_add_mode?: 'direct' | 'approval' | 'disabled'
  ios_compliance?: IOSComplianceSettings
  custom_portal_enabled: boolean
  custom_portal_title: string
  custom_portal_url: string
  custom_portal_icon_url: string
  burn_after_read_enabled?: boolean
  chat_attachment_menu?: ChatAttachmentMenuSettings
  message_crypto_mode?: 'plain' | 'compatible' | 'strict'
  group_max_members: number
  channel_max_members: number
  revoke_message_minutes?: number
  ip_rate_limit?: number
  user_rate_limit?: number
  heartbeat_timeout?: number
  voice_transcribe_provider?: string
  // 这些字段控制客户端是否具备直传资格；实际启用还受平台、稳定分桶和存储供应商共同约束。
  chat_image_direct_upload_enabled?: boolean
  chat_image_direct_upload_platforms?: string[]
  chat_image_direct_upload_rollout_percent?: number
  chat_image_direct_upload_max_concurrency?: number
  voice_transcribe_url?: string
  voice_transcribe_token?: string
  voice_transcribe_language?: string
  openai_api_key?: string
  openai_transcribe_model?: string
  openai_transcribe_url?: string
  deepseek_api_key?: string
  deepseek_base_url?: string
  deepseek_model?: string
  rtc_provider?: 'agora' | 'livekit'
  agora_enabled: boolean
  agora_app_id: string
  agora_app_certificate: string
  agora_token_expire: number
  livekit_enabled?: boolean
  livekit_server_url?: string
  livekit_api_key?: string
  livekit_api_secret?: string
  livekit_token_expire?: number
  apns_enabled: boolean
  apns_bundle_id: string
  apns_key_id: string
  apns_team_id: string
  apns_auth_key: string
  apns_environment: string
  fcm_enabled: boolean
  fcm_project_id: string
  fcm_service_account_json: string
  hms_enabled: boolean
  hms_app_id: string
  hms_app_secret: string
  jpush_enabled: boolean
  jpush_app_key: string
  jpush_master_secret: string
  push_default_title: string
  push_chat_enabled: boolean
  push_friend_enabled: boolean
  push_system_enabled: boolean
  push_category_chat: string
  push_category_service: string
  push_category_marketing: string
  push_primary_provider: string
  push_fallback_provider: string
  push_rate_limit_per_min: number
  push_marketing_daily_limit: number
  push_quiet_hours_enabled: boolean
  push_quiet_hours_start: string
  push_quiet_hours_end: string
  xiaomi_push_enabled: boolean
  xiaomi_package_name: string
  xiaomi_app_secret: string
  oppo_push_enabled: boolean
  oppo_app_key: string
  oppo_app_secret: string
  max_image_size: number
  max_video_size: number
  max_file_size: number
  max_voice_size: number
  cloud_storage?: CloudStorageConfig | string
  client_bootstrap?: ClientBootstrapConfig | string
  role_permissions?: RolePermissionConfig | string
  user_agreement?: string
  privacy_policy?: string
  system_name?: string
  system_version?: string
  _admin_role?: string
}
export function getSystemSettings() {
  return request.get<SystemSettings>({
    url: '/admin/settings'
  })
}
export type PublicAppSettings = Pick<
  SystemSettings,
  'system_name' | 'system_version' | 'allow_register'
>
export function getPublicAppSettings() {
  return request.get<PublicAppSettings>({
    url: '/app/settings',
    showErrorMessage: false
  })
}
export function updateSystemSettings(settings: Partial<SystemSettings>) {
  return request.put({
    url: '/admin/settings',
    params: settings
  })
}

export function getStorageStatus() {
  return request.get<StorageStatusResponse>({
    url: '/admin/storage/status'
  })
}

export function testStorageUpload() {
  return request.post<StorageTestUploadResponse>({
    url: '/admin/storage/test-upload',
    timeout: 60000,
    showErrorMessage: false
  })
}

export function getSystemHealthDetail() {
  return request.get<SystemHealthDetailResponse>({
    url: '/admin/system/health-detail'
  })
}

export function getSystemHealthTrend(params?: { hours?: number }) {
  return request.get<HealthTrendResponse>({
    url: '/admin/system/health-trend',
    params
  })
}

export interface PushTestParams {
  user_id?: number
  device_id?: number
  scene?: string
  title?: string
  body?: string
  data?: Record<string, unknown>
}

export interface PushTestResponse {
  submitted_devices: number
  scene: string
  submitted_at: string
}

export function sendPushTest(params: PushTestParams) {
  return request.post<PushTestResponse>({
    url: '/admin/push/test',
    params
  })
}

export interface PushLogItem {
  id: number
  user_id: number
  device_id: number
  device_key: string
  channel: string
  provider: string
  scene: string
  request_id: string
  success: boolean
  error: string
  title: string
  body: string
  occurred_at: string
}

export interface PushLogListResponse {
  list: PushLogItem[]
  total: number
  page: number
  page_size: number
}

export interface PushAggregateItem {
  name: string
  total: number
  success: number
  failed: number
  rate: number
}

export interface PushRecentFailureItem {
  id: number
  user_id: number
  device_id: number
  device_key: string
  channel: string
  scene: string
  error: string
  occurred_at: string
}

export interface PushStatsResponse {
  hours: number
  total: number
  success: number
  failed: number
  success_rate: number
  invalid_device_count: number
  invalid_token_failures: number
  unhealthy_channels: number
  channel_stats: PushAggregateItem[]
  scene_stats: PushAggregateItem[]
  app_version_stats: PushAggregateItem[]
  recent_failures: PushRecentFailureItem[]
}

export interface PushDeviceUser {
  id: number
  uuid: string
  username: string
  nickname: string
  status: number
}

export interface PushDeviceLastPush {
  id: number
  channel: string
  scene: string
  success: boolean
  error: string
  occurred_at: string
}

export interface PushDeviceItem {
  id: number
  user_id: number
  device_id: string
  device_type: string
  brand: string
  model: string
  push_channel: string
  device_name: string
  app_version: string
  push_token_bound: boolean
  push_token_length: number
  push_token_updated_at: string
  ip: string
  last_active: string
  created_at: string
  failed_7d: number
  user?: PushDeviceUser
  last_push?: PushDeviceLastPush
}

export interface PushDeviceListResponse {
  list: PushDeviceItem[]
  total: number
  page: number
  page_size: number
}

export interface PushDisableDeviceTokenResponse {
  id: number
  user_id?: number
  device_key?: string
  channel?: string
  disabled: boolean
  disabled_at?: string
  message?: string
}

export interface PushCleanupInvalidTokensResponse {
  dry_run: boolean
  hours: number
  min_failures: number
  channel: string
  matched_count: number
  cleared_count: number
  items: Array<{
    id: number
    user_id: number
    device_key: string
    channel: string
    failure_count: number
    last_active: string
    token_updated_at: string
    push_token_length: number
  }>
}

export function getPushLogs(params?: {
  page?: number
  page_size?: number
  user_id?: number | string
  device_id?: number | string
  channel?: string
  success?: string
}) {
  return request.get<PushLogListResponse>({
    url: '/admin/push/logs',
    params,
    showErrorMessage: false
  })
}

export function getPushDevices(params?: {
  page?: number
  page_size?: number
  user_id?: number | string
  channel?: string
  bound?: string
  keyword?: string
}) {
  return request.get<PushDeviceListResponse>({
    url: '/admin/push/devices',
    params,
    showErrorMessage: false
  })
}

export function disablePushDeviceToken(id: number) {
  return request.post<PushDisableDeviceTokenResponse>({
    url: `/admin/push/devices/${id}/disable-token`
  })
}

export function cleanupInvalidPushTokens(params: {
  hours?: number
  min_failures?: number
  channel?: string
  confirm?: boolean
  dry_run?: boolean
}) {
  return request.post<PushCleanupInvalidTokensResponse>({
    url: '/admin/push/invalid-tokens/cleanup',
    params
  })
}

export function getPushStats(params?: { hours?: number }) {
  return request.get<PushStatsResponse>({
    url: '/admin/push/stats',
    params,
    showErrorMessage: false
  })
}

export type HotUpdatePatchStatus = 'draft' | 'published' | 'paused' | 'rolled_back'
export type HotUpdatePatchPlatform = 'android' | 'ios' | 'all'
export type HotUpdatePatchDeliveryMode = 'self_hosted' | 'shorebird'

export interface HotUpdatePatchItem {
  id: number
  patch_id: string
  name: string
  description: string
  platform: HotUpdatePatchPlatform
  channel: string
  delivery_mode: HotUpdatePatchDeliveryMode
  min_app_version: string
  max_app_version: string
  min_build_number: number
  max_build_number: number
  target_app_version: string
  patch_version: string
  patch_url: string
  patch_hash: string
  release_notes: string
  rollout_percentage: number
  is_mandatory: boolean
  priority: number
  status: HotUpdatePatchStatus
  start_at?: string | null
  end_at?: string | null
  published_at?: string | null
  paused_at?: string | null
  rollback_at?: string | null
  created_by: number
  updated_by: number
  created_at: string
  updated_at: string
}

export interface HotUpdatePatchPayload {
  name: string
  description?: string
  platform: HotUpdatePatchPlatform
  channel?: string
  delivery_mode?: HotUpdatePatchDeliveryMode
  min_app_version?: string
  max_app_version?: string
  min_build_number?: number
  max_build_number?: number
  target_app_version?: string
  patch_version: string
  patch_url: string
  patch_hash?: string
  release_notes?: string
  rollout_percentage?: number
  is_mandatory?: boolean
  priority?: number
  start_at?: string | null
  end_at?: string | null
}

export interface HotUpdatePatchListParams {
  page?: number
  page_size?: number
  status?: HotUpdatePatchStatus | ''
  platform?: HotUpdatePatchPlatform | ''
  delivery_mode?: HotUpdatePatchDeliveryMode | ''
  channel?: string
  keyword?: string
}

export interface HotUpdatePatchListResponse {
  list: HotUpdatePatchItem[]
  total: number
  page: number
  page_size: number
}

export function getHotUpdatePatches(params?: HotUpdatePatchListParams) {
  return request.get<HotUpdatePatchListResponse>({
    url: '/admin/hot-update/patches',
    params
  })
}

export function getHotUpdatePatch(id: number) {
  return request.get<HotUpdatePatchItem>({
    url: `/admin/hot-update/patches/${id}`
  })
}

export function createHotUpdatePatch(payload: HotUpdatePatchPayload) {
  return request.post<HotUpdatePatchItem>({
    url: '/admin/hot-update/patches',
    params: payload
  })
}

export function updateHotUpdatePatch(id: number, payload: HotUpdatePatchPayload) {
  return request.put<HotUpdatePatchItem>({
    url: `/admin/hot-update/patches/${id}`,
    params: payload
  })
}

export function deleteHotUpdatePatch(id: number) {
  return request.del({
    url: `/admin/hot-update/patches/${id}`
  })
}

export function publishHotUpdatePatch(id: number) {
  return request.post({
    url: `/admin/hot-update/patches/${id}/publish`
  })
}

export function pauseHotUpdatePatch(id: number) {
  return request.post({
    url: `/admin/hot-update/patches/${id}/pause`
  })
}

export function rollbackHotUpdatePatch(id: number) {
  return request.post({
    url: `/admin/hot-update/patches/${id}/rollback`
  })
}
export type HotUpdatePatchReportStatus =
  | 'check_hit'
  | 'deferred'
  | 'apply_success'
  | 'install_started'
  | 'install_confirmed'
  | 'apply_failed'
  | 'sdk_not_integrated'
  | 'sdk_not_available'

export interface HotUpdatePatchReportItem {
  id: number
  patch_id: number
  patch_ref_id: string
  patch_version: string
  platform: HotUpdatePatchPlatform
  channel: string
  delivery_mode: HotUpdatePatchDeliveryMode
  app_version: string
  build_number: number
  device_id: string
  user_uuid: string
  status: HotUpdatePatchReportStatus
  message: string
  client_ip: string
  created_at: string
}

export interface HotUpdatePatchReportListParams {
  page?: number
  page_size?: number
  status?: HotUpdatePatchReportStatus | ''
  platform?: HotUpdatePatchPlatform | ''
  delivery_mode?: HotUpdatePatchDeliveryMode | ''
  channel?: string
  patch_id?: number
  patch_ref_id?: string
  user_uuid?: string
  device_id?: string
  keyword?: string
}

export interface HotUpdatePatchReportListResponse {
  list: HotUpdatePatchReportItem[]
  total: number
  page: number
  page_size: number
}

export function getHotUpdatePatchReports(params?: HotUpdatePatchReportListParams) {
  return request.get<HotUpdatePatchReportListResponse>({
    url: '/admin/hot-update/reports',
    params
  })
}
export interface OfficialUser {
  id: number
  user_id: number
  user_uuid: string
  username: string
  nickname: string
  avatar: string
  remark: string
  invite_code?: string
  welcome_message?: string
  is_service_enabled?: boolean
  created_at: string
}

export interface OfficialInvitee {
  usage_id: number
  user_id: number
  user_uuid: string
  username: string
  nickname: string
  avatar: string
  invite_code: string
  registered_at: string
}
export function getOfficialUsers() {
  return request.get<OfficialUser[]>({
    url: '/admin/settings/official-users'
  })
}
export function getOfficialUserInvitees(id: number) {
  return request.get<{ total: number; list: OfficialInvitee[] }>({
    url: `/admin/settings/official-users/${id}/invitees`
  })
}
export function addOfficialUser(userUUID: string, remark?: string) {
  return request.post({
    url: '/admin/settings/official-users',
    params: { user_uuid: userUUID, remark }
  })
}
export function addOfficialUserByUsername(username: string, remark?: string) {
  return request.post({
    url: '/admin/settings/official-users',
    params: { username, remark }
  })
}
export function addOfficialServiceUserByUsername(
  username: string,
  payload?: { remark?: string; welcome_message?: string; invite_code?: string }
) {
  return request.post({
    url: '/admin/settings/official-users',
    params: {
      username,
      remark: payload?.remark,
      welcome_message: payload?.welcome_message,
      invite_code: payload?.invite_code
    }
  })
}
export function updateOfficialUser(
  id: number,
  data: Partial<Pick<OfficialUser, 'remark' | 'welcome_message' | 'is_service_enabled'>> & {
    invite_code?: string
  }
) {
  return request.put({
    url: `/admin/settings/official-users/${id}`,
    params: data
  })
}
export function removeOfficialUser(id: number) {
  return request.del({
    url: `/admin/settings/official-users/${id}`
  })
}
export interface OfficialGroup {
  id: number
  chat_id: number
  chat_uuid: string
  name: string
  username: string
  avatar: string
  member_count: number
  remark: string
  created_at: string
}
export function getOfficialGroups() {
  return request.get<OfficialGroup[]>({
    url: '/admin/settings/official-groups'
  })
}
export function addOfficialGroup(chatUUID: string, remark?: string) {
  return request.post({
    url: '/admin/settings/official-groups',
    params: { chat_uuid: chatUUID, remark }
  })
}
export function addOfficialGroupByUsername(username: string, remark?: string) {
  return request.post({
    url: '/admin/settings/official-groups',
    params: { username, remark }
  })
}
export function removeOfficialGroup(id: number) {
  return request.del({
    url: `/admin/settings/official-groups/${id}`
  })
}
export interface OfficialChannel {
  id: number
  chat_id: number
  chat_uuid: string
  name: string
  username: string
  avatar: string
  member_count: number
  remark: string
  created_at: string
}
export function getOfficialChannels() {
  return request.get<OfficialChannel[]>({
    url: '/admin/settings/official-channels'
  })
}
export function addOfficialChannel(chatUUID: string, remark?: string) {
  return request.post({
    url: '/admin/settings/official-channels',
    params: { chat_uuid: chatUUID, remark }
  })
}
export function addOfficialChannelByUsername(username: string, remark?: string) {
  return request.post({
    url: '/admin/settings/official-channels',
    params: { username, remark }
  })
}
export function removeOfficialChannel(id: number) {
  return request.del({
    url: `/admin/settings/official-channels/${id}`
  })
}
export interface WalletStats {
  wallet_count: number
  total_balance: number
  total_frozen: number
  red_packet_count: number
  red_packet_amount: number
  transfer_count: number
  transfer_amount: number
}
export function getWalletStats() {
  return request.get<WalletStats>({
    url: '/admin/wallet/stats'
  })
}
export interface UserWalletInfo {
  user_id: string
  user_name: string
  username?: string
  avatar?: string
  balance: number
  frozen_balance: number
  has_pay_password: boolean
  is_locked: boolean
  created_at?: string
}
export interface WalletUserListResponse {
  list: UserWalletInfo[]
  total: number
  page: number
  page_size: number
}
export function getWalletUserList(params?: {
  page?: number
  page_size?: number
  keyword?: string
}) {
  return request.get<WalletUserListResponse>({
    url: '/admin/wallet/users',
    params
  })
}
export function getUserWallet(userId: string) {
  return request.get<UserWalletInfo>({
    url: `/admin/wallet/user/${userId}`
  })
}
export interface UserTransaction {
  id: number
  type: string
  amount: number
  balance_after: number
  related_id: string
  related_user?: {
    id: string
    nickname: string
    avatar?: string
  }
  remark: string
  created_at: string
}

export interface UserTransactionResponse {
  list: UserTransaction[]
  total: number
  page: number
  page_size: number
}

export function getUserTransactions(
  userId: string,
  params?: { page?: number; page_size?: number }
) {
  return request.get<UserTransactionResponse>({
    url: `/admin/wallet/user/${userId}/transactions`,
    params
  })
}
export function updateUserBalance(userId: string, amount: number, remark?: string) {
  return request.post({
    url: `/admin/wallet/user/${userId}/balance`,
    params: { amount, remark }
  })
}
export function resetUserPayPassword(userId: string, newPassword: string) {
  return request.post({
    url: `/admin/wallet/user/${userId}/reset-pay-password`,
    params: { new_password: newPassword }
  })
}
export function clearUserPayPassword(userId: string) {
  return request.post({
    url: `/admin/wallet/user/${userId}/clear-pay-password`
  })
}
export function lockUserWallet(userId: string) {
  return request.post({
    url: `/admin/wallet/user/${userId}/lock`
  })
}
export function unlockUserWallet(userId: string) {
  return request.post({
    url: `/admin/wallet/user/${userId}/unlock`
  })
}
export interface RedPacketRecord {
  id: string
  sender_id: string
  sender_name: string
  sender_avatar?: string
  chat_id: string
  type: string
  total_amount: number
  total_count: number
  remaining_amount: number
  remaining_count: number
  claim_count: number
  message: string
  status: string
  expired_at: string
  created_at: string
}
export interface RedPacketListResponse {
  list: RedPacketRecord[]
  total: number
  page: number
  page_size: number
}
export interface RedPacketSearchParams {
  page?: number
  page_size?: number
  status?: string
  user_id?: string
}
export function getRedPacketList(params: RedPacketSearchParams) {
  return request.get<RedPacketListResponse>({
    url: '/admin/wallet/red-packets',
    params
  })
}
export interface RedPacketClaimRecord {
  user_id: string
  user_name: string
  user_avatar?: string
  amount: number
  is_best: boolean
  created_at: string
}
export interface RedPacketDetail extends RedPacketRecord {
  claims: RedPacketClaimRecord[]
}
export function getRedPacketDetail(id: string) {
  return request.get<RedPacketDetail>({
    url: `/admin/wallet/red-packets/${id}`
  })
}
export function refundRedPacket(id: string) {
  return request.post({
    url: `/admin/wallet/red-packets/${id}/refund`
  })
}
export interface TransferRecord {
  id: string
  sender_id: string
  sender_name: string
  sender_avatar?: string
  receiver_id: string
  receiver_name: string
  receiver_avatar?: string
  amount: number
  remark: string
  status: string
  expired_at?: string
  accepted_at?: string
  created_at: string
}
export interface TransferListResponse {
  list: TransferRecord[]
  total: number
  page: number
  page_size: number
}
export interface TransferSearchParams {
  page?: number
  page_size?: number
  status?: string
  user_id?: string
}
export function getTransferList(params: TransferSearchParams) {
  return request.get<TransferListResponse>({
    url: '/admin/wallet/transfers',
    params
  })
}
export function getTransferDetail(id: string) {
  return request.get<TransferRecord>({
    url: `/admin/wallet/transfers/${id}`
  })
}
export function refundTransfer(id: string) {
  return request.post({
    url: `/admin/wallet/transfers/${id}/refund`
  })
}
export interface CallRecord {
  id: number
  channel_name?: string
  room_name?: string
  provider?: 'agora' | 'livekit'
  rtc_provider?: 'agora' | 'livekit'
  type: string
  status: string
  caller_id: string
  caller_name: string
  caller_avatar?: string
  callee_id: string
  callee_name: string
  callee_avatar?: string
  duration: number
  end_reason?: string
  connect_time?: string | null
  last_heartbeat_at?: string | null
  released_by_cleanup?: boolean
  replaced_by_new_call?: boolean
  started_at?: string
  ended_at?: string
  created_at: string
  recent_events?: CallEvent[]
}
export interface CallListResponse {
  list: CallRecord[]
  total: number
  page: number
  page_size: number
}
export interface CallSearchParams {
  page?: number
  page_size?: number
  type?: string
  status?: string
  user_id?: string
  start_date?: string
  end_date?: string
}
export function getCallList(params: CallSearchParams) {
  return request.get<CallListResponse>({
    url: '/admin/calls/list',
    params
  })
}
export function getCallDetail(id: number) {
  return request.get<CallRecord>({
    url: `/admin/calls/${id}`
  })
}
export interface CallStats {
  total_calls: number
  audio_calls: number
  video_calls: number
  connected_calls: number
  missed_calls: number
  rejected_calls: number
  cancelled_calls: number
  total_duration: number
  today_calls: number
  today_connected: number
  today_duration: number
  observability?: CallObservabilitySnapshot
}
export function getCallStats() {
  return request.get<CallStats>({
    url: '/admin/calls/stats'
  })
}
export function getUserCallHistory(userId: string, params?: { page?: number; page_size?: number }) {
  return request.get<CallListResponse>({
    url: `/admin/calls/user/${userId}`,
    params
  })
}
export function deleteCall(id: number) {
  return request.del({
    url: `/admin/calls/${id}`
  })
}
export function forceEndCall(id: number) {
  return request.post({
    url: `/admin/calls/${id}/force-end`
  })
}
export interface CallMetricLatency {
  count: number
  avg: number
  p95: number
  p99: number
  max: number
}
export interface CallObservabilitySnapshot {
  counters: Record<string, number>
  release_latency_ms: CallMetricLatency
  sample_window: number
}
export interface CallMetricsResponse {
  metrics: CallObservabilitySnapshot
  db_active_calls: number
  stale_ringing: number
  stale_connected: number
  stale_candidates: number
  cleanup_interval: string
  ringing_timeout: string
  heartbeat_timeout: string
}
export interface CallEvent {
  id: number
  call_id: number
  event_type: string
  actor_id?: number | null
  caller_id: number
  callee_id: number
  old_status: string
  new_status: string
  reason: string
  duration: number
  latency_ms: number
  request_id: string
  payload?: unknown
  created_at: string
}
export interface CallEventListResponse {
  list: CallEvent[]
  total: number
  page: number
  page_size: number
}
export function getCallMetrics() {
  return request.get<CallMetricsResponse>({
    url: '/admin/calls/metrics'
  })
}
export function getCallEvents(params?: {
  page?: number
  page_size?: number
  call_id?: number
  user_id?: string
  event_type?: string
  reason?: string
  request_id?: string
}) {
  return request.get<CallEventListResponse>({
    url: '/admin/calls/events',
    params
  })
}
export function getUserActiveCall(userId: string) {
  return request.get<CallRecord & { active: boolean; role?: 'caller' | 'callee' }>({
    url: `/admin/calls/active-user/${userId}`
  })
}
export function forceEndUserActiveCall(userId: string) {
  return request.post({
    url: `/admin/calls/force-user/${userId}`
  })
}
export function cleanupStaleCalls(params?: {
  ringing_seconds?: number
  connected_seconds?: number
  limit?: number
}) {
  return request.post({
    url: '/admin/calls/cleanup-stale',
    params
  })
}
export function batchDeleteCalls(ids: number[]) {
  return request.post({
    url: '/admin/calls/batch-delete',
    params: { ids }
  })
}
export function resetUserPassword(userId: number, newPassword: string) {
  return request.post({
    url: `/admin/users/${userId}/reset-password`,
    params: { new_password: newPassword }
  })
}
export interface WithdrawRequest {
  id: number
  user_id: number
  user_name?: string
  username?: string
  avatar?: string
  method_id: number
  method_name?: string
  amount: number
  fee: number
  actual_amount: number
  form_data: string
  status: string
  remark: string
  reviewed_by?: number
  reviewed_at?: string
  created_at: string
  updated_at: string
}
export interface WithdrawStats {
  pending_count: number
  approved_count: number
  completed_count: number
  rejected_count: number
  total_amount: number
}
export interface WithdrawMethodInfo {
  id: number
  name: string
  icon?: string
  fields: string
  min_amount: number
  max_amount: number
  fee: number
  status: number
  sort: number
  created_at: string
}
export function getWithdrawList(params?: {
  page?: number
  page_size?: number
  status?: string
  user_id?: string
}) {
  return request.get<{ list: WithdrawRequest[]; total: number; page: number; page_size: number }>({
    url: '/admin/wallet/withdraw/list',
    params
  })
}
export function getWithdrawStats() {
  return request.get<WithdrawStats>({
    url: '/admin/wallet/withdraw/stats'
  })
}
export function reviewWithdraw(id: number, action: string, remark?: string) {
  return request.post({
    url: `/admin/wallet/withdraw/${id}/review`,
    params: { action, remark }
  })
}
export function getWithdrawMethods() {
  return request.get<WithdrawMethodInfo[]>({
    url: '/admin/wallet/methods'
  })
}
export function createWithdrawMethod(data: Partial<WithdrawMethodInfo>) {
  return request.post({
    url: '/admin/wallet/methods',
    params: data
  })
}
export function updateWithdrawMethod(id: number, data: Partial<WithdrawMethodInfo>) {
  return request.put({
    url: `/admin/wallet/methods/${id}`,
    params: data
  })
}
export function deleteWithdrawMethod(id: number) {
  return request.del({
    url: `/admin/wallet/methods/${id}`
  })
}
export function getWalletSettings() {
  return request.get<Record<string, string>>({ url: '/admin/wallet/settings' })
}
export function saveWalletSettings(data: Record<string, string>) {
  return request.post({ url: '/admin/wallet/settings', params: data })
}

export interface RechargeMethodInfo {
  id: number
  name: string
  icon?: string
  type: string
  qrcode_url?: string
  account_info?: string
  min_amount: number
  max_amount: number
  remark?: string
  status: number
  sort: number
}
export function getRechargeMethods() {
  return request.get<RechargeMethodInfo[]>({ url: '/admin/wallet/recharge-methods' })
}
export function createRechargeMethod(data: Partial<RechargeMethodInfo>) {
  return request.post({ url: '/admin/wallet/recharge-methods', params: data })
}
export function updateRechargeMethod(id: number, data: Partial<RechargeMethodInfo>) {
  return request.put({ url: `/admin/wallet/recharge-methods/${id}`, params: data })
}
export function deleteRechargeMethod(id: number) {
  return request.del({ url: `/admin/wallet/recharge-methods/${id}` })
}

export interface RechargeOrderInfo {
  id: number
  user_id: string
  user_name: string
  username?: string
  avatar?: string
  method_name?: string
  amount: number
  proof_image?: string
  status: string
  remark?: string
  reviewed_by?: number
  reviewed_at?: string
  created_at: string
}
export function getRechargeOrders(params?: { page?: number; page_size?: number; status?: string }) {
  return request.get<{ list: RechargeOrderInfo[]; total: number }>({
    url: '/admin/wallet/recharge-orders',
    params
  })
}
export function reviewRechargeOrder(id: number, action: string, remark?: string) {
  return request.post({
    url: `/admin/wallet/recharge-orders/${id}/review`,
    params: { action, remark }
  })
}

export interface BroadcastItem {
  id: number
  title: string
  content: string
  type: string
  created_at: string
}
export function sendBroadcast(data: { title: string; content: string; type?: string }) {
  return request.post({ url: '/admin/broadcast', params: data })
}
export function listBroadcasts(params?: { page?: number; page_size?: number }) {
  return request.get<{ list: BroadcastItem[]; total: number }>({
    url: '/admin/broadcast/list',
    params
  })
}
export function clearBroadcasts() {
  return request.del({ url: '/admin/broadcast/clear' })
}
export function searchMessages(params: {
  page?: number
  page_size?: number
  keyword?: string
  chat_id?: string
  sender_id?: string
  type?: string
  start_date?: string
  end_date?: string
}) {
  return request.get<{ list: any[]; total: number; page: number; page_size: number }>({
    url: '/admin/messages/search',
    params
  })
}

export interface SmsGatewayConfig {
  enabled: boolean
  provider: string // smsbao | aliyun | tencent
  message_template: string
  smsbao: { user: string; password: string }
  aliyun: {
    access_key_id: string
    access_key_secret: string
    region: string
    sign_name: string
    template_code: string
  }
  tencent: {
    secret_id: string
    secret_key: string
    region: string
    sdk_app_id: string
    sign_name: string
    template_id: string
  }
}
export function getSmsGatewayConfig() {
  return request.get<SmsGatewayConfig>({ url: '/admin/settings/sms-gateway/config' })
}
export function saveSmsGatewayConfig(data: SmsGatewayConfig) {
  return request.put({ url: '/admin/settings/sms-gateway/config', params: data })
}

export interface PaymentGatewayConfig {
  enabled: boolean
  notify_base_url: string
  min_amount: number
  max_amount: number
  wechat: {
    enabled: boolean
    mch_id: string
    mch_api_v3_key: string
    mch_certificate_serial: string
    app_id: string
    private_key_pem?: string
    h5_app_name?: string
    h5_app_url?: string
  }
  alipay: {
    enabled: boolean
    app_id: string
    app_private_key_pem?: string
    alipay_public_key_pem?: string
    is_production: boolean
    return_url?: string
  }
}
export function getPaymentGatewayConfig() {
  return request.get<PaymentGatewayConfig>({ url: '/admin/wallet/payment-config' })
}
export function savePaymentGatewayConfig(data: PaymentGatewayConfig) {
  return request.put({ url: '/admin/wallet/payment-config', params: data })
}
export function freezeUser(id: number, reason?: string) {
  return request.post({ url: `/admin/users/${id}/freeze`, params: { reason } })
}
export function unfreezeUser(id: number) {
  return request.post({ url: `/admin/users/${id}/unfreeze` })
}

export interface EmojiStorePackItem {
  id: number
  pack_id: string
  name: string
  description: string
  preview_emoji: string
  preview_file: string
  sticker_files: string[]
  sort_order: number
  is_built_in: boolean
  is_active: boolean
  created_at: string
  updated_at: string
}

export interface EmojiStorePackSavePayload {
  pack_id: string
  name: string
  description?: string
  preview_emoji?: string
  preview_file?: string
  sticker_files: string[]
  sort_order?: number
  is_built_in?: boolean
  is_active?: boolean
}

export function getEmojiStorePacks(params?: { keyword?: string; is_active?: boolean }) {
  return request.get<{ list: EmojiStorePackItem[]; total: number }>({
    url: '/admin/emoji-store/packs',
    params
  })
}

export function createEmojiStorePack(payload: EmojiStorePackSavePayload) {
  return request.post<EmojiStorePackItem>({
    url: '/admin/emoji-store/packs',
    params: payload
  })
}

export function updateEmojiStorePack(id: number, payload: EmojiStorePackSavePayload) {
  return request.put<EmojiStorePackItem>({
    url: `/admin/emoji-store/packs/${id}`,
    params: payload
  })
}

export function setEmojiStorePackActive(id: number, isActive: boolean) {
  return request.put({
    url: `/admin/emoji-store/packs/${id}/active`,
    params: { is_active: isActive }
  })
}

export function deleteEmojiStorePack(id: number) {
  return request.del({
    url: `/admin/emoji-store/packs/${id}`
  })
}

export interface VipEntitlements {
  can_create_group: boolean
  can_create_channel: boolean
  max_owned_groups: number
  max_owned_channels: number
  max_group_members: number
  max_channel_members: number
  max_pinned_chats: number
  upload_image_limit_mb: number
  upload_video_limit_mb: number
  upload_voice_limit_mb: number
  upload_file_limit_mb: number
  can_set_public_username: boolean
  can_enable_member_protection: boolean
  badge: string
  badge_icon: string
}

export interface VipPlanItem {
  id: number
  code: string
  name: string
  level: number
  level_name: string
  duration_days: number
  price: number
  original_price: number
  benefits: VipEntitlements
  description: string
  sort: number
  enabled: boolean
  created_at: string
  updated_at: string
}

export interface VipPlanPayload {
  code?: string
  name: string
  level: number
  duration_days: number
  price: number
  original_price: number
  benefits: VipEntitlements
  description?: string
  sort?: number
  enabled?: boolean
}

export interface VipUserItem {
  id: number
  uuid: string
  username: string
  nickname: string
  avatar?: string
  phone?: string | null
  level: number
  level_name: string
  vip_status: string
  is_active: boolean
  expired_at?: string | null
  plan_id?: number | null
  plan_name?: string | null
}

export interface VipUserListResponse {
  list: VipUserItem[]
  total: number
  page: number
  page_size: number
}

export interface VipOrderItem {
  id: number
  order_no: string
  user_id: number
  user_uuid: string
  username: string
  nickname: string
  plan_id: number
  plan_name: string
  plan_level: number
  amount: number
  pay_method: string
  status: string
  paid_at?: string | null
  transaction_id?: string
  remark?: string
  created_at: string
}

export interface VipOrderListResponse {
  list: VipOrderItem[]
  total: number
  page: number
  page_size: number
}

export function getVipPlans(params?: { enabled?: boolean }) {
  return request.get<VipPlanItem[]>({ url: '/admin/vip/plans', params })
}

export function getVipFreeEntitlements() {
  return request.get<VipEntitlements>({ url: '/admin/vip/free-entitlements' })
}

export function updateVipFreeEntitlements(payload: VipEntitlements) {
  return request.put<VipEntitlements>({ url: '/admin/vip/free-entitlements', params: payload })
}

export function createVipPlan(payload: VipPlanPayload) {
  return request.post<VipPlanItem>({ url: '/admin/vip/plans', params: payload })
}

export function updateVipPlan(id: number, payload: VipPlanPayload) {
  return request.put<VipPlanItem>({ url: `/admin/vip/plans/${id}`, params: payload })
}

export function getVipUsers(params?: {
  page?: number
  page_size?: number
  keyword?: string
  level?: string
  status?: string
}) {
  return request.get<VipUserListResponse>({ url: '/admin/vip/users', params })
}

export function grantVip(userId: string | number, planId: number, days?: number, remark?: string) {
  return request.post({
    url: `/admin/vip/users/${userId}/grant`,
    params: { plan_id: planId, days, remark }
  })
}

export function cancelVip(userId: string | number, remark?: string) {
  return request.post({
    url: `/admin/vip/users/${userId}/cancel`,
    params: { remark }
  })
}

export function freezeVip(userId: string | number, remark?: string) {
  return request.post({
    url: `/admin/vip/users/${userId}/freeze`,
    params: { remark }
  })
}

export function unfreezeVip(userId: string | number, remark?: string) {
  return request.post({
    url: `/admin/vip/users/${userId}/unfreeze`,
    params: { remark }
  })
}

export function getVipOrders(params?: {
  page?: number
  page_size?: number
  status?: string
  keyword?: string
}) {
  return request.get<VipOrderListResponse>({ url: '/admin/vip/orders', params })
}


// ─── 签到记录 ──────────────────────────────────────────
export interface CheckinRecord {
  id: number
  user_id: string
  checkin_at: string
  created_at: string
}

export interface CheckinListResult {
  total: number
  page: number
  records: CheckinRecord[]
}

export function getAdminCheckinList(params: {
  page?: number
  page_size?: number
  user_id?: string
  date?: string
}): Promise<{ data: CheckinListResult }> {
  return request.get<{ data: CheckinListResult }>({
    url: '/admin/checkins/list',
    params
  })
}
