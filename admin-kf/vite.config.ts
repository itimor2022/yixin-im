import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'
import AutoImport from 'unplugin-auto-import/vite'
import Components from 'unplugin-vue-components/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'

export default defineConfig({
  plugins: [
    vue(),
    AutoImport({
      resolvers: [ElementPlusResolver()]
    }),
    Components({
      resolvers: [ElementPlusResolver({ importStyle: 'css' })]
    })
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    }
  },
  build: {
    rollupOptions: {
      output: {
        manualChunks(id) {
          if (!id.includes('node_modules')) return

          const normalizedId = id.replace(/\\/g, '/')
          if (normalizedId.includes('/element-plus/es/components/')) {
            const componentName = normalizedId
              .split('/element-plus/es/components/')[1]
              ?.split('/')[0]
            return componentName ? `el-${componentName}` : 'element-plus'
          }
          if (normalizedId.includes('/element-plus/')) return 'element-plus-core'
          if (id.includes('@iconify')) return 'iconify'
          if (id.includes('/vue/') || id.includes('/@vue/')) return 'vue-vendor'

          return 'vendor'
        }
      }
    }
  },
  server: {
    port: 4273,
    host: true
  }
})
