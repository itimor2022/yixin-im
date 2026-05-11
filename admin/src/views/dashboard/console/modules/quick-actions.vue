<!-- 快速操作 -->
<template>
  <div class="art-card p-5 mb-5 max-sm:mb-4">
    <h4 class="text-base font-medium mb-4">快速操作</h4>

    <div class="space-y-3">
      <RouterLink
        v-for="item in actions"
        :key="item.path"
        :to="item.path"
        class="flex items-center p-4 rounded-xl hover:bg-g-100 dark:hover:bg-g-800 transition-colors group"
      >
        <div
          class="size-10 rounded-lg flex-cc transition-transform group-hover:scale-110"
          :class="item.bgClass"
        >
          <ArtSvgIcon :icon="item.icon" class="text-xl text-white" />
        </div>
        <div class="ml-3 flex-1">
          <div class="font-medium">{{ item.title }}</div>
          <p class="text-xs text-g-400 mt-0.5">{{ item.desc }}</p>
        </div>
        <ArtSvgIcon icon="ri:arrow-right-s-line" class="text-xl text-g-400" />
      </RouterLink>
    </div>

    <!-- 系统信息 -->
    <div class="mt-6 pt-4 border-t border-g-200 dark:border-g-700">
      <h5 class="text-sm font-medium text-g-500 mb-3">系统信息</h5>
      <div class="space-y-2 text-sm">
        <div class="flex-cb">
          <span class="text-g-400">系统版本</span>
          <span class="font-medium">{{ systemVersionText }}</span>
        </div>
        <div class="flex-cb">
          <span class="text-g-400">后端状态</span>
          <span class="flex items-center gap-1">
            <span class="size-2 rounded-full bg-green-500"></span>
            <span class="text-green-500">运行中</span>
          </span>
        </div>
        <div class="flex-cb">
          <span class="text-g-400">当前时间</span>
          <span class="font-medium">{{ currentTime }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { getSystemSettings } from '@/api/admin'

  const actions = [
    {
      title: '用户管理',
      desc: '查看和管理所有用户',
      icon: 'ri:user-line',
      path: '/user/list',
      bgClass: 'bg-primary'
    },
    {
      title: '会话管理',
      desc: '管理群组和频道',
      icon: 'ri:chat-3-line',
      path: '/chat/list',
      bgClass: 'bg-success'
    }
  ]

  const currentTime = ref('')
  const systemVersionText = ref('未配置')

  const updateTime = () => {
    const now = new Date()
    currentTime.value = now.toLocaleString('zh-CN', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    })
  }

  const loadSystemVersion = async () => {
    try {
      const settings = await getSystemSettings()
      const systemVersion = settings.system_version?.trim()
      const systemName = settings.system_name?.trim()
      systemVersionText.value = systemVersion
        ? `${systemName || '系统'} v${systemVersion}`
        : '未配置'
    } catch {
      systemVersionText.value = '获取失败'
    }
  }

  onMounted(() => {
    updateTime()
    loadSystemVersion()
    const timer = setInterval(updateTime, 1000)
    onUnmounted(() => clearInterval(timer))
  })
</script>
