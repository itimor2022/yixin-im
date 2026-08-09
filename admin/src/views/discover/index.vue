<template>
  <div class="discover-page p-4">
    <ElCard shadow="never" class="mb-4">
      <div class="flex items-start justify-between gap-4 max-md:flex-col">
        <div>
          <div class="text-lg font-semibold">发现管理</div>
          <div class="mt-1 text-sm text-g-500">
            管理用户端发现页的轮播图和入口卡片，包括图片、名称、链接地址和顺序。显示状态请直接在表格操作中切换。
          </div>
        </div>
        <ElAlert
          v-if="isDemoAdmin"
          type="warning"
          :closable="false"
          show-icon
          class="w-full max-w-[360px]"
        >
          您当前是演示管理员，只能查看发现入口，无法进行新增、编辑或删除。
        </ElAlert>
      </div>
    </ElCard>

    <ElCard class="art-table-card mb-4" shadow="never">
      <div
        class="mb-4 flex items-center justify-between gap-4 max-md:flex-col max-md:items-stretch"
      >
        <div>
          <div class="text-base font-semibold">轮播图</div>
          <div class="mt-1 text-sm text-g-500">建议使用 16:7 横图，最多展示 5 张启用图片。</div>
        </div>
        <div class="flex items-center gap-2">
          <ElButton @click="loadBanners" :loading="bannerLoading">
            <ArtSvgIcon icon="ri:refresh-line" class="mr-1" />
            刷新
          </ElButton>
          <ElButton type="primary" @click="openCreateBannerDialog" :disabled="isDemoAdmin">
            <ArtSvgIcon icon="ri:image-add-line" class="mr-1" />
            新增轮播图
          </ElButton>
        </div>
      </div>

      <ElTable :data="banners" v-loading="bannerLoading" border stripe>
        <ElTableColumn type="index" label="#" width="60" align="center" />

        <ElTableColumn label="图片" width="190" align="center">
          <template #default="{ row }">
            <div class="discover-banner-thumb">
              <img
                v-if="row.image_url"
                :src="fixImageUrl(row.image_url)"
                alt="banner"
                class="h-full w-full object-cover"
              />
              <ArtSvgIcon v-else icon="ri:image-line" class="text-g-400 text-xl" />
            </div>
          </template>
        </ElTableColumn>

        <ElTableColumn prop="title" label="标题" min-width="180" show-overflow-tooltip />

        <ElTableColumn label="跳转地址" min-width="320" show-overflow-tooltip>
          <template #default="{ row }">
            <span v-if="row.url" class="text-primary">{{ row.url }}</span>
            <span v-else class="text-g-400">不跳转</span>
          </template>
        </ElTableColumn>

        <ElTableColumn prop="sort" label="顺序" width="80" align="center" />

        <ElTableColumn label="状态" width="100" align="center">
          <template #default="{ row }">
            <ElTag :type="row.enabled ? 'success' : 'info'" size="small" effect="light" round>
              {{ row.enabled ? '显示中' : '已隐藏' }}
            </ElTag>
          </template>
        </ElTableColumn>

        <ElTableColumn label="更新时间" width="180" align="center">
          <template #default="{ row }">
            {{ formatTime(row.updated_at || row.created_at) }}
          </template>
        </ElTableColumn>

        <ElTableColumn v-if="!isDemoAdmin" label="操作" width="220" fixed="right" align="center">
          <template #default="{ row }">
            <ElButton type="primary" link size="small" @click="openEditBannerDialog(row)">
              编辑
            </ElButton>
            <ElButton type="warning" link size="small" @click="handleToggleBannerVisible(row)">
              {{ row.enabled ? '隐藏' : '显示' }}
            </ElButton>
            <ElButton type="danger" link size="small" @click="handleDeleteBanner(row)">
              删除
            </ElButton>
          </template>
        </ElTableColumn>
      </ElTable>
    </ElCard>

    <ElCard class="art-table-card" shadow="never">
      <div
        class="mb-4 flex items-center justify-between gap-4 max-md:flex-col max-md:items-stretch"
      >
        <div class="flex flex-1 items-center gap-3 max-md:flex-col max-md:items-stretch">
          <ElInput v-model="keyword" placeholder="搜索标题或网址" clearable style="width: 280px">
            <template #prefix>
              <ArtSvgIcon icon="ri:search-line" />
            </template>
          </ElInput>
          <ElSelect v-model="enabledFilter" clearable placeholder="显示状态" style="width: 120px">
            <ElOption label="显示中" :value="true" />
            <ElOption label="已隐藏" :value="false" />
          </ElSelect>
          <div class="text-sm text-g-500">
            共 <span class="font-semibold text-primary">{{ filteredItems.length }}</span> 个入口
          </div>
        </div>
        <div class="flex items-center gap-2">
          <ElButton @click="loadItems" :loading="loading">
            <ArtSvgIcon icon="ri:refresh-line" class="mr-1" />
            刷新
          </ElButton>
          <ElButton type="primary" @click="openCreateDialog" :disabled="isDemoAdmin">
            <ArtSvgIcon icon="ri:add-line" class="mr-1" />
            新增入口
          </ElButton>
        </div>
      </div>

      <ElTable :data="filteredItems" v-loading="loading" border stripe>
        <ElTableColumn type="index" label="#" width="60" align="center" />

        <ElTableColumn label="图标" width="100" align="center">
          <template #default="{ row }">
            <div class="flex justify-center">
              <div class="discover-icon">
                <img
                  v-if="row.icon_url"
                  :src="fixImageUrl(row.icon_url)"
                  alt="icon"
                  class="h-full w-full object-cover"
                />
                <ArtSvgIcon v-else icon="ri:compass-discover-line" class="text-g-400 text-lg" />
              </div>
            </div>
          </template>
        </ElTableColumn>

        <ElTableColumn prop="title" label="名称" min-width="180" show-overflow-tooltip />

        <ElTableColumn label="链接地址" min-width="320" show-overflow-tooltip>
          <template #default="{ row }">
            <span class="text-primary">{{ row.url }}</span>
          </template>
        </ElTableColumn>

        <ElTableColumn prop="sort" label="顺序" width="80" align="center" />

        <ElTableColumn label="更新时间" width="180" align="center">
          <template #default="{ row }">
            {{ formatTime(row.updated_at || row.created_at) }}
          </template>
        </ElTableColumn>

        <ElTableColumn v-if="!isDemoAdmin" label="操作" width="220" fixed="right" align="center">
          <template #default="{ row }">
            <ElButton type="primary" link size="small" @click="openEditDialog(row)">
              编辑
            </ElButton>
            <ElButton type="warning" link size="small" @click="handleToggleVisible(row)">
              {{ row.enabled ? '隐藏' : '显示' }}
            </ElButton>
            <ElButton type="danger" link size="small" @click="handleDelete(row)"> 删除 </ElButton>
          </template>
        </ElTableColumn>

        <ElTableColumn v-else label="操作" width="100" fixed="right" align="center">
          <template #default="{ row }">
            <ElTag :type="row.enabled ? 'success' : 'info'" size="small" effect="light" round>
              {{ row.enabled ? '显示中' : '已隐藏' }}
            </ElTag>
          </template>
        </ElTableColumn>
      </ElTable>
    </ElCard>

    <ElDialog
      v-model="bannerDialogVisible"
      :title="editingBanner ? '编辑轮播图' : '新增轮播图'"
      width="680px"
      destroy-on-close
    >
      <ElForm :model="bannerForm" label-width="100px">
        <ElFormItem label="标题" required>
          <ElInput
            v-model="bannerForm.title"
            maxlength="100"
            show-word-limit
            placeholder="例如：官方活动"
          />
        </ElFormItem>
        <ElFormItem label="轮播图片" required>
          <div class="flex items-center gap-3">
            <ElUpload
              :action="bannerUploadUrl"
              :headers="uploadHeaders"
              :show-file-list="false"
              accept="image/*"
              :on-success="handleBannerUploadSuccess"
            >
              <div class="discover-banner-preview cursor-pointer">
                <img
                  v-if="bannerForm.image_url"
                  :src="fixImageUrl(bannerForm.image_url)"
                  alt="banner-preview"
                  class="h-full w-full object-cover"
                />
                <ArtSvgIcon v-else icon="ri:image-add-line" class="text-g-400 text-2xl" />
              </div>
            </ElUpload>
            <div class="text-xs text-g-400">建议 1600x700 或同等比例横图，单张不超过 8MB</div>
          </div>
        </ElFormItem>
        <ElFormItem label="跳转网址">
          <ElInput v-model="bannerForm.url" placeholder="可留空；支持 example.com 或 https://example.com" />
        </ElFormItem>
        <ElFormItem label="顺序">
          <ElInputNumber
            v-model="bannerForm.sort"
            :min="0"
            :max="9999"
            controls-position="right"
          />
          <span class="ml-2 text-xs text-g-400">数字越小越靠前</span>
        </ElFormItem>
      </ElForm>

      <template #footer>
        <ElButton @click="bannerDialogVisible = false">取消</ElButton>
        <ElButton type="primary" :loading="bannerSaving" @click="handleSaveBanner">保存</ElButton>
      </template>
    </ElDialog>

    <ElDialog
      v-model="dialogVisible"
      :title="editingItem ? '编辑发现入口' : '新增发现入口'"
      width="620px"
      destroy-on-close
    >
      <ElForm :model="form" label-width="100px">
        <ElFormItem label="标题" required>
          <ElInput v-model="form.title" maxlength="100" show-word-limit placeholder="例如：官网" />
        </ElFormItem>
        <ElFormItem label="图标" required>
          <div class="flex items-center gap-3">
            <ElUpload
              :action="uploadUrl"
              :headers="uploadHeaders"
              :show-file-list="false"
              accept="image/*"
              :on-success="handleUploadSuccess"
            >
              <div class="discover-icon cursor-pointer">
                <img
                  v-if="form.icon_url"
                  :src="fixImageUrl(form.icon_url)"
                  alt="icon-preview"
                  class="h-full w-full object-cover"
                />
                <ArtSvgIcon v-else icon="ri:image-add-line" class="text-g-400 text-lg" />
              </div>
            </ElUpload>
            <div class="text-xs text-g-400"> 点击上传图片 </div>
          </div>
        </ElFormItem>
        <ElFormItem label="访问网址" required>
          <ElInput v-model="form.url" placeholder="支持 example.com 或 https://example.com" />
        </ElFormItem>
        <ElFormItem label="顺序">
          <ElInputNumber v-model="form.sort" :min="0" :max="9999" controls-position="right" />
          <span class="ml-2 text-xs text-g-400">数字越小越靠前</span>
        </ElFormItem>
      </ElForm>

      <template #footer>
        <ElButton @click="dialogVisible = false">取消</ElButton>
        <ElButton type="primary" :loading="saving" @click="handleSave"> 保存 </ElButton>
      </template>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
  import { computed, onMounted, reactive, ref } from 'vue'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import { fixImageUrl } from '@/utils/url'
  import { usePermission } from '@/hooks/usePermission'
  import { useUserStore } from '@/store/modules/user'
  import {
    createDiscoverBanner,
    createDiscoverItem,
    deleteDiscoverBanner,
    deleteDiscoverItem,
    getDiscoverBanners,
    getDiscoverItems,
    updateDiscoverBanner,
    updateDiscoverItem,
    type DiscoverBanner,
    type DiscoverBannerPayload,
    type DiscoverItem,
    type DiscoverItemPayload
  } from '@/api/system-manage'

  defineOptions({ name: 'DiscoverList' })

  const { isDemoAdmin } = usePermission()
  const userStore = useUserStore()

  const loading = ref(false)
  const bannerLoading = ref(false)
  const saving = ref(false)
  const bannerSaving = ref(false)
  const dialogVisible = ref(false)
  const bannerDialogVisible = ref(false)
  const editingItem = ref<DiscoverItem | null>(null)
  const editingBanner = ref<DiscoverBanner | null>(null)
  const keyword = ref('')
  const enabledFilter = ref<boolean | undefined>(undefined)
  const items = ref<DiscoverItem[]>([])
  const banners = ref<DiscoverBanner[]>([])

  const form = reactive<DiscoverItemPayload>({
    title: '',
    icon_url: '',
    url: '',
    sort: 0
  })

  const bannerForm = reactive<DiscoverBannerPayload>({
    title: '',
    image_url: '',
    url: '',
    sort: 0
  })

  const uploadUrl = computed(
    () =>
      `${(import.meta.env.VITE_API_URL || '/api/v1').replace(/\/$/, '')}/admin/settings/discover-items/upload-icon`
  )

  const bannerUploadUrl = computed(
    () =>
      `${(import.meta.env.VITE_API_URL || '/api/v1').replace(/\/$/, '')}/admin/settings/discover-banners/upload-image`
  )

  const uploadHeaders = computed(() => ({
    Authorization: `Bearer ${userStore.accessToken}`
  }))

  const filteredItems = computed(() => {
    const text = keyword.value.trim().toLowerCase()
    return items.value.filter((item) => {
      const matchKeyword =
        !text || item.title.toLowerCase().includes(text) || item.url.toLowerCase().includes(text)
      const matchEnabled = enabledFilter.value === undefined || item.enabled === enabledFilter.value

      return matchKeyword && matchEnabled
    })
  })

  function resetForm() {
    form.title = ''
    form.icon_url = ''
    form.url = ''
    form.sort = 0
  }

  function resetBannerForm() {
    bannerForm.title = ''
    bannerForm.image_url = ''
    bannerForm.url = ''
    bannerForm.sort = 0
  }

  async function loadBanners() {
    bannerLoading.value = true
    try {
      banners.value = (await getDiscoverBanners()) || []
    } catch (error) {
      console.error('加载发现轮播图失败:', error)
      ElMessage.error('加载发现轮播图失败')
    } finally {
      bannerLoading.value = false
    }
  }

  async function loadItems() {
    loading.value = true
    try {
      items.value = (await getDiscoverItems()) || []
    } catch (error) {
      console.error('加载发现入口失败:', error)
      ElMessage.error('加载发现入口失败')
    } finally {
      loading.value = false
    }
  }

  function openCreateBannerDialog() {
    editingBanner.value = null
    resetBannerForm()
    bannerDialogVisible.value = true
  }

  function openEditBannerDialog(banner: DiscoverBanner) {
    editingBanner.value = banner
    bannerForm.title = banner.title
    bannerForm.image_url = banner.image_url || ''
    bannerForm.url = banner.url || ''
    bannerForm.sort = banner.sort ?? 0
    bannerDialogVisible.value = true
  }

  function openCreateDialog() {
    editingItem.value = null
    resetForm()
    dialogVisible.value = true
  }

  function openEditDialog(item: DiscoverItem) {
    editingItem.value = item
    form.title = item.title
    form.icon_url = item.icon_url || ''
    form.url = item.url
    form.sort = item.sort ?? 0
    dialogVisible.value = true
  }

  function handleBannerUploadSuccess(res: any) {
    const url = res?.data?.url || res?.url || ''
    if (url) {
      bannerForm.image_url = url
      ElMessage.success('轮播图片上传成功')
    } else {
      ElMessage.error('轮播图片上传失败')
    }
  }

  function handleUploadSuccess(res: any) {
    const url = res?.data?.url || res?.url || ''
    if (url) {
      form.icon_url = url
      ElMessage.success('图标上传成功')
    } else {
      ElMessage.error('图标上传失败')
    }
  }

  async function handleSaveBanner() {
    if (!bannerForm.title?.trim()) {
      ElMessage.warning('请输入标题')
      return
    }
    if (!bannerForm.image_url?.trim()) {
      ElMessage.warning('请上传轮播图片')
      return
    }

    bannerSaving.value = true
    try {
      const payload: DiscoverBannerPayload = {
        title: bannerForm.title.trim(),
        image_url: bannerForm.image_url.trim(),
        url: bannerForm.url?.trim() || '',
        sort: bannerForm.sort ?? 0
      }

      if (editingBanner.value) {
        await updateDiscoverBanner(editingBanner.value.id, payload)
      } else {
        await createDiscoverBanner(payload)
      }

      ElMessage.success(editingBanner.value ? '更新成功' : '创建成功')
      bannerDialogVisible.value = false
      await loadBanners()
    } catch (error) {
      console.error('保存发现轮播图失败:', error)
    } finally {
      bannerSaving.value = false
    }
  }

  async function handleSave() {
    if (!form.title?.trim()) {
      ElMessage.warning('请输入标题')
      return
    }
    if (!form.url?.trim()) {
      ElMessage.warning('请输入访问网址')
      return
    }
    if (!form.icon_url?.trim()) {
      ElMessage.warning('请上传图标')
      return
    }

    saving.value = true
    try {
      const payload: DiscoverItemPayload = {
        title: form.title.trim(),
        icon_url: form.icon_url?.trim() || '',
        url: form.url.trim(),
        sort: form.sort ?? 0
      }

      if (editingItem.value) {
        await updateDiscoverItem(editingItem.value.id, payload)
      } else {
        await createDiscoverItem(payload)
      }

      ElMessage.success(editingItem.value ? '更新成功' : '创建成功')
      dialogVisible.value = false
      await loadItems()
    } catch (error) {
      console.error('保存发现入口失败:', error)
    } finally {
      saving.value = false
    }
  }

  async function handleToggleBannerVisible(banner: DiscoverBanner) {
    try {
      await updateDiscoverBanner(banner.id, {
        title: banner.title,
        image_url: banner.image_url || '',
        url: banner.url || '',
        sort: banner.sort ?? 0,
        enabled: !banner.enabled
      })
      ElMessage.success(banner.enabled ? '已隐藏' : '已显示')
      await loadBanners()
    } catch (error) {
      console.error('切换发现轮播图显示状态失败:', error)
    }
  }

  async function handleToggleVisible(item: DiscoverItem) {
    try {
      await updateDiscoverItem(item.id, {
        title: item.title,
        icon_url: item.icon_url || '',
        url: item.url,
        sort: item.sort ?? 0,
        enabled: !item.enabled
      })
      ElMessage.success(item.enabled ? '已隐藏' : '已显示')
      await loadItems()
    } catch (error) {
      console.error('切换发现入口显示状态失败:', error)
    }
  }

  async function handleDeleteBanner(banner: DiscoverBanner) {
    try {
      await ElMessageBox.confirm(`确定删除轮播图「${banner.title}」吗？`, '提示', {
        type: 'warning'
      })
      await deleteDiscoverBanner(banner.id)
      ElMessage.success('删除成功')
      await loadBanners()
    } catch {
      // 用户取消不提示
    }
  }

  async function handleDelete(item: DiscoverItem) {
    try {
      await ElMessageBox.confirm(`确定删除「${item.title}」吗？`, '提示', {
        type: 'warning'
      })
      await deleteDiscoverItem(item.id)
      ElMessage.success('删除成功')
      await loadItems()
    } catch {
      // 用户取消不提示
    }
  }

  function formatTime(value: string) {
    if (!value) return '-'
    return new Date(value).toLocaleString('zh-CN')
  }

  onMounted(() => {
    loadBanners()
    loadItems()
  })
</script>

<style scoped lang="scss">
  .discover-icon {
    width: 44px;
    height: 44px;
    flex-shrink: 0;
    overflow: hidden;
    border-radius: 12px;
    border: 1px solid rgb(229 231 235 / 1);
    background: rgb(249 250 251 / 1);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .discover-banner-thumb {
    width: 150px;
    aspect-ratio: 16 / 7;
    overflow: hidden;
    border-radius: 8px;
    border: 1px solid rgb(229 231 235 / 1);
    background: rgb(249 250 251 / 1);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .discover-banner-preview {
    width: 320px;
    max-width: 100%;
    aspect-ratio: 16 / 7;
    overflow: hidden;
    border-radius: 8px;
    border: 1px solid rgb(229 231 235 / 1);
    background: rgb(249 250 251 / 1);
    display: flex;
    align-items: center;
    justify-content: center;
  }
</style>
