<!-- 会话管理页面 -->
<template>
  <div class="chat-page art-full-height">
    <ElCard class="art-table-card" shadow="never">
      <!-- 表格头部 -->
      <ArtTableHeader v-model:columns="columnChecks" :loading="loading" @refresh="refreshData">
        <template #left>
          <div class="flex items-center gap-4">
            <ElInput
              v-model="searchKeyword"
              placeholder="搜索名称"
              style="width: 200px"
              clearable
              @keyup.enter="handleSearch"
            >
              <template #prefix>
                <ArtSvgIcon icon="ri:search-line" />
              </template>
            </ElInput>
            <ElSelect
              v-model="statusFilter"
              placeholder="状态"
              clearable
              style="width: 120px"
              @change="handleSearch"
            >
              <ElOption label="正常" :value="0" />
              <ElOption label="已封禁" :value="1" />
              <ElOption label="已解散" :value="2" />
            </ElSelect>
            <span class="text-g-500">
              共 <span class="text-primary font-bold">{{ pagination.total }}</span> 个私聊
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
    </ElCard>

    <!-- 详情对话框 -->
    <ChatDetailDialog v-model="showDetailDialog" :chat-id="selectedChatId" @refresh="refreshData" />
  </div>
</template>

<script setup lang="ts">
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import ChatDetailDialog from './modules/chat-detail-dialog.vue'
  import { useTable } from '@/hooks/core/useTable'
  import { fetchGetChatList, deleteChat, ChatTableListItem } from '@/api/system-manage'
  import {
    ElTag,
    ElMessageBox,
    ElMessage,
    ElButton,
    ElSelect,
    ElOption,
    ElAvatar
  } from 'element-plus'
  import { getAvatarUrl } from '@/utils/url'
  import { usePermission } from '@/hooks/usePermission'
  import { useRouter } from 'vue-router'

  defineOptions({ name: 'ChatList' })

  const { isDemoAdmin } = usePermission()
  const router = useRouter()

  const searchKeyword = ref('')
  const statusFilter = ref<number | undefined>(undefined)

  // 详情对话框
  const showDetailDialog = ref(false)
  const selectedChatId = ref<number | null>(null)

  // 类型标签配置
  const TYPE_CONFIG = {
    1: { type: 'info' as const, text: '私聊', icon: 'ri:chat-private-line', color: '#64748b' }
  } as const

  // 状态标签配置
  const STATUS_CONFIG = {
    0: { type: 'success' as const, text: '正常' },
    1: { type: 'danger' as const, text: '已封禁' },
    2: { type: 'warning' as const, text: '已解散' }
  } as const

  const {
    columns,
    columnChecks,
    data,
    loading,
    pagination,
    getData,
    searchParams,
    handleSizeChange,
    handleCurrentChange,
    refreshData
  // useTable 统一接管加载状态、分页和查询参数，本页只提供会话接口与列定义。
  } = useTable({
    core: {
      apiFn: fetchGetChatList,
      apiParams: {
        current: 1,
        size: 20,
        keyword: '',
        type: 1
      },
      columnsFactory: () => [
        { type: 'index', width: 60, label: '#', align: 'center' },
        {
          prop: 'chatInfo',
          label: '会话信息',
          minWidth: 200,
          formatter: (row) => {
            const config = TYPE_CONFIG[row.type as keyof typeof TYPE_CONFIG] || TYPE_CONFIG[1]
            const isPrivate = row.type === 1

            // 私聊显示
            if (isPrivate) {
              const members = row.members || []
              return h('div', { class: 'flex items-center py-2' }, [
                // 私聊头像组
                members.length > 0
                  ? h(
                      'div',
                      { class: 'flex -space-x-2' },
                      members.slice(0, 2).map((m: any, i: number) =>
                        h(ElAvatar, {
                          key: i,
                          size: 36,
                          src: getAvatarUrl(m.avatar, m.uuid || m.nickname),
                          class: 'border-2 border-white ring-1 ring-gray-100'
                        })
                      )
                    )
                  : h(ElAvatar, {
                      size: 44,
                      src: getAvatarUrl(undefined, row.uuid),
                      class: 'rounded-xl'
                    }),
                h('div', { class: 'ml-4' }, [
                  h('p', { class: 'font-medium text-g-800' }, row.name || '私聊'),
                  h('div', { class: 'flex items-center gap-2 mt-1' }, [
                    h(
                      'span',
                      {
                        class: 'inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full',
                        style: { backgroundColor: config.color + '15', color: config.color }
                      },
                      [h('i', { class: config.icon + ' text-[10px]' }), config.text]
                    )
                  ])
                ])
              ])
            }

            // 群组/频道
            return h('div', { class: 'flex items-center py-2' }, [
              h(ElAvatar, {
                size: 44,
                src: getAvatarUrl(row.avatar, row.uuid),
                class: 'rounded-xl'
              }),
              h('div', { class: 'ml-4 flex-1 min-w-0' }, [
                h('p', { class: 'font-medium text-g-800 truncate' }, row.name || '未命名'),
                h('div', { class: 'flex items-center gap-2 mt-1' }, [
                  h(
                    'span',
                    {
                      class: 'inline-flex items-center gap-1 text-xs px-2 py-0.5 rounded-full',
                      style: { backgroundColor: config.color + '15', color: config.color }
                    },
                    [h('i', { class: config.icon + ' text-[10px]' }), config.text]
                  ),
                  row.description &&
                    h(
                      'span',
                      {
                        class: 'text-xs text-g-400 truncate max-w-[160px]'
                      },
                      row.description
                    )
                ])
              ])
            ])
          }
        },
        {
          prop: 'status',
          label: '状态',
          width: 90,
          align: 'center',
          formatter: (row) => {
            const config = STATUS_CONFIG[row.status as keyof typeof STATUS_CONFIG] || {
              type: 'success',
              text: '正常'
            }
            return h(
              ElTag,
              {
                type: config.type,
                size: 'small',
                effect: 'light',
                round: true
              },
              () => config.text
            )
          }
        },
        {
          prop: 'memberCount',
          label: '成员',
          width: 80,
          align: 'center',
          formatter: (row) => {
            if (row.type === 1) return h('span', { class: 'text-g-400' }, '2')
            return h('span', { class: 'font-medium' }, row.memberCount)
          }
        },
        {
          prop: 'createTime',
          label: '创建时间',
          width: 150,
          formatter: (row) => h('span', { class: 'text-g-500 text-sm' }, formatTime(row.createTime))
        },
        {
          prop: 'operation',
          label: '操作',
          width: 190,
          fixed: 'right',
          align: 'center',
          formatter: (row) => {
            // 演示管理员只能查看详情
            if (isDemoAdmin.value) {
              return h('div', { class: 'flex justify-center gap-1' }, [
                h(
                  ElButton,
                  {
                    type: 'primary',
                    link: true,
                    size: 'small',
                    onClick: () => handleViewDetail(row)
                  },
                  () => '详情'
                )
              ])
            }
            return h(
              'div',
              { class: 'flex justify-center gap-1' },
              [
                h(
                  ElButton,
                  {
                    type: 'primary',
                    link: true,
                    size: 'small',
                    onClick: () => handleViewDetail(row)
                  },
                  () => '详情'
                ),
                h(
                  ElButton,
                  {
                    type: 'info',
                    link: true,
                    size: 'small',
                    onClick: () =>
                      router.push({
                        path: '/chat/message-search',
                        query: { chat_id: row.uuid, name: row.name }
                      })
                  },
                  () => '聊天记录'
                ),
                h(ArtButtonTable, {
                  type: 'delete',
                  onClick: () => handleDelete(row)
                })
              ].filter(Boolean)
            )
          }
        }
      ]
    }
  })

  // 格式化时间
  const formatTime = (time: string) => {
    if (!time) return '-'
    const date = new Date(time)
    return date.toLocaleDateString('zh-CN', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit'
    })
  }

  // 搜索
  const handleSearch = () => {
    Object.assign(searchParams, {
      keyword: searchKeyword.value,
      status: statusFilter.value,
      type: 1
    })
    getData()
  }

  // 查看详情
  const handleViewDetail = (row: ChatTableListItem) => {
    selectedChatId.value = row.id
    showDetailDialog.value = true
  }

  // 删除会话
  const handleDelete = (row: ChatTableListItem): void => {
    ElMessageBox.confirm(
      `确定要删除${row.typeName || '会话'} "${row.name}" 吗？此操作不可恢复！`,
      '删除确认',
      {
        confirmButtonText: '确定删除',
        cancelButtonText: '取消',
        type: 'error'
      }
    ).then(async () => {
      try {
        await deleteChat(row.id)
        ElMessage.success('删除成功')
        // 删除以服务端结果为准，成功后重新拉取当前分页数据。
        refreshData()
      } catch (error) {
        console.error('删除失败:', error)
      }
    })
  }
</script>

<style lang="scss" scoped>
  .chat-page {
    :deep(.el-table) {
      .el-table__row {
        transition: background-color 0.2s;

        &:hover {
          background-color: rgba(var(--el-color-primary-rgb), 0.03);
        }
      }
    }
  }
</style>
