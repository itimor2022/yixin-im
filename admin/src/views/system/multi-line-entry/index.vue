<template>
  <div class="multi-line-entry-page">
    <ElAlert v-if="isDemoAdmin" type="warning" :closable="false" show-icon class="mb-4">
      演示管理员只能查看多线路入口配置。
    </ElAlert>
    <ElAlert v-else type="info" :closable="false" show-icon class="mb-4">
      这里配置 App 可用的 API、WebSocket 和资源入口。主线路不可用时，客户端会按顺序切到备用线路。
    </ElAlert>

    <div class="entry-hero">
      <div>
        <p class="entry-eyebrow">客户端访问线路</p>
        <h3>主线路不可用时，App 自动切到备用线路</h3>
        <p>
          只需要维护线上可访问的域名。主线路优先使用，备用线路按顺序接管；连接策略保持默认即可。
        </p>
      </div>
      <div class="entry-status">
        <ElTag :type="entryForm.enabled ? 'success' : 'info'" effect="light">
          {{ entryForm.enabled ? '已启用' : '未启用' }}
        </ElTag>
        <span>版本 {{ entryForm.version || 1 }}</span>
        <span>{{ entryForm.api_endpoints.length }} 条线路</span>
      </div>
    </div>

    <ElForm :model="entryForm" label-position="top" class="entry-form">
      <section class="entry-section">
        <div class="section-title">
          <div>
            <h4>基础设置</h4>
            <p>日常只需要开关、版本和缓存时间。</p>
          </div>
        </div>
        <div class="basic-grid">
          <ElFormItem label="启用动态入口">
            <ElSwitch v-model="entryForm.enabled" :disabled="isDemoAdmin" />
          </ElFormItem>
          <ElFormItem label="配置版本">
            <ElInputNumber
              v-model="entryForm.version"
              :min="1"
              :step="1"
              controls-position="right"
              :disabled="isDemoAdmin"
            />
            <p class="form-tip">每次调整线路后加 1，客户端会更快识别新配置。</p>
          </ElFormItem>
          <ElFormItem label="客户端缓存">
            <ElSelect v-model="entryForm.ttl_seconds" :disabled="isDemoAdmin">
              <ElOption label="5 分钟" :value="300" />
              <ElOption label="15 分钟" :value="900" />
              <ElOption label="30 分钟" :value="1800" />
              <ElOption label="1 小时" :value="3600" />
            </ElSelect>
          </ElFormItem>
        </div>
      </section>

      <section class="entry-section">
        <div class="section-title">
          <div>
            <h4>访问线路</h4>
            <p>一条线路包含 API 和 WebSocket。通常主域名一条，备用域名一条。</p>
          </div>
          <ElButton v-if="!isDemoAdmin" @click="addEndpoint">
            <ArtSvgIcon icon="ri:add-line" class="mr-1" />
            添加备用线路
          </ElButton>
        </div>

        <div class="endpoint-cards">
          <div
            v-for="(item, index) in entryForm.api_endpoints"
            :key="`endpoint-${index}`"
            class="endpoint-card"
          >
            <div class="endpoint-card-head">
              <div>
                <ElTag :type="index === 0 ? 'success' : 'info'" effect="light">
                  {{ index === 0 ? '主线路' : `备用线路 ${index}` }}
                </ElTag>
                <span class="endpoint-name">{{ item.id || `entry-${index + 1}` }}</span>
              </div>
              <ElButton
                v-if="!isDemoAdmin && entryForm.api_endpoints.length > 1"
                type="danger"
                link
                @click="removeEndpoint(index)"
              >
                删除
              </ElButton>
            </div>

            <div class="endpoint-grid">
              <ElFormItem label="API 地址">
                <ElInput
                  v-model="item.url"
                  placeholder="https://api.example.com"
                  :disabled="isDemoAdmin"
                  @blur="fillWsFromApi(index)"
                />
              </ElFormItem>
              <ElFormItem label="WebSocket 地址">
                <ElInput
                  v-if="entryForm.ws_endpoints[index]"
                  v-model="entryForm.ws_endpoints[index].url"
                  placeholder="wss://api.example.com/api/v1/ws"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="备注">
                <ElInput
                  v-model="item.region"
                  placeholder="例如：主线路 / 香港备用 / 高防备用"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
            </div>
          </div>
        </div>
      </section>

      <section class="entry-section">
        <div class="section-title">
          <div>
            <h4>资源线路</h4>
            <p>头像、图片、语音、文件会优先使用这里的域名。没有 CDN 时填 API 域名即可。</p>
          </div>
          <ElButton v-if="!isDemoAdmin" @click="addMediaBaseUrl">
            <ArtSvgIcon icon="ri:add-line" class="mr-1" />
            添加资源域名
          </ElButton>
        </div>
        <div class="media-url-list">
          <div
            v-for="(_item, index) in entryForm.media_base_urls"
            :key="`media-${index}`"
            class="media-url-row"
          >
            <ElInput
              v-model="entryForm.media_base_urls[index]"
              placeholder="https://cdn.example.com"
              :disabled="isDemoAdmin"
            />
            <ElButton
              v-if="!isDemoAdmin && entryForm.media_base_urls.length > 1"
              type="danger"
              link
              @click="removeMediaBaseUrl(index)"
            >
              删除
            </ElButton>
          </div>
        </div>
      </section>

      <section class="entry-section">
        <ElCollapse>
          <ElCollapseItem title="高级切换策略" name="advanced">
            <div class="strategy-presets">
              <ElButton :disabled="isDemoAdmin" @click="applyStrategyPreset('stable')">
                稳定优先
              </ElButton>
              <ElButton :disabled="isDemoAdmin" @click="applyStrategyPreset('fast')">
                快速切换
              </ElButton>
            </div>
            <div class="strategy-grid">
              <ElFormItem label="连接超时">
                <ElInputNumber
                  v-model="entryForm.strategy.connect_timeout_ms"
                  :min="1000"
                  :max="30000"
                  :step="500"
                  controls-position="right"
                  :disabled="isDemoAdmin"
                />
                <p class="form-tip">毫秒</p>
              </ElFormItem>
              <ElFormItem label="失败切换阈值">
                <ElInputNumber
                  v-model="entryForm.strategy.fail_threshold"
                  :min="1"
                  :max="10"
                  :step="1"
                  controls-position="right"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
              <ElFormItem label="失败冷却">
                <ElInputNumber
                  v-model="entryForm.strategy.cooldown_seconds"
                  :min="10"
                  :max="3600"
                  :step="10"
                  controls-position="right"
                  :disabled="isDemoAdmin"
                />
                <p class="form-tip">秒</p>
              </ElFormItem>
              <ElFormItem label="优先使用上次成功线路">
                <ElSwitch
                  v-model="entryForm.strategy.prefer_last_success"
                  :disabled="isDemoAdmin"
                />
              </ElFormItem>
            </div>
          </ElCollapseItem>
        </ElCollapse>
      </section>

      <div v-if="!isDemoAdmin" class="entry-actions">
        <ElButton type="primary" size="large" :loading="saving" @click="saveEntryConfig">
          保存多线路入口
        </ElButton>
      </div>
    </ElForm>
  </div>
</template>

<script setup lang="ts">
  import { reactive, ref, onMounted } from 'vue'
  import { ElMessage } from 'element-plus'
  import {
    getSystemSettings,
    updateSystemSettings,
    type ClientBootstrapConfig,
    type ClientEndpointConfig,
    type SystemSettings
  } from '@/api/admin'

  defineOptions({ name: 'MultiLineEntry' })

  const currentHttpOrigin = () =>
    typeof window === 'undefined' ? 'https://api.example.com' : window.location.origin

  const currentWsUrl = () => {
    const origin = currentHttpOrigin()
    return `${origin.replace(/^https:\/\//, 'wss://').replace(/^http:\/\//, 'ws://')}/api/v1/ws`
  }

  const createDefaultConfig = (): ClientBootstrapConfig => ({
    enabled: true,
    version: 1,
    ttl_seconds: 300,
    api_endpoints: [
      {
        id: 'main-api',
        url: currentHttpOrigin(),
        priority: 10,
        region: 'main',
        health_path: '/api/v1/ping'
      }
    ],
    ws_endpoints: [
      {
        id: 'main-ws',
        url: currentWsUrl(),
        priority: 10,
        region: 'main'
      }
    ],
    media_base_urls: [currentHttpOrigin()],
    strategy: {
      connect_timeout_ms: 5000,
      health_timeout_ms: 3000,
      fail_threshold: 1,
      cooldown_seconds: 60,
      prefer_last_success: true
    }
  })

  const isDemoAdmin = ref(false)
  const saving = ref(false)
  const entryForm = reactive<ClientBootstrapConfig>(createDefaultConfig())

  const trimUrl = (value: string) => value.trim().replace(/\/+$/, '')

  const deriveWsUrlFromApi = (rawUrl: string) => {
    const url = trimUrl(rawUrl)
    if (!url) return ''
    const wsBase = url.replace(/^https:\/\//, 'wss://').replace(/^http:\/\//, 'ws://')
    return `${wsBase}/api/v1/ws`
  }

  // API 与 WebSocket 入口按数组下标成对维护，新增或删除线路时必须保持两边同步。
  const syncEndpointPairs = () => {
    if (entryForm.api_endpoints.length === 0) {
      entryForm.api_endpoints.push({
        id: 'main-api',
        url: '',
        priority: 10,
        region: '',
        health_path: '/api/v1/ping'
      })
    }

    while (entryForm.ws_endpoints.length < entryForm.api_endpoints.length) {
      const index = entryForm.ws_endpoints.length
      const api = entryForm.api_endpoints[index]
      entryForm.ws_endpoints.push({
        id: index === 0 ? 'main-ws' : `backup-ws-${index}`,
        url: deriveWsUrlFromApi(api?.url || ''),
        priority: api?.priority || (index + 1) * 10,
        region: api?.region || '',
        health_path: ''
      })
    }
  }

  const fillWsFromApi = (index: number) => {
    syncEndpointPairs()
    const api = entryForm.api_endpoints[index]
    const ws = entryForm.ws_endpoints[index]
    if (!api || !ws || ws.url) return
    ws.url = deriveWsUrlFromApi(api.url)
  }

  const addEndpoint = () => {
    const index = entryForm.api_endpoints.length
    const priority = (index + 1) * 10
    entryForm.api_endpoints.push({
      id: `backup-api-${index}`,
      url: '',
      priority,
      region: '',
      health_path: '/api/v1/ping'
    })
    entryForm.ws_endpoints.push({
      id: `backup-ws-${index}`,
      url: '',
      priority,
      region: '',
      health_path: ''
    })
  }

  const removeEndpoint = (index: number) => {
    if (entryForm.api_endpoints.length <= 1) {
      ElMessage.warning('至少保留一条访问线路')
      return
    }
    entryForm.api_endpoints.splice(index, 1)
    entryForm.ws_endpoints.splice(index, 1)
  }

  const addMediaBaseUrl = () => {
    entryForm.media_base_urls.push('')
  }

  const removeMediaBaseUrl = (index: number) => {
    if (entryForm.media_base_urls.length <= 1) {
      ElMessage.warning('至少保留一个资源入口')
      return
    }
    entryForm.media_base_urls.splice(index, 1)
  }

  const applyStrategyPreset = (preset: 'stable' | 'fast') => {
    if (preset === 'stable') {
      entryForm.ttl_seconds = 1800
      entryForm.strategy.connect_timeout_ms = 5000
      entryForm.strategy.health_timeout_ms = 3000
      entryForm.strategy.fail_threshold = 2
      entryForm.strategy.cooldown_seconds = 120
      entryForm.strategy.prefer_last_success = true
      return
    }

    entryForm.ttl_seconds = 300
    entryForm.strategy.connect_timeout_ms = 3000
    entryForm.strategy.health_timeout_ms = 2000
    entryForm.strategy.fail_threshold = 1
    entryForm.strategy.cooldown_seconds = 30
    entryForm.strategy.prefer_last_success = true
  }

  const isValidHttpUrl = (value: string, allowHostOnly = true) => {
    const text = value.trim()
    if (!text) return true
    try {
      const finalUrl = /^https?:\/\//i.test(text) || !allowHostOnly ? text : `https://${text}`
      const parsedUrl = new URL(finalUrl)
      return ['http:', 'https:'].includes(parsedUrl.protocol)
    } catch {
      return false
    }
  }

  const isValidWsUrl = (value: string) => {
    const text = value.trim()
    if (!text) return true
    try {
      const parsedUrl = new URL(text)
      return ['ws:', 'wss:'].includes(parsedUrl.protocol)
    } catch {
      return false
    }
  }

  const applyConfig = (settings: SystemSettings) => {
    isDemoAdmin.value = settings._admin_role === 'demo_admin'
    const defaults = createDefaultConfig()
    const config =
      settings.client_bootstrap && typeof settings.client_bootstrap === 'object'
        ? (settings.client_bootstrap as Partial<ClientBootstrapConfig>)
        : defaults

    Object.assign(entryForm, defaults, config)
    // 克隆嵌套数组，避免编辑表单时直接修改接口返回对象或默认配置。
    entryForm.api_endpoints = [...(config.api_endpoints || defaults.api_endpoints)]
    entryForm.ws_endpoints = [...(config.ws_endpoints || defaults.ws_endpoints)]
    entryForm.media_base_urls = [...(config.media_base_urls || defaults.media_base_urls)]
    entryForm.strategy = {
      ...defaults.strategy,
      ...(config.strategy || {})
    }
    syncEndpointPairs()
  }

  const loadEntryConfig = async () => {
    try {
      applyConfig(await getSystemSettings())
    } catch {
      ElMessage.error('加载多线路入口失败')
    }
  }

  const cleanEndpoints = (items: ClientEndpointConfig[], type: 'api' | 'ws') =>
    items
      .map((item, index) => ({
        id: item.id.trim() || `${type}-${index + 1}`,
        url: trimUrl(item.url),
        priority: item.priority || (index + 1) * 10,
        region: (item.region || '').trim(),
        health_path: type === 'api' ? (item.health_path || '/api/v1/ping').trim() : ''
      }))
      .filter((item) => item.url)

  const buildPayload = (): ClientBootstrapConfig => {
    syncEndpointPairs()
    // 保存前统一清理空线路、尾部斜杠和重复资源地址，再对最终载荷做校验。
    return {
      enabled: entryForm.enabled,
      version: entryForm.version || 1,
      ttl_seconds: entryForm.ttl_seconds || 300,
      api_endpoints: cleanEndpoints(entryForm.api_endpoints, 'api'),
      ws_endpoints: cleanEndpoints(entryForm.ws_endpoints, 'ws'),
      media_base_urls: entryForm.media_base_urls
        .map(trimUrl)
        .filter((item, index, arr) => item && arr.indexOf(item) === index),
      strategy: {
        connect_timeout_ms: entryForm.strategy.connect_timeout_ms || 5000,
        health_timeout_ms: entryForm.strategy.health_timeout_ms || 3000,
        fail_threshold: entryForm.strategy.fail_threshold || 1,
        cooldown_seconds: entryForm.strategy.cooldown_seconds || 60,
        prefer_last_success: entryForm.strategy.prefer_last_success
      }
    }
  }

  const validatePayload = (payload: ClientBootstrapConfig): string | null => {
    if (payload.ttl_seconds < 30) return '客户端缓存时间不能小于 30 秒'
    if (payload.api_endpoints.length === 0) return '至少需要配置一个 API 入口'
    if (payload.ws_endpoints.length === 0) return '至少需要配置一个 WebSocket 入口'
    if (payload.media_base_urls.length === 0) return '至少需要配置一个资源入口'
    if (payload.api_endpoints.some((item) => !isValidHttpUrl(item.url, false))) {
      return 'API 入口必须是有效的 http:// 或 https:// 地址'
    }
    if (payload.ws_endpoints.some((item) => !isValidWsUrl(item.url))) {
      return 'WebSocket 入口必须是有效的 ws:// 或 wss:// 地址'
    }
    if (payload.media_base_urls.some((item) => !isValidHttpUrl(item, false))) {
      return '资源入口必须是有效的 http:// 或 https:// 地址'
    }
    if (payload.strategy.fail_threshold < 1) return '失败切换阈值不能小于 1'
    if (payload.strategy.cooldown_seconds < 10) return '失败冷却时间不能小于 10 秒'
    return null
  }

  const saveEntryConfig = async () => {
    const payload = buildPayload()
    const validationError = validatePayload(payload)
    if (validationError) {
      ElMessage.warning(validationError)
      return
    }

    saving.value = true
    try {
      await updateSystemSettings({ client_bootstrap: payload })
      applyConfig({ client_bootstrap: payload } as SystemSettings)
      ElMessage.success('多线路入口已保存')
    } catch {
      ElMessage.error('保存失败')
    } finally {
      saving.value = false
    }
  }

  onMounted(() => {
    loadEntryConfig()
  })
</script>

<style lang="scss" scoped>
  .multi-line-entry-page {
    max-width: 1080px;
    padding: 20px;
  }

  .entry-hero {
    display: flex;
    gap: 20px;
    align-items: flex-start;
    justify-content: space-between;
    padding: 20px;
    margin-bottom: 18px;
    background: #f8fafc;
    border: 1px solid #e5e7eb;
    border-radius: 8px;
  }

  .entry-eyebrow {
    margin: 0 0 6px;
    font-size: 13px;
    font-weight: 600;
    color: #2563eb;
  }

  .entry-hero h3,
  .section-title h4 {
    margin: 0;
    color: #111827;
  }

  .entry-hero h3 {
    font-size: 20px;
    font-weight: 700;
  }

  .entry-hero p,
  .section-title p,
  .form-tip {
    margin: 6px 0 0;
    font-size: 13px;
    line-height: 1.6;
    color: #6b7280;
  }

  .entry-status {
    display: flex;
    flex: 0 0 auto;
    flex-wrap: wrap;
    gap: 8px;
    justify-content: flex-end;
    min-width: 220px;
    font-size: 13px;
    color: #4b5563;
  }

  .entry-status span {
    padding: 4px 10px;
    background: #fff;
    border: 1px solid #e5e7eb;
    border-radius: 999px;
  }

  .entry-form,
  .endpoint-cards,
  .media-url-list {
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .entry-section {
    padding: 18px;
    background: #fff;
    border: 1px solid #e5e7eb;
    border-radius: 8px;
  }

  .section-title,
  .endpoint-card-head {
    display: flex;
    gap: 16px;
    align-items: flex-start;
    justify-content: space-between;
    margin-bottom: 16px;
  }

  .basic-grid,
  .endpoint-grid,
  .strategy-grid {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 14px;
  }

  .endpoint-card {
    padding: 14px;
    background: #f9fafb;
    border: 1px solid #edf2f7;
    border-radius: 8px;
  }

  .endpoint-card-head {
    align-items: center;
    margin-bottom: 12px;
  }

  .endpoint-card-head > div {
    display: flex;
    gap: 8px;
    align-items: center;
    min-width: 0;
  }

  .endpoint-name {
    overflow: hidden;
    font-size: 13px;
    color: #4b5563;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .media-url-row {
    display: grid;
    grid-template-columns: minmax(0, 1fr) 56px;
    gap: 10px;
    align-items: center;
  }

  .strategy-presets {
    display: flex;
    gap: 10px;
    margin-bottom: 14px;
  }

  .entry-actions {
    display: flex;
    justify-content: flex-end;
  }

  @media (max-width: 1200px) {
    .entry-hero,
    .section-title {
      flex-direction: column;
    }

    .entry-status {
      justify-content: flex-start;
      min-width: 0;
    }

    .basic-grid,
    .endpoint-grid,
    .strategy-grid,
    .media-url-row {
      grid-template-columns: 1fr;
    }
  }
</style>
