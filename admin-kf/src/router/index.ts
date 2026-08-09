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
    redirect: '/workbench',
    children: [
      {
        path: 'workbench',
        name: 'Workbench',
        component: () => import('@/views/workbench/index.vue'),
        meta: { title: '实时接待', description: '处理排队会话、客户咨询与跟进任务' }
      },
      {
        path: 'dashboard',
        name: 'Dashboard',
        component: () => import('@/views/dashboard/index.vue'),
        meta: { title: '数据概览', description: '查看邀请与服务运营数据' }
      },
      {
        path: 'customers',
        name: 'Customers',
        component: () => import('@/views/customers/index.vue'),
        meta: { title: '客户管理', description: '管理客户标签、备注与跟进信息' }
      },
      {
        path: 'quick-replies',
        name: 'QuickReplies',
        component: () => import('@/views/quick-replies/index.vue'),
        meta: { title: '快捷回复', description: '维护客服团队常用回复内容' }
      },
      {
        path: 'knowledge',
        name: 'Knowledge',
        component: () => import('@/views/knowledge/index.vue'),
        meta: { title: 'AI 知识库', description: '管理 FAQ、业务文档与未命中问题' }
      },
      {
        path: 'reports',
        name: 'Reports',
        component: () => import('@/views/reports/index.vue'),
        meta: { title: '数据报表', description: '分析响应效率、服务质量与解决率' }
      },
      {
        path: 'invite-code',
        name: 'InviteCode',
        component: () => import('@/views/invite-code/index.vue'),
        meta: { title: '我的邀请码', description: '复制个人邀请码与专属注册链接' }
      },
      {
        path: 'welcome-message',
        name: 'WelcomeMessage',
        component: () => import('@/views/welcome-message/index.vue'),
        meta: { title: '欢迎语', description: '配置新客户首次咨询时收到的欢迎内容' }
      },
      {
        path: 'invitees',
        name: 'Invitees',
        component: () => import('@/views/invitees/index.vue'),
        meta: { title: '邀请用户', description: '查看通过邀请码注册的客户' }
      },
      {
        path: 'profile',
        name: 'Profile',
        component: () => import('@/views/profile/index.vue'),
        meta: { title: '个人中心', description: '维护客服账号与安全设置' }
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

  // isLoggedIn 在启动阶段已由 session.restore 校验，不只是“本地存在 Token”的弱判断。
  const session = useSessionStore()
  if (!to.meta.public && !session.isLoggedIn) {
    return '/login'
  }

  if (to.path === '/login' && session.isLoggedIn) {
    return '/workbench'
  }

  return true
})
