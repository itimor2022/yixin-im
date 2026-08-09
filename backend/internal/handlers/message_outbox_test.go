// 文件用途：验证消息 Outbox 的幂等键、退避、载荷合并和最高序号选择。
// 核心逻辑：使用纯单元测试锁定不依赖数据库的恢复语义，数据库重启恢复由 Docker 验收脚本覆盖。

package handlers

import (
	"encoding/json"
	"testing"
	"time"

	"genericim/internal/models"
)

func TestMessageOutboxEventKeyIsStableAndTypeScoped(t *testing.T) {
	projection := messageOutboxEventKey(" chat-1 ", " msg-1 ", models.MessageOutboxTypeProjection)
	if projection != "message:chat-1:msg-1:projection" {
		t.Fatalf("unexpected projection key: %s", projection)
	}
	push := messageOutboxEventKey("chat-1", "msg-1", models.MessageOutboxTypePush)
	if projection == push {
		t.Fatal("different event types must not share an event key")
	}
}

func TestMessageOutboxRetryDelayIsBounded(t *testing.T) {
	cases := []struct {
		attempts int
		want     time.Duration
	}{
		{attempts: 0, want: time.Second},
		{attempts: 1, want: time.Second},
		{attempts: 2, want: 2 * time.Second},
		{attempts: 4, want: 8 * time.Second},
		{attempts: 8, want: time.Minute},
		{attempts: 20, want: time.Minute},
	}
	for _, tc := range cases {
		if got := messageOutboxRetryDelay(tc.attempts); got != tc.want {
			t.Fatalf("attempts=%d got=%s want=%s", tc.attempts, got, tc.want)
		}
	}
}

func TestProjectionBatchFromOutboxEventsCountsEveryMessageAndKeepsHighestSeq(t *testing.T) {
	createdAt := time.Date(2026, 7, 29, 20, 0, 0, 0, time.UTC)
	payloads := []messageOutboxPayload{
		{
			ChatID: 9, ChatUUID: "chat-9", ChatType: 2,
			MessageID: "msg-10", MessageSeq: 10, MessageType: 1, MessageCreatedAt: createdAt,
			SenderUserID: 101, SenderUUID: "user-101", SenderName: "甲",
			LastMsgText: "first", MentionAll: true,
		},
		{
			ChatID: 9, ChatUUID: "chat-9", ChatType: 2,
			MessageID: "msg-12", MessageSeq: 12, MessageType: 2, MessageCreatedAt: createdAt.Add(time.Second),
			SenderUserID: 102, SenderUUID: "user-102", SenderName: "乙",
			LastMsgText: "latest", MentionUUIDs: []string{"user-103"},
		},
		{
			ChatID: 9, ChatUUID: "chat-9", ChatType: 2,
			MessageID: "msg-11", MessageSeq: 11, MessageType: 1, MessageCreatedAt: createdAt.Add(500 * time.Millisecond),
			SenderUserID: 101, SenderUUID: "user-101", SenderName: "甲",
			LastMsgText: "middle",
		},
	}
	events := make([]models.MessageOutboxEvent, 0, len(payloads))
	for i := range payloads {
		encoded, err := json.Marshal(payloads[i])
		if err != nil {
			t.Fatal(err)
		}
		events = append(events, models.MessageOutboxEvent{
			ID:      uint64(i + 1),
			ChatID:  payloads[i].ChatID,
			Payload: encoded,
		})
	}

	batch, err := projectionBatchFromEvents(events)
	if err != nil {
		t.Fatal(err)
	}
	if batch.messageCount != 3 {
		t.Fatalf("message count got=%d want=3", batch.messageCount)
	}
	if batch.latestMessage.Seq != 12 || batch.lastMsgText != "latest" {
		t.Fatalf("latest projection got seq=%d text=%q", batch.latestMessage.Seq, batch.lastMsgText)
	}
	if batch.senderCounts[101] != 2 || batch.senderCounts[102] != 1 {
		t.Fatalf("unexpected sender counts: %#v", batch.senderCounts)
	}
	if _, ok := batch.mentionAllSenderIDs[101]; !ok {
		t.Fatal("mention-all sender was not retained")
	}
	if _, ok := batch.mentionUUIDs["user-103"]; !ok {
		t.Fatal("direct mention was not retained")
	}
}

func TestMergeOutboxPushTaskKeepsHighestSeqAndUnionsMentions(t *testing.T) {
	current := messagePushTask{
		chatID: 1, messageID: "msg-1", messageSeq: 1,
		mentionedUUIDs: map[string]struct{}{"user-a": {}},
	}
	next := messagePushTask{
		chatID: 1, messageID: "msg-2", messageSeq: 2, mentionsAll: true,
		mentionedUUIDs: map[string]struct{}{"user-b": {}},
	}
	got := mergeOutboxPushTask(current, next)
	if got.messageID != "msg-2" || got.messageSeq != 2 {
		t.Fatalf("highest sequence was not retained: id=%s seq=%d", got.messageID, got.messageSeq)
	}
	if !got.mentionsAll {
		t.Fatal("mention-all flag was not retained")
	}
	for _, userUUID := range []string{"user-a", "user-b"} {
		if _, ok := got.mentionedUUIDs[userUUID]; !ok {
			t.Fatalf("missing merged mention %s", userUUID)
		}
	}
}
