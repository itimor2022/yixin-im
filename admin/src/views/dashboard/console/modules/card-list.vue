<template>
  <div class="art-card stat-board">
    <div class="board-head">
      <div>
        <h3>实时指标</h3>
        <p>每 30 秒自动刷新</p>
      </div>
      <span class="refresh-time">{{ lastUpdatedText }}</span>
    </div>

    <div class="stat-layout">
      <div class="stat-grid">
        <div v-for="(item, index) in dataList" :key="index" class="stat-item">
          <div class="stat-top">
            <span class="stat-label">{{ item.des }}</span>
            <ArtSvgIcon :icon="item.icon" class="stat-icon" />
          </div>
          <ArtCountTo class="stat-value" :target="item.num" :duration="900" />
          <div class="stat-foot">
            <span>{{ item.subText }}</span>
            <span
              v-if="item.change"
              class="stat-change"
              :class="[item.change.indexOf('-') === 0 ? 'text-danger' : 'text-success']"
            >
              {{ item.change }}
            </span>
          </div>
        </div>
      </div>

      <div class="health-panel">
        <div class="health-head">
          <span>系统健康</span>
          <ElTag :type="overallHealthType" size="small" effect="plain">{{ overallHealthText }}</ElTag>
        </div>
        <div class="health-list">
          <div v-for="item in healthItems" :key="item.name" class="health-item">
            <span class="health-dot" :class="{ ok: item.ok }"></span>
            <span>{{ item.name }}</span>
            <strong>{{ item.ok ? '正常' : '异常' }}</strong>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { ElMessage } from 'element-plus'
  import {
    getDashboardStats,
    getMomentList,
    getRechargeOrders,
    getRuntimeStatus,
    getWithdrawList,
    getWithdrawStats
  } from '@/api/admin'
  import { getReportList, getReportStats } from '@/api/report'

  interface CardDataItem {
    des: string
    icon: string
    num: number
    subText: string
    change?: string
  }

  interface HealthItem {
    name: string
    ok: boolean
  }

  /**
   * 数据统计卡片
   */
  const dataList = reactive<CardDataItem[]>([
    {
      des: '总用户数',
      icon: 'ri:user-line',
      num: 0,
      subText: '今日新增',
      change: '+0'
    },
    {
      des: '今日新增',
      icon: 'ri:user-add-line',
      num: 0,
      subText: '新注册',
      change: '0'
    },
    {
      des: '在线用户',
      icon: 'ri:user-follow-line',
      num: 0,
      subText: '在线率',
      change: '0%'
    },
    {
      des: '群/频道',
      icon: 'ri:group-line',
      num: 0,
      subText: '频道',
      change: '0'
    },
    {
      des: '待审核',
      icon: 'ri:inbox-archive-line',
      num: 0,
      subText: '涉及模块',
      change: '0'
    },
    {
      des: '系统状态',
      icon: 'ri:pulse-line',
      num: 0,
      subText: '异常项',
      change: '0'
    }
  ])

  const healthItems = ref<HealthItem[]>([
    { name: 'API', ok: true },
    { name: 'MySQL', ok: true },
    { name: 'MongoDB', ok: true },
    { name: 'Redis', ok: true }
  ])
  const lastUpdatedAt = ref<Date | null>(null)

  const lastUpdatedText = computed(() => {
    if (!lastUpdatedAt.value) return '等待刷新'
    return `更新于 ${lastUpdatedAt.value.toLocaleTimeString('zh-CN', {
      hour: '2-digit',
      minute: '2-digit'
    })}`
  })

  const unhealthyCount = computed(() => healthItems.value.filter((item) => !item.ok).length)

  const overallHealthType = computed(() => (unhealthyCount.value > 0 ? 'warning' : 'success'))
  const overallHealthText = computed(() => (unhealthyCount.value > 0 ? '部分异常' : '全部正常'))

  const loadPendingCount = async () => {
    const [reportStats, reportList, withdrawStats, withdrawList, rechargeOrders, moments] =
      await Promise.allSettled([
        getReportStats(),
        getReportList({ page: 1, page_size: 1, status: '0' }),
        getWithdrawStats(),
        getWithdrawList({ page: 1, page_size: 1, status: 'pending' }),
        getRechargeOrders({ page: 1, page_size: 1, status: 'pending' }),
        getMomentList({ page: 1, page_size: 1, only_pending: true })
      ])

    const reportCount =
      reportStats.status === 'fulfilled'
        ? reportStats.value.overview.pending || 0
        : reportList.status === 'fulfilled'
          ? reportList.value.total || 0
          : 0
    const withdrawCount =
      withdrawStats.status === 'fulfilled'
        ? withdrawStats.value.pending_count || 0
        : withdrawList.status === 'fulfilled'
          ? withdrawList.value.total || 0
          : 0
    const rechargeCount = rechargeOrders.status === 'fulfilled' ? rechargeOrders.value.total || 0 : 0
    const momentCount = moments.status === 'fulfilled' ? moments.value.total || 0 : 0
    const counts = [reportCount, withdrawCount, rechargeCount, momentCount]

    return {
      total: counts.reduce((sum, count) => sum + count, 0),
      activeModules: counts.filter((count) => count > 0).length
    }
  }

  const loadHealth = async () => {
    const runtime = await getRuntimeStatus()
    healthItems.value = [
      { name: 'API', ok: true },
      { name: 'MySQL', ok: runtime.mysql_status === 'ok' },
      { name: 'MongoDB', ok: runtime.mongo_status === 'ok' },
      { name: 'Redis', ok: runtime.redis_status === 'ok' }
    ]
    return healthItems.value.filter((item) => !item.ok).length
  }

  // 加载统计数据
  const loadStats = async () => {
    try {
      const [stats, pending, abnormal] = await Promise.all([
        getDashboardStats(),
        loadPendingCount(),
        loadHealth()
      ])

      // 更新数据
      dataList[0].num = stats.total_users
      dataList[0].change = stats.new_users_today > 0 ? `+${stats.new_users_today}` : '0'

      dataList[1].num = stats.new_users_today
      dataList[1].change = stats.new_users_today > 0 ? `+${stats.new_users_today}` : '0'

      dataList[2].num = stats.online_users
      dataList[2].change =
        stats.total_users > 0 ? `${Math.round((stats.online_users / stats.total_users) * 100)}%` : '0%'

      dataList[3].num = stats.total_groups + stats.total_channels
      dataList[3].change = `${stats.total_channels}`

      dataList[4].num = pending.total
      dataList[4].change = `${pending.activeModules}`

      dataList[5].num = abnormal
      dataList[5].change = `${abnormal}`
      lastUpdatedAt.value = new Date()
    } catch (error) {
      console.error('加载统计数据失败:', error)
      ElMessage.error('加载统计数据失败')
    }
  }

  onMounted(() => {
    loadStats()
    // 每30秒刷新一次
    const timer = setInterval(loadStats, 30000)
    onUnmounted(() => clearInterval(timer))
  })
</script>

<style scoped lang="scss">
  .stat-board {
    padding: 16px 18px;
    margin-bottom: 14px;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 8px;
  }

  .board-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    margin-bottom: 14px;

    h3 {
      margin: 0;
      font-size: 15px;
      font-weight: 650;
      color: var(--el-text-color-primary);
    }

    p {
      margin: 4px 0 0;
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }
  }

  .refresh-time {
    flex: 0 0 auto;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .stat-layout {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 230px;
    gap: 12px;
  }

  .stat-grid {
    display: grid;
    grid-template-columns: repeat(6, minmax(0, 1fr));
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 8px;
    overflow: hidden;
    background: var(--el-bg-color);
  }

  .stat-item {
    min-width: 0;
    padding: 13px 14px;
    border-right: 1px solid var(--el-border-color-lighter);

    &:last-child {
      border-right: 0;
    }
  }

  .stat-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .stat-label {
    display: block;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .stat-value {
    display: block;
    margin-top: 8px;
    font-size: 24px;
    font-weight: 650;
    line-height: 1;
    color: var(--el-text-color-primary);
  }

  .stat-icon {
    flex: 0 0 auto;
    font-size: 18px;
    color: var(--el-text-color-placeholder);
  }

  .stat-foot {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-top: 10px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .stat-change {
    font-weight: 650;
  }

  .health-panel {
    min-width: 0;
    padding: 12px 14px;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 8px;
    background: var(--el-fill-color-extra-light);
  }

  .health-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    margin-bottom: 9px;

    span {
      font-size: 13px;
      font-weight: 650;
      color: var(--el-text-color-primary);
    }
  }

  .health-list {
    display: grid;
    gap: 7px;
  }

  .health-item {
    display: grid;
    grid-template-columns: 8px minmax(0, 1fr) auto;
    align-items: center;
    gap: 8px;
    font-size: 12px;
    color: var(--el-text-color-secondary);

    strong {
      font-weight: 600;
      color: var(--el-text-color-primary);
    }
  }

  .health-dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--el-color-warning);

    &.ok {
      background: var(--el-color-success);
    }
  }

  @media (max-width: 1400px) {
    .stat-layout {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 1200px) {
    .stat-grid {
      grid-template-columns: repeat(3, minmax(0, 1fr));
    }

    .stat-item {
      border-bottom: 1px solid var(--el-border-color-lighter);

      &:nth-child(3n) {
        border-right: 0;
      }

      &:nth-last-child(-n + 3) {
        border-bottom: 0;
      }
    }
  }

  @media (max-width: 640px) {
    .stat-grid {
      grid-template-columns: 1fr;
    }

    .stat-item {
      border-right: 0;

      &:nth-last-child(-n + 3) {
        border-bottom: 1px solid var(--el-border-color-lighter);
      }

      &:last-child {
        border-bottom: 0;
      }
    }
  }
</style>
