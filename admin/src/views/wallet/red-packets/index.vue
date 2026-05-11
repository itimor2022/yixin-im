<!-- 红包记录管理页面 -->
<template>
  <div class="red-packet-page art-full-height">
    <!-- 统计卡片 -->
    <el-row :gutter="16" class="mb-4">
      <el-col :span="6">
        <el-card shadow="never" class="stat-card">
          <div class="stat-val">{{ stats?.red_packet_count || 0 }}</div>
          <div class="stat-label">红包总数</div>
        </el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="never" class="stat-card">
          <div class="stat-val text-red-500">¥{{ (stats?.red_packet_amount || 0).toFixed(2) }}</div>
          <div class="stat-label">红包总金额</div>
        </el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="never" class="stat-card">
          <div class="stat-val">{{ stats?.transfer_count || 0 }}</div>
          <div class="stat-label">转账总数</div>
        </el-card>
      </el-col>
      <el-col :span="6">
        <el-card shadow="never" class="stat-card">
          <div class="stat-val text-green-500">¥{{ (stats?.total_balance || 0).toFixed(2) }}</div>
          <div class="stat-label">钱包总余额</div>
        </el-card>
      </el-col>
    </el-row>

    <el-card class="art-table-card" shadow="never">
      <!-- 搜索栏 -->
      <div class="search-bar mb-4 flex items-center gap-4">
        <el-select
          v-model="searchParams.status"
          placeholder="红包状态"
          clearable
          style="width: 150px"
        >
          <el-option label="全部状态" value="" />
          <el-option label="进行中" value="active" />
          <el-option label="已领完" value="finished" />
          <el-option label="已过期" value="expired" />
        </el-select>
        <el-input
          v-model="searchParams.user_id"
          placeholder="发送者ID"
          clearable
          style="width: 200px"
        />
        <el-button type="primary" @click="fetchData">搜索</el-button>
        <el-button @click="resetSearch">重置</el-button>
      </div>

      <!-- 表格 -->
      <el-table :data="list" v-loading="loading" stripe>
        <el-table-column type="index" label="#" width="50" align="center" />
        <el-table-column label="发送者" min-width="160">
          <template #default="{ row }">
            <div class="flex items-center gap-2">
              <el-avatar :size="32" :src="fixImageUrl(row.sender_avatar)">{{
                row.sender_name?.charAt(0)
              }}</el-avatar>
              <span class="font-medium">{{ row.sender_name }}</span>
            </div>
          </template>
        </el-table-column>
        <el-table-column label="类型" width="80" align="center">
          <template #default="{ row }">
            <el-tag :type="row.type === 'lucky' ? 'warning' : ''" size="small" round>
              {{ row.type === 'lucky' ? '拼手气' : '普通' }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="金额" width="100" align="right">
          <template #default="{ row }">
            <span style="color: #e84c3d; font-weight: 600"
              >¥{{ row.total_amount?.toFixed(2) }}</span
            >
          </template>
        </el-table-column>
        <el-table-column label="领取" width="80" align="center">
          <template #default="{ row }">{{ row.claim_count || 0 }}/{{ row.total_count }}</template>
        </el-table-column>
        <el-table-column label="剩余" width="90" align="right">
          <template #default="{ row }">
            <span style="color: #e6a23c">¥{{ row.remaining_amount?.toFixed(2) }}</span>
          </template>
        </el-table-column>
        <el-table-column label="祝福语" min-width="140" show-overflow-tooltip prop="message" />
        <el-table-column label="状态" width="80" align="center">
          <template #default="{ row }">
            <el-tag :type="statusType(row.status)" size="small">{{
              statusText(row.status)
            }}</el-tag>
          </template>
        </el-table-column>
        <el-table-column label="时间" width="155">
          <template #default="{ row }">{{ fmtTime(row.created_at) }}</template>
        </el-table-column>
        <el-table-column label="操作" width="130" fixed="right" align="center">
          <template #default="{ row }">
            <el-button size="small" type="primary" link @click="showDetail(row)">详情</el-button>
            <el-button
              v-if="row.status === 'active' && row.remaining_amount > 0"
              size="small"
              type="warning"
              link
              @click="handleRefund(row)"
              >退回</el-button
            >
          </template>
        </el-table-column>
      </el-table>

      <div class="mt-4 flex justify-end">
        <el-pagination
          v-model:current-page="pagination.page"
          v-model:page-size="pagination.page_size"
          :total="pagination.total"
          :page-sizes="[20, 50, 100]"
          layout="total, sizes, prev, pager, next"
          @size-change="
            (s) => {
              pagination.page_size = s
              pagination.page = 1
              fetchData()
            }
          "
          @current-change="fetchData"
        />
      </div>
    </el-card>

    <!-- 详情弹窗 — 简约风 -->
    <el-dialog v-model="detailVisible" title="红包详情" width="480px" :close-on-click-modal="true">
      <template v-if="currentDetail">
        <!-- 发送者 + 金额 -->
        <div class="detail-top">
          <el-avatar :size="44" :src="fixImageUrl(currentDetail.sender_avatar)">{{
            currentDetail.sender_name?.charAt(0)
          }}</el-avatar>
          <div class="detail-top-info">
            <div class="detail-top-name">{{ currentDetail.sender_name }}</div>
            <div class="detail-top-msg">{{ currentDetail.message || '恭喜发财，大吉大利' }}</div>
          </div>
          <div class="detail-top-amount">¥{{ currentDetail.total_amount?.toFixed(2) }}</div>
        </div>

        <el-divider style="margin: 16px 0" />

        <!-- 信息行 -->
        <div class="detail-rows">
          <div class="detail-row"
            ><span class="detail-row-label">类型</span
            ><span
              >{{ currentDetail.type === 'lucky' ? '拼手气红包' : '普通红包' }} ·
              {{ currentDetail.total_count }}个</span
            ></div
          >
          <div class="detail-row"
            ><span class="detail-row-label">状态</span
            ><el-tag :type="statusType(currentDetail.status)" size="small">{{
              statusText(currentDetail.status)
            }}</el-tag></div
          >
          <div class="detail-row"
            ><span class="detail-row-label">已领</span
            ><span
              >{{ currentDetail.claims?.length || 0 }} / {{ currentDetail.total_count }} 个</span
            ></div
          >
          <div class="detail-row"
            ><span class="detail-row-label">剩余</span
            ><span style="color: #e6a23c; font-weight: 500"
              >¥{{ currentDetail.remaining_amount?.toFixed(2) }}</span
            ></div
          >
          <div class="detail-row"
            ><span class="detail-row-label">过期</span
            ><span>{{ fmtTime(currentDetail.expired_at) }}</span></div
          >
          <div class="detail-row"
            ><span class="detail-row-label">发送</span
            ><span>{{ fmtTime(currentDetail.created_at) }}</span></div
          >
        </div>

        <!-- 领取记录 -->
        <template v-if="currentDetail.claims?.length">
          <el-divider style="margin: 16px 0" />
          <div class="detail-section-title">领取记录</div>
          <div class="claim-list">
            <div v-for="(c, i) in currentDetail.claims" :key="i" class="claim-item">
              <el-avatar :size="28" :src="fixImageUrl(c.user_avatar)">{{
                c.user_name?.charAt(0)
              }}</el-avatar>
              <div class="claim-item-info">
                <span class="claim-item-name">{{ c.user_name }}</span>
                <el-tag v-if="c.is_best" type="warning" size="small" round style="margin-left: 4px"
                  >最佳</el-tag
                >
              </div>
              <span class="claim-item-amount">¥{{ c.amount?.toFixed(2) }}</span>
            </div>
          </div>
        </template>
        <div v-else style="text-align: center; color: #999; padding: 20px 0; font-size: 13px"
          >暂无领取记录</div
        >
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
  import { ref, reactive, onMounted } from 'vue'
  import { ElMessageBox, ElMessage } from 'element-plus'
  import {
    getWalletStats,
    getRedPacketList,
    getRedPacketDetail,
    refundRedPacket,
    type WalletStats,
    type RedPacketRecord,
    type RedPacketDetail
  } from '@/api/admin'
  import { fixImageUrl } from '@/utils/url'

  defineOptions({ name: 'RedPacketList' })

  const loading = ref(false)
  const stats = ref<WalletStats | null>(null)
  const list = ref<RedPacketRecord[]>([])
  const detailVisible = ref(false)
  const currentDetail = ref<RedPacketDetail | null>(null)
  const searchParams = reactive({ status: '', user_id: '' })
  const pagination = reactive({ page: 1, page_size: 20, total: 0 })

  const statusType = (s: string) =>
    ({ active: 'success', finished: 'info', expired: 'warning' })[s] || 'info'
  const statusText = (s: string) =>
    ({ active: '进行中', finished: '已领完', expired: '已过期' })[s] || s
  const fmtTime = (t: string) => (t ? new Date(t).toLocaleString('zh-CN') : '-')

  const fetchStats = async () => {
    try {
      stats.value = (await getWalletStats()) as any
    } catch {
      /* */
    }
  }
  const fetchData = async () => {
    loading.value = true
    try {
      const res = await getRedPacketList({
        page: pagination.page,
        page_size: pagination.page_size,
        ...searchParams
      })
      list.value = res.list || []
      pagination.total = res.total || 0
    } catch {
      /* */
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
  const showDetail = async (row: RedPacketRecord) => {
    try {
      currentDetail.value = (await getRedPacketDetail(row.id)) as any
      detailVisible.value = true
    } catch {
      ElMessage.error('获取详情失败')
    }
  }
  const handleRefund = async (row: RedPacketRecord) => {
    try {
      await ElMessageBox.confirm(
        `确定退回剩余 ¥${row.remaining_amount?.toFixed(2)} 给发送者？`,
        '退回红包',
        { type: 'warning' }
      )
      await refundRedPacket(row.id)
      ElMessage.success('退回成功')
      fetchData()
      fetchStats()
    } catch (e: any) {
      if (e !== 'cancel') ElMessage.error(e?.message || '操作失败')
    }
  }
  onMounted(() => {
    fetchStats()
    fetchData()
  })
</script>

<style scoped>
  .stat-card {
    text-align: center;
  }
  .stat-card :deep(.el-card__body) {
    padding: 16px;
  }
  .stat-val {
    font-size: 24px;
    font-weight: 700;
    line-height: 1.2;
  }
  .stat-label {
    font-size: 12px;
    color: #999;
    margin-top: 4px;
  }

  /* 详情弹窗 */
  .detail-top {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .detail-top-info {
    flex: 1;
  }
  .detail-top-name {
    font-size: 15px;
    font-weight: 600;
  }
  .detail-top-msg {
    font-size: 12px;
    color: #999;
    margin-top: 2px;
  }
  .detail-top-amount {
    font-size: 22px;
    font-weight: 700;
    color: #e84c3d;
  }

  .detail-rows {
    display: flex;
    flex-direction: column;
    gap: 0;
  }
  .detail-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 8px 0;
    border-bottom: 1px solid #f5f5f5;
    font-size: 13px;
  }
  .detail-row:last-child {
    border-bottom: none;
  }
  .detail-row-label {
    color: #999;
    min-width: 50px;
  }

  .detail-section-title {
    font-size: 13px;
    font-weight: 600;
    margin-bottom: 8px;
  }
  .claim-list {
    max-height: 240px;
    overflow-y: auto;
  }
  .claim-item {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 0;
    border-bottom: 1px solid #f9f9f9;
  }
  .claim-item:last-child {
    border-bottom: none;
  }
  .claim-item-info {
    flex: 1;
    display: flex;
    align-items: center;
    font-size: 13px;
  }
  .claim-item-name {
    font-weight: 500;
  }
  .claim-item-amount {
    font-size: 14px;
    font-weight: 600;
    color: #e84c3d;
  }
</style>
