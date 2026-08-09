<!-- 用户增长趋势图表 -->
<template>
  <div class="art-card trend-panel">
    <div class="trend-head">
      <div>
        <h4>用户增长趋势</h4>
        <p>新增用户按日期聚合</p>
      </div>
      <ElRadioGroup v-model="period" size="small" @change="loadData">
        <ElRadioButton value="7">近7天</ElRadioButton>
        <ElRadioButton value="30">近30天</ElRadioButton>
      </ElRadioGroup>
    </div>

    <div v-if="loading" class="chart-placeholder">
      <ElSkeleton :rows="8" animated />
    </div>

    <div v-else-if="chartData.length === 0" class="empty-chart">
      <ArtSvgIcon icon="ri:bar-chart-box-line" />
      <span>暂无数据</span>
    </div>

    <div v-else ref="chartRef" class="chart-body"></div>
  </div>
</template>

<script setup lang="ts">
  import * as echarts from 'echarts/core'
  import { LineChart } from 'echarts/charts'
  import { GridComponent, TooltipComponent, LegendComponent } from 'echarts/components'
  import { CanvasRenderer } from 'echarts/renderers'
  import { getUserStatsDetail } from '@/api/admin'
  import { useSettingStore } from '@/store/modules/setting'

  echarts.use([LineChart, GridComponent, TooltipComponent, LegendComponent, CanvasRenderer])

  const settingStore = useSettingStore()
  const { isDark } = storeToRefs(settingStore)

  const chartRef = ref<HTMLElement>()
  const period = ref('7')
  const loading = ref(true)
  const chartData = ref<{ date: string; count: number }[]>([])
  let requestId = 0
  let resizeTimer: ReturnType<typeof setTimeout> | null = null
  let refreshTimer: ReturnType<typeof setInterval> | null = null

  let chart: echarts.ECharts | null = null

  const startAutoRefresh = () => {
    if (refreshTimer) return
    refreshTimer = setInterval(() => {
      loadData()
    }, 60000) // 60秒自动刷新一次
  }

  const stopAutoRefresh = () => {
    if (refreshTimer) {
      clearInterval(refreshTimer)
      refreshTimer = null
    }
  }

  const loadData = async () => {
    const currentRequestId = ++requestId
    let shouldSyncView = false
    try {
      loading.value = true
      const days = parseInt(period.value)
      const response = await getUserStatsDetail(days)
      // 竞态：仅使用最新请求的结果
      if (currentRequestId === requestId) {
        chartData.value = response?.daily_new_users || []
        shouldSyncView = true
      }
    } catch (error) {
      if (currentRequestId === requestId) {
        console.error('加载用户统计失败:', error)
        chartData.value = []
        shouldSyncView = true
      }
    } finally {
      if (shouldSyncView) {
        loading.value = false
        // 必须在 loading 变为 false 后渲染图表，否则 chartRef 指向的 div 尚未挂载
        await nextTick()
        renderChart()
      }
    }
  }

  const renderChart = () => {
    if (!chartRef.value || chartData.value.length === 0) {
      if (chart) {
        chart.dispose()
        chart = null
      }
      return
    }

    if (chart) {
      chart.dispose()
    }

    chart = echarts.init(chartRef.value)

    // 生成完整日期范围
    const days = parseInt(period.value)
    const normalizeDateKey = (value: string) => {
      if (!value) return ''
      // 兼容 "YYYY-MM-DD" / "YYYY-MM-DDTHH:mm:ssZ" / 其它可解析格式
      if (/^\d{4}-\d{2}-\d{2}$/.test(value)) return value
      const d = new Date(value)
      if (Number.isNaN(d.getTime())) return value.slice(0, 10)
      const y = d.getFullYear()
      const m = `${d.getMonth() + 1}`.padStart(2, '0')
      const day = `${d.getDate()}`.padStart(2, '0')
      return `${y}-${m}-${day}`
    }

    const formatLocalDate = (date: Date) => {
      const y = date.getFullYear()
      const m = `${date.getMonth() + 1}`.padStart(2, '0')
      const day = `${date.getDate()}`.padStart(2, '0')
      return `${y}-${m}-${day}`
    }

    const dateMap = new Map(
      chartData.value.map((item) => [normalizeDateKey(item.date), item.count])
    )
    const dates: string[] = []
    const counts: number[] = []

    for (let i = days - 1; i >= 0; i--) {
      const date = new Date()
      date.setDate(date.getDate() - i)
      const dateStr = formatLocalDate(date)
      dates.push(dateStr.slice(5)) // 只显示 MM-DD
      counts.push(dateMap.get(dateStr) || 0)
    }

    const option = {
      tooltip: {
        trigger: 'axis',
        backgroundColor: isDark.value ? '#1f2937' : '#fff',
        borderColor: isDark.value ? '#374151' : '#e5e7eb',
        textStyle: {
          color: isDark.value ? '#f3f4f6' : '#1f2937'
        }
      },
      grid: {
        left: '3%',
        right: '4%',
        bottom: '3%',
        containLabel: true
      },
      xAxis: {
        type: 'category',
        boundaryGap: false,
        data: dates,
        axisLine: {
          lineStyle: {
            color: isDark.value ? '#374151' : '#e5e7eb'
          }
        },
        axisLabel: {
          color: isDark.value ? '#9ca3af' : '#6b7280'
        }
      },
      yAxis: {
        type: 'value',
        minInterval: 1,
        axisLine: {
          show: false
        },
        axisTick: {
          show: false
        },
        splitLine: {
          lineStyle: {
            color: isDark.value ? '#374151' : '#f3f4f6'
          }
        },
        axisLabel: {
          color: isDark.value ? '#9ca3af' : '#6b7280'
        }
      },
      series: [
        {
          name: '新增用户',
          type: 'line',
          smooth: true,
          symbol: 'circle',
          symbolSize: 8,
          itemStyle: {
            color: '#3b82f6'
          },
          lineStyle: {
            width: 3,
            color: '#3b82f6'
          },
          areaStyle: {
            color: new echarts.graphic.LinearGradient(0, 0, 0, 1, [
              { offset: 0, color: 'rgba(59, 130, 246, 0.3)' },
              { offset: 1, color: 'rgba(59, 130, 246, 0.05)' }
            ])
          },
          data: counts
        }
      ]
    }

    chart.setOption(option)
    // 容器可能刚获得尺寸，延迟 resize 确保图表正确渲染
    resizeTimer = setTimeout(() => {
      chart?.resize()
      resizeTimer = null
    }, 100)
  }

  // 监听主题变化
  watch(isDark, () => {
    renderChart()
  })

  // 监听窗口大小
  const handleResize = () => {
    chart?.resize()
  }

  onMounted(() => {
    loadData()
    startAutoRefresh()
    window.addEventListener('resize', handleResize)
  })

  onActivated(() => {
    startAutoRefresh()
    loadData()
  })

  onDeactivated(() => {
    stopAutoRefresh()
  })

  onUnmounted(() => {
    window.removeEventListener('resize', handleResize)
    stopAutoRefresh()
    if (resizeTimer) clearTimeout(resizeTimer)
    chart?.dispose()
  })
</script>

<style scoped lang="scss">
  .trend-panel {
    padding: 0;
    margin-bottom: 14px;
    overflow: hidden;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 8px;
  }

  .trend-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 16px 18px 12px;
    border-bottom: 1px solid var(--el-border-color-lighter);

    h4 {
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

  .chart-body,
  .chart-placeholder,
  .empty-chart {
    height: 320px;
  }

  .chart-body {
    padding: 12px 10px 4px;
  }

  .chart-placeholder,
  .empty-chart {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 18px;
  }

  .empty-chart {
    flex-direction: column;
    gap: 8px;
    font-size: 13px;
    color: var(--el-text-color-secondary);

    .art-svg-icon,
    :deep(svg) {
      font-size: 32px;
      color: var(--el-text-color-placeholder);
    }
  }

  @media (max-width: 640px) {
    .trend-head {
      align-items: flex-start;
      flex-direction: column;
    }
  }
</style>
