// 文件用途：验证 invite_code_handler.go 中加好友链路辅助函数的边界行为。
// 核心逻辑：覆盖输入防御（自指、零值、nil 用户）。

package handlers

import (
	"testing"
	"time"

	"genericim/internal/models"
)

// TestLinkPairAsContacts_NoOpOnZeroOrSelf 验证 linkPairAsContacts 在以下情形
// 直接返回 nil 而不调用底层 ensureContactRelation：用户 ID 或目标 ID 为 0，
// 或两边是同一个用户。
//
// 由于这些分支在调用底层 SQL 之前就提前 return，传入 nil db 应当是安全的；
// 这点同时验证了短路逻辑没有遗漏。
func TestLinkPairAsContacts_NoOpOnZeroOrSelf(t *testing.T) {
	now := time.Now()
	cases := []struct {
		name      string
		userID    uint64
		contactID uint64
	}{
		{"zero user", 0, 100},
		{"zero contact", 50, 0},
		{"self contact", 50, 50},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if err := linkPairAsContacts(nil, c.userID, c.contactID, now); err != nil {
				t.Fatalf("expected nil error, got %v", err)
			}
		})
	}
}

// TestEnsureDirectRecommenderAndBindAsContacts_NoOpOnNilInputs 验证 nil 入参安全：
// - newUser 为 nil：直接返回 nil
// - newUser.RecommenderID 为 nil：直接返回 nil
func TestEnsureDirectRecommenderAndBindAsContacts_NoOpOnNilInputs(t *testing.T) {
	now := time.Now()
	if err := ensureDirectRecommenderAndBindAsContacts(nil, nil, now); err != nil {
		t.Fatalf("nil newUser should be no-op, got %v", err)
	}
	userWithoutRec := &models.User{ID: 42}
	if err := ensureDirectRecommenderAndBindAsContacts(nil, userWithoutRec, now); err != nil {
		t.Fatalf("nil RecommenderID should be no-op, got %v", err)
	}
}

// TestIsValidUserInviteCode 校验用户个人邀请码的格式规则：
//   - 必须恰好 10 位字符
//   - 首位不能是 '0'
//   - 全部字符必须是 0-9 的数字
func TestIsValidUserInviteCode(t *testing.T) {
	cases := []struct {
		name string
		code string
		want bool
	}{
		{"valid 10 digits starting with 1", "1234567890", true},
		{"valid 10 digits starting with 9", "9876543210", true},
		{"too short", "123456789", false},
		{"too long", "12345678901", false},
		{"empty", "", false},
		{"starts with 0", "0123456789", false},
		{"contains letter", "123456789a", false},
		{"all digits but 8 chars (hex)", "abcd1234", false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := models.IsValidUserInviteCode(c.code); got != c.want {
				t.Fatalf("IsValidUserInviteCode(%q) = %v, want %v", c.code, got, c.want)
			}
		})
	}
}