<template>
  <div class="checkin-page">
    <el-card>
      <template #header>
        <div class="card-header">
          <span>签到记录</span>
        </div>
      </template>

      <!-- 搜索栏 -->
      <el-form :inline="true" :model="query" class="search-form">
        <el-form-item label="用户ID">
          <el-input v-model="query.user_id" placeholder="请输入用户ID" clearable />
        </el-form-item>
        <el-form-item label="日期">
          <el-date-picker
            v-model="query.date"
            type="date"
            placeholder="选择日期"
            format="YYYY-MM-DD"
            value-format="YYYY-MM-DD"
            clearable
          />
        </el-form-item>
        <el-form-item>
          <el-button type="primary" @click="loadData">查询</el-button>
          <el-button @click="resetQuery">重置</el-button>
        </el-form-item>
      </el-form>

      <!-- 表格 -->
      <el-table :data="list" border stripe v-loading="loading">
        <el-table-column prop="id" label="ID" width="80" />
        <el-table-column prop="user_id" label="用户ID" width="100" />
        <el-table-column prop="username" label="用户名" />
        <el-table-column prop="checkin_at" label="签到时间" width="180">
          <template #default="{ row }">
            {{ formatDate(row.checkin_at) }}
          </template>
        </el-table-column>
        <el-table-column prop="continuous_days" label="连续天数" width="100">
          <template #default="{ row }">
            <el-tag type="success">{{ row.continuous_days ?? '-' }} 天</el-tag>
          </template>
        </el-table-column>
      </el-table>

      <!-- 分页 -->
      <div class="pagination">
        <el-pagination
          v-model:current-page="query.page"
          v-model:page-size="query.page_size"
          :total="total"
          :page-sizes="[20, 50, 100]"
          layout="total, sizes, prev, pager, next"
          @change="loadData"
        />
      </div>
    </el-card>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { getAdminCheckinList } from '@/api/admin'

const loading = ref(false)
const list = ref<any[]>([])
const total = ref(0)

const query = ref({
  page: 1,
  page_size: 20,
  user_id: '',
  date: ''
})

async function loadData() {
  loading.value = true
  try {
    const params: any = {
      page: query.value.page,
      page_size: query.value.page_size
    }
    if (query.value.user_id) params.user_id = query.value.user_id
    if (query.value.date) params.date = query.value.date

    const res = await getAdminCheckinList(params)
    list.value = (res as any)?.records ?? []
    total.value = (res as any)?.total ?? 0
  } catch (e) {
    console.error(e)
  } finally {
    loading.value = false
  }
}

function resetQuery() {
  query.value = { page: 1, page_size: 20, user_id: '', date: '' }
  loadData()
}

function formatDate(val: string) {
  if (!val) return '-'
  return new Date(val).toLocaleString('zh-CN')
}

onMounted(loadData)
</script>

<style scoped>
.checkin-page { padding: 16px; }
.search-form { margin-bottom: 16px; }
.pagination { margin-top: 16px; display: flex; justify-content: flex-end; }
</style>
