import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig({
  plugins: [vue()],
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

          if (id.includes('element-plus')) return 'element-plus'
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
