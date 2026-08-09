<template>
  <div class="wallet-settings">
    <el-tabs v-model="activeTab" type="border-card">
      <!-- Tab 1: 基础设置 -->
      <el-tab-pane label="基础设置" name="basic">
        <el-form
          :model="form"
          label-width="140px"
          v-loading="loading"
          style="max-width: 640px; padding: 16px 0"
        >
          <el-divider content-position="left">货币设置</el-divider>
          <el-form-item label="货币符号"
            ><el-input v-model="form.wallet_currency" placeholder="¥" style="width: 100px"
          /></el-form-item>
          <el-form-item label="货币名称"
            ><el-input
              v-model="form.wallet_currency_name"
              placeholder="人民币"
              style="width: 200px"
          /></el-form-item>
          <el-divider content-position="left">过期时间</el-divider>
          <el-form-item label="红包过期时间"
            ><el-input-number
              v-model.number="form.red_packet_expire_hours"
              :min="1"
              :max="168"
            /><span style="margin-left: 8px; color: #999">小时</span></el-form-item
          >
          <el-form-item label="转账过期时间"
            ><el-input-number
              v-model.number="form.transfer_expire_hours"
              :min="1"
              :max="168"
            /><span style="margin-left: 8px; color: #999">小时</span></el-form-item
          >
          <template v-if="false">
            <el-divider content-position="left">充值设置</el-divider>
            <el-form-item label="充值审核模式"
              ><el-radio-group v-model="form.recharge_review"
                ><el-radio value="0">自动到账</el-radio
                ><el-radio value="1">人工审核</el-radio></el-radio-group
              ></el-form-item
            >
            <el-form-item label="充值公告"
              ><el-input
                v-model="form.recharge_notice"
                type="textarea"
                :rows="3"
                placeholder="充值页面显示的公告"
            /></el-form-item>
          </template>
          <el-divider content-position="left">公告设置</el-divider>
          <el-form-item label="钱包公告"
            ><el-input
              v-model="form.wallet_notice"
              type="textarea"
              :rows="3"
              placeholder="钱包首页显示的公告"
          /></el-form-item>
          <el-form-item label="提现公告"
            ><el-input
              v-model="form.withdraw_notice"
              type="textarea"
              :rows="3"
              placeholder="提现页面显示的公告"
          /></el-form-item>
          <el-form-item
            ><el-button type="primary" @click="handleSave" :loading="saving"
              >保存设置</el-button
            ></el-form-item
          >
        </el-form>
      </el-tab-pane>

      <!-- Tab 2: 充值方式 -->
      <el-tab-pane v-if="false" label="充值方式" name="recharge">
        <div style="padding: 12px 0">
          <div
            style="
              display: flex;
              justify-content: space-between;
              align-items: center;
              margin-bottom: 16px;
            "
          >
            <span style="color: #666; font-size: 13px">管理 App 充值页面的收款方式</span>
            <el-button type="primary" size="small" @click="showRechargeDialog()"
              >添加充值方式</el-button
            >
          </div>
          <el-table :data="rechargeMethods" v-loading="rechargeLoading" stripe size="small">
            <el-table-column prop="name" label="名称" width="120" />
            <el-table-column label="类型" width="90"
              ><template #default="{ row }"
                ><el-tag size="small">{{ rechargeMethodTypeText(row.type) }}</el-tag></template
              ></el-table-column
            >
            <el-table-column label="收款账号" min-width="200" show-overflow-tooltip
              ><template #default="{ row }">{{
                row.account_info || row.qrcode_url || '-'
              }}</template></el-table-column
            >
            <el-table-column label="限额" width="150"
              ><template #default="{ row }"
                >¥{{ row.min_amount }} - ¥{{ row.max_amount }}</template
              ></el-table-column
            >
            <el-table-column label="状态" width="70"
              ><template #default="{ row }"
                ><el-tag :type="row.status === 1 ? 'success' : 'info'" size="small">{{
                  row.status === 1 ? '启用' : '禁用'
                }}</el-tag></template
              ></el-table-column
            >
            <el-table-column label="操作" width="120">
              <template #default="{ row }">
                <el-button size="small" type="primary" link @click="showRechargeDialog(row)"
                  >编辑</el-button
                >
                <el-popconfirm title="确定删除？" @confirm="delRechargeMethod(row.id)"
                  ><template #reference
                    ><el-button size="small" type="danger" link>删除</el-button></template
                  ></el-popconfirm
                >
              </template>
            </el-table-column>
          </el-table>
        </div>
      </el-tab-pane>

      <!-- Tab 3: 提现方式 -->
      <el-tab-pane label="提现方式" name="withdraw">
        <div style="padding: 12px 0">
          <div
            style="
              display: flex;
              justify-content: space-between;
              align-items: center;
              margin-bottom: 16px;
            "
          >
            <span style="color: #666; font-size: 13px">管理 App 提现页面的提现方式</span>
            <el-button type="primary" size="small" @click="showWithdrawDialog()"
              >添加提现方式</el-button
            >
          </div>
          <el-table :data="withdrawMethods" v-loading="withdrawLoading" stripe size="small">
            <el-table-column prop="name" label="名称" width="120" />
            <el-table-column label="收款字段" min-width="200"
              ><template #default="{ row }">{{
                parseFieldNames(row.fields)
              }}</template></el-table-column
            >
            <el-table-column label="手续费" width="80"
              ><template #default="{ row }">{{ row.fee }}%</template></el-table-column
            >
            <el-table-column label="限额" width="150"
              ><template #default="{ row }"
                >¥{{ row.min_amount }} - ¥{{ row.max_amount }}</template
              ></el-table-column
            >
            <el-table-column label="状态" width="70"
              ><template #default="{ row }"
                ><el-tag :type="row.status === 1 ? 'success' : 'info'" size="small">{{
                  row.status === 1 ? '启用' : '禁用'
                }}</el-tag></template
              ></el-table-column
            >
            <el-table-column label="操作" width="120">
              <template #default="{ row }">
                <el-button size="small" type="primary" link @click="showWithdrawDialog(row)"
                  >编辑</el-button
                >
                <el-popconfirm title="确定删除？" @confirm="delWithdrawMethod(row.id)"
                  ><template #reference
                    ><el-button size="small" type="danger" link>删除</el-button></template
                  ></el-popconfirm
                >
              </template>
            </el-table-column>
          </el-table>
        </div>
      </el-tab-pane>
    </el-tabs>

    <!-- 充值方式弹窗 -->
    <el-dialog
      v-if="false"
      v-model="rechargeDialogVisible"
      :title="editRecharge ? '编辑充值方式' : '添加充值方式'"
      width="540px"
      destroy-on-close
    >
      <el-form :model="rechargeForm" label-width="100px">
        <el-form-item label="名称" required
          ><el-input v-model="rechargeForm.name" placeholder="支付宝 / 微信 / 银行卡 / USDT"
        /></el-form-item>
        <el-form-item label="类型" required>
          <el-radio-group v-model="rechargeForm.type">
            <el-radio-button value="qrcode">二维码</el-radio-button>
            <el-radio-button value="bank">银行卡/USDT</el-radio-button>
            <el-radio-button value="manual">人工</el-radio-button>
          </el-radio-group>
        </el-form-item>

        <!-- 二维码：图片上传 -->
        <el-form-item label="收款二维码" v-if="rechargeForm.type === 'qrcode'">
          <div style="display: flex; gap: 12px; align-items: flex-start">
            <el-upload
              :action="uploadUrl"
              :headers="uploadHeaders"
              :show-file-list="false"
              :on-success="(res: any) => (rechargeForm.qrcode_url = res.data?.url || res.url || '')"
              accept="image/*"
            >
              <div
                v-if="rechargeForm.qrcode_url"
                style="
                  width: 120px;
                  height: 120px;
                  border: 1px solid #eee;
                  border-radius: 8px;
                  overflow: hidden;
                  cursor: pointer;
                "
              >
                <img
                  :src="fixImageUrl(rechargeForm.qrcode_url)"
                  style="width: 100%; height: 100%; object-fit: contain"
                />
              </div>
              <div
                v-else
                style="
                  width: 120px;
                  height: 120px;
                  border: 1px dashed #ccc;
                  border-radius: 8px;
                  display: flex;
                  flex-direction: column;
                  align-items: center;
                  justify-content: center;
                  cursor: pointer;
                  color: #999;
                "
              >
                <el-icon :size="24"><Plus /></el-icon>
                <span style="font-size: 12px; margin-top: 4px">上传二维码</span>
              </div>
            </el-upload>
            <div style="flex: 1"
              ><el-input
                v-model="rechargeForm.qrcode_url"
                placeholder="或直接输入图片URL"
                size="small"
            /></div>
          </div>
        </el-form-item>

        <!-- 银行卡/USDT：结构化账户信息 -->
        <template v-if="rechargeForm.type === 'bank'">
          <el-divider content-position="left" style="margin: 12px 0"
            >收款信息（用户可复制）</el-divider
          >
          <div
            v-for="(item, idx) in accountFields"
            :key="idx"
            style="display: flex; gap: 8px; margin-bottom: 8px; align-items: center"
          >
            <el-input
              v-model="item.label"
              placeholder="标签（如：开户银行）"
              style="width: 120px"
              size="small"
            />
            <el-input
              v-model="item.value"
              placeholder="内容（如：中国银行）"
              style="flex: 1"
              size="small"
            />
            <el-button
              :icon="Delete"
              circle
              size="small"
              type="danger"
              plain
              @click="accountFields.splice(idx, 1)"
            />
          </div>
          <el-button
            size="small"
            type="primary"
            plain
            @click="accountFields.push({ label: '', value: '' })"
            >+ 添加字段</el-button
          >
        </template>

        <el-form-item label="最小金额" style="margin-top: 16px"
          ><el-input-number v-model="rechargeForm.min_amount" :min="0"
        /></el-form-item>
        <el-form-item label="最大金额"
          ><el-input-number v-model="rechargeForm.max_amount" :min="1"
        /></el-form-item>
        <el-form-item label="说明"
          ><el-input v-model="rechargeForm.remark" placeholder="显示在充值方式下方的提示"
        /></el-form-item>
        <el-form-item label="排序"
          ><el-input-number v-model="rechargeForm.sort" :min="0"
        /></el-form-item>
        <el-form-item label="状态"
          ><el-switch v-model="rechargeForm.status" :active-value="1" :inactive-value="0"
        /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="rechargeDialogVisible = false">取消</el-button>
        <el-button type="primary" @click="saveRechargeMethod" :loading="rechargeSaving"
          >保存</el-button
        >
      </template>
    </el-dialog>

    <!-- 提现方式弹窗 — 可视化字段配置 -->
    <el-dialog
      v-model="withdrawDialogVisible"
      :title="editWithdraw ? '编辑提现方式' : '添加提现方式'"
      width="560px"
      destroy-on-close
    >
      <el-form :model="withdrawForm" label-width="100px">
        <el-form-item label="名称" required
          ><el-input v-model="withdrawForm.name" placeholder="支付宝 / 微信 / 银行卡"
        /></el-form-item>
        <el-divider content-position="left" style="margin: 12px 0">用户需填写的收款信息</el-divider>
        <div
          v-for="(field, idx) in withdrawFields"
          :key="idx"
          style="display: flex; gap: 6px; margin-bottom: 10px; align-items: center"
        >
          <el-input v-model="field.label" placeholder="字段名" style="width: 100px" size="small" />
          <el-input v-model="field.hint" placeholder="输入提示" style="flex: 1" size="small" />
          <el-select v-model="field.type" style="width: 90px" size="small">
            <el-option label="文本" value="text" /><el-option
              label="手机号"
              value="phone"
            /><el-option label="数字" value="number" /><el-option label="银行卡" value="bankCard" />
          </el-select>
          <el-button
            :icon="Delete"
            circle
            size="small"
            type="danger"
            plain
            @click="withdrawFields.splice(idx, 1)"
          />
        </div>
        <el-button
          size="small"
          type="primary"
          plain
          @click="
            withdrawFields.push({
              key: 'field_' + Date.now(),
              label: '',
              hint: '',
              type: 'text',
              required: true
            })
          "
          >+ 添加字段</el-button
        >

        <el-divider style="margin: 16px 0" />
        <el-form-item label="手续费"
          ><el-input-number v-model="withdrawForm.fee" :min="0" :max="100" :precision="2" /><span
            style="margin-left: 8px; color: #999"
            >%</span
          ></el-form-item
        >
        <el-form-item label="最小金额"
          ><el-input-number v-model="withdrawForm.min_amount" :min="0"
        /></el-form-item>
        <el-form-item label="最大金额"
          ><el-input-number v-model="withdrawForm.max_amount" :min="1"
        /></el-form-item>
        <el-form-item label="排序"
          ><el-input-number v-model="withdrawForm.sort" :min="0"
        /></el-form-item>
        <el-form-item label="状态"
          ><el-switch v-model="withdrawForm.status" :active-value="1" :inactive-value="0"
        /></el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="withdrawDialogVisible = false">取消</el-button>
        <el-button type="primary" @click="saveWithdrawMethod" :loading="withdrawSaving"
          >保存</el-button
        >
      </template>
    </el-dialog>
  </div>
</template>

<script setup lang="ts">
  import { ref, reactive, onMounted, computed } from 'vue'
  import { ElMessage } from 'element-plus'
  import { Delete, Plus } from '@element-plus/icons-vue'
  import {
    getWalletSettings,
    saveWalletSettings,
    getRechargeMethods,
    createRechargeMethod,
    updateRechargeMethod,
    deleteRechargeMethod,
    getWithdrawMethods,
    createWithdrawMethod,
    updateWithdrawMethod,
    deleteWithdrawMethod,
    type RechargeMethodInfo,
    type WithdrawMethodInfo
  } from '@/api/admin'
  import { fixImageUrl } from '@/utils/url'
  import { useUserStore } from '@/store/modules/user'

  defineOptions({ name: 'WalletSettings' })

  const activeTab = ref('basic')
  const userStore = useUserStore()

  const rechargeMethodTypeText = (type: string) => {
    const texts: Record<string, string> = {
      qrcode: '\u4e8c\u7ef4\u7801',
      bank: '\u94f6\u884c\u5361/USDT',
      manual: '\u4eba\u5de5'
    }
    return texts[type] || type
  }

  // 上传配置 — 与 API 基地址统一
  const uploadUrl = `${(import.meta.env.VITE_API_URL || '/api/v1').replace(/\/$/, '')}/admin/upload/image`
  const uploadHeaders = computed(() => {
    return { Authorization: `Bearer ${userStore.accessToken}` }
  })

  // ===== 基础设置 =====
  const loading = ref(false)
  const saving = ref(false)
  const form = reactive({
    wallet_currency: '¥',
    wallet_currency_name: '人民币',
    red_packet_expire_hours: '24',
    transfer_expire_hours: '24',
    recharge_review: '0',
    wallet_notice: '',
    recharge_notice: '',
    withdraw_notice: ''
  })
  const fetchSettings = async () => {
    loading.value = true
    try {
      const res = (await getWalletSettings()) as any
      // 仅回填当前表单声明的键，忽略设置接口中属于其他模块的字段。
      if (res)
        Object.keys(form).forEach((k) => {
          if (res[k] !== undefined) (form as any)[k] = res[k]
        })
    } catch (e) {
      console.error('加载钱包设置失败:', e)
      ElMessage.error('加载钱包设置失败')
    } finally {
      loading.value = false
    }
  }
  const handleSave = async () => {
    saving.value = true
    try {
      // 设置中心按字符串持久化钱包参数，提交边界统一序列化，客户端使用时再按语义转换。
      const d: Record<string, string> = {}
      Object.entries(form).forEach(([k, v]) => (d[k] = String(v)))
      await saveWalletSettings(d)
      ElMessage.success('保存成功')
    } catch {
      ElMessage.error('保存失败')
    } finally {
      saving.value = false
    }
  }

  // ===== 充值方式 =====
  const rechargeMethods = ref<RechargeMethodInfo[]>([])
  const rechargeLoading = ref(false)
  const rechargeDialogVisible = ref(false)
  const editRecharge = ref<RechargeMethodInfo | null>(null)
  const rechargeSaving = ref(false)
  const rechargeForm = reactive<any>({
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
  const accountFields = ref<{ label: string; value: string }[]>([])

  const fetchRechargeMethods = async () => {
    rechargeLoading.value = true
    try {
      rechargeMethods.value = ((await getRechargeMethods()) as any) || []
    } catch (e) {
      console.error('加载充值方式失败:', e)
      ElMessage.error('加载充值方式失败')
    } finally {
      rechargeLoading.value = false
    }
  }
  const showRechargeDialog = (row?: RechargeMethodInfo) => {
    editRecharge.value = row || null
    if (row) {
      Object.assign(rechargeForm, row)
      // account_info 是给 H5 展示的渠道账户键值，编辑时从 JSON 恢复为可排序表单行。
      try {
        const obj = JSON.parse(row.account_info || '{}')
        accountFields.value = Object.entries(obj).map(([k, v]) => ({ label: k, value: String(v) }))
      } catch {
        accountFields.value = []
      }
    } else {
      Object.assign(rechargeForm, {
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
      accountFields.value = [{ label: '', value: '' }]
    }
    rechargeDialogVisible.value = true
  }
  const saveRechargeMethod = async () => {
    if (!rechargeForm.name) {
      ElMessage.warning('请输入名称')
      return
    }
    // 把 accountFields 转成 JSON
    if (rechargeForm.type === 'bank') {
      const obj: Record<string, string> = {}
      accountFields.value.filter((f) => f.label && f.value).forEach((f) => (obj[f.label] = f.value))
      rechargeForm.account_info = JSON.stringify(obj)
    }
    rechargeSaving.value = true
    try {
      if (editRecharge.value) {
        await updateRechargeMethod(editRecharge.value.id, rechargeForm)
      } else {
        // 创建时排除 id 防止主键冲突
        const createData = { ...rechargeForm }
        delete createData.id
        delete createData.created_at
        delete createData.deleted_at
        delete createData.updated_at
        await createRechargeMethod(createData)
      }
      ElMessage.success('保存成功')
      rechargeDialogVisible.value = false
      fetchRechargeMethods()
    } catch {
      ElMessage.error('保存失败')
    } finally {
      rechargeSaving.value = false
    }
  }
  const delRechargeMethod = async (id: number) => {
    try {
      await deleteRechargeMethod(id)
      ElMessage.success('已删除')
      fetchRechargeMethods()
    } catch {
      ElMessage.error('删除失败')
    }
  }

  // ===== 提现方式 =====
  const withdrawMethods = ref<WithdrawMethodInfo[]>([])
  const withdrawLoading = ref(false)
  const withdrawDialogVisible = ref(false)
  const editWithdraw = ref<WithdrawMethodInfo | null>(null)
  const withdrawSaving = ref(false)
  const withdrawForm = reactive<any>({
    name: '',
    icon: '',
    fields: '[]',
    fee: 0,
    min_amount: 1,
    max_amount: 50000,
    status: 1,
    sort: 0
  })
  const withdrawFields = ref<
    { key: string; label: string; hint: string; type: string; required: boolean }[]
  >([])

  const fetchWithdrawMethods = async () => {
    withdrawLoading.value = true
    try {
      withdrawMethods.value = ((await getWithdrawMethods()) as any) || []
    } catch (e) {
      console.error('加载提现方式失败:', e)
      ElMessage.error('加载提现方式失败')
    } finally {
      withdrawLoading.value = false
    }
  }
  const parseFieldNames = (fieldsJson: string) => {
    try {
      return (JSON.parse(fieldsJson || '[]') as any[]).map((f: any) => f.label).join('、') || '-'
    } catch {
      return '-'
    }
  }
  const showWithdrawDialog = (row?: WithdrawMethodInfo) => {
    editWithdraw.value = row || null
    if (row) {
      Object.assign(withdrawForm, row)
      try {
        withdrawFields.value = JSON.parse(row.fields || '[]')
      } catch {
        withdrawFields.value = []
      }
    } else {
      Object.assign(withdrawForm, {
        name: '',
        icon: '',
        fields: '[]',
        fee: 0,
        min_amount: 1,
        max_amount: 50000,
        status: 1,
        sort: 0
      })
      withdrawFields.value = [
        { key: 'account', label: '收款账号', hint: '请输入收款账号', type: 'text', required: true },
        { key: 'realName', label: '真实姓名', hint: '请输入真实姓名', type: 'text', required: true }
      ]
    }
    withdrawDialogVisible.value = true
  }
  const saveWithdrawMethod = async () => {
    if (!withdrawForm.name) {
      ElMessage.warning('请输入名称')
      return
    }
    // key 会成为用户提现 form_data 的字段名，空 key 在保存前生成稳定的当前表单索引名。
    withdrawFields.value.forEach((f, i) => {
      if (!f.key) f.key = `field_${i}`
    })
    withdrawForm.fields = JSON.stringify(withdrawFields.value.filter((f) => f.label))
    withdrawSaving.value = true
    try {
      if (editWithdraw.value) await updateWithdrawMethod(editWithdraw.value.id, withdrawForm)
      else await createWithdrawMethod(withdrawForm)
      ElMessage.success('保存成功')
      withdrawDialogVisible.value = false
      fetchWithdrawMethods()
    } catch {
      ElMessage.error('保存失败')
    } finally {
      withdrawSaving.value = false
    }
  }
  const delWithdrawMethod = async (id: number) => {
    try {
      await deleteWithdrawMethod(id)
      ElMessage.success('已删除')
      fetchWithdrawMethods()
    } catch {
      ElMessage.error('删除失败')
    }
  }

  onMounted(() => {
    // 三组接口互不依赖，各自维护 loading，单组失败不会阻断其他配置区域。
    fetchSettings()
    fetchRechargeMethods()
    fetchWithdrawMethods()
  })
</script>
