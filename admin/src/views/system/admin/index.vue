<template>
  <div class="admin-account-page art-full-height">
    <ElAlert
      v-if="isDemoAdmin"
      type="warning"
      :closable="false"
      show-icon
      class="mb-4"
    >
      当前为演示管理员，只能查看管理员列表，不能新增、删除或修改配置。
    </ElAlert>

    <ElAlert type="info" :closable="false" show-icon class="mb-4">
      演示账号：demo / demo123，权限为只读；默认超级管理员：admin / 123456。
    </ElAlert>

    <ElCard class="art-table-card" shadow="never">
      <div class="table-toolbar">
        <div>
          <div class="toolbar-title">管理员列表</div>
          <div class="toolbar-subtitle">共 {{ admins.length }} 个后台账号</div>
        </div>
        <div class="toolbar-actions">
          <ElButton :loading="loading" @click="fetchAdmins">刷新</ElButton>
          <ElButton v-if="canManageAdmins" type="primary" @click="openCreateDialog">
            新增管理员
          </ElButton>
        </div>
      </div>

      <ElTable v-loading="loading" :data="admins" border stripe>
        <ElTableColumn prop="username" label="账号" min-width="130" />
        <ElTableColumn prop="nickname" label="昵称" min-width="140" />
        <ElTableColumn label="角色" width="130">
          <template #default="{ row }">
            <ElTag :type="roleTagType(row.role)">
              {{ roleLabel(row.role) }}
            </ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn label="状态" width="100">
          <template #default="{ row }">
            <ElTag :type="row.status === 1 ? 'success' : 'danger'">
              {{ row.status === 1 ? '正常' : '禁用' }}
            </ElTag>
          </template>
        </ElTableColumn>
        <ElTableColumn prop="last_login_ip" label="最后登录IP" min-width="130" />
        <ElTableColumn label="最后登录" min-width="170">
          <template #default="{ row }">
            {{ formatTime(row.last_login_at) }}
          </template>
        </ElTableColumn>
        <ElTableColumn label="创建时间" min-width="170">
          <template #default="{ row }">
            {{ formatTime(row.created_at) }}
          </template>
        </ElTableColumn>
        <ElTableColumn v-if="canManageAdmins" label="操作" width="110" fixed="right">
          <template #default="{ row }">
            <ElButton
              type="danger"
              link
              :disabled="row.role === 'super_admin'"
              @click="handleDelete(row)"
            >
              删除
            </ElButton>
          </template>
        </ElTableColumn>
      </ElTable>
    </ElCard>

    <ElDialog v-model="createVisible" title="新增管理员" width="460px" destroy-on-close>
      <ElForm :model="createForm" label-width="90px">
        <ElFormItem label="账号" required>
          <ElInput v-model="createForm.username" placeholder="请输入账号" maxlength="50" />
        </ElFormItem>
        <ElFormItem label="密码" required>
          <ElInput
            v-model="createForm.password"
            type="password"
            placeholder="至少 6 位"
            show-password
          />
        </ElFormItem>
        <ElFormItem label="昵称" required>
          <ElInput v-model="createForm.nickname" placeholder="请输入昵称" maxlength="100" />
        </ElFormItem>
        <ElFormItem label="角色" required>
          <ElSelect v-model="createForm.role" class="w-full">
            <ElOption
              v-for="item in roleOptions"
              :key="item.value"
              :label="item.label"
              :value="item.value"
            />
          </ElSelect>
        </ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="createVisible = false">取消</ElButton>
        <ElButton type="primary" :loading="saving" @click="submitCreate">保存</ElButton>
      </template>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
  import { computed, onMounted, reactive, ref } from 'vue'
  import { ElMessage, ElMessageBox } from 'element-plus'
  import { createAdmin, deleteAdmin, getAdminList } from '@/api/admin'
  import type { AdminCreateParams, AdminInfo } from '@/api/admin'
  import { usePermission } from '@/hooks/usePermission'

  const { isDemoAdmin, isSuperAdmin } = usePermission()
  const loading = ref(false)
  const saving = ref(false)
  const createVisible = ref(false)
  const admins = ref<AdminInfo[]>([])
  // 前端权限只控制操作入口，创建和删除仍由服务端再次校验管理员角色。
  const canManageAdmins = computed(() => isSuperAdmin.value && !isDemoAdmin.value)

  const roleOptions: Array<{ label: string; value: AdminCreateParams['role'] }> = [
    { label: '管理员', value: 'admin' },
    { label: '运营人员', value: 'operator' },
    { label: '演示管理员', value: 'demo_admin' }
  ]

  const createForm = reactive<AdminCreateParams>({
    username: '',
    password: '',
    nickname: '',
    role: 'admin'
  })

  const roleLabel = (role: AdminInfo['role']) => {
    const labels: Record<AdminInfo['role'], string> = {
      super_admin: '超级管理员',
      admin: '管理员',
      operator: '运营人员',
      demo_admin: '演示管理员'
    }
    return labels[role] || role
  }

  const roleTagType = (role: AdminInfo['role']) => {
    if (role === 'super_admin') return 'danger'
    if (role === 'demo_admin') return 'warning'
    if (role === 'operator') return 'info'
    return 'primary'
  }

  const formatTime = (value?: string | null) => {
    if (!value) return '-'
    return value.replace('T', ' ').replace(/\.\d+Z?$/, '')
  }

  const resetCreateForm = () => {
    createForm.username = ''
    createForm.password = ''
    createForm.nickname = ''
    createForm.role = 'admin'
  }

  const fetchAdmins = async () => {
    loading.value = true
    try {
      admins.value = await getAdminList()
    } finally {
      loading.value = false
    }
  }

  const openCreateDialog = () => {
    // 每次打开都清空上次输入，避免敏感密码残留在复用弹窗中。
    resetCreateForm()
    createVisible.value = true
  }

  const submitCreate = async () => {
    const username = createForm.username.trim()
    const password = createForm.password.trim()
    const nickname = createForm.nickname.trim()
    if (!username || !password || !nickname) {
      ElMessage.warning('请填写账号、密码和昵称')
      return
    }
    if (password.length < 6) {
      ElMessage.warning('密码至少 6 位')
      return
    }

    saving.value = true
    try {
      await createAdmin({
        username,
        password,
        nickname,
        role: createForm.role
      })
      ElMessage.success('管理员已创建')
      createVisible.value = false
      // 创建结果以服务端返回列表为准，成功后重新加载而非本地拼接。
      await fetchAdmins()
    } finally {
      saving.value = false
    }
  }

  const handleDelete = async (row: AdminInfo) => {
    if (row.role === 'super_admin') return
    await ElMessageBox.confirm(`确认删除管理员「${row.username}」？`, '删除确认', {
      type: 'warning',
      confirmButtonText: '删除',
      cancelButtonText: '取消'
    })
    await deleteAdmin(row.id)
    ElMessage.success('管理员已删除')
    await fetchAdmins()
  }

  onMounted(fetchAdmins)
</script>

<style scoped lang="scss">
  .admin-account-page {
    padding: 16px;
  }

  .table-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    margin-bottom: 16px;
  }

  .toolbar-title {
    font-size: 16px;
    font-weight: 600;
    color: var(--art-text-gray-900);
  }

  .toolbar-subtitle {
    margin-top: 4px;
    font-size: 12px;
    color: var(--art-text-gray-500);
  }

  .toolbar-actions {
    display: flex;
    gap: 8px;
  }

  @media (max-width: 640px) {
    .table-toolbar {
      align-items: stretch;
      flex-direction: column;
    }

    .toolbar-actions {
      justify-content: flex-end;
    }
  }
</style>
