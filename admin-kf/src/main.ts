import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import { router } from './router'
import { useSessionStore } from '@/stores/session'
import './styles/index.scss'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)

const session = useSessionStore(pinia)
// 先用持久化 Token 校验并恢复客服资料，再挂载路由，避免首屏守卫把有效会话误判为未登录。
// restore 无论成功或失败都会结束：失败时 Store 已清空失效 Token，随后由守卫跳转登录页。
session.restore().finally(() => {
  app.use(router)
  app.mount('#app')
})
