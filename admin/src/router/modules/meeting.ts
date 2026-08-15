import { AppRouteRecord } from '@/types/router'

// 会议管理（顶级菜单）
export const meetingRoutes: AppRouteRecord = {
  path: '/meeting',
  name: 'Meeting',
  component: '/index/index',
  meta: {
    title: '会议管理',
    icon: 'ri:vidicon-line',
    roles: ['R_SUPER', 'R_ADMIN', 'R_DEMO']
  },
  children: [
    {
      path: 'settings',
      name: 'MeetingSettings',
      component: '/meeting/settings',
      meta: {
        title: '会议设置',
        icon: 'ri:settings-3-line',
        keepAlive: true
      }
    },
    {
      path: 'list',
      name: 'MeetingList',
      component: '/meeting/list',
      meta: {
        title: '会议列表',
        icon: 'ri:calendar-event-line',
        keepAlive: true
      }
    }
  ]
}
