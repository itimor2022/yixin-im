<!-- 控制台 - 真实数据仪表盘 -->
<template>
  <div>
    <!-- 统计卡片 -->
    <CardList />
    <ServerStatusCard />

    <ElRow :gutter="20">
      <!-- 最新注册用户 -->
      <ElCol :sm="24" :lg="12">
        <NewUserList />
      </ElCol>
      <!-- 在线用户 -->
      <ElCol :sm="24" :lg="12">
        <OnlineUserList />
      </ElCol>
    </ElRow>

    <ElRow :gutter="20">
      <!-- 用户增长趋势 -->
      <ElCol :sm="24" :lg="16">
        <UserGrowthChart />
      </ElCol>
      <!-- 快速操作 -->
      <ElCol :sm="24" :lg="8">
        <QuickActions />
      </ElCol>
    </ElRow>
  </div>
</template>

<script setup lang="ts">
  import CardList from './modules/card-list.vue'
  import ServerStatusCard from './modules/server-status-card.vue'
  import NewUserList from './modules/new-user-list.vue'
  import OnlineUserList from './modules/online-user-list.vue'
  import UserGrowthChart from './modules/user-growth-chart.vue'
  import QuickActions from './modules/quick-actions.vue'

  defineOptions({ name: 'Console' })
</script>
