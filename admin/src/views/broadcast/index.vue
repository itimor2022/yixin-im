<script setup lang="ts">
  import { ref, onMounted } from 'vue'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import { sendBroadcast, listBroadcasts, clearBroadcasts, type BroadcastItem } from '@/api/admin'

  defineOptions({ name: 'Broadcast' })

  const form = ref({ title: '', content: '', type: 'info' })
  const sending = ref(false)
  const loading = ref(false)
  const clearing = ref(false)
  const history = ref<BroadcastItem[]>([])
  const page = ref(1)
  const pageSize = 20
  const total = ref(0)

  const typeOptions = [
    { label: '通知', value: 'info' },
    { label: '警告', value: 'warning' },
    { label: '紧急', value: 'urgent' },
    { label: '系统维护', value: 'maintenance' }
  ]

  function formatTime(dateStr: string) {
    if (!dateStr) return ''
    return new Date(dateStr).toLocaleString('zh-CN')
  }

  async function loadHistory() {
    loading.value = true
    try {
      const res = await listBroadcasts({ page: page.value, page_size: pageSize })
      history.value = (res as any)?.list || []
      total.value = (res as any)?.total || 0
    } catch {
      ElMessage.error('加载失败')
    }
    loading.value = false
  }

  async function handleSend() {
    if (!form.value.title.trim()) {
      ElMessage.warning('请输入公告标题')
      return
    }
    if (!form.value.content.trim()) {
      ElMessage.warning('请输入公告内容')
      return
    }
    await ElMessageBox.confirm('确定发送公告给所有在线用户？', '确认发送', { type: 'warning' })
    sending.value = true
    try {
      const res = (await sendBroadcast(form.value)) as any
      ElMessage.success(`公告发送成功，已推送给 ${res?.online_count ?? 0} 位在线用户`)
      form.value = { title: '', content: '', type: 'info' }
      page.value = 1
      await loadHistory()
    } catch (error) {
      console.error('Failed to send broadcast:', error)
      ElMessage.error('发送公告失败')
    }
    sending.value = false
  }

  async function handleClear() {
    await ElMessageBox.confirm('确定清空所有公告记录？此操作不可恢复。', '确认清空', {
      type: 'warning'
    })
    clearing.value = true
    try {
      const res = (await clearBroadcasts()) as any
      ElMessage.success(`已清空 ${res?.deleted_count ?? 0} 条公告记录`)
      history.value = []
      total.value = 0
    } catch (error) {
      console.error('Failed to clear broadcast history:', error)
      ElMessage.error('清空记录失败')
    }
    clearing.value = false
  }

  onMounted(loadHistory)
</script>

<template>
  <div class="broadcast-page">
    <!-- 发送公告 -->
    <ElCard class="mb-4">
      <template #header>
        <div style="display: flex; align-items: center; gap: 8px">
          <i class="ri:megaphone-line" style="font-size: 18px; color: #409eff" />
          <span style="font-weight: 600">发送全局公告</span>
        </div>
      </template>
      <ElAlert
        type="info"
        :closable="false"
        show-icon
        class="mb-4"
        description="公告将通过 WebSocket 实时推送给所有在线用户，请谨慎使用。"
      />
      <ElForm :model="form" label-width="100px" style="max-width: 600px">
        <ElFormItem label="公告标题">
          <ElInput v-model="form.title" placeholder="请输入公告标题" />
        </ElFormItem>
        <ElFormItem label="公告类型">
          <ElSelect v-model="form.type" style="width: 180px">
            <ElOption v-for="o in typeOptions" :key="o.value" :label="o.label" :value="o.value" />
          </ElSelect>
        </ElFormItem>
        <ElFormItem label="公告内容">
          <ElInput v-model="form.content" type="textarea" :rows="6" placeholder="请输入公告内容" />
        </ElFormItem>
        <ElFormItem>
          <ElButton type="primary" :loading="sending" @click="handleSend">发送公告</ElButton>
        </ElFormItem>
      </ElForm>
    </ElCard>

    <!-- 发送记录 -->
    <ElCard v-loading="loading">
      <template #header>
        <div style="display: flex; justify-content: space-between; align-items: center">
          <span style="font-weight: 600">发送记录</span>
          <ElButton
            v-if="history.length"
            type="danger"
            size="small"
            :loading="clearing"
            @click="handleClear"
          >
            清空记录
          </ElButton>
        </div>
      </template>
      <ElEmpty v-if="!loading && !history.length" description="暂无发送记录" />
      <ElTimeline v-else>
        <ElTimelineItem
          v-for="item in history"
          :key="item.id"
          :timestamp="formatTime(item.created_at)"
          placement="top"
          type="primary"
        >
          <ElCard shadow="never" style="border-left: 3px solid #409eff">
            <div style="font-weight: 600; margin-bottom: 6px">{{ item.title }}</div>
            <div style="color: #666; white-space: pre-wrap">{{ item.content }}</div>
            <div style="margin-top: 8px; display: flex; gap: 8px; align-items: center">
              <ElTag size="small">{{
                typeOptions.find((t) => t.value === item.type)?.label || item.type
              }}</ElTag>
              <ElTag size="small" type="success" v-if="(item as any).online_count != null">
                已推送 {{ (item as any).online_count }} 人
              </ElTag>
              <span v-if="(item as any).admin_name" style="font-size: 12px; color: #999">
                {{ (item as any).admin_name }}
              </span>
            </div>
          </ElCard>
        </ElTimelineItem>
      </ElTimeline>
      <div v-if="total > pageSize" style="display: flex; justify-content: center; margin-top: 16px">
        <ElPagination
          :current-page="page"
          :page-size="pageSize"
          :total="total"
          layout="prev,pager,next"
          @current-change="
            (p: number) => {
              page = p
              loadHistory()
            }
          "
        />
      </div>
    </ElCard>
  </div>
</template>
