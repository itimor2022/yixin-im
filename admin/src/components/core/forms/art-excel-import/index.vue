<!-- 导入 Excel 文件 -->
<template>
  <div class="inline-block">
    <ElUpload
      :auto-upload="false"
      accept=".xlsx"
      :show-file-list="false"
      @change="handleFileChange"
    >
      <ElButton type="primary" v-ripple>
        <slot>导入 Excel</slot>
      </ElButton>
    </ElUpload>
  </div>
</template>

<script setup lang="ts">
  import type { UploadFile } from 'element-plus'
  import type { Row } from 'read-excel-file/browser'

  defineOptions({ name: 'ArtExcelImport' })

  const normalizeHeader = (value: Row[number], index: number): string => {
    const header = value == null ? '' : String(value).trim()
    return header || `column_${index + 1}`
  }

  const isEmptyRow = (row: Row): boolean =>
    row.every((value) => value == null || String(value).trim() === '')

  async function importExcel(file: File): Promise<Array<Record<string, unknown>>> {
    // 解析库按需加载，避免未使用导入功能的页面承担首包体积。
    const { readSheet } = await import('read-excel-file/browser')
    const rows = await readSheet(file)
    if (rows.length === 0) return []

    // 第一行固定作为字段名，空表头生成稳定占位键，空数据行直接忽略。
    const headers = rows[0].map(normalizeHeader)
    return rows
      .slice(1)
      .filter((row) => !isEmptyRow(row))
      .map((row) => {
        const item: Record<string, unknown> = {}
        headers.forEach((header, index) => {
          item[header] = row[index] ?? ''
        })
        return item
      })
  }

  const emit = defineEmits<{
    'import-success': [data: Array<Record<string, unknown>>]
    'import-error': [error: Error]
  }>()

  const handleFileChange = async (uploadFile: UploadFile) => {
    try {
      if (!uploadFile.raw) return
      const results = await importExcel(uploadFile.raw)
      // 组件只负责解析并发出结果，字段校验和入库由业务页面处理。
      emit('import-success', results)
    } catch (error) {
      emit('import-error', error as Error)
    }
  }
</script>
