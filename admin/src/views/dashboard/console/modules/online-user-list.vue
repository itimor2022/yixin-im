<!-- 在线用户列表 -->
<template>
  <div class="art-card p-5 mb-5 max-sm:mb-4">
    <div class="flex-cb mb-4">
      <div class="flex items-center gap-2">
        <h4 class="text-base font-medium">在线用户</h4>
        <span
          class="px-2 py-0.5 text-xs rounded-full bg-green-100 text-green-600 dark:bg-green-900 dark:text-green-400"
        >
          {{ users.length }} 人在线
        </span>
      </div>
      <ElButton size="small" @click="loadUsers" :loading="loading">
        <ArtSvgIcon icon="ri:refresh-line" class="mr-1" />
        刷新
      </ElButton>
    </div>

    <div v-if="loading" class="h-64 flex-cc">
      <ElSkeleton :rows="5" animated />
    </div>

    <div v-else-if="users.length === 0" class="h-64 flex-cc flex-col text-g-400">
      <ArtSvgIcon icon="ri:user-unfollow-line" class="text-4xl mb-2" />
      <span>暂无在线用户</span>
    </div>

    <div v-else class="space-y-3 max-h-80 overflow-y-auto">
      <div
        v-for="user in users"
        :key="user.id"
        class="flex items-center p-3 rounded-lg hover:bg-g-100 dark:hover:bg-g-800 transition-colors"
      >
        <!-- 头像 + 在线状态 -->
        <div class="relative flex-shrink-0">
          <ElImage
            class="size-10 rounded-full"
            :src="getAvatarUrl(user.avatar, user.id)"
            fit="cover"
          />
          <span
            class="absolute bottom-0 right-0 size-3 bg-green-500 rounded-full border-2 border-white dark:border-g-900"
          ></span>
        </div>

        <!-- 用户信息 -->
        <div class="ml-3 flex-1 min-w-0">
          <div class="font-medium truncate">{{ user.nickname || user.username }}</div>
          <p class="text-xs text-g-400 truncate">{{ user.deviceName || '未知设备' }}</p>
        </div>

        <!-- 设备类型图标 -->
        <div class="flex-shrink-0">
          <ElTooltip :content="`IP: ${user.deviceIp || '未知'}`" placement="top">
            <div class="p-2 rounded-lg bg-g-100 dark:bg-g-800">
              <ArtSvgIcon :icon="getDeviceIcon(user.deviceType)" class="text-lg text-g-500" />
            </div>
          </ElTooltip>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { getUserList } from '@/api/admin'
  import { fixImageUrl } from '@/utils/url'

  // 获取头像URL
  const getAvatarUrl = (avatar: string | null, id: number): string => {
    if (avatar) {
      return fixImageUrl(avatar)
    }
    return `https://api.dicebear.com/7.x/avataaars/svg?seed=${id}`
  }

  interface OnlineUser {
    id: number
    username: string
    nickname: string
    avatar: string | null
    deviceType: string | null
    deviceName: string | null
    deviceIp: string | null
  }

  const users = ref<OnlineUser[]>([])
  const loading = ref(true)

  const loadUsers = async () => {
    try {
      loading.value = true
      const response = await getUserList({ page: 1, page_size: 50, online_only: true })
      users.value = response.list.map((item) => ({
        id: item.id,
        username: item.username,
        nickname: item.nickname,
        avatar: item.avatar,
        deviceType: item.device_type,
        deviceName: item.device_name,
        deviceIp: item.device_ip
      }))
    } catch (error) {
      console.error('加载在线用户失败:', error)
    } finally {
      loading.value = false
    }
  }

  const getDeviceIcon = (deviceType: string | null) => {
    const type = deviceType?.toLowerCase() || ''
    if (type.includes('ios') || type.includes('iphone')) return 'ri:apple-line'
    if (type.includes('android')) return 'ri:android-line'
    if (type.includes('mac')) return 'ri:macbook-line'
    if (type.includes('windows')) return 'ri:windows-line'
    if (type.includes('web')) return 'ri:global-line'
    return 'ri:smartphone-line'
  }

  onMounted(() => {
    loadUsers()
    // 每10秒刷新一次，保持接近实时
    const timer = setInterval(loadUsers, 10000)
    onUnmounted(() => clearInterval(timer))
  })
</script>
