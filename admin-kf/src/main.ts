import { createApp } from 'vue'
import { createPinia } from 'pinia'
import ElementPlus from 'element-plus'
import 'element-plus/dist/index.css'
import App from './App.vue'
import { router } from './router'
import { useSessionStore } from '@/stores/session'
import './styles/index.scss'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(ElementPlus)

const session = useSessionStore(pinia)
session.restore().finally(() => {
  app.use(router)
  app.mount('#app')
})
