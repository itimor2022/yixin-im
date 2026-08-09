<template>
  <div class="security-page">
    <section class="page-head">
      <div>
        <p>系统配置 / 安全审计</p>
        <h1>安全审计</h1>
        <span>查看后台登录、关键设置修改、存储测试和安全事件记录。</span>
      </div>
      <div class="head-actions">
        <ElButton :icon="Refresh" type="primary" :loading="loading || eventLoading" @click="refreshAll">
          刷新日志
        </ElButton>
      </div>
    </section>

    <section class="metric-grid">
      <div class="metric-card">
        <div class="metric-top">
          <span>24 小时登录</span>
          <ElIcon class="info"><Document /></ElIcon>
        </div>
        <strong>{{ formatNumber(summary.total_24h) }}</strong>
        <small>成功和失败总量</small>
      </div>
      <div class="metric-card">
        <div class="metric-top">
          <span>成功</span>
          <ElIcon class="success"><CircleCheck /></ElIcon>
        </div>
        <strong>{{ formatNumber(summary.success_24h) }}</strong>
        <small>最近 24 小时</small>
      </div>
      <div class="metric-card">
        <div class="metric-top">
          <span>失败</span>
          <ElIcon :class="summary.failed_24h > 0 ? 'warning' : 'info'"><WarningFilled /></ElIcon>
        </div>
        <strong>{{ formatNumber(summary.failed_24h) }}</strong>
        <small>用户名、密码或禁用账号</small>
      </div>
      <div class="metric-card">
        <div class="metric-top">
          <span>触发限流</span>
          <ElIcon :class="summary.throttled_24h > 0 ? 'danger' : 'info'"><Lock /></ElIcon>
        </div>
        <strong>{{ formatNumber(summary.throttled_24h) }}</strong>
        <small>{{ throttlePolicy.window_minutes }} 分钟窗口</small>
      </div>
    </section>

    <section class="content-grid">
      <div class="section-card span-4">
        <div class="section-head">
          <div>
            <h2>限流规则</h2>
            <p>连续失败后短暂锁定。</p>
          </div>
        </div>
        <div class="policy-list">
          <div>
            <span>统计窗口</span>
            <b>{{ throttlePolicy.window_minutes }} 分钟</b>
          </div>
          <div>
            <span>IP 失败上限</span>
            <b>{{ throttlePolicy.ip_limit }} 次</b>
          </div>
          <div>
            <span>账号失败上限</span>
            <b>{{ throttlePolicy.account_limit }} 次</b>
          </div>
        </div>
      </div>

      <div class="section-card span-8">
        <div class="section-head">
          <div>
            <h2>登录日志</h2>
            <p>按账号、IP、状态和限流筛选。</p>
          </div>
        </div>
        <div class="filter-bar">
          <ElInput v-model="filters.username" clearable placeholder="账号" class="filter-item" />
          <ElInput v-model="filters.ip" clearable placeholder="IP" class="filter-item" />
          <ElSelect v-model="filters.status" clearable placeholder="状态" class="filter-item">
            <ElOption label="成功" value="success" />
            <ElOption label="失败" value="failed" />
          </ElSelect>
          <ElSelect v-model="filters.throttled" clearable placeholder="限流" class="filter-item">
            <ElOption label="已触发" value="true" />
            <ElOption label="未触发" value="false" />
          </ElSelect>
          <ElButton :icon="Search" :loading="loading" @click="handleSearch">筛选</ElButton>
        </div>
        <ElTable v-loading="loading" :data="logs" class="clean-table mt-4" height="410">
          <ElTableColumn prop="created_at" label="时间" min-width="150" />
          <ElTableColumn prop="username" label="账号" min-width="110" show-overflow-tooltip>
            <template #default="{ row }">{{ row.username || '-' }}</template>
          </ElTableColumn>
          <ElTableColumn prop="ip" label="IP" min-width="120" show-overflow-tooltip />
          <ElTableColumn label="状态" width="86">
            <template #default="{ row }">
              <ElTag :type="row.status === 1 ? 'success' : 'danger'" effect="light">
                {{ row.status === 1 ? '成功' : '失败' }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn label="限流" width="86">
            <template #default="{ row }">
              <ElTag :type="row.throttle_applied ? 'warning' : 'info'" effect="light">
                {{ row.throttle_applied ? '是' : '否' }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn label="原因" min-width="130">
            <template #default="{ row }">{{ reasonLabel(row.failure_reason) }}</template>
          </ElTableColumn>
          <ElTableColumn prop="user_agent" label="User-Agent" min-width="220" show-overflow-tooltip />
          <template #empty>
            <ElEmpty :image-size="92" description="暂无登录日志" />
          </template>
        </ElTable>
        <div class="pagination-row">
          <ElPagination
            v-model:current-page="pagination.page"
            v-model:page-size="pagination.page_size"
            :total="pagination.total"
            :page-sizes="[20, 50, 100]"
            layout="total, sizes, prev, pager, next"
            @size-change="handleSizeChange"
            @current-change="handlePageChange"
          />
        </div>
      </div>
    </section>

    <section class="content-grid">
      <div class="section-card span-12">
        <div class="section-head">
          <div>
            <h2>关键操作审计</h2>
            <p>记录设置修改、存储测试等后台关键操作。</p>
          </div>
        </div>
        <div class="filter-bar">
          <ElSelect v-model="eventFilters.event_type" clearable placeholder="事件类型" class="filter-item">
            <ElOption label="系统设置" value="settings" />
            <ElOption label="存储" value="storage" />
          </ElSelect>
          <ElInput v-model="eventFilters.admin_username" clearable placeholder="管理员" class="filter-item" />
          <ElInput v-model="eventFilters.action" clearable placeholder="动作" class="filter-item" />
          <ElSelect v-model="eventFilters.success" clearable placeholder="结果" class="filter-item">
            <ElOption label="成功" value="true" />
            <ElOption label="失败" value="false" />
          </ElSelect>
          <ElButton :icon="Search" :loading="eventLoading" @click="handleEventSearch">筛选</ElButton>
        </div>
        <ElTable v-loading="eventLoading" :data="events" class="clean-table mt-4" height="330">
          <ElTableColumn prop="created_at" label="时间" min-width="150" />
          <ElTableColumn prop="admin_username" label="管理员" min-width="110" show-overflow-tooltip>
            <template #default="{ row }">{{ row.admin_username || '-' }}</template>
          </ElTableColumn>
          <ElTableColumn prop="event_type" label="类型" width="100">
            <template #default="{ row }">{{ eventTypeLabel(row.event_type) }}</template>
          </ElTableColumn>
          <ElTableColumn prop="action" label="动作" width="120">
            <template #default="{ row }">{{ eventActionLabel(row.action) }}</template>
          </ElTableColumn>
          <ElTableColumn prop="target" label="对象" min-width="130" show-overflow-tooltip />
          <ElTableColumn label="结果" width="86">
            <template #default="{ row }">
              <ElTag :type="row.success ? 'success' : 'danger'" effect="light">
                {{ row.success ? '成功' : '失败' }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="ip" label="IP" min-width="120" show-overflow-tooltip />
          <ElTableColumn label="详情" min-width="260" show-overflow-tooltip>
            <template #default="{ row }">{{ metadataPreview(row.metadata) }}</template>
          </ElTableColumn>
          <ElTableColumn prop="error" label="异常" min-width="180" show-overflow-tooltip>
            <template #default="{ row }">{{ row.error || '-' }}</template>
          </ElTableColumn>
          <template #empty>
            <ElEmpty :image-size="92" description="暂无关键操作审计" />
          </template>
        </ElTable>
        <div class="pagination-row">
          <ElPagination
            v-model:current-page="eventPagination.page"
            v-model:page-size="eventPagination.page_size"
            :total="eventPagination.total"
            :page-sizes="[20, 50, 100]"
            layout="total, sizes, prev, pager, next"
            @size-change="handleEventSizeChange"
            @current-change="handleEventPageChange"
          />
        </div>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
  import { onMounted, reactive, ref } from 'vue'
  import { ElMessage } from 'element-plus'
  import {
    CircleCheck,
    Document,
    Lock,
    Refresh,
    Search,
    WarningFilled
  } from '@element-plus/icons-vue'
  import {
    getAdminSecurityEvents,
    getAdminLoginLogs,
    type AdminSecurityEventItem,
    type AdminLoginLogItem,
    type AdminLoginLogListResponse
  } from '@/api/admin'

  defineOptions({ name: 'SystemSecurity' })

  const loading = ref(false)
  const eventLoading = ref(false)
  const logs = ref<AdminLoginLogItem[]>([])
  const events = ref<AdminSecurityEventItem[]>([])
  const summary = reactive({
    total_24h: 0,
    success_24h: 0,
    failed_24h: 0,
    throttled_24h: 0
  })
  const throttlePolicy = reactive({
    window_minutes: 15,
    ip_limit: 60,
    account_limit: 10
  })
  const filters = reactive({
    username: '',
    ip: '',
    status: '',
    throttled: ''
  })
  const eventFilters = reactive({
    event_type: '',
    admin_username: '',
    action: '',
    success: ''
  })
  const pagination = reactive({
    page: 1,
    page_size: 20,
    total: 0
  })
  const eventPagination = reactive({
    page: 1,
    page_size: 20,
    total: 0
  })

  const formatNumber = (value: number) => Number(value || 0).toLocaleString()

  const reasonLabel = (reason?: string) => {
    const labels: Record<string, string> = {
      not_found: '账号不存在',
      bad_password: '密码错误',
      disabled: '账号禁用',
      throttled: '触发限流'
    }
    return reason ? labels[reason] || reason : '-'
  }

  const eventTypeLabel = (value?: string) => {
    const labels: Record<string, string> = {
      settings: '系统设置',
      storage: '存储'
    }
    return value ? labels[value] || value : '-'
  }

  const eventActionLabel = (value?: string) => {
    const labels: Record<string, string> = {
      update: '更新',
      test_upload: '测试上传'
    }
    return value ? labels[value] || value : '-'
  }

  const metadataPreview = (value?: string) => {
    if (!value) return '-'
    try {
      const data = JSON.parse(value) as Record<string, unknown>
      if (Array.isArray(data.changed_keys)) {
        return `修改 ${data.changed_count || data.changed_keys.length} 项：${data.changed_keys.join('、')}`
      }
      if (data.object_key) {
        return `${data.provider || data.source || '-'} / ${data.object_key}`
      }
    } catch {
      return value
    }
    return value
  }

  const applyResponse = (data: AdminLoginLogListResponse) => {
    // 登录汇总和限流策略随审计列表一并返回，以本次响应作为同一时点的数据快照。
    logs.value = data.list || []
    pagination.total = data.total || 0
    Object.assign(summary, data.summary || {})
    Object.assign(throttlePolicy, data.throttle_policy || {})
  }

  const loadLogs = async () => {
    loading.value = true
    try {
      const data = await getAdminLoginLogs({
        page: pagination.page,
        page_size: pagination.page_size,
        username: filters.username.trim() || undefined,
        ip: filters.ip.trim() || undefined,
        status: filters.status || undefined,
        throttled: filters.throttled || undefined
      })
      applyResponse(data)
    } catch {
      ElMessage.error('读取登录审计失败')
    } finally {
      loading.value = false
    }
  }

  const loadSecurityEvents = async () => {
    eventLoading.value = true
    try {
      const data = await getAdminSecurityEvents({
        page: eventPagination.page,
        page_size: eventPagination.page_size,
        event_type: eventFilters.event_type || undefined,
        admin_username: eventFilters.admin_username.trim() || undefined,
        action: eventFilters.action.trim() || undefined,
        success: eventFilters.success || undefined
      })
      events.value = data.list || []
      eventPagination.total = data.total || 0
    } catch {
      ElMessage.error('读取关键操作审计失败')
    } finally {
      eventLoading.value = false
    }
  }

  const handleSearch = () => {
    pagination.page = 1
    loadLogs()
  }

  const handleSizeChange = (size: number) => {
    pagination.page_size = size
    pagination.page = 1
    loadLogs()
  }

  const handlePageChange = (page: number) => {
    pagination.page = page
    loadLogs()
  }

  const handleEventSearch = () => {
    eventPagination.page = 1
    loadSecurityEvents()
  }

  const handleEventSizeChange = (size: number) => {
    eventPagination.page_size = size
    eventPagination.page = 1
    loadSecurityEvents()
  }

  const handleEventPageChange = (page: number) => {
    eventPagination.page = page
    loadSecurityEvents()
  }

  const refreshAll = () => {
    // 登录审计与安全事件使用独立筛选和分页，刷新时分别请求，互不覆盖状态。
    loadLogs()
    loadSecurityEvents()
  }

  onMounted(refreshAll)
</script>

<style lang="scss" scoped>
  .security-page {
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

  .policy-list {
    display: grid;
    gap: 10px;
  }

  .policy-list div {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 12px;
    background: #f8fafc;
    border: 1px solid #edf2f7;
    border-radius: 8px;
  }

  .policy-list span {
    color: #64748b;
    font-size: 13px;
  }

  .policy-list b {
    color: #111827;
    font-size: 13px;
  }

  .filter-bar {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    align-items: center;
  }

  .filter-item {
    width: 150px;
  }

  .clean-table {
    --el-table-border-color: #edf2f7;
    --el-table-header-bg-color: #f8fafc;
    --el-table-header-text-color: #475569;

    border: 1px solid #edf2f7;
    border-radius: 8px;
  }

  .pagination-row {
    display: flex;
    justify-content: flex-end;
    margin-top: 14px;
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
    .security-page {
      padding: 12px;
    }

    .page-head,
    .head-actions {
      flex-direction: column;
    }

    .metric-grid {
      grid-template-columns: 1fr;
    }

    .filter-item {
      width: 100%;
    }

    .pagination-row {
      justify-content: flex-start;
      overflow-x: auto;
    }
  }
</style>
