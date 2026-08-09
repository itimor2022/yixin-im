// 文件用途：验证群聊列表缓存失效会按会话合并，避免消息数乘以成员数的 Redis 版本更新。
// 核心逻辑：同一会话并发入队只派发一次，不同会话相互独立，窗口结束后允许新批次。

package handlers

import (
	"sync"
	"testing"
	"time"
)

func TestChatListCacheInvalidationBatcherCoalescesConcurrentBurst(t *testing.T) {
	dispatched := make(chan uint64, 4)
	batcher := newChatListCacheInvalidationBatcher(time.Hour, func(chatID uint64) {
		dispatched <- chatID
	})

	var wg sync.WaitGroup
	for i := 0; i < 500; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			batcher.enqueue(42)
		}()
	}
	wg.Wait()

	if got := batcher.pendingCount(); got != 1 {
		t.Fatalf("pending chats=%d, want 1", got)
	}
	batcher.flush(42)
	if got := <-dispatched; got != 42 {
		t.Fatalf("dispatched chat=%d, want 42", got)
	}
	select {
	case extra := <-dispatched:
		t.Fatalf("unexpected second dispatch for chat %d", extra)
	default:
	}
}

func TestChatListCacheInvalidationBatcherStartsNewWindow(t *testing.T) {
	dispatched := make(chan uint64, 2)
	batcher := newChatListCacheInvalidationBatcher(time.Hour, func(chatID uint64) {
		dispatched <- chatID
	})

	batcher.enqueue(7)
	batcher.flush(7)
	batcher.enqueue(7)
	batcher.flush(7)

	if first, second := <-dispatched, <-dispatched; first != 7 || second != 7 {
		t.Fatalf("dispatch order=%d,%d, want 7,7", first, second)
	}
}
