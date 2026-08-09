// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"encoding/json"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"net/http"
	"strconv"
	"strings"
	"time"
	"genericim/internal/middleware"
	"genericim/internal/models"
	"genericim/pkg/response"
)

type OpsAuditHandler struct {
	db *gorm.DB
}

func NewOpsAuditHandler(db *gorm.DB) *OpsAuditHandler {
	return &OpsAuditHandler{db: db}
}

type adminSecurityEventInput struct {
	EventType string
	Action    string
	Target    string
	Success   bool
	Err       error
	Metadata  map[string]interface{}
}

func recordAdminSecurityEvent(c *gin.Context, db *gorm.DB, input adminSecurityEventInput) {
	if db == nil || c == nil {

		return
	}
	metadata := ""
	if input.Metadata != nil {

		if b, err := json.Marshal(input.Metadata); err == nil {

			metadata = truncateOpsLogText(string(b), 4096)

		}
	}
	errText := ""
	if input.Err != nil {

		errText = truncateOpsLogText(input.Err.Error(), 512)
	}
	item := models.AdminSecurityEvent{

		AdminID: middleware.GetAdminID(c),

		AdminUsername: truncateOpsLogText(getAdminUsername(c), 50),

		AdminRole: truncateOpsLogText(middleware.GetAdminRole(c), 30),

		EventType: truncateOpsLogText(input.EventType, 50),

		Action: truncateOpsLogText(input.Action, 80),

		Target: truncateOpsLogText(input.Target, 160),

		Success: input.Success,

		Error: errText,

		Metadata: metadata,

		IP: truncateOpsLogText(c.ClientIP(), 50),

		UserAgent: truncateOpsLogText(c.Request.UserAgent(), 500),

		CreatedAt: time.Now(),
	}
	_ = db.Create(&item).Error
}
func getAdminUsername(c *gin.Context) string {
	if c == nil {

		return ""
	}
	if raw, exists := c.Get("admin_username"); exists {

		if value, ok := raw.(string); ok {

			return value

		}
	}
	return ""
}
func parseAdminPageParams(c *gin.Context, defaultSize int) (int, int) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", strconv.Itoa(defaultSize)))
	if page <= 0 {

		page = 1
	}
	if pageSize <= 0 || pageSize > 100 {

		pageSize = defaultSize
	}
	return page, pageSize
}
func parseBoolQuery(value string) (bool, bool) {
	value = strings.TrimSpace(value)
	if value == "" {

		return false, false
	}
	return value == "1" || strings.EqualFold(value, "true"), true
} // ListUploadLogs returns recent upload outcomes for operations diagnostics.
func (h *OpsAuditHandler) ListUploadLogs(c *gin.Context) {
	page, pageSize := parseAdminPageParams(c, 20)
	query := h.db.Model(&models.UploadLog{})
	if mediaType := strings.TrimSpace(c.Query("media_type")); mediaType != "" {

		query = query.Where("media_type = ?", mediaType)
	}
	if provider := strings.TrimSpace(c.Query("provider")); provider != "" {

		query = query.Where("provider = ?", provider)
	}
	if success, ok := parseBoolQuery(c.Query("success")); ok {

		query = query.Where("success = ?", success)
	}
	if userID := strings.TrimSpace(c.Query("user_id")); userID != "" {

		query = query.Where("user_id = ?", userID)
	}
	if actorType := strings.TrimSpace(c.Query("actor_type")); actorType != "" {

		query = query.Where("actor_type = ?", actorType)
	}
	var total int64
	if err := query.Count(&total).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "查询上传日志失败")

		return
	}
	var rows []models.UploadLog
	if err := query.Order("created_at DESC, id DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&rows).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "查询上传日志失败")

		return
	}
	list := make([]gin.H, 0, len(rows))
	for _, item := range rows {

		list = append(list, gin.H{

			"id": item.ID,

			"actor_type": item.ActorType,

			"user_id": item.UserID,

			"admin_id": item.AdminID,

			"media_type": item.MediaType,

			"provider": item.Provider,

			"object_key": item.ObjectKey,

			"url": item.URL,

			"file_name": item.FileName,

			"content_type": item.ContentType,

			"size": item.Size,

			"success": item.Success,

			"error": item.Error,

			"duration_ms": item.DurationMS,

			"ip": item.IP,

			"created_at": formatAdminTime(item.CreatedAt),
		})
	}
	response.Success(c, gin.H{

		"list": list,

		"total": total,

		"page": page,

		"page_size": pageSize,
	})
} // ListMediaObjects returns lifecycle state for uploaded media.
func (h *OpsAuditHandler) ListMediaObjects(c *gin.Context) {
	page, pageSize := parseAdminPageParams(c, 20)
	query := h.db.Model(&models.MediaObject{})
	if status := strings.TrimSpace(c.Query("status")); status != "" {

		query = query.Where("status = ?", status)
	}
	if category := strings.TrimSpace(c.Query("category")); category != "" {

		query = query.Where("category = ?", category)
	}
	if provider := strings.TrimSpace(c.Query("provider")); provider != "" {

		query = query.Where("provider = ?", provider)
	}
	if userID := strings.TrimSpace(c.Query("user_id")); userID != "" {

		query = query.Where("user_id = ?", userID)
	}
	var total int64
	if err := query.Count(&total).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "查询媒体对象失败")

		return
	}
	var rows []models.MediaObject
	if err := query.Order("created_at DESC, id DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&rows).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "查询媒体对象失败")

		return
	}
	response.Success(c, gin.H{

		"list": rows,

		"total": total,

		"page": page,

		"page_size": pageSize,
	})
} // ListSecurityEvents returns admin operation audit events.
func (h *OpsAuditHandler) ListSecurityEvents(c *gin.Context) {
	page, pageSize := parseAdminPageParams(c, 20)
	query := h.db.Model(&models.AdminSecurityEvent{})
	if eventType := strings.TrimSpace(c.Query("event_type")); eventType != "" {

		query = query.Where("event_type = ?", eventType)
	}
	if action := strings.TrimSpace(c.Query("action")); action != "" {

		query = query.Where("action LIKE ?", "%"+action+"%")
	}
	if username := strings.TrimSpace(c.Query("admin_username")); username != "" {

		query = query.Where("admin_username LIKE ?", "%"+username+"%")
	}
	if success, ok := parseBoolQuery(c.Query("success")); ok {

		query = query.Where("success = ?", success)
	}
	var total int64
	if err := query.Count(&total).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "查询安全事件失败")

		return
	}
	var rows []models.AdminSecurityEvent
	if err := query.Order("created_at DESC, id DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&rows).Error; err != nil {

		response.Error(c, http.StatusInternalServerError, "查询安全事件失败")

		return
	}
	list := make([]gin.H, 0, len(rows))
	for _, item := range rows {

		list = append(list, gin.H{

			"id": item.ID,

			"admin_id": item.AdminID,

			"admin_username": item.AdminUsername,

			"admin_role": item.AdminRole,

			"event_type": item.EventType,

			"action": item.Action,

			"target": item.Target,

			"success": item.Success,

			"error": item.Error,

			"metadata": item.Metadata,

			"ip": item.IP,

			"user_agent": item.UserAgent,

			"created_at": formatAdminTime(item.CreatedAt),
		})
	}
	response.Success(c, gin.H{

		"list": list,

		"total": total,

		"page": page,

		"page_size": pageSize,
	})
}
