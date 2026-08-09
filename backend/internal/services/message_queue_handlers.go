// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"context"
	"encoding/json"
	"fmt"
	"genericim/internal/models"
	"genericim/internal/mq"
)

// RegisterMessageQueueHandlers
//

func RegisterMessageQueueHandlers(queue *mq.MessageQueue, pushService *PushService) {
	if queue == nil {
		return
	}
	queue.RegisterHandler("sync_message", func(ctx context.Context, msg *mq.QueueMessage) error {
		var stored models.Message
		if err := json.Unmarshal(msg.Payload, &stored); err != nil {
			return fmt.Errorf("decode sync_message payload: %w", err)
		}
		if stored.ChatID == "" || stored.MsgID == "" {
			return fmt.Errorf("invalid sync_message payload: chat_id or msg_id is empty")
		}
		return nil
	})
	queue.RegisterHandler("push_notify", func(ctx context.Context, msg *mq.QueueMessage) error {

		if pushService == nil {
			return fmt.Errorf("push service is not initialized")
		}

		var payload struct {
			UserID uint64                 `json:"user_id"`
			Title  string                 `json:"title"`
			Body   string                 `json:"body"`
			Data   map[string]interface{} `json:"data"`
		}
		if err := json.Unmarshal(msg.Payload, &payload); err != nil {
			return fmt.Errorf("decode push_notify payload: %w", err)
		}
		if payload.UserID == 0 {
			return fmt.Errorf("invalid push_notify payload: user_id is empty")
		}
		return pushService.PushToUser(payload.UserID, payload.Title, payload.Body, payload.Data)
	})
}
