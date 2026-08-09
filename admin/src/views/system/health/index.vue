<template>
  <div class="health-page">
    <section class="page-head">
      <div>
        <p>系统配置 / 运维状态</p>
        <h1>系统健康</h1>
        <span>查看后端依赖、消息队列、WebSocket、存储和推送的当前状态。</span>
      </div>
      <div class="head-actions">
        <ElButton
          :icon="Refresh"
          type="primary"
          :loading="loading || uploadLogLoading || trendLoading"
          @click="refreshAll"
        >
          刷新状态
        </ElButton>
      </div>
    </section>

    <section class="metric-grid">
      <div class="metric-card">
        <div class="metric-top">
          <span>整体状态</span>
          <ElIcon :class="statusTone(health?.status)"><component :is="statusIcon(health?.status)" /></ElIcon>
        </div>
        <strong>{{ statusLabel(health?.status) }}</strong>
        <small>{{ health?.server_time || '-' }}</small>
      </div>
      <div class="metric-card">
        <div class="metric-top">
          <span>运行时长</span>
          <ElIcon class="info"><Timer /></ElIcon>
        </div>
        <strong>{{ health?.uptime_text || '-' }}</strong>
        <small>{{ health?.started_at || '-' }}</small>
      </div>
      <div class="metric-card">
        <div class="metric-top">
          <span>在线连接</span>
          <ElIcon class="info"><Connection /></ElIcon>
        </div>
        <strong>{{ formatNumber(componentValue('WebSocket', 'online_connections')) }}</strong>
        <small>{{ formatNumber(componentValue('WebSocket', 'online_users')) }} 个在线用户</small>
      </div>
      <div class="metric-card">
        <div class="metric-top">
          <span>上传失败率</span>
          <ElIcon :class="statusTone(summaryComponent('upload')?.status)"><UploadFilled /></ElIcon>
        </div>
        <strong>{{ formatRate(summaryComponent('upload')?.failure_rate) }}</strong>
        <small>{{ formatNumber(summaryComponent('upload')?.failed) }} 失败 / {{ checkWindow }}</small>
      </div>
    </section>

    <section class="content-grid">
      <div class="section-card span-12">
        <div class="section-head trend-head">
          <div>
            <h2>健康趋势</h2>
            <p>{{ trendSubtitle }}</p>
          </div>
          <ElRadioGroup v-model="trendHours" size="small" @change="loadTrend">
            <ElRadioButton :value="6">6 小时</ElRadioButton>
            <ElRadioButton :value="24">24 小时</ElRadioButton>
            <ElRadioButton :value="72">72 小时</ElRadioButton>
          </ElRadioGroup>
        </div>
        <div v-loading="trendLoading" class="trend-chart-wrap">
          <ElEmpty
            v-if="trendData.length === 0 && !trendLoading"
            :image-size="92"
            description="暂无趋势数据"
          />
          <div v-show="trendData.length > 0" ref="trendChartRef" class="trend-chart"></div>
        </div>
      </div>
    </section>

    <section class="content-grid">
      <div class="section-card span-8">
        <div class="section-head">
          <div>
            <h2>组件状态</h2>
            <p>依赖服务、存储、连接和队列的实时检查结果。</p>
          </div>
        </div>
        <ElTable v-loading="loading" :data="components" class="clean-table" height="424">
          <ElTableColumn label="组件" width="150">
            <template #default="{ row }">
              <div class="component-name">
                <span class="status-dot" :class="statusTone(row.status)" />
                <span>{{ row.name }}</span>
              </div>
            </template>
          </ElTableColumn>
          <ElTableColumn label="状态" width="110">
            <template #default="{ row }">
              <ElTag :type="statusTag(row.status)" effect="light">
                {{ statusLabel(row.status) }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn label="关键指标" min-width="280">
            <template #default="{ row }">
              <div class="detail-line">{{ componentDetail(row) }}</div>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="error" label="异常" min-width="220" show-overflow-tooltip>
            <template #default="{ row }">{{ row.error || '-' }}</template>
          </ElTableColumn>
          <template #empty>
            <ElEmpty :image-size="92" description="暂无健康数据" />
          </template>
        </ElTable>
      </div>

      <div class="section-card span-4">
        <div class="section-head">
          <div>
            <h2>后端进程</h2>
            <p>当前服务进程和内存指标。</p>
          </div>
        </div>
        <div class="runtime-list">
          <div v-for="item in runtimeRows" :key="item.label">
            <span>{{ item.label }}</span>
            <b>{{ item.value }}</b>
          </div>
        </div>
      </div>
    </section>

    <section class="content-grid">
      <div class="section-card span-4">
        <div class="section-head">
          <div>
            <h2>存储</h2>
            <p>当前上传链路配置。</p>
          </div>
        </div>
        <div class="key-value-list">
          <div>
            <span>类型</span>
            <b>{{ summaryComponent('storage')?.provider || '-' }}</b>
          </div>
          <div>
            <span>Endpoint</span>
            <b>{{ summaryComponent('storage')?.endpoint || '-' }}</b>
          </div>
          <div>
            <span>Bucket</span>
            <b>{{ summaryComponent('storage')?.bucket || '-' }}</b>
          </div>
          <div>
            <span>公开域名</span>
            <b>{{ summaryComponent('storage')?.public_base_url || '-' }}</b>
          </div>
        </div>
      </div>

      <div class="section-card span-4">
        <div class="section-head">
          <div>
            <h2>队列</h2>
            <p>Redis 队列积压和死信。</p>
          </div>
        </div>
        <div class="queue-grid">
          <div v-for="item in queueRows" :key="item.label">
            <span>{{ item.label }}</span>
            <strong>{{ item.value }}</strong>
          </div>
        </div>
      </div>

      <div class="section-card span-4">
        <div class="section-head">
          <div>
            <h2>WebSocket</h2>
            <p>在线连接、断连和发送队列。</p>
          </div>
        </div>
        <div class="queue-grid">
          <div>
            <span>连接</span>
            <strong>{{ formatNumber(summaryComponent('websocket')?.online_connections) }}</strong>
          </div>
          <div>
            <span>在线用户</span>
            <strong>{{ formatNumber(summaryComponent('websocket')?.online_users) }}</strong>
          </div>
          <div>
            <span>活跃会话</span>
            <strong>{{ formatNumber(summaryComponent('websocket')?.active_chats) }}</strong>
          </div>
          <div>
            <span>累计断连</span>
            <strong>{{ formatNumber(summaryComponent('websocket')?.total_disconnects) }}</strong>
          </div>
          <div>
            <span>丢弃消息</span>
            <strong>{{ formatNumber(summaryComponent('websocket')?.dropped_messages) }}</strong>
          </div>
          <div>
            <span>广播队列</span>
            <strong>{{ formatNumber(summaryComponent('websocket')?.broadcast_queue_len) }}</strong>
          </div>
        </div>
      </div>
    </section>

    <section class="content-grid">
      <div class="section-card span-8">
        <div class="section-head">
          <div>
            <h2>最近上传失败</h2>
            <p>OSS/local 上传失败的用户、类型和原因。</p>
          </div>
          <ElButton :icon="Refresh" :loading="uploadLogLoading" @click="loadUploadLogs">
            刷新
          </ElButton>
        </div>
        <ElTable v-loading="uploadLogLoading" :data="uploadFailures" class="clean-table" height="300">
          <ElTableColumn prop="created_at" label="时间" min-width="150" />
          <ElTableColumn prop="actor_type" label="来源" width="90">
            <template #default="{ row }">{{ actorLabel(row.actor_type) }}</template>
          </ElTableColumn>
          <ElTableColumn prop="user_id" label="用户" width="86">
            <template #default="{ row }">{{ row.user_id || row.admin_id || '-' }}</template>
          </ElTableColumn>
          <ElTableColumn prop="media_type" label="类型" width="110" />
          <ElTableColumn prop="provider" label="存储" width="100" />
          <ElTableColumn prop="duration_ms" label="耗时" width="96">
            <template #default="{ row }">{{ row.duration_ms }} ms</template>
          </ElTableColumn>
          <ElTableColumn prop="error" label="错误" min-width="240" show-overflow-tooltip />
          <template #empty>
            <ElEmpty :image-size="92" description="暂无上传失败" />
          </template>
        </ElTable>
      </div>

      <div class="section-card span-4">
        <div class="section-head">
          <div>
            <h2>推送</h2>
            <p>最近窗口投递质量。</p>
          </div>
        </div>
        <div class="queue-grid">
          <div>
            <span>发送</span>
            <strong>{{ formatNumber(summaryComponent('push')?.total) }}</strong>
          </div>
          <div>
            <span>失败</span>
            <strong>{{ formatNumber(summaryComponent('push')?.failed) }}</strong>
          </div>
          <div>
            <span>成功率</span>
            <strong>{{ formatRate(summaryComponent('push')?.success_rate) }}</strong>
          </div>
          <div>
            <span>窗口</span>
            <strong>{{ checkWindow }}</strong>
          </div>
        </div>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
  import { computed, nextTick, onMounted, onUnmounted, ref } from 'vue'
  import { ElMessage } from 'element-plus'
  import {
    CircleCheck,
    Connection,
    Refresh,
    Timer,
    UploadFilled,
    WarningFilled
  } from '@element-plus/icons-vue'
  import { echarts, type EChartsOption } from '@/plugins/echarts'
  import {
    getUploadLogs,
    getSystemHealthDetail,
    getSystemHealthTrend,
    type HealthComponent,
    type HealthMetricSnapshotItem,
    type HealthStatus,
    type SystemHealthDetailResponse,
    type UploadLogItem
  } from '@/api/admin'

  defineOptions({ name: 'SystemHealth' })

  // 健康详情、失败日志和趋势采样来自三个独立接口，分别维护加载状态，互不阻塞。
  const loading = ref(false)
  const uploadLogLoading = ref(false)
  const trendLoading = ref(false)
  const trendHours = ref(24)
  const health = ref<SystemHealthDetailResponse | null>(null)
  const uploadFailures = ref<UploadLogItem[]>([])
  const trendData = ref<HealthMetricSnapshotItem[]>([])
  const trendChartRef = ref<HTMLElement>()
  let trendChart: ReturnType<typeof echarts.init> | null = null

  const components = computed(() => health.value?.components || [])
  const checkWindow = computed(() => health.value?.summary?.check_window || '15m')
  const trendSubtitle = computed(() => {
    if (trendData.value.length === 0) return `近 ${trendHours.value} 小时暂无采样`
    return `近 ${trendHours.value} 小时，${trendData.value.length} 个采样点`
  })

  const summaryComponent = (key: 'storage' | 'upload' | 'websocket' | 'push' | 'queue') =>
    health.value?.summary?.[key]

  const componentValue = (name: string, key: string) =>
    components.value.find((item) => item.name === name)?.[key]

  const statusLabel = (status?: HealthStatus | string) => {
    if (status === 'ok') return '正常'
    if (status === 'warning') return '警告'
    if (status === 'error') return '异常'
    return '未读取'
  }

  const statusTag = (status?: HealthStatus | string) => {
    if (status === 'ok') return 'success'
    if (status === 'warning') return 'warning'
    if (status === 'error') return 'danger'
    return 'info'
  }

  const statusTone = (status?: HealthStatus | string) => {
    if (status === 'ok') return 'success'
    if (status === 'warning') return 'warning'
    if (status === 'error') return 'danger'
    return 'info'
  }

  const statusIcon = (status?: HealthStatus | string) => {
    if (status === 'ok') return CircleCheck
    return WarningFilled
  }

  const formatNumber = (value: unknown) => Number(value || 0).toLocaleString()
  const formatRate = (value: unknown) => `${Number(value || 0).toFixed(1)}%`
  const formatTrendTime = (value: string) => {
    const date = new Date(value)
    if (Number.isNaN(date.getTime())) return value || '-'
    const month = `${date.getMonth() + 1}`.padStart(2, '0')
    const day = `${date.getDate()}`.padStart(2, '0')
    const hour = `${date.getHours()}`.padStart(2, '0')
    const minute = `${date.getMinutes()}`.padStart(2, '0')
    if (trendHours.value > 24) return `${month}-${day} ${hour}:${minute}`
    return `${hour}:${minute}`
  }
  const actorLabel = (value?: string) => {
    if (value === 'admin') return '后台'
    if (value === 'user') return '用户'
    return value || '-'
  }

  const runtimeRows = computed(() => {
    const runtime = health.value?.runtime
    if (!runtime) return []
    return [
      { label: 'Go', value: runtime.go_version },
      { label: '系统', value: `${runtime.os}/${runtime.arch}` },
      { label: 'CPU', value: `${runtime.cpu_num}` },
      { label: 'Goroutine', value: formatNumber(runtime.goroutines) },
      { label: 'Alloc', value: `${runtime.memory_alloc_mb} MB` },
      { label: 'Heap', value: `${runtime.heap_inuse_mb} MB` },
      { label: 'Sys', value: `${runtime.memory_sys_mb} MB` },
      { label: 'GC', value: formatNumber(runtime.gc_count) }
    ]
  })

  const queueRows = computed(() => {
    const queue = summaryComponent('queue')
    return [
      { label: '发送', value: formatNumber(queue?.message_send) },
      { label: '同步', value: formatNumber(queue?.message_sync) },
      { label: '推送', value: formatNumber(queue?.push_notify) },
      { label: '延迟', value: formatNumber(queue?.delayed) },
      { label: '死信', value: formatNumber(queue?.dead) }
    ]
  })

  const componentDetail = (row: HealthComponent) => {
    switch (row.name) {
      case 'MySQL':
        return `连接 ${formatNumber(row.open_connections)}，使用中 ${formatNumber(row.in_use)}，空闲 ${formatNumber(row.idle)}`
      case 'MongoDB':
      case 'Redis':
        return row.error ? '检查失败' : '连接可用'
      case 'Storage':
        return `${row.provider || '-'} / ${row.bucket || '-'}`
      case 'Upload':
        return `上传 ${formatNumber(row.total)}，失败 ${formatNumber(row.failed)}，失败率 ${formatRate(row.failure_rate)}`
      case 'WebSocket':
        return `连接 ${formatNumber(row.online_connections)}，断连 ${formatNumber(row.total_disconnects)}，丢弃 ${formatNumber(row.dropped_messages)}`
      case 'Push':
        return `发送 ${formatNumber(row.total)}，失败 ${formatNumber(row.failed)}，成功率 ${formatRate(row.success_rate)}`
      case 'Queue':
        return `发送 ${formatNumber(row.message_send)}，推送 ${formatNumber(row.push_notify)}，死信 ${formatNumber(row.dead)}`
      default:
        return '-'
    }
  }

  const loadHealth = async () => {
    loading.value = true
    try {
      health.value = await getSystemHealthDetail()
    } catch {
      ElMessage.error('读取系统健康状态失败')
    } finally {
      loading.value = false
    }
  }

  const loadUploadLogs = async () => {
    uploadLogLoading.value = true
    try {
      const result = await getUploadLogs({
        page: 1,
        page_size: 8,
        success: 'false'
      })
      uploadFailures.value = result.list || []
    } catch {
      ElMessage.error('读取上传失败日志失败')
    } finally {
      uploadLogLoading.value = false
    }
  }

  const renderTrendChart = () => {
    // 无数据或容器不存在时销毁旧实例，防止切换时间范围后残留过期图表。
    if (!trendChartRef.value || trendData.value.length === 0) {
      trendChart?.dispose()
      trendChart = null
      return
    }
    if (!trendChart) {
      trendChart = echarts.init(trendChartRef.value)
    }

    const labels = trendData.value.map((item) => formatTrendTime(item.created_at))
    const option: EChartsOption = {
      color: ['#2563eb', '#dc2626', '#f59e0b', '#059669', '#7c3aed'],
      tooltip: {
        trigger: 'axis',
        backgroundColor: '#ffffff',
        borderColor: '#e5e7eb',
        borderWidth: 1,
        textStyle: {
          color: '#111827'
        }
      },
      legend: {
        top: 0,
        right: 0,
        itemWidth: 12,
        itemHeight: 8,
        textStyle: {
          color: '#475569'
        }
      },
      grid: {
        left: 16,
        right: 56,
        top: 42,
        bottom: 18,
        containLabel: true
      },
      xAxis: {
        type: 'category',
        boundaryGap: false,
        data: labels,
        axisLine: {
          lineStyle: {
            color: '#e5e7eb'
          }
        },
        axisTick: {
          show: false
        },
        axisLabel: {
          color: '#64748b'
        }
      },
      yAxis: [
        {
          type: 'value',
          minInterval: 1,
          name: '数量',
          nameTextStyle: {
            color: '#64748b'
          },
          axisLine: {
            show: false
          },
          axisTick: {
            show: false
          },
          axisLabel: {
            color: '#64748b'
          },
          splitLine: {
            lineStyle: {
              color: '#eef2f7',
              type: 'dashed'
            }
          }
        },
        {
          type: 'value',
          minInterval: 1,
          name: 'MB',
          nameTextStyle: {
            color: '#64748b'
          },
          axisLine: {
            show: false
          },
          axisTick: {
            show: false
          },
          axisLabel: {
            color: '#64748b'
          },
          splitLine: {
            show: false
          }
        }
      ],
      series: [
        {
          name: '在线连接',
          type: 'line',
          smooth: true,
          symbol: 'none',
          lineStyle: { width: 2 },
          data: trendData.value.map((item) => item.ws_online_connections || 0)
        },
        {
          name: '上传失败',
          type: 'line',
          smooth: true,
          symbol: 'none',
          lineStyle: { width: 2 },
          data: trendData.value.map((item) => item.upload_failed || 0)
        },
        {
          name: '推送失败',
          type: 'line',
          smooth: true,
          symbol: 'none',
          lineStyle: { width: 2 },
          data: trendData.value.map((item) => item.push_failed || 0)
        },
        {
          name: '死信队列',
          type: 'line',
          smooth: true,
          symbol: 'none',
          lineStyle: { width: 2 },
          data: trendData.value.map((item) => item.queue_dead || 0)
        },
        {
          name: '内存',
          type: 'line',
          smooth: true,
          symbol: 'none',
          yAxisIndex: 1,
          lineStyle: { width: 2 },
          data: trendData.value.map((item) => item.memory_alloc_mb || 0)
        }
      ]
    }
    trendChart.setOption(option, true)
    window.setTimeout(() => trendChart?.resize(), 80)
  }

  const loadTrend = async () => {
    trendLoading.value = true
    try {
      const result = await getSystemHealthTrend({ hours: trendHours.value })
      trendData.value = result.list || []
      await nextTick()
      renderTrendChart()
    } catch {
      trendData.value = []
      trendChart?.dispose()
      trendChart = null
      ElMessage.error('读取健康趋势失败')
    } finally {
      trendLoading.value = false
    }
  }

  const refreshAll = () => {
    loadHealth()
    loadUploadLogs()
    loadTrend()
  }

  const handleResize = () => {
    trendChart?.resize()
  }

  onMounted(() => {
    refreshAll()
    window.addEventListener('resize', handleResize)
  })

  onUnmounted(() => {
    // ECharts 实例和全局监听器都不随 Vue 自动释放，需要在页面卸载时显式清理。
    window.removeEventListener('resize', handleResize)
    trendChart?.dispose()
  })
</script>

<style lang="scss" scoped>
  .health-page {
    min-height: 100%;
    padding: 18px;
    background: #f6f8fb;
  }

  .page-head,
  .section-card,
  .metric-card {
    border: 1px solid #e6ebf2;
    border-radius: 8px;
    background: #fff;
    box-shadow: 0 8px 20px rgb(15 23 42 / 3%);
  }

  .page-head {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 18px;
    margin-bottom: 14px;
    padding: 18px 20px;
  }

  .page-head p,
  .page-head span,
  .section-head p,
  .metric-card small {
    margin: 0;
    color: #64748b;
    font-size: 13px;
    line-height: 20px;
  }

  .page-head h1 {
    margin: 4px 0 6px;
    color: #111827;
    font-size: 22px;
    font-weight: 700;
    line-height: 30px;
  }

  .head-actions,
  .section-head {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 12px;
  }

  .metric-grid {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 12px;
    margin-bottom: 14px;
  }

  .metric-card {
    min-height: 108px;
    padding: 16px;
  }

  .metric-top {
    display: flex;
    align-items: center;
    justify-content: space-between;
    color: #64748b;
    font-size: 13px;
  }

  .metric-top .el-icon {
    width: 28px;
    height: 28px;
    border-radius: 8px;
    font-size: 16px;
  }

  .success {
    color: #059669;
    background: #ecfdf5;
  }

  .warning {
    color: #d97706;
    background: #fffbeb;
  }

  .danger {
    color: #dc2626;
    background: #fef2f2;
  }

  .info {
    color: #2563eb;
    background: #eff6ff;
  }

  .metric-card strong {
    display: block;
    margin-top: 10px;
    color: #111827;
    font-size: 28px;
    line-height: 34px;
  }

  .content-grid {
    display: grid;
    grid-template-columns: repeat(12, minmax(0, 1fr));
    gap: 14px;
    margin-bottom: 14px;
  }

  .span-4 {
    grid-column: span 4;
  }

  .span-8 {
    grid-column: span 8;
  }

  .span-12 {
    grid-column: 1 / -1;
  }

  .section-card {
    min-width: 0;
    padding: 18px;
  }

  .section-head {
    margin-bottom: 14px;
  }

  .section-head h2 {
    margin: 0 0 4px;
    color: #111827;
    font-size: 17px;
    font-weight: 650;
    line-height: 24px;
  }

  .trend-head {
    align-items: center;
  }

  .trend-chart-wrap {
    position: relative;
    min-height: 336px;
  }

  .trend-chart {
    width: 100%;
    height: 336px;
  }

  .clean-table {
    --el-table-border-color: #edf2f7;
    --el-table-header-bg-color: #f8fafc;
    --el-table-header-text-color: #475569;

    border: 1px solid #edf2f7;
    border-radius: 8px;
  }

  .component-name {
    display: flex;
    align-items: center;
    gap: 8px;
    font-weight: 600;
  }

  .status-dot {
    width: 8px;
    height: 8px;
    border-radius: 999px;
    background: #cbd5e1;
  }

  .status-dot.success {
    background: #10b981;
  }

  .status-dot.warning {
    background: #f59e0b;
  }

  .status-dot.danger {
    background: #ef4444;
  }

  .detail-line {
    overflow: hidden;
    color: #334155;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .runtime-list,
  .key-value-list {
    display: grid;
    gap: 10px;
  }

  .runtime-list div,
  .key-value-list div {
    display: flex;
    gap: 12px;
    align-items: center;
    justify-content: space-between;
    padding: 10px 12px;
    background: #f8fafc;
    border: 1px solid #edf2f7;
    border-radius: 8px;
  }

  .runtime-list span,
  .key-value-list span,
  .queue-grid span {
    color: #64748b;
    font-size: 13px;
  }

  .runtime-list b,
  .key-value-list b {
    overflow: hidden;
    max-width: 70%;
    color: #111827;
    font-size: 13px;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .queue-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 10px;
  }

  .queue-grid div {
    min-height: 78px;
    padding: 12px;
    background: #f8fafc;
    border: 1px solid #edf2f7;
    border-radius: 8px;
  }

  .queue-grid strong {
    display: block;
    margin-top: 8px;
    color: #111827;
    font-size: 24px;
    line-height: 30px;
  }

  @media (max-width: 1200px) {
    .metric-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .span-4,
    .span-8,
    .span-12 {
      grid-column: 1 / -1;
    }
  }

  @media (max-width: 768px) {
    .health-page {
      padding: 12px;
    }

    .page-head,
    .head-actions,
    .trend-head {
      flex-direction: column;
    }

    .metric-grid,
    .queue-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
