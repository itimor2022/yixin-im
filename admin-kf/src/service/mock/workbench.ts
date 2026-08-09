import type { ServiceConversation, ServiceMessage } from '@/types/customer-service'

// 工作台 Mock 是模块级固定数据源；API 适配层读取时应克隆，避免页面操作污染后续请求。
export const mockConversations: ServiceConversation[] = [
  {
    id: 'svc-20260714-001',
    queue: 'serving',
    priority: 'urgent',
    customer: {
      id: 'usr-7f0f32aa',
      name: '林晓夏',
      account: 'xiaoxia_2026',
      avatarText: '林',
      phone: '138****5612',
      region: '广东 深圳',
      registeredAt: '2026-04-12 11:08',
      lastActiveAt: '刚刚',
      vipLevel: 'VIP 3',
      balance: '¥ 286.00',
      orderCount: 8,
      totalPaid: '¥ 1,428.00',
      tags: ['高意向', '充值用户'],
      note: '客户关注消息同步稳定性，回复时优先说明处理进度。'
    },
    subject: '消息同步问题',
    lastMessage: '我换了手机以后，有几条聊天记录没有同步过来。',
    lastAt: '10:32',
    unread: 2,
    waitingMinutes: 1,
    agentName: '官方客服小助手',
    channel: 'app'
  },
  {
    id: 'svc-20260714-002',
    queue: 'waiting',
    priority: 'normal',
    customer: {
      id: 'usr-3ac212dd',
      name: '周木',
      account: 'amour_77',
      avatarText: '周',
      phone: '186****2098',
      region: '浙江 杭州',
      registeredAt: '2026-06-03 15:42',
      lastActiveAt: '2 分钟前',
      vipLevel: '普通用户',
      balance: '¥ 0.00',
      orderCount: 1,
      totalPaid: '¥ 12.00',
      tags: ['新用户'],
      note: ''
    },
    subject: '账号登录',
    lastMessage: '验证码一直收不到，能帮我看一下吗？',
    lastAt: '10:29',
    unread: 1,
    waitingMinutes: 4,
    channel: 'app'
  },
  {
    id: 'svc-20260714-003',
    queue: 'serving',
    priority: 'normal',
    customer: {
      id: 'usr-9bc189ke',
      name: '晚风',
      account: 'wanfeng_91',
      avatarText: '晚',
      phone: '159****8821',
      region: '四川 成都',
      registeredAt: '2026-05-18 09:15',
      lastActiveAt: '5 分钟前',
      vipLevel: 'VIP 1',
      balance: '¥ 58.00',
      orderCount: 3,
      totalPaid: '¥ 198.00',
      tags: ['企业用户'],
      note: '需要开具企业抬头发票。'
    },
    subject: '充值发票',
    lastMessage: '好的，我稍后把开票信息发过来。',
    lastAt: '10:25',
    unread: 0,
    waitingMinutes: 0,
    agentName: '官方客服小助手',
    channel: 'web'
  },
  {
    id: 'svc-20260713-018',
    queue: 'follow_up',
    priority: 'normal',
    customer: {
      id: 'usr-2de771ab',
      name: '陈先生',
      account: 'chen_2025',
      avatarText: '陈',
      phone: '137****3011',
      region: '江苏 苏州',
      registeredAt: '2025-12-09 18:30',
      lastActiveAt: '昨天',
      vipLevel: 'VIP 2',
      balance: '¥ 110.00',
      orderCount: 6,
      totalPaid: '¥ 876.00',
      tags: ['待回访'],
      note: '等待技术侧确认 Windows 客户端升级结果。'
    },
    subject: '客户端升级',
    lastMessage: '问题已经记录，确认后第一时间回复您。',
    lastAt: '昨天',
    unread: 0,
    waitingMinutes: 0,
    agentName: '官方客服小助手',
    channel: 'app'
  },
  {
    id: 'svc-20260712-011',
    queue: 'closed',
    priority: 'normal',
    customer: {
      id: 'usr-89aa122c',
      name: '方晴',
      account: 'qing_818',
      avatarText: '方',
      phone: '188****6767',
      region: '上海',
      registeredAt: '2026-01-27 12:16',
      lastActiveAt: '2 天前',
      vipLevel: '普通用户',
      balance: '¥ 6.00',
      orderCount: 2,
      totalPaid: '¥ 36.00',
      tags: ['已解决'],
      note: ''
    },
    subject: '好友添加',
    lastMessage: '已经可以正常添加了，谢谢。',
    lastAt: '周日',
    unread: 0,
    waitingMinutes: 0,
    agentName: '官方客服小助手',
    channel: 'app'
  }
]

export const mockMessages: Record<string, ServiceMessage[]> = {
  // 消息按会话 ID 建索引，模拟真实接口以 conversation.id 作为查询边界。
  'svc-20260714-001': [
    { id: 'm-001', sender: 'system', content: '客户从 App 内“帮助与客服”发起咨询', time: '10:24' },
    { id: 'm-002', sender: 'customer', content: '你好，我换了一台新手机，登录后发现聊天记录不全。', time: '10:25' },
    { id: 'm-003', sender: 'agent', content: '您好，我来帮您核查。请问旧手机现在还能正常登录吗？', time: '10:26', status: 'sent' },
    { id: 'm-004', sender: 'customer', content: '可以登录，主要是昨天晚上的几条消息没看到。', time: '10:27' },
    { id: 'm-005', sender: 'ai', content: '建议先确认两台设备的网络状态和客户端版本，再核对该账号的消息同步时间。', time: '10:28' },
    { id: 'm-006', sender: 'agent', content: '收到，请先不要退出旧设备。我正在查询同步状态，大约需要 2 分钟。', time: '10:30', status: 'sent' },
    { id: 'm-007', sender: 'customer', content: '好的。', time: '10:31' },
    { id: 'm-008', sender: 'customer', content: '我换了手机以后，有几条聊天记录没有同步过来。', time: '10:32' }
  ],
  'svc-20260714-002': [
    { id: 'm-101', sender: 'system', content: '客户从 App 登录页发起咨询', time: '10:28' },
    { id: 'm-102', sender: 'customer', content: '验证码一直收不到，能帮我看一下吗？', time: '10:29' }
  ],
  'svc-20260714-003': [
    { id: 'm-201', sender: 'customer', content: '充值记录可以开发票吗？', time: '10:20' },
    { id: 'm-202', sender: 'agent', content: '可以的，请提供发票抬头、税号和接收邮箱。', time: '10:22', status: 'sent' },
    { id: 'm-203', sender: 'customer', content: '好的，我稍后把开票信息发过来。', time: '10:25' }
  ],
  'svc-20260713-018': [
    { id: 'm-301', sender: 'customer', content: 'Windows 端升级后还是偶尔会闪退。', time: '昨天 16:12' },
    { id: 'm-302', sender: 'agent', content: '问题已经记录，确认后第一时间回复您。', time: '昨天 16:18', status: 'sent' }
  ],
  'svc-20260712-011': [
    { id: 'm-401', sender: 'customer', content: '已经可以正常添加了，谢谢。', time: '周日 11:02' },
    { id: 'm-402', sender: 'system', content: '会话已由官方客服小助手关闭', time: '周日 11:06' }
  ]
}

export const mockQuickReplies = [
  '您好，我正在为您核查，请稍等。',
  '问题已经记录，处理完成后会第一时间通知您。',
  '感谢您的反馈，请问还有其他需要帮助的吗？'
]
