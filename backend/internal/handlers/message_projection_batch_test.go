// 文件用途：验证 500 条并发群消息会合并为少量 UserChat 投影，并保持序号、未读和 @ 语义。
// 核心逻辑：批次保留最高 seq，累计每个发送者的消息数，并合并成员与提及集合。

package handlers

import (
	"fmt"
	"sync"
	"testing"
	"time"

	"genericim/internal/models"
)

func TestMessageProjectionBatcherCoalescesConcurrentBurst(t *testing.T) {
	dispatched := make(chan messageProjectionBatch, 2)
	batcher := newMessageProjectionBatcher(time.Hour, func(batch messageProjectionBatch) {
		dispatched <- batch
	})

	var wg sync.WaitGroup
	for seq := uint64(1); seq <= 500; seq++ {
		seq := seq
		wg.Add(1)
		go func() {
			defer wg.Done()
			senderID := seq%10 + 1
			batcher.enqueue(messageProjectionTask{
				chat: models.Chat{ID: 42, UUID: "chat-42", Type: 2},
				message: models.Message{
					MsgID: fmt.Sprintf("message-%03d", seq),
					Seq:   seq,
				},
				sender:          models.User{ID: senderID},
				senderName:      fmt.Sprintf("sender-%d", senderID),
				memberUserIDs:   []uint64{senderID, senderID + 100},
				lastMsgText:     fmt.Sprintf("content-%03d", seq),
				lastMsgMediaURL: fmt.Sprintf("media-%03d", seq),
				mentionAll:      seq == 250,
				mentionUUIDs:    []string{fmt.Sprintf("user-%03d", seq)},
			})
		}()
	}
	wg.Wait()

	if got := batcher.pendingCount(); got != 1 {
		t.Fatalf("pending chats=%d, want 1", got)
	}
	batcher.flush(42)
	batch := <-dispatched
	if batch.messageCount != 500 {
		t.Fatalf("message count=%d, want 500", batch.messageCount)
	}
	if batch.latestMessage.Seq != 500 || batch.latestMessage.MsgID != "message-500" {
		t.Fatalf("latest message=%d/%s, want 500/message-500", batch.latestMessage.Seq, batch.latestMessage.MsgID)
	}
	if batch.lastMsgText != "content-500" || batch.lastMsgMediaURL != "media-500" {
		t.Fatalf("latest preview=%s/%s", batch.lastMsgText, batch.lastMsgMediaURL)
	}
	if len(batch.senderCounts) != 10 {
		t.Fatalf("sender count entries=%d, want 10", len(batch.senderCounts))
	}
	var counted int64
	for _, count := range batch.senderCounts {
		counted += count
	}
	if counted != 500 {
		t.Fatalf("sender message total=%d, want 500", counted)
	}
	if len(batch.mentionAllSenderIDs) != 1 {
		t.Fatalf("mention-all senders=%d, want 1", len(batch.mentionAllSenderIDs))
	}
	if len(batch.mentionUUIDs) != 500 {
		t.Fatalf("direct mentions=%d, want 500", len(batch.mentionUUIDs))
	}
	if len(batch.memberUserIDs) != 20 {
		t.Fatalf("unique member ids=%d, want 20", len(batch.memberUserIDs))
	}
}

func TestMessageProjectionBatcherStartsNewWindow(t *testing.T) {
	dispatched := make(chan messageProjectionBatch, 2)
	batcher := newMessageProjectionBatcher(time.Hour, func(batch messageProjectionBatch) {
		dispatched <- batch
	})
	task := func(seq uint64) messageProjectionTask {
		return messageProjectionTask{
			chat:    models.Chat{ID: 7},
			message: models.Message{MsgID: fmt.Sprintf("m%d", seq), Seq: seq},
			sender:  models.User{ID: 1},
		}
	}
	batcher.enqueue(task(1))
	batcher.flush(7)
	batcher.enqueue(task(2))
	batcher.flush(7)

	if first, second := <-dispatched, <-dispatched; first.latestMessage.Seq != 1 || second.latestMessage.Seq != 2 {
		t.Fatalf("dispatch order=%d,%d, want 1,2", first.latestMessage.Seq, second.latestMessage.Seq)
	}
}
