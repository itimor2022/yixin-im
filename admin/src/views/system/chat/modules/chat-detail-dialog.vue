<!-- 会话详情对话框 -->
<template>
  <ElDialog
    v-model="visible"
    :title="dialogTitle"
    width="800px"
    destroy-on-close
    @close="handleClose"
  >
    <div v-loading="loading" class="chat-detail">
      <!-- 基本信息 -->
      <ElDescriptions :column="2" border>
        <ElDescriptionsItem label="ID">{{ chat?.id }}</ElDescriptionsItem>
        <ElDescriptionsItem label="UUID">
          <ElText truncated class="max-w-[200px]">{{ chat?.uuid }}</ElText>
        </ElDescriptionsItem>
        <ElDescriptionsItem label="名称">{{ chat?.name }}</ElDescriptionsItem>
        <ElDescriptionsItem label="类型">
          <ElTag :type="typeConfig.type" size="small">{{ typeConfig.text }}</ElTag>
        </ElDescriptionsItem>
        <ElDescriptionsItem label="状态">
          <ElTag :type="statusConfig.type" size="small">{{ statusConfig.text }}</ElTag>
        </ElDescriptionsItem>
        <ElDescriptionsItem label="成员数">{{ chat?.member_count }} 人</ElDescriptionsItem>
        <!-- 私聊不显示是否公开 -->
        <template v-if="!isPrivateChat">
          <ElDescriptionsItem label="是否公开">
            <ElTag :type="chat?.is_public ? 'success' : 'info'" size="small">
              {{ chat?.is_public ? '是' : '否' }}
            </ElTag>
          </ElDescriptionsItem>
        </template>
        <ElDescriptionsItem label="创建时间">{{ formatTime(chat?.created_at) }}</ElDescriptionsItem>
        <!-- 私聊不显示描述 -->
        <template v-if="!isPrivateChat">
          <ElDescriptionsItem label="描述" :span="2">
            {{ chat?.description || '暂无描述' }}
          </ElDescriptionsItem>
        </template>
        <template v-if="chat?.status === 1">
          <ElDescriptionsItem label="封禁原因" :span="2">
            <ElText type="danger">{{ chat?.ban_reason || '未提供原因' }}</ElText>
          </ElDescriptionsItem>
        </template>
      </ElDescriptions>

      <!-- 群组权限信息（仅群组/频道显示） -->
      <div v-if="!isPrivateChat" class="mt-4">
        <h4 class="text-base font-medium mb-2">群组设置</h4>
        <ElDescriptions :column="3" border size="small">
          <ElDescriptionsItem label="发送消息">
            <ElTag :type="chat?.can_send_message !== false ? 'success' : 'danger'" size="small">
              {{ chat?.can_send_message !== false ? '允许' : '禁止' }}
            </ElTag>
          </ElDescriptionsItem>
          <ElDescriptionsItem label="发送媒体">
            <ElTag :type="chat?.can_send_media !== false ? 'success' : 'danger'" size="small">
              {{ chat?.can_send_media !== false ? '允许' : '禁止' }}
            </ElTag>
          </ElDescriptionsItem>
          <ElDescriptionsItem label="发送链接">
            <ElTag :type="chat?.can_send_links !== false ? 'success' : 'danger'" size="small">
              {{ chat?.can_send_links !== false ? '允许' : '禁止' }}
            </ElTag>
          </ElDescriptionsItem>
          <ElDescriptionsItem label="添加成员">
            <ElTag :type="chat?.can_add_members ? 'success' : 'info'" size="small">
              {{ chat?.can_add_members ? '允许' : '仅管理员' }}
            </ElTag>
          </ElDescriptionsItem>
          <ElDescriptionsItem label="置顶消息">
            <ElTag :type="chat?.can_pin_messages ? 'success' : 'info'" size="small">
              {{ chat?.can_pin_messages ? '允许' : '仅管理员' }}
            </ElTag>
          </ElDescriptionsItem>
          <ElDescriptionsItem label="成员保护">
            <ElTag :type="chat?.member_protection ? 'warning' : 'info'" size="small">
              {{ chat?.member_protection ? '已开启' : '未开启' }}
            </ElTag>
          </ElDescriptionsItem>
          <ElDescriptionsItem label="加入审核">
            <ElTag :type="chat?.join_approval ? 'warning' : 'info'" size="small">
              {{ chat?.join_approval ? '需审核' : '直接加入' }}
            </ElTag>
          </ElDescriptionsItem>
          <ElDescriptionsItem label="在线人数">
            <span class="text-green-500 font-medium">{{ chat?.online_count || 0 }} 人</span>
          </ElDescriptionsItem>
          <ElDescriptionsItem v-if="chat?.join_approval" label="待审核申请">
            <ElTag v-if="chat?.pending_request_count && chat.pending_request_count > 0" type="danger" size="small">
              {{ chat.pending_request_count }} 条待处理
            </ElTag>
            <span v-else class="text-g-400">暂无</span>
          </ElDescriptionsItem>
        </ElDescriptions>
      </div>

      <!-- 群主信息（仅群组/频道显示） -->
      <div v-if="owner && !isPrivateChat" class="mt-4">
        <h4 class="text-base font-medium mb-2">{{ chat?.type === 3 ? '频道主' : '群主' }}信息</h4>
        <div class="flex items-center gap-3 p-3 bg-g-50 dark:bg-g-800 rounded-lg">
          <ElImage
            class="size-12 rounded-full"
            :src="getAvatarUrl(owner.avatar, owner.uuid)"
            fit="cover"
          />
          <div>
            <p class="font-medium">{{ owner.nickname || owner.username }}</p>
            <p class="text-sm text-g-500">@{{ owner.username }}</p>
          </div>
        </div>
      </div>

      <!-- 成员列表 -->
      <div class="mt-4">
        <div class="flex items-center justify-between mb-2">
          <h4 class="text-base font-medium"
            >{{ isPrivateChat ? '参与者' : '成员列表' }} ({{ memberTotal }} 人)</h4
          >
          <ElButton
            type="primary"
            link
            @click="loadMoreMembers"
            v-if="members.length < memberTotal"
          >
            加载更多
          </ElButton>
        </div>
        <ElTable :data="members" max-height="300" stripe>
          <ElTableColumn type="index" width="50" label="#" />
          <ElTableColumn label="用户" min-width="200">
            <template #default="{ row }">
              <div class="flex items-center gap-3">
                <ElImage
                  class="size-10 rounded-full"
                  :src="getAvatarUrl(row.avatar, row.user_uuid)"
                  fit="cover"
                />
                <div>
                  <p class="text-sm font-medium">{{ row.nickname || row.username }}</p>
                  <p class="text-xs text-g-400">@{{ row.username }}</p>
                </div>
              </div>
            </template>
          </ElTableColumn>
          <!-- 私聊不显示角色 -->
          <ElTableColumn v-if="!isPrivateChat" prop="role" label="角色" width="100">
            <template #default="{ row }">
              <ElTag :type="getRoleConfig(row.role).type" size="small">
                {{ getRoleConfig(row.role).text }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="joined_at" label="加入时间" width="160">
            <template #default="{ row }">
              {{ formatTime(row.joined_at) }}
            </template>
          </ElTableColumn>
          <!-- 私聊不显示移除操作 -->
          <ElTableColumn v-if="!isPrivateChat" label="操作" width="80" fixed="right">
            <template #default="{ row }">
              <ElButton
                v-if="row.role !== 3"
                type="danger"
                link
                size="small"
                @click="handleRemoveMember(row)"
              >
                移除
              </ElButton>
              <span v-else class="text-g-400 text-xs">-</span>
            </template>
          </ElTableColumn>
        </ElTable>
      </div>
    </div>

    <template #footer>
      <div class="flex justify-between">
        <div>
          <template v-if="chat?.type !== 1">
            <ElButton v-if="chat?.status !== 1" type="warning" @click="handleBan"> 封禁 </ElButton>
            <ElButton v-else type="success" @click="handleUnban"> 解封 </ElButton>
            <ElButton type="danger" @click="handleDissolve">解散</ElButton>
          </template>
        </div>
        <ElButton @click="visible = false">关闭</ElButton>
      </div>
    </template>
  </ElDialog>
</template>

<script setup lang="ts">
  import {
    getChatDetail,
    getChatMembers,
    removeChatMember,
    banChat,
    unbanChat,
    dissolveChat,
    ChatListItem,
    ChatMemberItem
  } from '@/api/admin'
  import { ElMessage, ElMessageBox, ElImage, ElText } from 'element-plus'
  import { getAvatarUrl } from '@/utils/url'

  const props = defineProps<{
    modelValue: boolean
    chatId: number | null
  }>()

  const emit = defineEmits<{
    (e: 'update:modelValue', value: boolean): void
    (e: 'refresh'): void
  }>()

  const visible = computed({
    get: () => props.modelValue,
    set: (val) => emit('update:modelValue', val)
  })

  const loading = ref(false)
  const chat = ref<ChatListItem | null>(null)
  const owner = ref<any>(null)
  const members = ref<ChatMemberItem[]>([])
  const memberTotal = ref(0)
  const memberPage = ref(1)

  const dialogTitle = computed(() => {
    if (!chat.value) return '会话详情'
    const typeNames: Record<number, string> = { 1: '私聊', 2: '群组', 3: '频道' }
    return `${typeNames[chat.value.type] || '会话'}详情 - ${chat.value.name}`
  })

  // 是否是私聊
  const isPrivateChat = computed(() => chat.value?.type === 1)

  // 格式化时间
  const formatTime = (time: string | undefined) => {
    if (!time) return '-'
    const date = new Date(time)
    return date.toLocaleString('zh-CN', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  const typeConfig = computed(() => {
    const configs: Record<number, { type: 'info' | 'primary' | 'warning'; text: string }> = {
      1: { type: 'info', text: '私聊' },
      2: { type: 'primary', text: '群组' },
      3: { type: 'warning', text: '频道' }
    }
    return configs[chat.value?.type || 0] || { type: 'info', text: '未知' }
  })

  const statusConfig = computed(() => {
    const configs: Record<number, { type: 'success' | 'danger' | 'warning'; text: string }> = {
      0: { type: 'success', text: '正常' },
      1: { type: 'danger', text: '已封禁' },
      2: { type: 'warning', text: '已解散' }
    }
    return configs[chat.value?.status || 0] || { type: 'success', text: '正常' }
  })

  const getRoleConfig = (role: number) => {
    const configs: Record<number, { type: 'danger' | 'warning' | 'info'; text: string }> = {
      1: { type: 'info', text: '成员' },
      2: { type: 'warning', text: '管理员' },
      3: { type: 'danger', text: '群主' }
    }
    return configs[role] || { type: 'info', text: '成员' }
  }

  // 加载会话详情
  const loadChatDetail = async () => {
    if (!props.chatId) return
    loading.value = true
    try {
      const res = await getChatDetail(props.chatId)
      chat.value = res.chat
      owner.value = res.owner
      members.value = res.members || []
      memberTotal.value = chat.value?.member_count || 0
    } catch (error) {
      console.error('加载会话详情失败:', error)
      ElMessage.error('加载详情失败')
    } finally {
      loading.value = false
    }
  }

  // 加载更多成员
  const loadMoreMembers = async () => {
    if (!props.chatId) return
    try {
      memberPage.value++
      const res = await getChatMembers(props.chatId, { page: memberPage.value, page_size: 50 })
      members.value.push(...res.list)
      memberTotal.value = res.total
    } catch (error) {
      console.error('加载成员失败:', error)
    }
  }

  // 移除成员
  const handleRemoveMember = async (member: ChatMemberItem) => {
    if (!props.chatId) return
    try {
      await ElMessageBox.confirm(
        `确定要移除成员 "${member.nickname || member.username}" 吗？`,
        '移除确认',
        { confirmButtonText: '确定', cancelButtonText: '取消', type: 'warning' }
      )
      await removeChatMember(props.chatId, member.id)
      ElMessage.success('已移除')
      members.value = members.value.filter((m) => m.id !== member.id)
      if (chat.value) chat.value.member_count--
      memberTotal.value--
    } catch (error: any) {
      if (error !== 'cancel') {
        ElMessage.error('移除失败')
      }
    }
  }

  // 封禁
  const handleBan = async () => {
    if (!props.chatId) return
    try {
      const { value: reason } = await ElMessageBox.prompt('请输入封禁原因（可选）', '封禁确认', {
        confirmButtonText: '确定封禁',
        cancelButtonText: '取消',
        type: 'warning',
        inputPlaceholder: '封禁原因...'
      })
      await banChat(props.chatId, reason)
      ElMessage.success('已封禁')
      emit('refresh')
      loadChatDetail()
    } catch (error: any) {
      if (error !== 'cancel') {
        ElMessage.error('封禁失败')
      }
    }
  }

  // 解封
  const handleUnban = async () => {
    if (!props.chatId) return
    try {
      await ElMessageBox.confirm('确定要解封该群组/频道吗？', '解封确认', {
        confirmButtonText: '确定',
        cancelButtonText: '取消',
        type: 'info'
      })
      await unbanChat(props.chatId)
      ElMessage.success('已解封')
      emit('refresh')
      loadChatDetail()
    } catch (error: any) {
      if (error !== 'cancel') {
        ElMessage.error('解封失败')
      }
    }
  }

  // 解散
  const handleDissolve = async () => {
    if (!props.chatId) return
    try {
      await ElMessageBox.confirm(
        '确定要解散该群组/频道吗？此操作不可恢复！所有成员将被移除。',
        '解散确认',
        { confirmButtonText: '确定解散', cancelButtonText: '取消', type: 'error' }
      )
      await dissolveChat(props.chatId)
      ElMessage.success('已解散')
      emit('refresh')
      visible.value = false
    } catch (error: any) {
      if (error !== 'cancel') {
        ElMessage.error('解散失败')
      }
    }
  }

  const handleClose = () => {
    chat.value = null
    owner.value = null
    members.value = []
    memberPage.value = 1
    memberTotal.value = 0
  }

  watch(
    () => props.modelValue,
    (val) => {
      if (val && props.chatId) {
        loadChatDetail()
      }
    }
  )
</script>

<style lang="scss" scoped>
  .chat-detail {
    :deep(.el-descriptions) {
      .el-descriptions__label {
        width: 100px;
      }
    }
  }
</style>
