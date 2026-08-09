<template>
  <div class="app-layout" :class="{ 'is-collapsed': collapsed }">
    <aside class="sider">
      <div class="brand">
        <div class="brand-mark">服</div>
        <div v-show="!collapsed" class="brand-copy">
          <div class="brand-title">客服中心</div>
          <div class="brand-subtitle">SERVICE DESK</div>
        </div>
      </div>

      <nav class="menu-list" aria-label="客服端主导航">
        <template v-for="group in menuGroups" :key="group.label">
          <div v-show="!collapsed" class="menu-group-title">{{ group.label }}</div>
          <RouterLink
            v-for="item in group.items"
            :key="item.path"
            :to="item.path"
            class="menu-item"
            :class="{ active: isMenuActive(item.path) }"
            :title="collapsed ? item.label : undefined"
          >
            <Icon :icon="item.icon" />
            <span v-show="!collapsed">{{ item.label }}</span>
            <span v-if="item.badge && !collapsed" class="menu-badge">{{ item.badge }}</span>
          </RouterLink>
        </template>
      </nav>

      <div class="sider-footer">
        <button class="user-badge" type="button" @click="router.push('/profile')">
          <div class="avatar">{{ avatarText }}</div>
          <div v-show="!collapsed" class="user-copy">
            <div class="user-name">{{ session.profile.nickname }}</div>
            <div class="user-role">客服坐席</div>
          </div>
          <Icon v-show="!collapsed" icon="ri:arrow-right-s-line" class="user-arrow" />
        </button>
      </div>
    </aside>

    <section class="main-area">
      <header class="topbar">
        <div class="topbar-left">
          <ElButton class="collapse-button" text circle @click="toggleCollapsed">
            <Icon :icon="collapsed ? 'ri:menu-unfold-line' : 'ri:menu-fold-line'" />
          </ElButton>
          <div class="page-heading">
            <h1 class="topbar-title">{{ currentTitle }}</h1>
            <p v-if="currentDescription" class="topbar-subtitle">{{ currentDescription }}</p>
          </div>
        </div>

        <div class="topbar-actions">
          <div class="presence-control">
            <span class="presence-dot" :class="presence"></span>
            <ElSelect v-model="presence" class="presence-select" aria-label="客服在线状态">
              <ElOption label="在线接待" value="online" />
              <ElOption label="忙碌" value="busy" />
              <ElOption label="离线" value="offline" />
            </ElSelect>
          </div>
          <div class="serving-count"><strong>{{ currentServing }}</strong><span>/ {{ maxConcurrent }} 接待中</span></div>
          <ElButton class="icon-button" text circle aria-label="通知">
            <ElBadge :is-dot="true"><Icon icon="ri:notification-3-line" /></ElBadge>
          </ElButton>
          <ElDropdown trigger="click" @command="handleCommand">
            <button class="topbar-user" type="button">
              <span class="topbar-avatar">{{ avatarText }}</span>
              <Icon icon="ri:arrow-down-s-line" />
            </button>
            <template #dropdown>
              <ElDropdownMenu>
                <ElDropdownItem command="profile">个人中心</ElDropdownItem>
                <ElDropdownItem command="logout" divided>退出登录</ElDropdownItem>
              </ElDropdownMenu>
            </template>
          </ElDropdown>
        </div>
      </header>

      <main class="view-area" :class="{ 'is-workbench': route.path === '/workbench' }">
        <RouterView />
      </main>
    </section>
  </div>
</template>

<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Icon } from '@iconify/vue'
import { useSessionStore } from '@/stores/session'
import {
  heartbeatServicePresence,
  updateServicePresence
} from '@/service/api/workbench'

interface MenuItem {
  path: string
  label: string
  icon: string
  badge?: number
}

interface MenuGroup {
  label: string
  items: MenuItem[]
}

const route = useRoute()
const router = useRouter()
const session = useSessionStore()
const collapsed = ref(localStorage.getItem('kf-sidebar-collapsed') === 'true')
const presence = ref<'online' | 'busy' | 'offline'>('online')
const currentServing = ref(0)
const maxConcurrent = ref(5)
let presenceReady = false
let heartbeatTimer: number | undefined

const menuGroups: MenuGroup[] = [
  {
    label: '服务中心',
    items: [
      { path: '/workbench', label: '实时接待', icon: 'ri:customer-service-2-line' },
      { path: '/dashboard', label: '数据概览', icon: 'ri:dashboard-line' },
      { path: '/customers', label: '客户管理', icon: 'ri:contacts-book-2-line' },
      { path: '/quick-replies', label: '快捷回复', icon: 'ri:chat-quote-line' }
    ]
  },
  {
    label: '智能与分析',
    items: [
      { path: '/knowledge', label: 'AI 知识库', icon: 'ri:brain-line' },
      { path: '/reports', label: '数据报表', icon: 'ri:bar-chart-box-line' }
    ]
  },
  {
    label: '邀请运营',
    items: [
      { path: '/invite-code', label: '我的邀请码', icon: 'ri:qr-code-line' },
      { path: '/invitees', label: '邀请用户', icon: 'ri:team-line' },
      { path: '/welcome-message', label: '欢迎语', icon: 'ri:message-3-line' }
    ]
  }
]

const currentTitle = computed(() => String(route.meta.title || '客服中心'))
const currentDescription = computed(() => String(route.meta.description || ''))
const avatarText = computed(() => session.profile.nickname?.trim().slice(0, 1) || '客')

const isMenuActive = (path: string) => route.path === path || route.path.startsWith(`${path}/`)

const toggleCollapsed = () => {
  collapsed.value = !collapsed.value
  localStorage.setItem('kf-sidebar-collapsed', String(collapsed.value))
}

const handleLogout = async () => {
  try {
    await updateServicePresence('offline')
  } catch {
    // 退出登录不能被状态上报失败阻断。
  }
  await session.logout()
  router.push('/login')
}

const syncPresenceSummary = (summary: { current_serving: number; max_concurrent: number }) => {
  currentServing.value = summary.current_serving
  maxConcurrent.value = summary.max_concurrent
}

watch(presence, async (value) => {
  if (!presenceReady) return
  try {
    syncPresenceSummary(await updateServicePresence(value))
  } catch {
    // 顶栏状态会在下一次心跳时重新与后端同步。
  }
})

onMounted(async () => {
  try {
    const summary = await updateServicePresence('online')
    presence.value = summary.presence
    syncPresenceSummary(summary)
  } catch {
    presence.value = 'offline'
  } finally {
    presenceReady = true
  }
  heartbeatTimer = window.setInterval(async () => {
    try {
      syncPresenceSummary(await heartbeatServicePresence())
    } catch {
      // 网络恢复后下一次心跳会自动纠正状态。
    }
  }, 30_000)
})

onBeforeUnmount(() => {
  if (heartbeatTimer) window.clearInterval(heartbeatTimer)
})

const handleCommand = (command: string) => {
  if (command === 'profile') {
    router.push('/profile')
    return
  }
  if (command === 'logout') handleLogout()
}

</script>

<style scoped lang="scss">
.app-layout {
  display: grid;
  grid-template-columns: 228px minmax(0, 1fr);
  min-height: 100vh;
  background: var(--kf-bg);
  transition: grid-template-columns 0.2s ease;
}

.app-layout.is-collapsed {
  grid-template-columns: 72px minmax(0, 1fr);
}

.sider {
  position: sticky;
  top: 0;
  z-index: 20;
  display: flex;
  flex-direction: column;
  min-width: 0;
  height: 100vh;
  padding: 18px 12px 14px;
  overflow: hidden;
  color: #ffffff;
  background: var(--kf-sidebar);
}

.brand {
  display: flex;
  align-items: center;
  gap: 11px;
  min-height: 44px;
  padding: 0 8px 16px;
  border-bottom: 1px solid rgb(255 255 255 / 10%);
}

.brand-mark,
.avatar,
.topbar-avatar {
  flex: 0 0 auto;
  display: grid;
  place-items: center;
  color: #111111;
  background: #ffffff;
}

.brand-mark {
  width: 36px;
  height: 36px;
  border-radius: 9px;
  font-size: 17px;
  font-weight: 800;
}

.brand-copy,
.user-copy {
  min-width: 0;
}

.brand-title {
  overflow: hidden;
  font-size: 15px;
  font-weight: 700;
  white-space: nowrap;
}

.brand-subtitle {
  margin-top: 3px;
  color: rgb(255 255 255 / 45%);
  font-size: 9px;
  letter-spacing: 0.12em;
}

.menu-list {
  flex: 1;
  padding-top: 10px;
  overflow-x: hidden;
  overflow-y: auto;
  scrollbar-width: none;
}

.menu-list::-webkit-scrollbar {
  display: none;
}

.menu-group-title {
  padding: 14px 12px 7px;
  color: rgb(255 255 255 / 38%);
  font-size: 10px;
  font-weight: 600;
  letter-spacing: 0.08em;
  white-space: nowrap;
}

.menu-item {
  position: relative;
  display: flex;
  align-items: center;
  gap: 11px;
  min-height: 42px;
  margin: 2px 0;
  padding: 0 12px;
  border-radius: 8px;
  color: rgb(255 255 255 / 63%);
  font-size: 13px;
  transition: color 0.16s ease, background 0.16s ease;
}

.menu-item :deep(svg) {
  flex: 0 0 auto;
  width: 18px;
  height: 18px;
}

.menu-item:hover {
  color: #ffffff;
  background: var(--kf-sidebar-hover);
}

.menu-item.active {
  color: #111111;
  font-weight: 650;
  background: #ffffff;
}

.menu-badge {
  min-width: 20px;
  margin-left: auto;
  padding: 2px 6px;
  border-radius: 999px;
  color: #ffffff;
  background: #dc2626;
  font-size: 10px;
  line-height: 16px;
  text-align: center;
}

.sider-footer {
  padding-top: 12px;
  border-top: 1px solid rgb(255 255 255 / 10%);
}

.user-badge {
  display: flex;
  align-items: center;
  gap: 10px;
  width: 100%;
  min-width: 0;
  padding: 8px;
  border: 0;
  border-radius: 8px;
  color: #ffffff;
  background: transparent;
  text-align: left;
  cursor: pointer;
}

.user-badge:hover {
  background: var(--kf-sidebar-hover);
}

.avatar {
  width: 32px;
  height: 32px;
  border-radius: 8px;
  font-size: 13px;
  font-weight: 700;
}

.user-name {
  overflow: hidden;
  font-size: 12px;
  font-weight: 600;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.user-role {
  margin-top: 3px;
  color: rgb(255 255 255 / 42%);
  font-size: 10px;
}

.user-arrow {
  flex: 0 0 auto;
  margin-left: auto;
  color: rgb(255 255 255 / 42%);
}

.main-area {
  display: grid;
  grid-template-rows: auto minmax(0, 1fr);
  min-width: 0;
  min-height: 100vh;
}

.topbar {
  position: sticky;
  top: 0;
  z-index: 15;
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 24px;
  min-width: 0;
  min-height: 64px;
  padding: 10px 24px;
  border-bottom: 1px solid var(--kf-border);
  background: rgb(255 255 255 / 96%);
}

.topbar-left,
.topbar-actions,
.presence-control,
.topbar-user {
  display: flex;
  align-items: center;
}

.topbar-left {
  min-width: 0;
  gap: 12px;
}

.collapse-button,
.icon-button {
  flex: 0 0 auto;
  color: var(--kf-text-secondary);
  font-size: 19px;
}

.page-heading {
  min-width: 0;
}

.topbar-title {
  margin: 0;
  color: var(--kf-text);
  font-size: 17px;
  font-weight: 700;
}

.topbar-subtitle {
  margin: 3px 0 0;
  overflow: hidden;
  color: var(--kf-text-muted);
  font-size: 11px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.topbar-actions {
  flex: 0 0 auto;
  gap: 14px;
}

.presence-control {
  gap: 7px;
}

.presence-dot {
  width: 7px;
  height: 7px;
  border-radius: 50%;
  background: var(--kf-text-muted);
}

.presence-dot.online {
  background: var(--kf-success);
  box-shadow: 0 0 0 3px rgb(22 163 74 / 12%);
}

.presence-dot.busy {
  background: var(--kf-warning);
  box-shadow: 0 0 0 3px rgb(217 119 6 / 12%);
}

.presence-select {
  width: 104px;
}

.presence-select :deep(.el-select__wrapper) {
  min-height: 32px;
  padding: 0 8px;
  box-shadow: none;
}

.serving-count {
  display: flex;
  align-items: baseline;
  gap: 3px;
  padding-left: 14px;
  border-left: 1px solid var(--kf-border);
  color: var(--kf-text-muted);
  font-size: 11px;
}

.serving-count strong {
  color: var(--kf-text);
  font-size: 14px;
}

.topbar-user {
  gap: 5px;
  padding: 0;
  border: 0;
  color: var(--kf-text-secondary);
  background: transparent;
  cursor: pointer;
}

.topbar-avatar {
  width: 31px;
  height: 31px;
  border: 1px solid var(--kf-border);
  border-radius: 50%;
  color: #ffffff;
  background: #171717;
  font-size: 12px;
  font-weight: 700;
}

.view-area {
  min-width: 0;
  padding: 20px;
}

.view-area.is-workbench {
  height: calc(100vh - 64px);
  padding: 12px;
  overflow: hidden;
}

.is-collapsed .brand {
  justify-content: center;
  padding-inline: 0;
}

.is-collapsed .menu-group-title {
  height: 10px;
  padding: 0;
}

.is-collapsed .menu-item {
  justify-content: center;
  padding: 0;
}

.is-collapsed .user-badge {
  justify-content: center;
  padding-inline: 0;
}

@media (max-width: 860px) {
  .app-layout,
  .app-layout.is-collapsed {
    grid-template-columns: 72px minmax(0, 1fr);
  }

  .brand {
    justify-content: center;
    padding-inline: 0;
  }

  .brand-copy,
  .menu-group-title,
  .menu-item span,
  .user-copy,
  .user-arrow {
    display: none !important;
  }

  .menu-item,
  .user-badge {
    justify-content: center;
    padding-inline: 0;
  }

  .menu-group-title {
    height: 10px;
    padding: 0;
  }

  .collapse-button {
    display: none;
  }
}

@media (max-width: 640px) {
  .app-layout,
  .app-layout.is-collapsed {
    grid-template-columns: 1fr;
    grid-template-rows: minmax(0, 1fr) 58px;
  }

  .sider {
    position: fixed;
    inset: auto 0 0;
    z-index: 30;
    grid-row: 2;
    width: 100%;
    height: 58px;
    padding: 7px 10px;
    border-top: 1px solid #2a2a2a;
  }

  .brand,
  .menu-group-title,
  .sider-footer,
  .menu-item:nth-of-type(n + 6) {
    display: none !important;
  }

  .menu-list {
    display: flex;
    justify-content: space-around;
    gap: 4px;
    padding: 0;
    overflow: hidden;
  }

  .menu-list > .menu-item {
    display: flex;
    flex: 1;
    max-width: 60px;
    min-height: 44px;
    margin: 0;
  }

  .main-area {
    min-height: calc(100vh - 58px);
    padding-bottom: 58px;
  }

  .topbar {
    min-height: 56px;
    padding: 8px 14px;
  }

  .topbar-subtitle,
  .serving-count,
  .presence-control,
  .icon-button {
    display: none;
  }

  .view-area {
    padding: 12px;
  }

  .view-area.is-workbench {
    height: calc(100vh - 114px);
    padding: 8px;
  }
}
</style>
