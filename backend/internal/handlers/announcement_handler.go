// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"strconv"
	"strings"
	"time"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/internal/ws"
	"genericim/pkg/response"
)

type AnnouncementHandler struct {
	db   *gorm.DB
	hub  *ws.Hub
	push *services.PushService
}

// getChatMemberUUIDs 获取群成员的 UUID 列表
func (h *AnnouncementHandler) getChatMemberUUIDs(chatID uint64) []string {
	var uuids []string
	h.db.Table("users").
		Joins("JOIN chat_members ON chat_members.user_id = users.id").
		Where("chat_members.chat_id = ?", chatID).
		Pluck("users.uuid", &uuids)
	return uuids
}

func NewAnnouncementHandler(db *gorm.DB, hub *ws.Hub, push *services.PushService) *AnnouncementHandler {
	return &AnnouncementHandler{db: db, hub: hub, push: push}
}

type CreateAnnouncementRequest struct {
	Content string `json:"content" binding:"required"`
}

func (h *AnnouncementHandler) CreateAnnouncement(c *gin.Context) {
	userID := c.GetString("user_id")
	chatUUID := c.Param("id")

	var req CreateAnnouncementRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "请输入公告内容")
		return
	}
	req.Content = strings.TrimSpace(req.Content)
	if req.Content == "" {
		response.BadRequest(c, "请输入公告内容")
		return
	}
	if len([]rune(req.Content)) > 5000 {
		response.BadRequest(c, "公告内容不能超过5000个字符")
		return
	}
	if filtered, blocked := filterContentWithDB(h.db, req.Content); blocked {
		response.BadRequest(c, "公告包含不允许的内容")
		return
	} else {
		req.Content = filtered
	}

	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return
	}

	var currentUser models.User
	h.db.Where("uuid = ?", userID).First(&currentUser)

	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&member).Error; err != nil {
		response.Forbidden(c, "您不是该群成员")
		return
	}
	if member.Role < 1 {
		response.Forbidden(c, "仅管理员可以发布公告")
		return
	}
	now := time.Now()
	announcement := models.ChatAnnouncement{
		ChatID:    chat.ID,
		Content:   req.Content,
		AuthorID:  currentUser.ID,
		IsPinned:  true,
		CreatedAt: now,
		UpdatedAt: now,
	}
	if err := h.db.Create(&announcement).Error; err != nil {
		response.ServerError(c, "发布失败")
		return
	}
	// 发布者默认已确认，避免确认进度永远少一人。
	h.db.Create(&models.ChatAnnouncementAcknowledgement{
		AnnouncementID: announcement.ID,
		UserID:         currentUser.ID,
		AcknowledgedAt: now,
	})
	memberUUIDs := h.getChatMemberUUIDs(chat.ID)
	if h.hub != nil && len(memberUUIDs) > 0 {
		h.hub.SendToUsers(memberUUIDs, map[string]interface{}{
			"type":        "chat_announcement",
			"chat_id":     chatUUID,
			"content":     req.Content,
			"author_id":   userID,
			"author_name": currentUser.Nickname,
			"created_at":  now.Format("2006-01-02 15:04:05"),
		})
	}
	if h.push != nil {
		var targetUserIDs []uint64
		if err := h.db.Model(&models.ChatMember{}).
			Where("chat_id = ? AND user_id != ?", chat.ID, currentUser.ID).
			Pluck("user_id", &targetUserIDs).Error; err == nil {
			for _, targetUserID := range targetUserIDs {
				targetID := targetUserID
				go func() {
					_ = h.push.PushChatAnnouncement(targetID, chatUUID, announcement.ID)
				}()
			}
		}
	}
	response.Success(c, announcement)
}

func (h *AnnouncementHandler) UpdateAnnouncement(c *gin.Context) {
	userID := c.GetString("user_id")
	chatUUID := c.Param("id")
	announcementID := c.Param("announcement_id")

	var req CreateAnnouncementRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "请输入公告内容")
		return
	}
	req.Content = strings.TrimSpace(req.Content)
	if req.Content == "" {
		response.BadRequest(c, "请输入公告内容")
		return
	}
	if len([]rune(req.Content)) > 5000 {
		response.BadRequest(c, "公告内容不能超过5000个字符")
		return
	}
	if filtered, blocked := filterContentWithDB(h.db, req.Content); blocked {
		response.BadRequest(c, "公告包含不允许的内容")
		return
	} else {
		req.Content = filtered
	}

	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return
	}

	var currentUser models.User
	h.db.Where("uuid = ?", userID).First(&currentUser)

	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&member).Error; err != nil {
		response.Forbidden(c, "您不是该群成员")
		return
	}
	if member.Role < 1 {
		response.Forbidden(c, "仅管理员可以修改公告")
		return
	}
	h.db.Model(&models.ChatAnnouncement{}).Where("id = ? AND chat_id = ?", announcementID, chat.ID).Updates(map[string]interface{}{
		"content":    req.Content,
		"updated_at": time.Now(),
	})
	memberUUIDs := h.getChatMemberUUIDs(chat.ID)
	if h.hub != nil && len(memberUUIDs) > 0 {
		h.hub.SendToUsers(memberUUIDs, map[string]interface{}{
			"type":    "chat_announcement_updated",
			"chat_id": chatUUID,
			"content": req.Content,
		})
	}
	response.SuccessWithMessage(c, "公告已更新", nil)
}

func (h *AnnouncementHandler) DeleteAnnouncement(c *gin.Context) {
	userID := c.GetString("user_id")
	chatUUID := c.Param("id")
	announcementID := c.Param("announcement_id")

	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return
	}

	var currentUser models.User
	h.db.Where("uuid = ?", userID).First(&currentUser)

	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&member).Error; err != nil {
		response.Forbidden(c, "您不是该群成员")
		return
	}
	if member.Role < 1 {
		response.Forbidden(c, "仅管理员可以删除公告")
		return
	}
	h.db.Where("announcement_id = ?", announcementID).Delete(&models.ChatAnnouncementAcknowledgement{})
	h.db.Where("id = ? AND chat_id = ?", announcementID, chat.ID).Delete(&models.ChatAnnouncement{})
	memberUUIDs := h.getChatMemberUUIDs(chat.ID)
	if h.hub != nil && len(memberUUIDs) > 0 {
		h.hub.SendToUsers(memberUUIDs, map[string]interface{}{
			"type":    "chat_announcement_deleted",
			"chat_id": chatUUID,
		})
	}
	response.SuccessWithMessage(c, "公告已删除", nil)
}

func (h *AnnouncementHandler) GetAnnouncements(c *gin.Context) {
	userUUID := c.GetString("user_id")
	chatUUID := c.Param("id")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 20
	}

	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return
	}
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&currentUser).Error; err != nil {
		response.Unauthorized(c, "用户不存在")
		return
	}
	var currentMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&currentMember).Error; err != nil {
		response.Forbidden(c, "您不是该群成员")
		return
	}

	var total int64
	h.db.Model(&models.ChatAnnouncement{}).Where("chat_id = ?", chat.ID).Count(&total)

	var announcements []models.ChatAnnouncement
	h.db.Where("chat_id = ?", chat.ID).
		Order("created_at DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&announcements)

	// 批量获取作者信息（替代 N+1 查询）
	authorIDs := make([]uint64, 0, len(announcements))
	for _, a := range announcements {
		authorIDs = append(authorIDs, a.AuthorID)
	}
	authorMap := make(map[uint64]models.User)
	if len(authorIDs) > 0 {
		var authors []models.User
		h.db.Select("id, nickname, avatar").Where("id IN ?", authorIDs).Find(&authors)
		for _, a := range authors {
			authorMap[a.ID] = a
		}
	}

	type AnnouncementWithAuthor struct {
		models.ChatAnnouncement
		AuthorName        string `json:"author_name"`
		AuthorAvatar      string `json:"author_avatar"`
		Acknowledged      bool   `json:"acknowledged"`
		AcknowledgedCount int64  `json:"acknowledged_count"`
		MemberCount       int64  `json:"member_count"`
	}
	announcementIDs := make([]uint64, 0, len(announcements))
	for _, announcement := range announcements {
		announcementIDs = append(announcementIDs, announcement.ID)
	}
	type acknowledgementCount struct {
		AnnouncementID uint64 `gorm:"column:announcement_id"`
		Count          int64  `gorm:"column:count"`
	}
	ackCounts := make(map[uint64]int64)
	acknowledged := make(map[uint64]bool)
	if len(announcementIDs) > 0 {
		var counts []acknowledgementCount
		h.db.Model(&models.ChatAnnouncementAcknowledgement{}).
			Select("announcement_id, COUNT(*) AS count").
			Where("announcement_id IN ?", announcementIDs).
			Group("announcement_id").Scan(&counts)
		for _, count := range counts {
			ackCounts[count.AnnouncementID] = count.Count
		}
		var ownAckIDs []uint64
		h.db.Model(&models.ChatAnnouncementAcknowledgement{}).
			Where("announcement_id IN ? AND user_id = ?", announcementIDs, currentUser.ID).
			Pluck("announcement_id", &ownAckIDs)
		for _, id := range ownAckIDs {
			acknowledged[id] = true
		}
	}
	var memberCount int64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Count(&memberCount)
	result := make([]AnnouncementWithAuthor, 0, len(announcements))
	for _, a := range announcements {
		author := authorMap[a.AuthorID]
		result = append(result, AnnouncementWithAuthor{
			ChatAnnouncement:  a,
			AuthorName:        author.Nickname,
			AuthorAvatar:      author.Avatar,
			Acknowledged:      acknowledged[a.ID],
			AcknowledgedCount: ackCounts[a.ID],
			MemberCount:       memberCount,
		})
	}
	response.Success(c, gin.H{
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func (h *AnnouncementHandler) AcknowledgeAnnouncement(c *gin.Context) {
	chatUUID := c.Param("id")
	announcementID, err := strconv.ParseUint(c.Param("announcement_id"), 10, 64)
	if err != nil || announcementID == 0 {
		response.BadRequest(c, "公告参数错误")
		return
	}
	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", c.GetString("user_id")).First(&user).Error; err != nil {
		response.Unauthorized(c, "用户不存在")
		return
	}
	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).First(&member).Error; err != nil {
		response.Forbidden(c, "您不是该群成员")
		return
	}
	var announcement models.ChatAnnouncement
	if err := h.db.Where("id = ? AND chat_id = ?", announcementID, chat.ID).First(&announcement).Error; err != nil {
		response.NotFound(c, "公告不存在")
		return
	}
	now := time.Now()
	ack := models.ChatAnnouncementAcknowledgement{
		AnnouncementID: announcement.ID,
		UserID:         user.ID,
		AcknowledgedAt: now,
	}
	if err := h.db.Where("announcement_id = ? AND user_id = ?", announcement.ID, user.ID).
		FirstOrCreate(&ack).Error; err != nil {
		response.ServerError(c, "确认失败")
		return
	}
	var count int64
	h.db.Model(&models.ChatAnnouncementAcknowledgement{}).
		Where("announcement_id = ?", announcement.ID).Count(&count)
	if h.hub != nil {
		h.hub.SendToUsers(h.getChatMemberUUIDs(chat.ID), map[string]interface{}{
			"type":               "chat_announcement_acknowledged",
			"chat_id":            chat.UUID,
			"announcement_id":    announcement.ID,
			"user_id":            user.UUID,
			"acknowledged_count": count,
		})
	}
	response.Success(c, gin.H{"acknowledged": true, "acknowledged_count": count})
}
