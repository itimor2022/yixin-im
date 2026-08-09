// 文件用途：验证 message_storage_policy_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"testing"
	"time"
)

func TestMessageCollectionNamesCoverConfiguredRetention(t *testing.T) {
	now := time.Date(2026, time.July, 14, 12, 0, 0, 0, time.UTC)
	names := messageCollectionNames("chat-1", now, 18)
	if len(names) != 19 {
		t.Fatalf("len(names)=%d, want 19 including legacy collection", len(names))
	}
	if names[0] != "messages_202607" || names[17] != "messages_202502" {
		t.Fatalf("unexpected retention boundaries: first=%s last=%s", names[0], names[17])
	}
	if names[18] != "messages" {
		t.Fatalf("legacy collection missing: %v", names)
	}
}

func TestMessageCollectionRetentionFilter(t *testing.T) {
	now := time.Date(2026, time.July, 14, 12, 0, 0, 0, time.UTC)
	for _, name := range []string{"messages", "messages_202607", "messages_202502"} {
		if !isMessageCollectionInsideRetention(name, now, 18) {
			t.Fatalf("expected %s inside retention", name)
		}
	}
	for _, name := range []string{"messages_202501", "messages_202608", "message_202607", "messages_bad"} {
		if isMessageCollectionInsideRetention(name, now, 18) {
			t.Fatalf("expected %s outside retention", name)
		}
	}
}

func TestMessageIdempotencyExpiryCoversRetention(t *testing.T) {
	now := time.Date(2026, time.January, 31, 12, 0, 0, 0, time.UTC)
	got := messageIdempotencyExpiry(now, 18)
	want := now.AddDate(0, 18, 0)
	if !got.Equal(want) {
		t.Fatalf("expiry=%s, want %s", got, want)
	}
}

func TestRecoveryCapabilitiesNeverPromiseShorterIdempotency(t *testing.T) {
	service := &MessageService{retentionMonths: 48, idempotencyMonths: 12}
	capabilities := service.RecoveryCapabilities()
	if capabilities.RetentionMonths != 48 || capabilities.IdempotencyMonths != 48 {
		t.Fatalf("unexpected capabilities: %+v", capabilities)
	}
	if capabilities.E2EERecoveryMode != "trusted_device_rewrap" {
		t.Fatalf("unexpected E2EE recovery mode: %s", capabilities.E2EERecoveryMode)
	}
}
