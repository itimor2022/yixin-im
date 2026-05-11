<template>
  <div class="page-card page-wrap" v-loading="loading">
    <h2 class="page-title">欢迎语设置</h2>
    <p class="page-subtitle">后续这里接入获取/更新欢迎语接口，支持保存和预览。</p>

    <div class="preset-panel">
      <div class="preset-head">
        <h3 class="section-title">预设模板</h3>
        <span class="preset-tip">可一键填充后再微调</span>
      </div>
      <div class="preset-status">
        <span class="status-chip">
          当前模板：<strong>{{ activePresetLabel || '自定义内容' }}</strong>
        </span>
        <span v-if="lastSavedAt" class="saved-at">最近保存：{{ lastSavedAt }}</span>
      </div>
      <div class="preset-list">
        <button
          v-for="preset in presets"
          :key="preset.id"
          type="button"
          :class="['preset-card', { active: message === preset.message }]"
          @click="applyPreset(preset.message)"
        >
          <strong>{{ preset.label }}</strong>
          <span>{{ preset.message }}</span>
        </button>
      </div>
      <div class="preset-actions">
        <ElButton plain @click="handleRestoreSystemDefault">恢复系统模板</ElButton>
      </div>
    </div>

    <div class="editor-grid">
      <section class="editor-panel">
        <div class="panel-head">
          <h3 class="section-title">编辑区</h3>
          <div class="length-indicator" :class="{ warning: messageLength > 450 }">{{ messageLength }}/500</div>
        </div>
        <ElInput
          v-model="message"
          type="textarea"
          :rows="10"
          maxlength="500"
          show-word-limit
          placeholder="请输入欢迎语内容"
        />
        <div class="actions">
          <ElButton :disabled="!isDirty" @click="resetMessage">恢复默认</ElButton>
          <ElButton type="success" :loading="saving" :disabled="!isDirty" @click="handleSave">保存欢迎语</ElButton>
        </div>
        <p v-if="isDirty" class="dirty-tip">你有未保存的修改，离开页面前请先保存。</p>
      </section>
      <section class="editor-panel">
        <div class="preview-head">
          <h3 class="section-title">预览区</h3>
          <span class="preview-tag">{{ activePresetLabel || '自定义预览' }}</span>
        </div>
        <div class="preview-box">
          <div class="chat-bubble">{{ message }}</div>
        </div>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, onBeforeMount, onBeforeUnmount, onMounted, ref } from 'vue'
import { onBeforeRouteLeave } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import { fetchServiceAdminWelcomeMessage, saveServiceAdminWelcomeMessage } from '@/service/api/service-admin'

const systemDefaultMessage = '你好，欢迎来到这里～我是你的专属客服，有问题随时告诉我，我会尽快帮你处理。'
const presets = [
  {
    id: 'warm',
    label: '温和接待',
    message: '你好，欢迎来到这里～我是你的专属客服，有问题随时告诉我，我会尽快帮你处理。'
  },
  {
    id: 'guide',
    label: '新手引导',
    message: '欢迎加入～如果你是第一次使用，建议先把你的需求发给我，我会按步骤带你快速上手。'
  },
  {
    id: 'fast',
    label: '高效回复',
    message: '你好，我已在线。请直接发送你的问题、截图或订单信息，我会尽快为你处理。'
  }
]

const defaultMessage = ref('')
const message = ref('')
const loading = ref(true)
const saving = ref(false)
const lastSavedAt = ref('')
const messageLength = computed(() => message.value.length)
const isDirty = computed(() => message.value !== defaultMessage.value)
const activePresetLabel = computed(
  () => presets.find((preset) => preset.message === message.value)?.label || ''
)

const formatNow = () => new Date().toLocaleString('zh-CN', { hour12: false })

const applyPreset = (presetMessage: string) => {
  message.value = presetMessage
}

const applySystemDefault = () => {
  message.value = systemDefaultMessage
}

const handleRestoreSystemDefault = async () => {
  if (message.value === systemDefaultMessage) {
    ElMessage.info('当前已经是系统模板')
    return
  }

  try {
    await ElMessageBox.confirm('确认恢复系统默认欢迎语吗？当前未保存的修改会保留在编辑区结果中，恢复后可继续保存。', '恢复系统模板', {
      type: 'warning',
      confirmButtonText: '确认恢复',
      cancelButtonText: '取消'
    })
    applySystemDefault()
    ElMessage.success('已恢复系统模板内容')
  } catch {
    return
  }
}

const resetMessage = () => {
  message.value = defaultMessage.value
}

const handleSave = async () => {
  saving.value = true
  try {
    const result = await saveServiceAdminWelcomeMessage(message.value)
    defaultMessage.value = result.message
    message.value = result.message
    lastSavedAt.value = formatNow()
    ElMessage.success(`欢迎语已保存（${result.length}/500）`)
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '保存失败')
  } finally {
    saving.value = false
  }
}

const beforeUnloadHandler = (event: BeforeUnloadEvent) => {
  if (!isDirty.value) return
  event.preventDefault()
  event.returnValue = ''
}

onBeforeMount(() => {
  window.addEventListener('beforeunload', beforeUnloadHandler)
})

onBeforeUnmount(() => {
  window.removeEventListener('beforeunload', beforeUnloadHandler)
})

onBeforeRouteLeave(async () => {
  if (!isDirty.value) return true

  try {
    await ElMessageBox.confirm('欢迎语有未保存的修改，确认离开当前页面吗？', '未保存提醒', {
      type: 'warning',
      confirmButtonText: '仍然离开',
      cancelButtonText: '留在当前页'
    })
    return true
  } catch {
    return false
  }
})

onMounted(async () => {
  try {
    const data = await fetchServiceAdminWelcomeMessage()
    defaultMessage.value = data.message
    message.value = data.message
    lastSavedAt.value = formatNow()
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '获取欢迎语失败')
  } finally {
    loading.value = false
  }
})
</script>

<style scoped lang="scss">
.page-wrap { padding: 28px; }
.preset-panel { margin-top: 24px; padding: 22px; border-radius: 18px; background: rgba(15,23,42,.62); border: 1px solid var(--line); }
.preset-head, .preset-status, .preview-head { display: flex; justify-content: space-between; gap: 12px; align-items: center; }
.preset-head { margin-bottom: 14px; }
.preset-status { margin-bottom: 14px; flex-wrap: wrap; }
.preset-tip, .saved-at { color: var(--text-soft); font-size: 13px; }
.status-chip, .preview-tag { display: inline-flex; align-items: center; gap: 6px; padding: 8px 12px; border-radius: 999px; background: rgba(74,222,128,.12); border: 1px solid rgba(74,222,128,.18); color: #c9f7d8; font-size: 13px; }
.preset-list { display: grid; grid-template-columns: repeat(3, minmax(0,1fr)); gap: 12px; }
.preset-card { display: grid; gap: 8px; padding: 16px; border-radius: 14px; border: 1px solid rgba(74,222,128,.16); background: rgba(2,6,23,.35); color: inherit; text-align: left; cursor: pointer; transition: .2s ease; }
.preset-card:hover, .preset-card.active { border-color: rgba(74,222,128,.45); transform: translateY(-1px); box-shadow: 0 0 0 1px rgba(74,222,128,.16); }
.preset-card span { color: var(--text-soft); line-height: 1.7; font-size: 13px; }
.preset-actions { display: flex; justify-content: flex-end; gap: 12px; margin-top: 14px; }
.editor-grid { display: grid; grid-template-columns: repeat(2, minmax(0,1fr)); gap: 18px; margin-top: 24px; }
.editor-panel { padding: 22px; border-radius: 18px; background: rgba(15,23,42,.62); border: 1px solid var(--line); }
.panel-head { display: flex; align-items: center; justify-content: space-between; gap: 12px; margin-bottom: 12px; }
.preview-head { margin-bottom: 16px; }
.length-indicator { color: var(--text-soft); font-size: 13px; }
.length-indicator.warning { color: #fbbf24; }
.actions { display: flex; justify-content: flex-end; gap: 12px; margin-top: 16px; }
.dirty-tip { margin-top: 10px; color: #fbbf24; font-size: 13px; }
.preview-box { min-height: 280px; display: flex; align-items: flex-start; padding: 18px; border-radius: 16px; background: rgba(2,6,23,.5); }
.chat-bubble { max-width: 360px; padding: 14px 16px; border-radius: 16px 16px 16px 6px; background: rgba(34,197,94,.18); border: 1px solid rgba(74,222,128,.22); line-height: 1.8; white-space: pre-wrap; }
@media (max-width: 960px) { .preset-list, .editor-grid { grid-template-columns: 1fr; } .preset-head, .preset-status, .preview-head, .preset-actions { flex-direction: column; align-items: flex-start; } }
</style>
