// 文件用途：验证 message_forward_bundle_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"testing"
	"time"
	"genericim/internal/models"
)

func TestBuildForwardBundleSnapshotUsesAuthoritativeSequence(t *testing.T) {
	now := time.Date(2026, 7, 16, 15, 0, 0, 0, time.UTC)
	bundle := buildForwardBundleSnapshot([]*models.Message{
		{MsgID: "second", Seq: 2, SenderName: "Bob", Type: models.MsgTypeImage, CreatedAt: now.Add(time.Minute)},
		{MsgID: "first", Seq: 1, SenderName: "Alice", Type: models.MsgTypeText, Content: models.MessageContent{Text: "hello"}, CreatedAt: now},
	})
	if len(bundle.Items) != 2 || bundle.Items[0].SourceMessageID != "first" || bundle.Items[1].SourceMessageID != "second" {
		t.Fatalf("snapshot order is not authoritative: %#v", bundle.Items)
	}
	if bundle.Items[0].SenderName != "Alice" || bundle.Items[0].Content.Text != "hello" {
		t.Fatalf("snapshot fields missing: %#v", bundle.Items[0])
	}
}

func TestForwardBundleDepth(t *testing.T) {
	level3 := &models.ForwardBundleInfo{Items: []models.ForwardBundleItem{{
		Content: models.MessageContent{ForwardBundle: &models.ForwardBundleInfo{Items: []models.ForwardBundleItem{{
			Content: models.MessageContent{ForwardBundle: &models.ForwardBundleInfo{}},
		}}}},
	}}}
	if got := forwardBundleDepth(level3); got != 3 {
		t.Fatalf("depth=%d want 3", got)
	}
}
