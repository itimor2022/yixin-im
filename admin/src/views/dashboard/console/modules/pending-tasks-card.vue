<template>
  <div class="art-card pending-card" v-loading="loading">
    <div class="pending-head">
      <div>
        <h4>待处理事项</h4>
        <p>举报、提现、充值与动态审核</p>
      </div>
      <ElButton size="small" text :loading="loading" @click="loadTasks">
        <ArtSvgIcon icon="ri:refresh-line" />
      </ElButton>
    </div>

    <div class="task-table">
      <div class="task-row task-title-row">
        <span>类型</span>
        <span>最新记录</span>
        <span>待办数</span>
        <span>操作</span>
      </div>

      <div v-for="item in tasks" :key="item.key" class="task-row">
        <div class="task-name">
          <span class="task-marker" :class="{ urgent: item.count > 0 }"></span>
          <ArtSvgIcon :icon="item.icon" />
          <span>{{ item.title }}</span>
        </div>
        <div class="task-desc">{{ item.latest || '暂无待处理记录' }}</div>
        <div class="task-count" :class="{ urgent: item.count > 0 }">{{ item.count }}</div>
        <div class="task-actions">
          <RouterLink :to="item.path" class="task-link">查看</RouterLink>
          <ElButton
            size="small"
            type="primary"
            link
            :disabled="item.count <= 0 || isDemoAdmin || actionLoading"
            @click="handleTask(item.key, 'approve')"
          >
            {{ item.key === 'reports' ? '处理' : '通过' }}
          </ElButton>
          <ElButton
            size="small"
            type="danger"
            link
            :disabled="item.count <= 0 || isDemoAdmin || actionLoading"
            @click="handleTask(item.key, 'reject')"
          >
            拒绝
          </ElButton>
        </div>
      </div>
    </div>

    <div class="pending-summary">
      <div>
        <span class="summary-label">待办总数</span>
        <span class="summary-value">{{ totalPending }}</span>
      </div>
      <div>
        <span class="summary-label">涉及模块</span>
        <span class="summary-value danger">{{ urgentPending }}</span>
      </div>
      <div>
        <span class="summary-label">处理权限</span>
        <span class="summary-value text">{{ isDemoAdmin ? '只读' : '可处理' }}</span>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { ElMessage, ElMessageBox } from 'element-plus'
  import {
    getMomentList,
    getRechargeOrders,
    reviewRechargeOrder,
    getWithdrawList,
    getWithdrawStats,
    reviewWithdraw,
    updateMomentStatus
  } from '@/api/admin'
  import type {
    MomentListItem,
    RechargeOrderInfo,
    WithdrawRequest
  } from '@/api/admin'
  import { getReportList, getReportStats, processReport } from '@/api/report'
  import type { ReportItem } from '@/api/report'
  import { usePermission } from '@/hooks/usePermission'

  interface PendingTask {
    key: string
    title: string
    count: number
    latest: string
    path: string
    icon: string
    iconBg: string
  }

  const loading = ref(false)
  const actionLoading = ref(false)
  const { isDemoAdmin } = usePermission()
  const latestReport = ref<ReportItem | null>(null)
  const latestWithdraw = ref<WithdrawRequest | null>(null)
  const latestRecharge = ref<RechargeOrderInfo | null>(null)
  const latestMoment = ref<MomentListItem | null>(null)
  const tasks = reactive<PendingTask[]>([
    {
      key: 'reports',
      title: '待处理举报',
      count: 0,
      latest: '',
      path: '/report/list',
      icon: 'ri:alarm-warning-line',
      iconBg: 'bg-warning/10 text-warning'
    },
    {
      key: 'withdraw',
      title: '提现审核',
      count: 0,
      latest: '',
      path: '/wallet/withdraw',
      icon: 'ri:money-cny-box-line',
      iconBg: 'bg-danger/10 text-danger'
    },
    {
      key: 'recharge',
      title: '充值审核',
      count: 0,
      latest: '',
      path: '/wallet/recharge',
      icon: 'ri:bank-card-line',
      iconBg: 'bg-primary/10 text-primary'
    },
    {
      key: 'moments',
      title: '动态审核',
      count: 0,
      latest: '',
      path: '/moment/list',
      icon: 'ri:compass-3-line',
      iconBg: 'bg-success/10 text-success'
    }
  ])

  const totalPending = computed(() => tasks.reduce((sum, item) => sum + item.count, 0))
  const urgentPending = computed(() => tasks.filter((item) => item.count > 0).length)

  const setTask = (key: string, count: number, latest: string) => {
    const item = tasks.find((task) => task.key === key)
    if (!item) return
    item.count = count
    item.latest = latest
  }

  const compactText = (value?: string | null) => {
    const text = (value || '').trim()
    if (!text) return ''
    return text.length > 24 ? `${text.slice(0, 24)}...` : text
  }

  const loadReports = async () => {
    const [stats, list] = await Promise.all([
      getReportStats(),
      getReportList({ page: 1, page_size: 1, status: '0' })
    ])
    const latest = list.list[0]
    latestReport.value = latest || null
    setTask(
      'reports',
      stats.overview.pending || 0,
      latest ? `${latest.reason_text || '举报'} · ${latest.target_name || latest.target_id}` : ''
    )
  }

  const loadWithdraw = async () => {
    const [stats, list] = await Promise.all([
      getWithdrawStats(),
      getWithdrawList({ page: 1, page_size: 1, status: 'pending' })
    ])
    const latest = list.list[0]
    latestWithdraw.value = latest || null
    setTask(
      'withdraw',
      stats.pending_count || 0,
      latest ? `${latest.user_name || latest.username || latest.user_id} · ¥${latest.amount}` : ''
    )
  }

  const loadRecharge = async () => {
    const res = await getRechargeOrders({ page: 1, page_size: 1, status: 'pending' })
    const latest = res.list[0]
    latestRecharge.value = latest || null
    setTask(
      'recharge',
      res.total || 0,
      latest ? `${latest.user_name || latest.username || latest.user_id} · ¥${latest.amount}` : ''
    )
  }

  const loadMoments = async () => {
    const res = await getMomentList({ page: 1, page_size: 1, only_pending: true })
    const latest = res.list[0]
    latestMoment.value = latest || null
    setTask(
      'moments',
      res.total || 0,
      latest ? `${latest.user_name || '用户'} · ${compactText(latest.content)}` : ''
    )
  }

  const loadTasks = async () => {
    loading.value = true
    try {
      await Promise.allSettled([loadReports(), loadWithdraw(), loadRecharge(), loadMoments()])
    } finally {
      loading.value = false
    }
  }

  const promptReview = async (title: string, confirmButtonText: string, inputPlaceholder = '备注（选填）') => {
    const { value } = await ElMessageBox.prompt(title, '快速处理', {
      inputPlaceholder,
      confirmButtonText,
      cancelButtonText: '取消',
      type: 'warning'
    })
    return value || ''
  }

  const handleReport = async (action: 'approve' | 'reject') => {
    if (!latestReport.value) return
    const note = await promptReview(
      action === 'approve' ? '确认将最新举报标记为已处理？' : '确认驳回最新举报？',
      action === 'approve' ? '已处理' : '驳回'
    )
    await processReport(latestReport.value.id, {
      status: action === 'approve' ? 1 : 2,
      process_note: note
    })
  }

  const handleWithdraw = async (action: 'approve' | 'reject') => {
    if (!latestWithdraw.value) return
    const remark = await promptReview(
      action === 'approve' ? '确认通过最新提现申请？' : '确认拒绝最新提现申请？',
      action === 'approve' ? '通过' : '拒绝'
    )
    await reviewWithdraw(latestWithdraw.value.id, action, remark)
  }

  const handleRecharge = async (action: 'approve' | 'reject') => {
    if (!latestRecharge.value) return
    const remark = await promptReview(
      action === 'approve' ? '确认通过最新充值申请？' : '确认拒绝最新充值申请？',
      action === 'approve' ? '通过' : '拒绝'
    )
    await reviewRechargeOrder(latestRecharge.value.id, action, remark)
  }

  const handleMoment = async (action: 'approve' | 'reject') => {
    if (!latestMoment.value) return
    const reason = await promptReview(
      action === 'approve' ? '确认通过最新动态审核？' : '确认拒绝最新动态审核？',
      action === 'approve' ? '通过' : '拒绝',
      '审核备注（选填）'
    )
    await updateMomentStatus(latestMoment.value.id, action === 'approve' ? 1 : 2, reason)
  }

  const handleTask = async (key: string, action: 'approve' | 'reject') => {
    if (isDemoAdmin.value || actionLoading.value) return
    actionLoading.value = true
    try {
      if (key === 'reports') await handleReport(action)
      if (key === 'withdraw') await handleWithdraw(action)
      if (key === 'recharge') await handleRecharge(action)
      if (key === 'moments') await handleMoment(action)
      ElMessage.success('处理成功')
      await loadTasks()
    } catch (error: any) {
      if (error !== 'cancel') {
        ElMessage.error(error?.message || '处理失败')
      }
    } finally {
      actionLoading.value = false
    }
  }

  onMounted(() => {
    loadTasks()
    const timer = setInterval(loadTasks, 30000)
    onUnmounted(() => clearInterval(timer))
  })
</script>

<style scoped lang="scss">
  .pending-card {
    padding: 0;
    margin-bottom: 14px;
    overflow: hidden;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 8px;
  }

  .pending-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 16px 18px 12px;
    border-bottom: 1px solid var(--el-border-color-lighter);

    h4 {
      margin: 0;
      font-size: 15px;
      font-weight: 600;
      color: var(--el-text-color-primary);
    }

    p {
      margin: 3px 0 0;
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }
  }

  .task-table {
    padding: 0 18px;
  }

  .task-row {
    display: grid;
    grid-template-columns: minmax(130px, 0.8fr) minmax(220px, 1.7fr) 80px minmax(150px, 0.9fr);
    align-items: center;
    gap: 12px;
    min-height: 52px;
    border-bottom: 1px solid var(--el-border-color-extra-light);

    &:last-child {
      border-bottom: 0;
    }
  }

  .task-title-row {
    min-height: 38px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .task-name {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
    font-size: 13px;
    font-weight: 600;
    color: var(--el-text-color-primary);
  }

  .task-marker {
    width: 7px;
    height: 7px;
    flex: 0 0 7px;
    border-radius: 50%;
    background: var(--el-border-color);

    &.urgent {
      background: var(--el-color-danger);
    }
  }

  .task-count {
    font-size: 18px;
    font-weight: 650;
    line-height: 1;
    color: var(--el-text-color-primary);

    &.urgent {
      color: var(--el-color-danger);
    }
  }

  .task-desc {
    overflow: hidden;
    font-size: 12px;
    line-height: 1.4;
    color: var(--el-text-color-secondary);
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .task-actions {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .task-link {
    font-size: 12px;
    color: var(--el-color-primary);
  }

  .pending-summary {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    border-top: 1px solid var(--el-border-color-lighter);
    background: var(--el-fill-color-extra-light);

    > div {
      padding: 12px 18px;
      border-right: 1px solid var(--el-border-color-lighter);

      &:last-child {
        border-right: 0;
      }
    }
  }

  .summary-label {
    display: block;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .summary-value {
    display: block;
    margin-top: 5px;
    font-size: 18px;
    font-weight: 650;
    line-height: 1;
    color: var(--el-text-color-primary);

    &.danger {
      color: var(--el-color-danger);
    }

    &.text {
      font-size: 14px;
    }
  }

  @media (max-width: 900px) {
    .task-row {
      grid-template-columns: minmax(120px, 1fr) 70px minmax(132px, 1fr);
    }

    .task-title-row span:nth-child(2),
    .task-desc {
      display: none;
    }
  }

  @media (max-width: 640px) {
    .task-row {
      grid-template-columns: 1fr auto;
    }

    .task-title-row,
    .task-actions {
      display: none;
    }

    .pending-summary {
      grid-template-columns: 1fr;

      > div {
        border-right: 0;
        border-bottom: 1px solid var(--el-border-color-lighter);

        &:last-child {
          border-bottom: 0;
        }
      }
    }
  }
</style>
