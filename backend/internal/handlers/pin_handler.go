// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"context"
	"errors"
	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"gorm.io/gorm"
	"sort"
	"strings"
	"time"
	"genericim/internal/models"
	"genericim/internal/ws"
	"genericim/pkg/response"
)

type PinHandler struct {
	db      *gorm.DB
	mongoDB *mongo.Database
	hub     *ws.Hub
}

func NewPinHandler(db *gorm.DB, mongoDB *mongo.Database, hub *ws.Hub) *PinHandler {
	return &PinHandler{db: db, mongoDB: mongoDB, hub: hub}
}

type PinMessageRequest struct {
	MessageID string `json:"message_id" binding:"required"`
}

func (h *PinHandler) PinMessage(c *gin.Context) {
	userID := c.GetString("user_id")
	chatUUID := c.Param("id")

	var req PinMessageRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return
	}
	if chat.Status != models.ChatStatusNormal {
		response.Forbidden(c, "会话已被封禁或解散")
		return
	}

	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {
		response.Forbidden(c, "用户不存在")
		return
	}

	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&member).Error; err != nil {
		response.Forbidden(c, "您不是该群成员")
		return
	}

	// 管理员/群主始终可以置顶；普通成员需要 CanPinMessages 开启
	if member.Role < 1 && !chat.CanPinMessages {
		response.Forbidden(c, "仅管理员可以置顶消息")
		return
	}

	msg, err := h.findMessageByMsgID(context.Background(), chatUUID, req.MessageID)
	if err != nil {
		if errors.Is(err, mongo.ErrNoDocuments) {
			response.NotFound(c, "消息不存在")
			return
		}
		response.ServerError(c, "置顶失败")
		return
	}
	msgText := buildPinnedMessagePreview(msg)
	now := time.Now()
	if err := h.db.Model(&chat).Updates(map[string]interface{}{
		"pinned_message_id":   req.MessageID,
		"pinned_message_text": msgText,
		"pinned_message_by":   currentUser.ID,
		"pinned_message_at":   now,
		"updated_at":          now,
	}).Error; err != nil {
		response.ServerError(c, "置顶失败")
		return
	}
	h.hub.SendToChat(chatUUID, map[string]interface{}{
		"type":         "message_pinned",
		"chat_id":      chatUUID,
		"message_id":   req.MessageID,
		"message_text": msgText,
		"pinned_by":    userID,
		"pinned_at":    now.Format("2006-01-02 15:04:05"),
	}, "")
	response.Success(c, map[string]interface{}{
		"message_id":          req.MessageID,
		"message_text":        msgText,
		"pinned_message_id":   req.MessageID,
		"pinned_message_text": msgText,
	})
}

func (h *PinHandler) UnpinMessage(c *gin.Context) {
	userID := c.GetString("user_id")
	chatUUID := c.Param("id")

	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return
	}
	if chat.Status != models.ChatStatusNormal {
		response.Forbidden(c, "会话已被封禁或解散")
		return
	}

	var currentUser models.User
	if err := h.db.Where("uuid = ?", userID).First(&currentUser).Error; err != nil {
		response.Forbidden(c, "用户不存在")
		return
	}

	var member models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", chat.ID, currentUser.ID).First(&member).Error; err != nil {
		response.Forbidden(c, "您不是该群成员")
		return
	}

	// 管理员/群主始终可以取消置顶；普通成员需要 CanPinMessages 开启
	if member.Role < 1 && !chat.CanPinMessages {
		response.Forbidden(c, "仅管理员可以取消置顶")
		return
	}
	if err := h.db.Model(&chat).Updates(map[string]interface{}{
		"pinned_message_id":   "",
		"pinned_message_text": "",
		"pinned_message_by":   0,
		"pinned_message_at":   nil,
		"updated_at":          time.Now(),
	}).Error; err != nil {
		response.ServerError(c, "取消置顶失败")
		return
	}
	h.hub.SendToChat(chatUUID, map[string]interface{}{
		"type":        "message_unpinned",
		"chat_id":     chatUUID,
		"unpinned_by": userID,
	}, "")
	response.SuccessWithMessage(c, "已取消置顶", nil)
}

func (h *PinHandler) GetPinnedMessage(c *gin.Context) {
	chatUUID := c.Param("id")

	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return
	}
	if chat.PinnedMessageID == "" {
		response.Success(c, nil)
		return
	}
	pinnedText := strings.TrimSpace(chat.PinnedMessageText)
	if chat.PinnedMessageID != "" {
		msg, findErr := h.findMessageByMsgID(context.Background(), chatUUID, chat.PinnedMessageID)
		if findErr == nil {
			rebuiltText := buildPinnedMessagePreview(msg)
			if rebuiltText != "" && rebuiltText != pinnedText {
				pinnedText = rebuiltText
				_ = h.db.Model(&chat).Update("pinned_message_text", pinnedText).Error
			}
		}
	}
	response.Success(c, map[string]interface{}{
		"message_id":   chat.PinnedMessageID,
		"message_text": pinnedText,
		"pinned_by":    chat.PinnedMessageBy,
		"pinned_at":    chat.PinnedMessageAt,
	})
}

func (h *PinHandler) findMessageByMsgID(ctx context.Context, chatID string, msgID string) (*models.Message, error) {
	collections, err := h.mongoDB.ListCollectionNames(ctx, bson.M{
		"name": bson.M{"$regex": "^messages_"},
	})
	if err != nil {
		return nil, err
	}
	sort.Sort(sort.Reverse(sort.StringSlice(collections)))
	collections = append(collections, "messages")
	seen := make(map[string]struct{}, len(collections))
	for _, name := range collections {
		if _, ok := seen[name]; ok {
			continue
		}
		seen[name] = struct{}{}

		var msg models.Message
		err := h.mongoDB.Collection(name).FindOne(ctx, bson.M{
			"msg_id":  msgID,
			"chat_id": chatID,
		}).Decode(&msg)
		if err == nil {
			return &msg, nil
		}
		if !errors.Is(err, mongo.ErrNoDocuments) {
			return nil, err
		}
	}
	return nil, mongo.ErrNoDocuments
}
