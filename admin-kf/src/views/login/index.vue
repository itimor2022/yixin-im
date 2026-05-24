<template>
  <div class="login-page">
    <div class="login-card page-card">
      <div class="hero">
        <div class="hero-badge">独立入口</div>
        <h1>官方客服登录后台</h1>
        <p>输入已被配置为官方客服的用户账号即可进入独立后台。</p>
      </div>

      <ElForm label-position="top" @submit.prevent>
        <ElFormItem label="账号">
          <ElInput v-model="form.username" placeholder="请输入用户名" />
        </ElFormItem>
        <ElFormItem label="密码">
          <ElInput v-model="form.password" type="password" show-password placeholder="请输入密码" />
        </ElFormItem>
        <ElFormItem>
          <ElButton type="success" size="large" class="submit-btn" :loading="session.loading" @click="handleLogin">
            登录进入工作台
          </ElButton>
        </ElFormItem>
      </ElForm>
    </div>
  </div>
</template>

<script setup lang="ts">
import { reactive } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { useSessionStore } from '@/stores/session'

const router = useRouter()
const session = useSessionStore()
const form = reactive({
  username: '',
  password: ''
})

const handleLogin = async () => {
  if (!form.username.trim() || !form.password) {
    ElMessage.warning('请输入账号和密码')
    return
  }

  try {
    await session.login({ username: form.username.trim(), password: form.password })
    router.push('/dashboard')
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '登录失败')
  }
}
</script>

<style scoped lang="scss">
.login-page { min-height: 100vh; display: grid; place-items: center; padding: 24px; }
.login-card { width: min(100%, 460px); padding: 32px; }
.hero-badge { display: inline-flex; padding: 6px 12px; border-radius: 999px; background: rgba(74,222,128,.14); color: #86efac; font-size: 12px; margin-bottom: 18px; }
.hero h1 { margin: 0; font-size: 34px; line-height: 1.15; }
.hero p { margin: 14px 0 28px; color: var(--text-soft); line-height: 1.7; }
.submit-btn { width: 100%; }
</style>
