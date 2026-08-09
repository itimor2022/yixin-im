// 文件用途：验证 sms_runtime_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package config

import "testing"

func TestValidateRuntimeRejectsConsoleSMSInRelease(t *testing.T) {
	cfg := &Config{}
	cfg.Server.Mode = "release"
	cfg.SMS.Enabled = true
	cfg.SMS.Provider = "console"
	cfg.JWT.Secret = "this-is-a-long-production-secret-value-for-testing"
	cfg.Server.AllowedOrigins = []string{"https://example.com"}
	cfg.WebSocket.AllowedOrigins = []string{"https://example.com"}
	if err := ValidateRuntime(cfg); err == nil {
		t.Fatal("release mode must reject the console SMS provider")
	}
}

func TestValidateRuntimeRejectsSMSRuntimeOverrideInRelease(t *testing.T) {
	cfg := &Config{}
	cfg.Server.Mode = "release"
	cfg.SMS.RuntimeOverride = true
	cfg.JWT.Secret = "this-is-a-long-production-secret-value-for-testing"
	cfg.Server.AllowedOrigins = []string{"https://example.com"}
	cfg.WebSocket.AllowedOrigins = []string{"https://example.com"}
	if err := ValidateRuntime(cfg); err == nil {
		t.Fatal("release mode must reject SMS runtime overrides")
	}
}

func TestValidateRuntimeRejectsConsoleEmailInRelease(t *testing.T) {
	cfg := &Config{}
	cfg.Server.Mode = "release"
	cfg.Email.Enabled = true
	cfg.Email.Provider = "console"
	cfg.JWT.Secret = "this-is-a-long-production-secret-value-for-testing"
	cfg.Server.AllowedOrigins = []string{"https://example.com"}
	cfg.WebSocket.AllowedOrigins = []string{"https://example.com"}
	if err := ValidateRuntime(cfg); err == nil {
		t.Fatal("release mode must reject the console email provider")
	}
}

func TestValidateRuntimeRejectsEmailRuntimeOverrideInRelease(t *testing.T) {
	cfg := &Config{}
	cfg.Server.Mode = "release"
	cfg.Email.RuntimeOverride = true
	cfg.JWT.Secret = "this-is-a-long-production-secret-value-for-testing"
	cfg.Server.AllowedOrigins = []string{"https://example.com"}
	cfg.WebSocket.AllowedOrigins = []string{"https://example.com"}
	if err := ValidateRuntime(cfg); err == nil {
		t.Fatal("release mode must reject email runtime overrides")
	}
}
