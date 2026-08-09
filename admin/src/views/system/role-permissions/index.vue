<template>
  <div class="role-permissions-page">
    <ElAlert v-if="isDemoAdmin" type="warning" :closable="false" show-icon class="mb-4">
      当前为演示管理员，只能查看角色权限，无法保存修改。
    </ElAlert>
    <ElAlert v-else type="info" :closable="false" show-icon class="mb-4">
      这里控制不同后台角色能看到哪些菜单。超级管理员始终拥有全部菜单，避免误配置后无法进入后台。
    </ElAlert>

    <div class="permission-shell">
      <aside class="role-sidebar">
        <div class="permission-switch">
          <div>
            <div class="switch-title">启用菜单权限</div>
            <div class="switch-desc">关闭后仅使用系统默认角色控制</div>
          </div>
          <ElSwitch v-model="form.enabled" :disabled="!canEdit" />
        </div>

        <ElMenu :default-active="activeRole" class="role-menu" @select="handleRoleSelect">
          <ElMenuItem v-for="role in roleOptions" :key="role.key" :index="role.key">
            <Icon :icon="role.icon" class="mr-2" />
            <span>{{ role.title }}</span>
          </ElMenuItem>
        </ElMenu>
      </aside>

      <section class="permission-panel">
        <div class="panel-head">
          <div>
            <h3>{{ currentRole.title }}</h3>
            <p>{{ currentRole.desc }}</p>
          </div>
          <div class="panel-actions">
            <ElButton :disabled="!canEdit || activeRole === 'super_admin'" @click="checkAll">
              全选
            </ElButton>
            <ElButton :disabled="!canEdit || activeRole === 'super_admin'" @click="clearCurrent">
              清空
            </ElButton>
            <ElButton :disabled="!canEdit || activeRole === 'super_admin'" @click="resetCurrent">
              恢复默认
            </ElButton>
            <ElButton type="primary" :loading="saving" :disabled="!canEdit" @click="save">
              保存配置
            </ElButton>
          </div>
        </div>

        <ElDivider />

        <ElTree
          ref="treeRef"
          :data="menuTree"
          node-key="path"
          show-checkbox
          default-expand-all
          :expand-on-click-node="false"
          :props="treeProps"
          :disabled="!canEdit || activeRole === 'super_admin'"
          class="permission-tree"
        >
          <template #default="{ data }">
            <div class="tree-node">
              <Icon v-if="data.icon" :icon="data.icon" />
              <span>{{ data.title }}</span>
              <code>{{ data.path }}</code>
            </div>
          </template>
        </ElTree>
      </section>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { computed, nextTick, onMounted, reactive, ref } from 'vue'
  import { ElMessage, ElTree } from 'element-plus'
  import { getSystemSettings, updateSystemSettings } from '@/api/admin'
  import type { AdminRoleKey, RolePermissionConfig } from '@/api/admin'
  import { routeModules } from '@/router/modules'
  import type { AppRouteRecord } from '@/types/router'

  interface MenuNode {
    path: string
    title: string
    icon?: string
    children?: MenuNode[]
  }

  interface RoleOption {
    key: AdminRoleKey
    title: string
    desc: string
    icon: string
  }

  const roleOptions: RoleOption[] = [
    {
      key: 'super_admin',
      title: '超级管理员',
      desc: '系统最高权限，始终展示全部菜单。',
      icon: 'ri:shield-star-line'
    },
    {
      key: 'admin',
      title: '普通管理员',
      desc: '适合日常管理人员，默认开放大部分业务菜单。',
      icon: 'ri:admin-line'
    },
    {
      key: 'operator',
      title: '运营人员',
      desc: '适合客服、运营和内容处理，默认隐藏系统密钥与支付配置。',
      icon: 'ri:user-follow-line'
    },
    {
      key: 'demo_admin',
      title: '演示管理员',
      desc: '默认展示全部菜单，仅允许查看，后端仍会拦截所有写操作并隐藏敏感接口配置。',
      icon: 'ri:eye-line'
    }
  ]

  const treeProps = {
    label: 'title',
    children: 'children'
  }

  const treeRef = ref<InstanceType<typeof ElTree>>()
  const activeRole = ref<AdminRoleKey>('admin')
  const saving = ref(false)
  const adminRole = ref('')
  const form = reactive<RolePermissionConfig>({
    enabled: false,
    roles: {
      super_admin: [],
      admin: [],
      operator: [],
      demo_admin: []
    }
  })

  const menuTree = computed(() => buildMenuTree(routeModules))
  const allMenuPaths = computed(() => flattenMenuPaths(menuTree.value))
  const currentRole = computed(
    () => roleOptions.find((role) => role.key === activeRole.value) || roleOptions[1]
  )
  const isDemoAdmin = computed(() => adminRole.value === 'demo_admin')
  const canEdit = computed(() => adminRole.value === 'super_admin')

  onMounted(loadSettings)

  async function loadSettings() {
    const settings = await getSystemSettings()
    adminRole.value = settings._admin_role || ''

    const saved = parseConfig(settings.role_permissions)
    const defaults = buildDefaultPermissions()

    form.enabled = saved?.enabled ?? false
    for (const role of roleOptions) {
      form.roles[role.key] = saved?.roles?.[role.key]?.length
        ? [...(saved.roles[role.key] || [])]
        : [...defaults[role.key]]
    }

    syncTree()
  }

  function handleRoleSelect(role: string) {
    persistCurrentRole()
    activeRole.value = role as AdminRoleKey
    syncTree()
  }

  function checkAll() {
    treeRef.value?.setCheckedKeys(allMenuPaths.value)
    persistCurrentRole()
  }

  function clearCurrent() {
    treeRef.value?.setCheckedKeys([])
    persistCurrentRole()
  }

  function resetCurrent() {
    const defaults = buildDefaultPermissions()
    treeRef.value?.setCheckedKeys(defaults[activeRole.value])
    persistCurrentRole()
  }

  async function save() {
    if (!canEdit.value) {
      ElMessage.warning('当前账号无权保存角色权限')
      return
    }

    // 当前树节点尚未自动写回表单，保存前必须先固化正在编辑的角色。
    persistCurrentRole()
    saving.value = true
    try {
      await updateSystemSettings({
        role_permissions: {
          enabled: form.enabled,
          roles: {
            admin: normalizePaths(form.roles.admin || []),
            operator: normalizePaths(form.roles.operator || []),
            demo_admin: normalizePaths(form.roles.demo_admin || [])
          }
        }
      })
      ElMessage.success('角色权限已保存，重新登录或刷新后台后生效')
    } finally {
      saving.value = false
    }
  }

  function syncTree() {
    nextTick(() => {
      const checked =
        activeRole.value === 'super_admin'
          ? allMenuPaths.value
          : form.roles[activeRole.value] || []
      treeRef.value?.setCheckedKeys(checked)
    })
  }

  function persistCurrentRole() {
    if (activeRole.value === 'super_admin') {
      form.roles.super_admin = allMenuPaths.value
      return
    }

    const checked = treeRef.value?.getCheckedKeys(false) || []
    const halfChecked = treeRef.value?.getHalfCheckedKeys() || []
    // 半选父节点也要持久化，否则刷新后无法还原完整菜单路径层级。
    form.roles[activeRole.value] = normalizePaths([...checked, ...halfChecked].map(String))
  }

  function parseConfig(value: RolePermissionConfig | string | undefined): RolePermissionConfig | null {
    if (!value) {
      return null
    }

    if (typeof value === 'string') {
      try {
        return JSON.parse(value) as RolePermissionConfig
      } catch {
        return null
      }
    }

    return value
  }

  function buildMenuTree(routes: AppRouteRecord[], parentPath = ''): MenuNode[] {
    return routes
      .filter((route) => !route.meta?.isHide)
      .map((route) => {
        const fullPath = buildFullPath(route.path || '', parentPath)
        const children = route.children?.length ? buildMenuTree(route.children, fullPath) : undefined

        return {
          path: fullPath,
          title: String(route.meta?.title || route.name || fullPath),
          icon: route.meta?.icon,
          children: children?.length ? children : undefined
        }
      })
  }

  function buildDefaultPermissions(): Record<AdminRoleKey, string[]> {
    const all = allMenuPaths.value
    const excludeForOperator = [
      '/user-permission/admins',
      '/user-permission/role-permissions',
      '/system/rtc-settings',
      '/system/ai-config',
      '/system/storage-config',
      '/system/health',
      '/system/security',
      '/system/multi-line-entry',
      '/system/hot-update',
      '/system/payment-gateway',
      '/system/push-report',
      '/system/push-config',
      '/operation/sms-gateway'
    ]

    return {
      super_admin: all,
      admin: all.filter((path) => path !== '/user-permission/role-permissions'),
      operator: all.filter((path) => !excludeForOperator.includes(path)),
      demo_admin: all
    }
  }

  function flattenMenuPaths(nodes: MenuNode[]): string[] {
    return nodes.flatMap((node) => [
      node.path,
      ...(node.children?.length ? flattenMenuPaths(node.children) : [])
    ])
  }

  function normalizePaths(paths: string[]): string[] {
    return [...new Set(paths.filter(Boolean))]
  }

  function buildFullPath(path: string, parentPath: string): string {
    if (!path) {
      return ''
    }
    if (path.startsWith('http://') || path.startsWith('https://') || path.startsWith('/')) {
      return path
    }
    if (!parentPath) {
      return `/${path}`
    }
    return `${parentPath.replace(/\/$/, '')}/${path.replace(/^\//, '')}`
  }
</script>

<style scoped>
  .role-permissions-page {
    padding: 16px;
  }

  .permission-shell {
    display: grid;
    grid-template-columns: 280px minmax(0, 1fr);
    gap: 16px;
    align-items: start;
  }

  .role-sidebar,
  .permission-panel {
    border: 1px solid var(--el-border-color-light);
    border-radius: 8px;
    background: var(--el-bg-color);
  }

  .permission-switch {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 16px;
    border-bottom: 1px solid var(--el-border-color-light);
  }

  .switch-title {
    color: var(--el-text-color-primary);
    font-weight: 600;
  }

  .switch-desc,
  .panel-head p {
    margin: 4px 0 0;
    color: var(--el-text-color-secondary);
    font-size: 13px;
    line-height: 1.5;
  }

  .role-menu {
    border-right: 0;
  }

  .permission-panel {
    min-height: 620px;
    padding: 18px;
  }

  .panel-head {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 16px;
  }

  .panel-head h3 {
    margin: 0;
    color: var(--el-text-color-primary);
    font-size: 18px;
    font-weight: 600;
  }

  .panel-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    justify-content: flex-end;
  }

  .permission-tree {
    max-width: 880px;
  }

  .tree-node {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
    color: var(--el-text-color-primary);
  }

  .tree-node code {
    color: var(--el-text-color-secondary);
    font-size: 12px;
    background: var(--el-fill-color-light);
    border-radius: 4px;
    padding: 2px 6px;
  }

  @media (max-width: 900px) {
    .permission-shell {
      grid-template-columns: 1fr;
    }

    .panel-head {
      flex-direction: column;
    }

    .panel-actions {
      justify-content: flex-start;
    }
  }
</style>
