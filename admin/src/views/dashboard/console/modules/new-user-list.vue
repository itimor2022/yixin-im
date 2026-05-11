<!-- 最新注册用户列表 -->
<template>
  <div class="art-card p-5 mb-5 max-sm:mb-4">
    <div class="flex-cb mb-4">
      <h4 class="text-base font-medium">最新注册用户</h4>
      <RouterLink to="/user/list" class="text-sm text-primary hover:underline">
        查看全部
      </RouterLink>
    </div>

    <div v-if="loading" class="h-64 flex-cc">
      <ElSkeleton :rows="5" animated />
    </div>

    <div v-else-if="users.length === 0" class="h-64 flex-cc text-g-400"> 暂无用户数据 </div>

    <div v-else class="space-y-3">
      <div
        v-for="user in users"
        :key="user.id"
        class="flex items-center p-3 rounded-lg hover:bg-g-100 dark:hover:bg-g-800 transition-colors"
      >
        <!-- 头像 -->
        <ElImage
          class="size-10 rounded-full flex-shrink-0"
          :src="getAvatarUrl(user.avatar, user.id)"
          fit="cover"
        />

        <!-- 用户信息 -->
        <div class="ml-3 flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <span class="font-medium truncate">{{ user.nickname || user.username }}</span>
            <span v-if="user.isOnline" class="inline-block size-2 rounded-full bg-green-500"></span>
          </div>
          <p class="text-xs text-g-400 truncate">@{{ user.username }}</p>
        </div>

        <!-- 注册时间 -->
        <div class="text-xs text-g-400 flex-shrink-0">
          {{ formatTime(user.createdAt) }}
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

  interface UserItem {
    id: number
    username: string
    nickname: string
    avatar: string | null
    isOnline: boolean
    createdAt: string
  }

  const users = ref<UserItem[]>([])
  const loading = ref(true)

  const loadUsers = async () => {
    try {
      loading.value = true
      const response = await getUserList({ page: 1, page_size: 10 })
      users.value = response.list.map((item) => ({
        id: item.id,
        username: item.username,
        nickname: item.nickname,
        avatar: item.avatar,
        isOnline: item.is_online,
        createdAt: item.created_at
      }))
    } catch (error) {
      console.error('加载用户列表失败:', error)
    } finally {
      loading.value = false
    }
  }

  const formatTime = (timeStr: string) => {
    const date = new Date(timeStr)
    const now = new Date()
    const diff = now.getTime() - date.getTime()
    const minutes = Math.floor(diff / 60000)
    const hours = Math.floor(diff / 3600000)
    const days = Math.floor(diff / 86400000)

    if (minutes < 1) return '刚刚'
    if (minutes < 60) return `${minutes}分钟前`
    if (hours < 24) return `${hours}小时前`
    if (days < 7) return `${days}天前`
    return date.toLocaleDateString()
  }

  onMounted(() => {
    loadUsers()
  })
</script>
