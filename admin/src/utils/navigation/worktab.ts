/**
 * 工作标签页管理模块
 *
 * 提供工作标签页（Worktab）的自动管理功能
 *
 * ## 主要功能
 *
 * - 根据路由导航自动创建和更新工作标签页
 * - iframe 页面标签页特殊处理
 * - 标签页信息提取（标题、路径、缓存状态等）
 * - 固定标签页支持
 * - 根据系统设置控制标签页显示
 * - 首页标签页特殊处理
 *
 * ## 使用场景
 *
 * - 路由守卫中自动创建标签页
 * - 页面切换时更新标签页状态
 * - 多标签页导航系统
 *
 * @module utils/navigation/worktab
 * @author Art Design Pro Team
 */
import { useWorktabStore } from '@/store/modules/worktab'
import { RouteLocationNormalized } from 'vue-router'
import { isIframe } from './route'
import { useSettingStore } from '@/store/modules/setting'
import { IframeRouteManager } from '@/router/core'
import { useCommon } from '@/hooks/core/useCommon'

// 需要参与缓存白名单的路由名
const CACHE_ROUTE_WHITELIST = new Set([
  'Broadcast',
  'OfficialService',
  'MomentList',
  'TopicList',
  'BannedWordList',
  'RedPacketList',
  'TransferList',
  'UserWalletList',
  'WithdrawList',
  'WalletSettings',
  'RechargeManage',
  'CallList',
  'ReportList',
  'DiscoverList',
  'SystemSettings',
  'SmsGateway',
  'PaymentGateway',
  'EmojiStoreCatalog'
])

const buildTabId = (name: string, path: string, query: Record<string, any> = {}) => {
  const base = name || path
  const queryKeys = Object.keys(query).sort()

  if (queryKeys.length === 0) {
    return String(base)
  }

  const serializedQuery = queryKeys.map((key) => `${key}=${String(query[key] ?? '')}`).join('&')

  return `${base}?${serializedQuery}`
}

/**
 * 根据当前路由信息设置工作标签页（worktab）
 * @param to 当前路由对象
 */
export const setWorktab = (to: RouteLocationNormalized): void => {
  const worktabStore = useWorktabStore()
  const { meta, path, name, params, query } = to
  if (!meta.isHideTab) {
    // 如果是 iframe 页面，则特殊处理工作标签页
    if (isIframe(path)) {
      const iframeRoute = IframeRouteManager.getInstance().findByPath(to.path)

      if (iframeRoute?.meta) {
        worktabStore.openTab({
          tabId: buildTabId(name as string, path, query as Record<string, any>),
          title: iframeRoute.meta.title,
          icon: meta.icon as string,
          path,
          name: name as string,
          keepAlive: CACHE_ROUTE_WHITELIST.has(String(name)),
          params,
          query
        })
      }
    } else if (useSettingStore().showWorkTab || path === useCommon().homePath.value) {
      worktabStore.openTab({
        tabId: buildTabId(name as string, path, query as Record<string, any>),
        title: meta.title as string,
        icon: meta.icon as string,
        path,
        name: name as string,
        keepAlive: CACHE_ROUTE_WHITELIST.has(String(name)),
        params,
        query,
        fixedTab: meta.fixedTab as boolean
      })
    }
  }
}
