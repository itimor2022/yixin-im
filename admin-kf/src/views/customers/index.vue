<template>
  <div class="customer-page page-card">
    <header class="page-head">
      <div><span class="eyebrow">客户资产</span><h2>客户管理</h2><p>沉淀标签、内部备注、业务价值和跟进任务，让每次接待都能延续上下文。</p></div>
      <ElButton @click="router.push('/workbench')"><Icon icon="ri:customer-service-2-line" /> 返回接待台</ElButton>
    </header>

    <div class="toolbar">
      <ElInput v-model="keyword" clearable placeholder="搜索客户昵称、账号或编号" @keyup.enter="loadRows" />
      <ElButton type="primary" @click="loadRows"><Icon icon="ri:search-line" /> 查询客户</ElButton>
      <span>共 {{ total }} 位服务客户</span>
    </div>

    <div v-loading="loading" class="customer-table">
      <div class="table-head"><span>客户</span><span>客户标签</span><span>业务价值</span><span>最近服务</span><span>跟进任务</span><span>操作</span></div>
      <article v-for="item in rows" :key="item.customer.uuid">
        <div class="identity"><i>{{ displayName(item).slice(0, 1) }}</i><div><strong>{{ displayName(item) }}</strong><span>{{ item.customer.username }}</span></div></div>
        <div class="tags"><span v-for="tag in item.customer.tags" :key="tag">{{ tag }}</span><em v-if="!item.customer.tags.length">未标签</em></div>
        <div class="value"><strong>{{ item.customer.vip_level || '普通用户' }}</strong><span>余额 ¥{{ Number(item.customer.balance || 0).toFixed(2) }} · 已付 ¥{{ Number(item.customer.total_paid || 0).toFixed(2) }}</span></div>
        <div class="service"><strong>{{ statusLabel[item.last_conversation_status] }}</strong><span>{{ formatDateTime(item.last_conversation_at) }} · {{ item.conversation_count }} 次</span></div>
        <div class="follow-up" :class="{ overdue: item.pending_follow_up && isOverdue(item.pending_follow_up.due_at) }">
          <template v-if="item.pending_follow_up"><strong>{{ item.pending_follow_up.content }}</strong><span>{{ formatDateTime(item.pending_follow_up.due_at) }}</span></template>
          <span v-else>暂无跟进</span>
        </div>
        <div class="actions"><ElButton text @click="openProfile(item)">资料</ElButton><ElButton text @click="openFollowUp(item)">跟进</ElButton></div>
      </article>
      <div v-if="!loading && !rows.length" class="empty-state"><Icon icon="ri:contacts-book-2-line" /><strong>暂无客户记录</strong><span>客户向官方客服发起咨询后会自动进入这里。</span></div>
    </div>

    <ElDialog v-model="profileVisible" title="客户标签与内部备注" width="min(94vw, 560px)">
      <div v-if="selected" class="dialog-customer"><i>{{ displayName(selected).slice(0, 1) }}</i><div><strong>{{ displayName(selected) }}</strong><span>{{ selected.customer.username }} · {{ selected.customer.phone || '未绑定手机' }}</span></div></div>
      <ElForm label-position="top">
        <ElFormItem label="客户标签"><ElSelect v-model="profileTags" multiple filterable allow-create default-first-option placeholder="输入后回车添加，最多 10 个" style="width:100%" /></ElFormItem>
        <ElFormItem label="内部备注"><ElInput v-model="profileNote" type="textarea" :rows="5" maxlength="2000" show-word-limit placeholder="仅客服团队可见，建议记录客户诉求、偏好和处理注意事项" /></ElFormItem>
      </ElForm>
      <template #footer><ElButton @click="profileVisible = false">取消</ElButton><ElButton type="primary" :loading="saving" @click="saveProfile">保存资料</ElButton></template>
    </ElDialog>

    <ElDialog v-model="followUpVisible" title="新建跟进提醒" width="min(94vw, 520px)">
      <div v-if="selected" class="dialog-customer"><i>{{ displayName(selected).slice(0, 1) }}</i><div><strong>{{ displayName(selected) }}</strong><span>提醒将分配给当前客服</span></div></div>
      <ElForm label-position="top">
        <ElFormItem label="跟进内容" required><ElInput v-model="followUpContent" type="textarea" :rows="4" maxlength="500" show-word-limit placeholder="写清楚下次需要确认的事项" /></ElFormItem>
        <ElFormItem label="提醒时间" required><ElDatePicker v-model="followUpAt" type="datetime" value-format="YYYY-MM-DDTHH:mm:ssZ" placeholder="选择提醒时间" style="width:100%" /></ElFormItem>
      </ElForm>
      <template #footer><ElButton @click="followUpVisible = false">取消</ElButton><ElButton type="primary" :loading="saving" :disabled="!followUpContent.trim() || !followUpAt" @click="saveFollowUp">创建提醒</ElButton></template>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { Icon } from '@iconify/vue'
import { ElMessage } from 'element-plus'
import { useRouter } from 'vue-router'
import {
  createServiceFollowUp,
  fetchServiceCustomers,
  updateServiceCustomerProfile,
  type ServiceCustomerDirectoryItem
} from '@/service/api/workbench'

const router = useRouter()
const rows = ref<ServiceCustomerDirectoryItem[]>([])
const total = ref(0)
const keyword = ref('')
const loading = ref(false)
const saving = ref(false)
const selected = ref<ServiceCustomerDirectoryItem>()
const profileVisible = ref(false)
const profileTags = ref<string[]>([])
const profileNote = ref('')
const followUpVisible = ref(false)
const followUpContent = ref('')
const followUpAt = ref('')

const statusLabel: Record<ServiceCustomerDirectoryItem['last_conversation_status'], string> = { waiting: '待接待', assigned: '待接受', serving: '接待中', pending: '待跟进', closed: '已结束' }
const displayName = (item: ServiceCustomerDirectoryItem) => item.customer.nickname || item.customer.username || '未命名客户'
const formatDateTime = (value: string) => new Date(value).toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })
const isOverdue = (value: string) => new Date(value).getTime() < Date.now()

const loadRows = async () => {
  loading.value = true
  try {
    // 客户目录以服务端列表为准，搜索和资料更新后都通过同一入口重新同步。
    const result = await fetchServiceCustomers(keyword.value)
    rows.value = result.list
    total.value = result.total
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '客户列表加载失败')
  } finally {
    loading.value = false
  }
}

const openProfile = (item: ServiceCustomerDirectoryItem) => {
  selected.value = item
  // 标签复制为弹窗草稿，取消编辑时不会污染表格中的原始对象。
  profileTags.value = [...item.customer.tags]
  profileNote.value = item.customer.note
  profileVisible.value = true
}

const saveProfile = async () => {
  if (!selected.value) return
  if (profileTags.value.length > 10) {
    ElMessage.warning('每位客户最多设置 10 个标签')
    return
  }
  saving.value = true
  try {
    const customer = await updateServiceCustomerProfile(selected.value.customer.uuid, profileTags.value, profileNote.value)
    selected.value.customer = customer
    profileVisible.value = false
    ElMessage.success('客户资料已保存')
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '客户资料保存失败')
  } finally {
    saving.value = false
  }
}

const openFollowUp = (item: ServiceCustomerDirectoryItem) => {
  selected.value = item
  followUpContent.value = ''
  followUpAt.value = ''
  followUpVisible.value = true
}

const saveFollowUp = async () => {
  if (!selected.value || !followUpAt.value) return
  saving.value = true
  try {
    selected.value.pending_follow_up = await createServiceFollowUp(selected.value.customer.uuid, {
      conversation_uuid: selected.value.last_conversation_uuid,
      // datetime-local 没有时区信息，提交前统一转换为 ISO 时间。
      content: followUpContent.value.trim(), due_at: new Date(followUpAt.value).toISOString()
    })
    followUpVisible.value = false
    ElMessage.success('跟进提醒已创建')
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '跟进提醒创建失败')
  } finally {
    saving.value = false
  }
}

onMounted(loadRows)
</script>

<style scoped lang="scss">
.customer-page { min-height: 100%; padding: 24px; }
.page-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 20px; padding-bottom: 20px; border-bottom: 1px solid var(--kf-border); }
.eyebrow { color: var(--kf-text-muted); font-size: 10px; font-weight: 700; letter-spacing: .12em; } h2 { margin: 5px 0 6px; font-size: 22px; } .page-head p { margin: 0; color: var(--kf-text-secondary); font-size: 12px; }
.toolbar { display: grid; grid-template-columns: minmax(260px, 440px) auto 1fr; align-items: center; gap: 9px; margin: 18px 0 14px; } .toolbar > span { justify-self: end; color: var(--kf-text-muted); font-size: 10px; }
.customer-table { min-height: 280px; border: 1px solid var(--kf-border); border-radius: 9px; overflow: hidden; }
.table-head, .customer-table article { display: grid; grid-template-columns: 1.25fr 1.1fr 1.15fr .9fr 1.1fr 100px; align-items: center; gap: 12px; padding: 12px 14px; }
.table-head { color: var(--kf-text-muted); background: var(--kf-surface-soft); font-size: 9px; font-weight: 700; }
.customer-table article { min-height: 72px; border-top: 1px solid var(--kf-border); background: #fff; }
.identity { min-width: 0; display: flex; align-items: center; gap: 9px; } .identity i, .dialog-customer i { flex: 0 0 auto; width: 34px; height: 34px; display: grid; place-items: center; border-radius: 9px; color: #fff; background: #171717; font-size: 12px; font-style: normal; font-weight: 700; }
.identity div, .value, .service, .follow-up, .dialog-customer div { min-width: 0; display: grid; gap: 4px; } .identity strong, .value strong, .service strong, .follow-up strong { overflow: hidden; font-size: 10px; text-overflow: ellipsis; white-space: nowrap; } .identity span, .value span, .service span, .follow-up span, .dialog-customer span { overflow: hidden; color: var(--kf-text-muted); font-size: 9px; text-overflow: ellipsis; white-space: nowrap; }
.tags { display: flex; flex-wrap: wrap; gap: 4px; } .tags span { padding: 3px 5px; border-radius: 4px; color: var(--kf-text-secondary); background: var(--kf-surface-soft); font-size: 8px; } .tags em { color: var(--kf-text-muted); font-size: 9px; font-style: normal; }
.follow-up.overdue strong, .follow-up.overdue span { color: #b45309; } .actions { display: flex; }
.empty-state { min-height: 300px; display: grid; place-content: center; justify-items: center; gap: 8px; color: var(--kf-text-muted); } .empty-state svg { width: 36px; height: 36px; } .empty-state strong { color: var(--kf-text-secondary); font-size: 13px; } .empty-state span { font-size: 10px; }
.dialog-customer { display: flex; align-items: center; gap: 10px; margin-bottom: 18px; padding: 12px; border-radius: 8px; background: var(--kf-surface-soft); } .dialog-customer strong { font-size: 12px; }
@media (max-width: 1100px) { .table-head { display: none; } .customer-table { border: 0; display: grid; gap: 9px; } .customer-table article { grid-template-columns: 1fr 1fr; border: 1px solid var(--kf-border); border-radius: 9px; } .actions { justify-self: end; } }
@media (max-width: 640px) { .customer-page { padding: 14px; } .page-head { align-items: center; } .page-head p { display: none; } .toolbar { grid-template-columns: 1fr auto; } .toolbar > span { grid-column: 1 / -1; justify-self: start; } .customer-table article { grid-template-columns: 1fr; } .actions { justify-self: start; } }
</style>
