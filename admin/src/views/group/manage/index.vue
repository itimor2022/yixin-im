<template>
  <div class="group-manage-page art-full-height">
    <div class="stats-row">
      <ElCard shadow="never" class="stat-card">
        <div class="stat-content">
          <div class="stat-icon primary">
            <ArtSvgIcon icon="ri:group-line" />
          </div>
          <div>
            <div class="stat-label">群总数</div>
            <div class="stat-value">{{ stats.group_count }}</div>
          </div>
        </div>
      </ElCard>
      <ElCard shadow="never" class="stat-card">
        <div class="stat-content">
          <div class="stat-icon success">
            <ArtSvgIcon icon="ri:add-circle-line" />
          </div>
          <div>
            <div class="stat-label">今日新增</div>
            <div class="stat-value">{{ stats.today_group_count }}</div>
          </div>
        </div>
      </ElCard>
      <ElCard shadow="never" class="stat-card">
        <div class="stat-content">
          <div class="stat-icon warning">
            <ArtSvgIcon icon="ri:forbid-line" />
          </div>
          <div>
            <div class="stat-label">当前筛选</div>
            <div class="stat-value">{{ pagination.total }}</div>
          </div>
        </div>
      </ElCard>
      <ElCard shadow="never" class="stat-card">
        <div class="stat-content">
          <div class="stat-icon danger">
            <ArtSvgIcon icon="ri:alarm-warning-line" />
          </div>
          <div>
            <div class="stat-label">封禁群数</div>
            <div class="stat-value">{{ stats.group_banned_count }}</div>
          </div>
        </div>
      </ElCard>
    </div>

    <ElCard shadow="never" class="toolbar-card">
      <div class="toolbar">
        <div class="toolbar-left">
          <ElInput
            v-model="filters.keyword"
            clearable
            placeholder="搜索群名称 / 简介 / 群主"
            class="search-input"
            @keyup.enter="handleSearch"
            @clear="handleSearch"
          >
            <template #prefix>
              <ArtSvgIcon icon="ri:search-line" />
            </template>
          </ElInput>
          <ElSelect v-model="filters.status" clearable placeholder="状态" class="status-select">
            <ElOption label="正常" :value="0" />
            <ElOption label="已封禁" :value="1" />
            <ElOption label="已解散" :value="2" />
          </ElSelect>
          <ElButton type="primary" @click="handleSearch">
            <ArtSvgIcon icon="ri:search-line" class="mr-1" />
            搜索
          </ElButton>
        </div>
        <ElButton :loading="loading" @click="refreshAll">
          <ArtSvgIcon icon="ri:refresh-line" class="mr-1" />
          刷新
        </ElButton>
      </div>
    </ElCard>

    <ElCard shadow="never" class="table-card">
      <ElTable v-loading="loading" :data="groups" row-key="id" height="100%">
        <ElTableColumn label="群信息" min-width="260">
          <template #default="{ row }">
            <div class="group-cell">
              <ElAvatar :size="44" :src="getAvatarUrl(row.avatar, row.uuid)" shape="square" />
              <div class="group-meta">
                <div class="group-name">{{ row.name || '未命名群' }}</div>
                <div class="group-desc">{{ row.description || row.uuid }}</div>
              </div>
            </div>
          </template>
        </ElTableColumn>
        <ElTableColumn label="群主" min-width="140">
          <template #default="{ row }">
            <span>{{ row.owner_name || '-' }}</span>
          </template>
        </ElTableColumn>
        <ElTableColumn label="成员" width="110" align="center">
          <template #default="{ row }">
            <span class="strong-text">{{ row.member_count }}</span>
            <span v-if="row.max_members" class="muted-text"> / {{ row.max_members }}</span>
          </template>
        </ElTableColumn>
        <ElTableColumn label="公开" width="90" align="center">
          <template #default="{ row }">
            <ElTag :type="row.is_public ? 'success' : 'info'" size="small">
              {{ row.is_public ? '公开' : '私密' }}
            </ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn label="状态" width="100" align="center">
          <template #default="{ row }">
            <ElTag :type="getStatusTag(row.status)" size="small">
              {{ getStatusText(row.status) }}
            </ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn label="创建时间" width="170">
          <template #default="{ row }">
            {{ formatTime(row.created_at) }}
          </template>
        </ElTableColumn>
        <ElTableColumn label="操作" width="250" fixed="right" align="center">
          <template #default="{ row }">
            <ElButton type="primary" link size="small" @click="openDrawer(row)">详情</ElButton>
            <ElButton type="info" link size="small" @click="openMessageSearch(row)"
              >聊天记录</ElButton
            >
            <ElButton
              v-if="row.status === 0"
              type="warning"
              link
              size="small"
              :disabled="isDemoAdmin"
              @click="handleBan(row)"
            >
              封禁
            </ElButton>
            <ElButton
              v-if="row.status === 1"
              type="success"
              link
              size="small"
              :disabled="isDemoAdmin"
              @click="handleUnban(row)"
            >
              解封
            </ElButton>
            <ElButton
              type="danger"
              link
              size="small"
              :disabled="isDemoAdmin || row.status === 2"
              @click="handleDissolve(row)"
            >
              解散
            </ElButton>
            <ElButton
              type="danger"
              link
              size="small"
              :disabled="isDemoAdmin"
              @click="handleDelete(row)"
            >
              删除
            </ElButton>
          </template>
        </ElTableColumn>
      </ElTable>

      <div class="pagination-row">
        <ElPagination
          v-model:current-page="pagination.page"
          v-model:page-size="pagination.pageSize"
          :total="pagination.total"
          :page-sizes="[10, 20, 50, 100]"
          layout="total, sizes, prev, pager, next, jumper"
          @size-change="loadData"
          @current-change="loadData"
        />
      </div>
    </ElCard>

    <ElDrawer v-model="drawerVisible" :title="drawerTitle" size="720px" destroy-on-close>
      <div v-loading="detailLoading" class="drawer-body">
        <ElTabs v-model="activeTab">
          <ElTabPane label="群资料" name="profile">
            <ElForm label-width="108px" :model="form" class="profile-form">
              <ElFormItem label="群名称">
                <ElInput v-model="form.name" maxlength="100" show-word-limit />
              </ElFormItem>
              <ElFormItem label="群头像">
                <ElInput v-model="form.avatar" placeholder="头像 URL" />
              </ElFormItem>
              <ElFormItem label="公开账号">
                <ElInput v-model="form.username" maxlength="32" placeholder="可选" />
              </ElFormItem>
              <ElFormItem label="群简介">
                <ElInput
                  v-model="form.description"
                  type="textarea"
                  maxlength="1000"
                  show-word-limit
                  :rows="4"
                />
              </ElFormItem>
              <ElFormItem label="成员上限">
                <ElInputNumber v-model="form.max_members" :min="0" :max="200000" />
                <span class="form-tip">0 表示不额外限制</span>
              </ElFormItem>
              <ElFormItem label="公开群">
                <ElSwitch v-model="form.is_public" />
              </ElFormItem>
              <ElDivider content-position="left">权限设置</ElDivider>
              <div class="switch-grid">
                <ElCheckbox v-model="form.can_send_message">成员可发消息</ElCheckbox>
                <ElCheckbox v-model="form.can_send_media">成员可发媒体</ElCheckbox>
                <ElCheckbox v-model="form.can_send_links">成员可发链接</ElCheckbox>
                <ElCheckbox v-model="form.can_add_members">成员可邀请</ElCheckbox>
                <ElCheckbox v-model="form.can_pin_messages">成员可置顶消息</ElCheckbox>
                <ElCheckbox v-model="form.member_protection">成员保护</ElCheckbox>
                <ElCheckbox v-model="form.join_approval">入群需审批</ElCheckbox>
              </div>
            </ElForm>
          </ElTabPane>

          <ElTabPane label="成员管理" name="members">
            <div class="member-toolbar">
              <div class="member-toolbar-left">
                <ElInput
                  v-model="memberKeyword"
                  clearable
                  placeholder="搜索昵称 / 账号 / UUID"
                  class="member-search"
                  @keyup.enter="reloadMembers"
                  @clear="reloadMembers"
                >
                  <template #prefix>
                    <ArtSvgIcon icon="ri:search-line" />
                  </template>
                </ElInput>
                <span>共 {{ memberTotal }} 人</span>
              </div>
              <div class="member-actions">
                <ElButton :loading="memberLoading" @click="reloadMembers">刷新成员</ElButton>
                <ElButton
                  type="primary"
                  :disabled="memberActionDisabled"
                  @click="openAddMemberDialog"
                >
                  <ArtSvgIcon icon="ri:user-add-line" class="mr-1" />
                  添加成员
                </ElButton>
              </div>
            </div>
            <ElTable :data="members" v-loading="memberLoading" max-height="520">
              <ElTableColumn label="用户" min-width="220">
                <template #default="{ row }">
                  <div class="member-cell">
                    <ElAvatar :size="36" :src="getAvatarUrl(row.avatar, row.user_uuid)" />
                    <div>
                      <div class="member-name">{{ row.nickname || row.username }}</div>
                      <div class="member-username">@{{ row.username || row.user_uuid }}</div>
                    </div>
                  </div>
                </template>
              </ElTableColumn>
              <ElTableColumn label="角色" width="130">
                <template #default="{ row }">
                  <ElTag :type="getRoleTag(row.role)" size="small">{{
                    getRoleText(row.role)
                  }}</ElTag>
                </template>
              </ElTableColumn>
              <ElTableColumn label="禁言" width="130">
                <template #default="{ row }">
                  <ElTooltip
                    v-if="row.is_muted"
                    :content="
                      row.mute_end_time ? `截止：${formatTime(row.mute_end_time)}` : '永久禁言'
                    "
                    placement="top"
                  >
                    <ElTag type="danger" size="small">禁言中</ElTag>
                  </ElTooltip>
                  <ElTag v-else type="success" size="small">正常</ElTag>
                </template>
              </ElTableColumn>
              <ElTableColumn label="加入时间" width="170">
                <template #default="{ row }">
                  {{ formatTime(row.joined_at) }}
                </template>
              </ElTableColumn>
              <ElTableColumn label="操作" width="300" fixed="right">
                <template #default="{ row }">
                  <ElButton
                    v-if="row.role !== 3"
                    type="primary"
                    link
                    size="small"
                    :disabled="memberActionDisabled"
                    @click="handleSetRole(row, row.role === 2 ? 1 : 2)"
                  >
                    {{ row.role === 2 ? '取消管理' : '设为管理' }}
                  </ElButton>
                  <ElButton
                    v-if="row.role !== 3 && !row.is_muted"
                    type="warning"
                    link
                    size="small"
                    :disabled="memberActionDisabled"
                    @click="handleMuteMember(row)"
                  >
                    禁言
                  </ElButton>
                  <ElButton
                    v-if="row.role !== 3 && row.is_muted"
                    type="success"
                    link
                    size="small"
                    :disabled="memberActionDisabled"
                    @click="handleUnmuteMember(row)"
                  >
                    解禁
                  </ElButton>
                  <ElButton
                    v-if="row.role !== 3"
                    type="warning"
                    link
                    size="small"
                    :disabled="memberActionDisabled"
                    @click="handleTransferOwner(row)"
                  >
                    转让群主
                  </ElButton>
                  <ElButton
                    v-if="row.role !== 3"
                    type="danger"
                    link
                    size="small"
                    :disabled="memberActionDisabled"
                    @click="handleRemoveMember(row)"
                  >
                    移除
                  </ElButton>
                  <span v-else class="muted-text">群主</span>
                </template>
              </ElTableColumn>
            </ElTable>
            <div class="pagination-row compact">
              <ElPagination
                v-model:current-page="memberPage"
                :page-size="50"
                :total="memberTotal"
                layout="total, prev, pager, next"
                @current-change="loadMembers"
              />
            </div>
          </ElTabPane>

          <ElTabPane label="入群申请" name="joinRequests">
            <div class="member-toolbar">
              <div class="member-toolbar-left">
                <ElInput
                  v-model="requestKeyword"
                  clearable
                  placeholder="搜索昵称 / 账号 / UUID / 留言"
                  class="member-search"
                  @keyup.enter="reloadJoinRequests"
                  @clear="reloadJoinRequests"
                >
                  <template #prefix>
                    <ArtSvgIcon icon="ri:search-line" />
                  </template>
                </ElInput>
                <ElSelect
                  v-model="requestStatus"
                  clearable
                  placeholder="申请状态"
                  class="status-select"
                  @change="reloadJoinRequests"
                >
                  <ElOption label="待审批" :value="0" />
                  <ElOption label="已通过" :value="1" />
                  <ElOption label="已拒绝" :value="2" />
                </ElSelect>
                <span>共 {{ requestTotal }} 条</span>
              </div>
              <ElButton :loading="requestLoading" @click="reloadJoinRequests">刷新申请</ElButton>
            </div>
            <ElTable :data="joinRequests" v-loading="requestLoading" max-height="520">
              <ElTableColumn label="申请用户" min-width="220">
                <template #default="{ row }">
                  <div class="member-cell">
                    <ElAvatar :size="36" :src="getAvatarUrl(row.avatar, row.user_uuid)" />
                    <div>
                      <div class="member-name">{{
                        row.nickname || row.username || row.user_uuid
                      }}</div>
                      <div class="member-username">@{{ row.username || row.user_uuid }}</div>
                    </div>
                  </div>
                </template>
              </ElTableColumn>
              <ElTableColumn label="留言" min-width="180">
                <template #default="{ row }">
                  <span class="request-message">{{ row.message || '-' }}</span>
                </template>
              </ElTableColumn>
              <ElTableColumn label="状态" width="110" align="center">
                <template #default="{ row }">
                  <ElTag :type="getRequestStatusTag(row.status)" size="small">
                    {{ getRequestStatusText(row.status) }}
                  </ElTag>
                </template>
              </ElTableColumn>
              <ElTableColumn label="申请时间" width="170">
                <template #default="{ row }">
                  {{ formatTime(row.created_at) }}
                </template>
              </ElTableColumn>
              <ElTableColumn label="操作" width="150" fixed="right" align="center">
                <template #default="{ row }">
                  <template v-if="row.status === 0">
                    <ElButton
                      type="success"
                      link
                      size="small"
                      :disabled="memberActionDisabled"
                      @click="handleReviewJoinRequest(row, true)"
                    >
                      通过
                    </ElButton>
                    <ElButton
                      type="danger"
                      link
                      size="small"
                      :disabled="memberActionDisabled"
                      @click="handleReviewJoinRequest(row, false)"
                    >
                      拒绝
                    </ElButton>
                  </template>
                  <span v-else class="muted-text">已处理</span>
                </template>
              </ElTableColumn>
            </ElTable>
            <div class="pagination-row compact">
              <ElPagination
                v-model:current-page="requestPage"
                :page-size="20"
                :total="requestTotal"
                layout="total, prev, pager, next"
                @current-change="loadJoinRequests"
              />
            </div>
          </ElTabPane>
        </ElTabs>
      </div>

      <template #footer>
        <div class="drawer-footer">
          <ElButton @click="drawerVisible = false">关闭</ElButton>
          <ElButton
            type="primary"
            :loading="saving"
            :disabled="profileReadonly"
            @click="saveProfile"
          >
            保存群资料
          </ElButton>
        </div>
      </template>
    </ElDrawer>

    <ElDialog v-model="addMemberVisible" title="添加群成员" width="520px">
      <ElForm label-width="96px">
        <ElFormItem label="用户标识">
          <ElInput
            v-model="addMemberForm.identifiersText"
            type="textarea"
            :rows="5"
            maxlength="2000"
            show-word-limit
            placeholder="输入用户 ID、短号、用户名或 UUID，多个用换行、逗号或空格分隔"
          />
        </ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="addMemberVisible = false">取消</ElButton>
        <ElButton
          type="primary"
          :loading="addMemberLoading"
          :disabled="memberActionDisabled"
          @click="submitAddMembers"
        >
          添加
        </ElButton>
      </template>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
  import {
    addChatMembers,
    banChat,
    ChatListItem,
    ChatJoinRequestItem,
    ChatMemberItem,
    ChatStatsResponse,
    deleteChat,
    dissolveChat,
    getChatDetail,
    getChatJoinRequests,
    getChatMembers,
    getChatStats,
    getGroupList,
    removeChatMember,
    reviewChatJoinRequest,
    transferChatOwner,
    unbanChat,
    updateChatInfo,
    updateChatMemberMute,
    updateChatMemberRole
  } from '@/api/admin'
  import { getAvatarUrl } from '@/utils/url'
  import { usePermission } from '@/hooks/usePermission'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import { useRouter } from 'vue-router'

  defineOptions({ name: 'GroupList' })

  const { isDemoAdmin } = usePermission()
  const router = useRouter()

  const loading = ref(false)
  const detailLoading = ref(false)
  const memberLoading = ref(false)
  const addMemberLoading = ref(false)
  const saving = ref(false)
  const drawerVisible = ref(false)
  const addMemberVisible = ref(false)
  const activeTab = ref('profile')
  const selectedGroup = ref<ChatListItem | null>(null)
  const groups = ref<ChatListItem[]>([])
  const members = ref<ChatMemberItem[]>([])
  const joinRequests = ref<ChatJoinRequestItem[]>([])
  const memberTotal = ref(0)
  const memberPage = ref(1)
  const memberKeyword = ref('')
  const requestLoading = ref(false)
  const requestTotal = ref(0)
  const requestPage = ref(1)
  const requestKeyword = ref('')
  const requestStatus = ref<number | undefined>(0)

  const filters = reactive({
    keyword: '',
    status: undefined as number | undefined
  })
  const pagination = reactive({
    page: 1,
    pageSize: 20,
    total: 0
  })
  const stats = ref<ChatStatsResponse>({
    group_count: 0,
    channel_count: 0,
    banned_count: 0,
    group_banned_count: 0,
    channel_banned_count: 0,
    today_group_count: 0,
    today_channel_count: 0,
    hot_groups: [],
    hot_channels: []
  })
  const form = reactive({
    name: '',
    avatar: '',
    description: '',
    username: '',
    max_members: 0,
    is_public: false,
    can_send_message: true,
    can_send_media: true,
    can_send_links: true,
    can_add_members: false,
    can_pin_messages: false,
    member_protection: false,
    join_approval: false
  })
  const addMemberForm = reactive({
    identifiersText: ''
  })

  const drawerTitle = computed(() => {
    return selectedGroup.value
      ? `群管理 - ${selectedGroup.value.name || selectedGroup.value.uuid}`
      : '群管理'
  })
  const profileReadonly = computed(() => isDemoAdmin.value || selectedGroup.value?.status === 2)
  const memberActionDisabled = computed(
    () => isDemoAdmin.value || selectedGroup.value?.status !== 0
  )

  const loadStats = async () => {
    stats.value = await getChatStats()
  }

  const loadData = async () => {
    loading.value = true
    try {
      const res = await getGroupList({
        page: pagination.page,
        page_size: pagination.pageSize,
        keyword: filters.keyword.trim() || undefined,
        status: filters.status
      })
      groups.value = res.list || []
      pagination.total = res.total || 0
    } finally {
      loading.value = false
    }
  }

  const handleSearch = () => {
    pagination.page = 1
    loadData()
  }

  const refreshAll = () => {
    return Promise.all([loadData(), loadStats()])
  }

  const openMessageSearch = (row: ChatListItem) => {
    router.push({
      path: '/chat/message-search',
      query: { chat_id: row.uuid, name: row.name || row.uuid }
    })
  }

  const openDrawer = async (row: ChatListItem) => {
    drawerVisible.value = true
    activeTab.value = 'profile'
    selectedGroup.value = row
    memberPage.value = 1
    memberKeyword.value = ''
    requestPage.value = 1
    requestKeyword.value = ''
    requestStatus.value = 0
    // 先取权威详情确定权限和状态，再并行加载成员与入群申请两个分页数据源。
    await loadDetail(row.id)
    await Promise.all([loadMembers(), loadJoinRequests()])
  }

  const loadDetail = async (id: number) => {
    detailLoading.value = true
    try {
      const detail = await getChatDetail(id)
      selectedGroup.value = detail.chat
      fillForm(detail.chat)
      members.value = detail.members || []
      memberTotal.value = detail.chat.member_count || members.value.length
    } finally {
      detailLoading.value = false
    }
  }

  const fillForm = (chat: ChatListItem) => {
    form.name = chat.name || ''
    form.avatar = chat.avatar || ''
    form.description = chat.description || ''
    form.username = chat.username || ''
    form.max_members = Number(chat.max_members || 0)
    form.is_public = chat.is_public === true
    form.can_send_message = chat.can_send_message !== false
    form.can_send_media = chat.can_send_media !== false
    form.can_send_links = chat.can_send_links !== false
    form.can_add_members = chat.can_add_members === true
    form.can_pin_messages = chat.can_pin_messages === true
    form.member_protection = chat.member_protection === true
    form.join_approval = chat.join_approval === true
  }

  const saveProfile = async () => {
    if (!selectedGroup.value) return
    const name = form.name.trim()
    if (!name) {
      ElMessage.warning('请填写群名称')
      return
    }
    saving.value = true
    try {
      const updated = await updateChatInfo(selectedGroup.value.id, {
        name,
        avatar: form.avatar.trim(),
        description: form.description.trim(),
        username: form.username.trim(),
        max_members: Number(form.max_members || 0),
        is_public: form.is_public,
        can_send_message: form.can_send_message,
        can_send_media: form.can_send_media,
        can_send_links: form.can_send_links,
        can_add_members: form.can_add_members,
        can_pin_messages: form.can_pin_messages,
        member_protection: form.member_protection,
        join_approval: form.join_approval
      })
      selectedGroup.value = updated
      fillForm(updated)
      ElMessage.success('群资料已保存')
      await Promise.all([loadData(), loadStats()])
    } finally {
      saving.value = false
    }
  }

  const reloadMembers = () => {
    memberPage.value = 1
    loadMembers()
  }

  const loadMembers = async () => {
    if (!selectedGroup.value) return
    memberLoading.value = true
    try {
      const res = await getChatMembers(selectedGroup.value.id, {
        page: memberPage.value,
        page_size: 50,
        keyword: memberKeyword.value.trim() || undefined
      })
      members.value = res.list || []
      memberTotal.value = res.total || 0
    } finally {
      memberLoading.value = false
    }
  }

  const openAddMemberDialog = () => {
    addMemberForm.identifiersText = ''
    addMemberVisible.value = true
  }

  const reloadJoinRequests = () => {
    requestPage.value = 1
    loadJoinRequests()
  }

  const loadJoinRequests = async () => {
    if (!selectedGroup.value) return
    requestLoading.value = true
    try {
      const res = await getChatJoinRequests(selectedGroup.value.id, {
        page: requestPage.value,
        page_size: 20,
        keyword: requestKeyword.value.trim() || undefined,
        status: requestStatus.value
      })
      joinRequests.value = res.list || []
      requestTotal.value = res.total || 0
    } finally {
      requestLoading.value = false
    }
  }

  const parseIdentifiers = () => {
    // 管理员可混输用户名、UUID、短 ID；这里只分词，具体标识解析和去重由后端完成。
    return addMemberForm.identifiersText
      .split(/[\s,，;；]+/)
      .map((item) => item.trim())
      .filter(Boolean)
  }

  const submitAddMembers = async () => {
    if (!selectedGroup.value) return
    const identifiers = parseIdentifiers()
    if (identifiers.length === 0) {
      ElMessage.warning('请输入要添加的用户')
      return
    }
    addMemberLoading.value = true
    try {
      const res = await addChatMembers(selectedGroup.value.id, { identifiers })
      // 接口分别返回新增和跳过数量，跳过项可能是已在群内或无法解析的标识。
      const addedCount = res.added_count || 0
      const skippedCount = res.skipped_count || 0
      const message = addedCount > 0 ? `已添加 ${addedCount} 人` : res.message || '没有新增成员'
      if (addedCount > 0) {
        ElMessage.success(skippedCount > 0 ? `${message}，跳过 ${skippedCount} 人` : message)
      } else {
        ElMessage.warning(skippedCount > 0 ? `${message}，跳过 ${skippedCount} 人` : message)
      }
      addMemberVisible.value = false
      await Promise.all([loadMembers(), loadData(), loadStats()])
    } finally {
      addMemberLoading.value = false
    }
  }

  const handleMuteMember = async (member: ChatMemberItem) => {
    if (!selectedGroup.value) return
    const { value } = await ElMessageBox.prompt(
      `请输入「${member.nickname || member.username}」的禁言时长（分钟）`,
      '禁言成员',
      {
        confirmButtonText: '确定禁言',
        cancelButtonText: '取消',
        inputValue: '60',
        inputPattern: /^\d+$/,
        inputErrorMessage: '请输入非负整数分钟',
        type: 'warning'
      }
    )
    const minutes = Number(value || 0)
    await updateChatMemberMute(selectedGroup.value.id, member.id, {
      is_muted: true,
      minutes
    })
    ElMessage.success('成员已禁言')
    await loadMembers()
  }

  const handleUnmuteMember = async (member: ChatMemberItem) => {
    if (!selectedGroup.value) return
    await updateChatMemberMute(selectedGroup.value.id, member.id, { is_muted: false })
    ElMessage.success('成员已解禁')
    await loadMembers()
  }

  const handleSetRole = async (member: ChatMemberItem, role: 1 | 2) => {
    if (!selectedGroup.value) return
    await updateChatMemberRole(selectedGroup.value.id, member.id, role)
    ElMessage.success('成员角色已更新')
    await loadMembers()
  }

  const handleReviewJoinRequest = async (row: ChatJoinRequestItem, approve: boolean) => {
    if (!selectedGroup.value) return
    await ElMessageBox.confirm(
      `确定${approve ? '通过' : '拒绝'}「${row.nickname || row.username || row.user_uuid}」的入群申请吗？`,
      approve ? '通过申请' : '拒绝申请',
      {
        confirmButtonText: approve ? '确定通过' : '确定拒绝',
        cancelButtonText: '取消',
        type: approve ? 'success' : 'warning'
      }
    )
    await reviewChatJoinRequest(selectedGroup.value.id, row.id, approve)
    ElMessage.success(approve ? '申请已通过' : '申请已拒绝')
    await Promise.all([loadJoinRequests(), loadMembers(), loadData(), loadStats()])
  }

  const handleTransferOwner = async (member: ChatMemberItem) => {
    // 转让群主会同时改变原群主与目标成员角色，完成后必须刷新详情和成员列表。
    if (!selectedGroup.value) return
    await ElMessageBox.confirm(
      `确定把群主转让给「${member.nickname || member.username}」吗？`,
      '转让群主',
      { confirmButtonText: '确定转让', cancelButtonText: '取消', type: 'warning' }
    )
    await transferChatOwner(selectedGroup.value.id, member.id)
    ElMessage.success('群主已转让')
    await Promise.all([loadDetail(selectedGroup.value.id), loadData()])
  }

  const handleRemoveMember = async (member: ChatMemberItem) => {
    if (!selectedGroup.value) return
    await ElMessageBox.confirm(
      `确定移除成员「${member.nickname || member.username}」吗？`,
      '移除成员',
      { confirmButtonText: '确定移除', cancelButtonText: '取消', type: 'warning' }
    )
    await removeChatMember(selectedGroup.value.id, member.id)
    ElMessage.success('成员已移除')
    await Promise.all([loadMembers(), loadData()])
  }

  const handleBan = async (row: ChatListItem) => {
    const { value } = await ElMessageBox.prompt(`确定封禁「${row.name}」吗？`, '封禁群', {
      confirmButtonText: '确定封禁',
      cancelButtonText: '取消',
      inputPlaceholder: '封禁原因（可选）',
      type: 'warning'
    })
    await banChat(row.id, value)
    ElMessage.success('群已封禁')
    await Promise.all([loadData(), loadStats()])
  }

  const handleUnban = async (row: ChatListItem) => {
    await ElMessageBox.confirm(`确定解封「${row.name}」吗？`, '解封群', {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'info'
    })
    await unbanChat(row.id)
    ElMessage.success('群已解封')
    await Promise.all([loadData(), loadStats()])
  }

  const handleDissolve = async (row: ChatListItem) => {
    await ElMessageBox.confirm(`确定解散「${row.name}」吗？所有成员会被移除。`, '解散群', {
      confirmButtonText: '确定解散',
      cancelButtonText: '取消',
      type: 'error'
    })
    await dissolveChat(row.id)
    ElMessage.success('群已解散')
    await Promise.all([loadData(), loadStats()])
  }

  const handleDelete = async (row: ChatListItem) => {
    await ElMessageBox.confirm(`确定删除「${row.name}」吗？此操作不可恢复。`, '删除群', {
      confirmButtonText: '确定删除',
      cancelButtonText: '取消',
      type: 'error'
    })
    await deleteChat(row.id)
    ElMessage.success('群已删除')
    await Promise.all([loadData(), loadStats()])
  }

  const getStatusText = (status: number) => {
    if (status === 1) return '已封禁'
    if (status === 2) return '已解散'
    return '正常'
  }

  const getStatusTag = (status: number) => {
    if (status === 1) return 'danger'
    if (status === 2) return 'warning'
    return 'success'
  }

  const getRoleText = (role: number) => {
    if (role === 3) return '群主'
    if (role === 2) return '管理员'
    return '成员'
  }

  const getRoleTag = (role: number) => {
    if (role === 3) return 'danger'
    if (role === 2) return 'warning'
    return 'info'
  }

  const getRequestStatusText = (status: number) => {
    if (status === 1) return '已通过'
    if (status === 2) return '已拒绝'
    return '待审批'
  }

  const getRequestStatusTag = (status: number) => {
    if (status === 1) return 'success'
    if (status === 2) return 'danger'
    return 'warning'
  }

  const formatTime = (value?: string) => {
    if (!value) return '-'
    const date = new Date(value)
    if (Number.isNaN(date.getTime())) return value
    return date.toLocaleString('zh-CN', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  onMounted(() => {
    loadStats()
    loadData()
  })
</script>

<style lang="scss" scoped>
  .group-manage-page {
    display: flex;
    min-height: 0;
    flex-direction: column;
    gap: 12px;
  }

  .stats-row {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 12px;
  }

  .stat-card :deep(.el-card__body) {
    padding: 16px;
  }

  .stat-content {
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .stat-icon {
    display: flex;
    width: 44px;
    height: 44px;
    align-items: center;
    justify-content: center;
    border-radius: 8px;
    font-size: 22px;

    &.primary {
      color: #2563eb;
      background: #dbeafe;
    }

    &.success {
      color: #059669;
      background: #d1fae5;
    }

    &.warning {
      color: #d97706;
      background: #fef3c7;
    }

    &.danger {
      color: #dc2626;
      background: #fee2e2;
    }
  }

  .stat-label {
    color: var(--art-gray-500);
    font-size: 13px;
  }

  .stat-value {
    margin-top: 2px;
    color: var(--art-gray-900);
    font-size: 24px;
    font-weight: 700;
  }

  .toolbar-card :deep(.el-card__body) {
    padding: 14px 16px;
  }

  .toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .toolbar-left {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .search-input {
    width: 260px;
  }

  .status-select {
    width: 130px;
  }

  .table-card {
    min-height: 0;
    flex: 1;
  }

  .table-card :deep(.el-card__body) {
    display: flex;
    height: 100%;
    min-height: 0;
    flex-direction: column;
    padding: 0;
  }

  .group-cell,
  .member-cell {
    display: flex;
    min-width: 0;
    align-items: center;
    gap: 12px;
  }

  .group-meta {
    min-width: 0;
  }

  .group-name,
  .member-name {
    overflow: hidden;
    color: var(--art-gray-900);
    font-weight: 600;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .group-desc,
  .member-username,
  .muted-text {
    overflow: hidden;
    color: var(--art-gray-500);
    font-size: 12px;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .strong-text {
    font-weight: 600;
  }

  .pagination-row {
    display: flex;
    justify-content: flex-end;
    padding: 14px 16px;

    &.compact {
      padding: 12px 0 0;
    }
  }

  .drawer-body {
    min-height: 520px;
  }

  .profile-form {
    max-width: 620px;
  }

  .form-tip {
    margin-left: 10px;
    color: var(--art-gray-500);
    font-size: 12px;
  }

  .switch-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px 18px;
    padding-left: 108px;
  }

  .member-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    margin-bottom: 12px;
  }

  .member-toolbar-left,
  .member-actions {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .member-search {
    width: 260px;
  }

  .drawer-footer {
    display: flex;
    justify-content: flex-end;
    gap: 10px;
  }

  @media (max-width: 900px) {
    .stats-row {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .toolbar,
    .toolbar-left,
    .member-toolbar,
    .member-toolbar-left,
    .member-actions {
      align-items: stretch;
      flex-direction: column;
    }

    .search-input,
    .status-select,
    .member-search {
      width: 100%;
    }

    .switch-grid {
      grid-template-columns: 1fr;
      padding-left: 0;
    }
  }
</style>
