// 文件用途：验证高并发图片消息的媒体提交会合并并去重。
// 核心逻辑：500 个并发入队在一个窗口内只派发一次，每个 media_id 只出现一次。

package handlers

import (
	"fmt"
	"sync"
	"testing"
	"time"
)

func TestMessageMediaCommitBatcherCoalescesConcurrentImages(t *testing.T) {
	dispatched := make(chan []string, 2)
	batcher := newMessageMediaCommitBatcher(time.Hour, func(mediaIDs []string) {
		dispatched <- mediaIDs
	})

	var wg sync.WaitGroup
	for index := 0; index < 500; index++ {
		index := index
		wg.Add(1)
		go func() {
			defer wg.Done()
			mediaID := fmt.Sprintf("media-%03d", index)
			batcher.enqueue([]string{mediaID, mediaID})
		}()
	}
	wg.Wait()

	if got := batcher.pendingCount(); got != 500 {
		t.Fatalf("pending media=%d, want 500", got)
	}
	batcher.flush()
	mediaIDs := <-dispatched
	if len(mediaIDs) != 500 {
		t.Fatalf("dispatched media=%d, want 500", len(mediaIDs))
	}
	select {
	case extra := <-dispatched:
		t.Fatalf("unexpected second dispatch with %d media", len(extra))
	default:
	}
}

func TestMessageMediaCommitBatcherStartsNewWindow(t *testing.T) {
	dispatched := make(chan []string, 2)
	batcher := newMessageMediaCommitBatcher(time.Hour, func(mediaIDs []string) {
		dispatched <- mediaIDs
	})
	batcher.enqueue([]string{"media-1"})
	batcher.flush()
	batcher.enqueue([]string{"media-2"})
	batcher.flush()

	first, second := <-dispatched, <-dispatched
	if len(first) != 1 || first[0] != "media-1" || len(second) != 1 || second[0] != "media-2" {
		t.Fatalf("unexpected dispatches: %v then %v", first, second)
	}
}
