<!-- 话题管理页面 -->
<template>
  <div class="topic-page art-full-height">
    <!-- 搜索栏 -->
    <ArtSearchBar
      v-model="searchForm"
      :fields="searchFields"
      @search="handleSearch"
      @reset="resetSearch"
    />

    <ElCard class="art-table-card" shadow="never">
      <!-- 表格头部 -->
      <ArtTableHeader v-model:columns="columnChecks" :loading="loading" @refresh="refreshData">
        <template #left>
          <ElButton type="primary" @click="showDialog('add')">
            <i class="ri-add-line mr-1"></i>新建话题
          </ElButton>
        </template>
      </ArtTableHeader>

      <!-- 表格 -->
      <ArtTable
        :loading="loading"
        :data="data"
        :columns="columns"
        :pagination="pagination"
        @pagination:size-change="handleSizeChange"
        @pagination:current-change="handleCurrentChange"
      >
      </ArtTable>
    </ElCard>

    <!-- 新建/编辑话题弹窗 -->
    <ElDialog
      v-model="dialogVisible"
      :title="dialogType === 'add' ? '新建话题' : '编辑话题'"
      width="500px"
    >
      <ElForm ref="formRef" :model="formData" :rules="rules" label-width="80px">
        <ElFormItem label="话题名称" prop="name">
          <ElInput v-model="formData.name" placeholder="请输入话题名称" />
        </ElFormItem>
        <ElFormItem label="描述" prop="description">
          <ElInput
            v-model="formData.description"
            type="textarea"
            :rows="3"
            placeholder="请输入话题描述"
          />
        </ElFormItem>
        <ElFormItem label="图标" prop="icon">
          <ElInput v-model="formData.icon" placeholder="emoji 或图标名称" />
        </ElFormItem>
        <ElFormItem label="排序" prop="sort">
          <ElInputNumber v-model="formData.sort" :min="0" :max="999" />
        </ElFormItem>
        <ElFormItem label="属性">
          <ElCheckbox v-model="formData.is_hot">热门</ElCheckbox>
          <ElCheckbox v-model="formData.is_official">官方</ElCheckbox>
        </ElFormItem>
        <ElFormItem label="状态" prop="status">
          <ElRadioGroup v-model="formData.status">
            <ElRadio :value="1">启用</ElRadio>
            <ElRadio :value="2">禁用</ElRadio>
          </ElRadioGroup>
        </ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="dialogVisible = false">取消</ElButton>
        <ElButton type="primary" :loading="submitting" @click="handleSubmit">确定</ElButton>
      </template>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
  import { useTable } from '@/hooks/core/useTable'
  import { getTopicList, createTopic, updateTopic, deleteTopic, Topic } from '@/api/admin'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import {
    ElTag,
    ElMessageBox,
    ElMessage,
    ElSwitch,
    type FormInstance,
    type FormRules
  } from 'element-plus'

  defineOptions({ name: 'TopicList' })

  // 弹窗
  const dialogVisible = ref(false)
  const dialogType = ref<'add' | 'edit'>('add')
  const submitting = ref(false)
  const formRef = ref<FormInstance>()
  const currentTopic = ref<Topic | null>(null)

  // 表单数据
  const formData = reactive({
    name: '',
    description: '',
    icon: '',
    sort: 0,
    is_hot: false,
    is_official: false,
    status: 1
  })

  // 表单验证
  const rules: FormRules = {
    name: [
      { required: true, message: '请输入话题名称', trigger: 'blur' },
      { min: 2, max: 50, message: '长度 2-50 字符', trigger: 'blur' }
    ]
  }

  // 搜索表单
  const searchForm = ref({
    keyword: ''
  })

  const searchFields = [
    { type: 'input', field: 'keyword', label: '搜索', placeholder: '搜索话题名称' }
  ]

  const {
    columns,
    columnChecks,
    data,
    loading,
    pagination,
    getData,
    searchParams,
    resetSearchParams,
    handleSizeChange,
    handleCurrentChange,
    refreshData
  } = useTable({
    core: {
      apiFn: async (params: any) => {
        const res = await getTopicList({
          page: params.current,
          page_size: params.size,
          keyword: params.keyword
        })
        return {
          records: res.list || [],
          total: res.total,
          current: res.page,
          size: res.page_size
        }
      },
      apiParams: {
        current: 1,
        size: 20,
        ...searchForm.value
      },
      columnsFactory: () => [
        { type: 'index', width: 60, label: '序号' },
        {
          prop: 'name',
          label: '话题名称',
          minWidth: 160,
          formatter: (row: Topic) => {
            return h('div', { class: 'flex items-center gap-2' }, [
              row.icon && h('span', { class: 'text-xl' }, row.icon),
              h('span', { class: 'font-medium' }, `#${row.name}`)
            ])
          }
        },
        {
          prop: 'description',
          label: '描述',
          minWidth: 200,
          formatter: (row: Topic) => {
            return h('span', { class: 'text-sm text-g-500' }, row.description || '-')
          }
        },
        {
          prop: 'post_count',
          label: '动态数',
          width: 100,
          align: 'center'
        },
        {
          prop: 'flags',
          label: '属性',
          width: 140,
          formatter: (row: Topic) => {
            const tags = []
            if (row.is_hot)
              tags.push(
                h(ElTag, { type: 'danger', size: 'small', effect: 'light' }, () => '🔥 热门')
              )
            if (row.is_official)
              tags.push(
                h(ElTag, { type: 'primary', size: 'small', effect: 'light' }, () => '✓ 官方')
              )
            return h(
              'div',
              { class: 'flex gap-1' },
              tags.length ? tags : [h('span', { class: 'text-g-300' }, '-')]
            )
          }
        },
        {
          prop: 'sort',
          label: '排序',
          width: 80,
          align: 'center'
        },
        {
          prop: 'status',
          label: '状态',
          width: 100,
          formatter: (row: Topic) => {
            return h(ElSwitch, {
              modelValue: row.status === 1,
              activeText: '启用',
              inactiveText: '禁用',
              onChange: async (val: boolean) => {
                await updateTopic(row.id, { status: val ? 1 : 2 })
                refreshData()
              }
            })
          }
        },
        {
          prop: 'operation',
          label: '操作',
          width: 120,
          fixed: 'right',
          formatter: (row: Topic) =>
            h('div', { class: 'flex gap-1' }, [
              h(ArtButtonTable, {
                type: 'edit',
                onClick: () => showDialog('edit', row)
              }),
              h(ArtButtonTable, {
                type: 'delete',
                onClick: () => handleDelete(row)
              })
            ])
        }
      ]
    }
  })

  // 搜索
  const handleSearch = (params: Record<string, any>) => {
    Object.assign(searchParams, params)
    getData()
  }

  const resetSearch = () => {
    resetSearchParams()
  }

  // 显示弹窗
  const showDialog = (type: 'add' | 'edit', row?: Topic) => {
    dialogType.value = type
    currentTopic.value = row || null

    if (type === 'edit' && row) {
      Object.assign(formData, {
        name: row.name,
        description: row.description,
        icon: row.icon,
        sort: row.sort,
        is_hot: row.is_hot,
        is_official: row.is_official,
        status: row.status
      })
    } else {
      Object.assign(formData, {
        name: '',
        description: '',
        icon: '',
        sort: 0,
        is_hot: false,
        is_official: false,
        status: 1
      })
    }

    dialogVisible.value = true
  }

  // 提交
  const handleSubmit = async () => {
    if (!formRef.value) return

    await formRef.value.validate(async (valid) => {
      if (!valid) return

      submitting.value = true
      try {
        if (dialogType.value === 'add') {
          await createTopic(formData)
          ElMessage.success('创建成功')
        } else if (currentTopic.value) {
          await updateTopic(currentTopic.value.id, formData)
          ElMessage.success('更新成功')
        }
        dialogVisible.value = false
        refreshData()
      } catch (e) {
        console.error(e)
      } finally {
        submitting.value = false
      }
    })
  }

  // 删除
  const handleDelete = (row: Topic) => {
    ElMessageBox.confirm(`确定要删除话题 "#${row.name}" 吗？`, '删除确认', {
      type: 'warning'
    }).then(async () => {
      await deleteTopic(row.id)
      ElMessage.success('已删除')
      refreshData()
    })
  }
</script>
