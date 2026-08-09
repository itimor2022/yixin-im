<template>
  <div class="emoji-store-page p-4">
    <ElCard shadow="never" class="mb-4">
      <div class="flex items-start justify-between gap-4 max-md:flex-col">
        <div>
          <div class="text-lg font-semibold">表情包目录管理</div>
          <div class="mt-1 text-sm text-g-500">
            管理客户端表情商店目录，可配置包标识、名称、预览与贴纸文件列表，并支持上下架。
          </div>
        </div>
        <ElAlert
          v-if="isDemoAdmin"
          type="warning"
          :closable="false"
          show-icon
          class="w-full max-w-[380px]"
        >
          您当前是演示管理员，仅可查看，无法新增、编辑、上下架或删除。
        </ElAlert>
      </div>
    </ElCard>

    <ElCard shadow="never">
      <div
        class="mb-4 flex items-center justify-between gap-4 max-md:flex-col max-md:items-stretch"
      >
        <div class="flex flex-1 items-center gap-3 max-md:flex-col max-md:items-stretch">
          <ElInput
            v-model="keyword"
            placeholder="搜索 pack_id 或名称"
            clearable
            style="width: 280px"
          >
            <template #prefix>
              <ArtSvgIcon icon="ri:search-line" />
            </template>
          </ElInput>
          <ElSelect v-model="activeFilter" clearable placeholder="上下架状态" style="width: 140px">
            <ElOption label="已上架" :value="true" />
            <ElOption label="已下架" :value="false" />
          </ElSelect>
          <div class="text-sm text-g-500">
            共 <span class="font-semibold text-primary">{{ packs.length }}</span> 个表情包
          </div>
        </div>
        <div class="flex items-center gap-2">
          <ElButton :loading="loading" @click="loadPacks">
            <ArtSvgIcon icon="ri:refresh-line" class="mr-1" />
            刷新
          </ElButton>
          <ElButton type="primary" :disabled="isDemoAdmin" @click="openCreateDialog">
            <ArtSvgIcon icon="ri:add-line" class="mr-1" />
            新增表情包
          </ElButton>
        </div>
      </div>

      <ElTable :data="packs" v-loading="loading" border stripe>
        <ElTableColumn type="index" label="#" width="60" align="center" />
        <ElTableColumn prop="pack_id" label="Pack ID" min-width="170" show-overflow-tooltip />
        <ElTableColumn prop="name" label="名称" min-width="160" show-overflow-tooltip />
        <ElTableColumn prop="description" label="描述" min-width="220" show-overflow-tooltip />
        <ElTableColumn label="预览" width="150" align="center">
          <template #default="{ row }">
            <div class="preview-cell">
              <span class="emoji">{{ row.preview_emoji || '-' }}</span>
              <span class="file">{{ previewFileName(row.preview_file) }}</span>
            </div>
          </template>
        </ElTableColumn>
        <ElTableColumn label="贴纸数" width="90" align="center">
          <template #default="{ row }">
            {{ row.sticker_files?.length || 0 }}
          </template>
        </ElTableColumn>
        <ElTableColumn label="排序" width="90" align="center">
          <template #default="{ row }">
            {{ row.sort_order }}
          </template>
        </ElTableColumn>
        <ElTableColumn label="内置包" width="90" align="center">
          <template #default="{ row }">
            <ElTag size="small" :type="row.is_built_in ? 'success' : 'info'" effect="light" round>
              {{ row.is_built_in ? '是' : '否' }}
            </ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn label="状态" width="120" align="center">
          <template #default="{ row }">
            <ElSwitch
              :model-value="row.is_active"
              :disabled="isDemoAdmin"
              @change="(value) => handleToggleActive(row, Boolean(value))"
            />
          </template>
        </ElTableColumn>
        <ElTableColumn label="更新时间" width="170" align="center">
          <template #default="{ row }">
            {{ formatTime(row.updated_at || row.created_at) }}
          </template>
        </ElTableColumn>

        <ElTableColumn v-if="!isDemoAdmin" label="操作" width="170" fixed="right" align="center">
          <template #default="{ row }">
            <ElButton type="primary" link size="small" @click="openEditDialog(row)">
              编辑
            </ElButton>
            <ElButton type="danger" link size="small" @click="handleDelete(row)"> 删除 </ElButton>
          </template>
        </ElTableColumn>
      </ElTable>
    </ElCard>

    <ElDialog
      v-model="dialogVisible"
      :title="editingPack ? '编辑表情包' : '新增表情包'"
      width="760px"
      destroy-on-close
    >
      <ElForm :model="form" label-width="110px">
        <ElFormItem label="Pack ID" required>
          <ElInput
            v-model="form.pack_id"
            maxlength="64"
            show-word-limit
            placeholder="例如：animated_faces"
          />
        </ElFormItem>
        <ElFormItem label="名称" required>
          <ElInput
            v-model="form.name"
            maxlength="100"
            show-word-limit
            placeholder="例如：动态笑脸"
          />
        </ElFormItem>
        <ElFormItem label="描述">
          <ElInput
            v-model="form.description"
            maxlength="255"
            show-word-limit
            type="textarea"
            :rows="2"
            placeholder="表情包描述"
          />
        </ElFormItem>
        <ElFormItem label="预览 Emoji">
          <ElInput v-model="form.preview_emoji" maxlength="16" placeholder="例如：😂" />
        </ElFormItem>
        <ElFormItem label="预览文件">
          <ElInput v-model="form.preview_file" maxlength="100" placeholder="例如：joy.json" />
        </ElFormItem>
        <ElFormItem label="贴纸文件" required>
          <ElInput
            v-model="stickerFilesText"
            type="textarea"
            :rows="6"
            placeholder="每行一个文件名，例如：&#10;joy.json&#10;laughing.json"
          />
          <div class="mt-1 text-xs text-g-400">每行一个文件名，保存时会自动去重和清洗。</div>
        </ElFormItem>
        <ElFormItem label="排序">
          <ElInputNumber v-model="form.sort_order" :min="0" :max="9999" controls-position="right" />
        </ElFormItem>
        <ElFormItem label="内置包">
          <ElSwitch v-model="form.is_built_in" />
        </ElFormItem>
        <ElFormItem label="上架状态">
          <ElSwitch v-model="form.is_active" />
        </ElFormItem>
      </ElForm>

      <template #footer>
        <ElButton @click="dialogVisible = false">取消</ElButton>
        <ElButton type="primary" :loading="saving" @click="handleSave">保存</ElButton>
      </template>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
  import { computed, onMounted, reactive, ref } from 'vue'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import { usePermission } from '@/hooks/usePermission'
  import {
    createEmojiStorePack,
    deleteEmojiStorePack,
    getEmojiStorePacks,
    setEmojiStorePackActive,
    updateEmojiStorePack,
    type EmojiStorePackItem
  } from '@/api/admin'

  defineOptions({ name: 'EmojiStoreCatalog' })

  const { isDemoAdmin } = usePermission()

  const loading = ref(false)
  const saving = ref(false)
  const dialogVisible = ref(false)
  const editingPack = ref<EmojiStorePackItem | null>(null)
  const keyword = ref('')
  const activeFilter = ref<boolean | undefined>(undefined)
  const packs = ref<EmojiStorePackItem[]>([])
  const stickerFilesText = ref('')

  const form = reactive({
    pack_id: '',
    name: '',
    description: '',
    preview_emoji: '',
    preview_file: '',
    sort_order: 0,
    is_built_in: false,
    is_active: true
  })

  const parsedStickerFiles = computed(() =>
    // 多行输入在提交前去空行、去首尾空格并去重，保持服务端文件列表稳定。
    Array.from(
      new Set(
        stickerFilesText.value
          .split('\n')
          .map((v) => v.trim())
          .filter(Boolean)
      )
    )
  )

  function resetForm() {
    form.pack_id = ''
    form.name = ''
    form.description = ''
    form.preview_emoji = ''
    form.preview_file = ''
    form.sort_order = 0
    form.is_built_in = false
    form.is_active = true
    stickerFilesText.value = ''
  }

  async function loadPacks() {
    loading.value = true
    try {
      const data = await getEmojiStorePacks({
        keyword: keyword.value.trim() || undefined,
        is_active: activeFilter.value
      })
      packs.value = data?.list || []
    } catch (error) {
      console.error('加载表情包目录失败:', error)
      ElMessage.error('加载表情包目录失败')
    } finally {
      loading.value = false
    }
  }

  function openCreateDialog() {
    editingPack.value = null
    resetForm()
    dialogVisible.value = true
  }

  function openEditDialog(item: EmojiStorePackItem) {
    // editingPack 同时标识编辑模式和更新目标；表单字段使用快照填充。
    editingPack.value = item
    form.pack_id = item.pack_id || ''
    form.name = item.name || ''
    form.description = item.description || ''
    form.preview_emoji = item.preview_emoji || ''
    form.preview_file = item.preview_file || ''
    form.sort_order = item.sort_order ?? 0
    form.is_built_in = !!item.is_built_in
    form.is_active = !!item.is_active
    stickerFilesText.value = (item.sticker_files || []).join('\n')
    dialogVisible.value = true
  }

  async function handleSave() {
    if (!form.pack_id.trim()) {
      ElMessage.warning('请输入 Pack ID')
      return
    }
    if (!form.name.trim()) {
      ElMessage.warning('请输入名称')
      return
    }
    if (!parsedStickerFiles.value.length) {
      ElMessage.warning('请至少填写一个贴纸文件')
      return
    }

    saving.value = true
    try {
      const payload = {
        // 表单展示态在此收敛为接口载荷，贴纸文件始终使用归一化后的数组。
        pack_id: form.pack_id.trim(),
        name: form.name.trim(),
        description: form.description?.trim() || '',
        preview_emoji: form.preview_emoji?.trim() || '',
        preview_file: form.preview_file?.trim() || '',
        sticker_files: parsedStickerFiles.value,
        sort_order: form.sort_order ?? 0,
        is_built_in: form.is_built_in,
        is_active: form.is_active
      }

      if (editingPack.value) {
        await updateEmojiStorePack(editingPack.value.id, payload)
      } else {
        await createEmojiStorePack(payload)
      }

      ElMessage.success(editingPack.value ? '更新成功' : '创建成功')
      dialogVisible.value = false
      await loadPacks()
    } catch (error) {
      console.error('保存表情包失败:', error)
      ElMessage.error('保存失败，请检查填写内容')
    } finally {
      saving.value = false
    }
  }

  async function handleToggleActive(item: EmojiStorePackItem, isActive: boolean) {
    if (isDemoAdmin.value) return
    try {
      await setEmojiStorePackActive(item.id, isActive)
      // 服务端确认后再更新当前行；失败时重载列表恢复真实状态。
      item.is_active = isActive
      ElMessage.success(isActive ? '已上架' : '已下架')
    } catch (error) {
      console.error('切换表情包状态失败:', error)
      ElMessage.error('状态更新失败')
      await loadPacks()
    }
  }

  async function handleDelete(item: EmojiStorePackItem) {
    try {
      await ElMessageBox.confirm(`确定删除表情包「${item.name}」吗？`, '提示', {
        type: 'warning'
      })
      await deleteEmojiStorePack(item.id)
      ElMessage.success('删除成功')
      await loadPacks()
    } catch {
      // ignore cancel
    }
  }

  function formatTime(value: string) {
    if (!value) return '-'
    return new Date(value).toLocaleString('zh-CN')
  }

  function previewFileName(value: string) {
    if (!value) return '-'
    const normalized = value.replace(/\\/g, '/')
    return normalized.split('/').filter(Boolean).pop() || normalized
  }

  onMounted(() => {
    loadPacks()
  })
</script>

<style scoped lang="scss">
  .preview-cell {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 12px;
    line-height: 1;
    max-width: 128px;
    white-space: nowrap;

    .emoji {
      flex: 0 0 auto;
      font-size: 16px;
    }

    .file {
      min-width: 0;
      overflow: hidden;
      color: rgb(107 114 128 / 1);
      text-overflow: ellipsis;
    }
  }
</style>
