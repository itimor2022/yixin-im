<template>
  <ElRow :gutter="20" class="mb-5">
    <ElCol :span="24">
      <div class="art-card p-5">
        <div class="flex items-center justify-between gap-4 mb-4">
          <div>
            <div class="text-base font-semibold text-g-800">服务器运行状态</div>
            <div class="text-xs text-g-400 mt-1">
              {{ runtime?.server_time || '正在加载...' }}
            </div>
          </div>
          <ElTag :type="overallStatusType" effect="light">
            {{ overallStatusText }}
          </ElTag>
        </div>

        <ElRow :gutter="16">
          <ElCol :xs="12" :sm="12" :md="6" :lg="4">
            <div class="status-metric">
              <span class="label">运行时长</span>
              <span class="value">{{ runtime?.uptime_text || '-' }}</span>
            </div>
          </ElCol>
          <ElCol :xs="12" :sm="12" :md="6" :lg="4">
            <div class="status-metric">
              <span class="label">Go 版本</span>
              <span class="value">{{ runtime?.go_version || '-' }}</span>
            </div>
          </ElCol>
          <ElCol :xs="12" :sm="12" :md="6" :lg="4">
            <div class="status-metric">
              <span class="label">协程数</span>
              <span class="value">{{ runtime?.goroutines ?? '-' }}</span>
            </div>
          </ElCol>
          <ElCol :xs="12" :sm="12" :md="6" :lg="4">
            <div class="status-metric">
              <span class="label">CPU 核心</span>
              <span class="value">{{ runtime?.cpu_num ?? '-' }}</span>
            </div>
          </ElCol>
          <ElCol :xs="12" :sm="12" :md="6" :lg="4">
            <div class="status-metric">
              <span class="label">内存占用</span>
              <span class="value">{{ runtime ? `${runtime.memory_alloc_mb} MB` : '-' }}</span>
            </div>
          </ElCol>
          <ElCol :xs="12" :sm="12" :md="6" :lg="4">
            <div class="status-metric">
              <span class="label">Heap</span>
              <span class="value">{{ runtime ? `${runtime.heap_inuse_mb} MB` : '-' }}</span>
            </div>
          </ElCol>
        </ElRow>

        <ElDivider class="my-4" />

        <ElRow :gutter="16">
          <ElCol :xs="12" :sm="12" :md="6">
            <div class="status-metric">
              <span class="label">消息发送队列</span>
              <span class="value">{{ runtime?.queue_message_send ?? '-' }}</span>
            </div>
          </ElCol>
          <ElCol :xs="12" :sm="12" :md="6">
            <div class="status-metric">
              <span class="label">消息同步队列</span>
              <span class="value">{{ runtime?.queue_message_sync ?? '-' }}</span>
            </div>
          </ElCol>
          <ElCol :xs="12" :sm="12" :md="6">
            <div class="status-metric">
              <span class="label">推送通知队列</span>
              <span class="value">{{ runtime?.queue_push_notify ?? '-' }}</span>
            </div>
          </ElCol>
          <ElCol :xs="12" :sm="12" :md="6">
            <div class="status-metric" :class="{ alert: (runtime?.queue_dead || 0) > 0 }">
              <span class="label">延迟 / 死信</span>
              <span class="value">
                {{ runtime ? `${runtime.queue_delayed} / ${runtime.queue_dead}` : '-' }}
              </span>
            </div>
          </ElCol>
        </ElRow>

        <ElDivider class="my-4" />

        <ElRow :gutter="16">
          <ElCol :xs="24" :md="8">
            <div class="dep-item">
              <div class="dep-head">
                <span>MySQL</span>
                <ElTag :type="statusType(runtime?.mysql_status)">
                  {{ runtime?.mysql_status || '-' }}
                </ElTag>
              </div>
              <div class="dep-error">{{ runtime?.mysql_error || '连接正常' }}</div>
            </div>
          </ElCol>
          <ElCol :xs="24" :md="8">
            <div class="dep-item">
              <div class="dep-head">
                <span>MongoDB</span>
                <ElTag :type="statusType(runtime?.mongo_status)">
                  {{ runtime?.mongo_status || '-' }}
                </ElTag>
              </div>
              <div class="dep-error">{{ runtime?.mongo_error || '连接正常' }}</div>
            </div>
          </ElCol>
          <ElCol :xs="24" :md="8">
            <div class="dep-item">
              <div class="dep-head">
                <span>Redis</span>
                <ElTag :type="statusType(runtime?.redis_status)">
                  {{ runtime?.redis_status || '-' }}
                </ElTag>
              </div>
              <div class="dep-error">{{ runtime?.redis_error || '连接正常' }}</div>
            </div>
          </ElCol>
        </ElRow>
      </div>
    </ElCol>
  </ElRow>
</template>

<script setup lang="ts">
  import { getRuntimeStatus, type RuntimeStatus } from '@/api/admin'
  import { ElMessage } from 'element-plus'

  const runtime = ref<RuntimeStatus | null>(null)

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
  .status-metric {
    padding: 12px 14px;
    border-radius: 8px;
    background: rgba(var(--el-color-primary-rgb), 0.04);
    height: 100%;

    &.alert {
      background: rgba(var(--el-color-danger-rgb), 0.08);
    }

    .label {
      display: block;
      font-size: 12px;
      color: var(--el-text-color-secondary);
      margin-bottom: 6px;
    }

    .value {
      display: block;
      font-size: 16px;
      font-weight: 600;
      color: var(--el-text-color-primary);
      word-break: break-all;
    }
  }

  .dep-item {
    padding: 12px 14px;
    border-radius: 8px;
    background: var(--el-fill-color-light);
    min-height: 92px;

    .dep-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      font-size: 14px;
      font-weight: 600;
      margin-bottom: 10px;
    }

    .dep-error {
      font-size: 12px;
      color: var(--el-text-color-secondary);
      line-height: 1.6;
      word-break: break-word;
    }
  }
</style>
