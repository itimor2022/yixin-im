// 文件用途：验证 chat_handler_clear_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"testing"
	"time"
)

func TestChatHistoryClearUpdatesRemovesCompletePreview(t *testing.T) {
	clearedAt := time.Date(2026, 7, 16, 20, 0, 0, 0, time.UTC)
	updates := chatHistoryClearUpdates(clearedAt)
	if updates["cleared_at"] != clearedAt {
		t.Fatalf("cleared_at=%v, want %v", updates["cleared_at"], clearedAt)
	}
	for _, key := range []string{"last_msg_id", "last_msg_seq", "unread_count"} {
		if value, ok := updates[key].(uint64); ok {
			if value != 0 {
				t.Fatalf("%s=%v, want 0", key, value)
			}
			continue
		}
		if value, ok := updates[key].(int); !ok || value != 0 {
			t.Fatalf("%s=%v, want numeric zero", key, updates[key])
		}
	}
	if updates["last_msg_time"] != nil {
		t.Fatalf("last_msg_time=%v, want nil", updates["last_msg_time"])
	}
	if updates["has_mention"] != false {
		t.Fatalf("has_mention=%v, want false", updates["has_mention"])
	}
	for _, key := range []string{
		"last_msg_text",
		"last_msg_sender",
		"last_msg_media_url",
	} {
		if updates[key] != "" {
			t.Fatalf("%s=%v, want empty string", key, updates[key])
		}
	}
	if updates["last_msg_type"] != 0 {
		t.Fatalf("last_msg_type=%v, want 0", updates["last_msg_type"])
	}
}
