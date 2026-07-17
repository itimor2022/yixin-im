import { AppRouteRecord } from '@/types/router'
import { dashboardRoutes } from './dashboard'
import {
  userRoutes,
  chatRoutes,
  momentRoutes,
  walletRoutes,
  callRoutes,
  reportRoutes,
  discoverRoutes,
  systemRoutes,
  broadcastRoutes,
  officialServiceRoutes
} from './system'

/**
 * 锦绣汇后台管理路由
 */
export const routeModules: AppRouteRecord[] = [
  dashboardRoutes,
  userRoutes,
  broadcastRoutes,
  officialServiceRoutes,
  chatRoutes,
  momentRoutes,
  walletRoutes,
  callRoutes,
  reportRoutes,
  discoverRoutes,
  systemRoutes
]
