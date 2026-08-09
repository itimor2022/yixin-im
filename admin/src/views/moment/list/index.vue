<!-- 动态管理页面 -->
<template>
  <div class="moment-page art-full-height">
    <!-- 搜索栏 -->
    <ArtSearchBar
      v-model="searchForm"
      :fields="searchFields"
      @search="handleSearch"
      @reset="resetSearch"
    />

    <ElCard class="art-table-card" shadow="never">
      <!-- 表格头部 -->
      <ArtTableHeader v-model:columns="columnChecks" :loading="loading" @refresh="refreshData">
        <template #left>
          <div class="flex items-center gap-4 flex-wrap">
            <span class="text-g-500">
              共 <span class="text-primary font-bold">{{ pagination.total }}</span> 条动态
            </span>
            <ElTag type="info" effect="light" round>待审核 {{ pendingCount }}</ElTag>
            <ElTag type="warning" effect="light" round>已隐藏 {{ hiddenCount }}</ElTag>
            <ElTag type="success" effect="light" round>正常 {{ approvedCount }}</ElTag>
            <ElButton link type="primary" @click="quickFilterPending">仅看待审核</ElButton>
            <ElButton link type="warning" @click="quickFilterWithReason">仅看有原因</ElButton>
            <ElButton link @click="resetSearch">重置筛选</ElButton>
          </div>
        </template>
        <template #right>
          <div v-if="!isDemoAdmin" class="flex items-center gap-2 ml-3">
            <ElButton
              type="success"
              plain
              :disabled="pendingSelectedIds.length === 0"
              @click="batchApprove"
            >
              批量通过 {{ pendingSelectedIds.length > 0 ? `(${pendingSelectedIds.length})` : '' }}
            </ElButton>
            <ElButton
              type="warning"
              plain
              :disabled="pendingSelectedIds.length === 0"
              @click="openBatchReasonDialog('reject')"
            >
              批量驳回 {{ pendingSelectedIds.length > 0 ? `(${pendingSelectedIds.length})` : '' }}
            </ElButton>
            <ElButton
              type="danger"
              plain
              :disabled="normalSelectedIds.length === 0"
              @click="openBatchReasonDialog('hide')"
            >
              批量隐藏 {{ normalSelectedIds.length > 0 ? `(${normalSelectedIds.length})` : '' }}
            </ElButton>
          </div>
        </template>
      </ArtTableHeader>

      <!-- 表格 -->
      <ArtTable
        ref="tableRef"
        :loading="loading"
        :data="data"
        :columns="columns"
        :pagination="pagination"
        :row-class-name="getRowClassName"
        @selection-change="handleSelectionChange"
        @pagination:size-change="handleSizeChange"
        @pagination:current-change="handleCurrentChange"
      >
      </ArtTable>
    </ElCard>

    <!-- 详情弹窗 -->
    <ElDialog v-model="detailVisible" title="动态详情" width="600px">
      <template v-if="currentMoment">
        <div class="moment-detail">
          <!-- 用户信息 -->
          <div class="flex items-center gap-3 mb-4">
            <ElAvatar
              :size="48"
              :src="
                currentMoment.user_avatar ? fixImageUrl(currentMoment.user_avatar) : defaultAvatar
              "
            />
            <div>
              <p class="font-medium">{{ currentMoment.user_name }}</p>
              <p class="text-sm text-g-400">{{ currentMoment.created_at }}</p>
            </div>
          </div>

          <ElAlert
            v-if="currentMoment.status === 0"
            type="success"
            :closable="false"
            show-icon
            class="mb-4"
          >
            当前动态待审核，建议优先处理。
          </ElAlert>

          <ElAlert
            v-if="currentMoment.review_reason"
            type="warning"
            :closable="false"
            show-icon
            class="mb-4"
          >
            原因：{{ currentMoment.review_reason }}
          </ElAlert>

          <ElDescriptions
            :column="2"
            border
            class="mb-4"
            v-if="currentMoment.reviewed_at || currentMoment.reviewed_by_name"
          >
            <ElDescriptionsItem label="审核人">
              {{ currentMoment.reviewed_by_name || '-' }}
            </ElDescriptionsItem>
            <ElDescriptionsItem label="审核时间">
              {{ currentMoment.reviewed_at || '-' }}
            </ElDescriptionsItem>
          </ElDescriptions>

          <!-- 内容 -->
          <p class="text-base leading-relaxed mb-4">{{ currentMoment.content }}</p>

          <!-- 媒体 -->
          <div v-if="currentMoment.media_urls?.length" class="grid grid-cols-3 gap-2 mb-4">
            <template v-for="(url, idx) in fixImageUrls(currentMoment.media_urls)" :key="idx">
              <!-- 视频 -->
              <video
                v-if="isVideoUrl(url)"
                :src="url"
                controls
                class="h-24 w-full rounded-lg object-cover"
              />
              <!-- 图片 -->
              <ElImage
                v-else
                :src="url"
                :preview-src-list="
                  fixImageUrls(currentMoment.media_urls).filter((u) => !isVideoUrl(u))
                "
                fit="cover"
                class="h-24 rounded-lg"
              />
            </template>
          </div>

          <!-- 话题 -->
          <div v-if="currentMoment.topics?.length" class="flex flex-wrap gap-2 mb-4">
            <ElTag v-for="topic in currentMoment.topics" :key="topic" type="primary" effect="light">
              #{{ topic }}
            </ElTag>
          </div>

          <!-- 统计 -->
          <div class="flex gap-6 text-sm text-g-500">
            <span><i class="ri-heart-line mr-1"></i>{{ currentMoment.like_count }} 赞</span>
            <span><i class="ri-chat-1-line mr-1"></i>{{ currentMoment.comment_count }} 评论</span>
            <span><i class="ri-eye-line mr-1"></i>{{ currentMoment.view_count }} 浏览</span>
          </div>
        </div>
      </template>
      <template #footer>
        <ElButton @click="detailVisible = false">关闭</ElButton>
        <ElButton v-if="currentMoment?.status === 0" type="success" @click="approveMoment">
          审核通过
        </ElButton>
        <ElButton
          v-if="currentMoment?.status === 0"
          type="warning"
          @click="openSingleReasonDialog('reject', currentMoment)"
        >
          驳回动态
        </ElButton>
        <ElButton
          v-if="currentMoment?.status === 1"
          type="warning"
          @click="openSingleReasonDialog('hide', currentMoment)"
        >
          隐藏动态
        </ElButton>
        <ElButton v-if="currentMoment?.status === 2" type="success" @click="restoreMoment">
          恢复动态
        </ElButton>
        <ElButton type="danger" @click="removeMoment">删除动态</ElButton>
      </template>
    </ElDialog>

    <ElDialog v-model="reasonDialogVisible" :title="reasonDialogTitle" width="520px">
      <div class="flex flex-wrap gap-2 mb-4" v-if="reasonDialogAction === 'reject'">
        <ElButton
          v-for="item in rejectReasonPresets"
          :key="item"
          size="small"
          plain
          type="warning"
          @click="reasonForm.reason = item"
        >
          {{ item }}
        </ElButton>
      </div>
      <ElInput
        v-model="reasonForm.reason"
        type="textarea"
        :rows="4"
        maxlength="200"
        show-word-limit
        :placeholder="reasonDialogPlaceholder"
      />
      <div class="text-xs text-g-400 mt-3">
        {{
          reasonDialogAction === 'reject'
            ? '驳回原因会同步展示给用户。'
            : '隐藏原因可选，便于后台追踪。'
        }}
      </div>
      <template #footer>
        <ElButton @click="closeReasonDialog">取消</ElButton>
        <ElButton type="primary" @click="submitReasonDialog">确定</ElButton>
      </template>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
  import { useTable } from '@/hooks/core/useTable'
  import { getMomentList, updateMomentStatus, deleteMoment, MomentListItem } from '@/api/admin'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import {
    ElTag,
    ElMessageBox,
    ElImage,
    ElAvatar,
    ElMessage,
    ElButton,
    ElAlert,
    ElInput,
    ElDescriptions,
    ElDescriptionsItem
  } from 'element-plus'
  import { fixImageUrl, getLocalAvatarDataUrl } from '@/utils/url'
  import { usePermission } from '@/hooks/usePermission'

  defineOptions({ name: 'MomentList' })

  const { isDemoAdmin } = usePermission()

  const defaultAvatar = getLocalAvatarDataUrl('default')
  const tableRef = ref()
  type ReasonActionType = 'reject' | 'hide'

  const rejectReasonPresets = [
    '内容含广告营销信息',
    '内容含违规引流信息',
    '内容含辱骂攻击信息',
    '内容含低俗不当信息',
    '内容真实性存疑'
  ]

  // 处理图片URL数组
  const fixImageUrls = (urls: string[] | undefined): string[] => {
    if (!urls?.length) return []
    return urls.map(fixImageUrl).filter((u) => u)
  }

  // 判断是否为视频文件
  const isVideoUrl = (url: string): boolean => {
    if (!url) return false
    const videoExts = ['.mp4', '.webm', '.ogg', '.mov', '.m4v', '.avi']
    const lowerUrl = url.toLowerCase()
    return videoExts.some((ext) => lowerUrl.includes(ext))
  }

  // 详情弹窗
  const detailVisible = ref(false)
  const currentMoment = ref<MomentListItem | null>(null)
  const selectedRows = ref<MomentListItem[]>([])

  // 原因弹窗
  const reasonDialogVisible = ref(false)
  const reasonDialogAction = ref<ReasonActionType>('reject')
  const reasonDialogMode = ref<'single' | 'batch'>('single')
  const reasonTarget = ref<MomentListItem | null>(null)
  const reasonForm = ref({ reason: '' })

  // 搜索表单
  const searchForm = ref({
    keyword: '',
    status: '',
    with_review_reason: false
  })

  const searchFields = [
    { type: 'input', field: 'keyword', label: '搜索', placeholder: '搜索动态内容' },
    {
      type: 'select',
      field: 'status',
      label: '状态',
      placeholder: '全部状态',
      options: [
        { label: '待审核', value: '0' },
        { label: '正常', value: '1' },
        { label: '已隐藏', value: '2' },
        { label: '已删除', value: '3' }
      ]
    },
    {
      type: 'select',
      field: 'with_review_reason',
      label: '审核说明',
      placeholder: '全部',
      options: [
        { label: '全部', value: false },
        { label: '仅看有原因', value: true }
      ]
    }
  ]

  // 状态配置
  const STATUS_CONFIG = {
    '0': { type: 'info' as const, text: '待审核' },
    '1': { type: 'success' as const, text: '正常' },
    '2': { type: 'warning' as const, text: '已隐藏' },
    '3': { type: 'danger' as const, text: '已删除' }
  } as const

  // 可见性配置
  const VISIBILITY_CONFIG = {
    '1': { text: '公开', icon: 'ri-earth-line' },
    '2': { text: '联系人', icon: 'ri-team-line' },
    '3': { text: '部分可见', icon: 'ri-user-line' },
    '4': { text: '私密', icon: 'ri-lock-line' }
  } as const

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
    refreshData
  } = useTable({
    core: {
      apiFn: async (params: any) => {
        const res = await getMomentList({
          page: params.current,
          page_size: params.size,
          keyword: params.keyword,
          status: params.status ? Number(params.status) : undefined,
          only_pending: params.status === '0',
          with_review_reason: !!params.with_review_reason
        })
        return {
          records: res.list || [],
          total: res.total,
          current: res.page,
          size: res.page_size
        }
      },
      apiParams: {
        current: 1,
        size: 20,
        ...searchForm.value
      },
      columnsFactory: () => [
        { type: 'selection', width: 50, fixed: 'left' },
        { type: 'index', width: 60, label: '序号' },
        {
          prop: 'userInfo',
          label: '发布者',
          minWidth: 160,
          formatter: (row: MomentListItem) => {
            // 使用 fixImageUrl 处理头像URL
            const avatarUrl = row.user_avatar ? fixImageUrl(row.user_avatar) : defaultAvatar
            return h('div', { class: 'flex items-center gap-2' }, [
              h(ElAvatar, {
                size: 36,
                src: avatarUrl
              }),
              h('span', { class: 'font-medium' }, row.user_name)
            ])
          }
        },
        {
          prop: 'content',
          label: '内容',
          minWidth: 280,
          formatter: (row: MomentListItem) => {
            const content = row.content.length > 60 ? row.content.slice(0, 60) + '...' : row.content
            return h('div', {}, [
              h('p', { class: 'text-sm line-clamp-2' }, content),
              row.review_reason
                ? h(
                    'p',
                    { class: 'text-xs text-warning mt-1 leading-5' },
                    `原因：${row.review_reason}`
                  )
                : null,
              row.media_urls?.length &&
                h(
                  'div',
                  { class: 'flex gap-1 mt-1' },
                  fixImageUrls(row.media_urls)
                    .slice(0, 3)
                    .map((url, idx) =>
                      isVideoUrl(url)
                        ? h('video', {
                            key: idx,
                            src: url,
                            class: 'w-10 h-10 rounded object-cover',
                            muted: true
                          })
                        : h(ElImage, {
                            key: idx,
                            src: url,
                            fit: 'cover',
                            class: 'w-10 h-10 rounded',
                            previewSrcList: fixImageUrls(row.media_urls).filter(
                              (u) => !isVideoUrl(u)
                            ),
                            previewTeleported: true
                          })
                    )
                )
            ])
          }
        },
        {
          prop: 'topics',
          label: '话题',
          width: 140,
          formatter: (row: MomentListItem) => {
            if (!row.topics?.length) return h('span', { class: 'text-g-300' }, '-')
            return h(
              'div',
              { class: 'flex flex-wrap gap-1' },
              row.topics
                .slice(0, 2)
                .map((t) =>
                  h(ElTag, { size: 'small', type: 'primary', effect: 'light' }, () => `#${t}`)
                )
            )
          }
        },
        {
          prop: 'visibility',
          label: '可见性',
          width: 100,
          formatter: (row: MomentListItem) => {
            const config =
              VISIBILITY_CONFIG[String(row.visibility) as keyof typeof VISIBILITY_CONFIG]
            return h('span', { class: 'flex items-center gap-1 text-sm text-g-500' }, [
              h('i', { class: config?.icon }),
              config?.text || '未知'
            ])
          }
        },
        {
          prop: 'stats',
          label: '互动',
          width: 120,
          formatter: (row: MomentListItem) => {
            return h('div', { class: 'text-xs text-g-500' }, [
              h('span', {}, `${row.like_count} 赞`),
              h('span', { class: 'mx-1' }, '·'),
              h('span', {}, `${row.comment_count} 评论`)
            ])
          }
        },
        {
          prop: 'status',
          label: '状态',
          width: 180,
          formatter: (row: MomentListItem) => {
            const config = STATUS_CONFIG[String(row.status) as keyof typeof STATUS_CONFIG]
            return h('div', { class: 'flex flex-col gap-1' }, [
              h(
                ElTag,
                {
                  type: config?.type || 'info',
                  size: 'small'
                },
                () => row.status_text || config?.text || '未知'
              ),
              row.status === 0
                ? h('span', { class: 'text-xs text-emerald-600 font-semibold' }, '优先处理')
                : null,
              row.reviewed_by_name || row.reviewed_at
                ? h('div', { class: 'text-xs text-g-400 leading-5' }, [
                    h('div', {}, `审核人：${row.reviewed_by_name || '-'}`),
                    h('div', {}, `审核时间：${row.reviewed_at || '-'}`)
                  ])
                : null
            ])
          }
        },
        {
          prop: 'created_at',
          label: '发布时间',
          width: 160
        },
        {
          prop: 'operation',
          label: '操作',
          width: 220,
          fixed: 'right',
          formatter: (row: MomentListItem) => {
            // 演示管理员只能查看
            if (isDemoAdmin.value) {
              return h('div', { class: 'flex gap-1' }, [
                h(ArtButtonTable, {
                  type: 'view',
                  onClick: () => showDetail(row)
                })
              ])
            }
            const actions = [
              h(ArtButtonTable, {
                type: 'view',
                onClick: () => showDetail(row)
              })
            ]
            if (row.status === 0) {
              actions.push(
                h(
                  ElButton,
                  {
                    size: 'small',
                    type: 'success',
                    plain: true,
                    onClick: async () => {
                      await updateMomentStatus(row.id, 1)
                      ElMessage.success('已审核通过')
                      refreshData()
                    }
                  },
                  () => '通过'
                ),
                h(
                  ElButton,
                  {
                    size: 'small',
                    type: 'warning',
                    plain: true,
                    onClick: () => openSingleReasonDialog('reject', row)
                  },
                  () => '驳回'
                )
              )
            } else if (row.status === 1) {
              actions.push(
                h(
                  ElButton,
                  {
                    size: 'small',
                    type: 'warning',
                    plain: true,
                    onClick: () => openSingleReasonDialog('hide', row)
                  },
                  () => '隐藏'
                )
              )
            } else if (row.status === 2) {
              actions.push(
                h(
                  ElButton,
                  {
                    size: 'small',
                    type: 'success',
                    plain: true,
                    onClick: async () => {
                      await updateMomentStatus(row.id, 1)
                      ElMessage.success('已恢复')
                      refreshData()
                    }
                  },
                  () => '恢复'
                )
              )
            }
            return h('div', { class: 'flex gap-1 items-center flex-wrap' }, [
              ...actions,
              h(ArtButtonTable, {
                type: 'delete',
                onClick: () => handleDelete(row)
              })
            ])
          }
        }
      ]
    }
  })

  const pendingCount = computed(
    () => data.value.filter((item: MomentListItem) => item.status === 0).length
  )
  const hiddenCount = computed(
    () => data.value.filter((item: MomentListItem) => item.status === 2).length
  )
  const approvedCount = computed(
    () => data.value.filter((item: MomentListItem) => item.status === 1).length
  )
  const pendingSelectedIds = computed(() =>
    selectedRows.value.filter((item) => item.status === 0).map((item) => item.id)
  )
  const normalSelectedIds = computed(() =>
    selectedRows.value.filter((item) => item.status === 1).map((item) => item.id)
  )

  // 搜索
  const handleSearch = (params: Record<string, any>) => {
    Object.assign(searchParams, params)
    getData()
  }

  const resetSearch = () => {
    selectedRows.value = []
    resetSearchParams()
  }

  const quickFilterPending = () => {
    searchForm.value.status = '0'
    searchForm.value.with_review_reason = false
    Object.assign(searchParams, { status: '0', with_review_reason: false, current: 1 })
    getData()
  }

  const quickFilterWithReason = () => {
    searchForm.value.with_review_reason = true
    Object.assign(searchParams, { with_review_reason: true, current: 1 })
    getData()
  }

  const handleSelectionChange = (rows: MomentListItem[]) => {
    selectedRows.value = rows
  }

  const getRowClassName = ({ row }: { row: MomentListItem }) => {
    return row.status === 0 ? 'moment-row-pending' : ''
  }

  // 显示详情
  const showDetail = (row: MomentListItem) => {
    currentMoment.value = row
    detailVisible.value = true
  }

  const openSingleReasonDialog = (action: ReasonActionType, row: MomentListItem) => {
    reasonDialogMode.value = 'single'
    reasonDialogAction.value = action
    reasonTarget.value = row
    reasonForm.value.reason = row.review_reason || ''
    reasonDialogVisible.value = true
  }

  const openBatchReasonDialog = (action: ReasonActionType) => {
    // 批量驳回只处理待审核项，批量隐藏只处理正常项，混合选择不会误改其他状态。
    const candidateIds = action === 'hide' ? normalSelectedIds.value : pendingSelectedIds.value
    if (candidateIds.length === 0) {
      ElMessage.warning(action === 'hide' ? '请先选择状态为正常的动态' : '请先选择待审核的动态')
      return
    }
    reasonDialogMode.value = 'batch'
    reasonDialogAction.value = action
    reasonTarget.value = null
    reasonForm.value.reason = ''
    reasonDialogVisible.value = true
  }

  const closeReasonDialog = () => {
    reasonDialogVisible.value = false
    reasonForm.value.reason = ''
    reasonTarget.value = null
  }

  const reasonDialogTitle = computed(() => {
    const actionText = reasonDialogAction.value === 'reject' ? '驳回原因' : '隐藏原因'
    return reasonDialogMode.value === 'batch' ? `批量填写${actionText}` : `填写${actionText}`
  })

  const reasonDialogPlaceholder = computed(() => {
    return reasonDialogAction.value === 'reject'
      ? '请输入驳回原因，用户将在“我的动态”中看到该说明'
      : '请输入隐藏原因（可选）'
  })

  const submitReasonDialog = async () => {
    const reason = reasonForm.value.reason.trim()

    if (reasonDialogAction.value === 'reject' && !reason) {
      ElMessage.warning('请填写驳回原因')
      return
    }

    try {
      if (reasonDialogMode.value === 'single' && reasonTarget.value) {
        await updateMomentStatus(reasonTarget.value.id, 2, reason || undefined)
        ElMessage.success(reasonDialogAction.value === 'reject' ? '已驳回' : '已隐藏')
        detailVisible.value = false
      } else {
        const targetIds =
          reasonDialogAction.value === 'hide' ? normalSelectedIds.value : pendingSelectedIds.value
        const actionText = reasonDialogAction.value === 'reject' ? '批量驳回' : '批量隐藏'
        await ElMessageBox.confirm(
          `确定${actionText}选中的 ${targetIds.length} 条动态吗？`,
          '批量操作确认',
          {
            type: 'warning'
          }
        )
        await Promise.all(targetIds.map((id) => updateMomentStatus(id, 2, reason || undefined)))
        // 所有请求成功后才清空选择；任一失败会保留当前上下文供管理员重试。
        ElMessage.success(`${actionText}成功，共处理 ${targetIds.length} 条`)
        selectedRows.value = []
        tableRef.value?.elTableRef?.clearSelection?.()
      }
      closeReasonDialog()
      refreshData()
    } catch (e) {
      console.error(e)
    }
  }

  const batchApprove = async () => {
    if (pendingSelectedIds.value.length === 0) {
      ElMessage.warning('请先选择待审核的动态')
      return
    }
    await ElMessageBox.confirm(
      `确定批量通过选中的 ${pendingSelectedIds.value.length} 条动态吗？`,
      '批量审核确认',
      {
        type: 'warning'
      }
    )
    await Promise.all(pendingSelectedIds.value.map((id) => updateMomentStatus(id, 1)))
    // 审核接口完成后重新拉取列表，统计、筛选结果和服务端状态保持一致。
    ElMessage.success(`批量通过成功，共处理 ${pendingSelectedIds.value.length} 条`)
    selectedRows.value = []
    tableRef.value?.elTableRef?.clearSelection?.()
    refreshData()
  }

  // 审核通过
  const approveMoment = async () => {
    if (!currentMoment.value) return
    try {
      await updateMomentStatus(currentMoment.value.id, 1)
      ElMessage.success('已审核通过')
      detailVisible.value = false
      refreshData()
    } catch (e) {
      console.error(e)
    }
  }

  // 恢复动态
  const restoreMoment = async () => {
    if (!currentMoment.value) return
    try {
      await updateMomentStatus(currentMoment.value.id, 1)
      ElMessage.success('已恢复')
      detailVisible.value = false
      refreshData()
    } catch (e) {
      console.error(e)
    }
  }

  // 删除动态
  const removeMoment = () => {
    if (!currentMoment.value) return
    ElMessageBox.confirm('确定要删除这条动态吗？删除后无法恢复', '删除确认', {
      type: 'warning'
    }).then(async () => {
      await deleteMoment(currentMoment.value!.id)
      ElMessage.success('已删除')
      detailVisible.value = false
      refreshData()
    })
  }

  // 删除（表格行）
  const handleDelete = (row: MomentListItem) => {
    ElMessageBox.confirm(`确定要删除用户 "${row.user_name}" 的这条动态吗？`, '删除确认', {
      type: 'warning'
    }).then(async () => {
      await deleteMoment(row.id)
      ElMessage.success('已删除')
      refreshData()
    })
  }
</script>

<style lang="scss" scoped>
  .moment-page {
    .moment-detail {
      max-height: 60vh;
      overflow-y: auto;
    }

    :deep(.moment-row-pending) {
      --el-table-tr-bg-color: rgba(24, 160, 88, 0.08);
    }
  }
</style>
