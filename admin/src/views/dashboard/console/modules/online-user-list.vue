<!-- 在线用户列表 -->
<template>
  <div class="art-card ops-panel" v-loading="loading">
    <div class="panel-head">
      <div>
        <div class="title-line">
          <h4>在线用户</h4>
          <ElTag type="success" size="small" effect="plain">{{ users.length }} 人在线</ElTag>
        </div>
        <p>设备、IP 与最近活跃状态</p>
      </div>
      <ElButton size="small" text :loading="loading" @click="loadUsers">
        <ArtSvgIcon icon="ri:refresh-line" />
      </ElButton>
    </div>

    <div class="online-summary">
      <div>
        <span class="summary-value">{{ users.length }}</span>
        <span class="summary-label">当前在线</span>
      </div>
      <div>
        <span class="summary-value">{{ androidCount }}</span>
        <span class="summary-label">Android</span>
      </div>
      <div>
        <span class="summary-value">{{ otherDeviceCount }}</span>
        <span class="summary-label">其它端</span>
      </div>
    </div>

    <div v-if="users.length === 0 && !loading" class="empty-state">暂无在线用户</div>

    <div v-else class="online-list">
      <div v-for="row in users.slice(0, 8)" :key="row.id" class="online-row">
        <div class="user-cell">
          <div class="avatar-wrap">
            <ElImage class="avatar" :src="getAvatarUrl(row.avatar, row.id)" fit="cover" lazy />
            <span class="online-dot"></span>
          </div>
          <div class="min-w-0">
            <div class="name-line truncate">{{ row.nickname || row.username }}</div>
            <div class="sub-line">@{{ row.username }}</div>
          </div>
        </div>
        <div class="device-cell">
          <ArtSvgIcon :icon="getDeviceIcon(row.device_type)" />
          <span class="truncate">{{ row.device_name || deviceTypeText(row.device_type) }}</span>
        </div>
        <div class="ip-cell">{{ row.device_ip || '-' }}</div>
        <div class="time-text">{{ formatTime(row.last_seen) }}</div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
  import { getUserList } from '@/api/admin'
  import type { UserListItem } from '@/api/admin'
  import { fixImageUrl, getLocalAvatarDataUrl } from '@/utils/url'

  const users = ref<UserListItem[]>([])
  const loading = ref(true)

  const androidCount = computed(() => {
    return users.value.filter((item) => (item.device_type || '').toLowerCase().includes('android')).length
  })

  const otherDeviceCount = computed(() => Math.max(users.value.length - androidCount.value, 0))

  const getAvatarUrl = (avatar: string | null, id: number): string => {
    if (avatar) return fixImageUrl(avatar)
    return getLocalAvatarDataUrl(id)
  }

  const loadUsers = async () => {
    try {
      loading.value = true
      const response = await getUserList({ page: 1, page_size: 30, online_only: true })
      users.value = response.list
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

  const deviceTypeText = (deviceType: string | null) => {
    return deviceType || '未知设备'
  }

  const formatTime = (timeStr?: string | null) => {
    if (!timeStr) return '在线'
    const date = new Date(timeStr)
    const now = new Date()
    const diff = now.getTime() - date.getTime()
    const minutes = Math.floor(diff / 60000)
    const hours = Math.floor(diff / 3600000)

    if (minutes < 1) return '刚刚'
    if (minutes < 60) return `${minutes}分钟前`
    if (hours < 24) return `${hours}小时前`
    return date.toLocaleDateString()
  }

  onMounted(() => {
    loadUsers()
    const timer = setInterval(loadUsers, 10000)
    onUnmounted(() => clearInterval(timer))
  })
</script>

<style scoped lang="scss">
  .ops-panel {
    padding: 0;
    margin-bottom: 0;
    overflow: hidden;
    border: 1px solid var(--el-border-color-lighter);
    border-radius: 8px;
  }

  .panel-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    padding: 16px 18px 12px;
    border-bottom: 1px solid var(--el-border-color-lighter);
  }

  .title-line {
    display: flex;
    align-items: center;
    gap: 8px;

    h4 {
      margin: 0;
      font-size: 15px;
      font-weight: 600;
      color: var(--el-text-color-primary);
    }
  }

  .panel-head p {
    margin: 3px 0 0;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .online-summary {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 0;
    border-bottom: 1px solid var(--el-border-color-lighter);
    background: var(--el-fill-color-extra-light);

    > div {
      padding: 12px 18px;
      border-right: 1px solid var(--el-border-color-lighter);

      &:last-child {
        border-right: 0;
      }
    }
  }

  .summary-value {
    display: block;
    font-size: 20px;
    font-weight: 650;
    line-height: 1;
    color: var(--el-text-color-primary);
  }

  .summary-label {
    display: block;
    margin-top: 5px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .online-list {
    min-height: 229px;
  }

  .online-row {
    display: grid;
    grid-template-columns: minmax(160px, 1.2fr) minmax(140px, 1fr) minmax(88px, 0.7fr) 82px;
    align-items: center;
    gap: 12px;
    min-height: 52px;
    padding: 9px 18px;
    border-bottom: 1px solid var(--el-border-color-extra-light);

    &:last-child {
      border-bottom: 0;
    }

    &:hover {
      background: var(--el-fill-color-extra-light);
    }
  }

  .user-cell,
  .device-cell {
    display: flex;
    align-items: center;
    gap: 9px;
    min-width: 0;
  }

  .device-cell {
    color: var(--el-text-color-regular);
  }

  .avatar-wrap {
    position: relative;
    flex: 0 0 30px;
  }

  .avatar {
    width: 30px;
    height: 30px;
    border-radius: 50%;
  }

  .online-dot {
    position: absolute;
    right: 0;
    bottom: 0;
    width: 9px;
    height: 9px;
    border: 2px solid var(--el-bg-color);
    border-radius: 50%;
    background: var(--el-color-success);
  }

  .name-line {
    font-size: 13px;
    font-weight: 500;
  }

  .sub-line,
  .time-text {
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .ip-cell {
    min-width: 0;
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .empty-state {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 282px;
    font-size: 13px;
    color: var(--el-text-color-secondary);
  }

  @media (max-width: 768px) {
    .online-row {
      grid-template-columns: 1fr auto;
    }

    .device-cell,
    .ip-cell {
      display: none;
    }
  }
</style>
