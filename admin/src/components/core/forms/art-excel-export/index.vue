<!-- 导出 Excel 文件 -->
<template>
  <ElButton
    :type="type"
    :size="size"
    :loading="isExporting"
    :disabled="disabled || !hasData"
    v-ripple
    @click="handleExport"
  >
    <template #loading>
      <ElIcon class="is-loading">
        <Loading />
      </ElIcon>
      {{ loadingText }}
    </template>
    <slot>{{ buttonText }}</slot>
  </ElButton>
</template>

<script setup lang="ts">
  import { computed, nextTick, readonly, ref } from 'vue'
  import { Loading } from '@element-plus/icons-vue'
  import { useThrottleFn } from '@vueuse/core'
  import type { ButtonType } from 'element-plus'
  import type { SheetData, SheetOptions } from 'write-excel-file/browser'

  defineOptions({ name: 'ArtExcelExport' })

  type ExportValue = string | number | boolean | null | undefined | Date
  type ExcelColumn = NonNullable<SheetOptions<Blob>['columns']>[number]

  interface ExportData {
    [key: string]: ExportValue
  }

  interface ColumnConfig {
    title: string
    width?: number
    formatter?: (value: ExportValue, row: ExportData, index: number) => string
  }

  interface ExportOptions {
    data: ExportData[]
    filename?: string
    sheetName?: string
    type?: ButtonType
    size?: 'large' | 'default' | 'small'
    disabled?: boolean
    buttonText?: string
    loadingText?: string
    autoIndex?: boolean
    indexColumnTitle?: string
    columns?: Record<string, ColumnConfig>
    headers?: Record<string, string>
    maxRows?: number
    showSuccessMessage?: boolean
    showErrorMessage?: boolean
    workbookOptions?: {
      creator?: string
      lastModifiedBy?: string
      created?: Date
      modified?: Date
    }
  }

  const props = withDefaults(defineProps<ExportOptions>(), {
    filename: () => `export_${new Date().toISOString().slice(0, 10)}`,
    sheetName: 'Sheet1',
    type: 'primary',
    size: 'default',
    disabled: false,
    buttonText: '导出 Excel',
    loadingText: '导出中...',
    autoIndex: false,
    indexColumnTitle: '序号',
    columns: () => ({}),
    headers: () => ({}),
    maxRows: 100000,
    showSuccessMessage: true,
    showErrorMessage: true,
    workbookOptions: () => ({})
  })

  const emit = defineEmits<{
    'before-export': [data: ExportData[]]
    'export-success': [filename: string, rowCount: number]
    'export-error': [error: ExportError]
    'export-progress': [progress: number]
  }>()

  class ExportError extends Error {
    constructor(
      message: string,
      public code: string,
      public details?: unknown
    ) {
      super(message)
      this.name = 'ExportError'
    }
  }

  const isExporting = ref(false)
  const hasData = computed(() => Array.isArray(props.data) && props.data.length > 0)

  const validateData = (data: ExportData[]): void => {
    if (!Array.isArray(data)) {
      throw new ExportError('数据必须是数组格式', 'INVALID_DATA_TYPE')
    }

    if (data.length === 0) {
      throw new ExportError('没有可导出的数据', 'NO_DATA')
    }

    if (data.length > props.maxRows) {
      throw new ExportError(`数据行数超过限制（${props.maxRows} 行）`, 'EXCEED_MAX_ROWS', {
        currentRows: data.length,
        maxRows: props.maxRows
      })
    }
  }

  const formatCellValue = (
    value: ExportValue,
    key: string,
    row: ExportData,
    index: number
  ): string => {
    const column = props.columns[key]
    if (column?.formatter) {
      return column.formatter(value, row, index)
    }

    if (value === null || value === undefined) {
      return ''
    }

    if (value instanceof Date) {
      return value.toLocaleDateString('zh-CN')
    }

    if (typeof value === 'boolean') {
      return value ? '是' : '否'
    }

    return String(value)
  }

  const processData = (data: ExportData[]): Record<string, string>[] =>
    data.map((item, index) => {
      const processedItem: Record<string, string> = {}

      if (props.autoIndex) {
        processedItem[props.indexColumnTitle] = String(index + 1)
      }

      Object.entries(item).forEach(([key, value]) => {
        let columnTitle = key
        if (props.columns[key]?.title) {
          columnTitle = props.columns[key].title
        } else if (props.headers[key]) {
          columnTitle = props.headers[key]
        }

        processedItem[columnTitle] = formatCellValue(value, key, item, index)
      })

      return processedItem
    })

  const calculateColumnWidths = (data: Record<string, string>[]): ExcelColumn[] => {
    if (data.length === 0) return []

    // 最多采样前 100 行估算列宽，避免大数据导出前重复遍历全部内容。
    const sampleSize = Math.min(data.length, 100)
    const columns = Object.keys(data[0])

    return columns.map((column) => {
      const configWidth = Object.values(props.columns).find((col) => col.title === column)?.width
      if (configWidth) return { width: configWidth }

      const maxLength = Math.max(
        column.length,
        ...data.slice(0, sampleSize).map((row) => String(row[column] || '').length)
      )
      const width = Math.min(Math.max(maxLength + 2, 8), 50)
      return { width }
    })
  }

  const buildSheetData = (data: Record<string, string>[]): SheetData => {
    if (data.length === 0) return []

    const headers = Object.keys(data[0])
    return [
      headers.map((header) => ({
        value: header,
        type: String,
        fontWeight: 'bold' as const
      })),
      ...data.map((row) => headers.map((header) => row[header] ?? ''))
    ]
  }

  const exportToExcel = async (
    data: ExportData[],
    filename: string,
    sheetName: string
  ): Promise<void> => {
    try {
      // 进度表示转换阶段完成度，不是浏览器文件写入的字节级进度。
      emit('export-progress', 10)

      const processedData = processData(data)
      emit('export-progress', 30)

      const sheetData = buildSheetData(processedData)
      const columns = calculateColumnWidths(processedData)
      emit('export-progress', 50)

      // 写文件库按需加载，普通列表页面不会进入主包。
      const { default: writeXlsxFile } = await import('write-excel-file/browser')
      emit('export-progress', 70)

      const timestamp = new Date().toISOString().replace(/[:.]/g, '-')
      const finalFilename = `${filename}_${timestamp}.xlsx`
      const excelFile = writeXlsxFile(sheetData, {
        sheet: sheetName,
        columns
      })
      emit('export-progress', 85)

      await excelFile.toFile(finalFilename)
      emit('export-progress', 100)

      await nextTick()
    } catch (error) {
      throw new ExportError(`Excel 导出失败: ${(error as Error).message}`, 'EXPORT_FAILED', error)
    }
  }

  const handleExport = useThrottleFn(async () => {
    // 节流和状态锁共同防止双击生成多个下载任务。
    if (isExporting.value) return

    isExporting.value = true

    try {
      validateData(props.data)
      emit('before-export', props.data)

      await exportToExcel(props.data, props.filename, props.sheetName)
      emit('export-success', props.filename, props.data.length)

      if (props.showSuccessMessage) {
        ElMessage.success({
          message: `成功导出 ${props.data.length} 条数据`,
          duration: 3000
        })
      }
    } catch (error) {
      const exportError =
        error instanceof ExportError
          ? error
          : new ExportError(`导出失败: ${(error as Error).message}`, 'UNKNOWN_ERROR', error)

      emit('export-error', exportError)

      if (props.showErrorMessage) {
        ElMessage.error({
          message: exportError.message,
          duration: 5000
        })
      }

      console.error('Excel 导出错误:', exportError)
    } finally {
      isExporting.value = false
      emit('export-progress', 0)
    }
  }, 1000)

  defineExpose({
    exportData: handleExport,
    isExporting: readonly(isExporting),
    hasData
  })
</script>

<style scoped>
  .is-loading {
    animation: rotating 2s linear infinite;
  }

  @keyframes rotating {
    0% {
      transform: rotate(0deg);
    }

    100% {
      transform: rotate(360deg);
    }
  }
</style>
