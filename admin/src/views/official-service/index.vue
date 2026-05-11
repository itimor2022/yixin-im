<template>
  <div class="official-service-page">
    <ElCard>
      <template #header>
        <div style="display: flex; justify-content: space-between; align-items: center">
          <span style="font-weight: 600">官方客服</span>
          <ElButton v-if="!isDemoAdmin" type="primary" @click="showAddDialog">
            <ArtSvgIcon icon="ri:add-line" class="mr-1" />
            添加官方客服
          </ElButton>
        </div>
      </template>

      <ElAlert v-if="isDemoAdmin" type="warning" :closable="false" show-icon class="mb-4">
        您当前是演示管理员，只能查看官方客服列表
      </ElAlert>
      <ElAlert v-else type="info" :closable="false" show-icon class="mb-4">
        官方客服添加后会自动生成专属邀请码，新用户填写邀请码注册后将自动加好友并收到欢迎语
      </ElAlert>

      <ElTable
        :data="officialUsers"
        :row-class-name="getRowClassName"
        v-loading="loading"
        border
        stripe
      >
        <ElTableColumn type="index" width="60" label="#" />
        <ElTableColumn label="用户" min-width="220">
          <template #default="{ row }">
            <div class="flex items-center gap-2">
              <ElAvatar :size="36" :src="getAvatarUrl(row.avatar, row.user_uuid)" />
              <div>
                <p class="font-medium">{{ row.nickname || row.username }}</p>
                <p class="text-xs text-g-400">@{{ row.username }}</p>
              </div>
            </div>
          </template>
        </ElTableColumn>
        <ElTableColumn prop="user_uuid" label="UUID" width="300">
          <template #default="{ row }">
            <code class="text-xs">{{ row.user_uuid }}</code>
          </template>
        </ElTableColumn>
        <ElTableColumn prop="invite_code" label="专属邀请码" width="180">
          <template #default="{ row }">
            <div v-if="row.invite_code" class="flex items-center gap-2">
              <ElTooltip content="单击复制邀请码，双击直接修改" placement="top">
                <code
                  class="text-xs font-semibold cursor-pointer rounded px-1 py-0.5 hover:bg-blue-50"
                  title="点击复制邀请码，双击可直接修改"
                  @click="handleCopyInviteCode(row.invite_code)"
                  @dblclick.stop="handleEditInviteCode(row)"
                >
                  {{ row.invite_code }}
                </code>
              </ElTooltip>
              <ElButton
                link
                type="primary"
                size="small"
                @click="handleCopyInviteCode(row.invite_code)"
              >
                {{ copiedInviteCode === row.invite_code ? '已复制' : '复制' }}
              </ElButton>
            </div>
            <span v-else class="text-g-400">-</span>
          </template>
        </ElTableColumn>
        <ElTableColumn
          prop="welcome_message"
          label="欢迎语"
          min-width="220"
          show-overflow-tooltip
        />
        <ElTableColumn prop="remark" label="备注" width="150" />
        <ElTableColumn label="旗下用户" width="110">
          <template #default="{ row }">
            <ElButton link type="primary" size="small" @click="handleViewInvitees(row)"
              >查看</ElButton
            >
          </template>
        </ElTableColumn>
        <ElTableColumn label="状态" width="90">
          <template #default="{ row }">
            <ElTag :type="row.is_service_enabled !== false ? 'success' : 'danger'" size="small">
              {{ row.is_service_enabled !== false ? '启用' : '停用' }}
            </ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn v-if="!isDemoAdmin" label="操作" width="280" fixed="right">
          <template #default="{ row }">
            <ElButton
              link
              size="small"
              :type="row.is_service_enabled !== false ? 'warning' : 'success'"
              @click="handleToggleStatus(row)"
            >
              {{ row.is_service_enabled !== false ? '停用' : '启用' }}
            </ElButton>
            <ElButton type="primary" link size="small" @click="handleEditWelcome(row)"
              >欢迎语</ElButton
            >
            <ElButton type="primary" link size="small" @click="handleEditInviteCode(row)"
              >邀请码</ElButton
            >
            <ElButton type="danger" link size="small" @click="handleRemove(row)">移除</ElButton>
          </template>
        </ElTableColumn>
      </ElTable>
    </ElCard>

    <ElDialog v-model="addDialogVisible" title="添加官方客服" width="500px">
      <ElForm :model="addForm" label-width="90px">
        <ElFormItem label="用户" required>
          <ElInput v-model="addForm.username" placeholder="输入用户名（如：user1）" />
        </ElFormItem>
        <ElFormItem label="邀请码">
          <ElInput
            v-model="addForm.invite_code"
            placeholder="自定义邀请码（6-12位字母数字，可选）"
          />
        </ElFormItem>
        <ElFormItem label="欢迎语">
          <ElInput
            v-model="addForm.welcome_message"
            type="textarea"
            :rows="2"
            placeholder="新用户注册后自动发送给对方"
          />
        </ElFormItem>
        <ElFormItem label="备注">
          <ElInput v-model="addForm.remark" placeholder="备注说明（可选）" />
        </ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="addDialogVisible = false">取消</ElButton>
        <ElButton type="primary" :loading="adding" @click="handleAdd">添加</ElButton>
      </template>
    </ElDialog>

    <ElDialog
      v-model="inviteeDialogVisible"
      :title="`${inviteeDialogTitle} · 旗下注册用户`"
      width="820px"
    >
      <ElAlert :closable="false" show-icon type="info" class="mb-4">
        展示通过该官方客服专属邀请码注册并完成绑定的用户
      </ElAlert>
      <ElTable :data="invitees" v-loading="inviteeLoading" border stripe max-height="420">
        <ElTableColumn type="index" width="60" label="#" />
        <ElTableColumn label="用户" min-width="220">
          <template #default="{ row }">
            <div class="flex items-center gap-2">
              <ElAvatar :size="34" :src="getAvatarUrl(row.avatar, row.user_uuid)" />
              <div>
                <p class="font-medium">{{ row.nickname || row.username }}</p>
                <p class="text-xs text-g-400">@{{ row.username }}</p>
              </div>
            </div>
          </template>
        </ElTableColumn>
        <ElTableColumn prop="user_uuid" label="UUID" width="300">
          <template #default="{ row }">
            <code class="text-xs">{{ row.user_uuid }}</code>
          </template>
        </ElTableColumn>
        <ElTableColumn prop="invite_code" label="邀请码" width="120" />
        <ElTableColumn label="绑定时间" width="170">
          <template #default="{ row }">
            <span class="text-xs">{{ formatTime(row.registered_at) }}</span>
          </template>
        </ElTableColumn>
      </ElTable>
      <div class="mt-3 text-sm text-g-400">共 {{ invitees.length }} 人</div>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
  import { ref, reactive, onMounted } from 'vue'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import { getAvatarUrl } from '@/utils/url'
  import { usePermission } from '@/hooks/usePermission'
  import {
    getOfficialUsers,
    getOfficialUserInvitees,
    addOfficialServiceUserByUsername,
    updateOfficialUser,
    removeOfficialUser,
    type OfficialUser,
    type OfficialInvitee
  } from '@/api/admin'

  defineOptions({ name: 'OfficialService' })

  const loading = ref(false)
  const adding = ref(false)
  const officialUsers = ref<OfficialUser[]>([])
  const { isDemoAdmin } = usePermission()
  const addDialogVisible = ref(false)
  const inviteeDialogVisible = ref(false)
  const inviteeLoading = ref(false)
  const inviteeDialogTitle = ref('')
  const invitees = ref<OfficialInvitee[]>([])
  const highlightRowId = ref<number | null>(null)
  const copiedInviteCode = ref('')
  let highlightTimer: ReturnType<typeof setTimeout> | null = null
  let copiedTimer: ReturnType<typeof setTimeout> | null = null
  const addForm = reactive({ username: '', invite_code: '', welcome_message: '', remark: '' })

  const formatTime = (value?: string) => {
    if (!value) return '-'
    const date = new Date(value)
    if (Number.isNaN(date.getTime())) return value
    const pad = (n: number) => (n < 10 ? `0${n}` : `${n}`)
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`
  }

  const markRowHighlight = (rowId: number) => {
    highlightRowId.value = rowId
    if (highlightTimer) clearTimeout(highlightTimer)
    highlightTimer = setTimeout(() => {
      highlightRowId.value = null
      highlightTimer = null
    }, 2200)
  }

  const getRowClassName = ({ row }: { row: OfficialUser }) =>
    row.id === highlightRowId.value ? 'official-service-row-highlight' : ''

  const loadUsers = async () => {
    loading.value = true
    try {
      officialUsers.value = (await getOfficialUsers()) || []
    } catch (error) {
      console.error('加载官方客服失败:', error)
    } finally {
      loading.value = false
    }
  }

  const showAddDialog = () => {
    addForm.username = ''
    addForm.invite_code = ''
    addForm.welcome_message = ''
    addForm.remark = ''
    addDialogVisible.value = true
  }

  const handleAdd = async () => {
    const username = addForm.username.trim()
    const inviteCode = addForm.invite_code.trim()
    if (!username) return ElMessage.warning('请输入用户名')
    if (inviteCode && !/^[A-Za-z0-9]{6,12}$/.test(inviteCode))
      return ElMessage.warning('自定义邀请码需为6-12位字母数字')
    adding.value = true
    try {
      await addOfficialServiceUserByUsername(username, {
        invite_code: inviteCode || undefined,
        welcome_message: addForm.welcome_message,
        remark: addForm.remark
      })
      ElMessage.success('添加成功')
      addDialogVisible.value = false
      loadUsers()
    } catch (error: any) {
      ElMessage.error(error?.message || '添加失败')
    } finally {
      adding.value = false
    }
  }

  const handleCopyInviteCode = async (inviteCode?: string, options?: { silent?: boolean }) => {
    if (!inviteCode) return false
    try {
      await navigator.clipboard.writeText(inviteCode)
      copiedInviteCode.value = inviteCode
      if (copiedTimer) clearTimeout(copiedTimer)
      copiedTimer = setTimeout(() => {
        copiedInviteCode.value = ''
        copiedTimer = null
      }, 1600)
      if (!options?.silent) ElMessage.success('邀请码已复制')
      return true
    } catch {
      if (!options?.silent) ElMessage.error('复制失败')
      return false
    }
  }

  const handleToggleStatus = async (row: OfficialUser) => {
    try {
      const enabled = row.is_service_enabled !== false
      await updateOfficialUser(row.id, { is_service_enabled: !enabled })
      ElMessage.success('状态已更新')
      loadUsers()
    } catch (error: any) {
      ElMessage.error(error?.message || '更新失败')
    }
  }

  const handleEditWelcome = async (row: OfficialUser) => {
    try {
      const { value } = await ElMessageBox.prompt('请输入欢迎语', '编辑欢迎语', {
        inputValue: row.welcome_message || '',
        inputType: 'textarea',
        inputPlaceholder: '请输入官方客服欢迎语'
      })
      await updateOfficialUser(row.id, { welcome_message: value || '' })
      ElMessage.success('欢迎语已更新')
      loadUsers()
    } catch (error: any) {
      if (error !== 'cancel') ElMessage.error(error?.message || '更新失败')
    }
  }

  const handleEditInviteCode = async (row: OfficialUser) => {
    try {
      const { value } = await ElMessageBox.prompt('请输入自定义邀请码', '修改邀请码', {
        inputValue: row.invite_code || '',
        inputPlaceholder: '6-12位字母数字',
        inputValidator: (value) => {
          const inviteCode = value.trim()
          if (!inviteCode) return '请输入邀请码'
          if (!/^[A-Za-z0-9]{6,12}$/.test(inviteCode)) return '自定义邀请码需为6-12位字母数字'
          return true
        }
      })
      const nextInviteCode = value.trim()
      await updateOfficialUser(row.id, { invite_code: nextInviteCode })
      const copied = await handleCopyInviteCode(nextInviteCode, { silent: true })
      markRowHighlight(row.id)
      ElMessage.success(copied ? '邀请码已更新，并已复制' : '邀请码已更新')
      loadUsers()
    } catch (error: any) {
      if (error !== 'cancel') ElMessage.error(error?.message || '更新失败')
    }
  }

  const handleRemove = async (row: OfficialUser) => {
    try {
      await ElMessageBox.confirm(
        `确定要移除官方客服 "${row.nickname || row.username}" 吗？`,
        '移除确认'
      )
      await removeOfficialUser(row.id)
      ElMessage.success('已移除')
      loadUsers()
    } catch (error: any) {
      if (error !== 'cancel') ElMessage.error(error?.message || '移除失败')
    }
  }

  const handleViewInvitees = async (row: OfficialUser) => {
    inviteeDialogTitle.value = row.nickname || row.username || '官方客服'
    inviteeDialogVisible.value = true
    inviteeLoading.value = true
    invitees.value = []
    try {
      const result = await getOfficialUserInvitees(row.id)
      invitees.value = result?.list || []
    } catch (error: any) {
      ElMessage.error(error?.message || '加载失败')
    } finally {
      inviteeLoading.value = false
    }
  }

  onMounted(loadUsers)
</script>

<style scoped>
  .official-service-page {
    width: 100%;
  }
  :deep(.official-service-row-highlight) {
    animation: official-service-row-flash 2.2s ease;
  }
  @keyframes official-service-row-flash {
    0% {
      background-color: rgba(59, 130, 246, 0.22);
    }
    100% {
      background-color: transparent;
    }
  }
</style>
