// 文件用途：合并已持久化消息的媒体绑定提交，移除图片 ACK 路径中的逐消息 MySQL 更新。
// 核心逻辑：500ms 窗口收集唯一 media_id，窗口结束后一次将 binding 推进为 bound。

package handlers

import (
	"strings"
	"sync"
	"time"
)

type messageMediaCommitBatcher struct {
	mu         sync.Mutex
	delay      time.Duration
	dispatch   func([]string)
	pending    map[string]struct{}
	timer      *time.Timer
	firstSeen  time.Time
	generation uint64
}

func newMessageMediaCommitBatcher(delay time.Duration, dispatch func([]string)) *messageMediaCommitBatcher {
	if delay <= 0 {
		delay = 500 * time.Millisecond
	}
	return &messageMediaCommitBatcher{
		delay:    delay,
		dispatch: dispatch,
		pending:  make(map[string]struct{}),
	}
}

func (b *messageMediaCommitBatcher) scheduleLocked() {
	if b.timer != nil {
		b.timer.Stop()
	}
	b.generation++
	generation := b.generation
	delay := nextDebounceDelay(b.firstSeen, b.delay)
	b.timer = time.AfterFunc(delay, func() {
		b.flushGeneration(generation)
	})
}

func (b *messageMediaCommitBatcher) enqueue(mediaIDs []string) {
	if b == nil || b.dispatch == nil || len(mediaIDs) == 0 {
		return
	}
	b.mu.Lock()
	for _, mediaID := range mediaIDs {
		if mediaID = strings.TrimSpace(mediaID); mediaID != "" {
			b.pending[mediaID] = struct{}{}
		}
	}
	if len(b.pending) > 0 {
		if b.firstSeen.IsZero() {
			b.firstSeen = time.Now()
		}
		b.scheduleLocked()
	}
	b.mu.Unlock()
}

func (b *messageMediaCommitBatcher) flush() {
	if b == nil {
		return
	}
	b.mu.Lock()
	if len(b.pending) == 0 {
		if b.timer != nil {
			b.timer.Stop()
		}
		b.timer = nil
		b.firstSeen = time.Time{}
		b.generation = 0
		b.mu.Unlock()
		return
	}
	if b.timer != nil {
		b.timer.Stop()
	}
	mediaIDs := make([]string, 0, len(b.pending))
	for mediaID := range b.pending {
		mediaIDs = append(mediaIDs, mediaID)
	}
	b.pending = make(map[string]struct{})
	b.timer = nil
	b.firstSeen = time.Time{}
	b.generation = 0
	b.mu.Unlock()
	b.dispatch(mediaIDs)
}

func (b *messageMediaCommitBatcher) flushGeneration(generation uint64) {
	if b == nil {
		return
	}
	b.mu.Lock()
	if b.generation != generation {
		b.mu.Unlock()
		return
	}
	if len(b.pending) == 0 {
		b.timer = nil
		b.firstSeen = time.Time{}
		b.generation = 0
		b.mu.Unlock()
		return
	}
	mediaIDs := make([]string, 0, len(b.pending))
	for mediaID := range b.pending {
		mediaIDs = append(mediaIDs, mediaID)
	}
	b.pending = make(map[string]struct{})
	b.timer = nil
	b.firstSeen = time.Time{}
	b.generation = 0
	b.mu.Unlock()
	b.dispatch(mediaIDs)
}

func (b *messageMediaCommitBatcher) pendingCount() int {
	if b == nil {
		return 0
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	return len(b.pending)
}

func (h *MessageHandler) enqueueMessageMediaCommit(mediaIDs []string) {
	if h == nil || h.messageMediaCommitBatcher == nil || len(mediaIDs) == 0 {
		return
	}
	h.messageMediaCommitBatcher.enqueue(mediaIDs)
}
