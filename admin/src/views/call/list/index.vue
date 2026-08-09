<!-- 通话记录管理页面 -->
<template>
  <div class="call-page art-full-height">
    <!-- 统计卡片 -->
    <div class="stats-grid mb-4">
      <ElCard shadow="never" class="stat-card">
        <div class="flex items-center gap-3">
          <div class="stat-icon bg-blue-100 text-blue-500">
            <i class="ri-phone-line text-xl"></i>
          </div>
          <div>
            <div class="text-2xl font-bold text-g-800">{{ stats?.total_calls || 0 }}</div>
            <div class="text-xs text-g-500">通话总数</div>
          </div>
        </div>
      </ElCard>
      <ElCard shadow="never" class="stat-card">
        <div class="flex items-center gap-3">
          <div class="stat-icon bg-green-100 text-green-500">
            <i class="ri-phone-fill text-xl"></i>
          </div>
          <div>
            <div class="text-2xl font-bold text-g-800">{{ stats?.connected_calls || 0 }}</div>
            <div class="text-xs text-g-500">接通数</div>
          </div>
        </div>
      </ElCard>
      <ElCard shadow="never" class="stat-card">
        <div class="flex items-center gap-3">
          <div class="stat-icon bg-gray-100 text-gray-600">
            <i class="ri-time-line text-xl"></i>
          </div>
          <div>
            <div class="text-2xl font-bold text-g-800">{{
              formatDuration(stats?.total_duration || 0)
            }}</div>
            <div class="text-xs text-g-500">总通话时长</div>
          </div>
        </div>
      </ElCard>
      <ElCard shadow="never" class="stat-card">
        <div class="flex items-center gap-3">
          <div class="stat-icon bg-orange-100 text-orange-500">
            <i class="ri-calendar-todo-line text-xl"></i>
          </div>
          <div>
            <div class="text-2xl font-bold text-g-800">{{ stats?.today_calls || 0 }}</div>
            <div class="text-xs text-g-500">今日通话</div>
          </div>
        </div>
      </ElCard>
    </div>

    <!-- 类型分布 -->
    <div class="type-stats mb-4 flex gap-4">
      <ElCard shadow="never" class="flex-1">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <i class="ri-mic-line text-blue-500 text-xl"></i>
            <span>语音通话</span>
          </div>
          <span class="text-xl font-bold">{{ stats?.audio_calls || 0 }}</span>
        </div>
      </ElCard>
      <ElCard shadow="never" class="flex-1">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <i class="ri-vidicon-line text-green-500 text-xl"></i>
            <span>视频通话</span>
          </div>
          <span class="text-xl font-bold">{{ stats?.video_calls || 0 }}</span>
        </div>
      </ElCard>
      <ElCard shadow="never" class="flex-1">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <i class="ri-phone-off-line text-red-500 text-xl"></i>
            <span>未接听</span>
          </div>
          <span class="text-xl font-bold">{{ stats?.missed_calls || 0 }}</span>
        </div>
      </ElCard>
      <ElCard shadow="never" class="flex-1">
        <div class="flex items-center justify-between">
          <div class="flex items-center gap-2">
            <i class="ri-close-circle-line text-orange-500 text-xl"></i>
            <span>已拒绝</span>
          </div>
          <span class="text-xl font-bold">{{ stats?.rejected_calls || 0 }}</span>
        </div>
      </ElCard>
    </div>

    <ElCard class="art-table-card" shadow="never">
      <!-- 搜索栏 -->
      <div class="search-bar mb-4 flex items-center gap-4 flex-wrap">
        <ElSelect v-model="searchParams.type" placeholder="通话类型" clearable style="width: 130px">
          <ElOption label="全部类型" value="" />
          <ElOption label="语音通话" value="voice" />
          <ElOption label="视频通话" value="video" />
        </ElSelect>
        <ElSelect
          v-model="searchParams.status"
          placeholder="通话状态"
          clearable
          style="width: 130px"
        >
          <ElOption label="全部状态" value="" />
          <ElOption label="呼叫中" value="calling" />
          <ElOption label="已接通" value="connected" />
          <ElOption label="已结束" value="ended" />
          <ElOption label="未接听" value="missed" />
          <ElOption label="已拒绝" value="rejected" />
          <ElOption label="已取消" value="cancelled" />
        </ElSelect>
        <ElInput
          v-model="searchParams.user_id"
          placeholder="用户ID"
          clearable
          style="width: 200px"
        />
        <ElDatePicker
          v-model="dateRange"
          type="daterange"
          range-separator="至"
          start-placeholder="开始日期"
          end-placeholder="结束日期"
          value-format="YYYY-MM-DD"
          style="width: 260px"
        />
        <ElButton type="primary" @click="fetchData">
          <i class="ri-search-line mr-1"></i>搜索
        </ElButton>
        <ElButton @click="resetSearch"> <i class="ri-refresh-line mr-1"></i>重置 </ElButton>
      </div>

      <!-- 批量操作 -->
      <div v-if="selectedIds.length" class="batch-actions mb-4 flex items-center gap-2">
        <span class="text-g-500">已选 {{ selectedIds.length }} 项</span>
        <ElButton size="small" type="danger" @click="handleBatchDelete">
          <i class="ri-delete-bin-line mr-1"></i>批量删除
        </ElButton>
      </div>

      <!-- 表格 -->
      <ElTable :data="list" v-loading="loading" stripe @selection-change="handleSelectionChange">
        <ElTableColumn type="selection" width="50" align="center" />
        <ElTableColumn type="index" label="序号" width="60" align="center" />
        <ElTableColumn label="主叫方" min-width="180">
          <template #default="{ row }">
            <div class="flex items-center gap-2">
              <ElAvatar :size="36" :src="fixImageUrl(row.caller_avatar)">
                {{ row.caller_name?.charAt(0) }}
              </ElAvatar>
              <div>
                <div class="font-medium">{{ row.caller_name }}</div>
                <div class="text-xs text-g-400">{{ row.caller_id }}</div>
              </div>
            </div>
          </template>
        </ElTableColumn>
        <ElTableColumn label="" width="60" align="center">
          <template #default="{ row }">
            <i
              :class="[
                'text-lg',
                row.type === 'video'
                  ? 'ri-vidicon-line text-green-500'
                  : 'ri-phone-line text-blue-500'
              ]"
            ></i>
          </template>
        </ElTableColumn>
        <ElTableColumn label="被叫方" min-width="180">
          <template #default="{ row }">
            <div class="flex items-center gap-2">
              <ElAvatar :size="36" :src="fixImageUrl(row.callee_avatar)">
                {{ row.callee_name?.charAt(0) }}
              </ElAvatar>
              <div>
                <div class="font-medium">{{ row.callee_name }}</div>
                <div class="text-xs text-g-400">{{ row.callee_id }}</div>
              </div>
            </div>
          </template>
        </ElTableColumn>
        <ElTableColumn label="类型" width="100" align="center">
          <template #default="{ row }">
            <ElTag :type="row.type === 'video' ? 'success' : 'primary'" size="small">
              {{ row.type === 'video' ? '视频' : '语音' }}
            </ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn label="接口" width="100" align="center">
          <template #default="{ row }">
            <ElTag :type="getProviderType(row)" size="small">
              {{ getProviderText(row) }}
            </ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn label="状态" width="100" align="center">
          <template #default="{ row }">
            <ElTag :type="getStatusType(row.status)" size="small">
              {{ getStatusText(row.status) }}
            </ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn label="通话时长" width="100" align="center">
          <template #default="{ row }">
            <span v-if="row.duration > 0">{{ formatCallDuration(row.duration) }}</span>
            <span v-else class="text-g-400">-</span>
          </template>
        </ElTableColumn>
        <ElTableColumn label="发起时间" width="160">
          <template #default="{ row }">
            {{ formatTime(row.created_at) }}
          </template>
        </ElTableColumn>
        <ElTableColumn label="操作" width="170" fixed="right" align="center">
          <template #default="{ row }">
            <ElButton
              v-if="isActiveCall(row.status)"
              size="small"
              type="warning"
              link
              @click="handleForceEnd(row)"
            >
              <i class="ri-stop-circle-line mr-1"></i>强制结束
            </ElButton>
            <ElButton size="small" type="danger" link @click="handleDelete(row)">
              <i class="ri-delete-bin-line mr-1"></i>删除
            </ElButton>
          </template>
        </ElTableColumn>
      </ElTable>

      <!-- 分页 -->
      <div class="pagination-wrapper mt-4 flex justify-end">
        <ElPagination
          v-model:current-page="pagination.page"
          v-model:page-size="pagination.page_size"
          :total="pagination.total"
          :page-sizes="[10, 20, 50, 100]"
          layout="total, sizes, prev, pager, next, jumper"
          @size-change="handleSizeChange"
          @current-change="handlePageChange"
        />
      </div>
    </ElCard>
  </div>
</template>

<script setup lang="ts">
  import { ref, reactive, onMounted } from 'vue'
  import {
    ElCard,
    ElTable,
    ElTableColumn,
    ElButton,
    ElTag,
    ElAvatar,
    ElPagination,
    ElInput,
    ElSelect,
    ElOption,
    ElDatePicker,
    ElMessageBox,
    ElMessage
  } from 'element-plus'
  import {
    getCallList,
    getCallStats,
    deleteCall,
    forceEndCall,
    batchDeleteCalls,
    CallRecord,
    CallStats
  } from '@/api/admin'
  import { fixImageUrl } from '@/utils/url'

  defineOptions({ name: 'CallList' })

  const loading = ref(false)
  const stats = ref<CallStats | null>(null)
  const list = ref<CallRecord[]>([])
  const selectedIds = ref<number[]>([])
  const dateRange = ref<[string, string] | null>(null)

  const searchParams = reactive({
    type: '',
    status: '',
    user_id: ''
  })

  const pagination = reactive({
    page: 1,
    page_size: 20,
    total: 0
  })

  const getStatusType = (status: string) => {
    switch (status) {
      case 'calling':
        return 'warning'
      case 'connected':
        return 'primary'
      case 'ended':
        return 'success'
      case 'missed':
        return 'danger'
      case 'rejected':
        return 'info'
      case 'cancelled':
        return 'info'
      default:
        return 'info'
    }
  }

  const getStatusText = (status: string) => {
    switch (status) {
      case 'calling':
        return '呼叫中'
      case 'connected':
        return '通话中'
      case 'ended':
        return '已结束'
      case 'missed':
        return '未接听'
      case 'rejected':
        return '已拒绝'
      case 'cancelled':
        return '已取消'
      default:
        return status
    }
  }

  const isActiveCall = (status: string) => status === 'calling' || status === 'connected'

  // 兼容历史 rtc_provider 和当前 provider 字段，未知值按默认 Agora 展示。
  const getCallProvider = (row: CallRecord) =>
    row.rtc_provider === 'livekit' || row.provider === 'livekit' ? 'livekit' : 'agora'

  const getProviderType = (row: CallRecord) =>
    getCallProvider(row) === 'livekit' ? 'success' : 'primary'

  const getProviderText = (row: CallRecord) =>
    getCallProvider(row) === 'livekit' ? 'LiveKit' : 'Agora'

  const formatTime = (time: string) => {
    if (!time) return '-'
    return new Date(time).toLocaleString('zh-CN')
  }

  const formatCallDuration = (seconds: number) => {
    const mins = Math.floor(seconds / 60)
    const secs = seconds % 60
    if (mins > 0) {
      return `${mins}分${secs}秒`
    }
    return `${secs}秒`
  }

  const formatDuration = (seconds: number) => {
    const hours = Math.floor(seconds / 3600)
    const mins = Math.floor((seconds % 3600) / 60)
    if (hours > 0) {
      return `${hours}小时${mins}分`
    }
    return `${mins}分钟`
  }

  const fetchStats = async () => {
    try {
      const res = await getCallStats()
      stats.value = res
    } catch (e) {
      console.error('获取统计失败', e)
      ElMessage.error('获取通话统计失败')
    }
  }

  const fetchData = async () => {
    loading.value = true
    try {
      const params: any = {
        page: pagination.page,
        page_size: pagination.page_size,
        ...searchParams
      }
      // 日期组件返回区间端点，转换成后端列表接口约定的 start_date/end_date。
      if (dateRange.value) {
        params.start_date = dateRange.value[0]
        params.end_date = dateRange.value[1]
      }
      const res = await getCallList(params)
      list.value = res.list || []
      pagination.total = res.total || 0
    } catch (e) {
      console.error('获取通话列表失败', e)
    } finally {
      loading.value = false
    }
  }

  const resetSearch = () => {
    searchParams.type = ''
    searchParams.status = ''
    searchParams.user_id = ''
    dateRange.value = null
    pagination.page = 1
    fetchData()
  }

  const handleSizeChange = (size: number) => {
    pagination.page_size = size
    pagination.page = 1
    fetchData()
  }

  const handlePageChange = (page: number) => {
    pagination.page = page
    fetchData()
  }

  const handleSelectionChange = (selection: CallRecord[]) => {
    selectedIds.value = selection.map((item) => item.id)
  }

  const handleDelete = async (row: CallRecord) => {
    try {
      await ElMessageBox.confirm('确定要删除该通话记录吗？', '删除确认', { type: 'warning' })
      await deleteCall(row.id)
      ElMessage.success('删除成功')
      fetchData()
      fetchStats()
    } catch (e: any) {
      if (e !== 'cancel') {
        ElMessage.error(e.message || '删除失败')
      }
    }
  }

  const handleForceEnd = async (row: CallRecord) => {
    try {
      await ElMessageBox.confirm(
        '确定要强制结束该通话吗？双方客户端会同步退出当前通话。',
        '强制结束通话',
        { type: 'warning' }
      )
      await forceEndCall(row.id)
      // 强制结束会改变记录状态和聚合统计，两份数据都需要重新向服务端读取。
      ElMessage.success('已强制结束')
      fetchData()
      fetchStats()
    } catch (e: any) {
      if (e !== 'cancel') {
        ElMessage.error(e.message || '强制结束失败')
      }
    }
  }

  const handleBatchDelete = async () => {
    try {
      await ElMessageBox.confirm(
        `确定要删除选中的 ${selectedIds.value.length} 条通话记录吗？`,
        '批量删除',
        { type: 'warning' }
      )
      await batchDeleteCalls(selectedIds.value)
      ElMessage.success('删除成功')
      selectedIds.value = []
      fetchData()
      fetchStats()
    } catch (e: any) {
      if (e !== 'cancel') {
        ElMessage.error(e.message || '删除失败')
      }
    }
  }

  onMounted(() => {
    fetchStats()
    fetchData()
  })
</script>

<style scoped lang="scss">
  .stats-grid {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 16px;
  }

  .stat-card {
    .stat-icon {
      width: 48px;
      height: 48px;
      border-radius: 12px;
      display: flex;
      align-items: center;
      justify-content: center;
    }
  }

  @media (max-width: 1200px) {
    .stats-grid {
      grid-template-columns: repeat(2, 1fr);
    }

    .type-stats {
      flex-wrap: wrap;
    }
  }
</style>
