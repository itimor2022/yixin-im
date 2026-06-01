<template>
  <div class="page-shell app-layout">
    <aside class="sider">
      <div class="brand">
        <div class="brand-mark">服</div>
        <div>
          <div class="brand-title">官方客服后台</div>
          <div class="brand-subtitle">Service Admin</div>
        </div>
      </div>

      <nav class="menu-list">
        <RouterLink
          v-for="item in menus"
          :key="item.path"
          :to="item.path"
          class="menu-item"
          :class="{ active: route.path === item.path }"
        >
          <Icon :icon="item.icon" />
          <span>{{ item.label }}</span>
        </RouterLink>
      </nav>

      <div class="sider-footer">
        <div class="user-badge">
          <div class="avatar">KF</div>
          <div>
            <div class="user-name">{{ session.profile.nickname }}</div>
            <div class="user-role">{{ session.profile.role }}</div>
          </div>
        </div>
      </div>
    </aside>

    <main class="main-area">
      <header class="topbar page-card">
        <div>
          <h1 class="topbar-title">{{ currentTitle }}</h1>
          <p class="topbar-subtitle">独立官方客服工作台前端壳子</p>
        </div>
        <div class="topbar-actions">
          <ElTag type="success" effect="dark" round>已独立部署预留</ElTag>
          <ElButton plain @click="handleLogout">退出登录</ElButton>
        </div>
      </header>

      <section class="view-area">
        <RouterView />
      </section>
    </main>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { Icon } from '@iconify/vue'
import { useSessionStore } from '@/stores/session'

const route = useRoute()
const router = useRouter()
const session = useSessionStore()

const menus = [
  { path: '/dashboard', label: '工作台', icon: 'ri:dashboard-line' },
  { path: '/invite-code', label: '我的邀请码', icon: 'ri:qr-code-line' },
  { path: '/welcome-message', label: '欢迎语设置', icon: 'ri:message-3-line' },
  { path: '/invitees', label: '我的用户', icon: 'ri:team-line' },
  { path: '/profile', label: '个人中心', icon: 'ri:user-settings-line' }
]

const currentTitle = computed(
  () => menus.find((item) => item.path === route.path)?.label || '官方客服后台'
)

const handleLogout = async () => {
  await session.logout()
  router.push('/login')
}
</script>

<style scoped lang="scss">
.app-layout { display: grid; grid-template-columns: 280px minmax(0, 1fr); gap: 20px; padding: 20px; }
.sider { display: flex; flex-direction: column; gap: 20px; padding: 24px 18px; border: 1px solid var(--line); border-radius: 24px; background: linear-gradient(180deg, rgba(15,23,42,.96), rgba(2,6,23,.92)); min-height: calc(100vh - 40px); }
.brand { display: flex; align-items: center; gap: 14px; padding: 8px 10px 18px; border-bottom: 1px solid var(--line); }
.brand-mark { width: 46px; height: 46px; border-radius: 16px; display: grid; place-items: center; font-size: 20px; font-weight: 800; color: #052e16; background: linear-gradient(135deg, #86efac, #22c55e); }
.brand-title { font-size: 18px; font-weight: 700; }
.brand-subtitle { margin-top: 4px; color: var(--text-soft); font-size: 12px; letter-spacing: .08em; text-transform: uppercase; }
.menu-list { display: grid; gap: 8px; }
.menu-item { display: flex; align-items: center; gap: 12px; padding: 13px 14px; border-radius: 16px; color: var(--text-soft); transition: .2s ease; }
.menu-item:hover, .menu-item.active { background: rgba(74,222,128,.14); color: var(--text); border: 1px solid rgba(74,222,128,.2); }
.sider-footer { margin-top: auto; }
.user-badge { display: flex; align-items: center; gap: 12px; padding: 14px; background: var(--panel-soft); border-radius: 18px; border: 1px solid var(--line); }
.avatar { width: 42px; height: 42px; display: grid; place-items: center; border-radius: 14px; background: rgba(34,197,94,.18); color: #86efac; font-weight: 700; }
.user-name { font-weight: 600; }
.user-role { margin-top: 4px; color: var(--text-soft); font-size: 12px; }
.main-area { min-width: 0; display: grid; gap: 20px; }
.topbar { display: flex; justify-content: space-between; align-items: center; padding: 20px 24px; }
.topbar-title { margin: 0; font-size: 24px; }
.topbar-subtitle { margin: 8px 0 0; color: var(--text-soft); }
.topbar-actions { display: flex; align-items: center; gap: 12px; }
.view-area { min-width: 0; }
@media (max-width: 960px) { .app-layout { grid-template-columns: 1fr; } .sider { min-height: auto; } .topbar { flex-direction: column; align-items: flex-start; gap: 16px; } }
</style>
