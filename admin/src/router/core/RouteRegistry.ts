/**
 * 路由注册核心类
 *
 * 负责动态路由的注册、验证和管理
 *
 * @module router/core/RouteRegistry
 * @author Art Design Pro Team
 */

import type { Router, RouteRecordRaw } from 'vue-router'
import type { AppRouteRecord } from '@/types/router'
import { ComponentLoader } from './ComponentLoader'
import { RouteValidator } from './RouteValidator'
import { RouteTransformer } from './RouteTransformer'

export class RouteRegistry {
  private router: Router
  private componentLoader: ComponentLoader
  private validator: RouteValidator
  private transformer: RouteTransformer
  private removeRouteFns: (() => void)[] = []
  private registered = false

  constructor(router: Router) {
    this.router = router
    this.componentLoader = new ComponentLoader()
    this.validator = new RouteValidator()
    this.transformer = new RouteTransformer(this.componentLoader)
  }

  /**
   * 注册动态路由
   */
  register(menuList: AppRouteRecord[]): void {
    if (this.registered) {
      const missingRoutes = this.collectMissingRoutes(menuList)

      if (missingRoutes.length === 0) {
        console.warn('[RouteRegistry] 路由已注册，跳过重复注册')
        return
      }

      console.warn(`[RouteRegistry] 动态路由缺失，重新注册: ${missingRoutes.join(', ')}`)
      this.unregister()
    }

    // 验证路由配置
    const validationResult = this.validator.validate(menuList)
    if (!validationResult.valid) {
      throw new Error(`路由配置验证失败: ${validationResult.errors.join(', ')}`)
    }

    // 转换并注册路由
    const removeRouteFns: (() => void)[] = []

    menuList.forEach((route) => {
      if (route.name && !this.router.hasRoute(route.name)) {
        const routeConfig = this.transformer.transform(route)
        const removeRouteFn = this.router.addRoute(routeConfig as RouteRecordRaw)
        removeRouteFns.push(removeRouteFn)
      }
    })

    this.removeRouteFns = removeRouteFns
    this.registered = true

    const missingRoutes = this.collectMissingRoutes(menuList)
    if (missingRoutes.length > 0) {
      console.warn(`[RouteRegistry] 以下动态路由未成功注册: ${missingRoutes.join(', ')}`)
    }
  }

  private collectMissingRoutes(routes: AppRouteRecord[], missingRoutes: string[] = []): string[] {
    routes.forEach((route) => {
      if (this.shouldSkipRouteCheck(route)) {
        return
      }

      if (!this.routeExists(route)) {
        missingRoutes.push(String(route.name || route.path))
      }

      if (route.children?.length) {
        this.collectMissingRoutes(route.children, missingRoutes)
      }
    })

    return missingRoutes
  }

  private shouldSkipRouteCheck(route: AppRouteRecord): boolean {
    if (route.meta?.link && !route.meta?.isIframe) {
      return true
    }

    if (!route.path && !route.name) {
      return true
    }

    return false
  }

  private routeExists(route: AppRouteRecord): boolean {
    if (route.name && this.router.hasRoute(route.name)) {
      return true
    }

    if (!route.path || this.isExternalPath(route.path)) {
      return true
    }

    const path = route.path.startsWith('/') ? route.path : `/${route.path}`
    const resolved = this.router.resolve(path)

    return resolved.matched.some((record) => {
      return record.name !== 'Exception404' && !record.path.includes(':pathMatch')
    })
  }

  private isExternalPath(path: string): boolean {
    return /^https?:\/\//i.test(path)
  }

  /**
   * 移除所有动态路由
   */
  unregister(): void {
    this.removeRouteFns.forEach((fn) => fn())
    this.removeRouteFns = []
    this.registered = false
  }

  /**
   * 检查是否已注册
   */
  isRegistered(): boolean {
    return this.registered
  }

  /**
   * 获取移除函数列表（用于 store 管理）
   */
  getRemoveRouteFns(): (() => void)[] {
    return this.removeRouteFns
  }

  /**
   * 标记为已注册（用于错误处理场景，避免重复请求）
   */
  markAsRegistered(): void {
    this.registered = true
  }
}
