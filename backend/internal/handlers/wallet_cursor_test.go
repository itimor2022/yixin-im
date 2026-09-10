// 文件用途：覆盖钱包流水游标（客户端 + 后台）的 encode/decode 单测，确保 (created_at, id) 元组可逆。
// 核心逻辑：单测只验证纯函数往返与非法输入，不依赖数据库，便于在 CI 中反复运行。

package handlers

import (
	"encoding/base64"
	"testing"
	"time"
	"genericim/internal/models"
)

// 钱包 Transaction 模型字段是平铺的（ID/CreatedAt），不内嵌 gorm.Model。
func mustEncode(t *testing.T, tx models.Transaction, encode func(models.Transaction) string) string {
	t.Helper()
	got := encode(tx)
	if got == "" {
		t.Fatal("expected non-empty cursor")
	}
	return got
}

func TestTransactionCursorRoundTrip(t *testing.T) {
	t.Parallel()
	now := time.Date(2024, 5, 1, 10, 30, 45, 123456789, time.UTC)
	tx := models.Transaction{ID: 9876543210, CreatedAt: now}
	cursor := mustEncode(t, tx, EncodeTransactionCursor)
	gotTime, gotID, err := DecodeTransactionCursor(cursor)
	if err != nil {
		t.Fatalf("decode cursor: %v", err)
	}
	if gotID != tx.ID {
		t.Fatalf("id mismatch: got %d want %d", gotID, tx.ID)
	}
	if !gotTime.Equal(now) {
		t.Fatalf("time mismatch: got %s want %s", gotTime.Format(time.RFC3339Nano), now.Format(time.RFC3339Nano))
	}
}

func TestAdminTransactionCursorRoundTrip(t *testing.T) {
	t.Parallel()
	now := time.Date(2024, 6, 1, 12, 0, 0, 0, time.UTC)
	tx := models.Transaction{ID: 42, CreatedAt: now}
	cursor := mustEncode(t, tx, EncodeAdminTransactionCursor)
	gotTime, gotID, err := DecodeAdminTransactionCursor(cursor)
	if err != nil {
		t.Fatalf("decode cursor: %v", err)
	}
	if gotID != tx.ID {
		t.Fatalf("id mismatch: got %d want %d", gotID, tx.ID)
	}
	if !gotTime.Equal(now) {
		t.Fatalf("time mismatch: got %s want %s", gotTime.Format(time.RFC3339Nano), now.Format(time.RFC3339Nano))
	}
}

// encodeRaw 直接把字符串 base64 化，便于构造"非法 JSON"或"缺字段"的游标数据。
func encodeRaw(s string) string {
	return base64.RawURLEncoding.EncodeToString([]byte(s))
}

func TestTransactionCursorInvalid(t *testing.T) {
	t.Parallel()
	cases := map[string]string{
		"empty":            "",
		"bad base64":       "!!!not-base64!!!",
		"not json":         encodeRaw("not-json"),
		"missing time":     encodeRaw(`{"i":1}`),
		"id zero":          encodeRaw(`{"t":"2024-01-01T00:00:00Z","i":0}`),
		"bad time format":  encodeRaw(`{"t":"not-a-time","i":1}`),
	}
	for name, raw := range cases {
		t.Run(name, func(t *testing.T) {
			if _, _, err := DecodeTransactionCursor(raw); err == nil {
				t.Fatalf("expected error for cursor %q", raw)
			}
		})
	}
}

func TestAdminTransactionCursorInvalid(t *testing.T) {
	t.Parallel()
	cases := map[string]string{
		"bad base64":      "!!!not-base64!!!",
		"not json":        encodeRaw("not-json"),
		"missing time":    encodeRaw(`{"i":1}`),
		"id zero":         encodeRaw(`{"t":"2024-01-01T00:00:00Z","i":0}`),
		"bad time format": encodeRaw(`{"t":"not-a-time","i":1}`),
	}
	for name, raw := range cases {
		t.Run(name, func(t *testing.T) {
			if _, _, err := DecodeAdminTransactionCursor(raw); err == nil {
				t.Fatalf("expected error for cursor %q", raw)
			}
		})
	}
}
