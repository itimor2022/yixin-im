<template>
  <div class="recharge-manage">
    <el-tabs v-model="activeTab">
      <!-- Tab 1: 充值方式管理 -->
      <el-tab-pane label="充值方式" name="methods">
        <div style="margin-bottom: 12px; display: flex; justify-content: flex-end">
          <el-button type="primary" @click="showMethodDialog()">添加充值方式</el-button>
        </div>
        <el-table :data="methods" v-loading="methodsLoading" stripe>
          <el-table-column prop="name" label="名称" width="120" />
          <el-table-column label="类型" width="100">
            <template #default="{ row }">
              <el-tag
                :type="row.type === 'qrcode' ? 'success' : row.type === 'bank' ? '' : 'warning'"
                size="small"
              >
                {{ { qrcode: '二维码', bank: '银行卡', manual: '人工' }[row.type] || row.type }}
              </el-tag>
            </template>
          </el-table-column>
          <el-table-column label="限额" width="160">
            <template #default="{ row }">¥{{ row.min_amount }} - ¥{{ row.max_amount }}</template>
          </el-table-column>
          <el-table-column label="状态" width="80">
            <template #default="{ row }">
              <el-tag :type="row.status === 1 ? 'success' : 'info'" size="small">{{
                row.status === 1 ? '启用' : '禁用'
              }}</el-tag>
            </template>
          </el-table-column>
          <el-table-column prop="sort" label="排序" width="60" />
          <el-table-column prop="remark" label="说明" min-width="150" show-overflow-tooltip />
          <el-table-column label="操作" width="130" fixed="right">
            <template #default="{ row }">
              <el-button size="small" type="primary" link @click="showMethodDialog(row)"
                >编辑</el-button
              >
              <el-popconfirm title="确定删除？" @confirm="handleDeleteMethod(row.id)">
                <template #reference
                  ><el-button size="small" type="danger" link>删除</el-button></template
                >
              </el-popconfirm>
            </template>
          </el-table-column>
        </el-table>
      </el-tab-pane>

      <!-- Tab 2: 充值审核 -->
      <el-tab-pane label="充值审核" name="orders">
        <div style="margin-bottom: 12px; display: flex; gap: 12px; align-items: center">
          <el-select
            v-model="orderFilter.status"
            clearable
            placeholder="全部状态"
            style="width: 140px"
            @change="fetchOrders"
          >
            <el-option label="待审核" value="pending" />
            <el-option label="已通过" value="approved" />
            <el-option label="已拒绝" value="rejected" />
          </el-select>
        </div>
        <el-table :data="orders" v-loading="ordersLoading" stripe>
          <el-table-column prop="id" label="ID" width="60" />
          <el-table-column label="用户" width="150">
            <template #default="{ row }">
              <div style="display: flex; align-items: center; gap: 6px">
                <el-avatar :size="28" :src="fixImageUrl(row.avatar)" />
                <span>{{ row.user_name }}</span>
              </div>
            </template>
          </el-table-column>
          <el-table-column label="金额" width="100">
            <template #default="{ row }"
              ><span style="font-weight: 600; color: #67c23a"
                >¥{{ row.amount?.toFixed(2) }}</span
              ></template
            >
          </el-table-column>
          <el-table-column prop="method_name" label="方式" width="100" />
          <el-table-column label="凭证" width="80">
            <template #default="{ row }">
              <el-image
                v-if="row.proof_image"
                :src="fixImageUrl(row.proof_image)"
                :preview-src-list="[fixImageUrl(row.proof_image)]"
                preview-teleported
                :z-index="3000"
                style="width: 40px; height: 40px; cursor: pointer; border-radius: 4px"
                fit="cover"
              />
              <span v-else style="color: #ccc">无</span>
            </template>
          </el-table-column>
          <el-table-column label="状态" width="80">
            <template #default="{ row }">
              <el-tag
                :type="{ pending: 'warning', approved: 'success', rejected: 'danger' }[row.status]"
                size="small"
              >
                {{
                  { pending: '待审核', approved: '已通过', rejected: '已拒绝' }[row.status] ||
                  row.status
                }}
              </el-tag>
            </template>
          </el-table-column>
          <el-table-column prop="remark" label="备注" min-width="120" show-overflow-tooltip />
          <el-table-column label="时间" width="155">
            <template #default="{ row }">{{
              row.created_at?.replace('T', ' ')?.substring(0, 19)
            }}</template>
          </el-table-column>
          <el-table-column label="操作" width="160" fixed="right">
            <template #default="{ row }">
              <template v-if="row.status === 'pending'">
                <el-button size="small" type="success" link @click="handleReview(row, 'approve')"
                  >通过</el-button
                >
                <el-button size="small" type="danger" link @click="handleReview(row, 'reject')"
                  >拒绝</el-button
                >
              </template>
              <span v-else style="color: #999; font-size: 12px">已处理</span>
            </template>
          </el-table-column>
        </el-table>
        <div style="display: flex; justify-content: flex-end; margin-top: 12px">
          <el-pagination
            v-model:current-page="orderPagination.page"
            v-model:page-size="orderPagination.pageSize"
            :total="orderPagination.total"
            :page-sizes="[20, 50]"
            layout="total,sizes,prev,pager,next"
            @size-change="fetchOrders"
            @current-change="fetchOrders"
          />
        </div>
      </el-tab-pane>
    </el-tabs>

    <!-- 充值方式编辑弹窗 -->
    <el-dialog
      v-model="methodDialogVisible"
      :title="editingMethod ? '编辑充值方式' : '添加充值方式'"
      width="500px"
    >
      <el-form :model="methodForm" label-width="100px">
        <el-form-item label="名称" required
          ><el-input v-model="methodForm.name" placeholder="支付宝/微信/银行卡"
        /></el-form-item>
        <el-form-item label="类型" required>
          <el-select v-model="methodForm.type" style="width: 100%">
            <el-option label="二维码" value="qrcode" /><el-option
              label="银行卡"
              value="bank"
            /><el-option label="人工" value="manual" />
          </el-select>
        </el-form-item>
        <el-form-item label="二维码" v-if="methodForm.type === 'qrcode'"
          ><el-input v-model="methodForm.qrcode_url" placeholder="二维码图片URL"
        /></el-form-item>
        <el-form-item label="账户信息" v-if="methodForm.type === 'bank'"
          ><el-input
            v-model="methodForm.account_info"
            type="textarea"
            :rows="3"
            placeholder='{"bank":"中国银行","account":"6222***","name":"张三"}'
        /></el-form-item>
        <el-form-item label="最小金额"
          ><el-input-number v-model="methodForm.min_amount" :min="0"
        /></el-form-item>
        <el-form-item label="最大金额"
          ><el-input-number v-model="methodForm.max_amount" :min="1"
        /></el-form-item>
        <el-form-item label="说明"
          ><el-input v-model="methodForm.remark" type="textarea" :rows="2"
        /></el-form-item>
        <el-form-item label="排序"
          ><el-input-number v-model="methodForm.sort" :min="0"
        /></el-form-item>
        <el-form-item label="状态">
          <el-switch
            v-model="methodForm.status"
            :active-value="1"
            :inactive-value="0"
            active-text="启用"
            inactive-text="禁用"
          />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="methodDialogVisible = false">取消</el-button>
        <el-button type="primary" @click="handleSaveMethod" :loading="methodSaving">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
  import { ref, reactive, onMounted } from 'vue'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import {
    getRechargeMethods,
    createRechargeMethod,
    updateRechargeMethod,
    deleteRechargeMethod,
    getRechargeOrders,
    reviewRechargeOrder,
    type RechargeMethodInfo,
    type RechargeOrderInfo
  } from '@/api/admin'
  import { fixImageUrl } from '@/utils/url'

  defineOptions({ name: 'RechargeManage' })

  const activeTab = ref('methods')

  // 充值方式
  const methods = ref<RechargeMethodInfo[]>([])
  const methodsLoading = ref(false)
  const methodDialogVisible = ref(false)
  const editingMethod = ref<RechargeMethodInfo | null>(null)
  const methodSaving = ref(false)
  const methodForm = reactive<Partial<RechargeMethodInfo>>({
    name: '',
    type: 'qrcode',
    qrcode_url: '',
    account_info: '',
    min_amount: 10,
    max_amount: 50000,
    remark: '',
    status: 1,
    sort: 0
  })

  const fetchMethods = async () => {
    methodsLoading.value = true
    try {
      methods.value = ((await getRechargeMethods()) as any) || []
    } catch {
      /* */
    } finally {
      methodsLoading.value = false
    }
  }

  const showMethodDialog = (row?: RechargeMethodInfo) => {
    editingMethod.value = row || null
    if (row) {
      Object.assign(methodForm, row)
    } else {
      Object.assign(methodForm, {
        name: '',
        type: 'qrcode',
        qrcode_url: '',
        account_info: '',
        min_amount: 10,
        max_amount: 50000,
        remark: '',
        status: 1,
        sort: 0
      })
    }
    methodDialogVisible.value = true
  }

  const handleSaveMethod = async () => {
    if (!methodForm.name) {
      ElMessage.warning('请输入名称')
      return
    }
    methodSaving.value = true
    try {
      if (editingMethod.value) {
        await updateRechargeMethod(editingMethod.value.id, methodForm)
      } else {
        await createRechargeMethod(methodForm)
      }
      ElMessage.success('保存成功')
      methodDialogVisible.value = false
      fetchMethods()
    } catch {
      ElMessage.error('保存失败')
    } finally {
      methodSaving.value = false
    }
  }

  const handleDeleteMethod = async (id: number) => {
    try {
      await deleteRechargeMethod(id)
      ElMessage.success('删除成功')
      fetchMethods()
    } catch {
      ElMessage.error('删除失败')
    }
  }

  // 充值审核
  const orders = ref<RechargeOrderInfo[]>([])
  const ordersLoading = ref(false)
  const orderFilter = reactive({ status: '' })
  const orderPagination = reactive({ page: 1, pageSize: 20, total: 0 })

  const fetchOrders = async () => {
    ordersLoading.value = true
    try {
      const res = (await getRechargeOrders({
        page: orderPagination.page,
        page_size: orderPagination.pageSize,
        status: orderFilter.status || undefined
      })) as any
      orders.value = res?.list || []
      orderPagination.total = res?.total || 0
    } catch {
      /* */
    } finally {
      ordersLoading.value = false
    }
  }

  const handleReview = async (row: RechargeOrderInfo, action: string) => {
    const text = action === 'approve' ? '通过' : '拒绝'
    try {
      const { value: remark } = await ElMessageBox.prompt(`确认${text}该充值申请？`, '审核', {
        inputPlaceholder: '备注（选填）',
        confirmButtonText: text,
        cancelButtonText: '取消',
        type: action === 'reject' ? 'warning' : 'info'
      })
      await reviewRechargeOrder(row.id, action, remark)
      ElMessage.success(`${text}成功`)
      fetchOrders()
    } catch (e: any) {
      if (e !== 'cancel') ElMessage.error(e?.message || `${text}失败`)
    }
  }

  onMounted(() => {
    fetchMethods()
    fetchOrders()
  })
</script>
