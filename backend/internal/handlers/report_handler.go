package handlers

import (
	"strconv"
	"time"

	"gaoranim/internal/models"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

type ReportHandler struct {
	db *gorm.DB
}

func NewReportHandler(db *gorm.DB) *ReportHandler {
	return &ReportHandler{db: db}
}

// CreateReportRequest 创建举报请求
type CreateReportRequest struct {
	TargetID    string `json:"target_id" binding:"required"`
	TargetType  string `json:"target_type" binding:"required,oneof=user group channel message"`
	Reason      string `json:"reason" binding:"required"`
	Description string `json:"description"`
}

// CreateReport 创建举报
func (h *ReportHandler) CreateReport(c *gin.Context) {
	var req CreateReportRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	userIDStr := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userIDStr).First(&user).Error; err != nil {
		response.Unauthorized(c, "用户未登录")
		return
	}

	// 检查是否已经举报过
	var existingReport models.Report
	if err := h.db.Where("reporter_id = ? AND target_id = ? AND target_type = ? AND status = ?",
		user.ID, req.TargetID, req.TargetType, models.ReportStatusPending).First(&existingReport).Error; err == nil {
		response.BadRequest(c, "您已举报过该内容，请等待处理")
		return
	}

	report := models.Report{
		UUID:        uuid.New().String(),
		ReporterID:  user.ID,
		TargetID:    req.TargetID,
		TargetType:  req.TargetType,
		Reason:      req.Reason,
		Description: req.Description,
		Status:      models.ReportStatusPending,
	}

	if err := h.db.Create(&report).Error; err != nil {
		response.ServerError(c, "提交失败")
		return
	}

	response.Success(c, gin.H{
		"id":      report.UUID,
		"message": "举报已提交",
	})
}

// ListReports 获取举报列表（管理员）
func (h *ReportHandler) ListReports(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	status := c.Query("status")
	targetType := c.Query("target_type")
	reason := c.Query("reason")

	offset := (page - 1) * pageSize

	query := h.db.Model(&models.Report{})

	if status != "" {
		statusInt, _ := strconv.Atoi(status)
		query = query.Where("status = ?", statusInt)
	}

	if targetType != "" {
		query = query.Where("target_type = ?", targetType)
	}

	if reason != "" {
		query = query.Where("reason = ?", reason)
	}

	var total int64
	query.Count(&total)

	var reports []models.Report
	if err := query.Preload("Reporter").
		Order("created_at DESC").
		Offset(offset).Limit(pageSize).
		Find(&reports).Error; err != nil {
		response.ServerError(c, "获取失败")
		return
	}

	// 构建响应
	list := make([]gin.H, 0, len(reports))
	for _, r := range reports {
		item := gin.H{
			"id":           r.UUID,
			"reporter_id":  r.Reporter.UUID,
			"reporter":     r.Reporter.Nickname,
			"target_id":    r.TargetID,
			"target_type":  r.TargetType,
			"reason":       r.Reason,
			"reason_text":  models.GetReasonText(r.Reason),
			"description":  r.Description,
			"status":       r.Status,
			"process_note": r.ProcessNote,
			"created_at":   r.CreatedAt,
			"processed_at": r.ProcessedAt,
		}

		// 获取被举报对象信息
		switch r.TargetType {
		case models.ReportTypeUser:
			var targetUser models.User
			if err := h.db.Where("uuid = ?", r.TargetID).First(&targetUser).Error; err == nil {
				item["target_name"] = targetUser.Nickname
				item["target_username"] = targetUser.Username
				item["target_avatar"] = targetUser.Avatar
			} else {
				// 如果找不到用户，使用 target_id 作为名称
				item["target_name"] = "用户 " + r.TargetID[:8]
				item["target_username"] = ""
				item["target_avatar"] = ""
			}
		case models.ReportTypeGroup, models.ReportTypeChannel:
			var targetChat models.Chat
			if err := h.db.Where("uuid = ?", r.TargetID).First(&targetChat).Error; err == nil {
				item["target_name"] = targetChat.Name
				item["target_username"] = targetChat.Username
				item["target_avatar"] = targetChat.Avatar
			} else {
				item["target_name"] = "会话 " + r.TargetID[:8]
				item["target_username"] = ""
				item["target_avatar"] = ""
			}
		default:
			item["target_name"] = r.TargetID[:8]
			item["target_username"] = ""
			item["target_avatar"] = ""
		}

		list = append(list, item)
	}

	response.Success(c, gin.H{
		"list":  list,
		"total": total,
		"page":  page,
	})
}

// ProcessReportRequest 处理举报请求
type ProcessReportRequest struct {
	Status      int    `json:"status" binding:"required,oneof=1 2"` // 1-已处理, 2-已驳回
	ProcessNote string `json:"process_note"`
}

// ProcessReport 处理举报（管理员）
func (h *ReportHandler) ProcessReport(c *gin.Context) {
	reportID := c.Param("id")

	var req ProcessReportRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	// 获取管理员ID（admin_id 是 uint64 类型）
	adminID, exists := c.Get("admin_id")
	if !exists || adminID == nil {
		response.Unauthorized(c, "请先登录")
		return
	}

	var report models.Report
	if err := h.db.Where("uuid = ?", reportID).First(&report).Error; err != nil {
		response.NotFound(c, "举报不存在")
		return
	}

	if report.Status != models.ReportStatusPending {
		response.BadRequest(c, "该举报已处理")
		return
	}

	now := time.Now()
	updates := map[string]interface{}{
		"status":       req.Status,
		"processed_by": adminID.(uint64),
		"processed_at": now,
		"process_note": req.ProcessNote,
	}

	if err := h.db.Model(&report).Updates(updates).Error; err != nil {
		response.ServerError(c, "处理失败")
		return
	}

	// 如果是已处理状态，可以对被举报对象进行相应操作
	if req.Status == models.ReportStatusProcessed {
		// TODO: 根据举报类型和严重程度，对被举报对象进行警告、禁言、封禁等操作
	}

	response.Success(c, gin.H{
		"message": "处理成功",
	})
}

// GetReportStats 获取举报统计
func (h *ReportHandler) GetReportStats(c *gin.Context) {
	var stats struct {
		Total     int64 `json:"total"`
		Pending   int64 `json:"pending"`
		Processed int64 `json:"processed"`
		Rejected  int64 `json:"rejected"`
		Today     int64 `json:"today"`
	}

	h.db.Model(&models.Report{}).Count(&stats.Total)
	h.db.Model(&models.Report{}).Where("status = ?", models.ReportStatusPending).Count(&stats.Pending)
	h.db.Model(&models.Report{}).Where("status = ?", models.ReportStatusProcessed).Count(&stats.Processed)
	h.db.Model(&models.Report{}).Where("status = ?", models.ReportStatusRejected).Count(&stats.Rejected)

	today := time.Now().Truncate(24 * time.Hour)
	h.db.Model(&models.Report{}).Where("created_at >= ?", today).Count(&stats.Today)

	// 按类型统计
	var typeStats []struct {
		TargetType string
		Count      int64
	}
	h.db.Model(&models.Report{}).
		Select("target_type, count(*) as count").
		Group("target_type").
		Find(&typeStats)

	// 按原因统计
	var reasonStats []struct {
		Reason string
		Count  int64
	}
	h.db.Model(&models.Report{}).
		Select("reason, count(*) as count").
		Group("reason").
		Find(&reasonStats)

	response.Success(c, gin.H{
		"overview":  stats,
		"by_type":   typeStats,
		"by_reason": reasonStats,
	})
}

// DeleteReport 删除举报记录（管理员）
func (h *ReportHandler) DeleteReport(c *gin.Context) {
	reportID := c.Param("id")

	result := h.db.Where("uuid = ?", reportID).Delete(&models.Report{})
	if result.Error != nil {
		response.ServerError(c, "删除失败")
		return
	}

	if result.RowsAffected == 0 {
		response.NotFound(c, "举报不存在")
		return
	}

	response.Success(c, gin.H{
		"message": "删除成功",
	})
}
