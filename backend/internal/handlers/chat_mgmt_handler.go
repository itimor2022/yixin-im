// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"context"
	"errors"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"net/http"
	"strconv"
	"strings"
	"time"
	"genericim/internal/cache"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/internal/ws"
	"genericim/pkg/response"
)

type ChatMgmtHandler struct {
	db         *gorm.DB
	cache      *cache.Cache
	hub        *ws.Hub
	msgService *services.MessageService
}

var (
	errAdminChatBanned          = errors.New("admin chat is banned")
	errAdminChatDissolved       = errors.New("admin chat is dissolved")
	errAdminChatFull            = errors.New("admin chat is full")
	errAdminJoinRequestReviewed = errors.New("admin join request reviewed")
	errAdminUserUnavailable     = errors.New("admin user unavailable")
	errAdminAlreadyOwner        = errors.New("admin member already owner")
)

func NewChatMgmtHandler(db *gorm.DB, c *cache.Cache, hub *ws.Hub, msgService *services.MessageService) *ChatMgmtHandler {
	return &ChatMgmtHandler{db: db, cache: c, hub: hub, msgService: msgService}
}

func parseAdminPagination(c *gin.Context, defaultPageSize int, maxPageSize int) (int, int, int) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", strconv.Itoa(defaultPageSize)))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 {
		pageSize = defaultPageSize
	}
	if maxPageSize > 0 && pageSize > maxPageSize {
		pageSize = maxPageSize
	}
	return page, pageSize, (page - 1) * pageSize
}

func rejectPrivateChat(c *gin.Context, chat models.Chat, message string) bool {
	if chat.Type == 1 {
		response.Error(c, http.StatusBadRequest, message)
		return true
	}
	return false
}

func rejectDissolvedChat(c *gin.Context, chat models.Chat, action string) bool {
	if chat.Status == models.ChatStatusDissolved {
		response.Error(c, http.StatusBadRequest, "已解散的群不能"+action)
		return true
	}
	return false
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
	status := c.Query("status")
	offset := (page - 1) * pageSize

	query := h.db.Model(&models.Chat{})
	if chatType != "" {
		query = query.Where("type = ?", chatType)
	}
	if status != "" {
		query = query.Where("status = ?", status)
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
	page, pageSize, offset := parseAdminPagination(c, 20, 100)
	keyword := strings.TrimSpace(c.Query("keyword"))
	status := c.Query("status")
	query := h.db.Model(&models.Chat{}).Where("chats.type = ?", 2)
	if keyword != "" {
		likeKeyword := "%" + keyword + "%"
		query = query.
			Joins("LEFT JOIN users AS owners ON owners.id = chats.owner_id").
			Where(
				"(chats.name LIKE ? OR chats.description LIKE ? OR chats.username LIKE ? OR chats.uuid = ? OR owners.username LIKE ? OR owners.nickname LIKE ?)",
				likeKeyword,
				likeKeyword,
				likeKeyword,
				keyword,
				likeKeyword,
				likeKeyword,
			)
	}
	if status != "" {
		query = query.Where("chats.status = ?", status)
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	var groups []models.Chat
	if err := query.
		Select("chats.*").
		Order("chats.member_count DESC, chats.created_at DESC").
		Offset(offset).
		Limit(pageSize).
		Find(&groups).Error; err != nil {
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
		h.db.Select("id", "username", "nickname", "avatar").Where("id IN ?", ownerIDs).Find(&owners)
	}
	ownerMap := make(map[uint64]models.User)
	for _, o := range owners {
		ownerMap[o.ID] = o
	}

	type GroupWithOwner struct {
		models.Chat
		OwnerName   string `json:"owner_name"`
		OwnerAvatar string `json:"owner_avatar"`
	}
	result := make([]GroupWithOwner, 0, len(groups))
	for _, g := range groups {
		ownerName := ""
		ownerAvatar := ""
		if g.OwnerID != 0 {
			if owner, ok := ownerMap[g.OwnerID]; ok {
				ownerName = owner.Nickname
				if ownerName == "" {
					ownerName = owner.Username
				}
				ownerAvatar = owner.Avatar
			}
		}
		result = append(result, GroupWithOwner{
			Chat:        g,
			OwnerName:   ownerName,
			OwnerAvatar: ownerAvatar,
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
	status := c.Query("status")
	offset := (page - 1) * pageSize

	query := h.db.Model(&models.Chat{}).Where("type = ?", 3)
	if keyword != "" {
		query = query.Where("name LIKE ?", "%"+keyword+"%")
	}
	if status != "" {
		query = query.Where("status = ?", status)
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

type updateChatInfoRequest struct {
	Name             *string `json:"name"`
	Avatar           *string `json:"avatar"`
	Description      *string `json:"description"`
	Username         *string `json:"username"`
	MaxMembers       *int    `json:"max_members"`
	IsPublic         *bool   `json:"is_public"`
	CanSendMessage   *bool   `json:"can_send_message"`
	CanSendMedia     *bool   `json:"can_send_media"`
	CanSendLinks     *bool   `json:"can_send_links"`
	CanAddMembers    *bool   `json:"can_add_members"`
	CanPinMessages   *bool   `json:"can_pin_messages"`
	MemberProtection *bool   `json:"member_protection"`
	JoinApproval     *bool   `json:"join_approval"`
}

// UpdateChatInfo updates group/channel profile and permission settings.
func (h *ChatMgmtHandler) UpdateChatInfo(c *gin.Context) {
	chatID := c.Param("id")

	var req updateChatInfoRequest
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
		response.Error(c, http.StatusBadRequest, "私聊不能编辑群资料")
		return
	}
	if chat.Status == models.ChatStatusDissolved {
		response.Error(c, http.StatusBadRequest, "已解散的群不能编辑")
		return
	}
	updates := map[string]interface{}{"updated_at": time.Now()}
	if req.Name != nil {
		name := strings.TrimSpace(*req.Name)
		if name == "" || len([]rune(name)) > 100 {
			response.Error(c, http.StatusBadRequest, "群名称长度需为 1-100 个字符")
			return
		}
		updates["name"] = name
	}
	if req.Avatar != nil {
		updates["avatar"] = strings.TrimSpace(*req.Avatar)
	}
	if req.Description != nil {
		description := strings.TrimSpace(*req.Description)
		if len([]rune(description)) > 1000 {
			response.Error(c, http.StatusBadRequest, "群简介不能超过 1000 个字符")
			return
		}
		updates["description"] = description
	}
	if req.Username != nil {
		username := strings.TrimSpace(*req.Username)
		if len([]rune(username)) > 32 {
			response.Error(c, http.StatusBadRequest, "公开账号不能超过 32 个字符")
			return
		}
		if username != "" {
			var count int64
			h.db.Model(&models.Chat{}).
				Where("username = ? AND id <> ?", username, chat.ID).
				Count(&count)
			if count > 0 {
				response.Error(c, http.StatusBadRequest, "公开账号已被占用")
				return
			}
		}
		updates["username"] = username
	}
	if req.MaxMembers != nil {
		if *req.MaxMembers < 0 {
			response.Error(c, http.StatusBadRequest, "成员上限不能小于 0")
			return
		}
		if *req.MaxMembers > 0 && *req.MaxMembers < chat.MemberCount {
			response.Error(c, http.StatusBadRequest, "成员上限不能小于当前成员数")
			return
		}
		updates["max_members"] = *req.MaxMembers
	}
	if req.IsPublic != nil {
		updates["is_public"] = *req.IsPublic
	}
	if req.CanSendMessage != nil {
		updates["can_send_message"] = *req.CanSendMessage
	}
	if req.CanSendMedia != nil {
		updates["can_send_media"] = *req.CanSendMedia
	}
	if req.CanSendLinks != nil {
		updates["can_send_links"] = *req.CanSendLinks
	}
	if req.CanAddMembers != nil {
		updates["can_add_members"] = *req.CanAddMembers
	}
	if req.CanPinMessages != nil {
		updates["can_pin_messages"] = *req.CanPinMessages
	}
	if req.MemberProtection != nil {
		updates["member_protection"] = *req.MemberProtection
	}
	if req.JoinApproval != nil {
		updates["join_approval"] = *req.JoinApproval
	}
	if err := h.db.Model(&chat).Updates(updates).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "保存失败")
		return
	}
	if err := h.db.First(&chat, chat.ID).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "读取群资料失败")
		return
	}
	response.Success(c, chat)
}

// UpdateChatStatus 更新会话状态
func (h *ChatMgmtHandler) UpdateChatStatus(c *gin.Context) {
	chatID := c.Param("id")

	var req struct {
		Status *int8 `json:"status" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	if req.Status == nil || (*req.Status != models.ChatStatusNormal && *req.Status != models.ChatStatusBanned) {
		response.Error(c, http.StatusBadRequest, "状态只能设置为正常或封禁")
		return
	}

	var chat models.Chat
	if err := h.db.First(&chat, chatID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "会话不存在")
		return
	}
	if *req.Status == models.ChatStatusBanned && rejectPrivateChat(c, chat, "私聊不能被封禁") {
		return
	}
	if rejectDissolvedChat(c, chat, "更新状态") {
		return
	}
	updates := map[string]interface{}{
		"status":     *req.Status,
		"updated_at": time.Now(),
	}
	if *req.Status == models.ChatStatusNormal {
		updates["ban_reason"] = ""
		updates["banned_at"] = nil
	}
	result := h.db.Model(&chat).Updates(updates)
	if result.Error != nil {
		response.Error(c, http.StatusInternalServerError, "更新失败")
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
	err := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("chat_id = ?", chat.ID).Delete(&models.ChatMember{}).Error; err != nil {
			return err
		}
		if err := tx.Where("chat_id = ?", chat.ID).Delete(&models.UserChat{}).Error; err != nil {
			return err
		}
		if err := tx.Where("chat_id = ?", chat.ID).Delete(&models.JoinRequest{}).Error; err != nil {
			return err
		}
		return tx.Delete(&chat).Error
	})
	if err != nil {
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
	type adminChatMember struct {
		ID             uint64     `json:"id"`
		ChatID         uint64     `json:"chat_id"`
		UserID         uint64     `json:"user_id"`
		Role           int8       `json:"role"`
		NicknameInChat string     `json:"nickname_in_chat"`
		IsMuted        bool       `json:"is_muted"`
		MuteEndTime    *time.Time `json:"mute_end_time"`
		JoinedAt       time.Time  `json:"joined_at"`
		UserUUID       string     `json:"user_uuid"`
		Username       string     `json:"username"`
		Nickname       string     `json:"nickname"`
		Avatar         string     `json:"avatar"`
	}
	var rawMembers []struct {
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
		Find(&rawMembers)
	members := make([]adminChatMember, 0, len(rawMembers))
	for _, m := range rawMembers {
		members = append(members, adminChatMember{
			ID:             m.ID,
			ChatID:         m.ChatID,
			UserID:         m.UserID,
			Role:           m.Role + 1,
			NicknameInChat: m.ChatMember.Nickname,
			IsMuted:        m.IsMuted,
			MuteEndTime:    m.MuteEndTime,
			JoinedAt:       m.JoinedAt,
			UserUUID:       m.UserUUID,
			Username:       m.Username,
			Nickname:       m.Nickname,
			Avatar:         m.Avatar,
		})
	}
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
	if rejectPrivateChat(c, chat, "私聊不能被封禁") {
		return
	}
	if rejectDissolvedChat(c, chat, "封禁") {
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
	if rejectPrivateChat(c, chat, "私聊不能被解封") {
		return
	}
	if rejectDissolvedChat(c, chat, "解封") {
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
	if rejectPrivateChat(c, chat, "私聊不能被解散") {
		return
	}
	if chat.Status == models.ChatStatusDissolved {
		response.Error(c, http.StatusBadRequest, "群已解散")
		return
	}

	var memberUserIDs []uint64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Pluck("user_id", &memberUserIDs)
	var memberUUIDs []string
	if len(memberUserIDs) > 0 {
		h.db.Model(&models.User{}).Where("id IN ?", memberUserIDs).Pluck("uuid", &memberUUIDs)
	}
	err := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&chat, chat.ID).Error; err != nil {
			return err
		}
		if chat.Status == models.ChatStatusDissolved {
			return errAdminChatDissolved
		}
		now := time.Now()
		if err := tx.Model(&chat).Updates(map[string]interface{}{
			"status":     models.ChatStatusDissolved,
			"updated_at": now,
		}).Error; err != nil {
			return err
		}
		return tx.Model(&models.UserChat{}).Where("chat_id = ?", chat.ID).
			Updates(map[string]interface{}{"updated_at": now}).Error
	})
	if err != nil {
		if errors.Is(err, errAdminChatDissolved) {
			response.Error(c, http.StatusBadRequest, "群已解散")
			return
		}
		response.Error(c, http.StatusInternalServerError, "解散失败")
		return
	}

	deleteUserChatListHotCache(c.Request.Context(), h.cache, memberUserIDs...)
	if h.msgService != nil {
		h.msgService.InvalidateMessageWindowCache(c.Request.Context(), chat.UUID)
	}
	if h.hub != nil && len(memberUUIDs) > 0 {
		h.hub.Broadcast(&ws.BroadcastMessage{
			UserIDs: memberUUIDs,
			Data: map[string]interface{}{
				"type":      "chat_dissolved",
				"chat_id":   chat.UUID,
				"status":    models.ChatStatusDissolved,
				"read_only": true,
			},
		})
	}
	response.Success(c, gin.H{
		"message": "已解散",
		"chat_id": chat.UUID,
	})
}

// GetChatMembers 获取成员列表
func (h *ChatMgmtHandler) GetChatMembers(c *gin.Context) {
	chatID := c.Param("id")
	page, pageSize, offset := parseAdminPagination(c, 50, 200)
	keyword := strings.TrimSpace(c.Query("keyword"))

	var chat models.Chat
	if err := h.db.First(&chat, chatID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "会话不存在")
		return
	}
	query := h.db.Table("chat_members").
		Joins("LEFT JOIN users ON chat_members.user_id = users.id").
		Where("chat_members.chat_id = ?", chat.ID)
	if keyword != "" {
		likeKeyword := "%" + keyword + "%"
		query = query.Where(
			"(chat_members.nickname LIKE ? OR users.username LIKE ? OR users.nickname LIKE ? OR users.uuid = ?)",
			likeKeyword,
			likeKeyword,
			likeKeyword,
			keyword,
		)
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	var rawMembers []struct {
		models.ChatMember
		UserUUID     string     `json:"user_uuid"`
		Username     string     `json:"username"`
		Nickname     string     `json:"nickname"`
		Avatar       string     `json:"avatar"`
		LastOnlineAt *time.Time `json:"last_online_at"`
	}
	if err := query.
		Select("chat_members.*, users.uuid as user_uuid, users.username, users.nickname, users.avatar, users.last_seen as last_online_at").
		Order("chat_members.role DESC, chat_members.joined_at ASC").
		Offset(offset).
		Limit(pageSize).
		Find(&rawMembers).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	type adminChatMemberListItem struct {
		ID             uint64     `json:"id"`
		ChatID         uint64     `json:"chat_id"`
		UserID         uint64     `json:"user_id"`
		Role           int8       `json:"role"`
		NicknameInChat string     `json:"nickname_in_chat"`
		IsMuted        bool       `json:"is_muted"`
		MuteEndTime    *time.Time `json:"mute_end_time"`
		JoinedAt       time.Time  `json:"joined_at"`
		UserUUID       string     `json:"user_uuid"`
		Username       string     `json:"username"`
		Nickname       string     `json:"nickname"`
		Avatar         string     `json:"avatar"`
		LastOnlineAt   *time.Time `json:"last_online_at"`
	}
	members := make([]adminChatMemberListItem, 0, len(rawMembers))
	for _, m := range rawMembers {
		members = append(members, adminChatMemberListItem{
			ID:             m.ID,
			ChatID:         m.ChatID,
			UserID:         m.UserID,
			Role:           m.Role + 1,
			NicknameInChat: m.ChatMember.Nickname,
			IsMuted:        m.IsMuted,
			MuteEndTime:    m.MuteEndTime,
			JoinedAt:       m.JoinedAt,
			UserUUID:       m.UserUUID,
			Username:       m.Username,
			Nickname:       m.Nickname,
			Avatar:         m.Avatar,
			LastOnlineAt:   m.LastOnlineAt,
		})
	}
	response.Success(c, gin.H{
		"list":      members,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

func adminJoinRequestStatusText(status int8) string {
	switch status {
	case models.JoinRequestApproved:
		return "已通过"
	case models.JoinRequestRejected:
		return "已拒绝"
	default:
		return "待审批"
	}
}

func (h *ChatMgmtHandler) getEffectiveMaxMembers(chat models.Chat) int {
	if chat.MaxMembers > 0 {
		return chat.MaxMembers
	}
	settingKey := models.SettingGroupMaxMembers
	defaultValue := 200000
	if chat.Type == 3 {
		settingKey = models.SettingChannelMaxMembers
		defaultValue = 0
	}

	var setting models.SystemSetting
	if err := h.db.Where("`key` = ?", settingKey).First(&setting).Error; err != nil {
		return defaultValue
	}
	maxMembers, err := strconv.Atoi(setting.Value)
	if err != nil {
		return defaultValue
	}
	return maxMembers
}

// GetJoinRequests lists group/channel join requests for the admin panel.
func (h *ChatMgmtHandler) GetJoinRequests(c *gin.Context) {
	chatID := c.Param("id")
	page, pageSize, offset := parseAdminPagination(c, 20, 100)
	keyword := strings.TrimSpace(c.Query("keyword"))
	statusQuery := strings.TrimSpace(c.Query("status"))

	var chat models.Chat
	if err := h.db.First(&chat, chatID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "会话不存在")
		return
	}
	if rejectPrivateChat(c, chat, "私聊没有入群申请") {
		return
	}
	query := h.db.Table("join_requests").
		Joins("LEFT JOIN users ON join_requests.user_id = users.id").
		Where("join_requests.chat_id = ?", chat.ID)
	if statusQuery != "" {
		status, err := strconv.Atoi(statusQuery)
		if err != nil || status < int(models.JoinRequestPending) || status > int(models.JoinRequestRejected) {
			response.Error(c, http.StatusBadRequest, "申请状态不正确")
			return
		}
		query = query.Where("join_requests.status = ?", status)
	}
	if keyword != "" {
		likeKeyword := "%" + keyword + "%"
		query = query.Where(
			"(users.username LIKE ? OR users.nickname LIKE ? OR users.uuid = ? OR join_requests.message LIKE ?)",
			likeKeyword,
			likeKeyword,
			keyword,
			likeKeyword,
		)
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	var rows []struct {
		models.JoinRequest
		UserUUID string `json:"user_uuid"`
		Username string `json:"username"`
		Nickname string `json:"nickname"`
		Avatar   string `json:"avatar"`
	}
	if err := query.
		Select("join_requests.*, users.uuid AS user_uuid, users.username, users.nickname, users.avatar").
		Order("join_requests.status ASC, join_requests.created_at DESC").
		Offset(offset).
		Limit(pageSize).
		Find(&rows).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	type adminJoinRequestItem struct {
		ID         uint64     `json:"id"`
		ChatID     uint64     `json:"chat_id"`
		UserID     uint64     `json:"user_id"`
		UserUUID   string     `json:"user_uuid"`
		Username   string     `json:"username"`
		Nickname   string     `json:"nickname"`
		Avatar     string     `json:"avatar"`
		Message    string     `json:"message"`
		Status     int8       `json:"status"`
		StatusText string     `json:"status_text"`
		ReviewedAt *time.Time `json:"reviewed_at"`
		CreatedAt  time.Time  `json:"created_at"`
		UpdatedAt  time.Time  `json:"updated_at"`
	}
	list := make([]adminJoinRequestItem, 0, len(rows))
	for _, row := range rows {
		list = append(list, adminJoinRequestItem{
			ID:         row.ID,
			ChatID:     row.ChatID,
			UserID:     row.UserID,
			UserUUID:   row.UserUUID,
			Username:   row.Username,
			Nickname:   row.Nickname,
			Avatar:     row.Avatar,
			Message:    row.Message,
			Status:     row.Status,
			StatusText: adminJoinRequestStatusText(row.Status),
			ReviewedAt: row.ReviewedAt,
			CreatedAt:  row.CreatedAt,
			UpdatedAt:  row.UpdatedAt,
		})
	}
	response.Success(c, gin.H{
		"list":      list,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// ReviewJoinRequest approves or rejects a group/channel join request from the admin panel.
func (h *ChatMgmtHandler) ReviewJoinRequest(c *gin.Context) {
	chatID := c.Param("id")
	requestID := c.Param("request_id")

	var req struct {
		Approve *bool `json:"approve"`
	}
	if err := c.ShouldBindJSON(&req); err != nil || req.Approve == nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	var chat models.Chat
	if err := h.db.First(&chat, chatID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "会话不存在")
		return
	}
	if rejectPrivateChat(c, chat, "私聊没有入群申请") {
		return
	}
	if chat.Status == models.ChatStatusDissolved {
		response.Error(c, http.StatusBadRequest, "已解散的群不能审批申请")
		return
	}
	if *req.Approve && chat.Status == models.ChatStatusBanned {
		response.Error(c, http.StatusBadRequest, "已封禁的群不能通过申请")
		return
	}
	now := time.Now()
	err := h.db.Transaction(func(tx *gorm.DB) error {

		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			First(&chat, chat.ID).Error; err != nil {
			return err
		}
		if chat.Status == models.ChatStatusDissolved {
			return errAdminChatDissolved
		}
		if *req.Approve && chat.Status == models.ChatStatusBanned {
			return errAdminChatBanned
		}

		var joinRequest models.JoinRequest
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("id = ? AND chat_id = ?", requestID, chat.ID).
			First(&joinRequest).Error; err != nil {
			return err
		}
		if joinRequest.Status != models.JoinRequestPending {
			return errAdminJoinRequestReviewed
		}
		if !*req.Approve {
			return tx.Model(&joinRequest).Updates(map[string]interface{}{
				"status":      models.JoinRequestRejected,
				"reviewer_id": 0,
				"reviewed_at": &now,
				"updated_at":  now,
			}).Error
		}

		var requestUser models.User
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			First(&requestUser, joinRequest.UserID).Error; err != nil {
			return err
		}
		if requestUser.Status != models.UserStatusNormal {
			return errAdminUserUnavailable
		}

		var existingMember models.ChatMember
		existingErr := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("chat_id = ? AND user_id = ?", chat.ID, joinRequest.UserID).
			First(&existingMember).Error
		if existingErr != nil && !errors.Is(existingErr, gorm.ErrRecordNotFound) {
			return existingErr
		}
		if errors.Is(existingErr, gorm.ErrRecordNotFound) {

			var memberCount int64
			if err := tx.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Count(&memberCount).Error; err != nil {
				return err
			}
			maxMembers := h.getEffectiveMaxMembers(chat)
			if maxMembers > 0 && int(memberCount) >= maxMembers {
				return errAdminChatFull
			}
			newMember := models.ChatMember{
				ChatID:    chat.ID,
				UserID:    joinRequest.UserID,
				Role:      0,
				JoinedAt:  now,
				UpdatedAt: now,
			}
			if err := tx.Create(&newMember).Error; err != nil {
				return err
			}
		}
		if err := tx.Clauses(clause.OnConflict{
			Columns: []clause.Column{{Name: "user_id"}, {Name: "chat_id"}},
			DoUpdates: clause.Assignments(map[string]interface{}{
				"is_archived": false,
				"sort_time":   now,
				"updated_at":  now,
			}),
		}).Create(&models.UserChat{
			UserID:    joinRequest.UserID,
			ChatID:    chat.ID,
			TargetID:  0,
			SortTime:  now,
			UpdatedAt: now,
		}).Error; err != nil {
			return err
		}

		var memberCount int64
		if err := tx.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Count(&memberCount).Error; err != nil {
			return err
		}
		if err := tx.Model(&models.Chat{}).Where("id = ?", chat.ID).Updates(map[string]interface{}{
			"member_count": int(memberCount),
			"updated_at":   now,
		}).Error; err != nil {
			return err
		}
		return tx.Model(&joinRequest).Updates(map[string]interface{}{
			"status":      models.JoinRequestApproved,
			"reviewer_id": 0,
			"reviewed_at": &now,
			"updated_at":  now,
		}).Error
	})
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			response.Error(c, http.StatusNotFound, "申请不存在")
			return
		}
		if errors.Is(err, errAdminJoinRequestReviewed) {
			response.Error(c, http.StatusBadRequest, "该申请已处理")
			return
		}
		if errors.Is(err, errAdminChatBanned) {
			response.Error(c, http.StatusBadRequest, "已封禁的群不能通过申请")
			return
		}
		if errors.Is(err, errAdminChatDissolved) {
			response.Error(c, http.StatusBadRequest, "已解散的群不能审批申请")
			return
		}
		if errors.Is(err, errAdminChatFull) {
			response.Error(c, http.StatusBadRequest, "群成员已达上限")
			return
		}
		if errors.Is(err, errAdminUserUnavailable) {
			response.Error(c, http.StatusBadRequest, "申请用户不是正常状态")
			return
		}
		response.Error(c, http.StatusInternalServerError, "审批失败")
		return
	}
	if *req.Approve {
		response.Success(c, gin.H{"message": "已通过申请"})
		return
	}
	response.Success(c, gin.H{"message": "已拒绝申请"})
}

type addChatMembersRequest struct {
	UserIDs     []uint64 `json:"user_ids"`
	UserUUIDs   []string `json:"user_uuids"`
	Usernames   []string `json:"usernames"`
	Identifiers []string `json:"identifiers"`
}

func (h *ChatMgmtHandler) resolveAdminMemberUsers(req addChatMembersRequest) ([]models.User, int, error) {
	idSet := make(map[uint64]struct{})
	shortIDSet := make(map[uint64]struct{})
	tokenSet := make(map[string]struct{})
	requestedSet := make(map[string]struct{})
	addToken := func(prefix string, value string) {
		value = strings.TrimSpace(value)
		if value == "" {
			return
		}
		requestedSet[prefix+":"+value] = struct{}{}
		tokenSet[value] = struct{}{}
		if numericValue, err := strconv.ParseUint(value, 10, 64); err == nil && numericValue > 0 {
			idSet[numericValue] = struct{}{}
			shortIDSet[numericValue] = struct{}{}
		}
	}
	for _, id := range req.UserIDs {
		if id == 0 {
			continue
		}
		requestedSet["id:"+strconv.FormatUint(id, 10)] = struct{}{}
		idSet[id] = struct{}{}
	}
	for _, uuid := range req.UserUUIDs {
		addToken("uuid", uuid)
	}
	for _, username := range req.Usernames {
		addToken("username", username)
	}
	for _, identifier := range req.Identifiers {
		addToken("identifier", identifier)
	}
	requestedCount := len(requestedSet)
	if requestedCount == 0 {
		return nil, 0, nil
	}
	conditions := make([]string, 0, 3)
	args := make([]interface{}, 0, 3)
	if len(idSet) > 0 {
		ids := make([]uint64, 0, len(idSet))
		for id := range idSet {
			ids = append(ids, id)
		}
		conditions = append(conditions, "id IN ?")
		args = append(args, ids)
	}
	if len(shortIDSet) > 0 {
		shortIDs := make([]uint64, 0, len(shortIDSet))
		for id := range shortIDSet {
			shortIDs = append(shortIDs, id)
		}
		conditions = append(conditions, "short_id IN ?")
		args = append(args, shortIDs)
	}
	if len(tokenSet) > 0 {
		tokens := make([]string, 0, len(tokenSet))
		for token := range tokenSet {
			tokens = append(tokens, token)
		}
		conditions = append(conditions, "(uuid IN ? OR username IN ?)")
		args = append(args, tokens, tokens)
	}

	var users []models.User
	err := h.db.Model(&models.User{}).
		Select("id", "uuid", "username", "nickname", "avatar", "status").
		Where("status = ?", models.UserStatusNormal).
		Where("("+strings.Join(conditions, " OR ")+")", args...).
		Limit(100).
		Find(&users).Error
	return users, requestedCount, err
}

// AddChatMembers adds normal users to a group/channel from the admin panel.
func (h *ChatMgmtHandler) AddChatMembers(c *gin.Context) {
	chatID := c.Param("id")

	var req addChatMembersRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	var chat models.Chat
	if err := h.db.First(&chat, chatID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "会话不存在")
		return
	}
	if rejectPrivateChat(c, chat, "私聊不能添加群成员") {
		return
	}
	if chat.Status == models.ChatStatusBanned {
		response.Error(c, http.StatusBadRequest, "已封禁的群不能添加成员")
		return
	}
	if rejectDissolvedChat(c, chat, "添加成员") {
		return
	}

	users, requestedCount, err := h.resolveAdminMemberUsers(req)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "查询用户失败")
		return
	}
	if requestedCount == 0 {
		response.Error(c, http.StatusBadRequest, "请填写要添加的用户")
		return
	}
	if len(users) == 0 {
		response.Error(c, http.StatusBadRequest, "没有找到可添加的正常用户")
		return
	}
	userIDs := make([]uint64, 0, len(users))
	for _, user := range users {
		userIDs = append(userIDs, user.ID)
	}
	now := time.Now()
	var addedUsers []models.User
	addedCount := 0
	err = h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&chat, chat.ID).Error; err != nil {
			return err
		}
		if chat.Status == models.ChatStatusBanned {
			return errAdminChatBanned
		}
		if chat.Status == models.ChatStatusDissolved {
			return errAdminChatDissolved
		}

		var existingUserIDs []uint64
		if err := tx.Model(&models.ChatMember{}).
			Where("chat_id = ? AND user_id IN ?", chat.ID, userIDs).
			Pluck("user_id", &existingUserIDs).Error; err != nil {
			return err
		}
		existingSet := make(map[uint64]struct{}, len(existingUserIDs))
		for _, id := range existingUserIDs {
			existingSet[id] = struct{}{}
		}

		var currentCount int64
		if err := tx.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Count(&currentCount).Error; err != nil {
			return err
		}
		newMembers := make([]models.ChatMember, 0, len(users))
		newUserChats := make([]models.UserChat, 0, len(users))
		for _, user := range users {
			if _, exists := existingSet[user.ID]; exists {
				continue
			}
			if chat.MaxMembers > 0 && int(currentCount)+len(newMembers) >= chat.MaxMembers {
				break
			}
			newMembers = append(newMembers, models.ChatMember{
				ChatID:    chat.ID,
				UserID:    user.ID,
				Role:      0,
				JoinedAt:  now,
				UpdatedAt: now,
			})
			newUserChats = append(newUserChats, models.UserChat{
				UserID:    user.ID,
				ChatID:    chat.ID,
				SortTime:  now,
				UpdatedAt: now,
			})
			addedUsers = append(addedUsers, user)
		}
		if len(newMembers) > 0 {
			memberCreate := tx.Clauses(clause.OnConflict{
				Columns:   []clause.Column{{Name: "chat_id"}, {Name: "user_id"}},
				DoNothing: true,
			}).Create(&newMembers)
			if memberCreate.Error != nil {
				return memberCreate.Error
			}
			addedCount = int(memberCreate.RowsAffected)
			if addedCount < len(addedUsers) {
				addedUsers = addedUsers[:addedCount]
			}
			if addedCount == 0 {
				newUserChats = nil
			} else if addedCount < len(newUserChats) {
				newUserChats = newUserChats[:addedCount]
			}
			if len(newUserChats) > 0 {
				if err := tx.Clauses(clause.OnConflict{
					Columns:   []clause.Column{{Name: "user_id"}, {Name: "chat_id"}},
					DoNothing: true,
				}).Create(&newUserChats).Error; err != nil {
					return err
				}
			}
		}

		var memberCount int64
		if err := tx.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Count(&memberCount).Error; err != nil {
			return err
		}
		return tx.Model(&models.Chat{}).Where("id = ?", chat.ID).Updates(map[string]interface{}{
			"member_count": int(memberCount),
			"updated_at":   now,
		}).Error
	})
	if err != nil {
		if errors.Is(err, errAdminChatBanned) {
			response.Error(c, http.StatusBadRequest, "已封禁的群不能添加成员")
			return
		}
		if errors.Is(err, errAdminChatDissolved) {
			response.Error(c, http.StatusBadRequest, "已解散的群不能添加成员")
			return
		}
		response.Error(c, http.StatusInternalServerError, "添加成员失败")
		return
	}
	if addedCount == 0 {
		response.Success(c, gin.H{
			"message":       "没有新增成员",
			"added_count":   0,
			"skipped_count": requestedCount,
		})
		return
	}
	addedItems := make([]MemberInfo, 0, len(addedUsers))
	for _, user := range addedUsers {
		displayName := user.Nickname
		if displayName == "" {
			displayName = user.Username
		}
		addedItems = append(addedItems, MemberInfo{
			UserID:   user.ID,
			UUID:     user.UUID,
			Nickname: displayName,
			Avatar:   user.Avatar,
		})
	}
	skippedCount := requestedCount - addedCount
	if skippedCount < 0 {
		skippedCount = 0
	}
	response.Success(c, gin.H{
		"message":       "成员已添加",
		"added_count":   addedCount,
		"skipped_count": skippedCount,
		"added_users":   addedItems,
	})
}

type updateChatMemberMuteRequest struct {
	IsMuted *bool `json:"is_muted"`
	Minutes int   `json:"minutes"`
}

// UpdateChatMemberMute updates a member mute state from the admin panel.
func (h *ChatMgmtHandler) UpdateChatMemberMute(c *gin.Context) {
	chatID := c.Param("id")
	memberID := c.Param("member_id")

	var req updateChatMemberMuteRequest
	if err := c.ShouldBindJSON(&req); err != nil || req.IsMuted == nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	if req.Minutes < 0 || req.Minutes > 525600 {
		response.Error(c, http.StatusBadRequest, "禁言时长需在 0-525600 分钟之间")
		return
	}

	var chat models.Chat
	if err := h.db.First(&chat, chatID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "会话不存在")
		return
	}
	if rejectPrivateChat(c, chat, "私聊不能禁言成员") {
		return
	}
	if chat.Status == models.ChatStatusBanned {
		response.Error(c, http.StatusBadRequest, "已封禁的群不能禁言成员")
		return
	}
	if rejectDissolvedChat(c, chat, "禁言成员") {
		return
	}

	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND id = ?", chat.ID, memberID).First(&member).Error; err != nil {
		response.Error(c, http.StatusNotFound, "成员不存在")
		return
	}
	if *req.IsMuted && member.Role >= 2 {
		response.Error(c, http.StatusBadRequest, "不能禁言群主")
		return
	}
	now := time.Now()
	updates := map[string]interface{}{
		"is_muted":   *req.IsMuted,
		"updated_at": now,
	}
	if *req.IsMuted && req.Minutes > 0 {
		muteEndTime := now.Add(time.Duration(req.Minutes) * time.Minute)
		updates["mute_end_time"] = &muteEndTime
	} else {
		updates["mute_end_time"] = nil
	}
	if err := h.db.Model(&member).Updates(updates).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "更新禁言状态失败")
		return
	}
	message := "成员已解禁"
	if *req.IsMuted {
		message = "成员已禁言"
	}
	response.Success(c, gin.H{"message": message})
}

// UpdateChatMemberRole sets a group member as member/admin. Owner cannot be changed here.
func (h *ChatMgmtHandler) UpdateChatMemberRole(c *gin.Context) {
	chatID := c.Param("id")
	memberID := c.Param("member_id")

	var req struct {
		Role int8 `json:"role"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}
	if req.Role != 1 && req.Role != 2 {
		response.Error(c, http.StatusBadRequest, "角色只能设置为成员或管理员")
		return
	}

	var chat models.Chat
	if err := h.db.First(&chat, chatID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "会话不存在")
		return
	}
	if rejectPrivateChat(c, chat, "私聊不能设置成员角色") {
		return
	}
	if chat.Status == models.ChatStatusBanned {
		response.Error(c, http.StatusBadRequest, "已封禁的群不能设置成员角色")
		return
	}
	if rejectDissolvedChat(c, chat, "设置成员角色") {
		return
	}

	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND id = ?", chat.ID, memberID).First(&member).Error; err != nil {
		response.Error(c, http.StatusNotFound, "成员不存在")
		return
	}
	if member.Role >= 2 {
		response.Error(c, http.StatusBadRequest, "群主角色不能在这里修改")
		return
	}
	err := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&chat, chat.ID).Error; err != nil {
			return err
		}
		if chat.Status == models.ChatStatusBanned {
			return errAdminChatBanned
		}
		if chat.Status == models.ChatStatusDissolved {
			return errAdminChatDissolved
		}
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).First(&member, member.ID).Error; err != nil {
			return err
		}
		if member.Role >= 2 {
			return errAdminAlreadyOwner
		}
		if err := tx.Model(&member).Updates(map[string]interface{}{
			"role":       req.Role - 1,
			"updated_at": time.Now(),
		}).Error; err != nil {
			return err
		}
		if req.Role == 1 {
			return tx.Where("chat_id = ? AND user_id = ?", chat.ID, member.UserID).
				Delete(&models.ChatAdminPermission{}).Error
		}
		return nil
	})
	if err != nil {
		switch {
		case errors.Is(err, errAdminChatBanned):
			response.Error(c, http.StatusBadRequest, "已封禁的群不能设置成员角色")
		case errors.Is(err, errAdminChatDissolved):
			response.Error(c, http.StatusBadRequest, "已解散的群不能设置成员角色")
		case errors.Is(err, errAdminAlreadyOwner):
			response.Error(c, http.StatusBadRequest, "群主角色不能在这里修改")
		default:
			response.Error(c, http.StatusInternalServerError, "角色更新失败")
		}
		return
	}
	var targetUser models.User
	if err := h.db.Select("uuid").First(&targetUser, member.UserID).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "角色更新失败")
		return
	}
	h.broadcastMemberRoleChanged(c.Request.Context(), &chat, targetUser.UUID, req.Role)
	response.Success(c, gin.H{"message": "角色已更新"})
}

func (h *ChatMgmtHandler) broadcastMemberRoleChanged(
	ctx context.Context,
	chat *models.Chat,
	targetUserUUID string,
	clientRole int8,
) {
	if h == nil || chat == nil {
		return
	}
	var memberUserIDs []uint64
	h.db.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Pluck("user_id", &memberUserIDs)
	deleteUserChatListHotCache(ctx, h.cache, memberUserIDs...)
	if h.hub == nil || len(memberUserIDs) == 0 {
		return
	}
	var memberUUIDs []string
	h.db.Model(&models.User{}).Where("id IN ?", memberUserIDs).Pluck("uuid", &memberUUIDs)
	if len(memberUUIDs) == 0 {
		return
	}
	h.hub.Broadcast(&ws.BroadcastMessage{
		UserIDs: memberUUIDs,
		Data: map[string]interface{}{
			"type":    "member_role_changed",
			"chat_id": chat.UUID,
			"user_id": targetUserUUID,
			"role":    clientRole,
		},
	})
}

// TransferChatOwner

func (h *ChatMgmtHandler) TransferChatOwner(c *gin.Context) {
	chatID := c.Param("id")

	var req struct {
		MemberID uint64 `json:"member_id"`
		UserID   uint64 `json:"user_id"`
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
	if rejectPrivateChat(c, chat, "私聊不能转让群主") {
		return
	}
	if chat.Status == models.ChatStatusBanned {
		response.Error(c, http.StatusBadRequest, "已封禁的群不能转让群主")
		return
	}
	if rejectDissolvedChat(c, chat, "转让群主") {
		return
	}
	if req.MemberID == 0 && req.UserID == 0 {
		response.Error(c, http.StatusBadRequest, "请选择新群主")
		return
	}
	err := h.db.Transaction(func(tx *gorm.DB) error {

		now := time.Now()
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			First(&chat, chat.ID).Error; err != nil {
			return err
		}
		if chat.Status == models.ChatStatusBanned {
			return errAdminChatBanned
		}
		if chat.Status == models.ChatStatusDissolved {
			return errAdminChatDissolved
		}
		memberQuery := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("chat_id = ?", chat.ID)
		if req.MemberID > 0 {
			memberQuery = memberQuery.Where("id = ?", req.MemberID)
		} else {
			memberQuery = memberQuery.Where("user_id = ?", req.UserID)
		}

		var target models.ChatMember
		if err := memberQuery.First(&target).Error; err != nil {
			return err
		}
		if target.UserID == chat.OwnerID {
			return errAdminAlreadyOwner
		}
		if err := tx.Model(&models.ChatMember{}).
			Where("chat_id = ? AND role = ?", chat.ID, 2).
			Updates(map[string]interface{}{"role": 1, "updated_at": now}).Error; err != nil {
			return err
		}
		if err := tx.Model(&models.ChatMember{}).
			Where("chat_id = ? AND user_id = ?", chat.ID, chat.OwnerID).
			Updates(map[string]interface{}{"role": 1, "updated_at": now}).Error; err != nil {
			return err
		}
		if err := tx.Model(&target).
			Updates(map[string]interface{}{"role": 2, "updated_at": now}).Error; err != nil {
			return err
		}
		return tx.Model(&chat).Updates(map[string]interface{}{
			"owner_id":   target.UserID,
			"updated_at": now,
		}).Error
	})
	if err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			response.Error(c, http.StatusNotFound, "成员不存在")
			return
		}
		if errors.Is(err, errAdminAlreadyOwner) {
			response.Error(c, http.StatusBadRequest, "该成员已经是群主")
			return
		}
		if errors.Is(err, errAdminChatBanned) {
			response.Error(c, http.StatusBadRequest, "已封禁的群不能转让群主")
			return
		}
		if errors.Is(err, errAdminChatDissolved) {
			response.Error(c, http.StatusBadRequest, "已解散的群不能转让群主")
			return
		}
		response.Error(c, http.StatusInternalServerError, "转让失败")
		return
	}
	response.Success(c, gin.H{"message": "群主已转让"})
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
	if rejectPrivateChat(c, chat, "私聊不能移除成员") {
		return
	}
	if chat.Status == models.ChatStatusBanned {
		response.Error(c, http.StatusBadRequest, "已封禁的群不能移除成员")
		return
	}
	if rejectDissolvedChat(c, chat, "移除成员") {
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
	err := h.db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Delete(&member).Error; err != nil {
			return err
		}
		if err := tx.Where("chat_id = ? AND user_id = ?", chat.ID, member.UserID).Delete(&models.UserChat{}).Error; err != nil {
			return err
		}
		var memberCount int64
		if err := tx.Model(&models.ChatMember{}).Where("chat_id = ?", chat.ID).Count(&memberCount).Error; err != nil {
			return err
		}
		return tx.Model(&models.Chat{}).Where("id = ?", chat.ID).Updates(map[string]interface{}{
			"member_count": int(memberCount),
			"updated_at":   time.Now(),
		}).Error
	})
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "移除成员失败")
		return
	}
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
	h.db.Model(&models.Chat{}).Where("type IN ? AND status = ?", []int{2, 3}, models.ChatStatusBanned).Count(&bannedCount)

	var groupBannedCount int64
	h.db.Model(&models.Chat{}).Where("type = 2 AND status = ?", models.ChatStatusBanned).Count(&groupBannedCount)

	var channelBannedCount int64
	h.db.Model(&models.Chat{}).Where("type = 3 AND status = ?", models.ChatStatusBanned).Count(&channelBannedCount)

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
		"group_count":          groupCount,
		"channel_count":        channelCount,
		"banned_count":         bannedCount,
		"group_banned_count":   groupBannedCount,
		"channel_banned_count": channelBannedCount,
		"today_group_count":    todayGroupCount,
		"today_channel_count":  todayChannelCount,
		"hot_groups":           hotGroups,
		"hot_channels":         hotChannels,
	})
}
