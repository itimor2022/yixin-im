<!-- 转账记录管理页面 -->
<template>
  <div class="transfer-page art-full-height">
    <ElCard class="art-table-card" shadow="never">
      <!-- 搜索栏 -->
      <div class="search-bar mb-4 flex items-center gap-4">
        <ElSelect
          v-model="searchParams.status"
          placeholder="转账状态"
          clearable
          style="width: 150px"
        >
          <ElOption label="全部状态" value="" />
          <ElOption label="待接收" value="pending" />
          <ElOption label="已接收" value="accepted" />
          <ElOption label="已退回" value="rejected" />
          <ElOption label="已过期" value="expired" />
        </ElSelect>
        <ElInput
          v-model="searchParams.user_id"
          placeholder="用户ID（发送者/接收者）"
          clearable
          style="width: 220px"
        />
        <ElButton type="primary" @click="fetchData">
          <i class="ri-search-line mr-1"></i>搜索
        </ElButton>
        <ElButton @click="resetSearch"> <i class="ri-refresh-line mr-1"></i>重置 </ElButton>
      </div>

      <!-- 表格 -->
      <ElTable :data="list" v-loading="loading" stripe>
        <ElTableColumn type="index" label="序号" width="60" align="center" />
        <ElTableColumn label="发送者" min-width="180">
          <template #default="{ row }">
            <div class="flex items-center gap-2">
              <ElAvatar :size="36" :src="fixImageUrl(row.sender_avatar)">
                {{ row.sender_name?.charAt(0) }}
              </ElAvatar>
              <div>
                <div class="font-medium">{{ row.sender_name }}</div>
                <div class="text-xs text-g-400">{{ row.sender_id }}</div>
              </div>
            </div>
          </template>
        </ElTableColumn>
        <ElTableColumn label="" width="60" align="center">
          <template #default>
            <i class="ri-arrow-right-line text-g-400 text-lg"></i>
          </template>
        </ElTableColumn>
        <ElTableColumn label="接收者" min-width="180">
          <template #default="{ row }">
            <div class="flex items-center gap-2">
              <ElAvatar :size="36" :src="fixImageUrl(row.receiver_avatar)">
                {{ row.receiver_name?.charAt(0) }}
              </ElAvatar>
              <div>
                <div class="font-medium">{{ row.receiver_name }}</div>
                <div class="text-xs text-g-400">{{ row.receiver_id }}</div>
              </div>
            </div>
          </template>
        </ElTableColumn>
        <ElTableColumn label="金额" width="120" align="right">
          <template #default="{ row }">
            <span class="text-green-600 font-bold text-lg">¥{{ row.amount.toFixed(2) }}</span>
          </template>
        </ElTableColumn>
        <ElTableColumn label="备注" min-width="150" show-overflow-tooltip>
          <template #default="{ row }">
            {{ row.remark || '-' }}
          </template>
        </ElTableColumn>
        <ElTableColumn label="状态" width="100" align="center">
          <template #default="{ row }">
            <ElTag :type="getStatusType(row.status)" size="small">
              {{ getStatusText(row.status) }}
            </ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn label="发送时间" width="160">
          <template #default="{ row }">
            {{ formatTime(row.created_at) }}
          </template>
        </ElTableColumn>
        <ElTableColumn label="接收时间" width="160">
          <template #default="{ row }">
            {{ row.accepted_at ? formatTime(row.accepted_at) : '-' }}
          </template>
        </ElTableColumn>
        <ElTableColumn label="操作" width="120" fixed="right" align="center">
          <template #default="{ row }">
            <ElButton
              v-if="row.status === 'pending'"
              size="small"
              type="warning"
              link
              @click="handleRefund(row)"
            >
              <i class="ri-refund-line mr-1"></i>退回
            </ElButton>
            <span v-else class="text-g-400 text-sm">-</span>
          </template>
        </ElTableColumn>
      </ElTable>

      <!-- 分页 -->
      <div class="pagination-wrapper mt-4 flex justify-end">
        <ElPagination
          v-model:current-page="pagination.page"
          v-model:page-size="pagination.page_size"
          :total="pagination.total"
          :page-sizes="[10, 20, 50, 100]"
          layout="total, sizes, prev, pager, next, jumper"
          @size-change="handleSizeChange"
          @current-change="handlePageChange"
        />
      </div>
    </ElCard>
  </div>
</template>

<script setup lang="ts">
  import { ref, reactive, onMounted } from 'vue'
  import {
    ElCard,
    ElTable,
    ElTableColumn,
    ElButton,
    ElTag,
    ElAvatar,
    ElPagination,
    ElInput,
    ElSelect,
    ElOption,
    ElMessageBox,
    ElMessage
  } from 'element-plus'
  import { getTransferList, refundTransfer, TransferRecord } from '@/api/admin'
  import { fixImageUrl } from '@/utils/url'

  defineOptions({ name: 'TransferList' })

  const loading = ref(false)
  const list = ref<TransferRecord[]>([])

  const searchParams = reactive({
    status: '',
    user_id: ''
  })

  const pagination = reactive({
    page: 1,
    page_size: 20,
    total: 0
  })

  const getStatusType = (status: string) => {
    switch (status) {
      case 'pending':
        return 'warning'
      case 'accepted':
        return 'success'
      case 'rejected':
        return 'info'
      case 'expired':
        return 'danger'
      default:
        return 'info'
    }
  }

  const getStatusText = (status: string) => {
    switch (status) {
      case 'pending':
        return '待接收'
      case 'accepted':
        return '已接收'
      case 'rejected':
        return '已退回'
      case 'expired':
        return '已过期'
      default:
        return status
    }
  }

  const formatTime = (time: string) => {
    if (!time) return '-'
    return new Date(time).toLocaleString('zh-CN')
  }

  const fetchData = async () => {
    loading.value = true
    try {
      // total 与当前筛选条件共享同一口径，页码和每页数量由本地分页状态传入。
      const res = await getTransferList({
        page: pagination.page,
        page_size: pagination.page_size,
        ...searchParams
      })
      list.value = res.list || []
      pagination.total = res.total || 0
    } catch (e) {
      console.error('获取转账列表失败', e)
    } finally {
      loading.value = false
    }
  }

  const resetSearch = () => {
    searchParams.status = ''
    searchParams.user_id = ''
    pagination.page = 1
    fetchData()
  }

  const handleSizeChange = (size: number) => {
    pagination.page_size = size
    pagination.page = 1
    fetchData()
  }

  const handlePageChange = (page: number) => {
    pagination.page = page
    fetchData()
  }

  const handleRefund = async (row: TransferRecord) => {
    try {
      await ElMessageBox.confirm(
        `确定要将转账 ¥${row.amount.toFixed(2)} 退回给发送者 ${row.sender_name} 吗？`,
        '退回转账',
        { type: 'warning' }
      )
      await refundTransfer(row.id)
      ElMessage.success('退回成功')
      // 退回会改变当前记录状态，服务端确认后重新读取本页。
      fetchData()
    } catch (e: any) {
      if (e !== 'cancel') {
        ElMessage.error(e.message || '操作失败')
      }
    }
  }

  onMounted(() => {
    fetchData()
  })
</script>

<style scoped lang="scss"></style>
