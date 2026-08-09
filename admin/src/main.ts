import App from './App.vue'
import { createApp } from 'vue'
import { initStore } from './store'                 // Store
import { initRouter } from './router'               // Router
import language from './locales'                    // 国际化
import '@styles/core/tailwind.css'                  // tailwind
import '@styles/index.scss'                         // 样式
import '@utils/sys/console.ts'                      // 控制台输出内容
import { setupGlobDirectives } from './directives'
import { setupErrorHandle } from './utils/sys/error-handle'
import { installRuntimeFingerprint } from './utils/sys/runtime-fingerprint'

document.addEventListener(
  'touchstart',
  function () {},
  { passive: false }
)

const app = createApp(App)
// Store 必须先于路由安装：路由守卫在首次导航时会直接读取登录态、菜单和系统设置。
initStore(app)
initRouter(app)
setupGlobDirectives(app)
setupErrorHandle(app)

app.use(language)
app.mount('#app')
// 指纹依赖已挂载后的浏览器运行环境，仅用于运行时诊断，不参与应用初始化。
installRuntimeFingerprint()
