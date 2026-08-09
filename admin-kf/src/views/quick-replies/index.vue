<template>
  <div class="quick-page page-card">
    <header class="page-head">
      <div>
        <span class="eyebrow">运营工具</span>
        <h2>快捷回复</h2>
        <p>团队统一维护高频话术，客服可在接待台搜索并一键插入。</p>
      </div>
      <ElButton type="primary" @click="openCreate"><Icon icon="ri:add-line" /> 新建回复</ElButton>
    </header>

    <section class="metrics">
      <div><span>全部话术</span><strong>{{ rows.length }}</strong></div>
      <div><span>已启用</span><strong>{{ enabledCount }}</strong></div>
      <div><span>话术分组</span><strong>{{ categories.length }}</strong></div>
    </section>

    <div class="toolbar">
      <ElInput v-model="keyword" clearable placeholder="搜索标题、内容或快捷指令" @keyup.enter="loadRows" />
      <ElSelect v-model="category" clearable placeholder="全部分组" @change="loadRows">
        <ElOption v-for="item in categories" :key="item" :label="item" :value="item" />
      </ElSelect>
      <ElButton @click="loadRows"><Icon icon="ri:search-line" /> 查询</ElButton>
    </div>

    <div v-loading="loading" class="reply-table">
      <article v-for="item in rows" :key="item.uuid" :class="{ disabled: !item.enabled }">
        <div class="reply-main">
          <div class="reply-title">
            <strong>{{ item.title }}</strong>
            <span>{{ item.category }}</span>
            <code v-if="item.shortcut">{{ item.shortcut }}</code>
            <em :class="{ enabled: item.enabled }">{{ item.enabled ? '启用' : '停用' }}</em>
          </div>
          <p>{{ item.content }}</p>
          <small v-if="item.keywords">关键词：{{ item.keywords }}</small>
        </div>
        <div class="reply-actions">
          <ElButton text @click="toggleEnabled(item)">{{ item.enabled ? '停用' : '启用' }}</ElButton>
          <ElButton text @click="openEdit(item)">编辑</ElButton>
          <ElButton text type="danger" @click="removeRow(item)">删除</ElButton>
        </div>
      </article>
      <div v-if="!loading && !rows.length" class="empty-state">
        <Icon icon="ri:chat-quote-line" />
        <strong>暂无快捷回复</strong>
        <span>创建第一条团队话术后，可直接在实时接待台使用。</span>
      </div>
    </div>

    <ElDialog v-model="dialogVisible" :title="editingUuid ? '编辑快捷回复' : '新建快捷回复'" width="min(94vw, 600px)">
      <ElForm label-position="top">
        <div class="form-grid">
          <ElFormItem label="标题" required><ElInput v-model="form.title" maxlength="100" placeholder="例如：收集问题信息" /></ElFormItem>
          <ElFormItem label="分组" required><ElInput v-model="form.category" maxlength="50" placeholder="例如：通用、排查、进度" /></ElFormItem>
          <ElFormItem label="快捷指令"><ElInput v-model="form.shortcut" maxlength="30" placeholder="例如：/info" /></ElFormItem>
          <ElFormItem label="排序"><ElInputNumber v-model="form.sort_order" :min="0" :max="9999" controls-position="right" /></ElFormItem>
        </div>
        <ElFormItem label="回复内容" required><ElInput v-model="form.content" type="textarea" :rows="5" maxlength="2000" show-word-limit /></ElFormItem>
        <ElFormItem label="搜索关键词"><ElInput v-model="form.keywords" maxlength="255" placeholder="多个关键词用逗号分隔" /></ElFormItem>
        <ElFormItem><ElCheckbox v-model="form.enabled">启用并在接待台展示</ElCheckbox></ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="dialogVisible = false">取消</ElButton>
        <ElButton type="primary" :loading="saving" :disabled="!form.title.trim() || !form.content.trim()" @click="saveRow">保存</ElButton>
      </template>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { Icon } from '@iconify/vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  createServiceQuickReply,
  deleteServiceQuickReply,
  fetchServiceQuickReplies,
  updateServiceQuickReply,
  type ServiceQuickReply,
  type ServiceQuickReplyInput
} from '@/service/api/workbench'

const rows = ref<ServiceQuickReply[]>([])
const keyword = ref('')
const category = ref('')
const loading = ref(false)
const saving = ref(false)
const dialogVisible = ref(false)
const editingUuid = ref('')
const form = reactive<ServiceQuickReplyInput>({ category: '通用', title: '', content: '', shortcut: '', keywords: '', sort_order: 0, enabled: true })

const enabledCount = computed(() => rows.value.filter((item) => item.enabled).length)
const categories = computed(() => [...new Set(rows.value.map((item) => item.category))])

const resetForm = () => Object.assign(form, { category: '通用', title: '', content: '', shortcut: '', keywords: '', sort_order: 0, enabled: true })

const loadRows = async () => {
  loading.value = true
  try {
    // 筛选交给接口执行，并显式包含停用项，保证管理视图可以重新启用历史回复。
    rows.value = await fetchServiceQuickReplies({ keyword: keyword.value, category: category.value, includeDisabled: true })
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '快捷回复加载失败')
  } finally {
    loading.value = false
  }
}

const openCreate = () => {
  // 空 UUID 表示创建模式；编辑模式则以 UUID 作为后续更新目标。
  editingUuid.value = ''
  resetForm()
  dialogVisible.value = true
}

const openEdit = (item: ServiceQuickReply) => {
  editingUuid.value = item.uuid
  Object.assign(form, { category: item.category, title: item.title, content: item.content, shortcut: item.shortcut, keywords: item.keywords, sort_order: item.sort_order, enabled: item.enabled })
  dialogVisible.value = true
}

const saveRow = async () => {
  saving.value = true
  try {
    if (editingUuid.value) await updateServiceQuickReply(editingUuid.value, { ...form })
    else await createServiceQuickReply({ ...form })
    dialogVisible.value = false
    ElMessage.success(editingUuid.value ? '快捷回复已更新' : '快捷回复已创建')
    await loadRows()
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '快捷回复保存失败')
  } finally {
    saving.value = false
  }
}

const toggleEnabled = async (item: ServiceQuickReply) => {
  try {
    await updateServiceQuickReply(item.uuid, { ...item, enabled: !item.enabled })
    // 服务端确认成功后再更新本地行，失败时界面仍保持原状态。
    item.enabled = !item.enabled
    ElMessage.success(item.enabled ? '已启用' : '已停用')
  } catch (error) {
    ElMessage.error(error instanceof Error ? error.message : '状态更新失败')
  }
}

const removeRow = async (item: ServiceQuickReply) => {
  try {
    await ElMessageBox.confirm(`确认删除“${item.title}”吗？`, '删除快捷回复', { type: 'warning', confirmButtonText: '删除', cancelButtonText: '取消' })
    await deleteServiceQuickReply(item.uuid)
    rows.value = rows.value.filter((row) => row.uuid !== item.uuid)
    ElMessage.success('快捷回复已删除')
  } catch (error) {
    if (error !== 'cancel' && error !== 'close') ElMessage.error(error instanceof Error ? error.message : '删除失败')
  }
}

onMounted(loadRows)
</script>

<style scoped lang="scss">
.quick-page { min-height: 100%; padding: 24px; }
.page-head { display: flex; justify-content: space-between; align-items: flex-start; gap: 20px; padding-bottom: 20px; border-bottom: 1px solid var(--kf-border); }
.eyebrow { color: var(--kf-text-muted); font-size: 10px; font-weight: 700; letter-spacing: .12em; }
h2 { margin: 5px 0 6px; font-size: 22px; } .page-head p { margin: 0; color: var(--kf-text-secondary); font-size: 12px; }
.metrics { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 10px; margin: 18px 0; }
.metrics div { display: grid; gap: 6px; padding: 14px; border: 1px solid var(--kf-border); border-radius: 9px; background: var(--kf-surface-soft); }
.metrics span { color: var(--kf-text-muted); font-size: 10px; } .metrics strong { font-size: 20px; }
.toolbar { display: grid; grid-template-columns: minmax(240px, 1fr) 180px auto; gap: 9px; margin-bottom: 14px; }
.reply-table { display: grid; gap: 8px; min-height: 200px; }
.reply-table article { display: flex; justify-content: space-between; align-items: center; gap: 20px; padding: 14px 16px; border: 1px solid var(--kf-border); border-radius: 9px; background: #fff; }
.reply-table article.disabled { opacity: .62; background: #fafafa; }
.reply-main { min-width: 0; display: grid; gap: 7px; }
.reply-title { display: flex; align-items: center; flex-wrap: wrap; gap: 7px; }
.reply-title strong { font-size: 13px; } .reply-title span, .reply-title em { padding: 3px 6px; border-radius: 4px; color: var(--kf-text-secondary); background: var(--kf-surface-soft); font-size: 9px; font-style: normal; }
.reply-title em.enabled { color: #11632e; background: #e8f7ee; } .reply-title code { color: #555; font-size: 10px; }
.reply-main p { margin: 0; color: var(--kf-text-secondary); font-size: 11px; line-height: 1.65; }
.reply-main small { color: var(--kf-text-muted); font-size: 9px; }
.reply-actions { flex: 0 0 auto; display: flex; }
.empty-state { min-height: 260px; display: grid; place-content: center; justify-items: center; gap: 8px; color: var(--kf-text-muted); }
.empty-state svg { width: 36px; height: 36px; } .empty-state strong { color: var(--kf-text-secondary); font-size: 13px; } .empty-state span { font-size: 10px; }
.form-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 0 14px; }
@media (max-width: 720px) { .quick-page { padding: 14px; } .page-head { align-items: center; } .metrics { grid-template-columns: 1fr; } .toolbar { grid-template-columns: 1fr; } .reply-table article { align-items: flex-start; flex-direction: column; } .reply-actions { align-self: flex-end; } .form-grid { grid-template-columns: 1fr; } }
</style>
