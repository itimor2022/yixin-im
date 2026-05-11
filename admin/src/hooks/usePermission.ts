/**
 * 权限检查 Hook
 *
 * 用于检查当前用户是否有权限执行某些操作
 */
import { computed } from 'vue'
import { useUserStore } from '@/store/modules/user'

export function usePermission() {
  const userStore = useUserStore()

  /**
   * 是否是演示管理员（只能查看，不能操作）
   */
  const isDemoAdmin = computed(() => {
    const roles = userStore.info?.roles || []
    return roles.includes('R_DEMO')
  })

  /**
   * 是否是超级管理员
   */
  const isSuperAdmin = computed(() => {
    const roles = userStore.info?.roles || []
    return roles.includes('R_SUPER')
  })

  /**
   * 是否可以执行写操作（非演示管理员）
   */
  const canWrite = computed(() => !isDemoAdmin.value)

  return {
    isDemoAdmin,
    isSuperAdmin,
    canWrite
  }
}
