<!-- 最新注册用户列表 -->
<template>
  <div class="art-card ops-panel" v-loading="loading">
    <div class="panel-head">
      <div>
        <h4>最新注册用户</h4>
        <p>最近 {{ users.length }} 位注册记录</p>
      </div>
      <RouterLink to="/user/list" class="panel-link">全部用户</RouterLink>
    </div>

    <div class="list-head">
      <span>用户</span>
      <span>手机号</span>
      <span>状态</span>
      <span>注册时间</span>
    </div>

    <div v-if="users.length === 0 && !loading" class="empty-state">暂无注册记录</div>

    <div v-else class="user-list">
      <div v-for="row in users.slice(0, 8)" :key="row.id" class="user-row">
        <div class="user-cell">
          <ElImage class="avatar" :src="getAvatarUrl(row.avatar, row.id)" fit="cover" lazy />
          <div class="min-w-0">
            <div class="name-line">
              <span class="truncate">{{ row.nickname || row.username }}</span>
              <span v-if="row.is_online" class="online-dot"></span>
            </div>
            <div class="sub-line">@{{ row.username }}</div>
          </div>
        </div>
        <div class="cell muted">{{ row.phone || '-' }}</div>
        <div class="cell">
          <ElTag :type="row.status === 1 ? 'success' : 'danger'" size="small" effect="plain">
            {{ row.status === 1 ? '正常' : '禁用' }}
          </ElTag>
        </div>
        <div class="cell time-text">{{ formatTime(row.created_at) }}</div>
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

  const getAvatarUrl = (avatar: string | null, id: number): string => {
    if (avatar) return fixImageUrl(avatar)
    return getLocalAvatarDataUrl(id)
  }

  const loadUsers = async () => {
    try {
      loading.value = true
      const response = await getUserList({ page: 1, page_size: 12 })
      users.value = response.list
    } catch (error) {
      console.error('加载用户列表失败:', error)
    } finally {
      loading.value = false
    }
  }

  const formatTime = (timeStr?: string | null) => {
    if (!timeStr) return '-'
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

  onMounted(loadUsers)
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

    h4 {
      margin: 0;
      font-size: 15px;
      font-weight: 600;
      color: var(--el-text-color-primary);
    }

    p {
      margin: 3px 0 0;
      font-size: 12px;
      color: var(--el-text-color-secondary);
    }
  }

  .panel-link {
    font-size: 13px;
    color: var(--el-color-primary);
  }

  .list-head,
  .user-row {
    display: grid;
    grid-template-columns: minmax(180px, 1.4fr) minmax(96px, 0.8fr) 76px 96px;
    align-items: center;
    gap: 12px;
  }

  .list-head {
    padding: 10px 18px;
    font-size: 12px;
    color: var(--el-text-color-secondary);
    background: var(--el-fill-color-extra-light);
    border-bottom: 1px solid var(--el-border-color-lighter);
  }

  .user-list {
    min-height: 282px;
  }

  .user-row {
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

  .user-cell {
    display: flex;
    align-items: center;
    gap: 9px;
    min-width: 0;
  }

  .avatar {
    width: 30px;
    height: 30px;
    flex: 0 0 30px;
    border-radius: 50%;
  }

  .name-line {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
    font-size: 13px;
    font-weight: 500;
  }

  .sub-line,
  .time-text {
    font-size: 12px;
    color: var(--el-text-color-secondary);
  }

  .cell {
    min-width: 0;
    font-size: 13px;
  }

  .muted {
    color: var(--el-text-color-secondary);
  }

  .online-dot {
    width: 7px;
    height: 7px;
    flex: 0 0 7px;
    border-radius: 50%;
    background: var(--el-color-success);
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
    .list-head {
      display: none;
    }

    .user-row {
      grid-template-columns: 1fr auto;
    }

    .cell {
      display: none;
    }

    .time-text {
      display: block;
    }
  }
</style>
