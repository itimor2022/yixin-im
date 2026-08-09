<template>
  <div class="hot-update-page p-4">
    <ElCard shadow="never" class="mb-4">
      <div class="flex items-start justify-between gap-4 max-md:flex-col">
        <div>
          <div class="text-lg font-semibold">热更新补丁管理</div>
          <div class="mt-1 text-sm text-g-500">
            支持补丁创建、灰度比例配置、发布、暂停、回滚；客户端通过
            <code>/app/hot-update/check</code> 自动命中可用补丁。
          </div>
        </div>
        <ElAlert
          v-if="isDemoAdmin"
          type="warning"
          :closable="false"
          show-icon
          class="w-full max-w-[380px]"
        >
          当前为演示管理员，仅可查看，不可创建、发布、暂停、回滚或删除补丁。
        </ElAlert>
      </div>
    </ElCard>

    <ElAlert
      class="mb-4"
      type="info"
      :closable="false"
      show-icon
      title="支持两种投递模式：self_hosted 用于整包安装更新，shorebird 用于不重装的 Dart 补丁。整包模式才需要填写 patch_url。"
    />

    <ElCard shadow="never">
      <div
        class="mb-4 flex items-center justify-between gap-3 max-md:flex-col max-md:items-stretch"
      >
        <div class="flex flex-1 items-center gap-3 max-md:flex-col max-md:items-stretch">
          <ElInput
            v-model="query.keyword"
            placeholder="搜索名称 / Patch ID / 版本"
            clearable
            style="width: 260px"
          />
          <ElSelect v-model="query.platform" clearable placeholder="平台" style="width: 130px">
            <ElOption label="Android" value="android" />
            <ElOption label="iOS" value="ios" />
            <ElOption label="全平台" value="all" />
          </ElSelect>
          <ElSelect v-model="query.status" clearable placeholder="状态" style="width: 130px">
            <ElOption label="草稿" value="draft" />
            <ElOption label="已发布" value="published" />
            <ElOption label="已暂停" value="paused" />
            <ElOption label="已回滚" value="rolled_back" />
          </ElSelect>
          <ElSelect
            v-model="query.delivery_mode"
            clearable
            placeholder="投递模式"
            style="width: 150px"
          >
            <ElOption label="自托管整包" value="self_hosted" />
            <ElOption label="Shorebird" value="shorebird" />
          </ElSelect>
          <ElInput
            v-model="query.channel"
            placeholder="渠道，默认 stable"
            clearable
            style="width: 180px"
          />
        </div>
        <div class="flex items-center gap-2">
          <ElButton :loading="loading" @click="loadList">刷新</ElButton>
          <ElButton type="primary" :disabled="isDemoAdmin" @click="openCreate"> 新建补丁 </ElButton>
        </div>
      </div>

      <ElTable :data="list" v-loading="loading" border stripe>
        <ElTableColumn prop="id" label="ID" width="80" />
        <ElTableColumn label="补丁信息" min-width="280">
          <template #default="{ row }">
            <div class="flex flex-col">
              <span class="font-medium">{{ row.name }}</span>
              <span class="text-xs text-g-500">Patch ID: {{ row.patch_id }}</span>
              <span class="text-xs text-g-500">版本：{{ row.patch_version }}</span>
              <span class="text-xs text-g-500">
                生效窗口：{{ formatSchedule(row.start_at, row.end_at) }}
              </span>
            </div>
          </template>
        </ElTableColumn>
        <ElTableColumn label="平台 / 渠道" width="150">
          <template #default="{ row }">
            <div>{{ platformText(row.platform) }}</div>
            <div class="text-xs text-g-500">{{ row.channel || 'stable' }}</div>
            <div class="text-xs text-g-500">{{ deliveryModeText(row.delivery_mode) }}</div>
          </template>
        </ElTableColumn>
        <ElTableColumn label="适配范围" min-width="220">
          <template #default="{ row }">
            <div class="text-xs">
              App 版本：{{ row.min_app_version || '-' }} ~ {{ row.max_app_version || '-' }}
            </div>
            <div class="text-xs text-g-500">
              Build：{{ row.min_build_number || '-' }} ~ {{ row.max_build_number || '-' }}
            </div>
          </template>
        </ElTableColumn>
        <ElTableColumn label="灰度 / 优先级" width="130">
          <template #default="{ row }">
            <div>{{ row.rollout_percentage }}%</div>
            <div class="text-xs text-g-500">优先级：{{ row.priority }}</div>
          </template>
        </ElTableColumn>
        <ElTableColumn label="强制" width="80" align="center">
          <template #default="{ row }">
            <ElTag :type="row.is_mandatory ? 'danger' : 'info'" size="small" effect="light" round>
              {{ row.is_mandatory ? '是' : '否' }}
            </ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn label="状态" width="110" align="center">
          <template #default="{ row }">
            <ElTag :type="statusType(row.status)" size="small" effect="light" round>
              {{ statusText(row.status) }}
            </ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn label="更新时间" width="170">
          <template #default="{ row }">
            {{ formatTime(row.updated_at || row.created_at) }}
          </template>
        </ElTableColumn>
        <ElTableColumn label="操作" :width="isDemoAdmin ? 120 : 320" fixed="right">
          <template #default="{ row }">
            <ElButton type="primary" link size="small" @click="focusReportsForPatch(row)">
              查看上报
            </ElButton>
            <template v-if="!isDemoAdmin">
              <ElButton type="primary" link size="small" @click="openEdit(row)">编辑</ElButton>
              <ElButton
                v-if="row.status !== 'published'"
                type="success"
                link
                size="small"
                @click="handleStatusAction('publish', row)"
              >
                发布
              </ElButton>
              <ElButton
                v-if="row.status === 'published'"
                type="warning"
                link
                size="small"
                @click="handleStatusAction('pause', row)"
              >
                暂停
              </ElButton>
              <ElButton
                v-if="row.status === 'published' || row.status === 'paused'"
                type="danger"
                link
                size="small"
                @click="handleStatusAction('rollback', row)"
              >
                回滚
              </ElButton>
              <ElButton type="danger" link size="small" @click="handleDelete(row)">删除</ElButton>
            </template>
          </template>
        </ElTableColumn>
      </ElTable>

      <div class="mt-4 flex justify-end">
        <ElPagination
          v-model:current-page="query.page"
          v-model:page-size="query.page_size"
          layout="total, sizes, prev, pager, next"
          :page-sizes="[10, 20, 50, 100]"
          :total="total"
          @change="loadList"
        />
      </div>
    </ElCard>

    <div ref="reportSectionRef" class="mt-4">
      <ElCard shadow="never">
        <template #header>
          <div class="flex items-start justify-between gap-3 max-md:flex-col max-md:items-stretch">
            <div>
              <div class="text-base font-semibold">补丁上报记录</div>
              <div class="mt-1 text-sm text-g-500">
                查看客户端实际命中、安装拉起、安装确认、失败和设备不支持等状态。
              </div>
            </div>
            <div class="flex items-center gap-2">
              <ElButton :loading="reportLoading" @click="loadReports">刷新</ElButton>
              <ElButton @click="resetReportQuery">重置筛选</ElButton>
            </div>
          </div>
        </template>

        <div class="mb-4 flex flex-wrap items-center gap-3">
          <ElInput
            v-model="reportQuery.patch_ref_id"
            placeholder="Patch ID"
            clearable
            style="width: 180px"
          />
          <ElInput
            v-model="reportQuery.keyword"
            placeholder="搜索版本 / 设备 ID / 用户 UUID / IP / 附加信息"
            clearable
            style="width: 320px"
          />
          <ElSelect
            v-model="reportQuery.status"
            clearable
            placeholder="上报状态"
            style="width: 160px"
          >
            <ElOption label="命中补丁" value="check_hit" />
            <ElOption label="用户暂缓" value="deferred" />
            <ElOption label="已拉起安装" value="install_started" />
            <ElOption label="安装已确认" value="install_confirmed" />
            <ElOption label="即时生效" value="apply_success" />
            <ElOption label="安装失败" value="apply_failed" />
            <ElOption label="客户端未接入" value="sdk_not_integrated" />
            <ElOption label="设备不支持" value="sdk_not_available" />
          </ElSelect>
          <ElSelect
            v-model="reportQuery.platform"
            clearable
            placeholder="平台"
            style="width: 130px"
          >
            <ElOption label="Android" value="android" />
            <ElOption label="iOS" value="ios" />
            <ElOption label="全平台" value="all" />
          </ElSelect>
          <ElSelect
            v-model="reportQuery.delivery_mode"
            clearable
            placeholder="投递模式"
            style="width: 150px"
          >
            <ElOption label="自托管整包" value="self_hosted" />
            <ElOption label="Shorebird" value="shorebird" />
          </ElSelect>
          <ElInput
            v-model="reportQuery.channel"
            placeholder="渠道，默认 stable"
            clearable
            style="width: 180px"
          />
          <ElButton type="primary" :loading="reportLoading" @click="loadReports">查询</ElButton>
        </div>

        <ElTable :data="reportList" v-loading="reportLoading" border stripe>
          <ElTableColumn label="上报时间" width="170">
            <template #default="{ row }">
              {{ formatTime(row.created_at) }}
            </template>
          </ElTableColumn>
          <ElTableColumn label="补丁" min-width="220" show-overflow-tooltip>
            <template #default="{ row }">
              <div class="flex flex-col">
                <span class="font-medium">{{ row.patch_ref_id || '-' }}</span>
                <span class="text-xs text-g-500">版本：{{ row.patch_version || '-' }}</span>
              </div>
            </template>
          </ElTableColumn>
          <ElTableColumn label="状态" width="130" align="center">
            <template #default="{ row }">
              <ElTag :type="reportStatusType(row.status)" size="small" effect="light" round>
                {{ reportStatusText(row.status) }}
              </ElTag>
            </template>
          </ElTableColumn>
          <ElTableColumn label="平台 / 渠道" width="140">
            <template #default="{ row }">
              <div>{{ platformText(row.platform) }}</div>
              <div class="text-xs text-g-500">{{ row.channel || 'stable' }}</div>
              <div class="text-xs text-g-500">{{ deliveryModeText(row.delivery_mode) }}</div>
            </template>
          </ElTableColumn>
          <ElTableColumn label="客户端版本" width="170">
            <template #default="{ row }">
              <div>{{ row.app_version || '-' }}</div>
              <div class="text-xs text-g-500">Build {{ row.build_number || '-' }}</div>
            </template>
          </ElTableColumn>
          <ElTableColumn label="设备 / 用户" min-width="260" show-overflow-tooltip>
            <template #default="{ row }">
              <div class="text-xs">设备：{{ row.device_id || '-' }}</div>
              <div class="text-xs text-g-500">用户：{{ row.user_uuid || '-' }}</div>
            </template>
          </ElTableColumn>
          <ElTableColumn prop="client_ip" label="IP" width="140" show-overflow-tooltip />
          <ElTableColumn label="附加信息" min-width="240" show-overflow-tooltip>
            <template #default="{ row }">
              {{ row.message || '-' }}
            </template>
          </ElTableColumn>
        </ElTable>

        <div class="mt-4 flex justify-end">
          <ElPagination
            v-model:current-page="reportQuery.page"
            v-model:page-size="reportQuery.page_size"
            layout="total, sizes, prev, pager, next"
            :page-sizes="[10, 20, 50, 100]"
            :total="reportTotal"
            @change="loadReports"
          />
        </div>
      </ElCard>
    </div>

    <ElDialog
      v-model="dialogVisible"
      :title="editing ? '编辑热更新补丁' : '新建热更新补丁'"
      width="760px"
      destroy-on-close
    >
      <ElForm :model="form" label-width="120px">
        <ElFormItem label="补丁名称" required>
          <ElInput
            v-model="form.name"
            maxlength="120"
            show-word-limit
            placeholder="例如：修复消息已读状态显示"
          />
        </ElFormItem>
        <ElFormItem label="平台" required>
          <ElSelect v-model="form.platform" style="width: 180px">
            <ElOption label="Android" value="android" />
            <ElOption label="iOS" value="ios" />
            <ElOption label="全平台" value="all" />
          </ElSelect>
        </ElFormItem>
        <ElFormItem label="渠道">
          <ElInput v-model="form.channel" maxlength="30" placeholder="默认 stable" />
        </ElFormItem>
        <ElFormItem label="投递模式" required>
          <ElSelect v-model="form.delivery_mode" style="width: 220px">
            <ElOption label="自托管整包" value="self_hosted" />
            <ElOption label="Shorebird 补丁" value="shorebird" />
          </ElSelect>
          <div class="mt-1 text-xs text-g-500">
            自托管整包仅支持单平台；Shorebird 按渠道对应客户端 track。
          </div>
        </ElFormItem>
        <ElFormItem label="补丁版本" required>
          <ElInput v-model="form.patch_version" maxlength="64" placeholder="例如：2026.04.22.1" />
        </ElFormItem>
        <ElFormItem
          :label="isSelfHostedMode ? '补丁地址' : '补丁地址（可空）'"
          :required="isSelfHostedMode"
        >
          <ElInput
            v-model="form.patch_url"
            maxlength="500"
            :placeholder="
              isSelfHostedMode
                ? 'Android: https://cdn.example.com/app-release.apk 或 iOS: https://cdn.example.com/manifest.plist'
                : 'Shorebird 模式下无需填写，客户端会按 channel(track) 检查补丁'
            "
          />
        </ElFormItem>
        <ElFormItem :label="isSelfHostedMode ? '补丁哈希' : '补丁哈希（可空）'">
          <ElInput
            v-model="form.patch_hash"
            maxlength="128"
            :placeholder="isSelfHostedMode ? 'SHA256（必填）' : 'Shorebird 模式下一般留空'"
          />
        </ElFormItem>
        <ElFormItem label="模式说明">
          <ElAlert
            :type="isSelfHostedMode ? 'info' : 'success'"
            :closable="false"
            show-icon
            :title="
              isSelfHostedMode
                ? '自托管整包模式：客户端下载 APK / manifest，并拉起系统安装流程。'
                : 'Shorebird 模式：后台负责灰度命中和开关，客户端按 channel(track) 直接检查并下载补丁。'
            "
          />
        </ElFormItem>
        <ElFormItem label="目标版本">
          <ElInput
            v-model="form.target_app_version"
            maxlength="64"
            placeholder="例如：1.2.0（可选）"
          />
        </ElFormItem>
        <ElFormItem label="生效时间">
          <div class="grid w-full grid-cols-2 gap-3">
            <ElDatePicker
              v-model="form.start_at"
              type="datetime"
              clearable
              placeholder="开始时间（可选）"
              style="width: 100%"
            />
            <ElDatePicker
              v-model="form.end_at"
              type="datetime"
              clearable
              placeholder="结束时间（可选）"
              style="width: 100%"
            />
          </div>
        </ElFormItem>
        <ElFormItem label="App 版本范围">
          <div class="grid w-full grid-cols-2 gap-3">
            <ElInput v-model="form.min_app_version" placeholder="最小版本（可选）" />
            <ElInput v-model="form.max_app_version" placeholder="最大版本（可选）" />
          </div>
        </ElFormItem>
        <ElFormItem label="Build 范围">
          <div class="grid w-full grid-cols-2 gap-3">
            <ElInputNumber
              v-model="form.min_build_number"
              :min="0"
              :max="10000000"
              controls-position="right"
              style="width: 100%"
            />
            <ElInputNumber
              v-model="form.max_build_number"
              :min="0"
              :max="10000000"
              controls-position="right"
              style="width: 100%"
            />
          </div>
        </ElFormItem>
        <ElFormItem label="灰度比例">
          <ElSlider v-model="form.rollout_percentage" :min="0" :max="100" show-input />
        </ElFormItem>
        <ElFormItem label="优先级">
          <ElInputNumber v-model="form.priority" :min="0" :max="1000" controls-position="right" />
        </ElFormItem>
        <ElFormItem label="强制补丁">
          <ElSwitch v-model="form.is_mandatory" />
        </ElFormItem>
        <ElFormItem label="描述">
          <ElInput
            v-model="form.description"
            type="textarea"
            :rows="2"
            maxlength="500"
            show-word-limit
          />
        </ElFormItem>
        <ElFormItem label="发布说明">
          <ElInput
            v-model="form.release_notes"
            type="textarea"
            :rows="4"
            maxlength="2000"
            show-word-limit
          />
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
  import { computed, nextTick, onMounted, reactive, ref } from 'vue'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import { usePermission } from '@/hooks/usePermission'
  import {
    createHotUpdatePatch,
    deleteHotUpdatePatch,
    getHotUpdatePatchReports,
    getHotUpdatePatches,
    pauseHotUpdatePatch,
    publishHotUpdatePatch,
    rollbackHotUpdatePatch,
    updateHotUpdatePatch,
    type HotUpdatePatchDeliveryMode,
    type HotUpdatePatchItem,
    type HotUpdatePatchPayload,
    type HotUpdatePatchReportItem,
    type HotUpdatePatchReportStatus,
    type HotUpdatePatchStatus
  } from '@/api/admin'

  defineOptions({ name: 'SystemHotUpdate' })

  const { isDemoAdmin } = usePermission()

  const loading = ref(false)
  const reportLoading = ref(false)
  const saving = ref(false)
  const dialogVisible = ref(false)
  const list = ref<HotUpdatePatchItem[]>([])
  const reportList = ref<HotUpdatePatchReportItem[]>([])
  const total = ref(0)
  const reportTotal = ref(0)
  const editingRow = ref<HotUpdatePatchItem | null>(null)
  const reportSectionRef = ref<HTMLElement | null>(null)

  const query = reactive({
    page: 1,
    page_size: 20,
    status: '' as HotUpdatePatchStatus | '',
    platform: '' as 'android' | 'ios' | 'all' | '',
    delivery_mode: '' as HotUpdatePatchDeliveryMode | '',
    channel: '',
    keyword: ''
  })

  const reportQuery = reactive({
    page: 1,
    page_size: 20,
    status: '' as HotUpdatePatchReportStatus | '',
    platform: '' as 'android' | 'ios' | 'all' | '',
    delivery_mode: '' as HotUpdatePatchDeliveryMode | '',
    channel: '',
    patch_ref_id: '',
    keyword: ''
  })

  const form = reactive({
    name: '',
    description: '',
    platform: 'android' as 'android' | 'ios' | 'all',
    channel: 'stable',
    delivery_mode: 'self_hosted' as HotUpdatePatchDeliveryMode,
    min_app_version: '',
    max_app_version: '',
    min_build_number: 0,
    max_build_number: 0,
    target_app_version: '',
    start_at: null as Date | null,
    end_at: null as Date | null,
    patch_version: '',
    patch_url: '',
    patch_hash: '',
    release_notes: '',
    rollout_percentage: 100,
    is_mandatory: false,
    priority: 0
  })

  const editing = computed(() => !!editingRow.value)
  const isSelfHostedMode = computed(() => form.delivery_mode === 'self_hosted')
  const sha256HashPattern = /^(sha256:)?[a-f0-9]{64}$/i
  const httpsURLPattern = /^https:\/\/[^@\s/]+\/\S+$/i

  function resetForm() {
    form.name = ''
    form.description = ''
    form.platform = 'android'
    form.channel = 'stable'
    form.delivery_mode = 'self_hosted'
    form.min_app_version = ''
    form.max_app_version = ''
    form.min_build_number = 0
    form.max_build_number = 0
    form.target_app_version = ''
    form.start_at = null
    form.end_at = null
    form.patch_version = ''
    form.patch_url = ''
    form.patch_hash = ''
    form.release_notes = ''
    form.rollout_percentage = 100
    form.is_mandatory = false
    form.priority = 0
  }

  function formatTime(value?: string | null) {
    if (!value) return '-'
    return new Date(value).toLocaleString('zh-CN')
  }

  function formatSchedule(startAt?: string | null, endAt?: string | null) {
    if (!startAt && !endAt) return '不限'
    if (startAt && endAt) {
      return `${formatTime(startAt)} ~ ${formatTime(endAt)}`
    }
    if (startAt) {
      return `${formatTime(startAt)} 开始`
    }
    return `${formatTime(endAt)} 结束`
  }

  function statusText(status: string) {
    switch (status) {
      case 'published':
        return '已发布'
      case 'paused':
        return '已暂停'
      case 'rolled_back':
        return '已回滚'
      default:
        return '草稿'
    }
  }

  function statusType(status: string) {
    switch (status) {
      case 'published':
        return 'success'
      case 'paused':
        return 'warning'
      case 'rolled_back':
        return 'danger'
      default:
        return 'info'
    }
  }

  function platformText(platform: string) {
    switch (platform) {
      case 'android':
        return 'Android'
      case 'ios':
        return 'iOS'
      case 'all':
        return '全平台'
      default:
        return platform || '-'
    }
  }

  function deliveryModeText(mode: string) {
    switch (mode) {
      case 'shorebird':
        return 'Shorebird'
      case 'self_hosted':
      default:
        return '自托管整包'
    }
  }

  function reportStatusText(status: string) {
    switch (status) {
      case 'check_hit':
        return '命中补丁'
      case 'deferred':
        return '用户暂缓'
      case 'install_started':
        return '已拉起安装'
      case 'install_confirmed':
        return '安装已确认'
      case 'apply_success':
        return '即时生效'
      case 'apply_failed':
        return '安装失败'
      case 'sdk_not_integrated':
        return '客户端未接入'
      case 'sdk_not_available':
        return '设备不支持'
      default:
        return status || '-'
    }
  }

  function reportStatusType(status: string) {
    switch (status) {
      case 'install_confirmed':
      case 'apply_success':
        return 'success'
      case 'deferred':
        return 'info'
      case 'install_started':
      case 'check_hit':
        return 'warning'
      case 'apply_failed':
      case 'sdk_not_available':
      case 'sdk_not_integrated':
        return 'danger'
      default:
        return 'info'
    }
  }

  async function loadList() {
    loading.value = true
    try {
      const data = await getHotUpdatePatches({
        page: query.page,
        page_size: query.page_size,
        status: query.status || undefined,
        platform: query.platform || undefined,
        delivery_mode: query.delivery_mode || undefined,
        channel: query.channel.trim() || undefined,
        keyword: query.keyword.trim() || undefined
      })
      list.value = data?.list || []
      total.value = data?.total || 0
    } catch (error) {
      console.error('加载热更新补丁列表失败', error)
      ElMessage.error('加载热更新补丁列表失败')
    } finally {
      loading.value = false
    }
  }

  async function loadReports() {
    reportLoading.value = true
    try {
      const data = await getHotUpdatePatchReports({
        page: reportQuery.page,
        page_size: reportQuery.page_size,
        status: reportQuery.status || undefined,
        platform: reportQuery.platform || undefined,
        delivery_mode: reportQuery.delivery_mode || undefined,
        channel: reportQuery.channel.trim() || undefined,
        patch_ref_id: reportQuery.patch_ref_id.trim() || undefined,
        keyword: reportQuery.keyword.trim() || undefined
      })
      reportList.value = data?.list || []
      reportTotal.value = data?.total || 0
    } catch (error) {
      console.error('加载补丁上报记录失败', error)
      ElMessage.error('加载补丁上报记录失败')
    } finally {
      reportLoading.value = false
    }
  }

  function resetReportQuery() {
    reportQuery.page = 1
    reportQuery.page_size = 20
    reportQuery.status = ''
    reportQuery.platform = ''
    reportQuery.delivery_mode = ''
    reportQuery.channel = ''
    reportQuery.patch_ref_id = ''
    reportQuery.keyword = ''
    loadReports()
  }

  async function focusReportsForPatch(row: HotUpdatePatchItem) {
    reportQuery.patch_ref_id = row.patch_id || ''
    reportQuery.page = 1
    await loadReports()
    await nextTick()
    reportSectionRef.value?.scrollIntoView({ behavior: 'smooth', block: 'start' })
    ElMessage.success(`已筛选补丁 ${row.patch_id} 的上报记录`)
  }

  function openCreate() {
    editingRow.value = null
    resetForm()
    dialogVisible.value = true
  }

  function openEdit(row: HotUpdatePatchItem) {
    editingRow.value = row
    form.name = row.name || ''
    form.description = row.description || ''
    form.platform = row.platform || 'android'
    form.channel = row.channel || 'stable'
    form.delivery_mode = row.delivery_mode || 'self_hosted'
    form.min_app_version = row.min_app_version || ''
    form.max_app_version = row.max_app_version || ''
    form.min_build_number = row.min_build_number || 0
    form.max_build_number = row.max_build_number || 0
    form.target_app_version = row.target_app_version || ''
    form.start_at = row.start_at ? new Date(row.start_at) : null
    form.end_at = row.end_at ? new Date(row.end_at) : null
    form.patch_version = row.patch_version || ''
    form.patch_url = row.patch_url || ''
    form.patch_hash = row.patch_hash || ''
    form.release_notes = row.release_notes || ''
    form.rollout_percentage = row.rollout_percentage ?? 100
    form.is_mandatory = !!row.is_mandatory
    form.priority = row.priority ?? 0
    dialogVisible.value = true
  }

  function buildPayload(): HotUpdatePatchPayload {
    // 自托管整包需要 URL/哈希；Shorebird 模式清空这两个字段，避免旧表单值误参与发布。
    return {
      name: form.name.trim(),
      description: form.description.trim(),
      platform: form.platform,
      channel: form.channel.trim() || 'stable',
      delivery_mode: form.delivery_mode,
      min_app_version: form.min_app_version.trim(),
      max_app_version: form.max_app_version.trim(),
      min_build_number: form.min_build_number || 0,
      max_build_number: form.max_build_number || 0,
      target_app_version: form.target_app_version.trim(),
      start_at: form.start_at ? form.start_at.toISOString() : null,
      end_at: form.end_at ? form.end_at.toISOString() : null,
      patch_version: form.patch_version.trim(),
      patch_url: form.delivery_mode === 'self_hosted' ? form.patch_url.trim() : '',
      patch_hash: form.delivery_mode === 'self_hosted' ? form.patch_hash.trim() : '',
      release_notes: form.release_notes.trim(),
      rollout_percentage: form.rollout_percentage,
      is_mandatory: form.is_mandatory,
      priority: form.priority || 0
    }
  }

  async function handleSave() {
    if (!form.name.trim()) {
      ElMessage.warning('请输入补丁名称')
      return
    }
    if (!form.patch_version.trim()) {
      ElMessage.warning('请输入补丁版本')
      return
    }
    if (form.delivery_mode === 'self_hosted' && form.platform === 'all') {
      ElMessage.warning('自托管整包不支持全平台，请分别创建 Android / iOS 补丁')
      return
    }
    if (form.delivery_mode === 'self_hosted' && !form.patch_url.trim()) {
      ElMessage.warning('请输入补丁地址')
      return
    }
    if (form.delivery_mode === 'self_hosted' && !isValidSelfHostedPatchUrl()) {
      ElMessage.warning(
        '自托管补丁地址必须使用 HTTPS，Android 为 .apk，iOS 为 .plist 或合法 itms-services'
      )
      return
    }
    if (form.delivery_mode === 'self_hosted' && !sha256HashPattern.test(form.patch_hash.trim())) {
      // 哈希在客户端下载后用于完整性校验，支持纯 64 位十六进制或 sha256: 前缀格式。
      ElMessage.warning('自托管整包必须填写 SHA256 补丁哈希')
      return
    }
    if (
      form.min_build_number > 0 &&
      form.max_build_number > 0 &&
      form.min_build_number > form.max_build_number
    ) {
      ElMessage.warning('最小 Build 不能大于最大 Build')
      return
    }
    if (form.start_at && form.end_at && form.start_at.getTime() > form.end_at.getTime()) {
      ElMessage.warning('开始时间不能晚于结束时间')
      return
    }

    saving.value = true
    try {
      const payload = buildPayload()
      if (editingRow.value) {
        await updateHotUpdatePatch(editingRow.value.id, payload)
      } else {
        await createHotUpdatePatch(payload)
      }
      ElMessage.success(editingRow.value ? '更新成功' : '创建成功')
      dialogVisible.value = false
      await loadList()
    } catch (error: any) {
      ElMessage.error(error?.message || '保存失败')
    } finally {
      saving.value = false
    }
  }

  function isValidSelfHostedPatchUrl() {
    const value = form.patch_url.trim()
    if (form.platform === 'android') {
      return httpsURLPattern.test(value) && value.toLowerCase().split('?')[0].endsWith('.apk')
    }
    if (form.platform === 'ios') {
      if (httpsURLPattern.test(value) && value.toLowerCase().split('?')[0].endsWith('.plist')) {
        return true
      }
      if (!value.toLowerCase().startsWith('itms-services://')) {
        return false
      }
      try {
        const parsed = new URL(value)
        if (parsed.searchParams.get('action') !== 'download-manifest') return false
        const embedded = parsed.searchParams.get('url') || ''
        return (
          httpsURLPattern.test(embedded) && embedded.toLowerCase().split('?')[0].endsWith('.plist')
        )
      } catch {
        return false
      }
    }
    return false
  }

  async function handleDelete(row: HotUpdatePatchItem) {
    try {
      await ElMessageBox.confirm(`确认删除补丁“${row.name}”吗？`, '删除确认', {
        type: 'warning'
      })
      await deleteHotUpdatePatch(row.id)
      ElMessage.success('删除成功')
      await loadList()
    } catch {
      // ignore cancel
    }
  }

  async function handleStatusAction(
    action: 'publish' | 'pause' | 'rollback',
    row: HotUpdatePatchItem
  ) {
    // 发布、暂停、回滚是服务端状态机动作，页面不预改状态，成功后重新加载权威列表。
    const textMap = {
      publish: '发布',
      pause: '暂停',
      rollback: '回滚'
    }
    try {
      await ElMessageBox.confirm(`确认${textMap[action]}补丁“${row.name}”吗？`, '操作确认', {
        type: 'warning'
      })
      if (action === 'publish') {
        await publishHotUpdatePatch(row.id)
      } else if (action === 'pause') {
        await pauseHotUpdatePatch(row.id)
      } else {
        await rollbackHotUpdatePatch(row.id)
      }
      ElMessage.success(`${textMap[action]}成功`)
      await loadList()
    } catch {
      // ignore cancel
    }
  }

  onMounted(() => {
    loadList()
    loadReports()
  })
</script>
