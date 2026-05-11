package handlers

import (
	"strconv"
	"time"

	"gaoranim/internal/models"
	"gaoranim/internal/ws"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type AnnouncementHandler struct {
	db  *gorm.DB
	hub *ws.Hub
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

func NewAnnouncementHandler(db *gorm.DB, hub *ws.Hub) *AnnouncementHandler {
	return &AnnouncementHandler{db: db, hub: hub}
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
		AuthorName   string `json:"author_name"`
		AuthorAvatar string `json:"author_avatar"`
	}

	result := make([]AnnouncementWithAuthor, 0, len(announcements))
	for _, a := range announcements {
		author := authorMap[a.AuthorID]
		result = append(result, AnnouncementWithAuthor{
			ChatAnnouncement: a,
			AuthorName:       author.Nickname,
			AuthorAvatar:     author.Avatar,
		})
	}

	response.Success(c, gin.H{
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}
