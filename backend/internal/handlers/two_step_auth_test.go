// 文件用途：验证 two_step_auth_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"crypto/sha256"
	"encoding/hex"
	"testing"
)

func TestTwoStepPasswordUsesAdaptiveHash(t *testing.T) {
	hash, err := hashTwoStepPassword("secondary-secret")
	if err != nil {
		t.Fatalf("hashTwoStepPassword: %v", err)
	}
	if isLegacyTwoStepHash(hash) {
		t.Fatalf("new password unexpectedly used legacy SHA-256: %q", hash)
	}
	valid, legacy := verifyTwoStepPassword(hash, "secondary-secret")
	if !valid || legacy {
		t.Fatalf("adaptive hash verification = (%v,%v), want(true,false)", valid, legacy)
	}
	valid, _ = verifyTwoStepPassword(hash, "wrong-secret")
	if valid {
		t.Fatal("wrong secondary password was accepted")
	}
}

func TestTwoStepPasswordLegacySHA256MigrationCheck(t *testing.T) {
	digest := sha256.Sum256([]byte("legacy-secret"))
	hash := hex.EncodeToString(digest[:])
	valid, legacy := verifyTwoStepPassword(hash, "legacy-secret")
	if !valid || !legacy {
		t.Fatalf("legacy verification = (%v,%v), want(true,true)", valid, legacy)
	}
	valid, legacy = verifyTwoStepPassword(hash, "wrong-secret")
	if valid || !legacy {
		t.Fatalf("wrong legacy verification = (%v,%v), want(false,true)", valid, legacy)
	}
}

func TestTwoStepPasswordValidation(t *testing.T) {
	if err := validateTwoStepPassword("12345"); err == nil {
		t.Fatal("short password should be rejected")
	}
	tooLong := make([]byte, 73)
	for i := range tooLong {
		tooLong[i] = 'a'
	}
	if err := validateTwoStepPassword(string(tooLong)); err == nil {
		t.Fatal("bcrypt-truncated password should be rejected")
	}
	if err := validateTwoStepPassword("安全密码123"); err != nil {
		t.Fatalf("valid unicode password rejected: %v", err)
	}
}

func TestGenerateTwoStepTicketIsRandomAndStrong(t *testing.T) {
	first, err := generateTwoStepTicket()
	if err != nil {
		t.Fatalf("first ticket: %v", err)
	}
	second, err := generateTwoStepTicket()
	if err != nil {
		t.Fatalf("second ticket: %v", err)
	}
	if len(first) != 64 || len(second) != 64 {
		t.Fatalf("ticket lengths = %d,%d; want 64 hex chars", len(first), len(second))
	}
	if first == second {
		t.Fatal("two generated challenge tickets are identical")
	}
}
