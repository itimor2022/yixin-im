package handlers

import (
	"gaoranim/internal/models"
	"gaoranim/internal/ws"
	"gaoranim/pkg/response"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type BroadcastHandler struct {
	hub *ws.Hub
	db  *gorm.DB
}

func NewBroadcastHandler(hub *ws.Hub, db *gorm.DB) *BroadcastHandler {
	return &BroadcastHandler{hub: hub, db: db}
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

	onlineCount := h.hub.GetOnlineCount()

	// ★ 集群改造：使用 SendToAllCluster 确保广播到所有节点的在线用户
	h.hub.SendToAllCluster(map[string]interface{}{
		"type":    "system_announcement",
		"title":   req.Title,
		"content": req.Content,
		"subtype": req.Type,
		"time":    time.Now().Format("2006-01-02 15:04:05"),
	})

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
	h.db.Create(&record)

	response.SuccessWithMessage(c, "公告发送成功", map[string]interface{}{
		"online_count": onlineCount,
	})
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
