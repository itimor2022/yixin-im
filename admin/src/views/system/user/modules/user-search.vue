<template>
  <ArtSearchBar
    ref="searchBarRef"
    v-model="formData"
    :items="formItems"
    :rules="rules"
    @reset="handleReset"
    @search="handleSearch"
  >
    <template #searchMode>
      <ElSegmented
        v-model="formData.searchMode"
        :options="searchModeOptions"
        size="default"
        @change="handleSearch"
      />
    </template>
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

  const genderOptions = [
    { label: '全部', value: '' },
    { label: '男', value: 'male' },
    { label: '女', value: 'female' },
    { label: '未设置', value: 'unknown' }
  ]

  const registerSourceOptions = [
    { label: '全部', value: '' },
    { label: '普通注册', value: 'manual' },
    { label: '一键注册', value: 'quick' }
  ]

  const credentialsStatusOptions = [
    { label: '全部', value: '' },
    { label: '已完善', value: 'initialized' },
    { label: '待完善', value: 'pending' }
  ]

  const searchModeOptions = [
    { label: '精确账号', value: 'exact' },
    { label: '模糊搜索', value: 'fuzzy' }
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
      label: '模式',
      key: 'searchMode',
      type: 'input',
      props: {
        style: { width: '176px' }
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
    },
    {
      label: '性别',
      key: 'gender',
      type: 'select',
      props: {
        placeholder: '请选择性别',
        options: genderOptions,
        clearable: true
      }
    },
    {
      label: '注册来源',
      key: 'registerSource',
      type: 'select',
      props: {
        placeholder: '请选择来源',
        options: registerSourceOptions,
        clearable: true
      }
    },
    {
      label: '登录凭证',
      key: 'credentialsStatus',
      type: 'select',
      props: {
        placeholder: '请选择状态',
        options: credentialsStatusOptions,
        clearable: true
      }
    },
    {
      label: '邀请码',
      key: 'inviteCode',
      type: 'input',
      props: {
        placeholder: '请输入用户邀请码',
        clearable: true,
        style: { width: '200px' }
      }
    },
    {
      label: '推荐人ID',
      key: 'recommenderId',
      type: 'input',
      props: {
        placeholder: '查询下级用户，输入推荐人用户ID',
        clearable: true,
        style: { width: '220px' }
      }
    }
  ])

  // 事件
  function handleReset() {
    onlineOnly.value = false
    formData.value.searchMode = 'exact'
    emit('reset')
  }

  async function handleSearch() {
    await searchBarRef.value?.validate()
    emit('search', {
      ...formData.value,
      searchMode: formData.value.searchMode || 'exact',
      onlineOnly: onlineOnly.value
    })
  }
</script>
