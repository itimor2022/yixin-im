<template>
  <ElConfigProvider>
    <RouterView />
  </ElConfigProvider>
</template>

<script setup lang="ts">
defineOptions({ name: 'ServiceAdminApp' })
</script>
