<template>
  <div class="push-config-page">
    <section class="page-head">
      <div>
        <p>系统配置 / 离线推送</p>
        <h1>推送配置</h1>
        <span>配置消息策略和厂商通道凭证，保存后新投递任务立即使用最新参数。</span>
      </div>
      <div class="head-actions">
        <ElButton :icon="DataAnalysis" @click="goReport">查看推送报表</ElButton>
        <ElButton v-if="!isDemoAdmin" type="primary" :loading="saving" @click="savePushSettings">
          保存配置
        </ElButton>
      </div>
    </section>

    <ElAlert v-if="isDemoAdmin" type="warning" :closable="false" show-icon class="mb-4">
      当前为演示管理员，只能查看推送配置，无法修改敏感密钥。
    </ElAlert>

    <section class="config-grid">
      <div class="config-card span-7">
        <div class="card-head">
          <div>
            <h2>消息策略</h2>
            <p>默认标题、可推送场景、分类标签、主备供应商和频控规则。</p>
          </div>
          <ElButton v-if="!isDemoAdmin" type="primary" :loading="saving" @click="savePushSettings">
            保存配置
          </ElButton>
        </div>
        <ElForm :model="pushForm" label-position="top" class="form-grid two">
          <ElFormItem label="默认通知标题">
            <ElInput v-model="pushForm.push_default_title" :disabled="isDemoAdmin" placeholder="通用IM" />
          </ElFormItem>
          <ElFormItem label="主推送供应商">
            <ElSelect v-model="pushForm.push_primary_provider" :disabled="isDemoAdmin" class="w-full">
              <ElOption label="JPush" value="jpush" />
              <ElOption label="FCM" value="fcm" />
              <ElOption label="HMS" value="hms" />
              <ElOption label="小米" value="xiaomi" />
              <ElOption label="OPPO" value="oppo" />
              <ElOption label="APNs" value="apns" />
              <ElOption label="个推（预留）" value="getui" />
              <ElOption label="自建 Native（预留）" value="native" />
            </ElSelect>
          </ElFormItem>
          <ElFormItem label="备用推送供应商">
            <ElSelect v-model="pushForm.push_fallback_provider" :disabled="isDemoAdmin" class="w-full">
              <ElOption label="不启用备用" value="none" />
              <ElOption label="JPush" value="jpush" />
              <ElOption label="FCM" value="fcm" />
              <ElOption label="HMS" value="hms" />
              <ElOption label="小米" value="xiaomi" />
              <ElOption label="OPPO" value="oppo" />
              <ElOption label="APNs" value="apns" />
              <ElOption label="个推（预留）" value="getui" />
              <ElOption label="自建 Native（预留）" value="native" />
            </ElSelect>
          </ElFormItem>
          <ElFormItem label="运营免打扰">
            <div class="inline-control">
              <ElSwitch v-model="pushForm.push_quiet_hours_enabled" :disabled="isDemoAdmin" />
              <ElInput
                v-model="pushForm.push_quiet_hours_start"
                :disabled="isDemoAdmin || !pushForm.push_quiet_hours_enabled"
                placeholder="22:00"
              />
              <span>至</span>
              <ElInput
                v-model="pushForm.push_quiet_hours_end"
                :disabled="isDemoAdmin || !pushForm.push_quiet_hours_enabled"
                placeholder="08:00"
              />
            </div>
          </ElFormItem>
          <ElFormItem label="推送场景" class="full">
            <div class="scenario-group">
              <ElCheckbox v-model="pushForm.push_chat_enabled" :disabled="isDemoAdmin">聊天消息</ElCheckbox>
              <ElCheckbox v-model="pushForm.push_friend_enabled" :disabled="isDemoAdmin">好友申请</ElCheckbox>
              <ElCheckbox v-model="pushForm.push_system_enabled" :disabled="isDemoAdmin">系统通知</ElCheckbox>
            </div>
          </ElFormItem>
          <ElFormItem label="聊天消息分类">
            <ElInput v-model="pushForm.push_category_chat" :disabled="isDemoAdmin" placeholder="chat_message" />
          </ElFormItem>
          <ElFormItem label="服务通知分类">
            <ElInput v-model="pushForm.push_category_service" :disabled="isDemoAdmin" placeholder="service_notice" />
          </ElFormItem>
          <ElFormItem label="运营通知分类">
            <ElInput v-model="pushForm.push_category_marketing" :disabled="isDemoAdmin" placeholder="marketing" />
          </ElFormItem>
          <ElFormItem label="单用户每分钟上限">
            <ElInputNumber
              v-model="pushForm.push_rate_limit_per_min"
              :min="0"
              :disabled="isDemoAdmin"
              controls-position="right"
              class="w-full"
            />
          </ElFormItem>
          <ElFormItem label="运营每日上限">
            <ElInputNumber
              v-model="pushForm.push_marketing_daily_limit"
              :min="0"
              :disabled="isDemoAdmin"
              controls-position="right"
              class="w-full"
            />
          </ElFormItem>
        </ElForm>
      </div>

      <div class="config-card span-5">
        <div class="card-head">
          <div>
            <h2>配置完整度</h2>
            <p>按启用状态检查关键凭证是否已填写。</p>
          </div>
        </div>
        <div class="status-list">
          <div v-for="item in providerStatus" :key="item.name" class="status-item">
            <div>
              <span class="status-dot" :class="item.ready ? 'ready' : item.enabled ? 'warn' : ''" />
              <strong>{{ item.name }}</strong>
            </div>
            <ElTag :type="item.ready ? 'success' : item.enabled ? 'warning' : 'info'" effect="light">
              {{ item.ready ? '完整' : item.enabled ? '待补齐' : '未启用' }}
            </ElTag>
          </div>
        </div>
      </div>
    </section>

    <section class="provider-grid">
      <div class="provider-card">
        <div class="provider-head">
          <div>
            <h3>APNs</h3>
            <p>iOS 离线通知</p>
          </div>
          <ElSwitch v-model="pushForm.apns_enabled" :disabled="isDemoAdmin" />
        </div>
        <ElForm :model="pushForm" label-position="top" class="provider-form">
          <ElFormItem label="Bundle ID">
            <ElInput
              v-model="pushForm.apns_bundle_id"
              :placeholder="isDemoAdmin ? '******' : 'com.genericim.ma100'"
              :disabled="!pushForm.apns_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="Key ID">
            <ElInput
              v-model="pushForm.apns_key_id"
              :placeholder="isDemoAdmin ? '******' : '10 位 Key ID'"
              :disabled="!pushForm.apns_enabled || isDemoAdmin"
              maxlength="10"
            />
          </ElFormItem>
          <ElFormItem label="Team ID">
            <ElInput
              v-model="pushForm.apns_team_id"
              :placeholder="isDemoAdmin ? '******' : '10 位 Team ID'"
              :disabled="!pushForm.apns_enabled || isDemoAdmin"
              maxlength="10"
            />
          </ElFormItem>
          <ElFormItem label="环境">
            <ElRadioGroup v-model="pushForm.apns_environment" :disabled="!pushForm.apns_enabled || isDemoAdmin">
              <ElRadio value="development">开发</ElRadio>
              <ElRadio value="production">生产</ElRadio>
            </ElRadioGroup>
          </ElFormItem>
          <ElFormItem label="Auth Key (.p8)" class="full">
            <ElInput
              v-model="pushForm.apns_auth_key"
              type="textarea"
              :rows="4"
              :placeholder="isDemoAdmin ? '******' : '-----BEGIN PRIVATE KEY-----'"
              :disabled="!pushForm.apns_enabled || isDemoAdmin"
            />
          </ElFormItem>
        </ElForm>
      </div>

      <div class="provider-card">
        <div class="provider-head">
          <div>
            <h3>JPush</h3>
            <p>Android 统一推送通道</p>
          </div>
          <ElSwitch v-model="pushForm.jpush_enabled" :disabled="isDemoAdmin" />
        </div>
        <ElForm :model="pushForm" label-position="top" class="provider-form">
          <ElFormItem label="极光 AppKey">
            <ElInput
              v-model="pushForm.jpush_app_key"
              :placeholder="isDemoAdmin ? '******' : '极光控制台 AppKey'"
              :disabled="!pushForm.jpush_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="极光 MasterSecret">
            <ElInput
              v-model="pushForm.jpush_master_secret"
              type="password"
              :show-password="!isDemoAdmin"
              :placeholder="isDemoAdmin ? '******' : '极光控制台 MasterSecret'"
              :disabled="!pushForm.jpush_enabled || isDemoAdmin"
            />
          </ElFormItem>
        </ElForm>
      </div>

      <div class="provider-card">
        <div class="provider-head">
          <div>
            <h3>FCM</h3>
            <p>Google Play / 海外 Android</p>
          </div>
          <ElSwitch v-model="pushForm.fcm_enabled" :disabled="isDemoAdmin" />
        </div>
        <ElForm :model="pushForm" label-position="top" class="provider-form">
          <ElFormItem label="Firebase Project ID">
            <ElInput
              v-model="pushForm.fcm_project_id"
              :placeholder="isDemoAdmin ? '******' : 'Firebase Project ID'"
              :disabled="!pushForm.fcm_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="Service Account JSON" class="full">
            <ElInput
              v-model="pushForm.fcm_service_account_json"
              type="textarea"
              :rows="4"
              :placeholder="isDemoAdmin ? '******' : '粘贴 Firebase service account JSON'"
              :disabled="!pushForm.fcm_enabled || isDemoAdmin"
            />
          </ElFormItem>
        </ElForm>
      </div>

      <div class="provider-card">
        <div class="provider-head">
          <div>
            <h3>HMS</h3>
            <p>华为设备原生通道</p>
          </div>
          <ElSwitch v-model="pushForm.hms_enabled" :disabled="isDemoAdmin" />
        </div>
        <ElForm :model="pushForm" label-position="top" class="provider-form">
          <ElFormItem label="HMS App ID">
            <ElInput
              v-model="pushForm.hms_app_id"
              :placeholder="isDemoAdmin ? '******' : '华为推送 App ID'"
              :disabled="!pushForm.hms_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="HMS App Secret">
            <ElInput
              v-model="pushForm.hms_app_secret"
              type="password"
              :show-password="!isDemoAdmin"
              :placeholder="isDemoAdmin ? '******' : '华为推送 App Secret'"
              :disabled="!pushForm.hms_enabled || isDemoAdmin"
            />
          </ElFormItem>
        </ElForm>
      </div>

      <div class="provider-card">
        <div class="provider-head">
          <div>
            <h3>小米</h3>
            <p>小米 / Redmi 原生通道</p>
          </div>
          <ElSwitch v-model="pushForm.xiaomi_push_enabled" :disabled="isDemoAdmin" />
        </div>
        <ElForm :model="pushForm" label-position="top" class="provider-form">
          <ElFormItem label="小米包名">
            <ElInput
              v-model="pushForm.xiaomi_package_name"
              :placeholder="isDemoAdmin ? '******' : 'com.genericim.ma100'"
              :disabled="!pushForm.xiaomi_push_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="小米 App Secret">
            <ElInput
              v-model="pushForm.xiaomi_app_secret"
              type="password"
              :show-password="!isDemoAdmin"
              :placeholder="isDemoAdmin ? '******' : '小米推送 App Secret'"
              :disabled="!pushForm.xiaomi_push_enabled || isDemoAdmin"
            />
          </ElFormItem>
        </ElForm>
      </div>

      <div class="provider-card">
        <div class="provider-head">
          <div>
            <h3>OPPO</h3>
            <p>OPPO / 一加 / realme 通道</p>
          </div>
          <ElSwitch v-model="pushForm.oppo_push_enabled" :disabled="isDemoAdmin" />
        </div>
        <ElForm :model="pushForm" label-position="top" class="provider-form">
          <ElFormItem label="OPPO App Key">
            <ElInput
              v-model="pushForm.oppo_app_key"
              :placeholder="isDemoAdmin ? '******' : 'OPPO 推送 App Key'"
              :disabled="!pushForm.oppo_push_enabled || isDemoAdmin"
            />
          </ElFormItem>
          <ElFormItem label="OPPO App Secret">
            <ElInput
              v-model="pushForm.oppo_app_secret"
              type="password"
              :show-password="!isDemoAdmin"
              :placeholder="isDemoAdmin ? '******' : 'OPPO 推送 App Secret'"
              :disabled="!pushForm.oppo_push_enabled || isDemoAdmin"
            />
          </ElFormItem>
        </ElForm>
      </div>
    </section>

    <div v-if="!isDemoAdmin" class="bottom-actions">
      <ElButton type="primary" size="large" :loading="saving" @click="savePushSettings">
        保存推送配置
      </ElButton>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { computed, reactive, ref, onMounted } from 'vue'
  import { useRouter } from 'vue-router'
  import { ElMessage } from 'element-plus'
  import { DataAnalysis } from '@element-plus/icons-vue'
  import {
    getSystemSettings,
    updateSystemSettings,
    type SystemSettings
  } from '@/api/admin'

  defineOptions({ name: 'PushConfig' })

  type PushSettingsPayload = Pick<
    SystemSettings,
    | 'apns_enabled'
    | 'apns_bundle_id'
    | 'apns_key_id'
    | 'apns_team_id'
    | 'apns_auth_key'
    | 'apns_environment'
    | 'fcm_enabled'
    | 'fcm_project_id'
    | 'fcm_service_account_json'
    | 'hms_enabled'
    | 'hms_app_id'
    | 'hms_app_secret'
    | 'jpush_enabled'
    | 'jpush_app_key'
    | 'jpush_master_secret'
    | 'push_default_title'
    | 'push_chat_enabled'
    | 'push_friend_enabled'
    | 'push_system_enabled'
    | 'push_category_chat'
    | 'push_category_service'
    | 'push_category_marketing'
    | 'push_primary_provider'
    | 'push_fallback_provider'
    | 'push_rate_limit_per_min'
    | 'push_marketing_daily_limit'
    | 'push_quiet_hours_enabled'
    | 'push_quiet_hours_start'
    | 'push_quiet_hours_end'
    | 'xiaomi_push_enabled'
    | 'xiaomi_package_name'
    | 'xiaomi_app_secret'
    | 'oppo_push_enabled'
    | 'oppo_app_key'
    | 'oppo_app_secret'
  >

  const router = useRouter()
  const isDemoAdmin = ref(false)
  const saving = ref(false)

  const pushForm = reactive<PushSettingsPayload>({
    apns_enabled: false,
    apns_bundle_id: '',
    apns_key_id: '',
    apns_team_id: '',
    apns_auth_key: '',
    apns_environment: 'development',
    fcm_enabled: false,
    fcm_project_id: '',
    fcm_service_account_json: '',
    hms_enabled: false,
    hms_app_id: '',
    hms_app_secret: '',
    jpush_enabled: false,
    jpush_app_key: '',
    jpush_master_secret: '',
    push_default_title: '通用IM',
    push_chat_enabled: true,
    push_friend_enabled: true,
    push_system_enabled: true,
    push_category_chat: 'chat_message',
    push_category_service: 'service_notice',
    push_category_marketing: 'marketing',
    push_primary_provider: 'jpush',
    push_fallback_provider: 'none',
    push_rate_limit_per_min: 0,
    push_marketing_daily_limit: 0,
    push_quiet_hours_enabled: false,
    push_quiet_hours_start: '22:00',
    push_quiet_hours_end: '08:00',
    xiaomi_push_enabled: false,
    xiaomi_package_name: '',
    xiaomi_app_secret: '',
    oppo_push_enabled: false,
    oppo_app_key: '',
    oppo_app_secret: ''
  })

  const providerStatus = computed(() => [
    {
      name: 'APNs',
      enabled: pushForm.apns_enabled,
      ready:
        pushForm.apns_enabled &&
        !!pushForm.apns_bundle_id &&
        !!pushForm.apns_key_id &&
        !!pushForm.apns_team_id &&
        !!pushForm.apns_auth_key
    },
    {
      name: 'JPush',
      enabled: pushForm.jpush_enabled,
      ready: pushForm.jpush_enabled && !!pushForm.jpush_app_key && !!pushForm.jpush_master_secret
    },
    {
      name: 'FCM',
      enabled: pushForm.fcm_enabled,
      ready: pushForm.fcm_enabled && !!pushForm.fcm_project_id && !!pushForm.fcm_service_account_json
    },
    {
      name: 'HMS',
      enabled: pushForm.hms_enabled,
      ready: pushForm.hms_enabled && !!pushForm.hms_app_id && !!pushForm.hms_app_secret
    },
    {
      name: '小米',
      enabled: pushForm.xiaomi_push_enabled,
      ready:
        pushForm.xiaomi_push_enabled &&
        !!pushForm.xiaomi_package_name &&
        !!pushForm.xiaomi_app_secret
    },
    {
      name: 'OPPO',
      enabled: pushForm.oppo_push_enabled,
      ready: pushForm.oppo_push_enabled && !!pushForm.oppo_app_key && !!pushForm.oppo_app_secret
    }
  ])

  const goReport = () => router.push('/system/push-report')

  const applySettings = (settings: SystemSettings) => {
    // 设置接口可能对密钥返回掩码值；表单按原字段回填，保存后再重新读取服务端最终状态。
    isDemoAdmin.value = settings._admin_role === 'demo_admin'
    pushForm.apns_enabled = settings.apns_enabled || false
    pushForm.apns_bundle_id = settings.apns_bundle_id || ''
    pushForm.apns_key_id = settings.apns_key_id || ''
    pushForm.apns_team_id = settings.apns_team_id || ''
    pushForm.apns_auth_key = settings.apns_auth_key || ''
    pushForm.apns_environment = settings.apns_environment || 'development'
    pushForm.fcm_enabled = settings.fcm_enabled || false
    pushForm.fcm_project_id = settings.fcm_project_id || ''
    pushForm.fcm_service_account_json = settings.fcm_service_account_json || ''
    pushForm.hms_enabled = settings.hms_enabled || false
    pushForm.hms_app_id = settings.hms_app_id || ''
    pushForm.hms_app_secret = settings.hms_app_secret || ''
    pushForm.jpush_enabled = settings.jpush_enabled || false
    pushForm.jpush_app_key = settings.jpush_app_key || ''
    pushForm.jpush_master_secret = settings.jpush_master_secret || ''
    pushForm.push_default_title = settings.push_default_title || '通用IM'
    pushForm.push_chat_enabled = settings.push_chat_enabled !== false
    pushForm.push_friend_enabled = settings.push_friend_enabled !== false
    pushForm.push_system_enabled = settings.push_system_enabled !== false
    pushForm.push_category_chat = settings.push_category_chat || 'chat_message'
    pushForm.push_category_service = settings.push_category_service || 'service_notice'
    pushForm.push_category_marketing = settings.push_category_marketing || 'marketing'
    pushForm.push_primary_provider = settings.push_primary_provider || 'jpush'
    pushForm.push_fallback_provider = settings.push_fallback_provider || 'none'
    pushForm.push_rate_limit_per_min = Number(settings.push_rate_limit_per_min || 0)
    pushForm.push_marketing_daily_limit = Number(settings.push_marketing_daily_limit || 0)
    pushForm.push_quiet_hours_enabled = settings.push_quiet_hours_enabled || false
    pushForm.push_quiet_hours_start = settings.push_quiet_hours_start || '22:00'
    pushForm.push_quiet_hours_end = settings.push_quiet_hours_end || '08:00'
    pushForm.xiaomi_push_enabled = settings.xiaomi_push_enabled || false
    pushForm.xiaomi_package_name = settings.xiaomi_package_name || ''
    pushForm.xiaomi_app_secret = settings.xiaomi_app_secret || ''
    pushForm.oppo_push_enabled = settings.oppo_push_enabled || false
    pushForm.oppo_app_key = settings.oppo_app_key || ''
    pushForm.oppo_app_secret = settings.oppo_app_secret || ''
  }

  const loadPushSettings = async () => {
    try {
      applySettings(await getSystemSettings())
    } catch {
      ElMessage.error('加载推送配置失败')
    }
  }

  // 只构建推送模块字段，避免该页面覆盖系统设置接口中的其他配置。
  const buildPushPayload = (): PushSettingsPayload => ({
    apns_enabled: pushForm.apns_enabled,
    apns_bundle_id: pushForm.apns_bundle_id.trim(),
    apns_key_id: pushForm.apns_key_id.trim(),
    apns_team_id: pushForm.apns_team_id.trim(),
    apns_auth_key: pushForm.apns_auth_key.trim(),
    apns_environment: pushForm.apns_environment.trim().toLowerCase(),
    fcm_enabled: pushForm.fcm_enabled,
    fcm_project_id: pushForm.fcm_project_id.trim(),
    fcm_service_account_json: pushForm.fcm_service_account_json.trim(),
    hms_enabled: pushForm.hms_enabled,
    hms_app_id: pushForm.hms_app_id.trim(),
    hms_app_secret: pushForm.hms_app_secret.trim(),
    jpush_enabled: pushForm.jpush_enabled,
    jpush_app_key: pushForm.jpush_app_key.trim(),
    jpush_master_secret: pushForm.jpush_master_secret.trim(),
    push_default_title: pushForm.push_default_title.trim() || '通用IM',
    push_chat_enabled: pushForm.push_chat_enabled,
    push_friend_enabled: pushForm.push_friend_enabled,
    push_system_enabled: pushForm.push_system_enabled,
    push_category_chat: pushForm.push_category_chat.trim() || 'chat_message',
    push_category_service: pushForm.push_category_service.trim() || 'service_notice',
    push_category_marketing: pushForm.push_category_marketing.trim() || 'marketing',
    push_primary_provider: pushForm.push_primary_provider,
    push_fallback_provider: pushForm.push_fallback_provider,
    push_rate_limit_per_min: Number(pushForm.push_rate_limit_per_min || 0),
    push_marketing_daily_limit: Number(pushForm.push_marketing_daily_limit || 0),
    push_quiet_hours_enabled: pushForm.push_quiet_hours_enabled,
    push_quiet_hours_start: pushForm.push_quiet_hours_start.trim() || '22:00',
    push_quiet_hours_end: pushForm.push_quiet_hours_end.trim() || '08:00',
    xiaomi_push_enabled: pushForm.xiaomi_push_enabled,
    xiaomi_package_name: pushForm.xiaomi_package_name.trim(),
    xiaomi_app_secret: pushForm.xiaomi_app_secret.trim(),
    oppo_push_enabled: pushForm.oppo_push_enabled,
    oppo_app_key: pushForm.oppo_app_key.trim(),
    oppo_app_secret: pushForm.oppo_app_secret.trim()
  })

  const validatePushPayload = (payload: PushSettingsPayload): string | null => {
    if (payload.apns_enabled) {
      if (
        !payload.apns_bundle_id ||
        !payload.apns_key_id ||
        !payload.apns_team_id ||
        !payload.apns_auth_key
      ) {
        return '启用 APNs 推送时，Bundle ID / Key ID / Team ID / Auth Key 不能为空'
      }
      if (!['development', 'production'].includes(payload.apns_environment)) {
        return 'APNs 环境仅支持 development 或 production'
      }
    }

    if (payload.fcm_enabled) {
      if (!payload.fcm_project_id || !payload.fcm_service_account_json) {
        return '启用 FCM 推送时，Project ID 与 Service Account JSON 不能为空'
      }
      const projectId = payload.fcm_project_id.trim()
      const normalizedProjectId = projectId.toLowerCase()
      if (
        projectId.startsWith('1:') ||
        normalizedProjectId.includes(':android:') ||
        normalizedProjectId.includes(':ios:')
      ) {
        return 'FCM Project ID 填写错误，请填写 Firebase Project ID，不要填写 mobilesdk_app_id'
      }

      try {
        // FCM Project ID 必须与服务账号文件一致，否则凭证合法但会向错误项目投递。
        const serviceAccount = JSON.parse(payload.fcm_service_account_json) as {
          project_id?: string
          client_email?: string
          private_key?: string
        }
        const serviceProjectId = (serviceAccount.project_id || '').trim()
        if (!serviceProjectId) return 'FCM Service Account JSON 缺少 project_id'
        if (!serviceAccount.client_email || !serviceAccount.private_key) {
          return 'FCM Service Account JSON 缺少 client_email 或 private_key'
        }
        if (serviceProjectId !== projectId) {
          return 'FCM Project ID 与 Service Account JSON 的 project_id 不一致'
        }
      } catch {
        return 'FCM Service Account JSON 格式错误'
      }
    }

    if (payload.hms_enabled && (!payload.hms_app_id || !payload.hms_app_secret)) {
      return '启用 HMS 推送时，App ID 与 App Secret 不能为空'
    }
    if (payload.jpush_enabled && (!payload.jpush_app_key || !payload.jpush_master_secret)) {
      return '启用极光推送时，AppKey 与 MasterSecret 不能为空'
    }
    const categoryPattern = /^[A-Za-z0-9_:-]{1,64}$/
    if (
      !categoryPattern.test(payload.push_category_chat) ||
      !categoryPattern.test(payload.push_category_service) ||
      !categoryPattern.test(payload.push_category_marketing)
    ) {
      return '消息分类仅支持 1-64 位字母、数字、下划线、横线、冒号'
    }
    const providers = ['jpush', 'getui', 'native', 'fcm', 'hms', 'xiaomi', 'oppo', 'apns']
    if (!providers.includes(payload.push_primary_provider)) return '主推送供应商配置错误'
    if (!['none', ...providers].includes(payload.push_fallback_provider)) {
      return '备用推送供应商配置错误'
    }
    if (payload.push_rate_limit_per_min < 0 || payload.push_marketing_daily_limit < 0) {
      return '频控上限不能为负数'
    }
    const timePattern = /^([01]\d|2[0-3]):[0-5]\d$/
    if (
      !timePattern.test(payload.push_quiet_hours_start) ||
      !timePattern.test(payload.push_quiet_hours_end)
    ) {
      return '免打扰时间格式必须是 HH:mm'
    }
    if (
      payload.xiaomi_push_enabled &&
      (!payload.xiaomi_package_name || !payload.xiaomi_app_secret)
    ) {
      return '启用小米推送时，包名与 App Secret 不能为空'
    }
    if (payload.oppo_push_enabled && (!payload.oppo_app_key || !payload.oppo_app_secret)) {
      return '启用 OPPO 推送时，App Key 与 App Secret 不能为空'
    }

    return null
  }

  const savePushSettings = async () => {
    const payload = buildPushPayload()
    const validationError = validatePushPayload(payload)
    if (validationError) {
      ElMessage.warning(validationError)
      return
    }

    saving.value = true
    try {
      await updateSystemSettings(payload)
      ElMessage.success('推送配置已保存')
      // 保存后重新回填，显示后端规范化及敏感字段脱敏后的真实配置。
      await loadPushSettings()
    } catch {
      ElMessage.error('保存失败')
    } finally {
      saving.value = false
    }
  }

  onMounted(loadPushSettings)
</script>

<style lang="scss" scoped>
  .push-config-page {
    min-height: 100%;
    padding: 18px;
    background: #f6f8fb;
  }

  .page-head,
  .config-card,
  .provider-card {
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
  .card-head p,
  .provider-head p {
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
  .card-head {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 12px;
  }

  .head-actions {
    flex: 0 0 auto;
  }

  .config-grid {
    display: grid;
    grid-template-columns: repeat(12, minmax(0, 1fr));
    gap: 14px;
    margin-bottom: 14px;
  }

  .span-7 {
    grid-column: span 7;
  }

  .span-5 {
    grid-column: span 5;
  }

  .config-card,
  .provider-card {
    min-width: 0;
    padding: 18px;
  }

  .card-head {
    margin-bottom: 16px;
  }

  .card-head h2,
  .provider-head h3 {
    margin: 0 0 4px;
    color: #111827;
    font-weight: 650;
  }

  .card-head h2 {
    font-size: 17px;
    line-height: 24px;
  }

  .provider-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 14px;
  }

  .provider-head {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 12px;
    margin-bottom: 14px;
  }

  .provider-head h3 {
    font-size: 16px;
    line-height: 22px;
  }

  .form-grid,
  .provider-form {
    display: grid;
    gap: 2px 14px;
  }

  .form-grid.two,
  .provider-form {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }

  .form-grid :deep(.el-form-item),
  .provider-form :deep(.el-form-item) {
    margin-bottom: 14px;
  }

  .full {
    grid-column: 1 / -1;
  }

  .inline-control {
    display: grid;
    width: 100%;
    grid-template-columns: auto minmax(88px, 1fr) auto minmax(88px, 1fr);
    gap: 8px;
    align-items: center;
  }

  .scenario-group {
    display: flex;
    flex-wrap: wrap;
    gap: 8px 18px;
  }

  .status-list {
    display: grid;
    gap: 10px;
  }

  .status-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    min-height: 44px;
    padding: 0 12px;
    border: 1px solid #edf2f7;
    border-radius: 8px;
    background: #f8fafc;
  }

  .status-item > div {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .status-dot {
    width: 8px;
    height: 8px;
    border-radius: 999px;
    background: #cbd5e1;
  }

  .status-dot.ready {
    background: #10b981;
  }

  .status-dot.warn {
    background: #f59e0b;
  }

  .bottom-actions {
    display: flex;
    justify-content: flex-end;
    margin-top: 14px;
    padding: 16px;
    border: 1px solid #e6ebf2;
    border-radius: 8px;
    background: #fff;
  }

  @media (max-width: 1200px) {
    .span-7,
    .span-5 {
      grid-column: 1 / -1;
    }

    .provider-grid {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 768px) {
    .push-config-page {
      padding: 12px;
    }

    .page-head,
    .head-actions {
      flex-direction: column;
    }

    .form-grid.two,
    .provider-form {
      grid-template-columns: 1fr;
    }

    .inline-control {
      grid-template-columns: 1fr;
    }
  }
</style>
