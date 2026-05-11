/**
 * 快速入口配置
 * 包含：应用列表、快速链接等配置
 */
import type { FastEnterConfig } from '@/types/config'

const fastEnterConfig: FastEnterConfig = {
  // 显示条件（屏幕宽度）
  minWidth: 1200,
  // 应用列表（只保留核心功能）
  applications: [
    {
      name: '控制台',
      description: '系统概览与数据统计',
      icon: 'ri:pie-chart-line',
      iconColor: '#377dff',
      enabled: true,
      order: 1,
      routeName: 'Console'
    },
    {
      name: '用户管理',
      description: '管理所有用户',
      icon: 'ri:user-line',
      iconColor: '#13DEB9',
      enabled: true,
      order: 2,
      routeName: 'UserList'
    },
    {
      name: '会话管理',
      description: '管理群组和频道',
      icon: 'ri:chat-3-line',
      iconColor: '#ffb100',
      enabled: true,
      order: 3,
      routeName: 'ChatList'
    },
    {
      name: '动态管理',
      description: '管理用户动态',
      icon: 'ri:chat-history-line',
      iconColor: '#ff6b6b',
      enabled: true,
      order: 4,
      routeName: 'MomentList'
    }
  ],
  // 快速链接（只保留核心功能）
  quickLinks: [
    {
      name: '用户管理',
      enabled: true,
      order: 1,
      routeName: 'UserList'
    },
    {
      name: '会话管理',
      enabled: true,
      order: 2,
      routeName: 'ChatList'
    },
    {
      name: '举报管理',
      enabled: true,
      order: 3,
      routeName: 'ReportList'
    }
  ]
}

export default Object.freeze(fastEnterConfig)
