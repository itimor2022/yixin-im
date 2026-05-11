<template>
  <ElRow :gutter="20" class="flex">
    <ElCol v-for="(item, index) in dataList" :key="index" :sm="12" :md="6" :lg="6">
      <div class="art-card relative flex flex-col justify-center h-35 px-5 mb-5 max-sm:mb-4">
        <span class="text-g-700 text-sm">{{ item.des }}</span>
        <ArtCountTo class="text-[26px] font-medium mt-2" :target="item.num" :duration="1300" />
        <div class="flex-c mt-1" v-if="item.subText">
          <span class="text-xs text-g-600">{{ item.subText }}</span>
          <span
            v-if="item.change"
            class="ml-1 text-xs font-semibold"
            :class="[item.change.indexOf('+') === -1 ? 'text-danger' : 'text-success']"
          >
            {{ item.change }}
          </span>
        </div>
        <div
          class="absolute top-0 bottom-0 right-5 m-auto size-12.5 rounded-xl flex-cc"
          :class="item.bgClass || 'bg-theme/10'"
        >
          <ArtSvgIcon :icon="item.icon" class="text-xl" :class="item.iconClass || 'text-theme'" />
        </div>
      </div>
    </ElCol>
  </ElRow>
</template>

<script setup lang="ts">
  import { ElMessage } from 'element-plus'
  import { getDashboardStats } from '@/api/admin'

  interface CardDataItem {
    des: string
    icon: string
    num: number
    subText?: string
    change?: string
    bgClass?: string
    iconClass?: string
  }

  /**
   * 数据统计卡片
   */
  const dataList = reactive<CardDataItem[]>([
    {
      des: '总用户数',
      icon: 'ri:user-line',
      num: 0,
      subText: '今日新增',
      change: '+0',
      bgClass: 'bg-primary/10',
      iconClass: 'text-primary'
    },
    {
      des: '在线用户',
      icon: 'ri:user-follow-line',
      num: 0,
      subText: '当前活跃',
      bgClass: 'bg-success/10',
      iconClass: 'text-success'
    },
    {
      des: '群组数量',
      icon: 'ri:group-line',
      num: 0,
      bgClass: 'bg-warning/10',
      iconClass: 'text-warning'
    },
    {
      des: '频道数量',
      icon: 'ri:broadcast-line',
      num: 0,
      bgClass: 'bg-danger/10',
      iconClass: 'text-danger'
    }
  ])

  // 加载统计数据
  const loadStats = async () => {
    try {
      const stats = await getDashboardStats()

      // 更新数据
      dataList[0].num = stats.total_users
      dataList[0].change = stats.new_users_today > 0 ? `+${stats.new_users_today}` : '0'

      dataList[1].num = stats.online_users

      dataList[2].num = stats.total_groups

      dataList[3].num = stats.total_channels
    } catch (error) {
      console.error('加载统计数据失败:', error)
      ElMessage.error('加载统计数据失败')
    }
  }

  onMounted(() => {
    loadStats()
    // 每30秒刷新一次
    const timer = setInterval(loadStats, 30000)
    onUnmounted(() => clearInterval(timer))
  })
</script>
