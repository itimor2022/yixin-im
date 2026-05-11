<script setup lang="ts">
  import { computed, onMounted, reactive, ref } from 'vue'
  import { ElMessage } from 'element-plus'
  import {
    cancelMembership,
    getMembershipOrders,
    getMembershipPlans,
    getMembershipSummary,
    getMembershipUsers,
    grantMembership,
    saveMembershipPlan,
    type MembershipOrderItem,
    type MembershipPlanItem,
    type MembershipSummary,
    type MembershipUserItem
  } from '@/api/admin'

  defineOptions({ name: 'MembershipManage' })

  const loading = ref(false)
  const usersLoading = ref(false)
  const plansLoading = ref(false)
  const ordersLoading = ref(false)
  const summary = ref<MembershipSummary>()
  const plans = ref<MembershipPlanItem[]>([])
  const users = ref<MembershipUserItem[]>([])
  const orders = ref<MembershipOrderItem[]>([])
  const searchKeyword = ref('')
  const page = ref(1)
  const total = ref(0)
  const pageSize = ref(20)
  const orderPage = ref(1)
  const orderTotal = ref(0)
  const planDialogVisible = ref(false)
  const grantDialogVisible = ref(false)
  const selectedUser = ref<MembershipUserItem>()

  const planForm = reactive<Partial<MembershipPlanItem>>({
    id: 0,
    name: '',
    slug: '',
    duration_days: 30,
    price: 28,
    original_price: 38,
    badge_label: 'PREMIUM',
    badge_color: '#3390EC',
    description: '',
    features: ['会员徽章', '更高上传限制'],
    status: 1,
    sort: 0
  })

  const grantForm = reactive({
    plan_id: undefined as number | undefined,
    days: 30
  })

  const featureText = computed({
    get: () => (planForm.features || []).join('\n'),
    set: (val: string) => {
      planForm.features = val
        .split('\n')
        .map((v) => v.trim())
        .filter(Boolean)
    }
  })

  async function loadAll() {
    loading.value = true
    try {
      await Promise.all([loadSummary(), loadPlans(), loadUsers(), loadOrders()])
    } finally {
      loading.value = false
    }
  }

  async function loadSummary() {
    summary.value = await getMembershipSummary()
  }

  async function loadPlans() {
    plansLoading.value = true
    try {
      plans.value = await getMembershipPlans()
    } finally {
      plansLoading.value = false
    }
  }

  async function loadUsers() {
    usersLoading.value = true
    try {
      const res = await getMembershipUsers({
        page: page.value,
        page_size: pageSize.value,
        keyword: searchKeyword.value
      })
      users.value = res.list
      total.value = res.total
    } finally {
      usersLoading.value = false
    }
  }

  async function loadOrders() {
    ordersLoading.value = true
    try {
      const res = await getMembershipOrders({ page: orderPage.value, page_size: 20 })
      orders.value = res.list
      orderTotal.value = res.total
    } finally {
      ordersLoading.value = false
    }
  }

  function editPlan(plan?: MembershipPlanItem) {
    if (plan) {
      Object.assign(planForm, JSON.parse(JSON.stringify(plan)))
    } else {
      Object.assign(planForm, {
        id: 0,
        name: '',
        slug: '',
        duration_days: 30,
        price: 28,
        original_price: 38,
        badge_label: 'PREMIUM',
        badge_color: '#3390EC',
        description: '',
        features: ['会员徽章', '更高上传限制'],
        status: 1,
        sort: 0
      })
    }
    planDialogVisible.value = true
  }

  async function submitPlan() {
    await saveMembershipPlan(planForm)
    ElMessage.success('保存成功')
    planDialogVisible.value = false
    loadPlans()
  }

  function openGrant(row: MembershipUserItem) {
    selectedUser.value = row
    grantForm.plan_id = plans.value[0]?.id
    grantForm.days = 30
    grantDialogVisible.value = true
  }

  async function submitGrant() {
    if (!selectedUser.value || !grantForm.plan_id) return
    await grantMembership(selectedUser.value.user_id, grantForm.plan_id, grantForm.days)
    ElMessage.success('赠送成功')
    grantDialogVisible.value = false
    loadUsers()
  }

  async function handleCancel(row: MembershipUserItem) {
    await cancelMembership(row.id)
    ElMessage.success('已取消')
    loadUsers()
  }

  onMounted(loadAll)
</script>

<template>
  <div class="membership-page" v-loading="loading">
    <div class="grid grid-cols-3 gap-4 mb-4">
      <ElCard>
        <div class="text-sm text-g-500">累计开通</div>
        <div class="text-3xl font-bold mt-2">{{ summary?.total_users || 0 }}</div>
      </ElCard>
      <ElCard>
        <div class="text-sm text-g-500">当前有效会员</div>
        <div class="text-3xl font-bold mt-2 text-blue-600">{{ summary?.active_users || 0 }}</div>
      </ElCard>
      <ElCard>
        <div class="text-sm text-g-500">累计收入</div>
        <div class="text-3xl font-bold mt-2 text-violet-600"
          >¥{{ (summary?.total_revenue || 0).toFixed(2) }}</div
        >
      </ElCard>
    </div>

    <ElCard class="mb-4">
      <template #header>
        <div class="flex items-center justify-between">
          <span class="font-semibold">会员套餐</span>
          <ElButton type="primary" @click="editPlan()">新增套餐</ElButton>
        </div>
      </template>
      <ElTable :data="plans" v-loading="plansLoading" stripe>
        <ElTableColumn prop="name" label="名称" min-width="140" />
        <ElTableColumn prop="duration_days" label="时长(天)" width="100" />
        <ElTableColumn label="价格" width="120">
          <template #default="{ row }">¥{{ row.price }}</template>
        </ElTableColumn>
        <ElTableColumn label="权益" min-width="260">
          <template #default="{ row }">{{ (row.features || []).join(' / ') }}</template>
        </ElTableColumn>
        <ElTableColumn label="状态" width="90">
          <template #default="{ row }">
            <ElTag :type="row.status === 1 ? 'success' : 'info'">{{
              row.status === 1 ? '启用' : '禁用'
            }}</ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn label="操作" width="100">
          <template #default="{ row }">
            <ElButton link type="primary" @click="editPlan(row)">编辑</ElButton>
          </template>
        </ElTableColumn>
      </ElTable>
    </ElCard>

    <ElCard class="mb-4">
      <template #header>
        <div class="flex items-center justify-between gap-3">
          <span class="font-semibold">用户会员</span>
          <div class="flex items-center gap-2">
            <ElInput
              v-model="searchKeyword"
              placeholder="搜索用户名/昵称"
              style="width: 220px"
              @keyup.enter="loadUsers"
            />
            <ElButton type="primary" @click="loadUsers">搜索</ElButton>
          </div>
        </div>
      </template>
      <ElTable :data="users" v-loading="usersLoading" stripe>
        <ElTableColumn prop="nickname" label="用户" min-width="160" />
        <ElTableColumn prop="plan_name" label="套餐" width="140" />
        <ElTableColumn prop="source" label="来源" width="100" />
        <ElTableColumn prop="status" label="状态" width="100" />
        <ElTableColumn prop="expire_at" label="到期时间" width="180" />
        <ElTableColumn label="操作" width="140">
          <template #default="{ row }">
            <ElButton link type="primary" @click="openGrant(row)">赠送</ElButton>
            <ElButton link type="danger" @click="handleCancel(row)">取消</ElButton>
          </template>
        </ElTableColumn>
      </ElTable>
      <div class="flex justify-end mt-4">
        <ElPagination
          v-model:current-page="page"
          v-model:page-size="pageSize"
          :total="total"
          layout="total, prev, pager, next"
          @current-change="loadUsers"
        />
      </div>
    </ElCard>

    <ElCard>
      <template #header><span class="font-semibold">购买订单</span></template>
      <ElTable :data="orders" v-loading="ordersLoading" stripe>
        <ElTableColumn prop="order_no" label="订单号" min-width="180" />
        <ElTableColumn prop="nickname" label="用户" min-width="140" />
        <ElTableColumn prop="plan_name" label="套餐" width="140" />
        <ElTableColumn prop="amount" label="金额" width="100" />
        <ElTableColumn prop="pay_channel" label="支付方式" width="100" />
        <ElTableColumn prop="status" label="状态" width="100" />
        <ElTableColumn prop="created_at" label="创建时间" width="180" />
      </ElTable>
      <div class="flex justify-end mt-4">
        <ElPagination
          v-model:current-page="orderPage"
          :page-size="20"
          :total="orderTotal"
          layout="total, prev, pager, next"
          @current-change="loadOrders"
        />
      </div>
    </ElCard>

    <ElDialog v-model="planDialogVisible" title="会员套餐" width="560px">
      <ElForm :model="planForm" label-width="100px">
        <ElFormItem label="名称"><ElInput v-model="planForm.name" /></ElFormItem>
        <ElFormItem label="标识"><ElInput v-model="planForm.slug" /></ElFormItem>
        <ElFormItem label="时长(天)"
          ><ElInputNumber v-model="planForm.duration_days" :min="1"
        /></ElFormItem>
        <ElFormItem label="价格"><ElInputNumber v-model="planForm.price" :min="0.01" /></ElFormItem>
        <ElFormItem label="原价"
          ><ElInputNumber v-model="planForm.original_price" :min="0"
        /></ElFormItem>
        <ElFormItem label="徽章"><ElInput v-model="planForm.badge_label" /></ElFormItem>
        <ElFormItem label="徽章色"><ElInput v-model="planForm.badge_color" /></ElFormItem>
        <ElFormItem label="简介"><ElInput v-model="planForm.description" /></ElFormItem>
        <ElFormItem label="权益"
          ><ElInput v-model="featureText" type="textarea" :rows="4" placeholder="每行一个权益"
        /></ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="planDialogVisible = false">取消</ElButton>
        <ElButton type="primary" @click="submitPlan">保存</ElButton>
      </template>
    </ElDialog>

    <ElDialog v-model="grantDialogVisible" title="赠送会员" width="420px">
      <ElForm :model="grantForm" label-width="90px">
        <ElFormItem label="用户"
          ><span>{{ selectedUser?.nickname }}</span></ElFormItem
        >
        <ElFormItem label="套餐">
          <ElSelect v-model="grantForm.plan_id" style="width: 100%">
            <ElOption v-for="item in plans" :key="item.id" :label="item.name" :value="item.id" />
          </ElSelect>
        </ElFormItem>
        <ElFormItem label="赠送天数"
          ><ElInputNumber v-model="grantForm.days" :min="1"
        /></ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="grantDialogVisible = false">取消</ElButton>
        <ElButton type="primary" @click="submitGrant">确认赠送</ElButton>
      </template>
    </ElDialog>
  </div>
</template>
