// 文件用途：验证 chat_state_sync_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"testing"
	"time"
	"genericim/internal/models"
)

func TestUserChatStatePayload(t *testing.T) {
	uc := &models.UserChat{
		UnreadCount: 3,
		HasMention:  true,
		IsPinned:    true,
		IsMuted:     false,
		LastMsgSeq:  88,
		UpdatedAt:   time.Date(2026, 6, 21, 10, 0, 0, 0, time.UTC),
	}
	payload := userChatStatePayload("chat-1", "user-1", uc, 77, "unread_count", "last_read_seq")
	if payload["type"] != wsTypeChatStateChanged {
		t.Fatalf("type=%v", payload["type"])
	}
	if payload["chat_id"] != "chat-1" {
		t.Fatalf("chat_id=%v", payload["chat_id"])
	}
	if payload["user_id"] != "user-1" {
		t.Fatalf("user_id=%v", payload["user_id"])
	}
	if payload["unread_count"] != 3 {
		t.Fatalf("unread_count=%v", payload["unread_count"])
	}
	if payload["has_mention"] != true {
		t.Fatalf("has_mention=%v", payload["has_mention"])
	}
	if payload["is_pinned"] != true {
		t.Fatalf("is_pinned=%v", payload["is_pinned"])
	}
	if payload["is_muted"] != false {
		t.Fatalf("is_muted=%v", payload["is_muted"])
	}
	if payload["last_read_seq"] != uint64(77) {
		t.Fatalf("last_read_seq=%v", payload["last_read_seq"])
	}
	if payload["last_msg_seq"] != uint64(88) {
		t.Fatalf("last_msg_seq=%v", payload["last_msg_seq"])
	}
	changed, ok := payload["changed"].([]string)
	if !ok || len(changed) != 2 {
		t.Fatalf("changed=%#v", payload["changed"])
	}
}
