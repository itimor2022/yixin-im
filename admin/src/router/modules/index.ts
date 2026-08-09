import { AppRouteRecord } from '@/types/router'
import { dashboardRoutes } from './dashboard'
import {
  userPermissionRoutes,
  messageCommunityRoutes,
  contentRiskRoutes,
  memberWalletRoutes,
  operationRoutes,
  systemRoutes,
} from './system'

/**
 * 通用IM后台管理路由
 */
export const routeModules: AppRouteRecord[] = [
  dashboardRoutes,
  userPermissionRoutes,
  messageCommunityRoutes,
  contentRiskRoutes,
  memberWalletRoutes,
  operationRoutes,
  systemRoutes
]
