<!-- 下级用户列表页面 -->
<template>
  <div class="user-subordinates-page art-full-height">
    <ElCard class="art-table-card" shadow="never">
      <template #header>
        <div class="flex items-center justify-between">
          <div>
            <span class="text-lg font-semibold">下级用户列表</span>
            <span v-if="parentUser" class="ml-4 text-g-400">
              上级用户：{{ parentUser.userName }}（{{ parentUser.phone }}）
            </span>
          </div>
          <ElButton @click="goBack">
            <ArtSvgIcon icon="ri:arrow-left-line" class="mr-1" />
            返回用户列表
          </ElButton>
        </div>
      </template>

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
    </ElCard>
  </div>
</template>

<script setup lang="ts">
  import ArtSvgIcon from '@/components/core/base/art-svg-icon/index.vue'
  import { useTable } from '@/hooks/core/useTable'
  import { getSubordinates, SubordinateItem } from '@/api/admin'
  import { ElTag, ElMessage, ElAvatar } from 'element-plus'
  import { fixImageUrl } from '@/utils/url'
  import { useRouter, useRoute } from 'vue-router'
  import { computed } from 'vue'

  defineOptions({ name: 'UserSubordinates' })

  const router = useRouter()
  const route = useRoute()

  // 从路由参数获取父用户信息
  const parentUser = computed(() => ({
    id: Number(route.query.userId),
    userName: String(route.query.userName || ''),
    phone: String(route.query.phone || '')
  }))

  // 获取头像URL
  const getAvatarUrl = (row: SubordinateItem): string => {
    if (row.avatar) {
      return fixImageUrl(row.avatar)
    }
    return `https://api.dicebear.com/7.x/avataaars/svg?seed=${row.id}`
  }

  // 状态配置
  const STATUS_CONFIG: Record<
    string | number,
    { type: 'danger' | 'success' | 'warning' | 'info'; text: string; color: string }
  > = {
    0: { type: 'danger', text: '禁用', color: '#ef4444' },
    1: { type: 'success', text: '正常', color: '#22c55e' },
    2: { type: 'warning', text: '待审核', color: '#f59e0b' },
    3: { type: 'warning', text: '封禁中', color: '#f97316' }
  }

  const getStatusConfig = (status: number | string) => {
    const key = typeof status === 'string' ? parseInt(status) : status
    return STATUS_CONFIG[key] || { type: 'info' as const, text: '未知', color: '#9ca3af' }
  }

  // 格式化时间
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
    handleSizeChange,
    handleCurrentChange
  } = useTable({
    core: {
      apiFn: (params: any) => getSubordinates(parentUser.value.id, params),
      apiParams: {
        page: 1,
        page_size: 20
      },
      columnsFactory: () => [
        { type: 'index', width: 70, label: '序号', align: 'center' },
        {
          prop: 'userInfo',
          label: '用户信息',
          minWidth: 280,
          formatter: (row) => {
            return h('div', { class: 'user-info-cell flex items-center py-2' }, [
              h('div', { class: 'avatar-wrapper relative' }, [
                h(ElAvatar, {
                  size: 48,
                  src: getAvatarUrl(row),
                  class: 'border-2 border-gray-100'
                }),
                h('span', {
                  class: `absolute bottom-0 right-0 size-3.5 rounded-full border-2 border-white ${row.isOnline ? 'bg-green-500' : 'bg-gray-300'}`
                })
              ]),
              h('div', { class: 'ml-4 flex-1' }, [
                h('div', { class: 'flex items-center gap-2' }, [
                  h('span', { class: 'font-semibold text-base text-g-800' }, row.nickname || row.username || '未设置'),
                  (row.is_member && row.badge_text) && h('span', {
                    class: 'text-xs px-1.5 py-0.5 rounded text-white font-bold ml-1',
                    style: { backgroundColor: row.badge_color || '#3390EC' }
                  }, row.badge_text)
                ]),
                h('div', { class: 'flex items-center gap-3 mt-1.5' }, [
                  h('span', { class: 'text-xs text-g-400 font-mono bg-gray-50 px-2 py-0.5 rounded' }, 'ID: ' + (row.uuid?.slice(0, 8) || row.id)),
                  row.phone && h('span', { class: 'text-xs text-g-400' }, row.phone)
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
            return h(ElTag, {
              type: statusConfig.type,
              size: 'default',
              effect: 'light',
              round: true
            }, () => statusConfig.text)
          }
        },
        {
          prop: 'lastSeen',
          label: '最后活跃',
          width: 140,
          align: 'center',
          formatter: (row) => {
            if (row.is_online) {
              return h('div', { class: 'flex items-center justify-center gap-1.5' }, [
                h('span', { class: 'relative flex h-2 w-2' }, [
                  h('span', {
                    class: 'animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75'
                  }),
                  h('span', { class: 'relative inline-flex rounded-full h-2 w-2 bg-green-500' })
                ]),
                h('span', { class: 'text-green-600 font-medium' }, '在线')
              ])
            }
            return h('span', { class: 'text-g-400' }, formatTime(row.last_seen || ''))
          }
        },
        {
          prop: 'createdAt',
          label: '注册时间',
          width: 140,
          align: 'center',
          formatter: (row) => {
            return h('span', { class: 'text-g-500 text-sm' }, row.created_at || '-')
          }
        },
        {
          prop: 'operation',
          label: '操作',
          width: 150,
          fixed: 'right',
          align: 'center',
          formatter: (row) => {
            return h('div', { class: 'flex justify-center gap-1 flex-wrap' }, [
              h('button', {
                class: 'art-button-table text-green-500',
                onClick: () => viewSubordinates(row)
              }, '查看下级')
            ])
          }
        }
      ]
    }
  })

  // 查看下级
  const viewSubordinates = async (row: SubordinateItem) => {
    try {
      const result = await getSubordinates(row.id, { page: 1, page_size: 1 })
      if (result.total === 0) {
        ElMessage.info('该用户没有下级')
        return
      }
      router.push({
        path: '/system/user-subordinates',
        query: { userId: row.id, userName: row.nickname || row.username, phone: row.phone }
      })
    } catch (error) {
      console.error('查询下级失败:', error)
      ElMessage.error('查询下级失败')
    }
  }

  // 返回
  const goBack = () => {
    router.push('/system/user')
  }

  onMounted(() => {
    if (!parentUser.value.id) {
      ElMessage.error('缺少用户ID参数')
      goBack()
      return
    }
    getData()
  })
</script>

<style lang="scss" scoped>
  .user-subordinates-page {
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
  }

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