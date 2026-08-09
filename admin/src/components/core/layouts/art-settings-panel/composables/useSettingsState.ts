import { useSettingStore } from '@/store/modules/setting'
import { MenuThemeEnum, MenuTypeEnum } from '@/enums/appEnum'

/**
 * 设置状态管理
 */
export function useSettingsState() {
  const settingStore = useSettingStore()

  // 色弱模式初始化
  const initColorWeak = () => {
    if (settingStore.colorWeak) {
      const el = document.getElementsByTagName('html')[0]
      // 延迟到应用根节点完成初始化后再加类，避免首屏挂载阶段样式竞争。
      setTimeout(() => {
        el.classList.add('color-weak')
      }, 100)
    }
  }

  // 菜单布局切换
  const switchMenuLayouts = (type: MenuTypeEnum) => {
    if (type === MenuTypeEnum.LEFT || type === MenuTypeEnum.TOP_LEFT) {
      settingStore.setMenuOpen(true)
    }
    settingStore.switchMenuLayouts(type)
    if (type === MenuTypeEnum.DUAL_MENU) {
      // 双列菜单依赖设计主题和展开状态，切换布局时同步修正这两个关联设置。
      settingStore.switchMenuStyles(MenuThemeEnum.DESIGN)
      settingStore.setMenuOpen(true)
    }
  }

  return {
    // 方法
    initColorWeak,
    switchMenuLayouts
  }
}
