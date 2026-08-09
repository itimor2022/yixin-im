// 文件用途：验证 email_service_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"context"
	"testing"
	"genericim/internal/config"
)

func TestNormalizeEmailAddress(t *testing.T) {
	tests := map[string]string{
		"User.Name+qa@Example.COM": "user.name+qa@example.com",
		"invalid":                  "",
		"Name <user@example.com>":  "",
		"user@example":             "",
		"user@example.com\nBcc:x":  "",
	}
	for input, want := range tests {
		if got := NormalizeEmailAddress(input); got != want {
			t.Fatalf("NormalizeEmailAddress(%q)=%q, want %q", input, got, want)
		}
	}
}

func TestConsoleEmailReadyAndSendOnlyInDebug(t *testing.T) {
	emailCfg := config.EmailConfig{Enabled: true, Provider: "console"}
	if !EmailSendReady(emailCfg, "debug") || EmailSendReady(emailCfg, "release") {
		t.Fatal("console email readiness must be limited to debug mode")
	}
	cfg := &config.Config{Email: emailCfg}
	cfg.Server.Mode = "release"
	if err := NewEmailService(cfg).SendOTP(context.Background(), "qa@example.com", "123456"); err == nil {
		t.Fatal("release mode must reject console email delivery")
	}
}
