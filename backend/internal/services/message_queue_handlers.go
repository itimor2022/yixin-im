package services

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	appCache "gaoranim/internal/cache"
	"gaoranim/internal/models"
	"gaoranim/internal/mq"
	"gorm.io/gorm"
)

// RegisterMessageQueueHandlers registers consumers for message-related queues.
// Realtime WebSocket delivery is performed in MessageService immediately after
// MongoDB persistence. The sync_message consumer validates and acknowledges
// legacy/best-effort queue entries so they are not silently discarded as
// unknown message types.
func RegisterMessageQueueHandlers(queue *mq.MessageQueue, pushService *PushService, db *gorm.DB, cache *appCache.Cache) {
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

        // user_chat_sync: F-04B 时间线模型
        // 发消息只写 Redis（last_seq + last_msg），不写 MySQL
        // unread_count 由客户端拉取会话列表时实时计算（last_seq - last_read_seq）
        queue.RegisterHandler("user_chat_sync", func(ctx context.Context, msg *mq.QueueMessage) error {
                if cache == nil {
                        return fmt.Errorf("cache is nil")
                }

                var payload struct {
                        ChatUUID      string `json:"chat_uuid"`
                        LastMsgID     string `json:"last_msg_id"`
                        LastMsgSeq    uint64 `json:"last_msg_seq"`
                        LastMsgTime   int64  `json:"last_msg_time"`
                        LastMsgText   string `json:"last_msg_text"`
                        LastMsgType   int    `json:"last_msg_type"`
                        LastMsgSender string `json:"last_msg_sender"`
                }
                if err := json.Unmarshal(msg.Payload, &payload); err != nil {
                        return fmt.Errorf("decode user_chat_sync payload: %w", err)
                }
                if payload.ChatUUID == "" || payload.LastMsgID == "" {
                        return fmt.Errorf("invalid user_chat_sync payload")
                }

                // ★ 只写 Redis，不碰 MySQL
                if err := cache.SetChatLastSeq(ctx, payload.ChatUUID, payload.LastMsgSeq); err != nil {
                        return fmt.Errorf("SetChatLastSeq failed: %w", err)
                }

                lastMsg := map[string]interface{}{
                        "msg_id":      payload.LastMsgID,
                        "seq":         payload.LastMsgSeq,
                        "time":        payload.LastMsgTime,
                        "text":        payload.LastMsgText,
                        "type":        payload.LastMsgType,
                        "sender_name": payload.LastMsgSender,
                }
                if err := cache.SetChatLastMsg(ctx, payload.ChatUUID, lastMsg); err != nil {
                        return fmt.Errorf("SetChatLastMsg failed: %w", err)
                }

				// ★ 同步写 MySQL chat_last_msg 表，作为 Redis 过期后的兜底
				if db != nil {
					var chatRow struct{ ID uint64 }
					if err2 := db.Table("chats").Select("id").Where("uuid = ?", payload.ChatUUID).Scan(&chatRow).Error; err2 == nil && chatRow.ID > 0 {
						msgTime := time.UnixMilli(payload.LastMsgTime)
						db.Exec(`INSERT INTO chat_last_msg (chat_id, last_seq, last_msg_time, last_msg_text, last_msg_type, last_msg_sender, updated_at)
							VALUES (?, ?, ?, ?, ?, ?, NOW())
							ON DUPLICATE KEY UPDATE
								last_seq = IF(VALUES(last_seq) >= last_seq, VALUES(last_seq), last_seq),
								last_msg_time = IF(VALUES(last_seq) >= last_seq, VALUES(last_msg_time), last_msg_time),
								last_msg_text = IF(VALUES(last_seq) >= last_seq, VALUES(last_msg_text), last_msg_text),
								last_msg_type = IF(VALUES(last_seq) >= last_seq, VALUES(last_msg_type), last_msg_type),
								last_msg_sender = IF(VALUES(last_seq) >= last_seq, VALUES(last_msg_sender), last_msg_sender),
								updated_at = NOW()`,
							chatRow.ID, payload.LastMsgSeq, msgTime, payload.LastMsgText, payload.LastMsgType, payload.LastMsgSender)
					}
				}

                return nil
        })
}
