// 文件用途：验证群消息离线推送合并不会随并发消息数放大任务数量。
// 核心逻辑：并发写入同一群后只派发一次，正文取最高 seq，@ 信息取窗口并集。

package handlers

import (
	"fmt"
	"sync"
	"testing"
	"time"
)

func TestMessagePushBatcherCoalescesConcurrentGroupBurst(t *testing.T) {
	dispatched := make(chan messagePushTask, 2)
	batcher := newMessagePushBatcher(time.Hour, func(task messagePushTask) {
		dispatched <- task
	})

	var wg sync.WaitGroup
	for seq := uint64(1); seq <= 500; seq++ {
		seq := seq
		wg.Add(1)
		go func() {
			defer wg.Done()
			userUUID := fmt.Sprintf("user-%03d", seq)
			batcher.enqueue(messagePushTask{
				chatID:     42,
				chatUUID:   "chat-42",
				messageID:  fmt.Sprintf("message-%03d", seq),
				messageSeq: seq,
				content:    fmt.Sprintf("content-%03d", seq),
				targets: []messagePushTarget{
					{UserID: seq, UUID: userUUID},
				},
				mentionedUUIDs: map[string]struct{}{userUUID: {}},
				mentionsAll:    seq == 250,
			})
		}()
	}
	wg.Wait()

	if got := batcher.pendingCount(); got != 1 {
		t.Fatalf("pending groups=%d, want 1", got)
	}
	batcher.flush(42)

	select {
	case task := <-dispatched:
		if task.messageSeq != 500 || task.messageID != "message-500" {
			t.Fatalf("latest task seq/id=%d/%s, want 500/message-500", task.messageSeq, task.messageID)
		}
		if task.content != "content-500" {
			t.Fatalf("latest content=%q", task.content)
		}
		if len(task.mentionedUUIDs) != 500 {
			t.Fatalf("mentioned users=%d, want 500", len(task.mentionedUUIDs))
		}
		if !task.mentionsAll {
			t.Fatal("mentionsAll should be preserved from the merged window")
		}
	default:
		t.Fatal("expected one dispatched task")
	}

	select {
	case extra := <-dispatched:
		t.Fatalf("unexpected second dispatch: %+v", extra)
	default:
	}
	if got := batcher.pendingCount(); got != 0 {
		t.Fatalf("pending groups after flush=%d, want 0", got)
	}
}

func TestMessagePushBatcherStartsNewWindowAfterFlush(t *testing.T) {
	dispatched := make(chan messagePushTask, 2)
	batcher := newMessagePushBatcher(time.Hour, func(task messagePushTask) {
		dispatched <- task
	})
	batcher.enqueue(messagePushTask{chatID: 7, messageID: "m1", messageSeq: 1})
	batcher.flush(7)
	batcher.enqueue(messagePushTask{chatID: 7, messageID: "m2", messageSeq: 2})
	batcher.flush(7)

	first := <-dispatched
	second := <-dispatched
	if first.messageID != "m1" || second.messageID != "m2" {
		t.Fatalf("dispatch order=%s,%s", first.messageID, second.messageID)
	}
}

func TestMessagePushBatcherIgnoresSupersededTimerGeneration(t *testing.T) {
	dispatched := 0
	batcher := newMessagePushBatcher(time.Hour, func(task messagePushTask) {
		dispatched++
	})
	task := messagePushTask{chatID: 9, messageID: "m1", messageSeq: 1}
	batcher.enqueue(task)
	oldGeneration := batcher.generations[9]
	task.messageID = "m2"
	task.messageSeq = 2
	batcher.enqueue(task)

	batcher.flushGeneration(9, oldGeneration)
	if dispatched != 0 {
		t.Fatalf("superseded timer dispatched batch: %d", dispatched)
	}
	if got := batcher.pendingCount(); got != 1 {
		t.Fatalf("pending batches = %d, want 1", got)
	}
	batcher.flush(9)
	if dispatched != 1 {
		t.Fatalf("manual flush dispatches = %d, want 1", dispatched)
	}
}
