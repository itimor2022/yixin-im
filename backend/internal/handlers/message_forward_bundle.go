// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"sort"
	"strings"
	"genericim/internal/models"
	"genericim/pkg/response"
)

const (
	maxForwardBundleItems = 100
	maxForwardBundleDepth = 3
)

func forwardBundleDepth(bundle *models.ForwardBundleInfo) int {
	if bundle == nil {
		return 0
	}
	maxChild := 0
	for _, item := range bundle.Items {
		if depth := forwardBundleDepth(item.Content.ForwardBundle); depth > maxChild {
			maxChild = depth
		}
	}
	return 1 + maxChild
}

func buildForwardBundleSnapshot(messages []*models.Message) *models.ForwardBundleInfo {
	ordered := append([]*models.Message(nil), messages...)
	sort.SliceStable(ordered, func(i, j int) bool {
		if ordered[i].Seq != ordered[j].Seq {
			return ordered[i].Seq < ordered[j].Seq
		}
		return ordered[i].CreatedAt.Before(ordered[j].CreatedAt)
	})
	items := make([]models.ForwardBundleItem, 0, len(ordered))
	senders := make([]string, 0, 2)
	seenSenders := map[string]struct{}{}
	for _, message := range ordered {
		if message == nil {
			continue
		}
		name := strings.TrimSpace(message.SenderName)
		if name == "" {
			name = "Unknown"
		}
		if _, exists := seenSenders[name]; !exists && len(senders) < 2 {
			seenSenders[name] = struct{}{}
			senders = append(senders, name)
		}
		items = append(items, models.ForwardBundleItem{
			SourceMessageID: message.MsgID,
			Type:            message.Type,
			SenderName:      name,
			SenderAvatar:    message.SenderAvatar,
			Content:         message.Content,
			CreatedAt:       message.CreatedAt.UTC(),
		})
	}
	title := "Chat history"
	if len(senders) == 1 {
		title = senders[0] + "'s chat history"
	} else if len(senders) >= 2 {
		title = senders[0] + " and " + senders[1] + "'s chat history"
	}
	return &models.ForwardBundleInfo{Title: title, Items: items}
}

func (h *MessageHandler) prepareForwardBundle(
	c *gin.Context,
	sender *models.User,
	req *SendMessageRequest,
) (*models.ForwardBundleInfo, bool) {
	if sender == nil || req == nil {
		response.BadRequest(c, "invalid forwarded record request")
		return nil, false
	}
	if len(req.SourceMsgIDs) < 2 || len(req.SourceMsgIDs) > maxForwardBundleItems {
		response.BadRequest(c, "forwarded record requires 2 to 100 messages")
		return nil, false
	}

	var sourceChat models.Chat
	if err := h.db.Where("uuid = ?", strings.TrimSpace(req.SourceChatID)).First(&sourceChat).Error; err != nil {
		response.NotFound(c, "source chat not found")
		return nil, false
	}
	var sourceMember models.ChatMember
	if err := h.db.Where("chat_id = ? AND user_id = ?", sourceChat.ID, sender.ID).First(&sourceMember).Error; err != nil {
		response.Forbidden(c, "not allowed to forward source messages")
		return nil, false
	}
	if sourceChat.Type == 2 && !sourceChat.AllowForward && sourceMember.Role < 1 {
		response.Forbidden(c, "forwarding is disabled for the source chat")
		return nil, false
	}
	seen := make(map[string]struct{}, len(req.SourceMsgIDs))
	messages := make([]*models.Message, 0, len(req.SourceMsgIDs))
	for _, rawID := range req.SourceMsgIDs {
		messageID := strings.TrimSpace(rawID)
		if messageID == "" {
			continue
		}
		if _, exists := seen[messageID]; exists {
			continue
		}
		seen[messageID] = struct{}{}
		message, found, err := h.msgService.FindMessageByMsgID(c.Request.Context(), sourceChat.UUID, messageID)
		if err != nil {
			response.ServerError(c, "failed to load source messages")
			return nil, false
		}
		if !found || message == nil || message.IsRevoked ||
			message.BurnAfterRead || message.E2EE != nil ||
			stringSliceContains(message.DeletedFor, sender.UUID) ||
			stringSliceContains(message.BurnedFor, sender.UUID) {
			response.Forbidden(c, "one or more source messages cannot be forwarded")
			return nil, false
		}
		if forwardBundleDepth(message.Content.ForwardBundle) >= maxForwardBundleDepth {
			response.BadRequest(c, "forwarded record nesting is too deep")
			return nil, false
		}
		messages = append(messages, message)
	}
	if len(messages) < 2 {
		response.BadRequest(c, "forwarded record requires two distinct messages")
		return nil, false
	}
	return buildForwardBundleSnapshot(messages), true
}
