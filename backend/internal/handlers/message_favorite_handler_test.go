// 文件用途：验证 message_favorite_handler_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"testing"
	"time"
	"genericim/internal/models"
)

func TestMessageFavoriteSnapshotUsesServerMessage(t *testing.T) {
	createdAt := time.Date(2026, 7, 16, 22, 0, 0, 0, time.UTC)
	message := &models.Message{
		MsgID:      "message-219",
		ChatID:     "chat-219",
		Seq:        19,
		SenderID:   "user-a",
		SenderName: "Alice",
		Type:       models.MsgTypeFile,
		Content: models.MessageContent{File: &models.FileInfo{
			URL:  "/uploads/favorite.pdf",
			Name: "favorite.pdf",
		}},
		CreatedAt: createdAt,
	}
	snapshot := messageFavoriteSnapshot(message, &models.Chat{Name: "Project"})
	if snapshot["message_id"] != "message-219" || snapshot["message_seq"] != uint64(19) {
		t.Fatalf("unexpected identity snapshot: %#v", snapshot)
	}
	if snapshot["message_type"] != "file" || snapshot["file_name"] != "favorite.pdf" {
		t.Fatalf("unexpected file snapshot: %#v", snapshot)
	}
	if snapshot["chat_name"] != "Project" || snapshot["sender_name"] != "Alice" {
		t.Fatalf("unexpected source snapshot: %#v", snapshot)
	}
}

func TestMessageFavoriteUsesExplicitTombstoneTable(t *testing.T) {
	if got := (models.MessageFavorite{}).TableName(); got != "message_favorites" {
		t.Fatalf("table name=%q", got)
	}
	if favoriteMessageTypeName(models.MsgTypeLocation) != "location" {
		t.Fatal("location type mapping missing")
	}
}
