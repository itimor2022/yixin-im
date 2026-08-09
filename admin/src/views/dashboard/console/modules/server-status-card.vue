<template>
  <div class="art-card runtime-panel">
    <div class="runtime-head">
      <div>
        <h4>服务器运行状态</h4>
        <p>{{ runtime?.server_time || '正在加载...' }}</p>
      </div>
      <ElTag :type="overallStatusType" effect="plain">{{ overallStatusText }}</ElTag>
    </div>

    <div class="metric-grid">
      <div v-for="item in runtimeMetrics" :key="item.label" class="metric-cell">
        <span>{{ item.label }}</span>
        <strong>{{ item.value }}</strong>
      </div>
    </div>

    <div class="section-title">队列积压</div>
    <div class="queue-grid">
      <div v-for="item in queueMetrics" :key="item.label" class="queue-cell" :class="{ alert: item.alert }">
        <span>{{ item.label }}</span>
        <strong>{{ item.value }}</strong>
      </div>
    </div>

    <div class="section-title">依赖服务</div>
    <div class="dep-grid">
      <div v-for="item in dependencyMetrics" :key="item.name" class="dep-row">
        <div class="dep-name">
          <span class="status-dot" :class="item.status"></span>
          <strong>{{ item.name }}</strong>
        </div>
        <ElTag :type="statusType(item.rawStatus)" effect="plain" size="small">
          {{ item.rawStatus || '-' }}
        </ElTag>
        <span class="dep-error">{{ item.error || '连接正常' }}</span>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { getRuntimeStatus, type RuntimeStatus } from '@/api/admin'
  import { ElMessage } from 'element-plus'

  const runtime = ref<RuntimeStatus | null>(null)

  const runtimeMetrics = computed(() => [
    { label: '运行时长', value: runtime.value?.uptime_text || '-' },
    { label: 'Go 版本', value: runtime.value?.go_version || '-' },
    { label: '协程数', value: runtime.value?.goroutines ?? '-' },
    { label: 'CPU 核心', value: runtime.value?.cpu_num ?? '-' },
    { label: '内存占用', value: runtime.value ? `${runtime.value.memory_alloc_mb} MB` : '-' },
    { label: 'Heap', value: runtime.value ? `${runtime.value.heap_inuse_mb} MB` : '-' }
  ])

  const queueMetrics = computed(() => [
    { label: '消息发送', value: runtime.value?.queue_message_send ?? '-' },
    { label: '消息同步', value: runtime.value?.queue_message_sync ?? '-' },
    { label: '推送通知', value: runtime.value?.queue_push_notify ?? '-' },
    {
      label: '延迟 / 死信',
      value: runtime.value ? `${runtime.value.queue_delayed} / ${runtime.value.queue_dead}` : '-',
      alert: (runtime.value?.queue_dead || 0) > 0
    }
  ])

  const dependencyMetrics = computed(() => [
    {
      name: 'MySQL',
      rawStatus: runtime.value?.mysql_status,
      status: runtime.value?.mysql_status === 'ok' ? 'ok' : 'warn',
      error: runtime.value?.mysql_error
    },
    {
      name: 'MongoDB',
      rawStatus: runtime.value?.mongo_status,
      status: runtime.value?.mongo_status === 'ok' ? 'ok' : 'warn',
      error: runtime.value?.mongo_error
    },
    {
      name: 'Redis',
      rawStatus: runtime.value?.redis_status,
      status: runtime.value?.redis_status === 'ok' ? 'ok' : 'warn',
      error: runtime.value?.redis_error
    }
  ])

  const statusType = (status?: string | null) => {
    if (status === 'ok') return 'success'
    if (status === 'error') return 'danger'
    return 'info'
  }

  const overallStatusType = computed(() => {
    if (!runtime.value) return 'info'
    return [
      runtime.value.mysql_status,
      runtime.value.mongo_status,
      runtime.value.redis_status
    ].every((item) => item === 'ok')
      ? 'success'
      : 'warning'
  })

  const overallStatusText = computed(() => {
    if (!runtime.value) return '加载中'
    return [
      runtime.value.mysql_status,
      runtime.value.mongo_status,
      runtime.value.redis_status
    ].every((item) => item === 'ok')
      ? '服务正常'
      : '部分异常'
  })

  const loadRuntime = async () => {
    try {
      runtime.value = await getRuntimeStatus()
    } catch (error) {
      console.error('加载服务器状态失败', error)
      ElMessage.error('加载服务器状态失败')
    }
  }

  onMounted(() => {
    loadRuntime()
    const timer = setInterval(loadRuntime, 30000)
    onUnmounted(() => clearInterval(timer))
  })
</script>

<style scoped lang="scss">
  .runtime-panel {
    padding: 0;
    margin-bottom: 14px;
    overflow: hidden;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 8px;
  }

  .runtime-head {
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

  .metric-grid,
  .queue-grid {
    display: grid;
    grid-template-columns: repeat(6, minmax(0, 1fr));
    border-bottom: 1px solid var(--el-border-color-lighter);
  }

  .queue-grid {
    grid-template-columns: repeat(4, minmax(0, 1fr));
  }

  .metric-cell,
  .queue-cell {
    min-width: 0;
    padding: 13px 18px;
    border-right: 1px solid var(--el-border-color-lighter);

    &:last-child {
      border-right: 0;
    }

    span {
      display: block;
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }

    strong {
      display: block;
      margin-top: 6px;
      overflow: hidden;
      font-size: 15px;
      font-weight: 650;
      color: var(--el-text-color-primary);
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }

  .queue-cell.alert strong {
    color: var(--el-color-danger);
  }

  .section-title {
    padding: 12px 18px 8px;
    font-size: 12px;
    font-weight: 650;
    color: var(--el-text-color-secondary);
    background: var(--el-fill-color-extra-light);
    border-bottom: 1px solid var(--el-border-color-lighter);
  }

  .dep-grid {
    padding: 0 18px;
  }

  .dep-row {
    display: grid;
    grid-template-columns: minmax(120px, 1fr) 86px minmax(180px, 2fr);
    align-items: center;
    gap: 12px;
    min-height: 50px;
    border-bottom: 1px solid var(--el-border-color-extra-light);

    &:last-child {
      border-bottom: 0;
    }
  }

  .dep-name {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;

    strong {
      font-size: 13px;
      color: var(--el-text-color-primary);
    }
  }

  .status-dot {
    width: 7px;
    height: 7px;
    flex: 0 0 7px;
    border-radius: 50%;
    background: var(--el-color-warning);

    &.ok {
      background: var(--el-color-success);
    }
  }

  .dep-error {
    overflow: hidden;
    font-size: 12px;
    color: var(--el-text-color-secondary);
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  @media (max-width: 1100px) {
    .metric-grid {
      grid-template-columns: repeat(3, minmax(0, 1fr));
    }

    .metric-cell:nth-child(3n) {
      border-right: 0;
    }

    .metric-cell:nth-child(-n + 3) {
      border-bottom: 1px solid var(--el-border-color-lighter);
    }
  }

  @media (max-width: 768px) {
    .runtime-head {
      align-items: flex-start;
      flex-direction: column;
    }

    .metric-grid,
    .queue-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .dep-row {
      grid-template-columns: 1fr auto;
    }

    .dep-error {
      grid-column: 1 / -1;
      padding-bottom: 10px;
    }
  }
</style>
