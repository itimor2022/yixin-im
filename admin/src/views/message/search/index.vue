<script setup lang="ts">
  import { ref, onMounted, watch } from 'vue'
  import { useRoute, useRouter } from 'vue-router'
  import { searchMessages } from '@/api/admin'
  import { fixImageUrl } from '@/utils/url'

  defineOptions({ name: 'MessageSearch' })

  const route = useRoute()
  const router = useRouter()

  const loading = ref(false)
  const list = ref<any[]>([])
  const page = ref(1)
  const pageSize = 20
  const total = ref(0)
  const keyword = ref('')
  const chatId = ref('')
  const senderId = ref('')
  const msgType = ref('')
  const dateRange = ref<[Date, Date] | null>(null)
  const targetName = ref('')

  const typeOptions = [
    { label: '文本', value: '1' },
    { label: '图片', value: '2' },
    { label: '视频', value: '3' },
    { label: '语音', value: '4' },
    { label: '文件', value: '5' },
    { label: '系统', value: '10' }
  ]

  const typeMap: Record<
    number,
    { label: string; type: 'success' | 'info' | 'warning' | 'danger' }
  > = {
    1: { label: '文本', type: 'success' },
    2: { label: '图片', type: 'info' },
    3: { label: '视频', type: 'warning' },
    4: { label: '语音', type: 'info' },
    5: { label: '文件', type: 'warning' },
    10: { label: '系统', type: 'danger' }
  }

  function formatDate(d: Date) {
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  }

  function getMsgPreview(row: any) {
    const c = row.content
    const text = typeof c === 'object' && c !== null ? c.text || '' : typeof c === 'string' ? c : ''
    return (
      text ||
      (row.type === 2
        ? '[图片]'
        : row.type === 3
          ? '[视频]'
          : row.type === 4
            ? '[语音]'
            : row.type === 5
              ? '[文件]'
              : row.type === 10
                ? '[系统]'
                : '[消息]')
    )
  }

  async function loadData() {
    loading.value = true
    try {
      const params: any = { page: page.value, page_size: pageSize }
      if (keyword.value) params.keyword = keyword.value
      if (chatId.value) params.chat_id = chatId.value
      if (senderId.value) params.sender_id = senderId.value
      if (msgType.value) params.type = msgType.value
      if (dateRange.value) {
        params.start_date = formatDate(dateRange.value[0])
        params.end_date = formatDate(dateRange.value[1])
      }
      const res = (await searchMessages(params)) as any
      list.value = res?.list || []
      total.value = res?.total || 0
    } catch (error) {
      console.error('Failed to search messages:', error)
    }
    loading.value = false
  }

  function handleSearch() {
    page.value = 1
    loadData()
  }

  function clearTarget() {
    chatId.value = ''
    senderId.value = ''
    targetName.value = ''
    router.replace({ query: {} })
    page.value = 1
    loadData()
  }

  function applyQueryParams() {
    const q = route.query
    chatId.value = q.chat_id ? String(q.chat_id) : ''
    senderId.value = q.sender_id ? String(q.sender_id) : ''
    targetName.value = q.name ? String(q.name) : ''
    page.value = 1
    loadData()
  }

  watch(() => route.query, applyQueryParams)
  onMounted(applyQueryParams)
</script>

<template>
  <ElCard>
    <template #header>
      <div style="display: flex; flex-wrap: wrap; gap: 8px; align-items: center">
        <ElAlert
          v-if="targetName"
          type="info"
          :closable="false"
          style="padding: 4px 12px; flex: none"
        >
          {{ targetName }} 的聊天记录
        </ElAlert>
        <ElInput
          v-model="keyword"
          placeholder="搜索消息内容"
          clearable
          style="width: 200px"
          @keyup.enter="handleSearch"
        />
        <ElInput v-model="chatId" placeholder="会话ID" clearable style="width: 160px" />
        <ElInput v-model="senderId" placeholder="发送者ID" clearable style="width: 160px" />
        <ElSelect v-model="msgType" placeholder="消息类型" clearable style="width: 120px">
          <ElOption v-for="o in typeOptions" :key="o.value" :label="o.label" :value="o.value" />
        </ElSelect>
        <ElDatePicker
          v-model="dateRange"
          type="daterange"
          range-separator="至"
          start-placeholder="开始日期"
          end-placeholder="结束日期"
          style="width: 260px"
          value-format="YYYY-MM-DD"
        />
        <ElButton type="primary" @click="handleSearch">搜索</ElButton>
        <ElButton v-if="targetName" @click="clearTarget">清除筛选</ElButton>
      </div>
    </template>

    <ElTable :data="list" v-loading="loading" stripe size="small">
      <ElTableColumn label="发送者" width="150">
        <template #default="{ row }">
          <div style="display: flex; align-items: center; gap: 8px">
            <ElAvatar :size="28" :src="fixImageUrl(row.sender_avatar)" />
            <span>{{ row.sender_name || row.sender_id }}</span>
          </div>
        </template>
      </ElTableColumn>
      <ElTableColumn label="类型" width="70">
        <template #default="{ row }">
          <ElTag :type="typeMap[row.type]?.type || 'info'" size="small">
            {{ typeMap[row.type]?.label || '未知' }}
          </ElTag>
        </template>
      </ElTableColumn>
      <ElTableColumn label="内容" min-width="260">
        <template #default="{ row }">
          <div
            style="max-width: 250px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap"
          >
            {{ getMsgPreview(row) }}
          </div>
        </template>
      </ElTableColumn>
      <ElTableColumn prop="chat_id" label="会话ID" width="140" show-overflow-tooltip />
      <ElTableColumn prop="created_at" label="发送时间" width="170" />
    </ElTable>

    <div style="display: flex; justify-content: flex-end; margin-top: 16px">
      <ElPagination
        :current-page="page"
        :page-size="pageSize"
        :total="total"
        layout="total,prev,pager,next"
        @current-change="
          (p: number) => {
            page = p
            loadData()
          }
        "
      />
    </div>
  </ElCard>
</template>
