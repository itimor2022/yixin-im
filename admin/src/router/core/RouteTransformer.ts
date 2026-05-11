/**
 * 路由转换器
 *
 * 负责将菜单数据转换为 Vue Router 路由配置
 *
 * @module router/core/RouteTransformer
 * @author Art Design Pro Team
 */

import type { RouteRecordRaw } from 'vue-router'
import type { AppRouteRecord } from '@/types/router'
import { ComponentLoader } from './ComponentLoader'
import { IframeRouteManager } from './IframeRouteManager'

interface ConvertedRoute extends Omit<RouteRecordRaw, 'children'> {
  id?: number
  children?: ConvertedRoute[]
  component?: RouteRecordRaw['component'] | (() => Promise<any>)
}

export class RouteTransformer {
  private componentLoader: ComponentLoader
  private iframeManager: IframeRouteManager

  constructor(componentLoader: ComponentLoader) {
    this.componentLoader = componentLoader
    this.iframeManager = IframeRouteManager.getInstance()
  }

  /**
   * 转换路由配置
   */
  transform(route: AppRouteRecord, depth = 0): ConvertedRoute {
    const { component, children, ...routeConfig } = route

    // 基础路由配置
    const converted: ConvertedRoute = {
      ...routeConfig,
      component: undefined
    }

    // 处理不同类型的路由
    if (route.meta.isIframe) {
      this.handleIframeRoute(converted, route, depth)
    } else if (this.isTopLevelDirectoryRoute(route, depth)) {
      this.handleTopLevelDirectoryRoute(converted, route)
    } else if (this.isFirstLevelRoute(route, depth)) {
      this.handleFirstLevelRoute(converted, route, component as string)
    } else {
      this.handleNormalRoute(converted, component as string)
    }

    // 递归处理子路由
    if (children?.length) {
      converted.children = children.map((child) => this.transform(child, depth + 1))
    }

    return converted
  }

  /**
   * 判断是否为顶级目录路由（自身不渲染页面，只承载子菜单）
   */
  private isTopLevelDirectoryRoute(route: AppRouteRecord, depth: number): boolean {
    return depth === 0 && Array.isArray(route.children) && route.children.length > 0
  }

  /**
   * 判断是否为一级路由（需要 Layout 包裹）
   */
  private isFirstLevelRoute(route: AppRouteRecord, depth: number): boolean {
    return depth === 0 && (!route.children || route.children.length === 0)
  }

  /**
   * 处理 iframe 类型路由
   */
  private handleIframeRoute(
    targetRoute: ConvertedRoute,
    sourceRoute: AppRouteRecord,
    depth: number
  ): void {
    if (depth === 0) {
      // 顶级 iframe：用 Layout 包裹
      targetRoute.component = this.componentLoader.loadLayout()
      targetRoute.path = this.extractFirstSegment(sourceRoute.path || '')
      targetRoute.name = ''

      targetRoute.children = [
        {
          ...sourceRoute,
          component: this.componentLoader.loadIframe()
        } as ConvertedRoute
      ]
    } else {
      // 非顶级（嵌套）iframe：直接使用 Iframe.vue
      targetRoute.component = this.componentLoader.loadIframe()
    }

    // 记录 iframe 路由
    this.iframeManager.add(sourceRoute)
  }

  /**
   * 处理顶级目录路由
   * 顶级目录自身使用 Layout，子菜单继续递归转换成真实页面路由
   */
  private handleTopLevelDirectoryRoute(converted: ConvertedRoute, route: AppRouteRecord): void {
    converted.component = this.componentLoader.loadLayout()

    const firstChildPath = this.findFirstVisibleChildPath(route.children || [])
    if (firstChildPath) {
      converted.redirect = firstChildPath
    }
  }

  /**
   * 查找第一个可见子菜单路径
   */
  private findFirstVisibleChildPath(routes: AppRouteRecord[]): string {
    for (const route of routes) {
      if (route.meta?.isHide) continue

      if (route.children?.length) {
        const childPath = this.findFirstVisibleChildPath(route.children)
        if (childPath) return childPath
      }

      if (route.path) {
        return route.path
      }
    }

    return ''
  }

  /**
   * 处理一级菜单路由
   */
  private handleFirstLevelRoute(
    converted: ConvertedRoute,
    route: AppRouteRecord,
    component: string | undefined
  ): void {
    converted.component = this.componentLoader.loadLayout()
    converted.path = this.extractFirstSegment(route.path || '')
    converted.name = ''
    route.meta.isFirstLevel = true

    converted.children = [
      {
        ...route,
        component: component ? this.componentLoader.load(component) : undefined
      } as ConvertedRoute
    ]
  }

  /**
   * 处理普通路由
   */
  private handleNormalRoute(converted: ConvertedRoute, component: string | undefined): void {
    if (component) {
      converted.component = this.componentLoader.load(component)
    }
  }

  /**
   * 提取路径的第一段
   */
  private extractFirstSegment(path: string): string {
    const segments = path.split('/').filter(Boolean)
    return segments.length > 0 ? `/${segments[0]}` : '/'
  }
}
