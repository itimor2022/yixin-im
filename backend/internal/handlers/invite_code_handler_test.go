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
//   - 当前配置的合法长度或旧版固定 10 位
//   - 首位不能是 '0'
//   - 全部字符必须是 0-9 的数字
// 通过 length=10（默认）覆盖历史上所有邀请码；额外 case 验证「配置为 6 位」和「配置为 8 位」时
// 旧 10 位邀请码仍然合法，保证历史用户/推荐关系不失效。
func TestIsValidUserInviteCode(t *testing.T) {
	cases := []struct {
		name   string
		code   string
		length int
		want   bool
	}{
		// length=10：等价于旧版的固定 10 位校验。
		{"valid 10 digits starting with 1", "1234567890", 10, true},
		{"valid 10 digits starting with 9", "9876543210", 10, true},
		{"too short", "123456789", 10, false},
		{"too long", "12345678901", 10, false},
		{"empty", "", 10, false},
		{"starts with 0", "0123456789", 10, false},
		{"contains letter", "123456789a", 10, false},
		{"all digits but 8 chars (hex)", "abcd1234", 10, false},
		// length=6：合法长度为 6，旧 10 位仍兼容。
		{"valid 6 digits length=6", "123456", 6, true},
		{"legacy 10 digits length=6 still valid", "1234567890", 6, true},
		{"7 digits length=6 should reject", "1234567", 6, false},
		{"starts with 0 length=6", "012345", 6, false},
		// length=8：合法长度为 8，旧 10 位仍兼容。
		{"valid 8 digits length=8", "12345678", 8, true},
		{"legacy 10 digits length=8 still valid", "1234567890", 8, true},
		// 缺省/越界 length：自动夹到默认 6。
		{"zero length clamps to default 6", "123456", 0, true},
		{"negative length clamps to default 6", "123456", -3, true},
		{"too-large length clamps to max 10", "1234567890", 99, true},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := models.IsValidUserInviteCode(c.code, c.length); got != c.want {
				t.Fatalf("IsValidUserInviteCode(%q, %d) = %v, want %v", c.code, c.length, got, c.want)
			}
		})
	}
}

// TestGenerateUserInviteCode 验证生成的邀请码满足「合法长度 + 首位 1-9 + 全数字」，
// 并覆盖 length 参数的夹紧边界（越界时回退到默认值/合法范围）。
func TestGenerateUserInviteCode(t *testing.T) {
	for _, length := range []int{6, 7, 8, 9, 10} {
		t.Run("length="+itoaForTest(length), func(t *testing.T) {
			code, err := models.GenerateUserInviteCode(length)
			if err != nil {
				t.Fatalf("GenerateUserInviteCode(%d) unexpected error: %v", length, err)
			}
			if !models.IsValidUserInviteCode(code, length) {
				t.Fatalf("generated code %q failed IsValidUserInviteCode(_, %d)", code, length)
			}
		})
	}

	// 越界值：负数和零应当夹紧到默认 6 位。
	t.Run("clamp zero/negative to default", func(t *testing.T) {
		code, err := models.GenerateUserInviteCode(0)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !models.IsValidUserInviteCode(code, models.UserInviteCodeDefaultLength) {
			t.Fatalf("clamped code %q failed validation for default length", code)
		}
	})

	// 越界值：> max 应当夹紧到 max=10。
	t.Run("clamp over-max to max length", func(t *testing.T) {
		code, err := models.GenerateUserInviteCode(99)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !models.IsValidUserInviteCode(code, models.UserInviteCodeMaxLength) {
			t.Fatalf("clamped code %q failed validation for max length", code)
		}
	})
}

// itoaForTest 仅为测试用的局部小工具，避免引入 strconv 导致测试依赖膨胀。
func itoaForTest(n int) string {
	if n == 0 {
		return "0"
	}
	negative := false
	if n < 0 {
		negative = true
		n = -n
	}
	var buf [20]byte
	i := len(buf)
	for n > 0 {
		i--
		buf[i] = byte('0' + n%10)
		n /= 10
	}
	if negative {
		i--
		buf[i] = '-'
	}
	return string(buf[i:])
}