<template>
  <div class="page-card page-wrap">
    <div class="head-row">
      <div>
        <h2 class="page-title">个人中心</h2>
        <p class="page-subtitle">独立客服后台下的个人资料与账号安全设置入口。</p>
      </div>
      <ElTag :type="session.profile.status === 'enabled' ? 'success' : 'info'" round>
        {{ session.profile.status === 'enabled' ? '服务中' : '已停用' }}
      </ElTag>
    </div>

    <div class="profile-grid">
      <section class="profile-panel">
        <h3 class="section-title">基本资料</h3>
        <div class="data-list">
          <div class="data-item"><span>账号昵称</span><span>{{ session.profile.nickname }}</span></div>
          <div class="data-item"><span>登录账号</span><span>{{ session.profile.username || '-' }}</span></div>
          <div class="data-item"><span>手机号</span><span>{{ session.profile.phone || '-' }}</span></div>
          <div class="data-item"><span>角色</span><span>{{ session.profile.role }}</span></div>
          <div class="data-item"><span>邀请码</span><span>{{ session.profile.inviteCode || '-' }}</span></div>
          <div class="data-item"><span>用户 UUID</span><span>{{ session.profile.userUuid || '-' }}</span></div>
        </div>
      </section>
      <section class="profile-panel">
        <h3 class="section-title">账号安全</h3>
        <ElForm label-position="top" @submit.prevent>
          <ElFormItem label="原密码">
            <ElInput v-model="passwordForm.oldPassword" type="password" show-password placeholder="请输入原密码" />
          </ElFormItem>
          <ElFormItem label="新密码">
            <ElInput v-model="passwordForm.newPassword" type="password" show-password placeholder="请输入 6-20 位新密码" />
          </ElFormItem>
          <ElFormItem label="确认新密码">
            <ElInput v-model="passwordForm.confirmPassword" type="password" show-password placeholder="请再次输入新密码" />
          </ElFormItem>
          <div class="action-stack">
          <ElButton type="primary" :loading="savingPassword" @click="handleChangePassword">修改密码</ElButton>
          </div>
        </ElForm>
        <p class="security-tip">修改密码已接入真实接口；成功后将自动退出并要求重新登录。</p>
      </section>
      <section class="profile-panel">
        <h3 class="section-title">绑定手机号</h3>
        <ElForm label-position="top" @submit.prevent>
          <ElFormItem label="手机号">
            <ElInput v-model="phoneForm.phone" placeholder="请输入中国大陆手机号" :disabled="Boolean(session.profile.phone)" />
          </ElFormItem>
          <ElFormItem label="验证码">
            <div class="inline-action">
              <ElInput v-model="phoneForm.code" placeholder="请输入验证码" :disabled="Boolean(session.profile.phone)" />
              <ElButton :disabled="sendCodeDisabled || Boolean(session.profile.phone)" @click="handleSendCode">
                {{ sendCodeButtonText }}
              </ElButton>
            </div>
          </ElFormItem>
          <div class="action-stack">
          <ElButton type="primary" :loading="bindingPhone" :disabled="Boolean(session.profile.phone)" @click="handleBindPhone">绑定手机号</ElButton>
            <ElButton type="danger" plain @click="handleLogout">退出当前登录</ElButton>
          </div>
        </ElForm>
        <p class="security-tip">
          <template v-if="session.profile.phone">当前账号已绑定手机号，无需再次绑定。</template>
          <template v-else>绑定手机号已接入真实短信验证码流程，请先获取验证码再完成绑定。</template>
        </p>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { bindServiceAdminPhone, sendServiceAdminPhoneBindCode, updateServiceAdminPassword } from '@/service/api/service-admin'
import { useSessionStore } from '@/stores/session'

const router = useRouter()
const session = useSessionStore()
const savingPassword = ref(false)
const bindingPhone = ref(false)
const countdown = ref(0)
let timer: ReturnType<typeof setInterval> | null = null

const passwordForm = reactive({
  oldPassword: '',
  newPassword: '',
  confirmPassword: ''
})

const phoneForm = reactive({
  phone: '',
  code: ''
})

const sendCodeDisabled = computed(() => countdown.value > 0)
const sendCodeButtonText = computed(() => (countdown.value > 0 ? `${countdown.value}s 后重试` : '获取验证码'))

const resetPasswordForm = () => {
  passwordForm.oldPassword = ''
  passwordForm.newPassword = ''
  passwordForm.confirmPassword = ''
}

const startCountdown = (seconds: number) => {
  // 倒计时只限制当前页面重复发送，服务端仍负责短信频控和验证码有效期校验。
  countdown.value = seconds
  if (timer) clearInterval(timer)
  timer = setInterval(() => {
    countdown.value -= 1
    if (countdown.value <= 0 && timer) {
      clearInterval(timer)
      timer = null
    }
  }, 1000)
}

const handleChangePassword = async () => {
  if (!passwordForm.oldPassword || !passwordForm.newPassword || !passwordForm.confirmPassword) {
    ElMessage.warning('请完整填写密码信息')
    return
  }

  if (passwordForm.newPassword.length < 6 || passwordForm.newPassword.length > 20) {
    ElMessage.warning('新密码长度需为 6-20 位')
    return
  }

  if (passwordForm.newPassword !== passwordForm.confirmPassword) {
    ElMessage.warning('两次输入的新密码不一致')
    return
  }

  savingPassword.value = true
  try {
    await updateServiceAdminPassword({
      oldPassword: passwordForm.oldPassword,
      newPassword: passwordForm.newPassword
    })
    // 密码变更后立即销毁当前会话，避免旧 Token 继续访问客服数据。
    ElMessage.success('密码已修改，请重新登录')
    resetPasswordForm()
    await session.logout()
    router.push('/login')
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '修改密码失败')
  } finally {
    savingPassword.value = false
  }
}

const handleSendCode = async () => {
  if (!phoneForm.phone.trim()) {
    ElMessage.warning('请输入手机号')
    return
  }

  try {
    const result = await sendServiceAdminPhoneBindCode(phoneForm.phone.trim())
    ElMessage.success(result.message || '验证码已发送')
    startCountdown(result.expires_in ? Math.min(result.expires_in, 60) : 60)
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '发送验证码失败')
  }
}

const handleBindPhone = async () => {
  if (!phoneForm.phone.trim() || !phoneForm.code.trim()) {
    ElMessage.warning('请填写手机号和验证码')
    return
  }

  bindingPhone.value = true
  try {
    await bindServiceAdminPhone({ phone: phoneForm.phone.trim(), code: phoneForm.code.trim() })
    // 绑定结果通过重新拉取资料进入 Store，避免只在表单内维护一份临时手机号。
    await session.refreshProfile()
    ElMessage.success('手机号绑定成功')
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '绑定手机号失败')
  } finally {
    bindingPhone.value = false
  }
}

const handleLogout = async () => {
  await session.logout()
  router.push('/login')
}

onBeforeUnmount(() => {
  // 页面销毁时释放验证码计时器，避免组件离开后继续更新响应式状态。
  if (timer) clearInterval(timer)
})
</script>

<style scoped lang="scss">
.page-wrap { padding: 24px; }
.head-row { display: flex; justify-content: space-between; gap: 16px; align-items: center; }
.profile-grid { margin-top: 24px; display: grid; grid-template-columns: repeat(3, minmax(0,1fr)); gap: 18px; }
.profile-panel { padding: 20px; border-radius: var(--kf-radius-md); background: var(--kf-surface); border: 1px solid var(--kf-border); }
.action-stack { display: grid; gap: 12px; }
.inline-action { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: 12px; }
.security-tip { margin: 14px 0 0; color: var(--text-soft); line-height: 1.7; }
@media (max-width: 1200px) { .profile-grid { grid-template-columns: 1fr; } }
</style>
