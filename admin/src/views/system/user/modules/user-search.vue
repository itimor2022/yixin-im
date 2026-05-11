<template>
  <ArtSearchBar
    ref="searchBarRef"
    v-model="formData"
    :items="formItems"
    :rules="rules"
    @reset="handleReset"
    @search="handleSearch"
  >
    <template #extra>
      <ElSwitch
        v-model="onlineOnly"
        active-text="只看在线"
        @change="handleSearch"
        style="margin-left: 16px"
      />
    </template>
  </ArtSearchBar>
</template>

<script setup lang="ts">
  interface Props {
    modelValue: Record<string, any>
  }
  interface Emits {
    (e: 'update:modelValue', value: Record<string, any>): void
    (e: 'search', params: Record<string, any>): void
    (e: 'reset'): void
  }
  const props = defineProps<Props>()
  const emit = defineEmits<Emits>()

  // 表单数据双向绑定
  const searchBarRef = ref()
  const onlineOnly = ref(false)

  const formData = computed({
    get: () => props.modelValue,
    set: (val) => emit('update:modelValue', val)
  })

  // 校验规则
  const rules = {}

  // 状态选项
  const statusOptions = [
    { label: '全部', value: '' },
    { label: '正常', value: '1' },
    { label: '禁用', value: '0' },
    { label: '待审核', value: '2' },
    { label: '封禁中', value: '3' }
  ]

  // 表单配置
  const formItems = computed(() => [
    {
      label: '搜索',
      key: 'userName',
      type: 'input',
      placeholder: '用户名/昵称/手机号',
      clearable: true,
      props: {
        style: { width: '200px' }
      }
    },
    {
      label: '状态',
      key: 'status',
      type: 'select',
      props: {
        placeholder: '请选择状态',
        options: statusOptions,
        clearable: true
      }
    }
  ])

  // 事件
  function handleReset() {
    onlineOnly.value = false
    emit('reset')
  }

  async function handleSearch() {
    await searchBarRef.value?.validate()
    emit('search', {
      ...formData.value,
      onlineOnly: onlineOnly.value
    })
  }
</script>
