<script setup lang="ts">
  import { ref, onMounted } from 'vue'
  import {
    ElMessage,
    ElMessageBox,
    ElTag,
    ElAvatar,
    ElButton,
    ElDialog,
    ElInput,
    ElSelect,
    ElOption,
    ElDescriptions,
    ElDescriptionsItem,
    ElCard,
    ElStatistic
  } from 'element-plus'
  import {
    getReportList,
    getReportStats,
    processReport,
    deleteReport,
    type ReportItem,
    type ReportStats
  } from '@/api/report'
  import { useTable } from '@/hooks'
  import { usePermission } from '@/hooks/usePermission'

  defineOptions({ name: 'ReportList' })

  const { isDemoAdmin } = usePermission()

  // 统计数据
  const stats = ref<ReportStats | null>(null)

  // 筛选条件
  const searchForm = ref({
    status: '',
    target_type: '',
    reason: ''
  })

  // 处理弹窗
  const showProcessDialog = ref(false)
  const currentReport = ref<ReportItem | null>(null)
  const processStatus = ref(1)
  const processNote = ref('')
  const processing = ref(false)

  // 状态配置
  const STATUS_CONFIG: Record<number, { text: string; type: 'warning' | 'success' | 'info' }> = {
    0: { text: '待处理', type: 'warning' },
    1: { text: '已处理', type: 'success' },
    2: { text: '已驳回', type: 'info' }
  }

  // 类型配置
  const TYPE_CONFIG: Record<string, { text: string; color: string }> = {
    user: { text: '用户', color: '#409eff' },
    group: { text: '群组', color: '#67c23a' },
    channel: { text: '频道', color: '#e6a23c' },
    message: { text: '消息', color: '#909399' }
  }

  // 原因配置
  const REASON_CONFIG: Record<string, string> = {
    spam: '垃圾信息',
    fake: '虚假信息/诈骗',
    violence: '暴力内容',
    porn: '色情内容',
    harassment: '骚扰欺凌',
    copyright: '侵犯版权',
    other: '其他'
  }

  // 使用 useTable
  const { data, loading, pagination, handleSizeChange, handleCurrentChange, refreshData } =
    useTable({
      core: {
        apiFn: async (params: any) => {
          const res = await getReportList({
            page: params.current,
            page_size: params.size,
            status: searchForm.value.status || undefined,
            target_type: searchForm.value.target_type || undefined,
            reason: searchForm.value.reason || undefined
          })
          return {
            records: res?.list || [],
            total: res?.total || 0,
            current: res?.page || 1,
            size: params.size
          }
        },
        apiParams: {
          current: 1,
          size: 20
        },
        columnsFactory: () => []
      }
    })

  // 加载统计数据
  async function loadStats() {
    try {
      const res = await getReportStats()
      stats.value = res
    } catch (error) {
      console.error('Failed to load stats:', error)
      ElMessage.error('加载举报统计失败')
    }
  }

  // 搜索
  function handleSearch() {
    refreshData()
  }

  // 重置
  function handleReset() {
    searchForm.value = { status: '', target_type: '', reason: '' }
    refreshData()
  }

  // 打开处理弹窗
  function openProcessDialog(report: ReportItem) {
    currentReport.value = report
    processStatus.value = 1
    processNote.value = ''
    showProcessDialog.value = true
  }

  // 提交处理
  async function submitProcess() {
    if (!currentReport.value) return

    processing.value = true
    try {
      await processReport(currentReport.value.id, {
        status: processStatus.value,
        process_note: processNote.value
      })
      ElMessage.success('处理成功')
      showProcessDialog.value = false
      refreshData()
      loadStats()
    } catch {
      ElMessage.error('处理失败')
    } finally {
      processing.value = false
    }
  }

  // 删除
  async function handleDelete(report: ReportItem) {
    try {
      await ElMessageBox.confirm('确定要删除这条举报记录吗？', '提示', {
        type: 'warning'
      })
      await deleteReport(report.id)
      ElMessage.success('删除成功')
      refreshData()
      loadStats()
    } catch {
      // 用户取消
    }
  }

  // 格式化时间
  function formatTime(time: string) {
    if (!time) return '-'
    return new Date(time).toLocaleString('zh-CN')
  }

  onMounted(() => {
    loadStats()
  })
</script>

<template>
  <div class="p-4">
    <!-- 统计卡片 -->
    <div class="grid grid-cols-5 gap-4 mb-4" v-if="stats">
      <ElCard shadow="hover">
        <ElStatistic title="总举报数" :value="stats.overview.total" />
      </ElCard>
      <ElCard shadow="hover">
        <ElStatistic title="待处理" :value="stats.overview.pending" value-style="color: #e6a23c" />
      </ElCard>
      <ElCard shadow="hover">
        <ElStatistic
          title="已处理"
          :value="stats.overview.processed"
          value-style="color: #67c23a"
        />
      </ElCard>
      <ElCard shadow="hover">
        <ElStatistic title="已驳回" :value="stats.overview.rejected" value-style="color: #909399" />
      </ElCard>
      <ElCard shadow="hover">
        <ElStatistic title="今日新增" :value="stats.overview.today" value-style="color: #409eff" />
      </ElCard>
    </div>

    <!-- 筛选栏 -->
    <div class="flex gap-4 mb-4">
      <ElSelect v-model="searchForm.status" placeholder="状态" clearable style="width: 120px">
        <ElOption label="待处理" value="0" />
        <ElOption label="已处理" value="1" />
        <ElOption label="已驳回" value="2" />
      </ElSelect>

      <ElSelect v-model="searchForm.target_type" placeholder="类型" clearable style="width: 120px">
        <ElOption label="用户" value="user" />
        <ElOption label="群组" value="group" />
        <ElOption label="频道" value="channel" />
        <ElOption label="消息" value="message" />
      </ElSelect>

      <ElSelect v-model="searchForm.reason" placeholder="原因" clearable style="width: 150px">
        <ElOption v-for="(text, key) in REASON_CONFIG" :key="key" :label="text" :value="key" />
      </ElSelect>

      <ElButton type="primary" @click="handleSearch">搜索</ElButton>
      <ElButton @click="handleReset">重置</ElButton>
    </div>

    <!-- 表格 -->
    <el-table v-loading="loading" :data="data" border stripe style="width: 100%">
      <el-table-column type="index" label="#" width="60" align="center" />

      <el-table-column label="举报对象" min-width="220">
        <template #default="{ row }">
          <div class="flex items-center gap-2">
            <ElAvatar :size="40" :src="row.target_avatar">
              {{ row.target_name?.charAt(0) || '?' }}
            </ElAvatar>
            <div class="flex flex-col">
              <span class="font-medium">{{ row.target_name || row.target_id }}</span>
              <span v-if="row.target_username" class="text-xs text-gray-500"
                >@{{ row.target_username }}</span
              >
              <ElTag
                size="small"
                :type="
                  row.target_type === 'user'
                    ? 'primary'
                    : row.target_type === 'group'
                      ? 'success'
                      : 'warning'
                "
              >
                {{ TYPE_CONFIG[row.target_type]?.text || '未知' }}
              </ElTag>
            </div>
          </div>
        </template>
      </el-table-column>

      <el-table-column prop="reporter" label="举报人" min-width="120">
        <template #default="{ row }">
          {{ row.reporter || '匿名' }}
        </template>
      </el-table-column>

      <el-table-column label="举报原因" min-width="120">
        <template #default="{ row }">
          <ElTag type="danger" effect="plain">
            {{ row.reason_text || REASON_CONFIG[row.reason] || row.reason }}
          </ElTag>
        </template>
      </el-table-column>

      <el-table-column prop="description" label="补充说明" min-width="150">
        <template #default="{ row }">
          {{ row.description || '-' }}
        </template>
      </el-table-column>

      <el-table-column label="状态" width="100">
        <template #default="{ row }">
          <ElTag :type="STATUS_CONFIG[row.status]?.type || 'info'">
            {{ STATUS_CONFIG[row.status]?.text || '未知' }}
          </ElTag>
        </template>
      </el-table-column>

      <el-table-column label="举报时间" width="180">
        <template #default="{ row }">
          {{ formatTime(row.created_at) }}
        </template>
      </el-table-column>

      <el-table-column label="操作" width="180" fixed="right">
        <template #default="{ row }">
          <div v-if="isDemoAdmin" class="text-gray-400 text-xs">仅查看</div>
          <div v-else class="flex gap-2">
            <ElButton
              v-if="row.status === 0"
              type="primary"
              size="small"
              @click="openProcessDialog(row)"
            >
              处理
            </ElButton>
            <ElButton type="danger" size="small" @click="handleDelete(row)"> 删除 </ElButton>
          </div>
        </template>
      </el-table-column>
    </el-table>

    <!-- 分页 -->
    <div class="flex justify-end mt-4">
      <el-pagination
        v-model:current-page="pagination.current"
        v-model:page-size="pagination.size"
        :total="pagination.total"
        :page-sizes="[10, 20, 50, 100]"
        layout="total, sizes, prev, pager, next, jumper"
        @size-change="handleSizeChange"
        @current-change="handleCurrentChange"
      />
    </div>

    <!-- 处理弹窗 -->
    <ElDialog v-model="showProcessDialog" title="处理举报" width="500px">
      <div v-if="currentReport" class="space-y-4">
        <ElDescriptions :column="1" border>
          <ElDescriptionsItem label="举报对象">{{
            currentReport.target_name || currentReport.target_id
          }}</ElDescriptionsItem>
          <ElDescriptionsItem label="举报原因">{{ currentReport.reason_text }}</ElDescriptionsItem>
          <ElDescriptionsItem label="补充说明">{{
            currentReport.description || '无'
          }}</ElDescriptionsItem>
        </ElDescriptions>

        <div>
          <div class="mb-2 font-medium">处理结果</div>
          <ElSelect v-model="processStatus" style="width: 100%">
            <ElOption :value="1" label="确认违规，已处理" />
            <ElOption :value="2" label="核实无误，驳回举报" />
          </ElSelect>
        </div>

        <div>
          <div class="mb-2 font-medium">处理备注</div>
          <ElInput
            v-model="processNote"
            type="textarea"
            :rows="3"
            placeholder="请输入处理备注（可选）"
          />
        </div>
      </div>

      <template #footer>
        <ElButton @click="showProcessDialog = false">取消</ElButton>
        <ElButton type="primary" :loading="processing" @click="submitProcess">确认处理</ElButton>
      </template>
    </ElDialog>
  </div>
</template>
