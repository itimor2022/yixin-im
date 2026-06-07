<template>
  <div class="popup-announcement-page">
    <ElCard shadow="never">
      <div class="toolbar">
        <span class="title">弹窗公告</span>
        <ElButton type="primary" @click="openCreate">新建公告</ElButton>
      </div>

      <ElTable :data="list" v-loading="loading" stripe style="width: 100%; margin-top: 16px">
        <ElTableColumn prop="id" label="ID" width="70" />
        <ElTableColumn prop="title" label="标题" min-width="160" show-overflow-tooltip />
        <ElTableColumn label="正文" min-width="220" show-overflow-tooltip>
          <template #default="{ row }">
            <span>{{ summarize(row.content) }}</span>
          </template>
        </ElTableColumn>
        <ElTableColumn label="图片" width="90">
          <template #default="{ row }">
            <ElImage
              v-if="row.image_url"
              :src="row.image_url"
              :preview-src-list="[row.image_url]"
              fit="cover"
              style="width: 48px; height: 48px; border-radius: 4px"
            />
            <span v-else style="color: #bbb">—</span>
          </template>
        </ElTableColumn>
        <ElTableColumn label="状态" width="100">
          <template #default="{ row }">
            <ElSwitch
              :model-value="row.enabled === 1"
              @change="(v: string | number | boolean) => toggleEnabled(row, v as boolean)"
            />
          </template>
        </ElTableColumn>
        <ElTableColumn prop="created_at" label="创建时间" width="180" />
        <ElTableColumn label="操作" width="160" fixed="right">
          <template #default="{ row }">
            <ElButton link type="primary" @click="openEdit(row)">编辑</ElButton>
            <ElButton link type="danger" @click="handleDelete(row)">删除</ElButton>
          </template>
        </ElTableColumn>
      </ElTable>

      <div class="pager">
        <ElPagination
          v-model:current-page="page"
          v-model:page-size="pageSize"
          :total="total"
          :page-sizes="[10, 20, 50]"
          layout="total, sizes, prev, pager, next"
          @current-change="loadList"
          @size-change="onSizeChange"
        />
      </div>
    </ElCard>

    <ElDialog
      v-model="dialogVisible"
      :title="editing ? '编辑公告' : '新建公告'"
      width="560px"
      @closed="resetForm"
    >
      <ElForm ref="formRef" :model="form" :rules="rules" label-width="80px">
        <ElFormItem label="标题" prop="title">
          <ElInput v-model="form.title" maxlength="200" show-word-limit placeholder="请输入公告标题" />
        </ElFormItem>
        <ElFormItem label="正文" prop="content">
          <ElInput
            v-model="form.content"
            type="textarea"
            :rows="5"
            placeholder="请输入公告正文"
          />
        </ElFormItem>
        <ElFormItem label="图片">
          <ElUpload
            class="img-uploader"
            :action="uploadAction"
            :headers="uploadHeaders"
            :show-file-list="false"
            accept="image/*"
            :on-success="onUploadSuccess"
            :before-upload="beforeUpload"
          >
            <img v-if="form.image_url" :src="form.image_url" class="uploaded-img" />
            <div v-else class="upload-placeholder">
              <ElIcon><Plus /></ElIcon>
              <span>上传图片</span>
            </div>
          </ElUpload>
          <ElInput
            v-model="form.image_url"
            placeholder="或直接填写图片 URL"
            style="margin-top: 8px"
            clearable
          />
        </ElFormItem>
        <ElFormItem label="跳转链接">
          <ElInput v-model="form.link_url" placeholder="可选，点击公告跳转的 URL" clearable />
        </ElFormItem>
        <ElFormItem label="启用">
          <ElSwitch v-model="form.enabled" />
        </ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="dialogVisible = false">取消</ElButton>
        <ElButton type="primary" :loading="submitting" @click="handleSubmit">确定</ElButton>
      </template>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
import { ref, reactive, computed, onMounted } from 'vue'
import { useUserStore } from '@/store/modules/user'
import { ElMessage, ElMessageBox, type FormInstance, type FormRules } from 'element-plus'
import { Plus } from '@element-plus/icons-vue'
import {
  fetchPopupAnnouncements,
  createPopupAnnouncement,
  updatePopupAnnouncement,
  deletePopupAnnouncement,
  type PopupAnnouncement
} from '@/api/system-manage'

defineOptions({ name: 'PopupAnnouncement' })

const userStore = useUserStore()

const list = ref<PopupAnnouncement[]>([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(20)
const loading = ref(false)

const dialogVisible = ref(false)
const editing = ref<PopupAnnouncement | null>(null)
const submitting = ref(false)
const formRef = ref<FormInstance>()

const form = reactive({
  title: '',
  content: '',
  image_url: '',
  link_url: '',
  enabled: false
})

const rules: FormRules = {
  title: [{ required: true, message: '请输入标题', trigger: 'blur' }],
  content: [{ required: true, message: '请输入正文', trigger: 'blur' }]
}

const uploadAction = computed(
  () =>
    `${(import.meta.env.VITE_API_URL || '/api/v1').replace(/\/$/, '')}/admin/settings/discover-items/upload-icon`
)
const uploadHeaders = computed(() => ({
  Authorization: `Bearer ${userStore.accessToken}`
}))

function summarize(text: string) {
  if (!text) return '—'
  return text.length > 30 ? text.slice(0, 30) + '…' : text
}

async function loadList() {
  loading.value = true
  try {
    const res = await fetchPopupAnnouncements({ page: page.value, page_size: pageSize.value })
    list.value = res.list || []
    total.value = res.total || 0
  } catch (e) {
    ElMessage.error('加载失败')
  } finally {
    loading.value = false
  }
}

function onSizeChange() {
  page.value = 1
  loadList()
}

function resetForm() {
  editing.value = null
  form.title = ''
  form.content = ''
  form.image_url = ''
  form.link_url = ''
  form.enabled = false
  formRef.value?.clearValidate()
}

function openCreate() {
  resetForm()
  dialogVisible.value = true
}

function openEdit(row: PopupAnnouncement) {
  editing.value = row
  form.title = row.title
  form.content = row.content
  form.image_url = row.image_url
  form.link_url = row.link_url
  form.enabled = row.enabled === 1
  dialogVisible.value = true
}

function beforeUpload(file: File) {
  const isImage = file.type.startsWith('image/')
  if (!isImage) {
    ElMessage.error('只能上传图片')
    return false
  }
  const ltSize = file.size / 1024 / 1024 < 5
  if (!ltSize) {
    ElMessage.error('图片不能超过 5MB')
    return false
  }
  return true
}

function onUploadSuccess(res: any) {
  const url = res?.data?.url || res?.url
  if (url) {
    form.image_url = url
    ElMessage.success('上传成功')
  } else {
    ElMessage.error('上传返回异常')
  }
}

async function handleSubmit() {
  await formRef.value?.validate()
  submitting.value = true
  try {
    const payload = {
      title: form.title,
      content: form.content,
      image_url: form.image_url,
      link_url: form.link_url,
      enabled: form.enabled
    }
    if (editing.value) {
      await updatePopupAnnouncement(editing.value.id, payload)
      ElMessage.success('已更新')
    } else {
      await createPopupAnnouncement(payload)
      ElMessage.success('已创建')
    }
    dialogVisible.value = false
    loadList()
  } catch (e) {
    ElMessage.error('保存失败')
  } finally {
    submitting.value = false
  }
}

async function toggleEnabled(row: PopupAnnouncement, val: boolean) {
  try {
    await updatePopupAnnouncement(row.id, {
      title: row.title,
      content: row.content,
      image_url: row.image_url,
      link_url: row.link_url,
      enabled: val
    })
    row.enabled = val ? 1 : 0
    ElMessage.success(val ? '已启用' : '已停用')
  } catch (e) {
    ElMessage.error('操作失败')
  }
}

async function handleDelete(row: PopupAnnouncement) {
  await ElMessageBox.confirm(`确认删除公告「${row.title}」？`, '提示', {
    type: 'warning'
  })
  try {
    await deletePopupAnnouncement(row.id)
    ElMessage.success('已删除')
    loadList()
  } catch (e) {
    ElMessage.error('删除失败')
  }
}

onMounted(loadList)
</script>

<style scoped>
.popup-announcement-page {
  padding: 16px;
}
.toolbar {
  display: flex;
  align-items: center;
  justify-content: space-between;
}
.toolbar .title {
  font-size: 16px;
  font-weight: 600;
}
.pager {
  margin-top: 16px;
  display: flex;
  justify-content: flex-end;
}
.img-uploader .uploaded-img {
  width: 100px;
  height: 100px;
  object-fit: cover;
  border-radius: 6px;
  display: block;
}
.upload-placeholder {
  width: 100px;
  height: 100px;
  border: 1px dashed #d9d9d9;
  border-radius: 6px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  color: #999;
  cursor: pointer;
}
.upload-placeholder:hover {
  border-color: var(--el-color-primary);
}
</style>
