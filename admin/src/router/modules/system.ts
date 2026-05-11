import { AppRouteRecord } from '@/types/router'

// 用户管理（顶级菜单）
export const userRoutes: AppRouteRecord = {
  path: '/user',
  name: 'UserManage',
  component: '/index/index',
  meta: {
    title: '用户管理',
    icon: 'ri:user-line',
    roles: ['R_SUPER', 'R_ADMIN', 'R_DEMO']
  },
  children: [
    {
      path: 'list',
      name: 'UserList',
      component: '/system/user',
      meta: {
        title: '用户列表',
        icon: 'ri:team-line',
        keepAlive: true
      }
    }
  ]
}

// 全局公告（顶级菜单）
export const broadcastRoutes: AppRouteRecord = {
  path: '/broadcast',
  name: 'BroadcastManage',
  component: '/index/index',
  meta: {
    title: '全局公告',
    icon: 'ri:megaphone-line',
    roles: ['R_SUPER', 'R_ADMIN']
  },
  children: [
    {
      path: 'index',
      name: 'Broadcast',
      component: '/broadcast',
      meta: {
        title: '发送公告',
        icon: 'ri:notification-3-line',
        keepAlive: true
      }
    }
  ]
}

// 官方客服（顶级菜单）
export const officialServiceRoutes: AppRouteRecord = {
  path: '/official-service',
  name: 'OfficialServiceManage',
  component: '/index/index',
  meta: {
    title: '官方客服',
    icon: 'ri:customer-service-2-line',
    roles: ['R_SUPER', 'R_ADMIN', 'R_DEMO']
  },
  children: [
    {
      path: 'index',
      name: 'OfficialService',
      component: '/official-service',
      meta: {
        title: '官方客服',
        icon: 'ri:user-star-line',
        keepAlive: true
      }
    }
  ]
}

// 会话管理（顶级菜单）
export const chatRoutes: AppRouteRecord = {
  path: '/chat',
  name: 'ChatManage',
  component: '/index/index',
  meta: {
    title: '会话管理',
    icon: 'ri:chat-3-line',
    roles: ['R_SUPER', 'R_ADMIN', 'R_DEMO']
  },
  children: [
    {
      path: 'list',
      name: 'ChatList',
      component: '/system/chat',
      meta: {
        title: '会话列表',
        icon: 'ri:chat-1-line',
        keepAlive: true
      }
    },
    {
      path: 'message-search',
      name: 'MessageSearch',
      component: '/message/search',
      meta: {
        title: '消息搜索',
        icon: 'ri:search-line',
        keepAlive: true
      }
    }
  ]
}

// 动态管理（顶级菜单）
export const momentRoutes: AppRouteRecord = {
  path: '/moment',
  name: 'MomentManage',
  component: '/index/index',
  meta: {
    title: '动态广场',
    icon: 'ri:compass-3-line',
    roles: ['R_SUPER', 'R_ADMIN', 'R_DEMO']
  },
  children: [
    {
      path: 'list',
      name: 'MomentList',
      component: '/moment/list',
      meta: {
        title: '动态管理',
        icon: 'ri:article-line',
        keepAlive: true
      }
    },
    {
      path: 'topics',
      name: 'TopicList',
      component: '/moment/topics',
      meta: {
        title: '话题管理',
        icon: 'ri:hashtag',
        keepAlive: true
      }
    },
    {
      path: 'banned-words',
      name: 'BannedWordList',
      component: '/moment/banned-words',
      meta: {
        title: '违禁词管理',
        icon: 'ri:spam-2-line',
        keepAlive: true
      }
    }
  ]
}

// 钱包管理（顶级菜单）
export const walletRoutes: AppRouteRecord = {
  path: '/wallet',
  name: 'WalletManage',
  component: '/index/index',
  meta: {
    title: '钱包管理',
    icon: 'ri:wallet-3-line',
    roles: ['R_SUPER', 'R_ADMIN', 'R_DEMO']
  },
  children: [
    {
      path: 'membership',
      name: 'MembershipManage',
      component: '/wallet/membership',
      meta: {
        title: '会员管理',
        icon: 'ri:vip-crown-2-line',
        keepAlive: true
      }
    },
    {
      path: 'red-packets',
      name: 'RedPacketList',
      component: '/wallet/red-packets',
      meta: {
        title: '红包记录',
        icon: 'ri:red-packet-line',
        keepAlive: true
      }
    },
    {
      path: 'transfers',
      name: 'TransferList',
      component: '/wallet/transfers',
      meta: {
        title: '转账记录',
        icon: 'ri:exchange-funds-line',
        keepAlive: true
      }
    },
    {
      path: 'user-wallets',
      name: 'UserWalletList',
      component: '/wallet/user-wallets',
      meta: {
        title: '用户钱包',
        icon: 'ri:bank-card-line',
        keepAlive: true
      }
    },
    {
      path: 'withdraw',
      name: 'WithdrawList',
      component: '/wallet/withdraw',
      meta: {
        title: '提现管理',
        icon: 'ri:money-cny-box-line',
        keepAlive: true
      }
    },
    {
      path: 'settings',
      name: 'WalletSettings',
      component: '/wallet/settings',
      meta: {
        title: '钱包设置',
        icon: 'ri:settings-3-line',
        keepAlive: true
      }
    }
  ]
}

// 通话记录管理（顶级菜单）
export const callRoutes: AppRouteRecord = {
  path: '/call',
  name: 'CallManage',
  component: '/index/index',
  meta: {
    title: '通话管理',
    icon: 'ri:phone-line',
    roles: ['R_SUPER', 'R_ADMIN', 'R_DEMO']
  },
  children: [
    {
      path: 'list',
      name: 'CallList',
      component: '/call/list',
      meta: {
        title: '通话记录',
        icon: 'ri:phone-find-line',
        keepAlive: true
      }
    }
  ]
}

// 举报管理（顶级菜单）
export const reportRoutes: AppRouteRecord = {
  path: '/report',
  name: 'ReportManage',
  component: '/index/index',
  meta: {
    title: '举报管理',
    icon: 'ri:alarm-warning-line',
    roles: ['R_SUPER', 'R_ADMIN', 'R_DEMO']
  },
  children: [
    {
      path: 'list',
      name: 'ReportList',
      component: '/system/report',
      meta: {
        title: '举报列表',
        icon: 'ri:error-warning-line',
        keepAlive: true
      }
    }
  ]
}

// 发现管理（顶级菜单）
export const discoverRoutes: AppRouteRecord = {
  path: '/discover',
  name: 'DiscoverManage',
  component: '/index/index',
  meta: {
    title: '发现管理',
    icon: 'ri:compass-discover-line',
    roles: ['R_SUPER', 'R_ADMIN', 'R_DEMO']
  },
  children: [
    {
      path: 'list',
      name: 'DiscoverList',
      component: '/discover',
      meta: {
        title: '发现管理',
        icon: 'ri:apps-2-line',
        keepAlive: true
      }
    }
  ]
}

// 异常页面
export const exceptionRoutes: AppRouteRecord = {
  path: '/exception',
  name: 'Exception',
  component: '/index/index',
  meta: {
    title: '异常页面',
    icon: 'ri:error-warning-line',
    roles: ['R_SUPER', 'R_ADMIN', 'R_DEMO'],
    isHide: true
  },
  children: [
    {
      path: '403',
      name: 'Exception403',
      component: '/exception/403',
      meta: {
        title: '403',
        isHide: true
      }
    },
    {
      path: '404',
      name: 'Exception404',
      component: '/exception/404',
      meta: {
        title: '404',
        isHide: true
      }
    },
    {
      path: '500',
      name: 'Exception500',
      component: '/exception/500',
      meta: {
        title: '500',
        isHide: true
      }
    }
  ]
}

// 系统设置（顶级菜单）
export const systemRoutes: AppRouteRecord = {
  path: '/system',
  name: 'System',
  component: '/index/index',
  meta: {
    title: '系统设置',
    icon: 'ri:settings-3-line',
    roles: ['R_SUPER', 'R_ADMIN', 'R_DEMO']
  },
  children: [
    {
      path: 'settings',
      name: 'SystemSettings',
      component: '/system/settings',
      meta: {
        title: '系统设置',
        icon: 'ri:settings-4-line',
        keepAlive: true
      }
    },
    {
      path: 'hot-update',
      name: 'HotUpdateManage',
      component: '/system/hot-update',
      meta: {
        title: '热更新补丁',
        icon: 'ri:download-cloud-2-line',
        keepAlive: true
      }
    },
    {
      path: 'sms-gateway',
      name: 'SmsGateway',
      component: '/system/sms-gateway',
      meta: {
        title: '短信网关',
        icon: 'ri:message-2-line',
        keepAlive: true
      }
    },
    {
      path: 'payment-gateway',
      name: 'PaymentGateway',
      component: '/system/payment-gateway',
      meta: {
        title: '支付网关',
        icon: 'ri:bank-line'
      }
    },
    {
      path: 'emoji-store',
      name: 'EmojiStoreCatalog',
      component: '/system/emoji-store',
      meta: {
        title: '表情包管理',
        icon: 'ri:emotion-line',
        keepAlive: true
      }
    },
    {
      path: 'user-center',
      name: 'UserCenter',
      component: '/system/user-center',
      meta: {
        title: '个人中心',
        icon: 'ri:user-settings-line',
        isHide: true,
        keepAlive: true,
        isHideTab: true
      }
    }
  ]
}
