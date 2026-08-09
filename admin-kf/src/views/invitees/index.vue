<template>
  <div class="page-card page-wrap" v-loading="loading">
    <div class="head-row">
      <div>
        <h2 class="page-title">我的用户</h2>
        <p class="page-subtitle">当前为列表壳子，后续接入“通过我的邀请码注册的用户”接口。</p>
      </div>
      <ElInput v-model="keyword" placeholder="搜索用户昵称 / UUID" style="max-width: 320px" />
    </div>

    <div v-if="error" class="state-card error-state">
      <div class="state-title">用户列表加载失败</div>
      <p class="state-text">{{ error }}</p>
        <ElButton type="primary" @click="loadUsers">重新加载</ElButton>
    </div>

    <div v-else-if="filteredUsers.length === 0" class="state-card empty-state">
      <div class="state-title">暂无用户</div>
      <p class="state-text">当前还没有通过你的邀请码注册的用户，后续有新增时会显示在这里。</p>
    </div>

    <div v-else class="user-list">
      <div
        v-for="user in filteredUsers"
        :key="user.id"
        :ref="(el) => setUserRowRef(user.uuid, el)"
        :class="['user-row', { active: highlightedUuid === user.uuid, pulse: animatedUuid === user.uuid }]"
      >
        <div>
          <div class="user-name">{{ user.name }}</div>
          <div class="user-meta">UUID: {{ user.uuid }} · 注册于 {{ user.registeredAt }}</div>
        </div>
        <div class="user-right">
          <ElButton text type="primary" @click="copyUuid(user.uuid)">复制 UUID</ElButton>
          <ElTag :type="user.active ? 'success' : 'info'" round>{{ user.active ? '已绑定' : '未激活' }}</ElTag>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute } from 'vue-router'
import { ElMessage } from 'element-plus'
import { fetchServiceAdminInvitees } from '@/service/api/service-admin'
import type { ServiceAdminInvitee } from '@/types/service-admin'

const route = useRoute()
const loading = ref(true)
const error = ref('')
const keyword = ref('')
const users = ref<ServiceAdminInvitee[]>([])
const highlightedUuid = ref('')
const animatedUuid = ref('')
// 表格行引用随筛选结果动态增删，用于从工作台跳转后精确滚动到目标用户。
const userRowRefs = new Map<string, HTMLElement>()
let animationTimer: ReturnType<typeof setTimeout> | null = null

const filteredUsers = computed(() => {
  const value = keyword.value.trim().toLowerCase()
  if (!value) return users.value
  return users.value.filter((item) =>
    item.name.toLowerCase().includes(value) || item.uuid.toLowerCase().includes(value)
  )
})

const syncQueryState = () => {
  // 工作台通过查询参数同时传入筛选词和高亮 UUID，列表页需保持二者同步。
  const keywordQuery = typeof route.query.keyword === 'string' ? route.query.keyword : ''
  const highlightQuery = typeof route.query.highlight === 'string' ? route.query.highlight : ''
  keyword.value = keywordQuery
  highlightedUuid.value = highlightQuery
}

const setUserRowRef = (uuid: string, element: Element | unknown) => {
  if (element instanceof HTMLElement) {
    userRowRefs.set(uuid, element)
    return
  }
  userRowRefs.delete(uuid)
}

const clearAnimationTimer = () => {
  if (!animationTimer) return
  clearTimeout(animationTimer)
  animationTimer = null
}

const focusHighlightedUser = async () => {
  const uuid = highlightedUuid.value
  if (!uuid) return

  await nextTick()
  const target = userRowRefs.get(uuid)
  if (!target) return

  target.scrollIntoView({ behavior: 'smooth', block: 'center' })
  animatedUuid.value = uuid
  clearAnimationTimer()
  animationTimer = setTimeout(() => {
    animatedUuid.value = ''
    animationTimer = null
  }, 1800)
}

const copyUuid = async (uuid: string) => {
  try {
    await navigator.clipboard.writeText(uuid)
    ElMessage.success('UUID 已复制')
  } catch {
    ElMessage.error('复制失败，请手动复制')
  }
}

const loadUsers = async () => {
  loading.value = true
  error.value = ''

  try {
    users.value = await fetchServiceAdminInvitees()
    await focusHighlightedUser()
  } catch (err) {
    error.value = err instanceof Error ? err.message : '获取用户列表失败'
    ElMessage.error(error.value)
  } finally {
    loading.value = false
  }
}

watch(() => route.query, syncQueryState, { immediate: true })
watch([filteredUsers, highlightedUuid], () => {
  void focusHighlightedUser()
})

onMounted(loadUsers)

onBeforeUnmount(() => {
  clearAnimationTimer()
  userRowRefs.clear()
})
</script>

<style scoped lang="scss">
.page-wrap { padding: 24px; }
.head-row { display: flex; justify-content: space-between; gap: 16px; align-items: center; margin-bottom: 22px; }
.user-list { display: grid; gap: 12px; }
.user-row, .state-card { padding: 18px; border-radius: var(--kf-radius-md); background: var(--kf-surface); border: 1px solid var(--kf-border); }
.user-row { display: flex; justify-content: space-between; align-items: center; gap: 16px; transition: .2s ease; }
.user-row.active { border-color: var(--kf-primary); box-shadow: 0 0 0 1px var(--kf-primary); }
.user-row.pulse { animation: pulse-highlight 1.1s ease; }
.user-name { font-size: 16px; font-weight: 600; }
.user-meta, .state-text { margin-top: 6px; color: var(--text-soft); font-size: 13px; }
.user-right { display: flex; align-items: center; gap: 10px; }
.state-title { font-size: 18px; font-weight: 700; }
.state-text { font-size: 14px; line-height: 1.8; margin-bottom: 16px; }

@keyframes pulse-highlight {
  0% { transform: scale(1); box-shadow: 0 0 0 1px var(--kf-primary); }
  35% { transform: scale(1.005); box-shadow: 0 0 0 1px var(--kf-primary), 0 0 0 8px rgb(23 23 23 / 6%); }
  100% { transform: scale(1); box-shadow: 0 0 0 1px var(--kf-primary); }
}

@media (max-width: 720px) { .head-row, .user-row { flex-direction: column; align-items: flex-start; } }
</style>
