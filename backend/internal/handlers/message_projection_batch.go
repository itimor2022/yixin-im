// 文件用途：合并同一会话短窗口内的 UserChat 派生投影，避免每条群消息更新全体成员两次。
// 核心逻辑：250ms 内保留最高 seq 作为会话预览，按发送者计数用单条 CASE SQL 累计未读，并合并 @ 状态。

package handlers

import (
	"sync"
	"time"

	"genericim/internal/models"
)

type messageProjectionBatch struct {
	chat                models.Chat
	latestMessage       models.Message
	sender              models.User
	senderName          string
	memberUserIDs       []uint64
	lastMsgText         string
	lastMsgMediaURL     string
	messageCount        int64
	senderCounts        map[uint64]int64
	mentionAllSenderIDs map[uint64]struct{}
	mentionUUIDs        map[string]struct{}
}

type messageProjectionBatcher struct {
	mu          sync.Mutex
	delay       time.Duration
	dispatch    func(messageProjectionBatch)
	pending     map[uint64]messageProjectionBatch
	timers      map[uint64]*time.Timer
	firstSeen   map[uint64]time.Time
	generations map[uint64]uint64
}

func newMessageProjectionBatcher(delay time.Duration, dispatch func(messageProjectionBatch)) *messageProjectionBatcher {
	if delay <= 0 {
		delay = 250 * time.Millisecond
	}
	return &messageProjectionBatcher{
		delay:       delay,
		dispatch:    dispatch,
		pending:     make(map[uint64]messageProjectionBatch),
		timers:      make(map[uint64]*time.Timer),
		firstSeen:   make(map[uint64]time.Time),
		generations: make(map[uint64]uint64),
	}
}

func (b *messageProjectionBatcher) scheduleLocked(chatID uint64) {
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

func newMessageProjectionBatch(task messageProjectionTask) messageProjectionBatch {
	batch := messageProjectionBatch{
		chat:                task.chat,
		latestMessage:       task.message,
		sender:              task.sender,
		senderName:          task.senderName,
		memberUserIDs:       uniqueUint64s(task.memberUserIDs),
		lastMsgText:         task.lastMsgText,
		lastMsgMediaURL:     task.lastMsgMediaURL,
		messageCount:        1,
		senderCounts:        map[uint64]int64{task.sender.ID: 1},
		mentionAllSenderIDs: make(map[uint64]struct{}),
		mentionUUIDs:        make(map[string]struct{}),
	}
	if task.mentionAll {
		batch.mentionAllSenderIDs[task.sender.ID] = struct{}{}
	}
	for _, userUUID := range task.mentionUUIDs {
		if userUUID != "" {
			batch.mentionUUIDs[userUUID] = struct{}{}
		}
	}
	return batch
}

func mergeMessageProjectionBatch(batch messageProjectionBatch, task messageProjectionTask) messageProjectionBatch {
	batch.messageCount++
	batch.senderCounts[task.sender.ID]++
	if task.mentionAll {
		batch.mentionAllSenderIDs[task.sender.ID] = struct{}{}
	}
	for _, userUUID := range task.mentionUUIDs {
		if userUUID != "" {
			batch.mentionUUIDs[userUUID] = struct{}{}
		}
	}
	if len(task.memberUserIDs) > 0 {
		batch.memberUserIDs = uniqueUint64s(append(batch.memberUserIDs, task.memberUserIDs...))
	}
	if task.message.Seq >= batch.latestMessage.Seq {
		batch.chat = task.chat
		batch.latestMessage = task.message
		batch.sender = task.sender
		batch.senderName = task.senderName
		batch.lastMsgText = task.lastMsgText
		batch.lastMsgMediaURL = task.lastMsgMediaURL
	}
	return batch
}

func (b *messageProjectionBatcher) enqueue(task messageProjectionTask) {
	if b == nil || b.dispatch == nil || task.chat.ID == 0 || task.message.MsgID == "" {
		return
	}
	b.mu.Lock()
	current, exists := b.pending[task.chat.ID]
	if !exists {
		b.pending[task.chat.ID] = newMessageProjectionBatch(task)
		b.firstSeen[task.chat.ID] = time.Now()
		b.scheduleLocked(task.chat.ID)
		b.mu.Unlock()
		return
	}
	b.pending[task.chat.ID] = mergeMessageProjectionBatch(current, task)
	b.scheduleLocked(task.chat.ID)
	b.mu.Unlock()
}

func (b *messageProjectionBatcher) flush(chatID uint64) {
	if b == nil {
		return
	}
	b.mu.Lock()
	batch, exists := b.pending[chatID]
	if timer := b.timers[chatID]; timer != nil {
		timer.Stop()
	}
	delete(b.pending, chatID)
	delete(b.timers, chatID)
	delete(b.firstSeen, chatID)
	delete(b.generations, chatID)
	b.mu.Unlock()
	if exists && b.dispatch != nil {
		b.dispatch(batch)
	}
}

func (b *messageProjectionBatcher) flushGeneration(chatID uint64, generation uint64) {
	if b == nil {
		return
	}
	b.mu.Lock()
	if b.generations[chatID] != generation {
		b.mu.Unlock()
		return
	}
	batch, exists := b.pending[chatID]
	delete(b.pending, chatID)
	delete(b.timers, chatID)
	delete(b.firstSeen, chatID)
	delete(b.generations, chatID)
	b.mu.Unlock()
	if exists && b.dispatch != nil {
		b.dispatch(batch)
	}
}

func (b *messageProjectionBatcher) pendingCount() int {
	if b == nil {
		return 0
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	return len(b.pending)
}
