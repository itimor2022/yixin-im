<template>
  <div class="workbench page-card" v-loading="loading">
    <div v-if="loadError" class="workbench-error">
      <Icon icon="ri:wifi-off-line" />
      <span>{{ loadError }}</span>
      <button type="button" @click="loadConversations">重新连接</button>
    </div>
    <div v-if="socketState !== 'connected'" class="realtime-state" :class="socketState">
      <span></span>{{ socketState === 'reconnecting' ? '实时连接正在重连' : '实时连接未建立' }}
    </div>
    <aside class="queue-column">
      <ConversationQueue
        v-model="activeQueue"
        v-model:search="search"
        :conversations="conversations"
        :current-id="currentId"
        @select="selectConversation"
        @refresh="loadConversations"
      />
    </aside>

    <section v-if="currentConversation" class="chat-column">
      <header class="conversation-header">
        <div class="conversation-identity">
          <ElButton class="mobile-queue-button" text circle aria-label="打开会话列表" @click="queueDrawer = true">
            <Icon icon="ri:chat-3-line" />
          </ElButton>
          <div class="header-avatar">{{ currentConversation.customer.avatarText }}</div>
          <div class="identity-copy">
            <div class="identity-line">
              <strong>{{ currentConversation.customer.name }}</strong>
              <span class="status-label" :class="currentConversation.queue">{{ queueLabel }}</span>
            </div>
            <p>{{ currentConversation.subject }} · {{ currentConversation.channel === 'app' ? 'App 客户端' : '网页端' }}</p>
          </div>
        </div>
        <div class="conversation-actions">
          <ElButton v-if="currentConversation.queue === 'waiting'" type="primary" size="small" @click="claimConversation">
            领取会话
          </ElButton>
          <ElButton v-else-if="currentConversation.backendStatus === 'assigned'" type="primary" size="small" @click="acceptConversation">
            接受会话
          </ElButton>
          <template v-else-if="currentConversation.queue !== 'closed'">
            <ElButton size="small" @click="showTransfer = true"><Icon icon="ri:share-forward-line" />转接</ElButton>
            <ElButton size="small" @click="closeConversation"><Icon icon="ri:check-double-line" />结束</ElButton>
          </template>
          <ElButton v-else size="small" @click="reopenConversation">重新打开</ElButton>
          <ElButton class="profile-button" text circle aria-label="查看客户资料" @click="profileDrawer = true">
            <Icon icon="ri:user-3-line" />
          </ElButton>
          <ElButton text circle aria-label="更多操作"><Icon icon="ri:more-2-fill" /></ElButton>
        </div>
      </header>

      <div ref="messageList" class="message-list">
        <div class="history-tip"><span>今天</span></div>
        <template v-for="message in currentMessages" :key="message.id">
          <div v-if="message.sender === 'system'" class="system-message">{{ message.content }} · {{ message.time }}</div>
          <div v-else-if="message.sender === 'ai'" class="ai-suggestion">
            <div class="ai-icon"><Icon icon="ri:sparkling-2-line" /></div>
            <div>
              <div class="ai-label">AI 回复建议</div>
              <p>{{ message.content }}</p>
              <button type="button" @click="composer = message.content">采用建议</button>
            </div>
          </div>
          <div v-else class="message-row" :class="message.sender">
            <div v-if="message.sender === 'customer'" class="message-avatar">{{ currentConversation.customer.avatarText }}</div>
            <div class="message-content">
              <div class="message-bubble">{{ message.content }}</div>
              <div class="message-meta">
                <span>{{ message.time }}</span>
                <span v-if="message.sender === 'agent'">{{ message.status === 'failed' ? '发送失败' : '已送达' }}</span>
              </div>
            </div>
            <div v-if="message.sender === 'agent'" class="message-avatar agent">客</div>
          </div>
        </template>
      </div>

      <footer class="composer" :class="{ disabled: currentConversation.queue === 'closed' || currentConversation.backendStatus === 'assigned' }">
        <div class="quick-replies">
          <button v-for="reply in quickReplies.slice(0, 6)" :key="reply.uuid" type="button" :title="reply.title" @click="composer = reply.content">{{ reply.title }}</button>
        </div>
        <div class="composer-tools">
          <button type="button" title="表情"><Icon icon="ri:emotion-line" /></button>
          <button type="button" title="图片"><Icon icon="ri:image-line" /></button>
          <button type="button" title="文件"><Icon icon="ri:attachment-2" /></button>
          <button type="button" title="快捷回复" @click="showQuickReplyPicker = true"><Icon icon="ri:chat-quote-line" /></button>
          <span></span>
          <button type="button" title="AI 回复建议"><Icon icon="ri:sparkling-2-line" /></button>
        </div>
        <textarea
          v-model="composer"
          :disabled="currentConversation.queue === 'closed' || currentConversation.backendStatus === 'assigned'"
          :placeholder="currentConversation.queue === 'closed' ? '该会话已结束，重新打开后可继续回复' : currentConversation.backendStatus === 'assigned' ? '接受会话后即可回复客户' : '输入回复内容，Enter 发送，Shift + Enter 换行'"
          @keydown.enter.exact.prevent="sendMessage"
        ></textarea>
        <div class="composer-footer">
          <span>{{ composer.length }}/2000</span>
          <ElButton type="primary" size="small" :disabled="!canSend" @click="sendMessage">发送</ElButton>
        </div>
      </footer>
    </section>

    <section v-else class="empty-chat">
      <Icon icon="ri:customer-service-2-line" />
      <strong>选择一个会话开始接待</strong>
      <p>客户消息、历史记录和业务资料会显示在这里。</p>
      <ElButton class="mobile-queue-button" type="primary" @click="queueDrawer = true">打开会话列表</ElButton>
    </section>

    <aside class="profile-column">
      <CustomerProfilePanel :conversation="currentConversation" />
    </aside>

    <ElDrawer v-model="queueDrawer" title="会话队列" direction="ltr" size="min(92vw, 340px)" class="workbench-drawer">
      <ConversationQueue
        v-model="activeQueue"
        v-model:search="search"
        :conversations="conversations"
        :current-id="currentId"
        @select="selectFromDrawer"
        @refresh="loadConversations"
      />
    </ElDrawer>

    <ElDrawer v-model="profileDrawer" title="客户资料" size="min(92vw, 340px)" class="workbench-drawer">
      <CustomerProfilePanel :conversation="currentConversation" />
    </ElDrawer>

    <ElDialog v-model="showTransfer" title="转接会话" width="min(92vw, 440px)">
      <ElForm label-position="top">
        <ElFormItem label="转接给">
          <ElSelect v-model="transferAgent" placeholder="请选择在线客服" style="width: 100%">
            <ElOption
              v-for="item in availableAgents"
              :key="item.id"
              :label="`${item.nickname} · 当前接待 ${item.current_serving}/${item.max_concurrent}`"
              :value="item.id"
            />
          </ElSelect>
        </ElFormItem>
        <ElFormItem label="转接备注">
          <ElInput v-model="transferNote" type="textarea" :rows="3" placeholder="填写需要同步给下一位客服的信息" />
        </ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="showTransfer = false">取消</ElButton>
        <ElButton type="primary" :disabled="!transferAgent || !transferNote.trim()" @click="transferConversation">确认转接</ElButton>
      </template>
    </ElDialog>

    <ElDialog v-model="showQuickReplyPicker" title="选择快捷回复" width="min(94vw, 620px)" class="quick-reply-dialog">
      <ElInput v-model="quickReplySearch" clearable placeholder="搜索标题、内容、快捷指令" prefix-icon="Search" />
      <div class="quick-reply-picker">
        <button v-for="reply in filteredQuickReplies" :key="reply.uuid" type="button" @click="applyQuickReply(reply.content)">
          <span><strong>{{ reply.title }}</strong><small>{{ reply.category }} · {{ reply.shortcut || '无快捷指令' }}</small></span>
          <p>{{ reply.content }}</p>
        </button>
        <div v-if="!filteredQuickReplies.length" class="quick-reply-empty">没有匹配的快捷回复</div>
      </div>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { Icon } from '@iconify/vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import ConversationQueue from '@/components/conversation/conversation-queue.vue'
import CustomerProfilePanel from '@/components/customer/customer-profile-panel.vue'
import {
  acceptServiceConversation,
  claimServiceConversation,
  closeServiceConversation,
  fetchAvailableServiceAgents,
  fetchServiceConversationMessages,
  fetchServiceConversations,
  fetchServiceQuickReplies,
  markServiceConversationRead,
  reopenServiceConversation,
  sendServiceConversationText,
  transferServiceConversation,
  type ServiceAgentPresence,
  type ServiceQuickReply
} from '@/service/api/workbench'
import type { ConversationQueue as QueueType, ServiceConversation, ServiceMessage } from '@/types/customer-service'
import { useServiceWebSocket } from '@/composables/use-service-websocket'
import { isServiceRequestErrorStatus } from '@/utils/request'

const conversations = ref<ServiceConversation[]>([])
const messages = ref<Record<string, ServiceMessage[]>>({})
const activeQueue = ref<QueueType>('serving')
const search = ref('')
const currentId = ref('')
const composer = ref('')
const queueDrawer = ref(false)
const profileDrawer = ref(false)
const showTransfer = ref(false)
const showQuickReplyPicker = ref(false)
const quickReplySearch = ref('')
const transferAgent = ref<number>()
const transferNote = ref('')
const messageList = ref<HTMLElement>()
const quickReplies = ref<ServiceQuickReply[]>([])
const availableAgents = ref<ServiceAgentPresence[]>([])
const loading = ref(true)
const loadError = ref('')
let realtimeRefreshTimer: number | undefined

const queueLabels: Record<QueueType, string> = {
  waiting: '待接待',
  serving: '接待中',
  follow_up: '待跟进',
  closed: '已结束'
}

const currentConversation = computed(() => conversations.value.find((item) => item.id === currentId.value))
const currentMessages = computed(() => messages.value[currentId.value] || [])
const queueLabel = computed(() => {
  if (currentConversation.value?.backendStatus === 'assigned') return '待接受'
  return currentConversation.value ? queueLabels[currentConversation.value.queue] : ''
})
const canSend = computed(() => Boolean(composer.value.trim()) && currentConversation.value?.queue !== 'closed' && currentConversation.value?.backendStatus !== 'assigned')
const filteredQuickReplies = computed(() => {
  const keyword = quickReplySearch.value.trim().toLowerCase()
  if (!keyword) return quickReplies.value
  return quickReplies.value.filter((item) => [item.title, item.content, item.shortcut, item.keywords]
    .some((value) => value.toLowerCase().includes(keyword)))
})

const applyQuickReply = (content: string) => {
  composer.value = content
  showQuickReplyPicker.value = false
}

const scrollToBottom = () => nextTick(() => {
  if (messageList.value) messageList.value.scrollTop = messageList.value.scrollHeight
})

const selectConversation = async (id: string) => {
  currentId.value = id
  const item = conversations.value.find((conversation) => conversation.id === id)
  if (item) item.unread = 0
  if (item) {
    try {
      messages.value[id] = await fetchServiceConversationMessages(item)
      // 待接待会话尚未归属任何客服。允许预览历史，但只有领取后才
      // 可以清除客户未读数，否则后端会正确返回 403。
      if (item.backendStatus !== 'waiting') {
        // 本地先清零用于即时反馈，服务端 read 成功后实时刷新会给出最终未读状态。
        await markServiceConversationRead(id)
      }
    } catch (error) {
      if (isServiceRequestErrorStatus(error, 403)) {
        delete messages.value[id]
        conversations.value = conversations.value.filter((conversation) => conversation.id !== id)
        if (currentId.value === id) currentId.value = ''
        ElMessage.warning('会话归属已变化，已从当前队列移除')
        return
      }
      ElMessage.error(error instanceof Error ? error.message : '消息记录加载失败')
    }
  }
  scrollToBottom()
}

const selectFromDrawer = async (id: string) => {
  await selectConversation(id)
  queueDrawer.value = false
}

const claimConversation = async () => {
  if (!currentConversation.value) return
  try {
    await claimServiceConversation(currentConversation.value.id)
    currentConversation.value.queue = 'serving'
    currentConversation.value.backendStatus = 'serving'
    currentConversation.value.agentName = '官方客服小助手'
    activeQueue.value = 'serving'
    ElMessage.success('会话已领取')
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '领取会话失败')
    await loadConversations()
  }
}

const acceptConversation = async () => {
  if (!currentConversation.value) return
  try {
    await acceptServiceConversation(currentConversation.value.id)
    currentConversation.value.backendStatus = 'serving'
    ElMessage.success('会话已进入接待中')
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '接受会话失败')
    await loadConversations()
  }
}

const closeConversation = async () => {
  if (!currentConversation.value) return
  try {
    await ElMessageBox.confirm('结束后客户将收到满意度评价邀请，确认结束本次会话吗？', '结束会话', {
      confirmButtonText: '确认结束',
      cancelButtonText: '继续接待',
      type: 'warning'
    })
    await closeServiceConversation(currentConversation.value.id)
    currentConversation.value.queue = 'closed'
    currentConversation.value.backendStatus = 'closed'
    activeQueue.value = 'closed'
    messages.value[currentId.value]?.push({
      id: `m-system-${Date.now()}`,
      sender: 'system',
      content: '会话已由官方客服小助手关闭',
      time: new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })
    })
    ElMessage.success('会话已结束')
  } catch (error) {
    if (error !== 'cancel' && error !== 'close') {
      ElMessage.error(error instanceof Error ? error.message : '结束会话失败')
    }
  }
}

const reopenConversation = async () => {
  if (!currentConversation.value) return
  try {
    await reopenServiceConversation(currentConversation.value.id)
    currentConversation.value.queue = 'serving'
    currentConversation.value.backendStatus = 'serving'
    activeQueue.value = 'serving'
    ElMessage.success('会话已重新打开')
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '重新打开失败')
  }
}

const transferConversation = async () => {
  if (!currentConversation.value || !transferAgent.value) return
  const target = availableAgents.value.find((item) => item.id === transferAgent.value)
  try {
    await transferServiceConversation(currentConversation.value.id, transferAgent.value, transferNote.value)
    showTransfer.value = false
    transferAgent.value = undefined
    transferNote.value = ''
    ElMessage.success(`已转接给${target?.nickname || '目标客服'}`)
    // 转接后当前客服可能失去会话可见权，必须全量刷新队列而不是只改 agentName。
    await loadConversations()
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '转接失败')
  }
}

const sendMessage = async () => {
  const content = composer.value.trim()
  if (!content || !currentConversation.value || currentConversation.value.queue === 'closed') return
  try {
    const message = await sendServiceConversationText(currentConversation.value.id, content)
    if (!messages.value[currentId.value]) messages.value[currentId.value] = []
    messages.value[currentId.value].push(message)
    currentConversation.value.lastMessage = content
    currentConversation.value.lastAt = message.time
    composer.value = ''
    scrollToBottom()
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '消息发送失败')
  }
}

const loadConversations = async () => {
  loading.value = true
  loadError.value = ''
  try {
    const queues: QueueType[] = ['waiting', 'serving', 'follow_up', 'closed']
    // 四个队列接口并行读取，确保一次刷新得到同一时点附近的完整工作台视图。
    const result = await Promise.all(queues.map((queue) => fetchServiceConversations(queue)))
    conversations.value = result.flat()
    const stillExists = conversations.value.some((item) => item.id === currentId.value)
    if (!stillExists) {
      const next = conversations.value.find((item) => item.queue === activeQueue.value) || conversations.value[0]
      currentId.value = next?.id || ''
      if (next) activeQueue.value = next.queue
    }
    if (currentConversation.value) await selectConversation(currentConversation.value.id)
  } catch (error) {
    loadError.value = error instanceof Error ? error.message : '客服会话连接失败'
  } finally {
    loading.value = false
  }
}

const loadQuickReplies = async () => {
  try {
    quickReplies.value = await fetchServiceQuickReplies()
  } catch (error) {
    ElMessage.warning(error instanceof Error ? error.message : '快捷回复加载失败')
  }
}

watch(showTransfer, async (visible) => {
  if (!visible) return
  try {
    availableAgents.value = await fetchAvailableServiceAgents()
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '可转接客服加载失败')
  }
})

const { state: socketState, connect: connectSocket } = useServiceWebSocket((event) => {
  if (!event.type.startsWith('service.')) return
  if (realtimeRefreshTimer) window.clearTimeout(realtimeRefreshTimer)
  // 一次业务操作可能连续推送多条 service.* 事件，短暂去抖后用 HTTP 数据统一校准。
  realtimeRefreshTimer = window.setTimeout(() => loadConversations(), 180)
})

onMounted(async () => {
  await Promise.all([loadConversations(), loadQuickReplies()])
  connectSocket()
})

onBeforeUnmount(() => {
  if (realtimeRefreshTimer) window.clearTimeout(realtimeRefreshTimer)
})
</script>

<style scoped lang="scss">
.workbench { position: relative; display: grid; grid-template-columns: minmax(260px, 306px) minmax(380px, 1fr) minmax(260px, 300px); width: 100%; height: 100%; min-height: 0; overflow: hidden; }
.workbench-error { position: absolute; z-index: 12; inset: 10px 50% auto auto; display: flex; align-items: center; gap: 7px; padding: 8px 10px; border: 1px solid #fed7aa; border-radius: 7px; color: #9a3412; background: #fff7ed; box-shadow: var(--kf-shadow); font-size: 10px; transform: translateX(50%); }
.workbench-error button { padding: 0; border: 0; color: inherit; background: transparent; font-weight: 700; cursor: pointer; }
.realtime-state { position: absolute; z-index: 11; right: 12px; bottom: 12px; display: flex; align-items: center; gap: 6px; padding: 6px 9px; border: 1px solid var(--kf-border); border-radius: 6px; color: var(--kf-text-secondary); background: rgb(255 255 255 / 92%); box-shadow: var(--kf-shadow); font-size: 9px; }
.realtime-state span { width: 6px; height: 6px; border-radius: 50%; background: var(--kf-warning); }
.realtime-state.closed span { background: var(--kf-text-muted); }
.queue-column, .chat-column, .profile-column { min-width: 0; min-height: 0; }
.queue-column { border-right: 1px solid var(--kf-border); }
.profile-column { border-left: 1px solid var(--kf-border); }
.chat-column { display: grid; grid-template-rows: auto minmax(0, 1fr) auto; background: #f7f8fa; }
.conversation-header { display: flex; justify-content: space-between; align-items: center; gap: 16px; min-height: 65px; padding: 10px 16px; border-bottom: 1px solid var(--kf-border); background: #fff; }
.conversation-identity { display: flex; align-items: center; min-width: 0; gap: 10px; }
.header-avatar { flex: 0 0 auto; width: 36px; height: 36px; display: grid; place-items: center; border-radius: 10px; color: #fff; background: #303030; font-size: 12px; font-weight: 700; }
.identity-copy { min-width: 0; }
.identity-line { display: flex; align-items: center; gap: 7px; }
.identity-line strong { overflow: hidden; font-size: 13px; text-overflow: ellipsis; white-space: nowrap; }
.identity-copy p { margin: 4px 0 0; overflow: hidden; color: var(--kf-text-muted); font-size: 10px; text-overflow: ellipsis; white-space: nowrap; }
.status-label { padding: 2px 5px; border-radius: 4px; color: var(--kf-text-secondary); background: #eef0f2; font-size: 9px; }
.status-label.waiting { color: #9a5b00; background: #fff4dd; }
.status-label.serving { color: #11632e; background: #e8f7ee; }
.status-label.closed { color: #6b7280; background: #f1f2f4; }
.conversation-actions { display: flex; align-items: center; gap: 6px; flex: 0 0 auto; }
.conversation-actions :deep(.el-button + .el-button) { margin-left: 0; }
.mobile-queue-button, .profile-button { display: none; }
.message-list { min-height: 0; padding: 22px 5%; overflow-y: auto; scroll-behavior: smooth; }
.history-tip { display: flex; align-items: center; gap: 10px; margin-bottom: 18px; color: var(--kf-text-muted); font-size: 9px; }
.history-tip::before, .history-tip::after { content: ''; flex: 1; height: 1px; background: var(--kf-border); }
.system-message { margin: 13px auto; color: var(--kf-text-muted); font-size: 9px; text-align: center; }
.message-row { display: flex; align-items: flex-start; gap: 8px; margin: 15px 0; }
.message-row.agent { justify-content: flex-end; }
.message-avatar { flex: 0 0 auto; width: 29px; height: 29px; display: grid; place-items: center; border-radius: 8px; color: #fff; background: #4b5563; font-size: 10px; font-weight: 700; }
.message-avatar.agent { color: #fff; background: #171717; }
.message-content { max-width: min(72%, 620px); }
.message-bubble { padding: 10px 12px; border: 1px solid var(--kf-border); border-radius: 4px 11px 11px; color: var(--kf-text); background: #fff; font-size: 12px; line-height: 1.65; white-space: pre-wrap; word-break: break-word; }
.agent .message-bubble { border-color: #171717; border-radius: 11px 4px 11px 11px; color: #fff; background: #171717; }
.message-meta { display: flex; justify-content: flex-start; gap: 6px; margin-top: 4px; color: var(--kf-text-muted); font-size: 8px; }
.agent .message-meta { justify-content: flex-end; }
.ai-suggestion { display: grid; grid-template-columns: 28px minmax(0, 1fr); gap: 9px; width: min(82%, 650px); margin: 15px auto; padding: 11px; border: 1px dashed #cfd3d9; border-radius: 9px; background: #fff; }
.ai-icon { width: 28px; height: 28px; display: grid; place-items: center; border-radius: 7px; color: #fff; background: #475569; }
.ai-label { color: var(--kf-text-secondary); font-size: 9px; font-weight: 700; }
.ai-suggestion p { margin: 5px 0; color: var(--kf-text-secondary); font-size: 10px; line-height: 1.6; }
.ai-suggestion button { padding: 0; border: 0; color: var(--kf-text); background: transparent; font-size: 9px; font-weight: 650; cursor: pointer; }
.composer { padding: 8px 14px 11px; border-top: 1px solid var(--kf-border); background: #fff; }
.quick-replies { display: flex; gap: 6px; padding-bottom: 7px; overflow-x: auto; scrollbar-width: none; }
.quick-replies::-webkit-scrollbar { display: none; }
.quick-replies button { flex: 0 0 auto; max-width: 210px; padding: 5px 8px; overflow: hidden; border: 1px solid var(--kf-border); border-radius: 6px; color: var(--kf-text-secondary); background: var(--kf-surface-soft); font-size: 9px; text-overflow: ellipsis; white-space: nowrap; cursor: pointer; }
.quick-replies button:hover { border-color: var(--kf-border-strong); color: var(--kf-text); background: #fff; }
.composer-tools { display: flex; align-items: center; gap: 3px; }
.composer-tools button { width: 27px; height: 27px; display: grid; place-items: center; padding: 0; border: 0; border-radius: 5px; color: var(--kf-text-secondary); background: transparent; cursor: pointer; }
.composer-tools button:hover { color: var(--kf-text); background: var(--kf-surface-soft); }
.composer-tools span { flex: 1; }
.composer textarea { display: block; width: 100%; height: 58px; padding: 6px 2px; resize: none; border: 0; outline: 0; color: var(--kf-text); background: transparent; font-size: 12px; line-height: 1.55; }
.composer textarea::placeholder { color: var(--kf-text-muted); }
.composer-footer { display: flex; justify-content: space-between; align-items: center; gap: 12px; }
.composer-footer > span { color: var(--kf-text-muted); font-size: 9px; }
.composer.disabled { background: #fafafa; }
.empty-chat { display: grid; place-content: center; justify-items: center; gap: 9px; min-width: 0; color: var(--kf-text-muted); background: #f7f8fa; text-align: center; }
.empty-chat > svg { width: 38px; height: 38px; }
.empty-chat strong { color: var(--kf-text-secondary); font-size: 14px; }
.empty-chat p { margin: 0; font-size: 11px; }
:global(.workbench-drawer .el-drawer__body) { padding: 0; overflow: hidden; }
.quick-reply-picker { display: grid; gap: 8px; max-height: 52vh; margin-top: 14px; overflow-y: auto; }
.quick-reply-picker > button { display: grid; gap: 7px; padding: 12px; border: 1px solid var(--kf-border); border-radius: 8px; color: var(--kf-text); background: #fff; text-align: left; cursor: pointer; }
.quick-reply-picker > button:hover { border-color: #171717; background: var(--kf-surface-soft); }
.quick-reply-picker span { display: flex; justify-content: space-between; align-items: center; gap: 12px; }
.quick-reply-picker strong { font-size: 12px; }
.quick-reply-picker small { color: var(--kf-text-muted); font-size: 9px; }
.quick-reply-picker p { margin: 0; color: var(--kf-text-secondary); font-size: 10px; line-height: 1.6; }
.quick-reply-empty { padding: 36px; color: var(--kf-text-muted); text-align: center; font-size: 11px; }

@media (max-width: 1279px) {
  .workbench { grid-template-columns: minmax(260px, 290px) minmax(360px, 1fr); }
  .profile-column { display: none; }
  .profile-button { display: inline-flex; }
}

@media (max-width: 959px) {
  .workbench { grid-template-columns: minmax(0, 1fr); }
  .queue-column { display: none; }
  .mobile-queue-button { display: inline-flex; }
}

@media (max-width: 640px) {
  .conversation-header { min-height: 58px; padding: 8px 9px; }
  .header-avatar { display: none; }
  .conversation-actions :deep(.el-button:not(.is-circle)) { padding-inline: 8px; }
  .conversation-actions :deep(.el-button:not(.is-circle) span svg) { display: none; }
  .message-list { padding: 14px 10px; }
  .message-content { max-width: 82%; }
  .composer { padding-inline: 9px; }
  .quick-replies { display: none; }
}
</style>
