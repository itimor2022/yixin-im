<!-- 违禁词管理页面 -->
<template>
  <div class="banned-word-page art-full-height">
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
          <div class="flex gap-2">
            <ElButton type="primary" @click="showDialog('add')">
              <i class="ri-add-line mr-1"></i>添加违禁词
            </ElButton>
            <ElButton @click="showBatchDialog">
              <i class="ri-file-list-line mr-1"></i>批量添加
            </ElButton>
          </div>
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

    <!-- 新建/编辑弹窗 -->
    <ElDialog
      v-model="dialogVisible"
      :title="dialogType === 'add' ? '添加违禁词' : '编辑违禁词'"
      width="480px"
    >
      <ElForm ref="formRef" :model="formData" :rules="rules" label-width="80px">
        <ElFormItem label="违禁词" prop="word">
          <ElInput v-model="formData.word" placeholder="请输入违禁词" />
        </ElFormItem>
        <ElFormItem label="分类" prop="category">
          <ElSelect v-model="formData.category" placeholder="选择分类" style="width: 100%">
            <ElOption
              v-for="cat in CATEGORIES"
              :key="cat.value"
              :label="cat.label"
              :value="cat.value"
            />
          </ElSelect>
        </ElFormItem>
        <ElFormItem label="处理级别" prop="level">
          <ElRadioGroup v-model="formData.level">
            <ElRadio :value="1">记录警告</ElRadio>
            <ElRadio :value="2">屏蔽替换</ElRadio>
            <ElRadio :value="3">禁止发布</ElRadio>
          </ElRadioGroup>
        </ElFormItem>
        <ElFormItem v-if="formData.level === 2" label="替换词" prop="replacement">
          <ElInput v-model="formData.replacement" placeholder="留空则替换为 ***" />
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

    <!-- 批量添加弹窗 -->
    <ElDialog v-model="batchDialogVisible" title="批量添加违禁词" width="500px">
      <ElForm ref="batchFormRef" :model="batchFormData" :rules="batchRules" label-width="80px">
        <ElFormItem label="违禁词" prop="words">
          <ElInput
            v-model="batchFormData.words"
            type="textarea"
            :rows="6"
            placeholder="每行一个违禁词&#10;词语1&#10;词语2&#10;词语3"
          />
        </ElFormItem>
        <ElFormItem label="分类" prop="category">
          <ElSelect v-model="batchFormData.category" placeholder="选择分类" style="width: 100%">
            <ElOption
              v-for="cat in CATEGORIES"
              :key="cat.value"
              :label="cat.label"
              :value="cat.value"
            />
          </ElSelect>
        </ElFormItem>
        <ElFormItem label="处理级别" prop="level">
          <ElRadioGroup v-model="batchFormData.level">
            <ElRadio :value="1">记录警告</ElRadio>
            <ElRadio :value="2">屏蔽替换</ElRadio>
            <ElRadio :value="3">禁止发布</ElRadio>
          </ElRadioGroup>
        </ElFormItem>
      </ElForm>
      <template #footer>
        <ElButton @click="batchDialogVisible = false">取消</ElButton>
        <ElButton type="primary" :loading="batchSubmitting" @click="handleBatchSubmit">
          批量添加
        </ElButton>
      </template>
    </ElDialog>
  </div>
</template>

<script setup lang="ts">
  import { useTable } from '@/hooks/core/useTable'
  import {
    getBannedWordList,
    createBannedWord,
    updateBannedWord,
    deleteBannedWord,
    batchCreateBannedWords,
    BannedWord
  } from '@/api/admin'
  import ArtButtonTable from '@/components/core/forms/art-button-table/index.vue'
  import {
    ElTag,
    ElMessageBox,
    ElMessage,
    ElSwitch,
    type FormInstance,
    type FormRules
  } from 'element-plus'

  defineOptions({ name: 'BannedWordList' })

  // 分类选项
  const CATEGORIES = [
    { value: 'politics', label: '政治敏感' },
    { value: 'porn', label: '色情低俗' },
    { value: 'ads', label: '广告推广' },
    { value: 'violence', label: '暴力恐怖' },
    { value: 'fraud', label: '欺诈诈骗' },
    { value: 'other', label: '其他' }
  ]

  // 级别配置
  const LEVEL_CONFIG = {
    1: { type: 'info' as const, text: '警告' },
    2: { type: 'warning' as const, text: '屏蔽' },
    3: { type: 'danger' as const, text: '禁止' }
  }

  // 弹窗
  const dialogVisible = ref(false)
  const dialogType = ref<'add' | 'edit'>('add')
  const submitting = ref(false)
  const formRef = ref<FormInstance>()
  const currentWord = ref<BannedWord | null>(null)

  // 批量弹窗
  const batchDialogVisible = ref(false)
  const batchSubmitting = ref(false)
  const batchFormRef = ref<FormInstance>()

  // 表单数据
  const formData = reactive({
    word: '',
    category: 'other',
    level: 2,
    replacement: '',
    status: 1
  })

  const batchFormData = reactive({
    words: '',
    category: 'other',
    level: 2
  })

  // 表单验证
  const rules: FormRules = {
    word: [
      { required: true, message: '请输入违禁词', trigger: 'blur' },
      { min: 1, max: 50, message: '长度 1-50 字符', trigger: 'blur' }
    ],
    category: [{ required: true, message: '请选择分类', trigger: 'change' }]
  }

  const batchRules: FormRules = {
    words: [{ required: true, message: '请输入违禁词', trigger: 'blur' }],
    category: [{ required: true, message: '请选择分类', trigger: 'change' }]
  }

  // 搜索表单
  const searchForm = ref({
    keyword: '',
    category: ''
  })

  const searchFields = [
    { type: 'input', field: 'keyword', label: '搜索', placeholder: '搜索违禁词' },
    {
      type: 'select',
      field: 'category',
      label: '分类',
      placeholder: '全部分类',
      options: CATEGORIES
    }
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
        const res = await getBannedWordList({
          page: params.current,
          page_size: params.size,
          keyword: params.keyword,
          category: params.category || undefined
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
          prop: 'word',
          label: '违禁词',
          minWidth: 160,
          formatter: (row: BannedWord) => {
            return h('span', { class: 'font-mono text-red-500' }, row.word)
          }
        },
        {
          prop: 'category',
          label: '分类',
          width: 120,
          formatter: (row: BannedWord) => {
            const cat = CATEGORIES.find((c) => c.value === row.category)
            return h(ElTag, { size: 'small', effect: 'light' }, () => cat?.label || row.category)
          }
        },
        {
          prop: 'level',
          label: '处理级别',
          width: 100,
          formatter: (row: BannedWord) => {
            const config = LEVEL_CONFIG[row.level as keyof typeof LEVEL_CONFIG]
            return h(
              ElTag,
              {
                type: config?.type || 'info',
                size: 'small'
              },
              () => config?.text || '未知'
            )
          }
        },
        {
          prop: 'replacement',
          label: '替换词',
          width: 120,
          formatter: (row: BannedWord) => {
            if (row.level !== 2) return h('span', { class: 'text-g-300' }, '-')
            return h('span', { class: 'font-mono' }, row.replacement || '***')
          }
        },
        {
          prop: 'hit_count',
          label: '命中次数',
          width: 100,
          align: 'center',
          formatter: (row: BannedWord) => {
            return h(
              'span',
              {
                class: row.hit_count > 0 ? 'text-orange-500 font-medium' : 'text-g-400'
              },
              row.hit_count
            )
          }
        },
        {
          prop: 'status',
          label: '状态',
          width: 100,
          formatter: (row: BannedWord) => {
            return h(ElSwitch, {
              modelValue: row.status === 1,
              activeText: '启用',
              inactiveText: '禁用',
              onChange: async (val: boolean) => {
                await updateBannedWord(row.id, { status: val ? 1 : 2 })
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
          formatter: (row: BannedWord) =>
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
  const showDialog = (type: 'add' | 'edit', row?: BannedWord) => {
    dialogType.value = type
    currentWord.value = row || null

    if (type === 'edit' && row) {
      Object.assign(formData, {
        word: row.word,
        category: row.category,
        level: row.level,
        replacement: row.replacement,
        status: row.status
      })
    } else {
      Object.assign(formData, {
        word: '',
        category: 'other',
        level: 2,
        replacement: '',
        status: 1
      })
    }

    dialogVisible.value = true
  }

  // 显示批量弹窗
  const showBatchDialog = () => {
    Object.assign(batchFormData, {
      words: '',
      category: 'other',
      level: 2
    })
    batchDialogVisible.value = true
  }

  // 提交
  const handleSubmit = async () => {
    if (!formRef.value) return

    await formRef.value.validate(async (valid) => {
      if (!valid) return

      submitting.value = true
      try {
        if (dialogType.value === 'add') {
          await createBannedWord(formData)
          ElMessage.success('添加成功')
        } else if (currentWord.value) {
          await updateBannedWord(currentWord.value.id, formData)
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

  // 批量提交
  const handleBatchSubmit = async () => {
    if (!batchFormRef.value) return

    await batchFormRef.value.validate(async (valid) => {
      if (!valid) return

      const words = batchFormData.words
        .split('\n')
        .map((w) => w.trim())
        .filter((w) => w)

      if (words.length === 0) {
        ElMessage.warning('请输入至少一个违禁词')
        return
      }

      batchSubmitting.value = true
      try {
        const res = await batchCreateBannedWords(words, batchFormData.category, batchFormData.level)
        ElMessage.success(`成功添加 ${(res as any)?.created || words.length} 个违禁词`)
        batchDialogVisible.value = false
        refreshData()
      } catch (e) {
        console.error(e)
      } finally {
        batchSubmitting.value = false
      }
    })
  }

  // 删除
  const handleDelete = (row: BannedWord) => {
    ElMessageBox.confirm(`确定要删除违禁词 "${row.word}" 吗？`, '删除确认', {
      type: 'warning'
    }).then(async () => {
      await deleteBannedWord(row.id)
      ElMessage.success('已删除')
      refreshData()
    })
  }
</script>
