<template>
  <div class="withdraw-manage">
    <!-- 统计卡片 -->
    <el-row :gutter="16" class="stats-row">
      <el-col :span="6"
        ><el-card shadow="never"
          ><el-statistic title="待审核" :value="stats.pending_count"
            ><template #suffix
              ><el-tag type="warning" size="small">待处理</el-tag></template
            ></el-statistic
          ></el-card
        ></el-col
      >
      <el-col :span="6"
        ><el-card shadow="never"
          ><el-statistic title="已通过" :value="stats.approved_count"
            ><template #suffix
              ><el-tag type="primary" size="small">待打款</el-tag></template
            ></el-statistic
          ></el-card
        ></el-col
      >
      <el-col :span="6"
        ><el-card shadow="never"
          ><el-statistic title="已完成" :value="stats.completed_count" /></el-card
      ></el-col>
      <el-col :span="6"
        ><el-card shadow="never"
          ><el-statistic
            title="累计提现"
            :value="stats.total_amount"
            :precision="2"
            prefix="¥" /></el-card
      ></el-col>
    </el-row>

    <!-- 筛选 -->
    <el-card shadow="never" class="filter-card">
      <el-form :inline="true">
        <el-form-item label="状态">
          <el-select v-model="filters.status" clearable placeholder="全部" @change="fetchList">
            <el-option label="待审核" value="pending" />
            <el-option label="已通过" value="approved" />
            <el-option label="已拒绝" value="rejected" />
            <el-option label="已完成" value="completed" />
          </el-select>
        </el-form-item>
        <el-form-item>
          <el-button type="primary" @click="fetchList">查询</el-button>
        </el-form-item>
      </el-form>
    </el-card>

    <!-- 列表 -->
    <el-card shadow="never">
      <el-table :data="list" v-loading="loading" stripe>
        <el-table-column prop="id" label="ID" width="60" />
        <el-table-column label="用户" width="150">
          <template #default="{ row }">
            <div style="display: flex; align-items: center; gap: 8px">
              <el-avatar :size="32" :src="fixImageUrl(row.avatar)" />
              <div>
                <div style="font-weight: 500">{{ row.user_name || '-' }}</div>
                <div style="font-size: 12px; color: #999">{{ row.username || '' }}</div>
              </div>
            </div>
          </template>
        </el-table-column>
        <el-table-column label="提现金额" width="120">
          <template #default="{ row }">
            <span style="font-weight: 600; color: #e6a23c">¥{{ row.amount?.toFixed(2) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="手续费" width="90">
          <template #default="{ row }">¥{{ row.fee?.toFixed(2) }}</template>
        </el-table-column>
        <el-table-column label="实际到账" width="110">
          <template #default="{ row }">
            <span style="font-weight: 600; color: #67c23a"
              >¥{{ row.actual_amount?.toFixed(2) }}</span
            >
          </template>
        </el-table-column>
        <el-table-column label="提现方式" prop="method_name" width="100" />
        <el-table-column label="状态" width="90">
          <template #default="{ row }">
            <el-tag :type="statusColor(row.status)" size="small">{{
              statusText(row.status)
            }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="备注" prop="remark" min-width="120" show-overflow-tooltip />
        <el-table-column label="申请时间" width="170">
          <template #default="{ row }">{{
            row.created_at?.replace('T', ' ')?.substring(0, 19)
          }}</template>
        </el-table-column>
        <el-table-column label="操作" width="200" fixed="right">
          <template #default="{ row }">
            <template v-if="row.status === 'pending'">
              <el-button type="success" size="small" @click="handleReview(row, 'approve')"
                >通过</el-button
              >
              <el-button type="danger" size="small" @click="handleReview(row, 'reject')"
                >拒绝</el-button
              >
            </template>
            <template v-else-if="row.status === 'approved'">
              <el-button type="primary" size="small" @click="handleReview(row, 'complete')"
                >确认打款</el-button
              >
            </template>
            <template v-else>
              <span style="color: #999; font-size: 12px">已处理</span>
            </template>
          </template>
        </el-table-column>
      </el-table>

      <div style="display: flex; justify-content: flex-end; margin-top: 16px">
        <el-pagination
          v-model:current-page="pagination.page"
          v-model:page-size="pagination.pageSize"
          :total="pagination.total"
          :page-sizes="[20, 50, 100]"
          layout="total, sizes, prev, pager, next"
          @size-change="fetchList"
          @current-change="fetchList"
        />
      </div>
    </el-card>
  </div>
</template>

<script setup lang="ts">
  import { ref, reactive, onMounted } from 'vue'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import {
    getWithdrawList,
    getWithdrawStats,
    reviewWithdraw,
    type WithdrawRequest,
    type WithdrawStats
  } from '@/api/admin'
  import { fixImageUrl } from '@/utils/url'

  defineOptions({ name: 'WithdrawList' })

  type TagType = 'primary' | 'success' | 'warning' | 'info' | 'danger'

  const loading = ref(false)
  const list = ref<WithdrawRequest[]>([])
  const stats = reactive<WithdrawStats>({
    pending_count: 0,
    approved_count: 0,
    completed_count: 0,
    rejected_count: 0,
    total_amount: 0
  })
  const filters = reactive({ status: '' })
  const pagination = reactive({ page: 1, pageSize: 20, total: 0 })

  const statusTagMap: Record<string, TagType> = {
    pending: 'warning',
    approved: 'primary',
    rejected: 'danger',
    completed: 'success'
  }
  const statusColor = (s: string): TagType => statusTagMap[s] || 'info'
  const statusText = (s: string) =>
    ({ pending: '待审核', approved: '已通过', rejected: '已拒绝', completed: '已完成' })[s] || s

  const fetchList = async () => {
    loading.value = true
    try {
      const res = await getWithdrawList({
        page: pagination.page,
        page_size: pagination.pageSize,
        status: filters.status || undefined
      })
      list.value = res.list || []
      pagination.total = res.total || 0
    } catch {
      /* */
    } finally {
      loading.value = false
    }
  }

  const fetchStats = async () => {
    // 汇总统计不受当前列表状态筛选影响，使用独立接口维护全局口径。
    try {
      const res = await getWithdrawStats()
      Object.assign(stats, res)
    } catch {
      /* */
    }
  }

  const handleReview = async (row: WithdrawRequest, action: string) => {
    const actionText = { approve: '通过', reject: '拒绝', complete: '确认打款' }[action] || action
    try {
      const { value: remark } = await ElMessageBox.prompt(`确认${actionText}该提现申请？`, '审核', {
        inputPlaceholder: '备注（选填）',
        confirmButtonText: actionText,
        cancelButtonText: '取消',
        type: action === 'reject' ? 'warning' : 'info'
      })
      await reviewWithdraw(row.id, action, remark)
      ElMessage.success(`${actionText}成功`)
      // 审核动作同时影响当前列表和全局统计，两类数据分别刷新。
      fetchList()
      fetchStats()
    } catch (e: any) {
      if (e !== 'cancel') ElMessage.error(e?.message || `${actionText}失败`)
    }
  }

  onMounted(() => {
    fetchList()
    fetchStats()
  })
</script>

<style scoped>
  .withdraw-manage {
    padding: 0;
  }
  .stats-row {
    margin-bottom: 16px;
  }
  .filter-card {
    margin-bottom: 16px;
  }
  .filter-card :deep(.el-card__body) {
    padding: 12px 16px;
  }
</style>
