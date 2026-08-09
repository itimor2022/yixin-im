// 文件用途：合并高频群消息的离线推送，并在一个批次内筛选在线、静音和无设备成员。
// 核心逻辑：同一群 500ms 内只保留最高 seq 的通知正文，同时合并 @ 信息，避免逐消息乘以全体成员的后台扇出。

package handlers

import (
	"fmt"
	"log"
	"sync"
	"time"

	"genericim/internal/models"
	"genericim/internal/services"
)

type messagePushTarget struct {
	UserID uint64
	UUID   string
}

type messagePushTask struct {
	chatID         uint64
	chatUUID       string
	chatType       string
	messageID      string
	messageSeq     uint64
	senderUserID   uint64
	senderName     string
	content        string
	mediaURL       string
	targets        []messagePushTarget
	mentionedUUIDs map[string]struct{}
	mentionsAll    bool
}

func cloneMessagePushTask(task messagePushTask) messagePushTask {
	task.targets = append([]messagePushTarget(nil), task.targets...)
	task.mentionedUUIDs = cloneStringSet(task.mentionedUUIDs)
	return task
}

func cloneStringSet(values map[string]struct{}) map[string]struct{} {
	if len(values) == 0 {
		return nil
	}
	cloned := make(map[string]struct{}, len(values))
	for value := range values {
		cloned[value] = struct{}{}
	}
	return cloned
}

type messagePushBatcher struct {
	mu          sync.Mutex
	delay       time.Duration
	dispatch    func(messagePushTask)
	pending     map[uint64]messagePushTask
	timers      map[uint64]*time.Timer
	firstSeen   map[uint64]time.Time
	generations map[uint64]uint64
}

func newMessagePushBatcher(delay time.Duration, dispatch func(messagePushTask)) *messagePushBatcher {
	if delay <= 0 {
		delay = 500 * time.Millisecond
	}
	return &messagePushBatcher{
		delay:       delay,
		dispatch:    dispatch,
		pending:     make(map[uint64]messagePushTask),
		timers:      make(map[uint64]*time.Timer),
		firstSeen:   make(map[uint64]time.Time),
		generations: make(map[uint64]uint64),
	}
}

func (b *messagePushBatcher) scheduleLocked(chatID uint64) {
	if timer := b.timers[chatID]; timer != nil {
		timer.Stop()
	}
	b.generations[chatID]++
	generation := b.generations[chatID]
	delay := nextDebounceDelay(b.firstSeen[chatID], b.delay)
	b.timers[chatID] = time.AfterFunc(delay, func() {
		b.flushGeneration(chatID, generation)
	})
}

func (b *messagePushBatcher) enqueue(task messagePushTask) {
	if b == nil || b.dispatch == nil || task.chatID == 0 || task.messageID == "" {
		return
	}

	b.mu.Lock()
	current, exists := b.pending[task.chatID]
	if !exists {
		b.pending[task.chatID] = cloneMessagePushTask(task)
		b.firstSeen[task.chatID] = time.Now()
		b.scheduleLocked(task.chatID)
		b.mu.Unlock()
		return
	}

	mentionsAll := current.mentionsAll || task.mentionsAll
	mentionedUUIDs := cloneStringSet(current.mentionedUUIDs)
	if mentionedUUIDs == nil && len(task.mentionedUUIDs) > 0 {
		mentionedUUIDs = make(map[string]struct{}, len(task.mentionedUUIDs))
	}
	for userUUID := range task.mentionedUUIDs {
		mentionedUUIDs[userUUID] = struct{}{}
	}

	if task.messageSeq >= current.messageSeq {
		current = cloneMessagePushTask(task)
	}
	current.mentionsAll = mentionsAll
	current.mentionedUUIDs = mentionedUUIDs
	b.pending[task.chatID] = current
	b.scheduleLocked(task.chatID)
	b.mu.Unlock()
}

func (b *messagePushBatcher) flush(chatID uint64) {
	if b == nil {
		return
	}
	b.mu.Lock()
	task, exists := b.pending[chatID]
	if timer := b.timers[chatID]; timer != nil {
		timer.Stop()
	}
	delete(b.pending, chatID)
	delete(b.timers, chatID)
	delete(b.firstSeen, chatID)
	delete(b.generations, chatID)
	b.mu.Unlock()
	if exists && b.dispatch != nil {
		b.dispatch(task)
	}
}

func (b *messagePushBatcher) flushGeneration(chatID uint64, generation uint64) {
	if b == nil {
		return
	}
	b.mu.Lock()
	if b.generations[chatID] != generation {
		b.mu.Unlock()
		return
	}
	task, exists := b.pending[chatID]
	delete(b.pending, chatID)
	delete(b.timers, chatID)
	delete(b.firstSeen, chatID)
	delete(b.generations, chatID)
	b.mu.Unlock()
	if exists && b.dispatch != nil {
		b.dispatch(task)
	}
}

func (b *messagePushBatcher) pendingCount() int {
	if b == nil {
		return 0
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	return len(b.pending)
}

func (h *MessageHandler) enqueueMessagePush(task messagePushTask) {
	if h == nil || h.pushService == nil || h.messagePushBatcher == nil {
		return
	}
	h.messagePushBatcher.enqueue(task)
}

func (h *MessageHandler) sendBatchedMessagePush(task messagePushTask) {
	if err := h.sendBatchedMessagePushWithError(task); err != nil {
		log.Printf("[PushBatch] send failed chat=%s seq=%d err=%v", task.chatUUID, task.messageSeq, err)
	}
}

func (h *MessageHandler) sendBatchedMessagePushWithError(task messagePushTask) error {
	if h == nil || h.db == nil || h.pushService == nil {
		return nil
	}
	if len(task.targets) == 0 {
		var targets []messagePushTarget
		query := h.db.Table("chat_members AS cm").
			Select("cm.user_id AS user_id, u.uuid AS uuid").
			Joins("JOIN users AS u ON u.id = cm.user_id").
			Where("cm.chat_id = ?", task.chatID)
		if task.senderUserID != 0 {
			query = query.Where("cm.user_id != ?", task.senderUserID)
		}
		if err := query.Scan(&targets).Error; err != nil {
			return fmt.Errorf("query members: %w", err)
		}
		task.targets = targets
	}
	if len(task.targets) == 0 {
		return nil
	}

	recipients := make([]services.NewMessagePushRecipient, 0, len(task.targets))
	seenUserIDs := make(map[uint64]struct{}, len(task.targets))
	for _, target := range task.targets {
		if target.UserID == 0 || target.UUID == "" {
			continue
		}
		if _, exists := seenUserIDs[target.UserID]; exists {
			continue
		}
		seenUserIDs[target.UserID] = struct{}{}
		if h.hub != nil && h.hub.IsUserOnline(target.UUID) {
			continue
		}
		_, directlyMentioned := task.mentionedUUIDs[target.UUID]
		recipients = append(recipients, services.NewMessagePushRecipient{
			UserID:    target.UserID,
			Mentioned: task.mentionsAll || directlyMentioned,
		})
	}
	if len(recipients) == 0 {
		return nil
	}

	userIDs := make([]uint64, 0, len(recipients))
	for _, recipient := range recipients {
		userIDs = append(userIDs, recipient.UserID)
	}
	var mutedUserIDs []uint64
	if err := h.db.Model(&models.UserChat{}).
		Where("chat_id = ? AND user_id IN ? AND is_muted = ?", task.chatID, userIDs, true).
		Pluck("user_id", &mutedUserIDs).Error; err != nil {
		return fmt.Errorf("query muted users: %w", err)
	}
	if len(mutedUserIDs) > 0 {
		muted := make(map[uint64]struct{}, len(mutedUserIDs))
		for _, userID := range mutedUserIDs {
			muted[userID] = struct{}{}
		}
		filtered := recipients[:0]
		for _, recipient := range recipients {
			if _, isMuted := muted[recipient.UserID]; !isMuted {
				filtered = append(filtered, recipient)
			}
		}
		recipients = filtered
	}
	if len(recipients) == 0 {
		return nil
	}

	result, err := h.pushService.PushNewMessageBatch(
		recipients,
		task.senderName,
		task.content,
		task.chatUUID,
		task.chatType,
		task.messageID,
		task.mediaURL,
	)
	if err != nil {
		return fmt.Errorf("push recipients=%d: %w", len(recipients), err)
	}
	log.Printf(
		"[PushBatch] chat=%s seq=%d candidates=%d device_users=%d scheduled_devices=%d",
		task.chatUUID,
		task.messageSeq,
		len(recipients),
		result.DeviceUsers,
		result.ScheduledDevices,
	)
	return nil
}
