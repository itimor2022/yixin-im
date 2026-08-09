// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"gorm.io/gorm"
	"time"
	"genericim/internal/models"
	"genericim/internal/ws"
)

const wsTypeChatStateChanged = "chat_state_changed"

func userChatStatePayload(
	chatUUID string,
	userUUID string,
	userChat *models.UserChat,
	lastReadSeq uint64,
	changedFields ...string,
) map[string]interface{} {
	payload := map[string]interface{}{
		"type":          wsTypeChatStateChanged,
		"chat_id":       chatUUID,
		"user_id":       userUUID,
		"last_read_seq": lastReadSeq,
		"changed":       changedFields,
		"updated_at":    time.Now().UTC().Format(time.RFC3339Nano),
	}
	if userChat != nil {
		payload["unread_count"] = userChat.UnreadCount
		payload["has_mention"] = userChat.HasMention
		payload["is_pinned"] = userChat.IsPinned
		payload["is_muted"] = userChat.IsMuted
		payload["last_msg_seq"] = userChat.LastMsgSeq
	}
	return payload
}

func sendUserChatStateChanged(
	hub *ws.Hub,
	userUUID string,
	chatUUID string,
	userChat *models.UserChat,
	lastReadSeq uint64,
	changedFields ...string,
) {

	if hub == nil || userUUID == "" {
		return
	}
	hub.SendToUser(userUUID, userChatStatePayload(
		chatUUID,
		userUUID,
		userChat,
		lastReadSeq,
		changedFields...,
	))
}

func currentLastReadSeq(db *gorm.DB, chatID uint64, userID uint64) uint64 {
	if db == nil || chatID == 0 || userID == 0 {
		return 0
	}
	var member models.ChatMember
	if err := db.
		Where("chat_id = ? AND user_id = ?", chatID, userID).
		Select("last_read_seq").
		First(&member).Error; err != nil {
		return 0
	}
	return member.LastReadSeq
}
