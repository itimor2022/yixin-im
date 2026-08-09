// 文件用途：持久化并消费消息提交后的派生工作，替代只存在于进程内存中的短窗口队列。
// 核心逻辑：消息 ACK 前批量写入唯一 Outbox 事件；后台按租约领取、阶段提交和退避重试，进程重启后继续处理。

package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/google/uuid"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"genericim/internal/models"
	"genericim/internal/services"
)

const (
	messageOutboxPollInterval = 100 * time.Millisecond
	messageOutboxLease        = 2 * time.Minute
	messageOutboxClaimLimit   = 2000
	messageOutboxMaxAttempts  = 8
)

type messageOutboxPayload struct {
	ChatID           uint64    `json:"chat_id"`
	ChatUUID         string    `json:"chat_uuid"`
	ChatType         int8      `json:"chat_type"`
	MessageID        string    `json:"message_id"`
	MessageSeq       uint64    `json:"message_seq"`
	MessageType      int       `json:"message_type"`
	MessageCreatedAt time.Time `json:"message_created_at"`
	SenderUserID     uint64    `json:"sender_user_id"`
	SenderUUID       string    `json:"sender_uuid"`
	SenderName       string    `json:"sender_name"`
	MemberUserIDs    []uint64  `json:"member_user_ids,omitempty"`
	LastMsgText      string    `json:"last_msg_text"`
	LastMsgMediaURL  string    `json:"last_msg_media_url,omitempty"`
	MentionAll       bool      `json:"mention_all,omitempty"`
	MentionUUIDs     []string  `json:"mention_uuids,omitempty"`
	PushPreviewText  string    `json:"push_preview_text,omitempty"`
	PushChatType     string    `json:"push_chat_type,omitempty"`
	ReservedMediaIDs []string  `json:"reserved_media_ids,omitempty"`
}

func messageOutboxEventKey(chatUUID, messageID, eventType string) string {
	return fmt.Sprintf("message:%s:%s:%s", strings.TrimSpace(chatUUID), strings.TrimSpace(messageID), strings.TrimSpace(eventType))
}

func messageOutboxAvailableAt(eventType string, now time.Time) time.Time {
	switch eventType {
	case models.MessageOutboxTypeProjection:
		return now.Add(250 * time.Millisecond)
	case models.MessageOutboxTypeMediaCommit, models.MessageOutboxTypePush:
		return now.Add(500 * time.Millisecond)
	default:
		return now
	}
}

func messageOutboxRetryDelay(attempts int) time.Duration {
	if attempts < 1 {
		attempts = 1
	}
	delay := time.Second << min(attempts-1, 6)
	if delay > time.Minute {
		return time.Minute
	}
	return delay
}

func (h *MessageHandler) startMessageOutboxWorkers() {
	if h == nil || h.db == nil {
		return
	}
	workers := 1
	if raw := strings.TrimSpace(os.Getenv("GENERIC_IM_MESSAGE_OUTBOX_WORKERS")); raw != "" {
		if parsed, err := strconv.Atoi(raw); err == nil && parsed >= 0 {
			workers = parsed
		}
	}
	if workers == 0 {
		log.Printf("[MessageOutbox] workers disabled by GENERIC_IM_MESSAGE_OUTBOX_WORKERS=0")
		return
	}
	if h.messageOutboxWake == nil {
		h.messageOutboxWake = make(chan struct{}, 1)
	}
	for i := 0; i < workers; i++ {
		workerID := fmt.Sprintf("%s-%s-%d", hostnameForMessageOutbox(), uuid.NewString()[:8], i)
		go h.runMessageOutboxWorker(workerID)
	}
	log.Printf("[MessageOutbox] started workers=%d", workers)
}

func hostnameForMessageOutbox() string {
	host, err := os.Hostname()
	if err != nil || strings.TrimSpace(host) == "" {
		return "unknown"
	}
	return host
}

func (h *MessageHandler) signalMessageOutbox() {
	if h == nil || h.messageOutboxWake == nil {
		return
	}
	select {
	case h.messageOutboxWake <- struct{}{}:
	default:
	}
}

func (h *MessageHandler) ensureMessageOutboxEvents(ctx context.Context, payload messageOutboxPayload, eventTypes ...string) error {
	if h == nil || h.db == nil || payload.ChatID == 0 || payload.ChatUUID == "" || payload.MessageID == "" {
		return errors.New("invalid message outbox payload")
	}
	if len(eventTypes) == 0 {
		return nil
	}
	encoded, err := json.Marshal(payload)
	if err != nil {
		return fmt.Errorf("encode message outbox payload: %w", err)
	}
	now := time.Now()
	seen := make(map[string]struct{}, len(eventTypes))
	events := make([]models.MessageOutboxEvent, 0, len(eventTypes))
	for _, eventType := range eventTypes {
		eventType = strings.TrimSpace(eventType)
		if eventType == "" {
			continue
		}
		if _, exists := seen[eventType]; exists {
			continue
		}
		seen[eventType] = struct{}{}
		events = append(events, models.MessageOutboxEvent{
			EventKey:    messageOutboxEventKey(payload.ChatUUID, payload.MessageID, eventType),
			EventType:   eventType,
			ChatID:      payload.ChatID,
			ChatUUID:    payload.ChatUUID,
			MessageID:   payload.MessageID,
			MessageSeq:  payload.MessageSeq,
			Payload:     append(json.RawMessage(nil), encoded...),
			Status:      models.MessageOutboxStatusPending,
			AvailableAt: messageOutboxAvailableAt(eventType, now),
		})
	}
	if len(events) == 0 {
		return nil
	}
	if err := h.db.WithContext(ctx).
		Clauses(clause.OnConflict{
			Columns:   []clause.Column{{Name: "event_key"}},
			DoNothing: true,
		}).
		Create(&events).Error; err != nil {
		return fmt.Errorf("persist message outbox: %w", err)
	}
	h.signalMessageOutbox()
	return nil
}

func (h *MessageHandler) runMessageOutboxWorker(workerID string) {
	ticker := time.NewTicker(messageOutboxPollInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
		case <-h.messageOutboxWake:
		}
		for {
			ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
			events, err := h.claimMessageOutboxEvents(ctx, workerID, messageOutboxClaimLimit)
			if err == nil && len(events) > 0 {
				h.processMessageOutboxEvents(ctx, workerID, events)
			}
			cancel()
			if err != nil {
				log.Printf("[MessageOutbox] claim failed worker=%s err=%v", workerID, err)
				break
			}
			if len(events) < messageOutboxClaimLimit {
				break
			}
		}
	}
}

func (h *MessageHandler) claimMessageOutboxEvents(ctx context.Context, workerID string, limit int) ([]models.MessageOutboxEvent, error) {
	if limit <= 0 {
		limit = messageOutboxClaimLimit
	}
	now := time.Now()
	leaseUntil := now.Add(messageOutboxLease)
	events := make([]models.MessageOutboxEvent, 0, limit)
	err := h.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE", Options: "SKIP LOCKED"}).
			Where(
				"(status IN ? AND available_at <= ?) OR (status = ? AND lease_until IS NOT NULL AND lease_until <= ?)",
				[]string{models.MessageOutboxStatusPending, models.MessageOutboxStatusRetrying},
				now,
				models.MessageOutboxStatusProcessing,
				now,
			).
			Order("available_at ASC, id ASC").
			Limit(limit).
			Find(&events).Error; err != nil {
			return err
		}
		if len(events) == 0 {
			return nil
		}
		ids := messageOutboxEventIDs(events)
		result := tx.Model(&models.MessageOutboxEvent{}).
			Where("id IN ?", ids).
			Updates(map[string]interface{}{
				"status":      models.MessageOutboxStatusProcessing,
				"worker_id":   workerID,
				"lease_until": leaseUntil,
				"attempts":    gorm.Expr("attempts + 1"),
				"last_error":  "",
			})
		if result.Error != nil {
			return result.Error
		}
		if result.RowsAffected != int64(len(events)) {
			return fmt.Errorf("claim expected=%d updated=%d", len(events), result.RowsAffected)
		}
		for i := range events {
			events[i].Status = models.MessageOutboxStatusProcessing
			events[i].WorkerID = workerID
			events[i].LeaseUntil = &leaseUntil
			events[i].Attempts++
		}
		return nil
	})
	return events, err
}

func messageOutboxEventIDs(events []models.MessageOutboxEvent) []uint64 {
	ids := make([]uint64, 0, len(events))
	for i := range events {
		ids = append(ids, events[i].ID)
	}
	return ids
}

func decodeMessageOutboxPayload(event models.MessageOutboxEvent) (messageOutboxPayload, error) {
	var payload messageOutboxPayload
	if err := json.Unmarshal(event.Payload, &payload); err != nil {
		return payload, fmt.Errorf("decode event=%d: %w", event.ID, err)
	}
	if payload.ChatID == 0 || payload.ChatUUID == "" || payload.MessageID == "" {
		return payload, fmt.Errorf("event=%d has incomplete payload", event.ID)
	}
	return payload, nil
}

func (h *MessageHandler) processMessageOutboxEvents(ctx context.Context, workerID string, events []models.MessageOutboxEvent) {
	byType := make(map[string][]models.MessageOutboxEvent)
	for i := range events {
		byType[events[i].EventType] = append(byType[events[i].EventType], events[i])
	}
	handled := make(map[string]struct{}, 4)
	for _, eventType := range []string{
		models.MessageOutboxTypeProjection,
		models.MessageOutboxTypeMediaCommit,
		models.MessageOutboxTypeServiceConversation,
		models.MessageOutboxTypePush,
	} {
		typed := byType[eventType]
		if len(typed) == 0 {
			continue
		}
		handled[eventType] = struct{}{}
		switch eventType {
		case models.MessageOutboxTypeProjection:
			h.processMessageProjectionOutbox(ctx, workerID, typed)
		case models.MessageOutboxTypeMediaCommit:
			h.processMessageMediaOutbox(ctx, workerID, typed)
		case models.MessageOutboxTypeServiceConversation:
			h.processServiceConversationOutbox(ctx, workerID, typed)
		case models.MessageOutboxTypePush:
			h.processMessagePushOutbox(ctx, workerID, typed)
		}
	}
	for eventType, typed := range byType {
		if _, ok := handled[eventType]; !ok {
			h.retryMessageOutboxEvents(ctx, workerID, typed, fmt.Errorf("unsupported event type %q", eventType))
		}
	}
}

func payloadProjectionTask(payload messageOutboxPayload) messageProjectionTask {
	return messageProjectionTask{
		chat: models.Chat{
			ID:   payload.ChatID,
			UUID: payload.ChatUUID,
			Type: payload.ChatType,
		},
		message: models.Message{
			MsgID:     payload.MessageID,
			ChatID:    payload.ChatUUID,
			Seq:       payload.MessageSeq,
			Type:      payload.MessageType,
			CreatedAt: payload.MessageCreatedAt,
		},
		sender: models.User{
			ID:   payload.SenderUserID,
			UUID: payload.SenderUUID,
		},
		senderName:      payload.SenderName,
		memberUserIDs:   append([]uint64(nil), payload.MemberUserIDs...),
		lastMsgText:     payload.LastMsgText,
		lastMsgMediaURL: payload.LastMsgMediaURL,
		mentionAll:      payload.MentionAll,
		mentionUUIDs:    append([]string(nil), payload.MentionUUIDs...),
	}
}

func projectionBatchFromEvents(events []models.MessageOutboxEvent) (messageProjectionBatch, error) {
	var batch messageProjectionBatch
	for i := range events {
		payload, err := decodeMessageOutboxPayload(events[i])
		if err != nil {
			return batch, err
		}
		task := payloadProjectionTask(payload)
		if batch.messageCount == 0 {
			batch = newMessageProjectionBatch(task)
		} else {
			batch = mergeMessageProjectionBatch(batch, task)
		}
	}
	return batch, nil
}

func (h *MessageHandler) processMessageProjectionOutbox(ctx context.Context, workerID string, events []models.MessageOutboxEvent) {
	byChat := make(map[uint64][]models.MessageOutboxEvent)
	for i := range events {
		byChat[events[i].ChatID] = append(byChat[events[i].ChatID], events[i])
	}
	chatIDs := make([]uint64, 0, len(byChat))
	for chatID := range byChat {
		chatIDs = append(chatIDs, chatID)
	}
	sort.Slice(chatIDs, func(i, j int) bool { return chatIDs[i] < chatIDs[j] })
	for _, chatID := range chatIDs {
		group := byChat[chatID]
		allBatch, err := projectionBatchFromEvents(group)
		if err != nil {
			h.retryMessageOutboxEvents(ctx, workerID, group, err)
			continue
		}
		fresh := make([]models.MessageOutboxEvent, 0, len(group))
		for i := range group {
			if group[i].DBAppliedAt == nil {
				fresh = append(fresh, group[i])
			}
		}
		lock := &h.messageProjectionLocks[chatID%uint64(len(h.messageProjectionLocks))]
		lock.Lock()
		if len(fresh) > 0 {
			freshBatch, batchErr := projectionBatchFromEvents(fresh)
			if batchErr == nil {
				batchErr = h.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
					if err := h.applyMessageProjectionDB(tx, freshBatch); err != nil {
						return err
					}
					now := time.Now()
					result := tx.Model(&models.MessageOutboxEvent{}).
						Where("id IN ? AND worker_id = ? AND status = ?", messageOutboxEventIDs(fresh), workerID, models.MessageOutboxStatusProcessing).
						Update("db_applied_at", now)
					if result.Error != nil {
						return result.Error
					}
					if result.RowsAffected != int64(len(fresh)) {
						return fmt.Errorf("projection stage marker expected=%d updated=%d", len(fresh), result.RowsAffected)
					}
					return nil
				})
			}
			if batchErr != nil {
				lock.Unlock()
				h.retryMessageOutboxEvents(ctx, workerID, group, batchErr)
				continue
			}
		}
		err = h.applyMessageProjectionPost(ctx, allBatch)
		lock.Unlock()
		if err != nil {
			h.retryMessageOutboxEvents(ctx, workerID, group, err)
			continue
		}
		h.completeMessageOutboxEvents(ctx, workerID, group)
	}
}

func (h *MessageHandler) processMessageMediaOutbox(ctx context.Context, workerID string, events []models.MessageOutboxEvent) {
	fresh := make([]models.MessageOutboxEvent, 0, len(events))
	mediaSet := make(map[string]struct{})
	for i := range events {
		payload, err := decodeMessageOutboxPayload(events[i])
		if err != nil {
			h.retryMessageOutboxEvents(ctx, workerID, []models.MessageOutboxEvent{events[i]}, err)
			continue
		}
		if events[i].DBAppliedAt != nil {
			continue
		}
		fresh = append(fresh, events[i])
		for _, mediaID := range payload.ReservedMediaIDs {
			if mediaID = strings.TrimSpace(mediaID); mediaID != "" {
				mediaSet[mediaID] = struct{}{}
			}
		}
	}
	if len(fresh) > 0 {
		mediaIDs := make([]string, 0, len(mediaSet))
		for mediaID := range mediaSet {
			mediaIDs = append(mediaIDs, mediaID)
		}
		err := h.db.WithContext(ctx).Transaction(func(tx *gorm.DB) error {
			if err := services.CommitMessageMediaBatch(tx, mediaIDs); err != nil {
				return err
			}
			now := time.Now()
			result := tx.Model(&models.MessageOutboxEvent{}).
				Where("id IN ? AND worker_id = ? AND status = ?", messageOutboxEventIDs(fresh), workerID, models.MessageOutboxStatusProcessing).
				Update("db_applied_at", now)
			if result.Error != nil {
				return result.Error
			}
			if result.RowsAffected != int64(len(fresh)) {
				return fmt.Errorf("media stage marker expected=%d updated=%d", len(fresh), result.RowsAffected)
			}
			return nil
		})
		if err != nil {
			h.retryMessageOutboxEvents(ctx, workerID, events, err)
			return
		}
	}
	h.completeMessageOutboxEvents(ctx, workerID, events)
}

func (h *MessageHandler) processServiceConversationOutbox(ctx context.Context, workerID string, events []models.MessageOutboxEvent) {
	for i := range events {
		event := events[i]
		payload, err := decodeMessageOutboxPayload(event)
		if err == nil && h.serviceConversationService == nil {
			err = errors.New("service conversation service is not ready")
		}
		if err == nil {
			sender := models.User{ID: payload.SenderUserID, UUID: payload.SenderUUID}
			chat := models.Chat{ID: payload.ChatID, UUID: payload.ChatUUID, Type: payload.ChatType}
			msg := models.Message{
				MsgID:     payload.MessageID,
				ChatID:    payload.ChatUUID,
				Seq:       payload.MessageSeq,
				Type:      payload.MessageType,
				CreatedAt: payload.MessageCreatedAt,
			}
			err = h.serviceConversationService.OnCustomerMessage(ctx, &sender, &chat, payload.MemberUserIDs, &msg, payload.LastMsgText)
		}
		if err != nil {
			h.retryMessageOutboxEvents(ctx, workerID, []models.MessageOutboxEvent{event}, err)
			continue
		}
		h.completeMessageOutboxEvents(ctx, workerID, []models.MessageOutboxEvent{event})
	}
}

func payloadPushTask(payload messageOutboxPayload) messagePushTask {
	mentions := make(map[string]struct{}, len(payload.MentionUUIDs))
	for _, userUUID := range payload.MentionUUIDs {
		if userUUID = strings.TrimSpace(userUUID); userUUID != "" {
			mentions[userUUID] = struct{}{}
		}
	}
	return messagePushTask{
		chatID:         payload.ChatID,
		chatUUID:       payload.ChatUUID,
		chatType:       payload.PushChatType,
		messageID:      payload.MessageID,
		messageSeq:     payload.MessageSeq,
		senderUserID:   payload.SenderUserID,
		senderName:     payload.SenderName,
		content:        payload.PushPreviewText,
		mediaURL:       payload.LastMsgMediaURL,
		mentionedUUIDs: mentions,
		mentionsAll:    payload.MentionAll,
	}
}

func mergeOutboxPushTask(current, next messagePushTask) messagePushTask {
	mentionsAll := current.mentionsAll || next.mentionsAll
	mentionedUUIDs := cloneStringSet(current.mentionedUUIDs)
	if mentionedUUIDs == nil {
		mentionedUUIDs = make(map[string]struct{})
	}
	for userUUID := range next.mentionedUUIDs {
		mentionedUUIDs[userUUID] = struct{}{}
	}
	if next.messageSeq >= current.messageSeq {
		current = cloneMessagePushTask(next)
	}
	current.mentionsAll = mentionsAll
	current.mentionedUUIDs = mentionedUUIDs
	return current
}

func (h *MessageHandler) processMessagePushOutbox(ctx context.Context, workerID string, events []models.MessageOutboxEvent) {
	type pushGroup struct {
		task   messagePushTask
		events []models.MessageOutboxEvent
	}
	groups := make(map[uint64]pushGroup)
	for i := range events {
		payload, err := decodeMessageOutboxPayload(events[i])
		if err != nil {
			h.retryMessageOutboxEvents(ctx, workerID, []models.MessageOutboxEvent{events[i]}, err)
			continue
		}
		next := payloadPushTask(payload)
		group := groups[payload.ChatID]
		if len(group.events) == 0 {
			group.task = next
		} else {
			group.task = mergeOutboxPushTask(group.task, next)
		}
		group.events = append(group.events, events[i])
		groups[payload.ChatID] = group
	}
	for _, group := range groups {
		if err := h.sendBatchedMessagePushWithError(group.task); err != nil {
			h.retryMessageOutboxEvents(ctx, workerID, group.events, err)
			continue
		}
		h.completeMessageOutboxEvents(ctx, workerID, group.events)
	}
}

func (h *MessageHandler) completeMessageOutboxEvents(ctx context.Context, workerID string, events []models.MessageOutboxEvent) {
	if len(events) == 0 {
		return
	}
	now := time.Now()
	result := h.db.WithContext(ctx).Model(&models.MessageOutboxEvent{}).
		Where("id IN ? AND worker_id = ? AND status = ?", messageOutboxEventIDs(events), workerID, models.MessageOutboxStatusProcessing).
		Updates(map[string]interface{}{
			"status":       models.MessageOutboxStatusCompleted,
			"completed_at": now,
			"lease_until":  nil,
			"worker_id":    "",
			"last_error":   "",
		})
	if result.Error != nil {
		log.Printf("[MessageOutbox] complete failed events=%d err=%v", len(events), result.Error)
	}
}

func (h *MessageHandler) retryMessageOutboxEvents(ctx context.Context, workerID string, events []models.MessageOutboxEvent, processErr error) {
	if len(events) == 0 {
		return
	}
	errText := "unknown processing error"
	if processErr != nil {
		errText = processErr.Error()
	}
	if len(errText) > 1000 {
		errText = errText[:1000]
	}
	for i := range events {
		event := events[i]
		status := models.MessageOutboxStatusRetrying
		availableAt := time.Now().Add(messageOutboxRetryDelay(event.Attempts))
		var completedAt *time.Time
		if event.Attempts >= messageOutboxMaxAttempts {
			status = models.MessageOutboxStatusDead
			now := time.Now()
			completedAt = &now
		}
		result := h.db.WithContext(ctx).Model(&models.MessageOutboxEvent{}).
			Where("id = ? AND worker_id = ? AND status = ?", event.ID, workerID, models.MessageOutboxStatusProcessing).
			Updates(map[string]interface{}{
				"status":       status,
				"available_at": availableAt,
				"lease_until":  nil,
				"worker_id":    "",
				"completed_at": completedAt,
				"last_error":   errText,
			})
		if result.Error != nil {
			log.Printf("[MessageOutbox] retry update failed event=%d err=%v", event.ID, result.Error)
		} else if status == models.MessageOutboxStatusDead {
			log.Printf("[MessageOutbox] event dead id=%d key=%s attempts=%d err=%s", event.ID, event.EventKey, event.Attempts, errText)
		}
	}
}
