<!-- 用户钱包管理页面 -->
<template>
  <div class="user-wallet-page art-full-height">
    <ElCard class="art-table-card" shadow="never">
      <!-- 搜索栏 -->
      <div class="search-bar mb-4 flex items-center gap-4">
        <ElInput
          v-model="searchKeyword"
          placeholder="搜索用户名/昵称"
          clearable
          style="width: 250px"
          @keyup.enter="fetchData"
        >
          <template #prepend>
            <i class="ri-search-line"></i>
          </template>
        </ElInput>
        <ElButton type="primary" @click="fetchData">
          <i class="ri-search-line mr-1"></i>搜索
        </ElButton>
        <ElButton @click="resetSearch"> <i class="ri-refresh-line mr-1"></i>重置 </ElButton>
      </div>

      <!-- 钱包用户列表 -->
      <ElTable :data="list" v-loading="loading" stripe>
        <ElTableColumn type="index" label="序号" width="60" align="center" />
        <ElTableColumn label="用户" min-width="200">
          <template #default="{ row }">
            <div class="flex items-center gap-3">
              <ElAvatar :size="40" :src="fixImageUrl(row.avatar)">
                {{ row.user_name?.charAt(0) }}
              </ElAvatar>
              <div>
                <div class="font-medium">{{ row.user_name }}</div>
                <div class="text-xs text-g-400">@{{ row.username }}</div>
              </div>
            </div>
          </template>
        </ElTableColumn>
        <ElTableColumn label="可用余额" width="140" align="right">
          <template #default="{ row }">
            <span class="text-green-600 font-bold text-lg">¥{{ row.balance.toFixed(2) }}</span>
          </template>
        </ElTableColumn>
        <ElTableColumn label="冻结金额" width="120" align="right">
          <template #default="{ row }">
            <span class="text-orange-500">¥{{ row.frozen_balance.toFixed(2) }}</span>
          </template>
        </ElTableColumn>
        <ElTableColumn label="支付密码" width="100" align="center">
          <template #default="{ row }">
            <ElTag v-if="row.has_pay_password" type="success" size="small">已设置</ElTag>
            <ElTag v-else type="warning" size="small">未设置</ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn label="状态" width="90" align="center">
          <template #default="{ row }">
            <ElTag v-if="row.is_locked" type="danger" size="small">已锁定</ElTag>
            <ElTag v-else type="success" size="small">正常</ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn label="开通时间" width="160">
          <template #default="{ row }">
            {{ formatTime(row.created_at) }}
          </template>
        </ElTableColumn>
        <ElTableColumn label="操作" width="200" fixed="right" align="center">
          <template #default="{ row }">
            <ElButton size="small" type="primary" link @click="showWalletDetail(row)">
              <i class="ri-wallet-line mr-1"></i>管理
            </ElButton>
            <ElButton size="small" type="warning" link @click="showBalanceDialog(row)">
              <i class="ri-subtract-line mr-1"></i>扣减
            </ElButton>
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

    <!-- 钱包详情弹窗 -->
    <ElDialog v-model="detailVisible" title="钱包管理" width="700px">
      <div v-if="currentWallet" class="wallet-detail">
        <!-- 钱包卡片 -->
        <div
          class="wallet-card bg-gradient-to-r from-blue-500 to-purple-600 text-white p-6 rounded-xl mb-6"
        >
          <div class="flex justify-between items-start mb-4">
            <div class="flex items-center gap-3">
              <ElAvatar :size="48" :src="fixImageUrl(currentWallet.avatar)">
                {{ currentWallet.user_name?.charAt(0) }}
              </ElAvatar>
              <div>
                <div class="text-xl font-bold">{{ currentWallet.user_name }}</div>
                <div class="text-sm opacity-70">@{{ currentWallet.username }}</div>
              </div>
            </div>
            <div class="flex items-center gap-2">
              <ElTag v-if="currentWallet.is_locked" type="danger" size="small">已锁定</ElTag>
              <ElTag v-if="currentWallet.has_pay_password" type="success" size="small"
                >已设密码</ElTag
              >
              <ElTag v-else type="warning" size="small">未设密码</ElTag>
            </div>
          </div>
          <div class="grid grid-cols-2 gap-4">
            <div>
              <div class="text-sm opacity-80">可用余额</div>
              <div class="text-3xl font-bold">¥{{ currentWallet.balance.toFixed(2) }}</div>
            </div>
            <div>
              <div class="text-sm opacity-80">冻结金额</div>
              <div class="text-2xl font-bold opacity-80"
                >¥{{ currentWallet.frozen_balance.toFixed(2) }}</div
              >
            </div>
          </div>
        </div>

        <!-- 操作按钮 -->
        <div class="action-buttons mb-6 flex flex-wrap gap-3">
          <ElButton type="warning" @click="showBalanceDialogInner()">
            <i class="ri-subtract-line mr-1"></i>扣减
          </ElButton>
          <ElButton @click="showResetPayPwdDialog">
            <i class="ri-key-line mr-1"></i>重置支付密码
          </ElButton>
          <ElButton @click="handleClearPayPwd">
            <i class="ri-delete-bin-line mr-1"></i>清除支付密码
          </ElButton>
          <ElButton v-if="!currentWallet.is_locked" type="danger" @click="handleLockWallet">
            <i class="ri-lock-line mr-1"></i>锁定钱包
          </ElButton>
          <ElButton v-else type="success" @click="handleUnlockWallet">
            <i class="ri-lock-unlock-line mr-1"></i>解锁钱包
          </ElButton>
        </div>

        <!-- 资金记录 -->
        <div class="transaction-section">
          <div class="flex justify-between items-center mb-4">
            <h3 class="text-lg font-bold">资金记录</h3>
            <ElButton size="small" @click="fetchTransactions">
              <i class="ri-refresh-line mr-1"></i>刷新
            </ElButton>
          </div>
          <ElTable :data="transactions" v-loading="transLoading" stripe max-height="300">
            <ElTableColumn label="类型" width="100" align="center">
              <template #default="{ row }">
                <ElTag :type="getTransTypeColor(row.type)" size="small">
                  {{ getTransTypeText(row.type) }}
                </ElTag>
              </template>
            </ElTableColumn>
            <ElTableColumn label="金额" width="110" align="right">
              <template #default="{ row }">
                <span :class="row.amount > 0 ? 'text-green-600' : 'text-red-500'" class="font-bold">
                  {{ row.amount > 0 ? '+' : '' }}{{ row.amount.toFixed(2) }}
                </span>
              </template>
            </ElTableColumn>
            <ElTableColumn label="余额" width="100" align="right">
              <template #default="{ row }"> ¥{{ row.balance_after.toFixed(2) }} </template>
            </ElTableColumn>
            <ElTableColumn label="备注" min-width="120" show-overflow-tooltip prop="remark" />
            <ElTableColumn label="时间" width="150">
              <template #default="{ row }">
                {{ formatTime(row.created_at) }}
              </template>
            </ElTableColumn>
          </ElTable>
        </div>
      </div>
    </ElDialog>

    <!-- 余额调整弹窗 -->
    <ElDialog v-model="balanceDialogVisible" title="扣减余额" width="400px">
      <ElForm :model="balanceForm" label-width="80px">
        <ElFormItem label="用户">
          <span class="font-medium"
            >{{ balanceTargetUser?.user_name }} (@{{ balanceTargetUser?.username }})</span
          >
        </ElFormItem>
        <ElFormItem label="当前余额">
          <span class="text-green-600 font-bold">¥{{ balanceTargetUser?.balance.toFixed(2) }}</span>
        </ElFormItem>
        <ElFormItem label="金额">
          <ElInputNumber
            v-model="balanceForm.amount"
            :min="0.01"
            :precision="2"
            :step="10"
            style="width: 100%"
          />
        </ElFormItem>
        <ElFormItem label="备注">
          <ElInput v-model="balanceForm.remark" placeholder="操作备注（可选）" />
        </ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="balanceDialogVisible = false">取消</ElButton>
        <ElButton type="primary" @click="handleBalanceSubmit">确定</ElButton>
      </template>
    </ElDialog>

    <!-- 重置支付密码弹窗 -->
    <ElDialog v-model="resetPwdDialogVisible" title="重置支付密码" width="400px">
      <ElForm :model="resetPwdForm" label-width="100px">
        <ElFormItem label="新支付密码">
          <ElInput
            v-model="resetPwdForm.password"
            type="password"
            maxlength="6"
            show-password
            placeholder="请输入6位数字密码"
          />
        </ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="resetPwdDialogVisible = false">取消</ElButton>
        <ElButton type="primary" @click="handleResetPwdSubmit">确定</ElButton>
      </template>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
  import { ref, reactive, onMounted } from 'vue'
  import {
    ElCard,
    ElButton,
    ElInput,
    ElInputNumber,
    ElTag,
    ElAvatar,
    ElTable,
    ElTableColumn,
    ElPagination,
    ElDialog,
    ElForm,
    ElFormItem,
    ElMessageBox,
    ElMessage
  } from 'element-plus'
  import {
    getWalletUserList,
    getUserWallet,
    getUserTransactions,
    updateUserBalance,
    resetUserPayPassword,
    clearUserPayPassword,
    lockUserWallet,
    unlockUserWallet,
    UserWalletInfo,
    UserTransaction
  } from '@/api/admin'
  import { fixImageUrl } from '@/utils/url'

  defineOptions({ name: 'UserWalletList' })

  const loading = ref(false)
  const list = ref<UserWalletInfo[]>([])
  const searchKeyword = ref('')

  const pagination = reactive({
    page: 1,
    page_size: 20,
    total: 0
  })

  // 详情弹窗
  const detailVisible = ref(false)
  const currentWallet = ref<UserWalletInfo | null>(null)
  const transactions = ref<UserTransaction[]>([])
  const transLoading = ref(false)

  // 余额调整
  const balanceDialogVisible = ref(false)
  const balanceTargetUser = ref<UserWalletInfo | null>(null)
  const balanceForm = reactive({
    amount: 100,
    remark: ''
  })

  // 重置密码
  const resetPwdDialogVisible = ref(false)
  const resetPwdForm = reactive({
    password: ''
  })

  const getTransTypeColor = (type: string) => {
    const colors: Record<string, string> = {
      recharge: 'success',
      withdraw: 'warning',
      red_packet_send: 'danger',
      red_packet_receive: 'success',
      transfer_out: 'danger',
      transfer_in: 'success',
      refund: 'info',
      admin_recharge: 'primary',
      admin_deduct: 'danger'
    }
    return colors[type] || 'info'
  }

  const getTransTypeText = (type: string) => {
    const texts: Record<string, string> = {
      recharge: '充值',
      withdraw: '提现',
      red_packet_send: '发红包',
      red_packet_receive: '收红包',
      transfer_out: '转出',
      transfer_in: '收款',
      refund: '退款',
      admin_recharge: '后台充值',
      admin_deduct: '后台扣减'
    }
    return texts[type] || type
  }

  const formatTime = (time: string) => {
    if (!time) return '-'
    return new Date(time).toLocaleString('zh-CN')
  }

  const fetchData = async () => {
    loading.value = true
    try {
      const res = await getWalletUserList({
        page: pagination.page,
        page_size: pagination.page_size,
        keyword: searchKeyword.value || undefined
      })
      list.value = res.list || []
      pagination.total = res.total || 0
    } catch (e) {
      console.error('获取钱包列表失败', e)
    } finally {
      loading.value = false
    }
  }

  const resetSearch = () => {
    searchKeyword.value = ''
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

  const showWalletDetail = async (row: UserWalletInfo) => {
    currentWallet.value = row
    detailVisible.value = true
    fetchTransactions()
  }

  const fetchTransactions = async () => {
    if (!currentWallet.value) return
    transLoading.value = true
    try {
      const res = await getUserTransactions(currentWallet.value.user_id, {
        page: 1,
        page_size: 50
      })
      transactions.value = res.list || []
    } catch (e) {
      console.error('获取资金记录失败', e)
    } finally {
      transLoading.value = false
    }
  }

  const showBalanceDialog = (row: UserWalletInfo) => {
    balanceTargetUser.value = row
    balanceForm.amount = 100
    balanceForm.remark = ''
    balanceDialogVisible.value = true
  }

  const showBalanceDialogInner = () => {
    if (currentWallet.value) {
      showBalanceDialog(currentWallet.value)
    }
  }

  const handleBalanceSubmit = async () => {
    if (!balanceTargetUser.value) return
    const amount = -balanceForm.amount
    try {
      await updateUserBalance(balanceTargetUser.value.user_id, amount, balanceForm.remark)
      ElMessage.success('操作成功')
      balanceDialogVisible.value = false
      fetchData()
      // 如果详情弹窗打开，刷新当前钱包数据
      if (detailVisible.value && currentWallet.value) {
        const res = await getUserWallet(currentWallet.value.user_id)
        currentWallet.value = res
        fetchTransactions()
      }
    } catch (e: any) {
      ElMessage.error(e.message || '操作失败')
    }
  }

  const showResetPayPwdDialog = () => {
    resetPwdForm.password = ''
    resetPwdDialogVisible.value = true
  }

  const handleResetPwdSubmit = async () => {
    if (!currentWallet.value) return
    if (!/^\d{6}$/.test(resetPwdForm.password)) {
      ElMessage.warning('请输入6位数字密码')
      return
    }
    try {
      await resetUserPayPassword(currentWallet.value.user_id, resetPwdForm.password)
      ElMessage.success('重置成功')
      resetPwdDialogVisible.value = false
      const res = await getUserWallet(currentWallet.value.user_id)
      currentWallet.value = res
      fetchData()
    } catch (e: any) {
      ElMessage.error(e.message || '操作失败')
    }
  }

  const handleClearPayPwd = async () => {
    if (!currentWallet.value) return
    try {
      await ElMessageBox.confirm('确定要清除该用户的支付密码吗？', '清除支付密码', {
        type: 'warning'
      })
      await clearUserPayPassword(currentWallet.value.user_id)
      ElMessage.success('清除成功')
      const res = await getUserWallet(currentWallet.value.user_id)
      currentWallet.value = res
      fetchData()
    } catch (e: any) {
      if (e !== 'cancel') {
        ElMessage.error(e.message || '操作失败')
      }
    }
  }

  const handleLockWallet = async () => {
    if (!currentWallet.value) return
    try {
      await ElMessageBox.confirm('确定要锁定该用户的钱包吗？锁定后无法进行任何交易。', '锁定钱包', {
        type: 'warning'
      })
      await lockUserWallet(currentWallet.value.user_id)
      ElMessage.success('锁定成功')
      const res = await getUserWallet(currentWallet.value.user_id)
      currentWallet.value = res
      fetchData()
    } catch (e: any) {
      if (e !== 'cancel') {
        ElMessage.error(e.message || '操作失败')
      }
    }
  }

  const handleUnlockWallet = async () => {
    if (!currentWallet.value) return
    try {
      await unlockUserWallet(currentWallet.value.user_id)
      ElMessage.success('解锁成功')
      const res = await getUserWallet(currentWallet.value.user_id)
      currentWallet.value = res
      fetchData()
    } catch (e: any) {
      ElMessage.error(e.message || '操作失败')
    }
  }

  onMounted(() => {
    fetchData()
  })
</script>

<style scoped lang="scss">
  .wallet-card {
    box-shadow: 0 10px 40px rgba(0, 0, 0, 0.15);
  }
</style>
