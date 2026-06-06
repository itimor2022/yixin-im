<!-- 签到记录页面 -->
<template>
  <div class="checkin-page art-full-height">
    <ElCard class="art-table-card" shadow="never">
      <div class="mb-4 flex items-center gap-3">
        <ElInput
          v-model="searchForm.keyword"
          placeholder="用户名 / 昵称"
          clearable
          style="width: 220px"
          @keyup.enter="handleSearch"
        />
        <ElDatePicker
          v-model="searchForm.date"
          type="date"
          value-format="YYYY-MM-DD"
          placeholder="选择日期"
          clearable
        />
        <ElButton type="primary" :loading="loading" @click="handleSearch">查询</ElButton>
        <ElButton @click="handleReset">重置</ElButton>
        <span class="text-g-500 ml-auto">
          共 <span class="text-primary font-bold">{{ total }}</span> 条记录
        </span>
      </div>

      <ElTable v-loading="loading" :data="records" border>
        <ElTableColumn label="用户" min-width="200">
          <template #default="{ row }">
            <div class="flex items-center gap-2">
              <ElAvatar :src="row.avatar" :size="32">
                {{ (row.nickname || row.username || '?').charAt(0) }}
              </ElAvatar>
              <div>
                <div class="font-medium">{{ row.nickname || row.username }}</div>
                <div class="text-xs text-g-400">{{ row.username }}</div>
              </div>
            </div>
          </template>
        </ElTableColumn>
        <ElTableColumn label="UUID" prop="uuid" min-width="240" show-overflow-tooltip />
        <ElTableColumn label="签到日期" prop="checkinDate" width="140">
          <template #default="{ row }">{{ formatDate(row.checkinDate) }}</template>
        </ElTableColumn>
        <ElTableColumn label="签到时间" prop="createdAt" width="180">
          <template #default="{ row }">{{ formatTime(row.createdAt) }}</template>
        </ElTableColumn>
      </ElTable>

      <div class="mt-4 flex justify-end">
        <ElPagination
          v-model:current-page="pagination.current"
          v-model:page-size="pagination.size"
          :total="total"
          :page-sizes="[20, 50, 100]"
          layout="total, sizes, prev, pager, next, jumper"
          @size-change="loadData"
          @current-change="loadData"
        />
      </div>
    </ElCard>
  </div>
</template>

<script setup lang="ts">
  import { onMounted, reactive, ref } from 'vue'
  import { fetchGetCheckinList, CheckinTableListItem } from '@/api/system-manage'

  const loading = ref(false)
  const records = ref<CheckinTableListItem[]>([])
  const total = ref(0)

  const searchForm = reactive({
    keyword: '',
    date: ''
  })

  const pagination = reactive({
    current: 1,
    size: 20
  })

  const formatDate = (v: string) => (v ? v.slice(0, 10) : '-')
  const formatTime = (v: string) => (v ? v.replace('T', ' ').slice(0, 19) : '-')

  const loadData = async () => {
    loading.value = true
    try {
      const res = await fetchGetCheckinList({
        current: pagination.current,
        size: pagination.size,
        keyword: searchForm.keyword || undefined,
        date: searchForm.date || undefined
      })
      records.value = res.records
      total.value = res.total
    } catch (e) {
      console.error('加载签到记录失败:', e)
    } finally {
      loading.value = false
    }
  }

  const handleSearch = () => {
    pagination.current = 1
    loadData()
  }

  const handleReset = () => {
    searchForm.keyword = ''
    searchForm.date = ''
    pagination.current = 1
    loadData()
  }

  onMounted(loadData)
</script>
