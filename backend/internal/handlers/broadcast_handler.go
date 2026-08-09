// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"log"
	"strconv"
	"time"
	"genericim/internal/models"
	"genericim/internal/ws"
	"genericim/pkg/response"
)

type BroadcastHandler struct {
	hub  *ws.Hub
	db   *gorm.DB
	push SystemAnnouncementPusher
}

type SystemAnnouncementPusher interface {
	PushSystemAnnouncement(userID uint64, title, content string, broadcastID uint64, subtype string) error
}

func NewBroadcastHandler(hub *ws.Hub, db *gorm.DB, push ...SystemAnnouncementPusher) *BroadcastHandler {
	handler := &BroadcastHandler{hub: hub, db: db}
	if len(push) > 0 {
		handler.push = push[0]
	}
	return handler
}

type BroadcastRequest struct {
	Title   string `json:"title" binding:"required"`
	Content string `json:"content" binding:"required"`
	Type    string `json:"type"`
}

func (h *BroadcastHandler) SendBroadcast(c *gin.Context) {
	var req BroadcastRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	if req.Type == "" {
		req.Type = "announcement"
	}

	var onlineCount int64
	if h.hub != nil {
		onlineCount = h.hub.GetOnlineCount()
	}

	adminID, _ := c.Get("admin_id")
	adminName, _ := c.Get("admin_username")
	aid, _ := adminID.(uint64)
	aname, _ := adminName.(string)
	record := models.SystemBroadcast{
		Title:       req.Title,
		Content:     req.Content,
		Type:        req.Type,
		OnlineCount: onlineCount,
		AdminID:     aid,
		AdminName:   aname,
		CreatedAt:   time.Now(),
	}
	if err := h.db.Create(&record).Error; err != nil {
		response.ServerError(c, "公告保存失败")
		return
	}
	if h.hub != nil {
		h.hub.SendToAll(map[string]interface{}{
			"type":         "system_announcement",
			"broadcast_id": record.ID,
			"title":        req.Title,
			"content":      req.Content,
			"subtype":      req.Type,
			"time":         record.CreatedAt.Format("2006-01-02 15:04:05"),
		})
	}
	if h.push != nil {
		go h.pushPersistedBroadcast(record)
	}
	response.SuccessWithMessage(c, "公告发送成功", map[string]interface{}{
		"broadcast_id": record.ID,
		"online_count": onlineCount,
	})
}

func (h *BroadcastHandler) pushPersistedBroadcast(record models.SystemBroadcast) {
	if h == nil || h.db == nil || h.push == nil || record.ID == 0 {
		return
	}
	var userIDs []uint64
	if err := h.db.Model(&models.User{}).
		Where("status = ?", models.UserStatusNormal).
		Pluck("id", &userIDs).Error; err != nil {
		log.Printf("[Broadcast] list push recipients failed broadcast=%d: %v", record.ID, err)
		return
	}
	for _, userID := range userIDs {
		if err := h.push.PushSystemAnnouncement(
			userID,
			record.Title,
			record.Content,
			record.ID,
			record.Type,
		); err != nil {
			log.Printf("[Broadcast] push failed broadcast=%d user=%d: %v", record.ID, userID, err)
		}
	}
}

func (h *BroadcastHandler) ListBroadcasts(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}

	var total int64
	h.db.Model(&models.SystemBroadcast{}).Count(&total)

	var records []models.SystemBroadcast
	h.db.Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&records)
	response.Success(c, gin.H{
		"list":      records,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func (h *BroadcastHandler) ClearBroadcasts(c *gin.Context) {
	result := h.db.Where("1 = 1").Delete(&models.SystemBroadcast{})
	if result.Error != nil {
		response.ServerError(c, "清理失败")
		return
	}
	response.SuccessWithMessage(c, "公告记录已清空", gin.H{
		"deleted_count": result.RowsAffected,
	})
}

// GetRecentBroadcasts 获取最近的公告（供客户端登录后拉取未读公告）
func (h *BroadcastHandler) GetRecentBroadcasts(c *gin.Context) {
	sinceStr := c.Query("since")
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "10"))
	if limit <= 0 || limit > 50 {
		limit = 10
	}
	query := h.db.Model(&models.SystemBroadcast{}).Order("created_at DESC").Limit(limit)
	if sinceStr != "" {
		if t, err := time.Parse(time.RFC3339, sinceStr); err == nil {
			query = query.Where("created_at > ?", t)
		}
	}

	var records []models.SystemBroadcast
	query.Find(&records)
	response.Success(c, gin.H{
		"list":  records,
		"total": len(records),
	})
}
