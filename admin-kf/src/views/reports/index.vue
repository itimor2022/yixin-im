<template>
  <div class="placeholder-page page-card">
    <div class="placeholder-icon"><Icon icon="ri:bar-chart-box-line" /></div>
    <h2>数据报表</h2>
    <p>下一阶段将接入首次响应、解决时长、满意度、客服接待量和 AI 解决率。</p>
    <ElButton type="primary" @click="router.push('/dashboard')">查看现有数据概览</ElButton>
  </div>
</template>

<script setup lang="ts">
import { Icon } from '@iconify/vue'
import { useRouter } from 'vue-router'
const router = useRouter()
</script>

<style scoped lang="scss">
.placeholder-page { min-height: 420px; display: grid; place-content: center; justify-items: center; gap: 10px; padding: 40px; text-align: center; }
.placeholder-icon { width: 54px; height: 54px; display: grid; place-items: center; border-radius: 12px; color: #fff; background: #171717; font-size: 24px; }
h2 { margin: 8px 0 0; font-size: 20px; } p { max-width: 480px; margin: 0 0 12px; color: var(--kf-text-secondary); font-size: 13px; line-height: 1.7; }
</style>
