import { createRouter, createWebHashHistory } from 'vue-router'
import { useSessionStore } from '@/stores/session'

const routes = [
  {
    path: '/login',
    name: 'Login',
    component: () => import('@/views/login/index.vue'),
    meta: { title: '登录', public: true }
  },
  {
    path: '/',
    component: () => import('@/layouts/app-layout.vue'),
    redirect: '/dashboard',
    children: [
      {
        path: 'dashboard',
        name: 'Dashboard',
        component: () => import('@/views/dashboard/index.vue'),
        meta: { title: '工作台' }
      },
      {
        path: 'invite-code',
        name: 'InviteCode',
        component: () => import('@/views/invite-code/index.vue'),
        meta: { title: '我的邀请码' }
      },
      {
        path: 'welcome-message',
        name: 'WelcomeMessage',
        component: () => import('@/views/welcome-message/index.vue'),
        meta: { title: '欢迎语设置' }
      },
      {
        path: 'invitees',
        name: 'Invitees',
        component: () => import('@/views/invitees/index.vue'),
        meta: { title: '我的用户' }
      },
      {
        path: 'profile',
        name: 'Profile',
        component: () => import('@/views/profile/index.vue'),
        meta: { title: '个人中心' }
      }
    ]
  }
]

export const router = createRouter({
  history: createWebHashHistory(),
  routes
})

router.beforeEach((to) => {
  document.title = `${String(to.meta.title || '')} - 官方客服后台`

  const session = useSessionStore()
  if (!to.meta.public && !session.isLoggedIn) {
    return '/login'
  }

  if (to.path === '/login' && session.isLoggedIn) {
    return '/dashboard'
  }

  return true
})
