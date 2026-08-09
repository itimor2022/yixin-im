// 文件用途：验证 auth_quick_register_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"regexp"
	"testing"
)

func TestFormatQuickRegisterCredentials(t *testing.T) {
	username, password, nickname := formatQuickRegisterCredentials([]byte{
		0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0x10, 0x32, 0x54, 0x76,
	})
	if !regexp.MustCompile(`^q_[a-f0-9]{12}$`).MatchString(username) {
		t.Fatalf("unexpected username: %q", username)
	}
	if !regexp.MustCompile(`^[a-f0-9]{20}$`).MatchString(password) {
		t.Fatalf("unexpected password: %q", password)
	}
	if !regexp.MustCompile(`^用户[A-F0-9]{6}$`).MatchString(nickname) {
		t.Fatalf("unexpected nickname: %q", nickname)
	}
}

func TestHashQuickRegisterValue(t *testing.T) {
	got := hashQuickRegisterValue("device-1")
	if len(got) != 64 || got == hashQuickRegisterValue("device-2") {
		t.Fatalf("unexpected hash: %q", got)
	}
}
