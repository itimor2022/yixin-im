<template>
  <div class="push-report-page">
    <section class="page-head">
      <div>
        <p>系统配置 / 推送运营</p>
        <h1>推送报表</h1>
        <span>查看最近 24 小时投递质量、厂商通道状态、测试投递与失败日志。</span>
      </div>
      <div class="head-actions">
        <ElButton :icon="Setting" @click="goConfig">推送配置</ElButton>
        <ElButton type="primary" :icon="Refresh" :loading="statsLoading || logsLoading" @click="refreshMonitor">
          刷新报表
        </ElButton>
      </div>
    </section>

    <ElAlert v-if="monitorChecked && !monitorAvailable" type="warning" :closable="false" show-icon class="mb-4">
      推送报表接口暂未接入或当前后端版本未部署完成，配置页仍可正常使用。
    </ElAlert>

    <section class="metric-grid">
      <div v-for="item in metricCards" :key="item.label" class="metric-card">
        <div class="metric-top">
          <span>{{ item.label }}</span>
          <ElIcon :class="item.tone"><component :is="item.icon" /></ElIcon>
        </div>
        <strong>{{ item.value }}</strong>
        <small>{{ item.caption }}</small>
      </div>
    </section>

    <section class="content-grid">
      <div class="section-card span-8">
        <div class="section-head">
          <div>
            <h2>通道状态</h2>
            <p>按启用状态、配置完整度和最近测试结果汇总。</p>
          </div>
        </div>
        <ElTable :data="vendorRows" class="clean-table" height="392">
          <ElTableColumn label="通道" width="150">
            <template #default="{ row }">
              <div class="channel-name">
                <span class="channel-dot" :class="row.ready ? 'ready' : row.enabled ? 'warn' : ''" />
                <span>{{ row.name }}</span>
              </div>
            </template>
          </ElTableColumn>
          <ElTableColumn label="启用" width="100">
            <template #default="{ row }">
              <ElTag :type="row.enabled ? 'success' : 'info'" effect="light">
                {{ row.enabled ? '已启用' : '未启用' }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn label="配置状态" width="120">
            <template #default="{ row }">
              <ElTag :type="row.ready ? 'success' : row.enabled ? 'warning' : 'info'" effect="light">
                {{ row.ready ? '完整' : row.enabled ? '待补齐' : '未配置' }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="lastResult" label="最近测试" width="110" />
          <ElTableColumn prop="note" label="说明" min-width="240" show-overflow-tooltip />
        </ElTable>
      </div>

      <div class="section-card span-4">
        <div class="section-head">
          <div>
            <h2>监控概览</h2>
            <p>最近 24 小时通道质量。</p>
          </div>
        </div>
        <ElTable :data="channelStatsRows" class="clean-table compact-table" height="392">
          <ElTableColumn prop="name" label="通道" min-width="90" />
          <ElTableColumn prop="total" label="发送" width="76" />
          <ElTableColumn label="成功率" width="92">
            <template #default="{ row }">{{ formatRate(row.rate) }}</template>
          </ElTableColumn>
        </ElTable>
      </div>
    </section>

    <section class="content-grid">
      <div class="section-card span-5">
        <div class="section-head">
          <div>
            <h2>测试推送</h2>
            <p>向指定用户或设备提交一次测试投递。</p>
          </div>
        </div>
        <ElForm :model="testForm" label-position="top" class="form-grid">
          <ElFormItem label="测试目标">
            <ElRadioGroup v-model="testTarget" :disabled="isDemoAdmin">
              <ElRadio value="user">用户 ID</ElRadio>
              <ElRadio value="device">设备 ID</ElRadio>
            </ElRadioGroup>
          </ElFormItem>
          <ElFormItem :label="testTarget === 'user' ? '用户 ID' : '设备 ID'">
            <ElInputNumber
              v-model="testForm.target_id"
              :min="1"
              :disabled="isDemoAdmin"
              controls-position="right"
              class="w-full"
            />
          </ElFormItem>
          <ElFormItem label="推送场景">
            <ElSelect v-model="testForm.scene" :disabled="isDemoAdmin" class="w-full">
              <ElOption label="聊天消息" value="chat_message" />
              <ElOption label="好友申请" value="friend_request" />
              <ElOption label="群通知" value="group_notice" />
              <ElOption label="系统通知" value="system_notice" />
              <ElOption label="运营通知" value="marketing_notice" />
            </ElSelect>
          </ElFormItem>
          <ElFormItem label="标题">
            <ElInput v-model="testForm.title" :disabled="isDemoAdmin" />
          </ElFormItem>
          <ElFormItem label="内容">
            <ElInput v-model="testForm.body" :disabled="isDemoAdmin" />
          </ElFormItem>
          <ElFormItem v-if="!isDemoAdmin">
            <ElButton type="primary" :loading="testing" @click="sendTest">发送测试推送</ElButton>
            <ElButton :loading="logsLoading" @click="loadLogs">刷新日志</ElButton>
          </ElFormItem>
        </ElForm>
      </div>

      <div class="section-card span-7">
        <div class="section-head">
          <div>
            <h2>推送日志</h2>
            <p>最近投递记录、失败原因和设备信息。</p>
          </div>
        </div>
        <div class="log-filter-bar">
          <ElSelect v-model="logFilters.channel" clearable placeholder="通道" class="filter-item">
            <ElOption label="JPush" value="jpush" />
            <ElOption label="APNs" value="apns" />
            <ElOption label="FCM" value="fcm" />
            <ElOption label="HMS" value="hms" />
            <ElOption label="小米" value="xiaomi" />
            <ElOption label="OPPO" value="oppo" />
          </ElSelect>
          <ElSelect v-model="logFilters.success" clearable placeholder="状态" class="filter-item">
            <ElOption label="成功" value="true" />
            <ElOption label="失败" value="false" />
          </ElSelect>
          <ElInput v-model="logFilters.user_id" clearable placeholder="用户 ID" class="filter-item" />
          <ElInput v-model="logFilters.device_id" clearable placeholder="设备 ID" class="filter-item" />
          <ElButton :icon="Search" :loading="logsLoading" @click="loadLogs">筛选</ElButton>
        </div>
        <ElTable v-loading="logsLoading" :data="logs" class="clean-table mt-4" height="360">
          <ElTableColumn prop="occurred_at" label="时间" min-width="150" />
          <ElTableColumn prop="channel" label="通道" width="92" />
          <ElTableColumn prop="scene" label="场景" width="120" />
          <ElTableColumn label="状态" width="82">
            <template #default="{ row }">
              <ElTag :type="row.success ? 'success' : 'danger'" effect="light">
                {{ row.success ? '成功' : '失败' }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="user_id" label="用户" width="80" />
          <ElTableColumn prop="device_key" label="设备" min-width="130" show-overflow-tooltip />
          <ElTableColumn prop="title" label="标题" min-width="120" show-overflow-tooltip />
          <ElTableColumn prop="error" label="错误" min-width="180" show-overflow-tooltip />
          <template #empty>
            <ElEmpty :image-size="92" description="暂无推送日志" />
          </template>
        </ElTable>
      </div>
    </section>

    <section class="content-grid">
      <div class="section-card span-12">
        <div class="section-head">
          <div>
            <h2>设备 Token 管理</h2>
            <p>查看设备推送 token 状态、最近投递结果，并清理已失效 token。</p>
          </div>
          <div class="section-actions">
            <ElButton :icon="Refresh" :loading="devicesLoading" @click="loadDevices">刷新设备</ElButton>
            <ElButton
              type="warning"
              :icon="WarningFilled"
              :loading="cleanupLoading"
              :disabled="isDemoAdmin"
              @click="previewInvalidCleanup"
            >
              预检无效 Token
            </ElButton>
            <ElButton
              type="danger"
              :icon="Delete"
              :loading="cleanupLoading"
              :disabled="isDemoAdmin"
              @click="runInvalidCleanup"
            >
              清理无效 Token
            </ElButton>
          </div>
        </div>

        <ElAlert
          v-if="cleanupResult"
          :type="cleanupResult.cleared_count > 0 ? 'success' : 'info'"
          :closable="false"
          show-icon
          class="mb-3"
        >
          <template #title>
            {{ cleanupResult.dry_run ? '预检完成' : '清理完成' }}：匹配
            {{ cleanupResult.matched_count }} 个设备，已清理 {{ cleanupResult.cleared_count }} 个 token。
          </template>
        </ElAlert>

        <div class="log-filter-bar">
          <ElSelect v-model="deviceFilters.channel" clearable placeholder="通道" class="filter-item">
            <ElOption label="JPush" value="jpush" />
            <ElOption label="APNs" value="apns" />
            <ElOption label="FCM" value="fcm" />
            <ElOption label="HMS" value="hms" />
            <ElOption label="小米" value="xiaomi" />
            <ElOption label="OPPO" value="oppo" />
          </ElSelect>
          <ElSelect v-model="deviceFilters.bound" clearable placeholder="Token 状态" class="filter-item">
            <ElOption label="已绑定" value="true" />
            <ElOption label="未绑定" value="false" />
          </ElSelect>
          <ElInput v-model="deviceFilters.user_id" clearable placeholder="用户 ID" class="filter-item" />
          <ElInput
            v-model="deviceFilters.keyword"
            clearable
            placeholder="设备/型号/版本"
            class="filter-keyword"
            @keyup.enter="loadDevices"
          />
          <ElButton :icon="Search" :loading="devicesLoading" @click="loadDevices">筛选</ElButton>
        </div>

        <ElTable v-loading="devicesLoading" :data="devices" class="clean-table mt-4" height="420">
          <ElTableColumn prop="id" label="ID" width="76" />
          <ElTableColumn label="用户" min-width="150" show-overflow-tooltip>
            <template #default="{ row }">
              <div class="device-user">
                <strong>{{ row.user?.nickname || row.user?.username || `用户 ${row.user_id}` }}</strong>
                <span>ID {{ row.user_id }}</span>
              </div>
            </template>
          </ElTableColumn>
          <ElTableColumn label="设备" min-width="220" show-overflow-tooltip>
            <template #default="{ row }">
              <div class="device-user">
                <strong>{{ row.device_name || row.model || row.device_id }}</strong>
                <span>{{ row.brand || '-' }} {{ row.model || '' }} · {{ row.app_version || '-' }}</span>
              </div>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="push_channel" label="通道" width="92" />
          <ElTableColumn label="Token" width="122">
            <template #default="{ row }">
              <ElTag :type="row.push_token_bound ? 'success' : 'warning'" effect="light">
                {{ row.push_token_bound ? `已绑定 ${row.push_token_length}` : '未绑定' }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="failed_7d" label="7天失败" width="92" />
          <ElTableColumn label="最近推送" min-width="190" show-overflow-tooltip>
            <template #default="{ row }">
              <div v-if="row.last_push" class="last-push">
                <ElTag :type="row.last_push.success ? 'success' : 'danger'" effect="light" size="small">
                  {{ row.last_push.success ? '成功' : '失败' }}
                </ElTag>
                <span>{{ row.last_push.occurred_at }}</span>
                <small v-if="row.last_push.error">{{ row.last_push.error }}</small>
              </div>
              <span v-else class="muted-text">暂无</span>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="last_active" label="最后活跃" min-width="150" />
          <ElTableColumn label="操作" width="158" fixed="right">
            <template #default="{ row }">
              <ElButton
                type="danger"
                link
                :icon="Delete"
                :disabled="isDemoAdmin || !row.push_token_bound"
                :loading="disabledTokenLoading[row.id]"
                @click="disableDeviceToken(row)"
              >
                停用 Token
              </ElButton>
            </template>
          </ElTableColumn>
          <template #empty>
            <ElEmpty :image-size="92" description="暂无推送设备" />
          </template>
        </ElTable>

        <div class="table-footer">
          <span>共 {{ deviceTotal }} 台设备</span>
          <ElPagination
            v-model:current-page="deviceFilters.page"
            v-model:page-size="deviceFilters.page_size"
            :page-sizes="[10, 20, 50, 100]"
            :total="deviceTotal"
            layout="sizes, prev, pager, next"
            small
            @size-change="loadDevices"
            @current-change="loadDevices"
          />
        </div>
      </div>
    </section>
  </div>
</template>

<script setup lang="ts">
  import { computed, reactive, ref, onMounted } from 'vue'
  import { useRouter } from 'vue-router'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import {
    CircleCheck,
    DataAnalysis,
    Delete,
    Document,
    Refresh,
    Search,
    Setting,
    WarningFilled
  } from '@element-plus/icons-vue'
  import {
    cleanupInvalidPushTokens,
    disablePushDeviceToken,
    getPushDevices,
    getPushLogs,
    getPushStats,
    getSystemSettings,
    sendPushTest,
    type PushCleanupInvalidTokensResponse,
    type PushAggregateItem,
    type PushDeviceItem,
    type PushLogItem,
    type PushStatsResponse,
    type SystemSettings
  } from '@/api/admin'

  defineOptions({ name: 'PushReport' })

  const router = useRouter()
  // 配置、日志、统计和设备列表来自独立数据源，各自失败时仍允许其他区域继续展示。
  const isDemoAdmin = ref(false)
  const testing = ref(false)
  const logsLoading = ref(false)
  const statsLoading = ref(false)
  const devicesLoading = ref(false)
  const cleanupLoading = ref(false)
  const monitorAvailable = ref(true)
  const monitorChecked = ref(false)
  const testTarget = ref<'user' | 'device'>('user')
  const logs = ref<PushLogItem[]>([])
  const pushStats = ref<PushStatsResponse | null>(null)
  const devices = ref<PushDeviceItem[]>([])
  const deviceTotal = ref(0)
  const cleanupResult = ref<PushCleanupInvalidTokensResponse | null>(null)
  const disabledTokenLoading = reactive<Record<number, boolean>>({})

  const logFilters = reactive({
    channel: '',
    success: '',
    user_id: '',
    device_id: ''
  })

  const deviceFilters = reactive({
    page: 1,
    page_size: 20,
    channel: '',
    bound: '',
    user_id: '',
    keyword: ''
  })

  const settings = reactive({
    apns_enabled: false,
    apns_bundle_id: '',
    apns_key_id: '',
    apns_team_id: '',
    apns_auth_key: '',
    fcm_enabled: false,
    fcm_project_id: '',
    fcm_service_account_json: '',
    hms_enabled: false,
    hms_app_id: '',
    hms_app_secret: '',
    jpush_enabled: false,
    jpush_app_key: '',
    jpush_master_secret: '',
    xiaomi_push_enabled: false,
    xiaomi_package_name: '',
    xiaomi_app_secret: '',
    oppo_push_enabled: false,
    oppo_app_key: '',
    oppo_app_secret: ''
  })

  const testForm = reactive({
    target_id: 1,
    scene: 'system_notice',
    title: '推送测试',
    body: '这是一条后台推送测试消息'
  })

  const safeNumber = (value?: number) => Number(value || 0)
  const formatRate = (value?: number) => `${safeNumber(value).toFixed(1)}%`
  const goConfig = () => router.push('/system/push-config')

  const metricCards = computed(() => [
    {
      label: '24 小时发送',
      value: safeNumber(pushStats.value?.total).toLocaleString(),
      caption: !monitorChecked.value
        ? '待刷新'
        : monitorAvailable.value
          ? '全部通道提交量'
          : '监控待接入',
      icon: DataAnalysis,
      tone: 'info'
    },
    {
      label: '成功率',
      value: formatRate(pushStats.value?.success_rate),
      caption: `${safeNumber(pushStats.value?.success)} 成功 / ${safeNumber(pushStats.value?.failed)} 失败`,
      icon: CircleCheck,
      tone: 'success'
    },
    {
      label: '异常通道',
      value: safeNumber(pushStats.value?.unhealthy_channels).toLocaleString(),
      caption: '低成功率通道数量',
      icon: WarningFilled,
      tone: safeNumber(pushStats.value?.unhealthy_channels) > 0 ? 'danger' : 'success'
    },
    {
      label: '无效设备',
      value: safeNumber(pushStats.value?.invalid_device_count).toLocaleString(),
      caption: '未绑定或失效 Token',
      icon: Document,
      tone: 'warning'
    }
  ])

  const emptyChannelStats: PushAggregateItem[] = [
    { name: 'apns', total: 0, success: 0, failed: 0, rate: 0 },
    { name: 'jpush', total: 0, success: 0, failed: 0, rate: 0 },
    { name: 'fcm', total: 0, success: 0, failed: 0, rate: 0 },
    { name: 'hms', total: 0, success: 0, failed: 0, rate: 0 }
  ]

  const channelStatsRows = computed(() => {
    const rows = pushStats.value?.channel_stats || []
    return rows.length > 0 ? rows : emptyChannelStats
  })

  const findRecentLog = (channel: string) => logs.value.find((item) => item.channel === channel)

  const recentText = (channel: string) => {
    const item = findRecentLog(channel)
    if (!item) return '暂无'
    return item.success ? '成功' : '失败'
  }

  const jpushReady = computed(
    () => settings.jpush_enabled && !!settings.jpush_app_key && !!settings.jpush_master_secret
  )

  const vendorRows = computed(() => [
    {
      name: 'APNs',
      enabled: settings.apns_enabled,
      ready:
        settings.apns_enabled &&
        !!settings.apns_bundle_id &&
        !!settings.apns_key_id &&
        !!settings.apns_team_id &&
        !!settings.apns_auth_key,
      lastResult: recentText('apns'),
      note: 'iOS 离线通知'
    },
    {
      name: 'JPush',
      enabled: settings.jpush_enabled,
      ready: jpushReady.value,
      lastResult: recentText('jpush'),
      note: '统一通道，承接 Android 厂商通道和分类策略'
    },
    {
      name: 'FCM',
      enabled: settings.fcm_enabled,
      ready: settings.fcm_enabled && !!settings.fcm_project_id && !!settings.fcm_service_account_json,
      lastResult: recentText('fcm'),
      note: '海外 Android / Google Play 设备'
    },
    {
      name: 'HMS',
      enabled: settings.hms_enabled,
      ready: settings.hms_enabled && !!settings.hms_app_id && !!settings.hms_app_secret,
      lastResult: recentText('hms'),
      note: '华为设备原生通道'
    },
    {
      name: '小米',
      enabled: settings.xiaomi_push_enabled,
      ready:
        settings.xiaomi_push_enabled &&
        !!settings.xiaomi_package_name &&
        !!settings.xiaomi_app_secret,
      lastResult: recentText('xiaomi'),
      note: '小米 / Redmi 原生通道'
    },
    {
      name: 'OPPO',
      enabled: settings.oppo_push_enabled,
      ready: settings.oppo_push_enabled && !!settings.oppo_app_key && !!settings.oppo_app_secret,
      lastResult: recentText('oppo'),
      note: 'OPPO / 一加 / realme 原生通道'
    },
    {
      name: '荣耀',
      enabled: settings.jpush_enabled,
      ready: jpushReady.value,
      lastResult: recentText('jpush'),
      note: '通过极光厂商通道承接'
    },
    {
      name: 'vivo / 魅族',
      enabled: settings.jpush_enabled,
      ready: jpushReady.value,
      lastResult: recentText('jpush'),
      note: '通过极光厂商通道承接'
    }
  ])

  const applySettings = (data: SystemSettings) => {
    isDemoAdmin.value = data._admin_role === 'demo_admin'
    settings.apns_enabled = data.apns_enabled || false
    settings.apns_bundle_id = data.apns_bundle_id || ''
    settings.apns_key_id = data.apns_key_id || ''
    settings.apns_team_id = data.apns_team_id || ''
    settings.apns_auth_key = data.apns_auth_key || ''
    settings.fcm_enabled = data.fcm_enabled || false
    settings.fcm_project_id = data.fcm_project_id || ''
    settings.fcm_service_account_json = data.fcm_service_account_json || ''
    settings.hms_enabled = data.hms_enabled || false
    settings.hms_app_id = data.hms_app_id || ''
    settings.hms_app_secret = data.hms_app_secret || ''
    settings.jpush_enabled = data.jpush_enabled || false
    settings.jpush_app_key = data.jpush_app_key || ''
    settings.jpush_master_secret = data.jpush_master_secret || ''
    settings.xiaomi_push_enabled = data.xiaomi_push_enabled || false
    settings.xiaomi_package_name = data.xiaomi_package_name || ''
    settings.xiaomi_app_secret = data.xiaomi_app_secret || ''
    settings.oppo_push_enabled = data.oppo_push_enabled || false
    settings.oppo_app_key = data.oppo_app_key || ''
    settings.oppo_app_secret = data.oppo_app_secret || ''
  }

  const loadPushSettings = async () => {
    try {
      applySettings(await getSystemSettings())
    } catch {
      ElMessage.error('加载推送配置失败')
    }
  }

  const loadLogs = async () => {
    logsLoading.value = true
    try {
      const result = await getPushLogs({
        page: 1,
        page_size: 20,
        channel: logFilters.channel || undefined,
        success: logFilters.success || undefined,
        user_id: logFilters.user_id || undefined,
        device_id: logFilters.device_id || undefined
      })
      logs.value = result.list || []
      monitorAvailable.value = true
      monitorChecked.value = true
    } catch {
      logs.value = []
      monitorAvailable.value = false
      monitorChecked.value = true
    } finally {
      logsLoading.value = false
    }
  }

  const loadStats = async () => {
    statsLoading.value = true
    try {
      pushStats.value = await getPushStats({ hours: 24 })
      monitorAvailable.value = true
      monitorChecked.value = true
    } catch {
      pushStats.value = null
      monitorAvailable.value = false
      monitorChecked.value = true
    } finally {
      statsLoading.value = false
    }
  }

  const refreshMonitor = async () => {
    await Promise.allSettled([loadLogs(), loadStats(), loadDevices()])
  }

  const loadDevices = async () => {
    devicesLoading.value = true
    try {
      const result = await getPushDevices({
        page: deviceFilters.page,
        page_size: deviceFilters.page_size,
        channel: deviceFilters.channel || undefined,
        bound: deviceFilters.bound || undefined,
        user_id: deviceFilters.user_id || undefined,
        keyword: deviceFilters.keyword || undefined
      })
      devices.value = result.list || []
      deviceTotal.value = result.total || 0
      monitorAvailable.value = true
      monitorChecked.value = true
    } catch {
      devices.value = []
      deviceTotal.value = 0
      monitorAvailable.value = false
      monitorChecked.value = true
    } finally {
      devicesLoading.value = false
    }
  }

  const disableDeviceToken = async (row: PushDeviceItem) => {
    if (!row.push_token_bound) return
    try {
      await ElMessageBox.confirm('停用后该设备需要重新上报 token 才能收到离线推送。', '确认停用 Token', {
        type: 'warning',
        confirmButtonText: '停用',
        cancelButtonText: '取消'
      })
    } catch {
      return
    }

    disabledTokenLoading[row.id] = true
    try {
      const result = await disablePushDeviceToken(row.id)
      ElMessage.success(result.disabled ? '已停用该设备 token' : result.message || '设备 token 已是空')
      await Promise.allSettled([loadDevices(), loadStats(), loadLogs()])
    } catch {
      ElMessage.error('停用 token 失败')
    } finally {
      disabledTokenLoading[row.id] = false
    }
  }

  const cleanupInvalidTokens = async (dryRun: boolean) => {
    // 预检只计算命中设备；实际清理会清空 token，因此还需显式确认并传递 confirm。
    if (!dryRun) {
      try {
        await ElMessageBox.confirm(
          '将清空最近 7 天出现 3 次以上无效 token 错误的设备 token，操作后需要客户端重新上报。',
          '确认清理无效 Token',
          {
            type: 'warning',
            confirmButtonText: '清理',
            cancelButtonText: '取消'
          }
        )
      } catch {
        return
      }
    }

    cleanupLoading.value = true
    try {
      cleanupResult.value = await cleanupInvalidPushTokens({
        hours: 168,
        min_failures: 3,
        channel: deviceFilters.channel || undefined,
        dry_run: dryRun,
        confirm: !dryRun
      })
      const count = dryRun ? cleanupResult.value.matched_count : cleanupResult.value.cleared_count
      ElMessage.success(`${dryRun ? '预检' : '清理'}完成，影响 ${count} 台设备`)
      await Promise.allSettled([loadDevices(), loadStats(), loadLogs()])
    } catch {
      ElMessage.error(`${dryRun ? '预检' : '清理'}无效 token 失败`)
    } finally {
      cleanupLoading.value = false
    }
  }

  const previewInvalidCleanup = () => cleanupInvalidTokens(true)
  const runInvalidCleanup = () => cleanupInvalidTokens(false)

  const sendTest = async () => {
    if (!testForm.target_id || testForm.target_id <= 0) {
      ElMessage.warning('请输入测试目标 ID')
      return
    }

    testing.value = true
    try {
      const result = await sendPushTest({
        [testTarget.value === 'user' ? 'user_id' : 'device_id']: testForm.target_id,
        scene: testForm.scene,
        title: testForm.title.trim(),
        body: testForm.body.trim()
      })
      ElMessage.success(`已提交 ${result.submitted_devices} 台设备`)
      // 测试推送会产生新日志并改变统计，提交后同时刷新三个监控数据源。
      await refreshMonitor()
    } catch {
      ElMessage.error('发送测试推送失败')
    } finally {
      testing.value = false
    }
  }

  onMounted(() => {
    loadPushSettings()
    refreshMonitor()
  })
</script>

<style lang="scss" scoped>
  .push-report-page {
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

  .head-actions {
    flex: 0 0 auto;
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

  .metric-top .success {
    color: #059669;
    background: #ecfdf5;
  }

  .metric-top .warning {
    color: #d97706;
    background: #fffbeb;
  }

  .metric-top .danger {
    color: #dc2626;
    background: #fef2f2;
  }

  .metric-top .info {
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

  .span-5 {
    grid-column: span 5;
  }

  .span-7 {
    grid-column: span 7;
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

  .section-actions {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 8px;
  }

  .section-head h2 {
    margin: 0 0 4px;
    color: #111827;
    font-size: 17px;
    font-weight: 650;
    line-height: 24px;
  }

  .clean-table {
    --el-table-border-color: #edf2f7;
    --el-table-header-bg-color: #f8fafc;
    --el-table-header-text-color: #475569;

    border: 1px solid #edf2f7;
    border-radius: 8px;
  }

  .compact-table {
    font-size: 13px;
  }

  .channel-name {
    display: flex;
    align-items: center;
    gap: 8px;
    font-weight: 600;
  }

  .channel-dot {
    width: 8px;
    height: 8px;
    border-radius: 999px;
    background: #cbd5e1;
  }

  .channel-dot.ready {
    background: #10b981;
  }

  .channel-dot.warn {
    background: #f59e0b;
  }

  .form-grid {
    display: grid;
    gap: 2px;
  }

  .form-grid :deep(.el-form-item) {
    margin-bottom: 14px;
  }

  .log-filter-bar {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    align-items: center;
  }

  .filter-item {
    width: 132px;
  }

  .filter-keyword {
    width: 190px;
  }

  .device-user,
  .last-push {
    display: flex;
    min-width: 0;
    flex-direction: column;
    gap: 2px;
  }

  .device-user strong {
    overflow: hidden;
    color: #111827;
    font-size: 13px;
    font-weight: 650;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .device-user span,
  .last-push span,
  .last-push small,
  .muted-text,
  .table-footer {
    color: #64748b;
    font-size: 12px;
    line-height: 18px;
  }

  .last-push {
    gap: 4px;
  }

  .last-push small {
    overflow: hidden;
    color: #dc2626;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .table-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding-top: 12px;
  }

  @media (max-width: 1200px) {
    .metric-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .span-4,
    .span-5,
    .span-7,
    .span-8 {
      grid-column: 1 / -1;
    }
  }

  @media (max-width: 768px) {
    .push-report-page {
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

    .filter-keyword {
      width: 100%;
    }

    .section-actions,
    .table-footer {
      align-items: stretch;
      flex-direction: column;
    }
  }
</style>
