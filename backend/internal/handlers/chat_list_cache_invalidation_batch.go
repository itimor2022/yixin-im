// 文件用途：合并高频群消息产生的会话列表缓存失效，避免每条消息都遍历全群成员更新 Redis 版本。
// 核心逻辑：同一群在固定窗口内只查询一次成员并批量递增会话列表版本；私聊仍走同步的两人失效路径。

package handlers

import (
	"context"
	"log"
	"sync"
	"time"

	"genericim/internal/models"
)

type chatListCacheInvalidationBatcher struct {
	mu          sync.Mutex
	delay       time.Duration
	dispatch    func(uint64)
	pending     map[uint64]*time.Timer
	firstSeen   map[uint64]time.Time
	generations map[uint64]uint64
}

func newChatListCacheInvalidationBatcher(delay time.Duration, dispatch func(uint64)) *chatListCacheInvalidationBatcher {
	if delay <= 0 {
		delay = 500 * time.Millisecond
	}
	return &chatListCacheInvalidationBatcher{
		delay:       delay,
		dispatch:    dispatch,
		pending:     make(map[uint64]*time.Timer),
		firstSeen:   make(map[uint64]time.Time),
		generations: make(map[uint64]uint64),
	}
}

func (b *chatListCacheInvalidationBatcher) scheduleLocked(chatID uint64) {
	if timer := b.pending[chatID]; timer != nil {
		timer.Stop()
	}
	b.generations[chatID]++
	generation := b.generations[chatID]
	delay := nextDebounceDelay(b.firstSeen[chatID], b.delay)
	b.pending[chatID] = time.AfterFunc(delay, func() {
		b.flushGeneration(chatID, generation)
	})
}

func (b *chatListCacheInvalidationBatcher) enqueue(chatID uint64) {
	if b == nil || b.dispatch == nil || chatID == 0 {
		return
	}
	b.mu.Lock()
	if _, exists := b.pending[chatID]; !exists {
		b.firstSeen[chatID] = time.Now()
	}
	b.scheduleLocked(chatID)
	b.mu.Unlock()
}

func (b *chatListCacheInvalidationBatcher) flush(chatID uint64) {
	if b == nil {
		return
	}
	b.mu.Lock()
	timer, exists := b.pending[chatID]
	if timer != nil {
		timer.Stop()
	}
	delete(b.pending, chatID)
	delete(b.firstSeen, chatID)
	delete(b.generations, chatID)
	b.mu.Unlock()
	if exists && b.dispatch != nil {
		b.dispatch(chatID)
	}
}

func (b *chatListCacheInvalidationBatcher) flushGeneration(chatID uint64, generation uint64) {
	if b == nil {
		return
	}
	b.mu.Lock()
	if b.generations[chatID] != generation {
		b.mu.Unlock()
		return
	}
	_, exists := b.pending[chatID]
	delete(b.pending, chatID)
	delete(b.firstSeen, chatID)
	delete(b.generations, chatID)
	b.mu.Unlock()
	if exists && b.dispatch != nil {
		b.dispatch(chatID)
	}
}

func (b *chatListCacheInvalidationBatcher) pendingCount() int {
	if b == nil {
		return 0
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	return len(b.pending)
}

func (h *MessageHandler) enqueueChatListCacheInvalidation(chatID uint64) {
	if h == nil || h.cache == nil || h.chatListCacheBatcher == nil {
		return
	}
	h.chatListCacheBatcher.enqueue(chatID)
}

func (h *MessageHandler) invalidateChatListCacheForMembers(chatID uint64) {
	if h == nil || h.db == nil || h.cache == nil || chatID == 0 {
		return
	}
	var userIDs []uint64
	if err := h.db.Model(&models.UserChat{}).
		Where("chat_id = ?", chatID).
		Pluck("user_id", &userIDs).Error; err != nil {
		log.Printf("[ChatListCacheBatch] query members failed chatID=%d err=%v", chatID, err)
		return
	}
	deleteUserChatListHotCache(context.Background(), h.cache, userIDs...)
	log.Printf("[ChatListCacheBatch] chatID=%d invalidated_users=%d", chatID, len(userIDs))
}
