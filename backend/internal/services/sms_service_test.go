// 文件用途：验证 sms_service_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package services

import (
	"context"
	"testing"
	"genericim/internal/config"
)

func TestNormalizeCNMobileRejectsInvalidMainlandPrefixes(t *testing.T) {
	tests := []struct {
		input string
		want  string
	}{
		{input: "13800138000", want: "13800138000"},
		{input: "+86 138-0013-8000", want: "13800138000"},
		{input: "10000000000", want: ""},
		{input: "12000000000", want: ""},
		{input: "8612000000000", want: ""},
		{input: "1380013800", want: ""},
	}
	for _, tt := range tests {
		if got := NormalizeCNMobile(tt.input); got != tt.want {
			t.Errorf("NormalizeCNMobile(%q)=%q, want %q", tt.input, got, tt.want)
		}
	}
}

func TestConsoleSMSSendRejectsReleaseMode(t *testing.T) {
	cfg := &config.Config{}
	cfg.Server.Mode = "release"
	cfg.SMS.Enabled = true
	cfg.SMS.Provider = "console"

	service := NewSMSService(cfg, nil)
	if err := service.SendOTP(context.Background(), "19900000000", "123456"); err == nil {
		t.Fatal("release mode must reject console SMS delivery")
	}
}

func TestConsoleSMSReadyOnlyInDebugMode(t *testing.T) {
	cfg := config.SMSConfig{Enabled: true, Provider: "console"}
	if !SMSSendReady(nil, cfg, "debug") {
		t.Fatal("console SMS must be ready in debug mode")
	}
	if SMSSendReady(nil, cfg, "release") {
		t.Fatal("console SMS must be disabled in release mode")
	}
}

func TestSMSRuntimeOverrideKeepsLocalProvider(t *testing.T) {
	cfg := config.SMSConfig{
		Enabled:         true,
		Provider:        "console",
		RuntimeOverride: true,
	}
	loaded := LoadSMSForRuntime(nil, cfg)
	if loaded.Provider != "console" || !loaded.RuntimeOverride {
		t.Fatalf("runtime override lost: %+v", loaded)
	}
}
