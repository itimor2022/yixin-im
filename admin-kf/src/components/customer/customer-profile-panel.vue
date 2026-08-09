<template>
  <section v-if="conversation" class="customer-panel">
    <header class="profile-head">
      <div class="profile-avatar">{{ conversation.customer.avatarText }}</div>
      <strong>{{ conversation.customer.name }}</strong>
      <span>{{ conversation.customer.account }}</span>
      <div class="profile-tags">
        <span v-for="tag in tags" :key="tag">{{ tag }}<button v-if="editing" type="button" @click="removeTag(tag)">×</button></span>
        <button v-if="!editing && !tags.length" class="empty-tag" type="button" @click="editing = true">添加客户标签</button>
      </div>
      <div v-if="editing" class="tag-editor">
        <input v-model="newTag" maxlength="20" placeholder="输入标签后回车" @keydown.enter.prevent="addTag" />
        <button type="button" :disabled="!newTag.trim()" @click="addTag">添加</button>
      </div>
    </header>

    <div class="profile-section">
      <h3>基础资料</h3>
      <dl>
        <div><dt>客户编号</dt><dd>{{ conversation.customer.id }}</dd></div>
        <div><dt>手机号码</dt><dd>{{ conversation.customer.phone }}</dd></div>
        <div><dt>所在地区</dt><dd>{{ conversation.customer.region }}</dd></div>
        <div><dt>注册时间</dt><dd>{{ conversation.customer.registeredAt }}</dd></div>
        <div><dt>最近活跃</dt><dd>{{ conversation.customer.lastActiveAt }}</dd></div>
      </dl>
    </div>

    <div class="profile-section">
      <div class="section-heading">
        <h3>业务摘要</h3>
        <button type="button">查看详情</button>
      </div>
      <div class="business-grid">
        <div><span>会员等级</span><strong>{{ conversation.customer.vipLevel }}</strong></div>
        <div><span>账户余额</span><strong>{{ conversation.customer.balance }}</strong></div>
        <div><span>会员订单</span><strong>{{ conversation.customer.orderCount }}</strong></div>
        <div><span>累计支付</span><strong>{{ conversation.customer.totalPaid }}</strong></div>
      </div>
    </div>

    <div class="profile-section note-section">
      <div class="section-heading">
        <h3>内部备注</h3>
        <button type="button" :disabled="saving" @click="editing ? saveProfile() : (editing = true)">{{ editing ? (saving ? '保存中' : '保存') : '编辑' }}</button>
      </div>
      <textarea v-if="editing" v-model="note" rows="4" placeholder="输入仅客服可见的备注"></textarea>
      <p v-else>{{ note || '暂无内部备注' }}</p>
    </div>

    <div class="profile-section follow-up-section">
      <div class="section-heading">
        <h3>跟进提醒</h3>
        <button type="button" @click="showFollowUpForm = !showFollowUpForm">{{ showFollowUpForm ? '取消' : '新建' }}</button>
      </div>
      <div v-if="showFollowUpForm" class="follow-up-form">
        <textarea v-model="followUpContent" rows="2" maxlength="500" placeholder="例如：明天下午回访升级结果"></textarea>
        <input v-model="followUpAt" type="datetime-local" />
        <button type="button" :disabled="creatingFollowUp || !followUpContent.trim() || !followUpAt" @click="submitFollowUp">
          {{ creatingFollowUp ? '创建中' : '创建提醒' }}
        </button>
      </div>
      <div v-if="followUps.length" class="follow-up-list">
        <article v-for="item in followUps" :key="item.uuid" :class="{ overdue: isOverdue(item.due_at) }">
          <div><strong>{{ item.content }}</strong><span>{{ formatDateTime(item.due_at) }} · {{ item.agent_name }}</span></div>
          <button type="button" @click="completeFollowUp(item.uuid)">完成</button>
        </article>
      </div>
      <p v-else class="empty-follow-up">暂无待跟进任务</p>
    </div>

    <div class="profile-section timeline-section">
      <h3>服务记录</h3>
      <div class="timeline-item"><i></i><div><strong>发起本次咨询</strong><span>{{ conversation.lastAt }} · {{ conversation.channel === 'app' ? 'App' : '网页' }}</span></div></div>
      <div v-if="conversation.queue === 'closed'" class="timeline-item"><i></i><div><strong>本次会话已结束</strong><span>由 {{ conversation.agentName || '官方客服' }} 处理</span></div></div>
    </div>
  </section>
</template>

<script setup lang="ts">
import { ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import type { ServiceConversation } from '@/types/customer-service'
import {
  createServiceFollowUp,
  fetchServiceFollowUps,
  updateServiceCustomerProfile,
  updateServiceFollowUp,
  type ServiceFollowUp
} from '@/service/api/workbench'

const props = defineProps<{ conversation?: ServiceConversation }>()
const editing = ref(false)
const note = ref('')
const tags = ref<string[]>([])
const newTag = ref('')
const saving = ref(false)
const showFollowUpForm = ref(false)
const followUpContent = ref('')
const followUpAt = ref('')
const creatingFollowUp = ref(false)
const followUps = ref<ServiceFollowUp[]>([])

const addTag = () => {
  const tag = newTag.value.trim()
  if (!tag || tags.value.includes(tag)) return
  if (tags.value.length >= 10) {
    ElMessage.warning('每位客户最多设置 10 个标签')
    return
  }
  tags.value.push(tag)
  newTag.value = ''
}

const removeTag = (tag: string) => {
  tags.value = tags.value.filter((item) => item !== tag)
}

const saveProfile = async () => {
  if (!props.conversation) return
  saving.value = true
  try {
    const result = await updateServiceCustomerProfile(props.conversation.customer.id, tags.value, note.value)
    // 服务端响应是最终值，同时回写会话对象和当前编辑草稿。
    props.conversation.customer.tags = result.tags
    props.conversation.customer.note = result.note
    tags.value = [...result.tags]
    note.value = result.note
    editing.value = false
    ElMessage.success('客户标签和内部备注已保存')
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '客户资料保存失败')
  } finally {
    saving.value = false
  }
}

const loadFollowUps = async () => {
  if (!props.conversation) {
    followUps.value = []
    return
  }
  try {
    followUps.value = await fetchServiceFollowUps(props.conversation.customer.id, 'pending')
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '跟进任务加载失败')
  }
}

const submitFollowUp = async () => {
  if (!props.conversation || !followUpAt.value || !followUpContent.value.trim()) return
  creatingFollowUp.value = true
  try {
    const item = await createServiceFollowUp(props.conversation.customer.id, {
      conversation_uuid: props.conversation.id,
      content: followUpContent.value.trim(),
      due_at: new Date(followUpAt.value).toISOString()
    })
    // 新任务按到期时间重新排序，保证侧栏顺序与后续加载结果一致。
    followUps.value = [...followUps.value, item].sort((a, b) => new Date(a.due_at).getTime() - new Date(b.due_at).getTime())
    followUpContent.value = ''
    followUpAt.value = ''
    showFollowUpForm.value = false
    ElMessage.success('跟进提醒已创建')
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '跟进提醒创建失败')
  } finally {
    creatingFollowUp.value = false
  }
}

const completeFollowUp = async (uuid: string) => {
  try {
    await updateServiceFollowUp(uuid, { status: 'done' })
    followUps.value = followUps.value.filter((item) => item.uuid !== uuid)
    ElMessage.success('跟进任务已完成')
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '跟进任务更新失败')
  }
}

const formatDateTime = (value: string) => new Date(value).toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })
const isOverdue = (value: string) => new Date(value).getTime() < Date.now()

watch(
  () => props.conversation?.id,
  () => {
    // 切换会话时重置本地草稿，并重新加载该客户的待跟进任务。
    note.value = props.conversation?.customer.note || ''
    tags.value = [...(props.conversation?.customer.tags || [])]
    editing.value = false
    showFollowUpForm.value = false
    void loadFollowUps()
  },
  { immediate: true }
)
</script>

<style scoped lang="scss">
.customer-panel { min-width: 0; height: 100%; overflow-y: auto; background: var(--kf-surface); }
.profile-head { display: grid; justify-items: center; padding: 22px 16px 18px; border-bottom: 1px solid var(--kf-border); text-align: center; }
.profile-avatar { width: 54px; height: 54px; display: grid; place-items: center; margin-bottom: 10px; border-radius: 15px; color: #fff; background: #171717; font-size: 19px; font-weight: 750; }
.profile-head strong { font-size: 15px; }
.profile-head > span { margin-top: 4px; color: var(--kf-text-muted); font-size: 10px; }
.profile-tags { display: flex; flex-wrap: wrap; justify-content: center; gap: 5px; margin-top: 10px; }
.profile-tags span { padding: 4px 7px; border: 1px solid var(--kf-border); border-radius: 5px; color: var(--kf-text-secondary); background: var(--kf-surface-soft); font-size: 9px; }
.profile-tags span button { margin-left: 4px; padding: 0; border: 0; color: var(--kf-text-muted); background: transparent; cursor: pointer; }
.empty-tag { padding: 4px 7px; border: 1px dashed var(--kf-border-strong); border-radius: 5px; color: var(--kf-text-muted); background: transparent; font-size: 9px; cursor: pointer; }
.tag-editor { display: flex; width: 100%; gap: 6px; margin-top: 8px; }
.tag-editor input { min-width: 0; flex: 1; padding: 6px 7px; border: 1px solid var(--kf-border); border-radius: 5px; outline: 0; font-size: 9px; }
.tag-editor button { padding: 0 8px; border: 0; border-radius: 5px; color: #fff; background: #171717; font-size: 9px; cursor: pointer; }
.profile-section { padding: 16px; border-bottom: 1px solid var(--kf-border); }
.profile-section h3 { margin: 0 0 12px; font-size: 12px; }
.profile-section dl { display: grid; gap: 10px; margin: 0; }
.profile-section dl > div { display: flex; justify-content: space-between; gap: 10px; min-width: 0; font-size: 10px; }
.profile-section dt { flex: 0 0 auto; color: var(--kf-text-muted); }
.profile-section dd { margin: 0; overflow: hidden; color: var(--kf-text-secondary); text-align: right; text-overflow: ellipsis; white-space: nowrap; }
.section-heading { display: flex; justify-content: space-between; align-items: center; gap: 10px; }
.section-heading h3 { margin-bottom: 12px; }
.section-heading button { padding: 0; border: 0; color: var(--kf-text-secondary); background: transparent; font-size: 10px; cursor: pointer; }
.business-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 7px; }
.business-grid div { display: grid; gap: 5px; padding: 9px; border-radius: 7px; background: var(--kf-surface-soft); }
.business-grid span { color: var(--kf-text-muted); font-size: 9px; }
.business-grid strong { font-size: 11px; }
.note-section p { margin: 0; color: var(--kf-text-secondary); font-size: 10px; line-height: 1.7; }
.note-section textarea { width: 100%; padding: 9px; resize: vertical; border: 1px solid var(--kf-border); border-radius: 7px; outline: none; color: var(--kf-text); font-size: 10px; line-height: 1.6; }
.note-section textarea:focus { border-color: var(--kf-primary); }
.follow-up-form { display: grid; gap: 7px; margin-bottom: 10px; }
.follow-up-form textarea, .follow-up-form input { width: 100%; padding: 8px; border: 1px solid var(--kf-border); border-radius: 6px; outline: 0; font-size: 10px; resize: vertical; }
.follow-up-form > button { padding: 7px; border: 0; border-radius: 6px; color: #fff; background: #171717; font-size: 10px; cursor: pointer; }
.follow-up-form > button:disabled { opacity: .45; cursor: not-allowed; }
.follow-up-list { display: grid; gap: 7px; }
.follow-up-list article { display: flex; justify-content: space-between; align-items: center; gap: 8px; padding: 9px; border: 1px solid var(--kf-border); border-radius: 7px; background: var(--kf-surface-soft); }
.follow-up-list article.overdue { border-color: #fed7aa; background: #fff7ed; }
.follow-up-list article div { min-width: 0; display: grid; gap: 4px; }
.follow-up-list article strong { overflow: hidden; font-size: 10px; text-overflow: ellipsis; white-space: nowrap; }
.follow-up-list article span { color: var(--kf-text-muted); font-size: 8px; }
.follow-up-list article button { flex: 0 0 auto; padding: 4px 6px; border: 1px solid var(--kf-border); border-radius: 5px; background: #fff; font-size: 9px; cursor: pointer; }
.empty-follow-up { margin: 0; color: var(--kf-text-muted); font-size: 9px; }
.timeline-section { border-bottom: 0; }
.timeline-item { position: relative; display: grid; grid-template-columns: 10px minmax(0, 1fr); gap: 8px; padding-bottom: 13px; }
.timeline-item:not(:last-child)::before { content: ''; position: absolute; left: 3px; top: 10px; bottom: 0; width: 1px; background: var(--kf-border); }
.timeline-item i { position: relative; z-index: 1; width: 7px; height: 7px; margin-top: 3px; border-radius: 50%; background: #171717; }
.timeline-item div { display: grid; gap: 4px; }
.timeline-item strong { font-size: 10px; }
.timeline-item span { color: var(--kf-text-muted); font-size: 9px; }
</style>
