import { AppRouteRecord } from '@/types/router'

const commonRoles = ['R_SUPER', 'R_ADMIN', 'R_DEMO']

// 用户与权限
export const userPermissionRoutes: AppRouteRecord = {
  path: '/user-permission',
  name: 'UserPermission',
  component: '/index/index',
  meta: {
    title: '用户与权限',
    icon: 'ri:user-settings-line',
    roles: commonRoles
  },
  children: [
    {
      path: 'users',
      alias: ['/user/list'],
      name: 'UserList',
      component: '/system/user',
      meta: {
        title: '用户列表',
        icon: 'ri:team-line',
        keepAlive: true
      }
    },
    {
      path: 'admins',
      alias: ['/admin-accounts/list', '/system/admins'],
      name: 'AdminAccountManageList',
      component: '/system/admin',
      meta: {
        title: '管理员管理',
        icon: 'ri:admin-line',
        keepAlive: true
      }
    },
    {
      path: 'role-permissions',
      name: 'RolePermissions',
      component: '/system/role-permissions',
      meta: {
        title: '角色权限',
        icon: 'ri:shield-user-line',
        roles: commonRoles,
        keepAlive: true
      }
    },
    {
      path: 'checkin-records',
      name: 'CheckinRecords',
      component: '/system/checkin',
      meta: {
        title: '签到记录',
        icon: 'ri:calendar-check-line',
        keepAlive: true
      }
    }
  ]
}

// 消息与社群
export const messageCommunityRoutes: AppRouteRecord = {
  path: '/message-community',
  name: 'MessageCommunity',
  component: '/index/index',
  meta: {
    title: '消息与社群',
    icon: 'ri:chat-3-line',
    roles: commonRoles
  },
  children: [
    {
      path: 'private-chats',
      alias: ['/chat/list'],
      name: 'ChatList',
      component: '/system/chat',
      meta: {
        title: '私聊列表',
        icon: 'ri:chat-1-line',
        keepAlive: true
      }
    },
    {
      path: 'groups',
      alias: ['/group/manage'],
      name: 'GroupList',
      component: '/group/manage',
      meta: {
        title: '群列表',
        icon: 'ri:group-line',
        keepAlive: true
      }
    },
    {
      path: 'message-search',
      alias: ['/chat/message-search'],
      name: 'MessageSearch',
      component: '/message/search',
      meta: {
        title: '消息搜索',
        icon: 'ri:search-line',
        keepAlive: true
      }
    },
    {
      path: 'calls',
      alias: ['/call/list'],
      name: 'CallList',
      component: '/call/list',
      meta: {
        title: '通话记录',
        icon: 'ri:phone-find-line',
        keepAlive: true
      }
    },
    // {
    //   path: 'official-service',
    //   alias: ['/official-service/index'],
    //   name: 'OfficialService',
    //   component: '/official-service',
    //   meta: {
    //     title: '官方客服',
    //     icon: 'ri:customer-service-2-line',
    //     keepAlive: true
    //   }
    // }
  ]
}

// 内容与风控
export const contentRiskRoutes: AppRouteRecord = {
  path: '/content-risk',
  name: 'ContentRisk',
  component: '/index/index',
  meta: {
    title: '内容与风控',
    icon: 'ri:shield-check-line',
    roles: commonRoles
  },
  children: [
    {
      path: 'moments',
      alias: ['/moment/list'],
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
      alias: ['/moment/topics'],
      name: 'TopicList',
      component: '/moment/topics',
      meta: {
        title: '话题管理',
        icon: 'ri:hashtag',
        keepAlive: true
      }
    },
    {
      path: 'discover-page',
      alias: ['/discover/list'],
      name: 'DiscoverList',
      component: '/discover',
      meta: {
        title: '发现页配置',
        icon: 'ri:compass-discover-line',
        keepAlive: true
      }
    },
    {
      path: 'emoji-store',
      alias: ['/system/emoji-store'],
      name: 'EmojiStoreCatalog',
      component: '/system/emoji-store',
      meta: {
        title: '表情包管理',
        icon: 'ri:emotion-line',
        keepAlive: true
      }
    },
    {
      path: 'reports',
      alias: ['/report/list'],
      name: 'ReportList',
      component: '/system/report',
      meta: {
        title: '举报列表',
        icon: 'ri:error-warning-line',
        keepAlive: true
      }
    },
    {
      path: 'banned-words',
      alias: ['/moment/banned-words'],
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

// 会员与钱包
export const memberWalletRoutes: AppRouteRecord = {
  path: '/member-wallet',
  name: 'MemberWallet',
  component: '/index/index',
  meta: {
    title: '会员与钱包',
    icon: 'ri:vip-crown-2-line',
    roles: commonRoles
  },
  children: [
    {
      path: 'vip',
      alias: ['/vip/index'],
      name: 'VipManageIndex',
      component: '/vip',
      meta: {
        title: '会员管理',
        icon: 'ri:vip-crown-line',
        keepAlive: true
      }
    },
    {
      path: 'user-wallets',
      alias: ['/wallet/user-wallets'],
      name: 'UserWalletList',
      component: '/wallet/user-wallets',
      meta: {
        title: '用户钱包',
        icon: 'ri:bank-card-line',
        keepAlive: true
      }
    },
    {
      path: 'recharge',
      alias: ['/wallet/recharge'],
      name: 'RechargeManage',
      component: '/wallet/recharge',
      meta: {
        title: '充值管理',
        icon: 'ri:bank-card-line',
        keepAlive: true
      }
    },
    {
      path: 'withdraw',
      alias: ['/wallet/withdraw'],
      name: 'WithdrawList',
      component: '/wallet/withdraw',
      meta: {
        title: '提现管理',
        icon: 'ri:money-cny-box-line',
        keepAlive: true
      }
    },
    {
      path: 'red-packets',
      alias: ['/wallet/red-packets'],
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
      alias: ['/wallet/transfers'],
      name: 'TransferList',
      component: '/wallet/transfers',
      meta: {
        title: '转账记录',
        icon: 'ri:exchange-funds-line',
        keepAlive: true
      }
    },
    {
      path: 'wallet-settings',
      alias: ['/wallet/settings'],
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

// 运营触达
export const operationRoutes: AppRouteRecord = {
  path: '/operation',
  name: 'Operation',
  component: '/index/index',
  meta: {
    title: '运营触达',
    icon: 'ri:send-plane-line',
    roles: commonRoles
  },
  children: [
    {
      path: 'broadcast',
      alias: ['/broadcast/index'],
      name: 'Broadcast',
      component: '/broadcast',
      meta: {
        title: '全局公告',
        icon: 'ri:megaphone-line',
        roles: commonRoles,
        keepAlive: true
      }
    },
    {
      path: 'sms-gateway',
      alias: ['/system/sms-gateway'],
      name: 'SmsGateway',
      component: '/system/sms-gateway',
      meta: {
        title: '短信网关',
        icon: 'ri:message-2-line',
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
    roles: commonRoles,
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

// 系统配置
export const systemRoutes: AppRouteRecord = {
  path: '/system',
  name: 'System',
  component: '/index/index',
  meta: {
    title: '系统配置',
    icon: 'ri:settings-3-line',
    roles: commonRoles
  },
  children: [
    {
      path: 'settings',
      name: 'SystemSettings',
      component: '/system/settings',
      meta: {
        title: '基础设置',
        icon: 'ri:settings-4-line',
        keepAlive: true
      }
    },
    {
      path: 'rtc-settings',
      name: 'SystemRTCSettings',
      component: '/system/settings',
      meta: {
        title: '音视频接口',
        icon: 'ri:vidicon-line',
        keepAlive: true
      }
    },
    {
      path: 'feature-settings',
      name: 'SystemFeatureSettings',
      component: '/system/settings',
      meta: {
        title: '客户端功能',
        icon: 'ri:toggle-line',
        keepAlive: true
      }
    },
    {
      path: 'ai-config',
      name: 'SystemAIConfig',
      component: '/system/settings',
      meta: {
        title: 'AI配置',
        icon: 'ri:brain-line',
        keepAlive: true
      }
    },
    {
      path: 'storage-config',
      name: 'SystemStorageConfig',
      component: '/system/settings',
      meta: {
        title: '存储配置',
        icon: 'ri:cloud-line',
        keepAlive: true
      }
    },
    {
      path: 'health',
      name: 'SystemHealth',
      component: '/system/health',
      meta: {
        title: '系统健康',
        icon: 'ri:pulse-line',
        keepAlive: true
      }
    },
    {
      path: 'security',
      name: 'SystemSecurity',
      component: '/system/security',
      meta: {
        title: '安全审计',
        icon: 'ri:shield-keyhole-line',
        keepAlive: true
      }
    },
    {
      path: 'push-report',
      alias: ['/operation/push-report'],
      name: 'PushReport',
      component: '/system/push-report',
      meta: {
        title: '推送报表',
        icon: 'ri:bar-chart-box-line',
        keepAlive: true
      }
    },
    {
      path: 'push-config',
      alias: ['/operation/push-config'],
      name: 'PushConfig',
      component: '/system/push-config',
      meta: {
        title: '推送配置',
        icon: 'ri:notification-3-line',
        keepAlive: true
      }
    },
    {
      path: 'multi-line-entry',
      name: 'MultiLineEntry',
      component: '/system/multi-line-entry',
      meta: {
        title: '多线路入口',
        icon: 'ri:route-line',
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
      path: 'payment-gateway',
      name: 'PaymentGateway',
      component: '/system/payment-gateway',
      meta: {
        title: '支付网关',
        icon: 'ri:bank-line'
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
