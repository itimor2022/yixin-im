<template>
  <div class="page-card dashboard-page" v-loading="loading">
    <div class="hero-block">
      <div>
        <h2 class="page-title">客服工作台</h2>
        <p class="page-subtitle">查看邀请增长、用户转化与客服账号运行状态。</p>
      </div>
      <ElTag effect="plain" size="large" round>运营概览</ElTag>
    </div>

    <div v-if="error" class="state-card error-state">
      <div class="state-title">工作台数据暂时不可用</div>
      <p class="state-text">{{ error }}</p>
      <ElButton type="primary" @click="loadDashboard">重新加载</ElButton>
    </div>

    <template v-else>
      <div class="metric-grid">
        <div class="metric-card">
          <div class="metric-label">我的邀请码</div>
          <div class="metric-value">{{ dashboard.inviteCode }}</div>
        </div>
        <div class="metric-card">
          <div class="metric-label">旗下用户数</div>
          <div class="metric-value">{{ dashboard.inviteeCount }}</div>
        </div>
        <div class="metric-card">
          <div class="metric-label">今日新增</div>
          <div class="metric-value">{{ dashboard.inviteeToday }}</div>
        </div>
        <div class="metric-card">
          <div class="metric-label">近 7 日转化</div>
          <div class="metric-value">{{ dashboard.weeklyConversion ?? 0 }}</div>
        </div>
      </div>

      <div class="split-grid">
        <section class="panel-block">
          <h3 class="section-title">本周数据概览</h3>
          <div class="data-list">
            <div class="data-item"><span>服务状态</span><span>{{ dashboard.serviceStatusText }}</span></div>
            <div class="data-item"><span>邀请码累计使用</span><span>{{ dashboard.usedCount ?? 0 }}</span></div>
            <div class="data-item"><span>注册链接</span><span class="url-text">{{ dashboard.registerUrl || '-' }}</span></div>
          </div>
        </section>
        <section class="panel-block">
          <h3 class="section-title">近 7 日新增趋势</h3>
          <div v-if="dashboard.recentTrend?.length" class="trend-chart">
            <div v-for="item in dashboard.recentTrend" :key="item.date" class="trend-bar-item">
              <div class="bar-wrap">
                <div class="bar-fill" :style="{ height: `${Math.max(item.count * 18, item.count ? 14 : 6)}px` }"></div>
              </div>
              <strong>{{ item.count }}</strong>
              <span>{{ item.date.slice(5) }}</span>
            </div>
          </div>
          <div v-else class="state-text">暂无趋势数据</div>
        </section>
      </div>

      <section class="panel-block recent-panel">
        <div class="recent-head">
          <h3 class="section-title">最近新增用户</h3>
          <ElButton text type="primary" @click="openInvitees()">查看全部</ElButton>
        </div>
        <div v-if="dashboard.recentInvitees?.length" class="recent-list">
          <button
            v-for="item in dashboard.recentInvitees"
            :key="`${item.uuid}-${item.registeredAt}`"
            class="recent-row"
            type="button"
            @click="openInvitees(item.uuid)"
          >
            <div>
              <div class="recent-name">{{ item.name || '未命名用户' }}</div>
              <div class="recent-meta">UUID: {{ item.uuid }}</div>
            </div>
            <span class="recent-time">{{ item.registeredAt }}</span>
          </button>
        </div>
        <div v-else class="state-text">最近暂无新增用户</div>
      </section>
    </template>
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { fetchServiceAdminDashboard } from '@/service/api/service-admin'
import type { ServiceAdminDashboard } from '@/types/service-admin'

const router = useRouter()
const loading = ref(true)
const error = ref('')
const dashboard = ref<ServiceAdminDashboard>({
  inviteCode: '-',
  inviteeCount: 0,
  inviteeToday: 0,
  serviceStatusText: '-',
  weeklyConversion: 0,
  usedCount: 0,
  registerUrl: '-',
  recentTrend: [],
  recentInvitees: []
})

const openInvitees = (uuid?: string) => {
  if (!uuid) {
    router.push('/invitees')
    return
  }

  // 同时传筛选词与高亮 UUID，让列表页能保留目标行并滚动到对应位置。
  router.push({
    path: '/invitees',
    query: {
      highlight: uuid,
      keyword: uuid
    }
  })
}

const loadDashboard = async () => {
  loading.value = true
  error.value = ''

  try {
    dashboard.value = await fetchServiceAdminDashboard()
  } catch (err) {
    error.value = err instanceof Error ? err.message : '获取工作台数据失败'
    ElMessage.error(error.value)
  } finally {
    loading.value = false
  }
}

onMounted(loadDashboard)
</script>

<style scoped lang="scss">
.dashboard-page { padding: 24px; }
.hero-block { display: flex; justify-content: space-between; gap: 20px; align-items: flex-start; margin-bottom: 24px; }
.split-grid { margin-top: 24px; display: grid; grid-template-columns: repeat(2, minmax(0,1fr)); gap: 16px; }
.panel-block, .state-card { padding: 20px; border-radius: var(--kf-radius-md); background: var(--kf-surface); border: 1px solid var(--kf-border); }
.recent-panel { margin-top: 16px; }
.recent-head { display: flex; justify-content: space-between; align-items: center; gap: 12px; margin-bottom: 12px; }
.state-title { font-size: 18px; font-weight: 700; }
.state-text { margin: 10px 0 18px; color: var(--text-soft); }
.error-state { margin-top: 16px; }
.url-text { max-width: 260px; text-align: right; word-break: break-all; }
.trend-chart { display: grid; grid-template-columns: repeat(7, minmax(0,1fr)); gap: 10px; align-items: end; min-height: 220px; }
.trend-bar-item { display: grid; justify-items: center; gap: 8px; }
.bar-wrap { width: 100%; min-height: 150px; display: flex; align-items: flex-end; justify-content: center; padding: 8px 0; border-radius: 10px; background: var(--kf-surface-soft); }
.bar-fill { width: 28px; border-radius: 5px 5px 2px 2px; background: #303030; transition: height .25s ease; }
.recent-list { display: grid; gap: 12px; }
.recent-row { display: flex; justify-content: space-between; gap: 16px; padding: 14px 16px; border-radius: var(--kf-radius-sm); background: var(--kf-surface-soft); border: 1px solid transparent; color: inherit; text-align: left; cursor: pointer; transition: .2s ease; }
.recent-row:hover { border-color: var(--kf-border-strong); background: #fff; }
.recent-name { font-size: 15px; font-weight: 700; }
.recent-meta, .recent-time { color: var(--text-soft); font-size: 13px; }
@media (max-width: 960px) { .hero-block, .split-grid, .recent-row { grid-template-columns: 1fr; display: grid; } }
</style>
