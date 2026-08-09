<script setup lang="ts">
  import { ref, reactive, onMounted, h } from 'vue'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import {
    getPaymentGatewayConfig,
    savePaymentGatewayConfig,
    type PaymentGatewayConfig
  } from '@/api/admin'

  defineOptions({ name: 'PaymentGateway' })

  const loading = ref(false)
  const saving = ref(false)

  function getDefaultNotifyBaseUrl() {
    if (typeof window === 'undefined' || !window.location?.origin) {
      return ''
    }
    return window.location.origin
  }

  function getEffectiveNotifyBaseUrl() {
    // 未显式配置时用当前后台来源生成预览地址，生产部署仍建议填写公网回调域名。
    return form.notify_base_url || getDefaultNotifyBaseUrl()
  }

  function buildNotifyUrl(channel: 'wechat' | 'alipay') {
    const base = getEffectiveNotifyBaseUrl().trim().replace(/\/$/, '')
    if (!base) return ''
    return `${base}/api/v1/payment/notify/${channel}`
  }

  function isValidAbsoluteUrl(value: string) {
    try {
      const url = new URL(value)
      return Boolean(url.protocol && url.host)
    } catch {
      return false
    }
  }

  function isValidReturnUrl(value: string) {
    return value.startsWith('/') || isValidAbsoluteUrl(value)
  }

  function looksLikePem(value: string) {
    return value.includes('BEGIN')
  }

  function getDefaultAlipayReturnUrl() {
    if (typeof window === 'undefined' || !window.location?.origin) {
      return '/wallet/payment-result'
    }
    return `${window.location.origin}/wallet/payment-result`
  }

  async function copyAlipayReturnUrl() {
    const value = form.alipay.return_url || getDefaultAlipayReturnUrl()
    try {
      await navigator.clipboard.writeText(value)
      ElMessage.success('同步回调地址已复制')
    } catch {
      ElMessage.error('复制失败')
    }
  }

  async function copyText(value: string, label: string) {
    if (!value) return
    try {
      await navigator.clipboard.writeText(value)
      ElMessage.success(`${label}已复制`)
    } catch {
      ElMessage.error('复制失败')
    }
  }

  function showValidationErrors(errors: string[]) {
    ElMessageBox.alert(
      h('div', { class: 'space-y-2 text-sm leading-6' }, [
        h('div', { class: 'font-medium text-[#1f2937]' }, '请先完善以下配置项：'),
        h(
          'ul',
          { class: 'm-0 pl-5 text-[#4b5563]' },
          errors.map((item) => h('li', { class: 'mb-1' }, item))
        )
      ]),
      '配置校验未通过',
      {
        confirmButtonText: '我知道了',
        type: 'warning'
      }
    )
  }

  function getErrorMessage(error: unknown) {
    if (error && typeof error === 'object' && 'message' in error) {
      const message = (error as { message?: unknown }).message
      if (typeof message === 'string' && message.trim()) {
        return message
      }
    }
    return '保存失败'
  }

  function defaultForm(): PaymentGatewayConfig {
    return {
      enabled: false,
      notify_base_url: '',
      min_amount: 1,
      max_amount: 10000,
      wechat: {
        enabled: false,
        mch_id: '',
        mch_api_v3_key: '',
        mch_certificate_serial: '',
        app_id: '',
        private_key_pem: '',
        h5_app_name: '',
        h5_app_url: ''
      },
      alipay: {
        enabled: false,
        app_id: '',
        app_private_key_pem: '',
        alipay_public_key_pem: '',
        is_production: false,
        return_url: getDefaultAlipayReturnUrl()
      }
    }
  }

  const form = reactive<PaymentGatewayConfig>(defaultForm())

  async function loadConfig() {
    loading.value = true
    try {
      const res = (await getPaymentGatewayConfig()) as any
      if (res) {
        // 嵌套渠道配置分别与默认值合并，兼容后端旧版本缺少新增字段的响应。
        Object.assign(form, {
          ...defaultForm(),
          ...res,
          wechat: { ...defaultForm().wechat, ...(res.wechat || {}) },
          alipay: { ...defaultForm().alipay, ...(res.alipay || {}) }
        })
        if (!form.alipay.return_url) {
          form.alipay.return_url = getDefaultAlipayReturnUrl()
        }
        if (!form.notify_base_url) {
          form.notify_base_url = getDefaultNotifyBaseUrl()
        }
      }
    } catch (error) {
      console.error('Failed to load payment gateway config:', error)
    }
    loading.value = false
  }

  function validateForm() {
    // 前端校验用于一次性汇总可见问题，密钥和回调地址仍由服务端做最终验证。
    if (!form.enabled) return true

    const errors: string[] = []
    const notifyBase = form.notify_base_url.trim()
    const alipayReturnUrl = (form.alipay.return_url || getDefaultAlipayReturnUrl()).trim()
    const wechatPrivateKey = form.wechat.private_key_pem?.trim() || ''
    const alipayPrivateKey = form.alipay.app_private_key_pem?.trim() || ''
    const alipayPublicKey = form.alipay.alipay_public_key_pem?.trim() || ''

    if (form.min_amount <= 0) {
      errors.push('最小充值金额必须大于 0')
    }
    if (form.max_amount < form.min_amount) {
      errors.push('最大充值金额不能小于最小充值金额')
    }
    if (notifyBase && !isValidAbsoluteUrl(notifyBase)) {
      errors.push('异步通知基础地址必须是有效的公网 URL')
    }

    if (form.wechat.enabled) {
      if (!form.wechat.app_id.trim()) errors.push('请填写微信支付 App ID')
      if (!form.wechat.mch_id.trim()) errors.push('请填写微信支付商户号 MchID')
      if (!form.wechat.mch_api_v3_key.trim()) errors.push('请填写微信支付 API v3 密钥')
      if (!form.wechat.mch_certificate_serial.trim()) errors.push('请填写微信支付证书序列号')
      if (!wechatPrivateKey) {
        errors.push('请填写微信支付商户私钥')
      } else if (!looksLikePem(wechatPrivateKey)) {
        errors.push('微信支付商户私钥内容格式不正确')
      }
    }

    if (form.alipay.enabled) {
      if (!form.alipay.app_id.trim()) errors.push('请填写支付宝 App ID')
      if (!alipayPrivateKey) {
        errors.push('请填写支付宝应用私钥')
      } else if (!looksLikePem(alipayPrivateKey)) {
        errors.push('支付宝应用私钥内容格式不正确')
      }
      if (!alipayPublicKey) {
        errors.push('请填写支付宝公钥')
      } else if (!looksLikePem(alipayPublicKey)) {
        errors.push('支付宝公钥内容格式不正确')
      }
      if (alipayReturnUrl && !isValidReturnUrl(alipayReturnUrl)) {
        errors.push('支付宝同步回调地址必须是有效 URL 或站内路径')
      }
    }

    if (errors.length > 0) {
      showValidationErrors(errors)
      return false
    }

    return true
  }

  async function save() {
    if (!validateForm()) return
    saving.value = true
    try {
      // 整体提交网关快照，渠道启用状态与对应凭据保持同一次更新。
      await savePaymentGatewayConfig(form)
      ElMessage.success('保存成功')
    } catch (error) {
      ElMessage.error(getErrorMessage(error))
    }
    saving.value = false
  }

  onMounted(loadConfig)
</script>

<template>
  <ElCard header="在线支付网关设置" v-loading="loading">
    <ElForm :model="form" label-width="180px" class="max-w-2xl">
      <ElFormItem label="启用在线支付">
        <ElSwitch v-model="form.enabled" />
      </ElFormItem>
      <ElFormItem label="异步通知基础地址">
        <div class="w-full space-y-3" style="max-width: 560px">
          <ElInput
            v-model="form.notify_base_url"
            :placeholder="getDefaultNotifyBaseUrl() || '如：https://api.example.com'"
          />
          <div
            class="rounded-xl border border-[#e5e7eb] bg-[#f8fafc] p-3 text-xs text-g-500 dark:border-[#3a3a3c] dark:bg-[#232326]"
          >
            <div class="mb-2 leading-6"
              >这里填写后端公网根地址，例如接口域名；系统会自动拼接微信和支付宝通知路径。留空时默认取当前站点域名。</div
            >
            <div
              v-if="buildNotifyUrl('wechat')"
              class="flex items-center justify-between gap-3 rounded-lg bg-white/80 px-3 py-2 dark:bg-black/10"
            >
              <div class="min-w-0">
                <div class="text-[11px] font-semibold uppercase tracking-wide text-[#07c160]"
                  >微信异步通知</div
                >
                <div class="truncate text-g-500">{{ buildNotifyUrl('wechat') }}</div>
              </div>
              <ElButton
                text
                size="small"
                @click="copyText(buildNotifyUrl('wechat'), '微信通知地址')"
                >复制</ElButton
              >
            </div>
            <div
              v-if="buildNotifyUrl('alipay')"
              class="mt-2 flex items-center justify-between gap-3 rounded-lg bg-white/80 px-3 py-2 dark:bg-black/10"
            >
              <div class="min-w-0">
                <div class="text-[11px] font-semibold uppercase tracking-wide text-[#1677ff]"
                  >支付宝异步通知</div
                >
                <div class="truncate text-g-500">{{ buildNotifyUrl('alipay') }}</div>
              </div>
              <ElButton
                text
                size="small"
                @click="copyText(buildNotifyUrl('alipay'), '支付宝通知地址')"
                >复制</ElButton
              >
            </div>
          </div>
        </div>
      </ElFormItem>
      <ElFormItem label="最小充值金额（元）">
        <ElInputNumber
          v-model="form.min_amount"
          :min="0.01"
          :precision="2"
          controls-position="right"
        />
      </ElFormItem>
      <ElFormItem label="最大充值金额（元）">
        <ElInputNumber
          v-model="form.max_amount"
          :min="1"
          :precision="2"
          controls-position="right"
        />
      </ElFormItem>

      <ElDivider content-position="left">微信支付</ElDivider>
      <ElFormItem label="启用微信支付">
        <ElSwitch v-model="form.wechat.enabled" />
      </ElFormItem>
      <ElFormItem label="App ID">
        <ElInput
          v-model="form.wechat.app_id"
          :disabled="!form.wechat.enabled"
          style="max-width: 400px"
        />
      </ElFormItem>
      <ElFormItem label="商户号 MchID">
        <ElInput
          v-model="form.wechat.mch_id"
          :disabled="!form.wechat.enabled"
          style="max-width: 400px"
        />
      </ElFormItem>
      <ElFormItem label="API v3 密钥">
        <ElInput
          v-model="form.wechat.mch_api_v3_key"
          show-password
          :disabled="!form.wechat.enabled"
          style="max-width: 400px"
        />
      </ElFormItem>
      <ElFormItem label="证书序列号">
        <ElInput
          v-model="form.wechat.mch_certificate_serial"
          :disabled="!form.wechat.enabled"
          style="max-width: 400px"
        />
      </ElFormItem>
      <ElFormItem label="商户私钥 (PEM)">
        <ElInput
          v-model="form.wechat.private_key_pem"
          type="textarea"
          :rows="4"
          placeholder="粘贴 apiclient_key.pem 的完整内容（含 -----BEGIN...）"
          :disabled="!form.wechat.enabled"
        />
      </ElFormItem>
      <ElFormItem label="H5 应用名称">
        <ElInput
          v-model="form.wechat.h5_app_name"
          :disabled="!form.wechat.enabled"
          style="max-width: 360px"
        />
      </ElFormItem>
      <ElFormItem label="H5 应用 URL">
        <ElInput
          v-model="form.wechat.h5_app_url"
          :disabled="!form.wechat.enabled"
          style="max-width: 400px"
        />
      </ElFormItem>

      <ElDivider content-position="left">支付宝</ElDivider>
      <ElFormItem label="启用支付宝">
        <ElSwitch v-model="form.alipay.enabled" />
      </ElFormItem>
      <ElFormItem label="生产环境">
        <ElSwitch v-model="form.alipay.is_production" :disabled="!form.alipay.enabled" />
        <span class="ml-2 text-sm text-g-400">关闭则使用沙箱环境</span>
      </ElFormItem>
      <ElFormItem label="App ID">
        <ElInput
          v-model="form.alipay.app_id"
          :disabled="!form.alipay.enabled"
          style="max-width: 400px"
        />
      </ElFormItem>
      <ElFormItem label="应用私钥 (PEM)">
        <ElInput
          v-model="form.alipay.app_private_key_pem"
          type="textarea"
          :rows="4"
          placeholder="粘贴应用私钥（RSA2，含 -----BEGIN...）"
          :disabled="!form.alipay.enabled"
        />
      </ElFormItem>
      <ElFormItem label="支付宝公钥 (PEM)">
        <ElInput
          v-model="form.alipay.alipay_public_key_pem"
          type="textarea"
          :rows="4"
          placeholder="粘贴支付宝平台公钥（含 -----BEGIN...）"
          :disabled="!form.alipay.enabled"
        />
      </ElFormItem>
      <ElFormItem label="同步回调地址">
        <div class="w-full space-y-3" style="max-width: 560px">
          <ElInput :model-value="form.alipay.return_url || getDefaultAlipayReturnUrl()" readonly>
            <template #append>
              <ElButton @click="copyAlipayReturnUrl">复制</ElButton>
            </template>
          </ElInput>
          <div
            class="rounded-xl border border-[#e5e7eb] bg-[#fffaf0] p-3 text-xs text-g-500 dark:border-[#3a3a3c] dark:bg-[#2a2418]"
          >
            <div class="text-[11px] font-semibold uppercase tracking-wide text-[#1677ff]"
              >支付宝同步回跳</div
            >
            <div class="mt-1 leading-6"
              >这是支付宝支付完成后用户浏览器回跳到你前端结果页的地址，不是支付宝官方地址；系统会自动附加订单号参数。</div
            >
          </div>
        </div>
      </ElFormItem>

      <ElFormItem>
        <ElButton type="primary" :loading="saving" @click="save">保存支付配置</ElButton>
      </ElFormItem>
    </ElForm>
  </ElCard>
</template>
