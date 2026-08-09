// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"encoding/json"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm/clause"
	"strconv"
	"strings"
	"time"
	"genericim/internal/models"
	"genericim/pkg/response"
)

type addMessageFavoriteRequest struct {
	ChatID    string `json:"chat_id" binding:"required"`
	MessageID string `json:"message_id" binding:"required"`
}

func favoriteMessageTypeName(messageType int) string {
	switch messageType {
	case models.MsgTypeImage:
		return "image"
	case models.MsgTypeVideo:
		return "video"
	case models.MsgTypeVoice:
		return "voice"
	case models.MsgTypeFile:
		return "file"
	case models.MsgTypeLocation:
		return "location"
	case models.MsgTypeSticker:
		return "sticker"
	case models.MsgTypeContact:
		return "contact"
	case models.MsgTypeCall:
		return "call"
	case models.MsgTypeRedPacket:
		return "redPacket"
	case models.MsgTypeTransfer:
		return "transfer"
	case models.MsgTypeForwardBundle:
		return "forwardBundle"
	case models.MsgTypeSystem:
		return "system"
	default:
		return "text"
	}
}

func messageFavoriteSnapshot(message *models.Message, chat *models.Chat) map[string]interface{} {
	snapshot := map[string]interface{}{
		"message_id":    message.MsgID,
		"message_seq":   message.Seq,
		"chat_id":       message.ChatID,
		"chat_name":     chat.Name,
		"sender_id":     message.SenderID,
		"sender_name":   message.SenderName,
		"sender_avatar": message.SenderAvatar,
		"message_type":  favoriteMessageTypeName(message.Type),
		"content":       message.Content.Text,
		"created_at":    message.CreatedAt,
	}
	if media := message.Content.Media; media != nil {
		snapshot["media_url"] = media.URL
		snapshot["media_duration"] = media.Duration
	}
	if voice := message.Content.Voice; voice != nil {
		snapshot["media_url"] = voice.URL
		snapshot["media_duration"] = voice.Duration
	}
	if file := message.Content.File; file != nil {
		snapshot["media_url"] = file.URL
		snapshot["file_name"] = file.Name
	}
	if location := message.Content.Location; location != nil {
		snapshot["location_latitude"] = location.Latitude
		snapshot["location_longitude"] = location.Longitude
		snapshot["location_title"] = location.Title
		snapshot["location_address"] = location.Address
	}
	return snapshot
}

func favoriteResponseItem(favorite *models.MessageFavorite) gin.H {
	item := gin.H{}
	_ = json.Unmarshal(favorite.Snapshot, &item)
	item["favorite_id"] = favorite.UUID
	item["collected_at"] = favorite.CollectedAt
	item["updated_at"] = favorite.UpdatedAt
	item["deleted"] = favorite.DeletedAt != nil
	return item
}

func (h *MessageHandler) resolveFavoriteOwnerAndMessage(c *gin.Context, chatID, messageID string) (*models.User, *models.Chat, *models.Message, bool) {
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.Unauthorized(c, "用户不存在")
		return nil, nil, nil, false
	}

	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatID).First(&chat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return nil, nil, nil, false
	}
	var membershipCount int64
	if err := h.db.Model(&models.ChatMember{}).
		Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).
		Count(&membershipCount).Error; err != nil || membershipCount == 0 {
		response.Forbidden(c, "无权收藏该会话消息")
		return nil, nil, nil, false
	}

	message, found, err := h.msgService.FindMessageByMsgID(c.Request.Context(), chatID, messageID)
	if err != nil {
		response.ServerError(c, "读取消息失败")
		return nil, nil, nil, false
	}
	if !found || message == nil || message.IsRevoked {
		response.NotFound(c, "消息不存在或已撤回")
		return nil, nil, nil, false
	}
	if message.BurnAfterRead || message.E2EE != nil {
		response.Forbidden(c, "该消息不支持收藏")
		return nil, nil, nil, false
	}
	return &user, &chat, message, true
}

// AddMessageFavorite stores a server-authored snapshot and is idempotent per
// user/chat/message. Re-adding a tombstone restores the same logical favorite.
func (h *MessageHandler) AddMessageFavorite(c *gin.Context) {
	var req addMessageFavoriteRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	req.ChatID = strings.TrimSpace(req.ChatID)
	req.MessageID = strings.TrimSpace(req.MessageID)
	user, chat, message, ok := h.resolveFavoriteOwnerAndMessage(c, req.ChatID, req.MessageID)
	if !ok {
		return
	}

	snapshot, err := json.Marshal(messageFavoriteSnapshot(message, chat))
	if err != nil {
		response.ServerError(c, "生成收藏快照失败")
		return
	}
	now := time.Now()
	favorite := models.MessageFavorite{
		UUID:        uuid.NewString(),
		UserID:      user.ID,
		ChatUUID:    req.ChatID,
		MessageID:   req.MessageID,
		MessageSeq:  message.Seq,
		Snapshot:    snapshot,
		CollectedAt: now,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	if err := h.db.Clauses(clause.OnConflict{
		Columns: []clause.Column{{Name: "user_id"}, {Name: "chat_uuid"}, {Name: "message_id"}},
		DoUpdates: clause.Assignments(map[string]interface{}{
			"message_seq":  message.Seq,
			"snapshot":     snapshot,
			"collected_at": now,
			"deleted_at":   nil,
			"updated_at":   now,
		}),
	}).Create(&favorite).Error; err != nil {
		response.ServerError(c, "收藏失败")
		return
	}
	if err := h.db.Where("user_id = ? AND chat_uuid = ? AND message_id = ?", user.ID, req.ChatID, req.MessageID).First(&favorite).Error; err != nil {
		response.ServerError(c, "读取收藏失败")
		return
	}
	item := favoriteResponseItem(&favorite)
	if h.hub != nil {
		h.hub.SendToUser(user.UUID, map[string]interface{}{"type": "message_favorite_changed", "action": "upsert", "favorite": item})
	}
	response.Success(c, item)
}

func (h *MessageHandler) ListMessageFavorites(c *gin.Context) {
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.Unauthorized(c, "用户不存在")
		return
	}
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "50"))
	if page < 1 {
		page = 1
	}
	if pageSize < 1 || pageSize > 100 {
		pageSize = 50
	}
	var total int64
	query := h.db.Model(&models.MessageFavorite{}).Where("user_id = ? AND deleted_at IS NULL", user.ID)
	if err := query.Count(&total).Error; err != nil {
		response.ServerError(c, "读取收藏失败")
		return
	}
	var favorites []models.MessageFavorite
	if err := query.Order("collected_at DESC").Offset((page - 1) * pageSize).Limit(pageSize).Find(&favorites).Error; err != nil {
		response.ServerError(c, "读取收藏失败")
		return
	}
	items := make([]gin.H, 0, len(favorites))
	for index := range favorites {
		items = append(items, favoriteResponseItem(&favorites[index]))
	}
	response.SuccessWithPage(c, items, total, page, pageSize)
}

func (h *MessageHandler) SyncMessageFavorites(c *gin.Context) {
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.Unauthorized(c, "用户不存在")
		return
	}
	since, err := time.Parse(time.RFC3339Nano, strings.TrimSpace(c.Query("since")))
	if err != nil {
		since = time.Unix(0, 0)
	}
	var favorites []models.MessageFavorite
	if err := h.db.Where("user_id = ? AND updated_at > ?", user.ID, since).
		Order("updated_at ASC").Limit(500).Find(&favorites).Error; err != nil {
		response.ServerError(c, "同步收藏失败")
		return
	}
	items := make([]gin.H, 0, len(favorites))
	for index := range favorites {
		items = append(items, favoriteResponseItem(&favorites[index]))
	}
	response.Success(c, gin.H{"items": items, "server_time": time.Now()})
}

func (h *MessageHandler) DeleteMessageFavorite(c *gin.Context) {
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.Unauthorized(c, "用户不存在")
		return
	}
	chatID := strings.TrimSpace(c.Param("chat_id"))
	messageID := strings.TrimSpace(c.Param("message_id"))
	if chatID == "" || messageID == "" {
		response.BadRequest(c, "参数错误")
		return
	}
	now := time.Now()
	result := h.db.Model(&models.MessageFavorite{}).
		Where("user_id = ? AND chat_uuid = ? AND message_id = ? AND deleted_at IS NULL", user.ID, chatID, messageID).
		Updates(map[string]interface{}{"deleted_at": now, "updated_at": now})
	if result.Error != nil {
		response.ServerError(c, "取消收藏失败")
		return
	}
	if result.RowsAffected == 0 {
		response.NotFound(c, "收藏不存在")
		return
	}
	if h.hub != nil {
		h.hub.SendToUser(user.UUID, map[string]interface{}{"type": "message_favorite_changed", "action": "delete", "chat_id": chatID, "message_id": messageID, "updated_at": now})
	}
	response.Success(c, gin.H{"deleted": true, "updated_at": now})
}
