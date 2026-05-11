import request from '@/utils/http'

export interface ReportItem {
  id: string
  reporter_id: string
  reporter: string
  target_id: string
  target_type: string
  target_name?: string
  target_username?: string
  target_avatar?: string
  reason: string
  reason_text: string
  description: string
  status: number
  process_note?: string
  created_at: string
  processed_at?: string
}

export interface ReportListResponse {
  list: ReportItem[]
  total: number
  page: number
}

export interface ReportStats {
  overview: {
    total: number
    pending: number
    processed: number
    rejected: number
    today: number
  }
  by_type: Array<{ TargetType: string; Count: number }>
  by_reason: Array<{ Reason: string; Count: number }>
}

// 获取举报列表
export function getReportList(params: {
  page?: number
  page_size?: number
  status?: string
  target_type?: string
  reason?: string
}) {
  return request.get<ReportListResponse>({
    url: '/admin/reports/list',
    params
  })
}

// 获取举报统计
export function getReportStats() {
  return request.get<ReportStats>({
    url: '/admin/reports/stats'
  })
}

// 处理举报
export function processReport(id: string, data: { status: number; process_note?: string }) {
  return request.post({
    url: `/admin/reports/${id}/process`,
    data
  })
}

// 删除举报
export function deleteReport(id: string) {
  return request.del({
    url: `/admin/reports/${id}`
  })
}
