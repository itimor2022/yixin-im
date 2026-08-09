// 文件用途：验证消息序号在并发 INCR 与 Mongo 校准并行时不会回退或重复。
// 核心逻辑：本机 Redis 可用时交错执行分配与旧值校准，并检查所有分配值唯一。

package cache

import (
	"context"
	"fmt"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
)

func TestSetCurrentMsgSeqNeverMovesConcurrentAllocatorBackward(t *testing.T) {
	address := os.Getenv("QA_REDIS_ADDR")
	if address == "" {
		address = "127.0.0.1:6379"
	}
	client := redis.NewClient(&redis.Options{Addr: address})
	t.Cleanup(func() {
		_ = client.Close()
	})

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := client.Ping(ctx).Err(); err != nil {
		t.Skipf("Redis integration test skipped: %v", err)
	}

	chatID := fmt.Sprintf("test-monotonic-%d", time.Now().UnixNano())
	key := KeyMsgSeq + chatID
	t.Cleanup(func() {
		_ = client.Del(context.Background(), key).Err()
	})
	cache := NewCache(client)
	if err := cache.SetCurrentMsgSeq(ctx, chatID, 1000); err != nil {
		t.Fatal(err)
	}

	const allocations = 500
	values := make(chan uint64, allocations)
	errors := make(chan error, allocations*2)
	var wait sync.WaitGroup
	for index := 0; index < allocations; index++ {
		wait.Add(2)
		go func() {
			defer wait.Done()
			value, err := cache.GetNextMsgSeq(ctx, chatID)
			if err != nil {
				errors <- err
				return
			}
			values <- value
		}()
		go func() {
			defer wait.Done()
			if err := cache.SetCurrentMsgSeq(ctx, chatID, 1000); err != nil {
				errors <- err
			}
		}()
	}
	wait.Wait()
	close(values)
	close(errors)
	for err := range errors {
		t.Fatal(err)
	}

	seen := make(map[uint64]struct{}, allocations)
	for value := range values {
		if _, exists := seen[value]; exists {
			t.Fatalf("duplicate allocated seq=%d", value)
		}
		seen[value] = struct{}{}
	}
	if len(seen) != allocations {
		t.Fatalf("allocated values=%d, want %d", len(seen), allocations)
	}
	current, err := cache.GetCurrentMsgSeq(ctx, chatID)
	if err != nil {
		t.Fatal(err)
	}
	if current != 1000+allocations {
		t.Fatalf("current seq=%d, want %d", current, 1000+allocations)
	}
}
