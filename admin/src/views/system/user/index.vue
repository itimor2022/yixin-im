<!-- 用户管理页面 -->
<template>
  <div class="user-page art-full-height">
    <!-- 搜索栏 -->
    <UserSearch v-model="searchForm" @search="handleSearch" @reset="resetSearchParams"></UserSearch>

    <ElCard class="art-table-card" shadow="never">
      <!-- 表格头部 -->
      <ArtTableHeader v-model:columns="columnChecks" :loading="loading" @refresh="handleRefresh">
        <template #left>
          <div class="flex items-center gap-4">
            <span class="text-g-500">
              共 <span class="text-primary font-bold">{{ pagination.total }}</span> 位用户
            </span>
            <ElDivider direction="vertical" />
            <span class="text-xs text-g-400">
              <span class="inline-flex items-center gap-1">
                <span
                  :class="[
                    'size-2 rounded-full',
                    loading ? 'bg-yellow-500 animate-pulse' : 'bg-green-500'
                  ]"
                ></span>
                {{ lastUpdateTime ? `最后更新: ${lastUpdateTime}` : '实时监控中' }}
              </span>
            </span>
          </div>
        </template>
      </ArtTableHeader>

      <!-- 表格 -->
      <ArtTable
        :loading="loading"
        :data="data"
        :columns="columns"
        :pagination="pagination"
        @pagination:size-change="handleSizeChange"
        @pagination:current-change="handleCurrentChange"
      >
      </ArtTable>

      <!-- 编辑用户弹窗 -->
      <UserDialog
        v-model:visible="dialogVisible"
        :type="dialogType"
        :user-data="currentUserData"
        @submit="handleDialogSubmit"
      />

      <ElDialog v-model="diagnosticVisible" title="用户诊断" width="920px" destroy-on-close>
        <div v-if="diagnosticData" class="diagnostic-panel">
          <div class="diagnostic-grid">
            <ElCard shadow="never">
              <template #header>概览</template>
              <ElDescriptions :column="2" border size="small">
                <ElDescriptionsItem label="用户">
                  {{ diagnosticData.user.nickname || diagnosticData.user.username }}
                </ElDescriptionsItem>
                <ElDescriptionsItem label="UUID">
                  <span class="font-mono">{{ diagnosticData.user.uuid }}</span>
                </ElDescriptionsItem>
                <ElDescriptionsItem label="在线">
                  <ElTag :type="diagnosticData.user.is_online ? 'success' : 'info'">
                    {{ diagnosticData.user.is_online ? '在线' : '离线' }}
                  </ElTag>
                </ElDescriptionsItem>
                <ElDescriptionsItem label="诊断时间">
                  {{ diagnosticData.summary.diagnosed_at || '-' }}
                </ElDescriptionsItem>
                <ElDescriptionsItem label="设备">
                  {{ diagnosticData.summary.active_device_count }} /
                  {{ diagnosticData.summary.device_count }} 活跃
                </ElDescriptionsItem>
                <ElDescriptionsItem label="推送">
                  {{ diagnosticData.summary.push_bound_count }} 个设备已绑定
                </ElDescriptionsItem>
                <ElDescriptionsItem label="会话/联系人">
                  {{ diagnosticData.summary.chat_count }} /
                  {{ diagnosticData.summary.contact_count }}
                </ElDescriptionsItem>
                <ElDescriptionsItem label="未读">
                  {{ diagnosticData.summary.unread_total }}
                </ElDescriptionsItem>
              </ElDescriptions>
            </ElCard>

            <ElCard shadow="never">
              <template #header>检查项</template>
              <div class="diagnostic-checks">
                <ElAlert
                  v-for="item in diagnosticData.checks"
                  :key="item.title"
                  :title="item.title"
                  :description="item.detail"
                  :type="checkAlertType(item.level)"
                  :closable="false"
                  show-icon
                />
              </div>
            </ElCard>
          </div>

          <ElCard shadow="never" class="mt-4">
            <template #header>设备与推送</template>
            <ElTable :data="diagnosticData.devices" size="small" border>
              <ElTableColumn prop="device_type" label="类型" width="90" />
              <ElTableColumn prop="device_name" label="设备" min-width="140" />
              <ElTableColumn prop="device_ip" label="IP" width="130" />
              <ElTableColumn prop="push_channel" label="推送渠道" width="100" />
              <ElTableColumn label="Token" width="110">
                <template #default="{ row }">
                  <ElTag :type="row.push_token_bound ? 'success' : 'warning'" size="small">
                    {{ row.push_token_bound ? `已绑定 ${row.push_token_length}` : '未绑定' }}
                  </ElTag>
                </template>
              </ElTableColumn>
              <ElTableColumn label="最近推送" min-width="220" show-overflow-tooltip>
                <template #default="{ row }">
                  <div v-if="row.last_push">
                    <ElTag :type="row.last_push.success ? 'success' : 'danger'" size="small">
                      {{ row.last_push.success ? '成功' : '失败' }}
                    </ElTag>
                    <span class="ml-2 text-xs text-g-500">
                      {{ row.last_push.occurred_at || '-' }}
                    </span>
                    <div v-if="row.last_push.error" class="text-xs text-red-500 mt-1">
                      {{ row.last_push.error }}
                    </div>
                  </div>
                  <span v-else class="text-xs text-g-400">暂无记录</span>
                </template>
              </ElTableColumn>
              <ElTableColumn prop="last_active" label="最后活跃" width="170" />
            </ElTable>
          </ElCard>

          <ElCard shadow="never" class="mt-4">
            <template #header>最近推送记录</template>
            <ElTable :data="diagnosticData.push_logs || []" size="small" border>
              <ElTableColumn prop="occurred_at" label="时间" width="170" />
              <ElTableColumn prop="channel" label="渠道" width="90" />
              <ElTableColumn label="结果" width="90">
                <template #default="{ row }">
                  <ElTag :type="row.success ? 'success' : 'danger'" size="small">
                    {{ row.success ? '成功' : '失败' }}
                  </ElTag>
                </template>
              </ElTableColumn>
              <ElTableColumn prop="device_key" label="设备" min-width="140" show-overflow-tooltip />
              <ElTableColumn prop="title" label="标题" min-width="120" show-overflow-tooltip />
              <ElTableColumn prop="error" label="错误" min-width="260" show-overflow-tooltip />
            </ElTable>
          </ElCard>

          <ElCard shadow="never" class="mt-4">
            <template #header>最近会话</template>
            <ElTable :data="diagnosticData.recent_chats" size="small" border>
              <ElTableColumn prop="chat_id" label="Chat ID" width="90" />
              <ElTableColumn prop="last_msg_seq" label="Seq" width="90" />
              <ElTableColumn
                prop="last_msg_text"
                label="最后消息"
                min-width="220"
                show-overflow-tooltip
              />
              <ElTableColumn prop="unread_count" label="未读" width="80" />
              <ElTableColumn prop="last_msg_time" label="时间" width="170" />
            </ElTable>
          </ElCard>
        </div>
        <div v-else class="py-8 text-center text-g-400">正在加载诊断数据...</div>
        <template #footer>
          <ElButton @click="diagnosticVisible = false">关闭</ElButton>
          <ElButton
            type="primary"
            :loading="testPushLoading"
            :disabled="!diagnosticData || diagnosticData.summary.push_bound_count === 0"
            @click="handleTestPush"
          >
            发送测试推送
          </ElButton>
        </template>
      </ElDialog>
    </ElCard>
  </div>
</template>

<script setup lang="ts">
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { useTable } from '@/hooks/core/useTable'
  import {
    fetchGetUserList,
    kickUser,
    banUser,
    unbanUser,
    UserTableListItem
  } from '@/api/system-manage'
  import {
    freezeUser,
    unfreezeUser,
    resetUserPassword,
    getUserDiagnostics,
    sendUserTestPush,
    UserDiagnosticResponse
  } from '@/api/admin'
  import UserSearch from './modules/user-search.vue'
  import UserDialog from './modules/user-dialog.vue'
  import { ElTag, ElMessageBox, ElMessage, ElAvatar, ElDivider } from 'element-plus'
  import { DialogType } from '@/types'
  import { fixImageUrl } from '@/utils/url'
  import { usePermission } from '@/hooks/usePermission'
  import { useRouter } from 'vue-router'

  defineOptions({ name: 'UserList' })

  const { isDemoAdmin } = usePermission()
  const router = useRouter()

  // 获取头像URL
  const getAvatarUrl = (row: UserTableListItem): string => {
    if (row.avatar) {
      return fixImageUrl(row.avatar)
    }
    return `https://api.dicebear.com/7.x/avataaars/svg?seed=${row.id}`
  }

  // 最后更新时间
  const lastUpdateTime = ref('')

  // 弹窗相关
  const dialogType = ref<DialogType>('edit')
  const dialogVisible = ref(false)
  const currentUserData = ref<Partial<UserTableListItem>>({})
  const diagnosticVisible = ref(false)
  const diagnosticData = ref<UserDiagnosticResponse | null>(null)
  const testPushLoading = ref(false)

  // 搜索表单
  const searchForm = ref({
    userName: undefined,
    status: '', // 默认显示所有状态
    onlineOnly: false
  })

  // 状态配置（支持数字和字符串类型）
  const STATUS_CONFIG: Record<
    string | number,
    { type: 'danger' | 'success' | 'warning' | 'info'; text: string; color: string }
  > = {
    0: { type: 'danger', text: '禁用', color: '#ef4444' },
    1: { type: 'success', text: '正常', color: '#22c55e' },
    2: { type: 'warning', text: '待审核', color: '#f59e0b' },
    3: { type: 'warning', text: '封禁中', color: '#f97316' } // 封禁状态：可登录但不能发消息
  }

  // 获取状态配置（支持数字和字符串）
  const getStatusConfig = (status: number | string) => {
    const key = typeof status === 'string' ? parseInt(status) : status
    return STATUS_CONFIG[key] || { type: 'info' as const, text: '未知', color: '#9ca3af' }
  }

  // 格式化时间显示
  const formatTime = (time: string) => {
    if (!time) return '-'
    const date = new Date(time)
    const now = new Date()
    const diff = now.getTime() - date.getTime()
    const days = Math.floor(diff / (1000 * 60 * 60 * 24))

    if (days === 0) {
      return '今天 ' + date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
    } else if (days === 1) {
      return '昨天 ' + date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
    } else if (days < 7) {
      return `${days}天前`
    }
    return date.toLocaleDateString('zh-CN', { month: '2-digit', day: '2-digit' })
  }

  const {
    columns,
    columnChecks,
    data,
    loading,
    pagination,
    getData,
    searchParams,
    resetSearchParams,
    handleSizeChange,
    handleCurrentChange,
    refreshData,
    refreshSoft
  } = useTable({
    core: {
      apiFn: fetchGetUserList,
      apiParams: {
        current: 1,
        size: 20,
        ...searchForm.value
      },
      columnsFactory: () => [
        { type: 'index', width: 70, label: '序号', align: 'center' },
        {
          prop: 'userInfo',
          label: '用户信息',
          minWidth: 280,
          formatter: (row) => {
            return h('div', { class: 'user-info-cell flex items-center py-2' }, [
              // 头像容器 - 带在线状态
              h('div', { class: 'avatar-wrapper relative' }, [
                h(ElAvatar, {
                  size: 48,
                  src: getAvatarUrl(row),
                  class: 'border-2 border-gray-100'
                }),
                // 在线状态指示点
                h('span', {
                  class: `absolute bottom-0 right-0 size-3.5 rounded-full border-2 border-white ${row.isOnline ? 'bg-green-500' : 'bg-gray-300'}`
                })
              ]),
              // 用户信息
              h('div', { class: 'ml-4 flex-1' }, [
                h('div', { class: 'flex items-center gap-2' }, [
                  h(
                    'span',
                    { class: 'font-semibold text-base text-g-800' },
                    row.userName || '未设置'
                  ),
                  row.nickname && h('span', { class: 'text-sm text-g-400' }, `(${row.nickname})`),
                  // 封禁状态标识
                  Number(row.status) === 3 &&
                    h(
                      'span',
                      {
                        class: 'text-xs px-1.5 py-0.5 bg-orange-100 text-orange-600 rounded'
                      },
                      '封禁中'
                    )
                ]),
                h('div', { class: 'flex items-center gap-3 mt-1.5' }, [
                  h(
                    'span',
                    { class: 'text-xs text-g-400 font-mono bg-gray-50 px-2 py-0.5 rounded' },
                    'ID: ' + (row.uuid?.slice(0, 8) || row.id)
                  ),
                  row.phone && h('span', { class: 'text-xs text-g-400' }, row.phone),
                  // 显示封禁原因
                  row.banReason &&
                    h('span', { class: 'text-xs text-orange-500' }, `封禁原因: ${row.banReason}`)
                ])
              ])
            ])
          }
        },
        {
          prop: 'status',
          label: '状态',
          width: 100,
          align: 'center',
          formatter: (row) => {
            const statusConfig = getStatusConfig(row.status)
            return h(
              ElTag,
              {
                type: statusConfig.type,
                size: 'default',
                effect: 'light',
                round: true
              },
              () => statusConfig.text
            )
          }
        },
        {
          prop: 'device',
          label: '设备 / IP',
          minWidth: 200,
          formatter: (row) => {
            if (!row.deviceType || row.deviceType === '-' || row.deviceType === 'unknown') {
              return h('span', { class: 'text-g-300' }, '—')
            }

            // 设备类型配置 - 使用 ri: 前缀格式
            const deviceConfigs: Record<
              string,
              { icon: string; color: string; bg: string; name: string }
            > = {
              ios: { icon: 'ri:apple-fill', color: '#000', bg: '#f3f4f6', name: 'iPhone' },
              android: {
                icon: 'ri:android-fill',
                color: '#3ddc84',
                bg: '#dcfce7',
                name: 'Android'
              },
              macos: { icon: 'ri:macbook-line', color: '#64748b', bg: '#f1f5f9', name: 'Mac' },
              windows: {
                icon: 'ri:windows-fill',
                color: '#0078d4',
                bg: '#dbeafe',
                name: 'Windows'
              },
              linux: { icon: 'ri:ubuntu-fill', color: '#e95420', bg: '#ffedd5', name: 'Linux' },
              web: { icon: 'ri:global-line', color: '#6366f1', bg: '#e0e7ff', name: 'Web' }
            }

            const deviceType = row.deviceType?.toLowerCase() || 'unknown'
            const config = deviceConfigs[deviceType] || {
              icon: 'ri:smartphone-line',
              color: '#9ca3af',
              bg: '#f3f4f6',
              name: row.deviceType
            }
            const pushChannelText =
              row.pushChannel && row.pushChannel !== '-'
                ? String(row.pushChannel).toUpperCase()
                : '未上报'
            const pushStateText = row.pushTokenBound
              ? `Push ${pushChannelText} · token:${row.pushTokenLength || 0}`
              : `Push ${pushChannelText} · 未绑定`

            return h('div', { class: 'device-info' }, [
              h('div', { class: 'flex items-center gap-2' }, [
                h(
                  'span',
                  {
                    class: 'inline-flex items-center justify-center size-8 rounded-lg',
                    style: { backgroundColor: config.bg }
                  },
                  [
                    h(ArtSvgIcon, {
                      icon: config.icon,
                      style: { color: config.color, fontSize: '18px' }
                    })
                  ]
                ),
                h('div', {}, [
                  h(
                    'p',
                    { class: 'text-sm font-medium text-g-700' },
                    row.deviceName || config.name
                  ),
                  h('p', { class: 'text-xs text-g-400 mt-0.5 font-mono' }, row.deviceIp || '-'),
                  h('p', { class: 'text-xs text-g-500 mt-0.5 font-mono' }, pushStateText)
                ])
              ])
            ])
          }
        },
        {
          prop: 'lastSeen',
          label: '最后活跃',
          width: 140,
          align: 'center',
          formatter: (row) => {
            if (row.isOnline) {
              return h('div', { class: 'flex items-center justify-center gap-1.5' }, [
                h('span', { class: 'relative flex h-2 w-2' }, [
                  h('span', {
                    class:
                      'animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75'
                  }),
                  h('span', { class: 'relative inline-flex rounded-full h-2 w-2 bg-green-500' })
                ]),
                h('span', { class: 'text-green-600 font-medium' }, '在线')
              ])
            }
            return h('span', { class: 'text-g-400' }, formatTime(row.lastSeen))
          }
        },
        {
          prop: 'serviceBind',
          label: '归属客服 / 邀请码',
          minWidth: 210,
          formatter: (row) => {
            if (!row.serviceUsername && !row.serviceInviteCode) {
              return h('span', { class: 'text-g-300' }, '—')
            }
            const serviceName = row.serviceNickname || row.serviceUsername || '未知客服'
            return h('div', { class: 'py-1' }, [
              h('div', { class: 'text-sm text-g-700 font-medium' }, serviceName),
              h(
                'div',
                { class: 'text-xs text-g-400 mt-1 font-mono' },
                `邀请码: ${row.serviceInviteCode || '-'}`
              )
            ])
          }
        },
        {
          prop: 'createTime',
          label: '注册时间',
          width: 140,
          align: 'center',
          sortable: true,
          formatter: (row) => {
            return h('span', { class: 'text-g-500 text-sm' }, row.createTime || '-')
          }
        },
        {
          prop: 'operation',
          label: '操作',
          width: 200,
          fixed: 'right',
          align: 'center',
          formatter: (row) => {
            // 演示管理员只显示查看提示
            if (isDemoAdmin.value) {
              return h('span', { class: 'text-xs text-gray-400' }, '仅查看')
            }
            return h(
              'div',
              { class: 'flex justify-center gap-1 flex-wrap' },
              [
                h(ArtButtonTable, {
                  type: 'edit',
                  onClick: () => showDialog('edit', row)
                }),
                h(ArtButtonTable, {
                  icon: 'ri:chat-history-line',
                  iconClass: 'bg-blue-100 text-blue-500',
                  onClick: () =>
                    router.push({
                      path: '/chat/message-search',
                      query: { sender_id: row.uuid, name: row.userName }
                    })
                }),
                h(ArtButtonTable, {
                  icon: 'ri:pulse-line',
                  iconClass: 'bg-cyan-100 text-cyan-500',
                  onClick: () => handleDiagnostics(row)
                }),
                h(ArtButtonTable, {
                  icon: 'ri:key-2-line',
                  iconClass: 'bg-purple-100 text-purple-500',
                  onClick: () => handleResetPassword(row)
                }),
                // 封禁/解封按钮 - 使用自定义图标和颜色
                Number(row.status) !== 3
                  ? h(ArtButtonTable, {
                      icon: 'ri:forbid-line',
                      iconClass: 'bg-orange-100 text-orange-500',
                      onClick: () => handleBanUser(row)
                    })
                  : h(ArtButtonTable, {
                      icon: 'ri:check-line',
                      iconClass: 'bg-green-100 text-green-500',
                      onClick: () => handleUnbanUser(row)
                    }),
                // 冻结/解冻按钮（status 0 = 已冻结）
                Number(row.status) !== 0
                  ? h(ArtButtonTable, {
                      icon: 'ri:lock-line',
                      iconClass: 'bg-red-100 text-red-500',
                      onClick: () => handleFreezeUser(row)
                    })
                  : h(ArtButtonTable, {
                      icon: 'ri:lock-unlock-line',
                      iconClass: 'bg-blue-100 text-blue-500',
                      onClick: () => handleUnfreezeUser(row)
                    }),
                // 只有在线用户显示强制下线按钮
                row.isOnline &&
                  h(ArtButtonTable, {
                    type: 'delete',
                    onClick: () => handleKickUser(row)
                  })
              ].filter(Boolean)
            )
          }
        }
      ]
    }
  })

  // 搜索处理
  const handleSearch = (params: Record<string, any>) => {
    Object.assign(searchParams, {
      userName: params.userName,
      status: params.status,
      onlineOnly: params.onlineOnly
    })
    getData()
    updateLastTime()
  }

  // 手动刷新
  const handleRefresh = () => {
    refreshData()
    updateLastTime()
  }

  // 更新最后刷新时间
  const updateLastTime = () => {
    const now = new Date()
    lastUpdateTime.value = now.toLocaleTimeString('zh-CN', {
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    })
  }

  // 显示编辑弹窗
  const showDialog = (type: DialogType, row?: UserTableListItem): void => {
    dialogType.value = type
    currentUserData.value = row || {}
    nextTick(() => {
      dialogVisible.value = true
    })
  }

  // 强制下线
  const checkAlertType = (level: string): 'success' | 'info' | 'warning' | 'error' => {
    if (level === 'ok') return 'success'
    if (level === 'error') return 'error'
    if (level === 'warning') return 'warning'
    return 'info'
  }

  const handleDiagnostics = async (row: UserTableListItem): Promise<void> => {
    diagnosticData.value = null
    diagnosticVisible.value = true
    testPushLoading.value = false
    try {
      diagnosticData.value = await getUserDiagnostics(row.id)
    } catch (error) {
      diagnosticVisible.value = false
      console.error('用户诊断失败:', error)
      ElMessage.error('用户诊断失败')
    }
  }

  const handleTestPush = async (): Promise<void> => {
    const userId = diagnosticData.value?.user.id
    if (!userId) return

    testPushLoading.value = true
    try {
      const result = await sendUserTestPush(userId)
      ElMessage.success(`测试推送已提交，目标设备 ${result.push_device_count} 个`)
      window.setTimeout(async () => {
        try {
          diagnosticData.value = await getUserDiagnostics(userId)
        } catch (error) {
          console.error('刷新推送诊断失败:', error)
        }
      }, 1500)
    } catch (error) {
      console.error('测试推送失败:', error)
      ElMessage.error('测试推送失败')
    } finally {
      testPushLoading.value = false
    }
  }

  const handleKickUser = (row: UserTableListItem): void => {
    ElMessageBox.confirm(`确定要将用户 "${row.userName}" 强制下线吗？`, '强制下线', {
      confirmButtonText: '确定',
      cancelButtonText: '取消',
      type: 'warning'
    }).then(async () => {
      try {
        await kickUser(row.id)
        ElMessage.success('已强制下线')
        refreshData()
      } catch (error) {
        console.error('强制下线失败:', error)
      }
    })
  }

  // 封禁用户
  const handleBanUser = async (row: UserTableListItem): Promise<void> => {
    try {
      const { value: reason } = await ElMessageBox.prompt(
        `确定要封禁用户 "${row.userName}" 吗？\n封禁后用户可以登录但无法发送消息。`,
        '封禁用户',
        {
          confirmButtonText: '确定封禁',
          cancelButtonText: '取消',
          type: 'warning',
          inputPlaceholder: '请输入封禁原因（必填）',
          inputValidator: (value) => {
            if (!value || value.trim() === '') {
              return '请输入封禁原因'
            }
            return true
          }
        }
      )
      await banUser(row.id, reason)
      ElMessage.success('用户已被封禁')
      refreshData()
    } catch (error: any) {
      if (error !== 'cancel') {
        console.error('封禁失败:', error)
        ElMessage.error('封禁失败')
      }
    }
  }

  // 解封用户
  const handleUnbanUser = async (row: UserTableListItem): Promise<void> => {
    try {
      await ElMessageBox.confirm(
        `确定要解封用户 "${row.userName}" 吗？\n解封后用户将恢复正常使用。`,
        '解封用户',
        {
          confirmButtonText: '确定解封',
          cancelButtonText: '取消',
          type: 'info'
        }
      )
      await unbanUser(row.id)
      ElMessage.success('用户已解封')
      refreshData()
    } catch (error: any) {
      if (error !== 'cancel') {
        console.error('解封失败:', error)
        ElMessage.error('解封失败')
      }
    }
  }

  // 冻结用户（禁用 + 踢下线）
  const handleFreezeUser = async (row: UserTableListItem): Promise<void> => {
    try {
      const { value: reason } = await ElMessageBox.prompt(
        `确定要冻结用户 "${row.userName}" 吗？\n冻结后用户将被禁用并强制下线。`,
        '冻结用户',
        {
          confirmButtonText: '确定冻结',
          cancelButtonText: '取消',
          type: 'warning',
          inputPlaceholder: '请输入冻结原因（选填）'
        }
      )
      await freezeUser(row.id, reason)
      ElMessage.success('用户已冻结')
      refreshData()
    } catch (error: any) {
      if (error !== 'cancel') {
        ElMessage.error('冻结失败')
      }
    }
  }

  // 解冻用户
  const handleUnfreezeUser = async (row: UserTableListItem): Promise<void> => {
    try {
      await ElMessageBox.confirm(
        `确定要解冻用户 "${row.userName}" 吗？\n解冻后用户将恢复正常使用。`,
        '解冻用户',
        { confirmButtonText: '确定解冻', cancelButtonText: '取消', type: 'info' }
      )
      await unfreezeUser(row.id)
      ElMessage.success('用户已解冻')
      refreshData()
    } catch (error: any) {
      if (error !== 'cancel') {
        ElMessage.error('解冻失败')
      }
    }
  }

  // 重置登录密码
  const handleResetPassword = async (row: UserTableListItem): Promise<void> => {
    try {
      const { value: pwd } = await ElMessageBox.prompt(
        `重置用户 "${row.userName}" 的登录密码`,
        '重置密码',
        {
          confirmButtonText: '确定重置',
          cancelButtonText: '取消',
          inputType: 'password',
          inputPlaceholder: '输入新密码，留空则重置为 123456'
        }
      )
      await resetUserPassword(row.id, pwd || '123456')
      ElMessage.success('密码已重置，用户下次登录使用新密码')
    } catch (error: any) {
      if (error !== 'cancel') {
        ElMessage.error('重置失败')
      }
    }
  }

  // 弹窗提交
  const handleDialogSubmit = async () => {
    dialogVisible.value = false
    currentUserData.value = {}
    refreshData()
  }

  // 自动刷新（每30秒刷新一次在线状态）
  let refreshTimer: ReturnType<typeof setInterval> | null = null

  onMounted(() => {
    updateLastTime()
    getData()
    // 启动自动刷新
    refreshTimer = setInterval(() => {
      if (!dialogVisible.value) {
        refreshSoft()
        updateLastTime()
      }
    }, 30000) // 30秒刷新一次
  })

  onActivated(() => {
    if (!dialogVisible.value) {
      refreshSoft()
      updateLastTime()
    }
  })

  onUnmounted(() => {
    // 清除定时器
    if (refreshTimer) {
      clearInterval(refreshTimer)
      refreshTimer = null
    }
  })
</script>

<style lang="scss" scoped>
  .user-page {
    :deep(.el-table) {
      .el-table__row {
        transition: background-color 0.2s;

        &:hover {
          background-color: rgba(var(--el-color-primary-rgb), 0.03);
        }
      }

      .cell {
        padding: 12px 16px;
      }
    }

    .avatar-wrapper {
      flex-shrink: 0;
    }

    .user-info-cell {
      min-height: 56px;
    }

    .device-info {
      padding: 4px 0;
    }

    .diagnostic-panel {
      .diagnostic-grid {
        display: grid;
        grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
        gap: 16px;
      }

      .diagnostic-checks {
        display: flex;
        flex-direction: column;
        gap: 10px;
      }
    }
  }

  // 在线状态动画
  @keyframes pulse {
    0%,
    100% {
      opacity: 1;
    }
    50% {
      opacity: 0.5;
    }
  }
</style>
