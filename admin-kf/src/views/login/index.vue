<template>
  <div class="login-page">
    <div class="login-brand">
      <div class="brand-mark">服</div>
      <div>
        <div class="brand-name">客服中心</div>
        <div class="brand-en">SERVICE DESK</div>
      </div>
    </div>
    <div class="login-card page-card">
      <div class="hero">
        <div class="hero-badge">客服工作台</div>
        <h1>欢迎回来</h1>
        <p>登录后接待客户咨询，处理服务会话和跟进任务。</p>
      </div>

      <ElForm label-position="top" @submit.prevent>
        <div v-if="isLocalDemo" class="local-demo">
          <div><strong>本地演示账号</strong><span>demo_service / 123456</span></div>
          <button type="button" @click="fillLocalDemo">填入账号</button>
        </div>
        <ElFormItem label="账号">
          <ElInput v-model="form.username" name="kf_service_username" :autocomplete="isLocalDemo ? 'off' : 'username'" placeholder="请输入客服账号" />
        </ElFormItem>
        <ElFormItem label="密码">
          <ElInput v-model="form.password" name="kf_service_password" :autocomplete="isLocalDemo ? 'off' : 'current-password'" type="password" show-password placeholder="请输入密码" />
        </ElFormItem>
        <ElFormItem>
          <ElButton type="primary" size="large" class="submit-btn" :loading="session.loading" @click="handleLogin">
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
// 演示账号仅在本机主机名下暴露，部署环境不会预填固定凭据。
const isLocalDemo = ['127.0.0.1', 'localhost'].includes(window.location.hostname)
const form = reactive({
  username: isLocalDemo ? 'demo_service' : '',
  password: isLocalDemo ? '123456' : ''
})

const fillLocalDemo = () => {
  form.username = 'demo_service'
  form.password = '123456'
}

const handleLogin = async () => {
  if (!form.username.trim() || !form.password) {
    ElMessage.warning('请输入账号和密码')
    return
  }

  try {
    // 登录态持久化由 session store 统一负责，页面只处理输入和登录后的导航。
    await session.login({ username: form.username.trim(), password: form.password })
    router.push('/workbench')
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '登录失败')
  }
}
</script>

<style scoped lang="scss">
.login-page { min-height: 100vh; display: grid; place-items: center; align-content: center; gap: 24px; padding: 32px 24px; background: #f5f6f8; }
.login-brand { display: flex; align-items: center; gap: 12px; }
.brand-mark { width: 42px; height: 42px; display: grid; place-items: center; border-radius: 10px; color: #fff; background: #111; font-size: 19px; font-weight: 800; }
.brand-name { color: var(--kf-text); font-size: 17px; font-weight: 750; }
.brand-en { margin-top: 3px; color: var(--kf-text-muted); font-size: 9px; letter-spacing: .12em; }
.login-card { width: min(100%, 440px); padding: 36px; }
.hero-badge { display: inline-flex; padding: 5px 10px; border: 1px solid var(--kf-border); border-radius: 999px; color: var(--kf-text-secondary); background: var(--kf-surface-soft); font-size: 11px; margin-bottom: 18px; }
.hero h1 { margin: 0; color: var(--kf-text); font-size: 30px; line-height: 1.2; }
.hero p { margin: 12px 0 28px; color: var(--kf-text-secondary); line-height: 1.7; }
.local-demo { display: flex; justify-content: space-between; align-items: center; gap: 12px; margin: -8px 0 18px; padding: 10px 12px; border: 1px solid var(--kf-border); border-radius: 8px; background: var(--kf-surface-soft); }
.local-demo div { display: grid; gap: 3px; }
.local-demo strong { font-size: 11px; }
.local-demo span { color: var(--kf-text-secondary); font-family: ui-monospace, SFMono-Regular, Consolas, monospace; font-size: 10px; }
.local-demo button { flex: 0 0 auto; padding: 5px 8px; border: 1px solid var(--kf-border-strong); border-radius: 5px; color: var(--kf-text); background: #fff; font-size: 9px; cursor: pointer; }
.submit-btn { width: 100%; }
@media (max-width: 520px) { .login-card { padding: 28px 22px; } }
</style>
