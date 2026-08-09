<!-- 控制台 - 真实数据仪表盘 -->
<template>
  <div class="console-page">
    <CardList />

    <PendingTasksCard />

    <ElRow :gutter="16" class="main-grid">
      <!-- 最新注册用户 -->
      <ElCol :sm="24" :lg="12">
        <NewUserList />
      </ElCol>
      <!-- 在线用户 -->
      <ElCol :sm="24" :lg="12">
        <OnlineUserList />
      </ElCol>
    </ElRow>

    <ElRow :gutter="16" class="main-grid">
      <!-- 用户增长趋势 -->
      <ElCol :sm="24" :lg="16">
        <UserGrowthChart />
      </ElCol>
      <!-- 快速操作 -->
      <ElCol :sm="24" :lg="8">
        <QuickActions />
      </ElCol>
    </ElRow>

    <!-- 服务器运行状态 -->
    <ServerStatusCard />
  </div>
</template>

<script setup lang="ts">
  import CardList from './modules/card-list.vue'
  import ServerStatusCard from './modules/server-status-card.vue'
  import NewUserList from './modules/new-user-list.vue'
  import OnlineUserList from './modules/online-user-list.vue'
  import PendingTasksCard from './modules/pending-tasks-card.vue'
  import UserGrowthChart from './modules/user-growth-chart.vue'
  import QuickActions from './modules/quick-actions.vue'

  defineOptions({ name: 'Console' })
</script>

<style scoped lang="scss">
  .console-page {
    padding-bottom: 8px;
  }

  .main-grid {
    margin-bottom: 14px;
  }
</style>
