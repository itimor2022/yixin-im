<template>
  <section class="conversation-queue">
    <header class="queue-header">
      <div>
        <h2>会话队列</h2>
        <p>共 {{ conversations.length }} 个会话</p>
      </div>
      <ElButton text circle aria-label="刷新会话" @click="emit('refresh')"><Icon icon="ri:refresh-line" /></ElButton>
    </header>

    <div class="queue-tabs">
      <button
        v-for="tab in tabs"
        :key="tab.value"
        type="button"
        :class="{ active: modelValue === tab.value }"
        @click="emit('update:modelValue', tab.value)"
      >
        <span>{{ tab.label }}</span>
        <strong>{{ counts[tab.value] }}</strong>
      </button>
    </div>

    <div class="queue-search">
      <Icon icon="ri:search-line" />
      <input
        :value="search"
        type="search"
        placeholder="搜索客户或会话内容"
        @input="emit('update:search', ($event.target as HTMLInputElement).value)"
      />
    </div>

    <div v-if="filteredConversations.length" class="conversation-list">
      <button
        v-for="item in filteredConversations"
        :key="item.id"
        type="button"
        class="conversation-item"
        :class="{ active: item.id === currentId }"
        @click="emit('select', item.id)"
      >
        <div class="customer-avatar">{{ item.customer.avatarText }}</div>
        <div class="conversation-copy">
          <div class="conversation-mainline">
            <strong>{{ item.customer.name }}</strong>
            <time>{{ item.lastAt }}</time>
          </div>
          <div class="conversation-subject">
            <span v-if="item.priority === 'urgent'" class="urgent-dot"></span>
            {{ item.subject }}
          </div>
          <div class="conversation-preview">{{ item.lastMessage }}</div>
          <div class="conversation-meta">
            <span>{{ item.channel === 'app' ? 'App' : '网页' }}</span>
            <span v-if="item.queue === 'waiting'" class="waiting">已等待 {{ item.waitingMinutes }} 分钟</span>
          </div>
        </div>
        <span v-if="item.unread" class="unread-badge">{{ item.unread }}</span>
      </button>
    </div>

    <div v-else class="queue-empty">
      <Icon icon="ri:chat-check-line" />
      <strong>当前队列为空</strong>
      <span>新的客户咨询会自动显示在这里</span>
    </div>
  </section>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { Icon } from '@iconify/vue'
import type { ConversationQueue, ServiceConversation } from '@/types/customer-service'

const props = defineProps<{
  conversations: ServiceConversation[]
  currentId: string
  modelValue: ConversationQueue
  search: string
}>()

// 该组件是受控列表：筛选状态由 v-model/search 回传，选择和刷新只发出意图事件。
const emit = defineEmits<{
  'update:modelValue': [value: ConversationQueue]
  'update:search': [value: string]
  select: [id: string]
  refresh: []
}>()

const tabs: Array<{ label: string; value: ConversationQueue }> = [
  { label: '待接待', value: 'waiting' },
  { label: '我的接待', value: 'serving' },
  { label: '待跟进', value: 'follow_up' },
  { label: '已关闭', value: 'closed' }
]

const counts = computed<Record<ConversationQueue, number>>(() => ({
  waiting: props.conversations.filter((item) => item.queue === 'waiting').length,
  serving: props.conversations.filter((item) => item.queue === 'serving').length,
  follow_up: props.conversations.filter((item) => item.queue === 'follow_up').length,
  closed: props.conversations.filter((item) => item.queue === 'closed').length
}))

const filteredConversations = computed(() => {
  // 队列筛选始终先执行，搜索仅在当前队列内匹配客户与会话摘要字段。
  const keyword = props.search.trim().toLowerCase()
  return props.conversations.filter((item) => {
    if (item.queue !== props.modelValue) return false
    if (!keyword) return true
    return [item.customer.name, item.customer.account, item.subject, item.lastMessage]
      .some((value) => value.toLowerCase().includes(keyword))
  })
})
</script>

<style scoped lang="scss">
.conversation-queue { display: flex; flex-direction: column; min-width: 0; min-height: 0; height: 100%; background: var(--kf-surface); }
.queue-header { display: flex; align-items: center; justify-content: space-between; gap: 12px; padding: 18px 16px 12px; }
.queue-header h2 { margin: 0; font-size: 16px; }
.queue-header p { margin: 4px 0 0; color: var(--kf-text-muted); font-size: 11px; }
.queue-tabs { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 6px; padding: 0 12px 12px; border-bottom: 1px solid var(--kf-border); }
.queue-tabs button { display: flex; justify-content: space-between; align-items: center; gap: 6px; min-width: 0; padding: 8px 9px; border: 0; border-radius: 7px; color: var(--kf-text-secondary); background: transparent; font-size: 11px; cursor: pointer; }
.queue-tabs button:hover { background: var(--kf-surface-soft); }
.queue-tabs button.active { color: #fff; background: var(--kf-primary); }
.queue-tabs strong { font-size: 10px; }
.queue-search { display: flex; align-items: center; gap: 8px; margin: 12px; padding: 9px 10px; border: 1px solid var(--kf-border); border-radius: 8px; color: var(--kf-text-muted); background: var(--kf-surface-soft); }
.queue-search:focus-within { border-color: var(--kf-primary); background: #fff; }
.queue-search input { min-width: 0; width: 100%; padding: 0; border: 0; outline: 0; color: var(--kf-text); background: transparent; font-size: 12px; }
.conversation-list { min-height: 0; overflow-y: auto; }
.conversation-item { position: relative; display: grid; grid-template-columns: 38px minmax(0, 1fr); gap: 10px; width: 100%; padding: 13px 14px; border: 0; border-bottom: 1px solid #f0f1f3; color: inherit; background: transparent; text-align: left; cursor: pointer; }
.conversation-item:hover { background: #fafafa; }
.conversation-item.active { background: #f1f2f4; }
.conversation-item.active::before { content: ''; position: absolute; inset: 0 auto 0 0; width: 3px; background: #171717; }
.customer-avatar { width: 38px; height: 38px; display: grid; place-items: center; border-radius: 10px; color: #fff; background: #303030; font-size: 13px; font-weight: 700; }
.conversation-copy { min-width: 0; }
.conversation-mainline { display: flex; justify-content: space-between; align-items: center; gap: 8px; }
.conversation-mainline strong { overflow: hidden; font-size: 13px; text-overflow: ellipsis; white-space: nowrap; }
.conversation-mainline time { flex: 0 0 auto; color: var(--kf-text-muted); font-size: 10px; }
.conversation-subject { display: flex; align-items: center; gap: 5px; margin-top: 5px; color: var(--kf-text-secondary); font-size: 11px; }
.urgent-dot { width: 5px; height: 5px; border-radius: 50%; background: var(--kf-danger); }
.conversation-preview { margin-top: 4px; overflow: hidden; color: var(--kf-text-muted); font-size: 11px; text-overflow: ellipsis; white-space: nowrap; }
.conversation-meta { display: flex; justify-content: space-between; gap: 8px; margin-top: 7px; color: var(--kf-text-muted); font-size: 9px; }
.conversation-meta .waiting { color: var(--kf-warning); }
.unread-badge { position: absolute; right: 13px; bottom: 11px; min-width: 17px; height: 17px; padding: 0 5px; border-radius: 999px; color: #fff; background: var(--kf-danger); font-size: 9px; line-height: 17px; text-align: center; }
.queue-empty { flex: 1; display: grid; place-content: center; justify-items: center; gap: 8px; padding: 30px; color: var(--kf-text-muted); text-align: center; }
.queue-empty svg { width: 30px; height: 30px; }
.queue-empty strong { color: var(--kf-text-secondary); font-size: 13px; }
.queue-empty span { font-size: 11px; line-height: 1.6; }
</style>
