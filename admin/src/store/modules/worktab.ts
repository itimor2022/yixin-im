/**
 * 工作标签页状态管理模块
 *
 * 提供多标签页功能的完整状态管理
 *
 * ## 主要功能
 *
 * - 标签页打开和关闭
 * - 标签页固定和取消固定
 * - 批量关闭（左侧、右侧、其他、全部）
 * - 标签页缓存管理（KeepAlive）
 * - 标签页标题自定义
 * - 标签页路由验证
 * - 动态路由参数处理
 *
 * ## 使用场景
 *
 * - 多标签页导航
 * - 页面缓存控制
 * - 标签页右键菜单
 * - 固定常用页面
 * - 批量关闭标签
 *
 * ## 核心特性
 *
 * - 智能标签页复用（同路由名称复用）
 * - 固定标签页保护（不可关闭）
 * - KeepAlive 缓存排除管理
 * - 路由有效性验证
 * - 首页自动保留
 *
 * ## 持久化
 * - 使用 localStorage 存储
 * - 存储键：sys-v{version}-worktab
 * - 刷新页面保持标签状态
 *
 * @module store/modules/worktab
 * @author Art Design Pro Team
 */
import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { router } from '@/router'
import { LocationQueryRaw, Router, RouteLocationNormalizedLoaded } from 'vue-router'
import { WorkTab } from '@/types'
import { useCommon } from '@/hooks/core/useCommon'

interface WorktabState {
  current: Partial<WorkTab>
  opened: WorkTab[]
}

/**
 * 工作台标签页管理 Store
 */
export const useWorktabStore = defineStore(
  'worktabStore',
  () => {
    // 状态定义
    const current = ref<Partial<WorkTab>>({})
    const opened = ref<WorkTab[]>([])

    const buildTabId = (tab: Pick<WorkTab, 'name' | 'path' | 'query'>): string => {
      const base = tab.name || tab.path
      const query = tab.query || {}
      const queryKeys = Object.keys(query).sort()

      if (queryKeys.length === 0) {
        return String(base)
      }

      const serializedQuery = queryKeys.map((key) => `${key}=${String(query[key] ?? '')}`).join('&')

      return `${base}?${serializedQuery}`
    }

    const normalizeTab = (tab: WorkTab): WorkTab => ({
      ...tab,
      tabId: tab.tabId || buildTabId(tab)
    })

    const resolveTabId = (target: string | Partial<WorkTab>): string => {
      if (typeof target === 'string') return target
      if (target.tabId) return target.tabId
      return buildTabId({
        name: target.name || '',
        path: target.path || '',
        query: target.query
      })
    }

    // 计算属性
    const hasOpenedTabs = computed(() => opened.value.length > 0)
    const hasMultipleTabs = computed(() => opened.value.length > 1)
    const currentTabIndex = computed(() =>
      current.value.tabId ? opened.value.findIndex((tab) => tab.tabId === current.value.tabId) : -1
    )

    /**
     * 获取当前激活 tabId
     */
    const activeTabId = computed(() => current.value.tabId || '')

    /**
     * 获取当前路由对应标签
     */
    const getCurrentTabByRoute = (
      routeLocation: RouteLocationNormalizedLoaded
    ): WorkTab | undefined => {
      const tabId = resolveTabId({
        name: routeLocation.name as string,
        path: routeLocation.path,
        query: routeLocation.query
      })
      return opened.value.find((tab) => tab.tabId === tabId)
    }

    /**
     * 查找标签页索引
     */
    const findTabIndex = (tabId: string): number => {
      return opened.value.findIndex((tab) => tab.tabId === tabId)
    }

    /**
     * 根据路径查找标签页索引
     */
    const findTabIndexByPath = (path: string): number => {
      return opened.value.findIndex((tab) => tab.path === path)
    }

    /**
     * 获取标签页
     */
    const getTab = (tabId: string): WorkTab | undefined => {
      return opened.value.find((tab) => tab.tabId === tabId)
    }

    /**
     * 根据路径获取标签页
     */
    const getTabByPath = (path: string): WorkTab | undefined => {
      return opened.value.find((tab) => tab.path === path)
    }

    /**
     * 检查标签页是否可关闭
     */
    const isTabClosable = (tab: WorkTab): boolean => {
      return !tab.fixedTab
    }

    /**
     * 安全的路由跳转
     */
    const safeRouterPush = (tab: Partial<WorkTab>): void => {
      if (!tab.path) {
        console.warn('尝试跳转到无效路径的标签页')
        return
      }

      try {
        router.push({
          path: tab.path,
          query: tab.query as LocationQueryRaw
        })
      } catch (error) {
        console.error('路由跳转失败:', error)
      }
    }

    /**
     * 打开或激活一个选项卡
     */
    const openTab = (tab: WorkTab): void => {
      if (!tab.path) {
        console.warn('尝试打开无效的标签页')
        return
      }

      const normalizedTab = normalizeTab(tab)
      let existingIndex = findTabIndex(normalizedTab.tabId)

      if (existingIndex === -1 && normalizedTab.path) {
        existingIndex = findTabIndexByPath(normalizedTab.path)
      }

      if (existingIndex === -1) {
        const insertIndex = normalizedTab.fixedTab ? findFixedTabInsertIndex() : opened.value.length

        if (normalizedTab.fixedTab) {
          opened.value.splice(insertIndex, 0, normalizedTab)
        } else {
          opened.value.push(normalizedTab)
        }

        current.value = normalizedTab
      } else {
        const existingTab = opened.value[existingIndex]

        opened.value[existingIndex] = {
          ...existingTab,
          ...normalizedTab,
          tabId: existingTab.tabId || normalizedTab.tabId
        }

        current.value = opened.value[existingIndex]
      }
    }

    /**
     * 查找固定标签页的插入位置
     */
    const findFixedTabInsertIndex = (): number => {
      let insertIndex = 0
      for (let i = 0; i < opened.value.length; i++) {
        if (opened.value[i].fixedTab) {
          insertIndex = i + 1
        } else {
          break
        }
      }
      return insertIndex
    }

    /**
     * 关闭指定的选项卡
     */
    const removeTab = (tabId: string): void => {
      const targetTab = getTab(tabId)
      const targetIndex = findTabIndex(tabId)

      if (targetIndex === -1) {
        console.warn(`尝试关闭不存在的标签页: ${tabId}`)
        return
      }

      if (targetTab && !isTabClosable(targetTab)) {
        console.warn(`尝试关闭固定标签页: ${tabId}`)
        return
      }

      opened.value.splice(targetIndex, 1)

      const { homePath } = useCommon()

      if (!hasOpenedTabs.value) {
        if (targetTab?.path !== homePath.value) {
          current.value = {}
          safeRouterPush({ path: homePath.value })
        }
        return
      }

      if (current.value.tabId === tabId) {
        const newIndex = targetIndex >= opened.value.length ? opened.value.length - 1 : targetIndex
        current.value = opened.value[newIndex]
        safeRouterPush(current.value)
      }
    }

    /**
     * 关闭左侧选项卡
     */
    const removeLeft = (tabId: string): void => {
      const targetIndex = findTabIndex(tabId)

      if (targetIndex === -1) {
        console.warn(`尝试关闭左侧标签页，但目标标签页不存在: ${tabId}`)
        return
      }

      const leftTabs = opened.value.slice(0, targetIndex)
      const closableLeftTabs = leftTabs.filter(isTabClosable)

      if (closableLeftTabs.length === 0) {
        console.warn('左侧没有可关闭的标签页')
        return
      }

      opened.value = opened.value.filter(
        (tab, index) => index >= targetIndex || !isTabClosable(tab)
      )

      const targetTab = getTab(tabId)
      if (targetTab) {
        current.value = targetTab
      }
    }

    /**
     * 关闭右侧选项卡
     */
    const removeRight = (tabId: string): void => {
      const targetIndex = findTabIndex(tabId)

      if (targetIndex === -1) {
        console.warn(`尝试关闭右侧标签页，但目标标签页不存在: ${tabId}`)
        return
      }

      const rightTabs = opened.value.slice(targetIndex + 1)
      const closableRightTabs = rightTabs.filter(isTabClosable)

      if (closableRightTabs.length === 0) {
        console.warn('右侧没有可关闭的标签页')
        return
      }

      opened.value = opened.value.filter(
        (tab, index) => index <= targetIndex || !isTabClosable(tab)
      )

      const targetTab = getTab(tabId)
      if (targetTab) {
        current.value = targetTab
      }
    }

    /**
     * 关闭其他选项卡
     */
    const removeOthers = (tabId: string): void => {
      const targetTab = getTab(tabId)

      if (!targetTab) {
        console.warn(`尝试关闭其他标签页，但目标标签页不存在: ${tabId}`)
        return
      }

      const otherTabs = opened.value.filter((tab) => tab.tabId !== tabId)
      const closableTabs = otherTabs.filter(isTabClosable)

      if (closableTabs.length === 0) {
        console.warn('没有其他可关闭的标签页')
        return
      }

      opened.value = opened.value.filter((tab) => tab.tabId === tabId || !isTabClosable(tab))
      current.value = targetTab
    }

    /**
     * 关闭所有可关闭的标签页
     */
    const removeAll = (): void => {
      const { homePath } = useCommon()
      const hasFixedTabs = opened.value.some((tab) => tab.fixedTab)

      const closableTabs = opened.value.filter((tab) => {
        if (!isTabClosable(tab)) return false
        return hasFixedTabs || tab.path !== homePath.value
      })

      if (closableTabs.length === 0) {
        console.warn('没有可关闭的标签页')
        return
      }

      opened.value = opened.value.filter((tab) => {
        return !isTabClosable(tab) || (!hasFixedTabs && tab.path === homePath.value)
      })

      if (!hasOpenedTabs.value) {
        current.value = {}
        safeRouterPush({ path: homePath.value })
        return
      }

      const homeTab = opened.value.find((tab) => tab.path === homePath.value)
      const targetTab = homeTab || opened.value[0]

      current.value = targetTab
      safeRouterPush(targetTab)
    }

    /**
     * 关闭所有可关闭的标签页
     */
    const toggleFixedTab = (tabId: string): void => {
      const targetIndex = findTabIndex(tabId)

      if (targetIndex === -1) {
        console.warn(`尝试切换不存在标签页的固定状态: ${tabId}`)
        return
      }

      const tab = { ...opened.value[targetIndex] }
      tab.fixedTab = !tab.fixedTab

      opened.value.splice(targetIndex, 1)

      if (tab.fixedTab) {
        const firstNonFixedIndex = opened.value.findIndex((t) => !t.fixedTab)
        const insertIndex = firstNonFixedIndex === -1 ? opened.value.length : firstNonFixedIndex
        opened.value.splice(insertIndex, 0, tab)
      } else {
        const fixedCount = opened.value.filter((t) => t.fixedTab).length
        opened.value.splice(fixedCount, 0, tab)
      }

      if (current.value.tabId === tabId) {
        current.value = tab
      }
    }

    /**
     * 验证工作台标签页的路由有效性
     */
    const validateWorktabs = (routerInstance: Router): void => {
      try {
        // 动态路由校验：优先使用路由 name 判断有效性；否则用 resolve 匹配参数化路径
        const isTabRouteValid = (tab: Partial<WorkTab>): boolean => {
          try {
            if (tab.name) {
              const routes = routerInstance.getRoutes()
              if (routes.some((r) => r.name === tab.name)) return true
            }
            if (tab.path) {
              const resolved = routerInstance.resolve({
                path: tab.path,
                query: (tab.query as LocationQueryRaw) || undefined
              })
              return resolved.matched.length > 0
            }
            return false
          } catch {
            return false
          }
        }

        // 过滤出有效的标签页
        const validTabs = opened.value
          .map((tab) => normalizeTab(tab))
          .filter((tab) => isTabRouteValid(tab))

        if (validTabs.length !== opened.value.length) {
          console.warn('发现无效的标签页路由，已自动清理')
          opened.value = validTabs
        }

        // 验证当前激活标签的有效性
        const isCurrentValid = current.value && isTabRouteValid(current.value)

        if (!isCurrentValid && validTabs.length > 0) {
          console.warn('当前激活标签无效，已自动切换')
          current.value = validTabs[0]
        } else if (!isCurrentValid) {
          current.value = {}
        }
      } catch (error) {
        console.error('验证工作台标签页失败:', error)
      }
    }

    /**
     * 清空所有状态（用于登出等场景）
     */
    const clearAll = (): void => {
      current.value = {}
      opened.value = []
    }

    /**
     * 获取状态快照（用于持久化存储）
     */
    const getStateSnapshot = (): WorktabState => {
      return {
        current: { ...current.value },
        opened: [...opened.value]
      }
    }

    /**
     * 获取标签页标题
     */
    const getTabTitle = (tabId: string): WorkTab | undefined => {
      return getTab(tabId)
    }

    /**
     * 更新标签页标题
     */
    const updateTabTitle = (tabId: string, title: string): void => {
      const tab = getTab(tabId)
      if (tab) {
        tab.customTitle = title
      }
    }

    /**
     * 重置标签页标题
     */
    const resetTabTitle = (tabId: string): void => {
      const tab = getTab(tabId)
      if (tab) {
        tab.customTitle = ''
      }
    }

    return {
      // 状态
      current,
      opened,

      // 计算属性
      hasOpenedTabs,
      hasMultipleTabs,
      activeTabId,
      currentTabIndex,

      // 方法
      openTab,
      removeTab,
      removeLeft,
      removeRight,
      removeOthers,
      removeAll,
      toggleFixedTab,
      validateWorktabs,
      clearAll,
      getStateSnapshot,

      // 工具方法
      findTabIndex,
      findTabIndexByPath,
      getTab,
      getTabByPath,
      getCurrentTabByRoute,
      isTabClosable,
      getTabTitle,
      updateTabTitle,
      resetTabTitle
    }
  },
  {
    persist: {
      key: 'worktab',
      storage: localStorage
    }
  }
)
