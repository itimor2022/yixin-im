<template>
  <div class="setting-drawer">
    <ElDrawer
      size="300px"
      v-model="visible"
      :lock-scroll="true"
      :with-header="false"
      :before-close="handleClose"
      :destroy-on-close="false"
      modal-class="setting-modal"
      @open="handleOpen"
      @close="handleDrawerClose"
    >
      <div class="drawer-con">
        <slot />
      </div>
    </ElDrawer>
  </div>
</template>

<script setup lang="ts">
  interface Props {
    modelValue: boolean
  }

  interface Emits {
    (e: 'update:modelValue', value: boolean): void
    (e: 'open'): void
    (e: 'close'): void
  }

  const props = defineProps<Props>()
  const emit = defineEmits<Emits>()

  // 抽屉可见性完全受父组件 v-model 控制，内部关闭也通过 update 事件回传。
  const visible = computed({
    get: () => props.modelValue,
    set: (value: boolean) => emit('update:modelValue', value)
  })

  const handleOpen = () => {
    emit('open')
  }

  const handleDrawerClose = () => {
    // close 在抽屉动画完成后发出，父组件可在此清理临时全局样式。
    emit('close')
  }

  const handleClose = () => {
    visible.value = false
  }
</script>
