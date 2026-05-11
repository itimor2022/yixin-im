package handlers

import (
	"net/http"
	"strconv"
	"time"

	"gaoranim/internal/models"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type ChatMgmtHandler struct {
	db *gorm.DB
}

func NewChatMgmtHandler(db *gorm.DB) *ChatMgmtHandler {
	return &ChatMgmtHandler{db: db}
}

// ChatWithMembers 带成员信息的会话
type ChatWithMembers struct {
	models.Chat
	Members     []MemberInfo `json:"members,omitempty"`
	OwnerName   string       `json:"owner_name,omitempty"`
	OwnerAvatar string       `json:"owner_avatar,omitempty"`
}

type MemberInfo struct {
	UserID   uint64 `json:"user_id"`
	UUID     string `json:"uuid"`
	Nickname string `json:"nickname"`
	Avatar   string `json:"avatar"`
}

// ListChats 获取所有会话列表
func (h *ChatMgmtHandler) ListChats(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	chatType := c.Query("type")
	keyword := c.Query("keyword")

	offset := (page - 1) * pageSize

	query := h.db.Model(&models.Chat{})

	if chatType != "" {
		query = query.Where("type = ?", chatType)
	}

	if keyword != "" {
		query = query.Where("name LIKE ?", "%"+keyword+"%")
	}

	var total int64
	query.Count(&total)

	var chats []models.Chat
	if err := query.Order("created_at DESC").Offset(offset).Limit(pageSize).Find(&chats).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	// 为私聊获取参与者信息
	result := make([]ChatWithMembers, 0, len(chats))
	for _, chat := range chats {
		item := ChatWithMembers{Chat: chat}

		if chat.Type == 1 {
			// 私聊：先从 chat_members 获取参与者
			var members []struct {
				UserID   uint64 `json:"user_id"`
				UUID     string `json:"uuid"`
				Username string `json:"username"`
				Nickname string `json:"nickname"`
				Avatar   string `json:"avatar"`
			}
			h.db.Table("chat_members").
				Select("chat_members.user_id, users.uuid, users.username, users.nickname, users.avatar").
				Joins("LEFT JOIN users ON chat_members.user_id = users.id").
				Where("chat_members.chat_id = ?", chat.ID).
				Find(&members)

			// 如果 chat_members 没有记录，尝试从 user_chats 回退获取
			if len(members) == 0 {
				var userChats []models.UserChat
				h.db.Where("chat_id = ?", chat.ID).Find(&userChats)

				userIDs := make([]uint64, 0)
				for _, uc := range userChats {
					userIDs = append(userIDs, uc.UserID)
					if uc.TargetID > 0 {
						userIDs = append(userIDs, uc.TargetID)
					}
				}

				// 去重
				uniqueIDs := make(map[uint64]bool)
				for _, id := range userIDs {
					uniqueIDs[id] = true
				}

				for id := range uniqueIDs {
					var user models.User
					if h.db.Select("id", "uuid", "username", "nickname", "avatar").First(&user, id).Error == nil {
						displayName := user.Nickname
						if displayName == "" {
							displayName = user.Username
						}
						item.Members = append(item.Members, MemberInfo{
							UserID:   user.ID,
							UUID:     user.UUID,
							Nickname: displayName,
							Avatar:   user.Avatar,
						})
					}
				}
			} else {
				for _, m := range members {
					// 优先使用昵称，没有则用用户名
					displayName := m.Nickname
					if displayName == "" {
						displayName = m.Username
					}
					item.Members = append(item.Members, MemberInfo{
						UserID:   m.UserID,
						UUID:     m.UUID,
						Nickname: displayName,
						Avatar:   m.Avatar,
					})
				}
			}

			// 私聊名称为两个用户的显示名
			if len(item.Members) == 2 {
				item.Name = item.Members[0].Nickname + " · " + item.Members[1].Nickname
				item.Description = "私聊对话"
			} else if len(item.Members) == 1 {
				item.Name = item.Members[0].Nickname
				item.Description = "私聊对话"
			} else {
				item.Name = "私聊"
				item.Description = "私聊对话"
			}
		} else {
			// 群组/频道：获取群主信息
			if chat.OwnerID > 0 {
				var owner models.User
				h.db.Select("nickname", "avatar").First(&owner, chat.OwnerID)
				item.OwnerName = owner.Nickname
				item.OwnerAvatar = owner.Avatar
			}
		}

		result = append(result, item)
	}

	response.Success(c, gin.H{
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// ListGroups 获取群组列表
func (h *ChatMgmtHandler) ListGroups(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	keyword := c.Query("keyword")

	offset := (page - 1) * pageSize

	query := h.db.Model(&models.Chat{}).Where("type = ?", 2)

	if keyword != "" {
		query = query.Where("name LIKE ?", "%"+keyword+"%")
	}

	var total int64
	query.Count(&total)

	var groups []models.Chat
	if err := query.Order("member_count DESC").Offset(offset).Limit(pageSize).Find(&groups).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	// 获取群主信息
	ownerIDs := make([]uint64, 0, len(groups))
	for _, g := range groups {
		if g.OwnerID != 0 {
			ownerIDs = append(ownerIDs, g.OwnerID)
		}
	}

	var owners []models.User
	if len(ownerIDs) > 0 {
		h.db.Select("id", "nickname").Where("id IN ?", ownerIDs).Find(&owners)
	}

	ownerMap := make(map[uint64]string)
	for _, o := range owners {
		ownerMap[o.ID] = o.Nickname
	}

	type GroupWithOwner struct {
		models.Chat
		OwnerName string `json:"owner_name"`
	}

	result := make([]GroupWithOwner, 0, len(groups))
	for _, g := range groups {
		ownerName := ""
		if g.OwnerID != 0 {
			ownerName = ownerMap[g.OwnerID]
		}
		result = append(result, GroupWithOwner{
			Chat:      g,
			OwnerName: ownerName,
		})
	}

	response.Success(c, gin.H{
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// ListChannels 获取频道列表
func (h *ChatMgmtHandler) ListChannels(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	keyword := c.Query("keyword")

	offset := (page - 1) * pageSize

	query := h.db.Model(&models.Chat{}).Where("type = ?", 3)

	if keyword != "" {
		query = query.Where("name LIKE ?", "%"+keyword+"%")
	}

	var total int64
	query.Count(&total)

	var channels []models.Chat
	if err := query.Order("member_count DESC").Offset(offset).Limit(pageSize).Find(&channels).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	response.Success(c, gin.H{
		"list":      channels,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// UpdateChatStatus 更新会话状态
func (h *ChatMgmtHandler) UpdateChatStatus(c *gin.Context) {
	chatID := c.Param("id")

	var req struct {
		Status int8 `json:"status" binding:"required,oneof=0 1"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	result := h.db.Model(&models.Chat{}).Where("id = ?", chatID).Update("status", req.Status)
	if result.Error != nil {
		response.Error(c, http.StatusInternalServerError, "更新失败")
		return
	}

	if result.RowsAffected == 0 {
		response.Error(c, http.StatusNotFound, "会话不存在")
		return
	}

	response.Success(c, nil)
}

// DeleteChat 删除会话
func (h *ChatMgmtHandler) DeleteChat(c *gin.Context) {
	chatID := c.Param("id")

	var chat models.Chat
	if err := h.db.First(&chat, chatID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "会话不存在")
		return
	}

	// 软删除
	if err := h.db.Delete(&chat).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "删除失败")
		return
	}

	response.Success(c, nil)
}

// GetChatDetail 获取会话详情
func (h *ChatMgmtHandler) GetChatDetail(c *gin.Context) {
	chatID := c.Param("id")

	var chat models.Chat
	if err := h.db.First(&chat, chatID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "会话不存在")
		return
	}

	// 获取群主信息
	var owner models.User
	if chat.OwnerID > 0 {
		h.db.Select("id", "uuid", "username", "nickname", "avatar").First(&owner, chat.OwnerID)
	}

	// 获取成员列表
	var members []struct {
		models.ChatMember
		UserUUID string `json:"user_uuid"`
		Username string `json:"username"`
		Nickname string `json:"nickname"`
		Avatar   string `json:"avatar"`
	}
	h.db.Table("chat_members").
		Select("chat_members.*, users.uuid as user_uuid, users.username, users.nickname, users.avatar").
		Joins("LEFT JOIN users ON chat_members.user_id = users.id").
		Where("chat_members.chat_id = ?", chat.ID).
		Order("chat_members.role DESC, chat_members.joined_at ASC").
		Limit(100).
		Find(&members)

	response.Success(c, gin.H{
		"chat":    chat,
		"owner":   owner,
		"members": members,
	})
}

// BanChat 封禁群组/频道
func (h *ChatMgmtHandler) BanChat(c *gin.Context) {
	chatID := c.Param("id")

	var req struct {
		Reason string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	var chat models.Chat
	if err := h.db.First(&chat, chatID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "会话不存在")
		return
	}

	if chat.Type == 1 {
		response.Error(c, http.StatusBadRequest, "私聊不能被封禁")
		return
	}

	now := time.Now()
	result := h.db.Model(&chat).Updates(map[string]interface{}{
		"status":     models.ChatStatusBanned,
		"ban_reason": req.Reason,
		"banned_at":  now,
		"updated_at": now,
	})

	if result.Error != nil {
		response.Error(c, http.StatusInternalServerError, "封禁失败")
		return
	}

	response.Success(c, gin.H{
		"message": "已封禁",
		"chat_id": chat.UUID,
	})
}

// UnbanChat 解封群组/频道
func (h *ChatMgmtHandler) UnbanChat(c *gin.Context) {
	chatID := c.Param("id")

	var chat models.Chat
	if err := h.db.First(&chat, chatID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "会话不存在")
		return
	}

	result := h.db.Model(&chat).Updates(map[string]interface{}{
		"status":     models.ChatStatusNormal,
		"ban_reason": "",
		"banned_at":  nil,
		"updated_at": time.Now(),
	})

	if result.Error != nil {
		response.Error(c, http.StatusInternalServerError, "解封失败")
		return
	}

	response.Success(c, gin.H{
		"message": "已解封",
		"chat_id": chat.UUID,
	})
}

// DissolveChat 解散群组/频道
func (h *ChatMgmtHandler) DissolveChat(c *gin.Context) {
	chatID := c.Param("id")

	var chat models.Chat
	if err := h.db.First(&chat, chatID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "会话不存在")
		return
	}

	if chat.Type == 1 {
		response.Error(c, http.StatusBadRequest, "私聊不能被解散")
		return
	}

	// 更新状态为解散
	h.db.Model(&chat).Updates(map[string]interface{}{
		"status":     models.ChatStatusDissolved,
		"updated_at": time.Now(),
	})

	// 删除所有成员
	h.db.Where("chat_id = ?", chat.ID).Delete(&models.ChatMember{})

	// 删除用户会话记录
	h.db.Where("chat_id = ?", chat.ID).Delete(&models.UserChat{})

	response.Success(c, gin.H{
		"message": "已解散",
		"chat_id": chat.UUID,
	})
}

// GetChatMembers 获取成员列表
func (h *ChatMgmtHandler) GetChatMembers(c *gin.Context) {
	chatID := c.Param("id")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "50"))
	offset := (page - 1) * pageSize

	var chat models.Chat
	if err := h.db.First(&chat, chatID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "会话不存在")
		return
	}

	var total int64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Count(&total)

	var members []struct {
		models.ChatMember
		UserUUID     string     `json:"user_uuid"`
		Username     string     `json:"username"`
		Nickname     string     `json:"nickname"`
		Avatar       string     `json:"avatar"`
		LastOnlineAt *time.Time `json:"last_online_at"`
	}
	h.db.Table("chat_members").
		Select("chat_members.*, users.uuid as user_uuid, users.username, users.nickname, users.avatar, users.last_online_at").
		Joins("LEFT JOIN users ON chat_members.user_id = users.id").
		Where("chat_members.chat_id = ?", chat.ID).
		Order("chat_members.role DESC, chat_members.joined_at ASC").
		Offset(offset).
		Limit(pageSize).
		Find(&members)

	response.Success(c, gin.H{
		"list":      members,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// RemoveChatMember 管理员移除成员
func (h *ChatMgmtHandler) RemoveChatMember(c *gin.Context) {
	chatID := c.Param("id")
	memberID := c.Param("member_id")

	var chat models.Chat
	if err := h.db.First(&chat, chatID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "会话不存在")
		return
	}

	// 获取要移除的成员
	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND id = ?", chat.ID, memberID).First(&member).Error; err != nil {
		response.Error(c, http.StatusNotFound, "成员不存在")
		return
	}

	// 不能移除群主（Role: 0=成员 1=管理员 2=群主/创建者）
	if member.Role >= 2 {
		response.Error(c, http.StatusBadRequest, "不能移除群主")
		return
	}

	// 移除成员
	h.db.Delete(&member)

	// 删除用户会话记录
	h.db.Where("chat_id = ? AND user_id = ?", chat.ID, member.UserID).Delete(&models.UserChat{})

	// 更新成员数
	h.db.Model(&chat).Update("member_count", gorm.Expr("member_count - 1"))

	response.Success(c, gin.H{"message": "已移除"})
}

// GetChatStats 获取群组/频道统计
func (h *ChatMgmtHandler) GetChatStats(c *gin.Context) {
	// 总群组数
	var groupCount int64
	h.db.Model(&models.Chat{}).Where("type = 2").Count(&groupCount)

	// 总频道数
	var channelCount int64
	h.db.Model(&models.Chat{}).Where("type = 3").Count(&channelCount)

	// 被封禁数
	var bannedCount int64
	h.db.Model(&models.Chat{}).Where("status = ?", models.ChatStatusBanned).Count(&bannedCount)

	// 今日新增群组
	today := time.Now().Truncate(24 * time.Hour)
	var todayGroupCount int64
	h.db.Model(&models.Chat{}).Where("type = 2 AND created_at >= ?", today).Count(&todayGroupCount)

	// 今日新增频道
	var todayChannelCount int64
	h.db.Model(&models.Chat{}).Where("type = 3 AND created_at >= ?", today).Count(&todayChannelCount)

	// 热门群组（按成员数排序）
	var hotGroups []models.Chat
	h.db.Where("type = 2 AND status = 0").Order("member_count DESC").Limit(10).Find(&hotGroups)

	// 热门频道
	var hotChannels []models.Chat
	h.db.Where("type = 3 AND status = 0").Order("member_count DESC").Limit(10).Find(&hotChannels)

	response.Success(c, gin.H{
		"group_count":         groupCount,
		"channel_count":       channelCount,
		"banned_count":        bannedCount,
		"today_group_count":   todayGroupCount,
		"today_channel_count": todayChannelCount,
		"hot_groups":          hotGroups,
		"hot_channels":        hotChannels,
	})
}
