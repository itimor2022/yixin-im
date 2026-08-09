// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"strings"
	"time"
	"genericim/internal/models"
	"genericim/pkg/response"
)

type messageDetailMemberRow struct {
	UserID      uint64
	UUID        string
	Nickname    string
	Avatar      string
	Role        int8
	LastReadSeq uint64
}

func canViewMessageReceiptMembers(chatType int8, viewerRole int8) bool {
	return chatType == 1 || viewerRole >= 1
}

func messageStatusName(status int) string {
	switch status {
	case models.MsgStatusRead:
		return "read"
	case models.MsgStatusDelivered:
		return "delivered"
	case models.MsgStatusSent:
		return "sent"
	default:
		return "sending"
	}
}

func stringSliceContains(items []string, target string) bool {
	for _, item := range items {
		if item == target {
			return true
		}
	}
	return false
}

// GetMessageDetail returns authoritative message timestamps and receipt data.
// Group/channel delivery is intentionally not inferred from a global Mongo
// status because the current schema has no per-member delivered cursor.
func (h *MessageHandler) GetMessageDetail(c *gin.Context) {
	chatUUID := strings.TrimSpace(c.Query("chat_id"))
	messageID := strings.TrimSpace(c.Query("msg_id"))
	if chatUUID == "" || messageID == "" {
		response.BadRequest(c, "chat_id and msg_id are required")
		return
	}
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.Unauthorized(c, "user not found")
		return
	}

	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {
		response.NotFound(c, "chat not found")
		return
	}

	var viewer models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).First(&viewer).Error; err != nil {
		response.Forbidden(c, "not a chat member")
		return
	}

	message, found, err := h.msgService.FindMessageByMsgID(c.Request.Context(), chatUUID, messageID)
	if err != nil {
		response.ServerError(c, "failed to load message")
		return
	}
	if !found || message == nil || stringSliceContains(message.DeletedFor, userUUID) ||
		stringSliceContains(message.BurnedFor, userUUID) {
		response.NotFound(c, "message not found")
		return
	}

	var rows []messageDetailMemberRow
	query := h.db.Table("chat_members AS cm").
		Select("cm.user_id, users.uuid, users.nickname, users.avatar, cm.role, cm.last_read_seq").
		Joins("JOIN users ON users.id = cm.user_id AND users.deleted_at IS NULL").
		Where("cm.chat_id = ? AND cm.joined_at <= ?", chat.ID, message.CreatedAt).
		Order("cm.role DESC, cm.joined_at ASC")
	if err := query.Scan(&rows).Error; err != nil {
		response.ServerError(c, "failed to load message receipts")
		return
	}
	recipientCount := 0
	readCount := 0
	for _, row := range rows {
		if row.UUID == message.SenderID {
			continue
		}
		recipientCount++
		if message.Seq > 0 && row.LastReadSeq >= message.Seq {
			readCount++
		}
	}
	privateChat := chat.Type == 1
	deliveredCount := readCount
	deliveryKnown := privateChat
	if privateChat && message.Status >= models.MsgStatusDelivered {
		deliveredCount = recipientCount
	}
	canViewMembers := canViewMessageReceiptMembers(chat.Type, viewer.Role)
	members := make([]gin.H, 0)
	if canViewMembers {
		for _, row := range rows {
			if row.UUID == message.SenderID {
				continue
			}
			isRead := message.Seq > 0 && row.LastReadSeq >= message.Seq
			isDelivered := isRead || (privateChat && message.Status >= models.MsgStatusDelivered)
			members = append(members, gin.H{
				"user_id":         row.UUID,
				"nickname":        row.Nickname,
				"avatar":          row.Avatar,
				"role":            row.Role,
				"read":            isRead,
				"delivered":       isDelivered,
				"delivered_known": privateChat || isRead,
			})
		}
	}
	sender := gin.H{
		"user_id":  message.SenderID,
		"nickname": message.SenderName,
		"avatar":   message.SenderAvatar,
	}
	if message.IsAnonymous && viewer.Role < 1 && message.SenderID != userUUID {
		sender = gin.H{"anonymous": true}
	}

	var editedAt interface{}
	if message.EditedAt != nil {
		editedAt = message.EditedAt.UTC()
	}
	response.Success(c, gin.H{
		"message": gin.H{
			"message_id": message.MsgID,
			"chat_id":    message.ChatID,
			"seq":        message.Seq,
			"type":       message.Type,
			"status":     messageStatusName(message.Status),
			"created_at": message.CreatedAt.UTC(),
			"updated_at": message.UpdatedAt.UTC(),
			"edited_at":  editedAt,
			"revoked":    message.IsRevoked,
		},
		"sender": sender,
		"receipts": gin.H{
			"recipient_count":      recipientCount,
			"read_count":           readCount,
			"unread_count":         recipientCount - readCount,
			"delivered_count":      deliveredCount,
			"delivery_count_known": deliveryKnown,
			"can_view_members":     canViewMembers,
			"member_protection_on": chat.MemberProtection,
			"members":              members,
		},
		"generated_at": time.Now().UTC(),
	})
}
