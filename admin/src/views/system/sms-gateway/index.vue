<script setup lang="ts">
  import { ref, reactive, onMounted } from 'vue'
  import { ElMessage } from 'element-plus'
  import { getSmsGatewayConfig, saveSmsGatewayConfig, type SmsGatewayConfig } from '@/api/admin'

  defineOptions({ name: 'SmsGateway' })

  const loading = ref(false)
  const saving = ref(false)

  function defaultForm(): SmsGatewayConfig {
    return {
      enabled: false,
      provider: 'smsbao',
      message_template: '【应用签名】您的验证码是{code}，5分钟内有效。',
      smsbao: { user: '', password: '' },
      aliyun: {
        access_key_id: '',
        access_key_secret: '',
        region: 'cn-hangzhou',
        sign_name: '',
        template_code: ''
      },
      tencent: {
        secret_id: '',
        secret_key: '',
        region: 'ap-guangzhou',
        sdk_app_id: '',
        sign_name: '',
        template_id: ''
      }
    }
  }

  const form = reactive<SmsGatewayConfig>(defaultForm())

  async function loadConfig() {
    loading.value = true
    try {
      const res = (await getSmsGatewayConfig()) as any
      if (res) {
        Object.assign(form, {
          ...defaultForm(),
          ...res,
          smsbao: { ...defaultForm().smsbao, ...(res.smsbao || {}) },
          aliyun: { ...defaultForm().aliyun, ...(res.aliyun || {}) },
          tencent: { ...defaultForm().tencent, ...(res.tencent || {}) }
        })
      }
    } catch (error) {
      console.error('Failed to load SMS gateway config:', error)
    }
    loading.value = false
  }

  async function save() {
    saving.value = true
    try {
      await saveSmsGatewayConfig(form)
      ElMessage.success('保存成功')
    } catch {
      ElMessage.error('保存失败')
    }
    saving.value = false
  }

  onMounted(loadConfig)
</script>

<template>
  <ElCard header="短信网关设置" v-loading="loading">
    <ElAlert type="info" :closable="false" show-icon class="mb-4">
      用于 App
      绑定手机号验证码。渠道三选一：<strong>短信宝</strong>（HTTP+MD5）、<strong>阿里云</strong>（模板变量
      code）、<strong>腾讯云</strong>（模板单变量填验证码）。
    </ElAlert>

    <ElForm :model="form" label-width="160px" class="max-w-2xl">
      <ElFormItem label="启用短信">
        <ElSwitch v-model="form.enabled" />
        <span class="ml-2 text-sm text-g-400">开启后 App 绑定手机号时将发送短信验证码</span>
      </ElFormItem>
      <ElFormItem label="短信渠道">
        <ElSelect v-model="form.provider" style="width: 200px">
          <ElOption label="短信宝 smsbao" value="smsbao" />
          <ElOption label="阿里云 aliyun" value="aliyun" />
          <ElOption label="腾讯云 tencent" value="tencent" />
        </ElSelect>
      </ElFormItem>
      <ElFormItem label="短信宝正文模板">
        <ElInput
          v-model="form.message_template"
          type="textarea"
          :rows="2"
          placeholder="须含 {code}，仅短信宝使用"
          style="max-width: 480px"
        />
      </ElFormItem>

      <ElDivider content-position="left">短信宝</ElDivider>
      <ElFormItem label="用户名">
        <ElInput v-model="form.smsbao.user" style="max-width: 360px" />
      </ElFormItem>
      <ElFormItem label="密码">
        <ElInput v-model="form.smsbao.password" show-password style="max-width: 360px" />
      </ElFormItem>

      <ElDivider content-position="left">阿里云</ElDivider>
      <ElFormItem label="AccessKey ID">
        <ElInput v-model="form.aliyun.access_key_id" style="max-width: 360px" />
      </ElFormItem>
      <ElFormItem label="AccessKey Secret">
        <ElInput v-model="form.aliyun.access_key_secret" show-password style="max-width: 360px" />
      </ElFormItem>
      <ElFormItem label="Region">
        <ElInput v-model="form.aliyun.region" placeholder="cn-hangzhou" style="max-width: 240px" />
      </ElFormItem>
      <ElFormItem label="签名">
        <ElInput v-model="form.aliyun.sign_name" style="max-width: 360px" />
      </ElFormItem>
      <ElFormItem label="模板 CODE">
        <ElInput v-model="form.aliyun.template_code" style="max-width: 360px" />
      </ElFormItem>

      <ElDivider content-position="left">腾讯云</ElDivider>
      <ElFormItem label="SecretId">
        <ElInput v-model="form.tencent.secret_id" style="max-width: 360px" />
      </ElFormItem>
      <ElFormItem label="SecretKey">
        <ElInput v-model="form.tencent.secret_key" show-password style="max-width: 360px" />
      </ElFormItem>
      <ElFormItem label="Region">
        <ElInput
          v-model="form.tencent.region"
          placeholder="ap-guangzhou"
          style="max-width: 240px"
        />
      </ElFormItem>
      <ElFormItem label="SdkAppId">
        <ElInput v-model="form.tencent.sdk_app_id" style="max-width: 360px" />
      </ElFormItem>
      <ElFormItem label="签名">
        <ElInput v-model="form.tencent.sign_name" style="max-width: 360px" />
      </ElFormItem>
      <ElFormItem label="模板 ID">
        <ElInput v-model="form.tencent.template_id" style="max-width: 360px" />
      </ElFormItem>

      <ElFormItem>
        <ElButton type="primary" :loading="saving" @click="save">保存短信配置</ElButton>
      </ElFormItem>
    </ElForm>
  </ElCard>
</template>
