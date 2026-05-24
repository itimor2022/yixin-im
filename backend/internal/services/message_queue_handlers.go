package services

import (
	"context"
	"encoding/json"
	"fmt"

	"time"

	"gaoranim/internal/models"
	"gaoranim/internal/mq"
	"gorm.io/gorm"
)

// RegisterMessageQueueHandlers registers consumers for message-related queues.
// Realtime WebSocket delivery is performed in MessageService immediately after
// MongoDB persistence. The sync_message consumer validates and acknowledges
// legacy/best-effort queue entries so they are not silently discarded as
// unknown message types.
func RegisterMessageQueueHandlers(queue *mq.MessageQueue, pushService *PushService, db *gorm.DB) {
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

	// user_chat_sync: 异步更新 user_chats 会话预览
	// 每条消息发送后投递到此队列，消费者批量写入 MySQL，避免同步阻塞请求
	queue.RegisterHandler("user_chat_sync", func(ctx context.Context, msg *mq.QueueMessage) error {
		if db == nil {
			return fmt.Errorf("db is nil")
		}

		var payload struct {
			ChatID        uint64 `json:"chat_id"`
			SenderID      uint64 `json:"sender_id"`       // 发送者不增加自己的未读数
			LastMsgID     string `json:"last_msg_id"`
			LastMsgSeq    int64  `json:"last_msg_seq"`
			LastMsgTime   int64  `json:"last_msg_time"`   // Unix 毫秒
			LastMsgText   string `json:"last_msg_text"`
			LastMsgType   int    `json:"last_msg_type"`
			LastMsgSender string `json:"last_msg_sender"`
		}
		if err := json.Unmarshal(msg.Payload, &payload); err != nil {
			return fmt.Errorf("decode user_chat_sync payload: %w", err)
		}
		if payload.ChatID == 0 || payload.LastMsgID == "" {
			return fmt.Errorf("invalid user_chat_sync payload: chat_id or last_msg_id is empty")
		}

		msgTime := time.UnixMilli(payload.LastMsgTime)

		// 更新所有成员的会话预览（last_msg 字段 + sort_time）
		// 发送者的 unread_count 不增加；其他成员 unread_count+1
		err := db.Model(&models.UserChat{}).
			Where("chat_id = ? AND user_id != ?", payload.ChatID, payload.SenderID).
			Updates(map[string]interface{}{
				"last_msg_id":     payload.LastMsgID,
				"last_msg_seq":    payload.LastMsgSeq,
				"last_msg_time":   msgTime,
				"last_msg_text":   payload.LastMsgText,
				"last_msg_type":   payload.LastMsgType,
				"last_msg_sender": payload.LastMsgSender,
				"sort_time":       msgTime,
				"unread_count":    gorm.Expr("unread_count + 1"),
			}).Error
		if err != nil {
			return fmt.Errorf("update user_chats for non-sender: %w", err)
		}

		// 发送者自己：只更新预览，不增加未读数
		err = db.Model(&models.UserChat{}).
			Where("chat_id = ? AND user_id = ?", payload.ChatID, payload.SenderID).
			Updates(map[string]interface{}{
				"last_msg_id":     payload.LastMsgID,
				"last_msg_seq":    payload.LastMsgSeq,
				"last_msg_time":   msgTime,
				"last_msg_text":   payload.LastMsgText,
				"last_msg_type":   payload.LastMsgType,
				"last_msg_sender": payload.LastMsgSender,
				"sort_time":       msgTime,
			}).Error
		if err != nil {
			return fmt.Errorf("update user_chats for sender: %w", err)
		}

		return nil
	})
}
