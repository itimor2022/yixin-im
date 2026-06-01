<template>
  <div class="page-card page-wrap" v-loading="loading">
    <div class="head-row">
      <div>
        <h2 class="page-title">我的邀请码</h2>
        <p class="page-subtitle">当前版本展示独立后台下的个人邀请码管理界面。</p>
      </div>
      <div class="head-actions">
        <ElButton type="success" @click="handleCopyCode">复制邀请码</ElButton>
        <ElButton plain @click="handleCopyLink">复制注册链接</ElButton>
      </div>
    </div>

    <div class="invite-box">
      <div class="invite-box-head">
        <div>
          <div class="invite-code">{{ inviteCode.code }}</div>
          <div class="invite-meta">
            <span>最近更新时间：{{ inviteCode.updatedAt }}</span>
            <span>状态：{{ inviteCode.statusText }}</span>
          </div>
        </div>
        <div class="status-pill">
          <span class="status-dot"></span>
          <span>{{ inviteCode.statusText }}</span>
        </div>
      </div>
    </div>

    <div class="link-panel">
      <div class="link-label">专属注册链接</div>
      <div class="link-card">
        <div class="link-main">{{ inviteCode.registerUrl }}</div>
        <div class="link-tip">如果这里没有域名，请检查后端 `server.base_url` 配置。</div>
      </div>
    </div>

    <div class="data-grid">
      <div class="data-card">
        <span>使用人数</span>
        <strong>{{ inviteCode.usedCount }}</strong>
      </div>
      <div class="data-card">
        <span>本周转化</span>
        <strong>+{{ inviteCode.weeklyConversion }}</strong>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { fetchServiceAdminInviteCode } from '@/service/api/service-admin'
import type { ServiceAdminInviteCode } from '@/types/service-admin'

const loading = ref(true)
const inviteCode = ref<ServiceAdminInviteCode>({
  code: '-',
  updatedAt: '-',
  statusText: '-',
  registerUrl: '-',
  usedCount: 0,
  weeklyConversion: 0
})

const hasValidLink = computed(() => Boolean(inviteCode.value.registerUrl && inviteCode.value.registerUrl !== '-'))

const copyText = async (value: string, successText: string) => {
  if (!value || value === '-') return

  try {
    await navigator.clipboard.writeText(value)
    ElMessage.success(successText)
  } catch {
    ElMessage.error('复制失败，请手动复制')
  }
}

const handleCopyCode = () => copyText(inviteCode.value.code, '邀请码已复制')
const handleCopyLink = () => {
  if (!hasValidLink.value) {
    ElMessage.warning('当前暂无可复制的注册链接')
    return
  }
  copyText(inviteCode.value.registerUrl, '注册链接已复制')
}

onMounted(async () => {
  try {
    inviteCode.value = await fetchServiceAdminInviteCode()
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '获取邀请码失败')
  } finally {
    loading.value = false
  }
})
</script>

<style scoped lang="scss">
.page-wrap { padding: 28px; }
.head-row { display: flex; justify-content: space-between; gap: 16px; align-items: center; margin-bottom: 24px; }
.head-actions { display: flex; gap: 12px; }
.invite-box { padding: 28px; border-radius: 20px; background: linear-gradient(135deg, rgba(34,197,94,.18), rgba(59,130,246,.12)); border: 1px solid rgba(74,222,128,.25); margin-bottom: 18px; }
.invite-box-head { display: flex; justify-content: space-between; gap: 18px; align-items: flex-start; }
.invite-code { font-size: 42px; font-weight: 800; letter-spacing: .08em; }
.invite-meta { display: flex; gap: 20px; margin-top: 12px; color: var(--text-soft); flex-wrap: wrap; }
.status-pill { display: inline-flex; align-items: center; gap: 8px; padding: 8px 12px; border-radius: 999px; background: rgba(2,6,23,.32); border: 1px solid rgba(74,222,128,.24); color: #d8ffe5; }
.status-dot { width: 8px; height: 8px; border-radius: 999px; background: #4ade80; box-shadow: 0 0 10px rgba(74,222,128,.7); }
.link-panel { margin-bottom: 18px; }
.link-label { margin-bottom: 10px; color: var(--text-soft); font-size: 13px; }
.link-card { padding: 18px; border-radius: 16px; background: rgba(15,23,42,.62); border: 1px solid var(--line); }
.link-main { font-size: 15px; line-height: 1.8; word-break: break-all; color: var(--text); }
.link-tip { margin-top: 8px; color: var(--text-soft); font-size: 12px; }
.data-grid { display: grid; grid-template-columns: repeat(2, minmax(0,1fr)); gap: 14px; }
.data-card { display: grid; gap: 10px; padding: 18px; border-radius: 16px; background: rgba(15,23,42,.62); border: 1px solid var(--line); }
.data-card span { color: var(--text-soft); font-size: 13px; }
.data-card strong { font-size: 26px; }
@media (max-width: 720px) {
  .head-row, .invite-box-head, .head-actions { flex-direction: column; align-items: flex-start; }
  .invite-code { font-size: 28px; }
  .data-grid { grid-template-columns: 1fr; }
}
</style>
