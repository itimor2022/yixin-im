// 文件用途：验证 config_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package config

import (
	"strings"
	"testing"
)

func TestLoadBundledConfigFiles(t *testing.T) {
	for _, path := range []string{

		"../../config.yaml",

		"../../baota/config.yaml",
	} {

		path := path

		t.Run(path, func(t *testing.T) {

			cfg, err := Load(path)

			if err != nil {

				t.Fatalf("load config: %v", err)

			}

			if cfg.LiveKit.TokenExpire < 0 {

				t.Fatalf("livekit token_expire should not be negative, got %d", cfg.LiveKit.TokenExpire)

			}

		})
	}
}
func TestValidateRuntimeRelease(t *testing.T) {
	t.Run("accepts strong release config", func(t *testing.T) {

		if err := ValidateRuntime(validReleaseConfig()); err != nil {

			t.Fatalf("ValidateRuntime returned error: %v", err)

		}
	})
	for _, tc := range []struct {
		name string

		mutate func(*Config)

		want string
	}{

		{

			name: "rejects weak jwt secret",

			mutate: func(cfg *Config) { cfg.JWT.Secret = "change-in-production" },

			want: "jwt.secret",
		},

		{

			name: "rejects missing api origins",

			mutate: func(cfg *Config) { cfg.Server.AllowedOrigins = nil },

			want: "server.allowed_origins",
		},

		{

			name: "rejects wildcard api origin",

			mutate: func(cfg *Config) { cfg.Server.AllowedOrigins = []string{"https://admin.example.com", "*"} },

			want: "server.allowed_origins",
		},

		{

			name: "rejects missing websocket origins",

			mutate: func(cfg *Config) { cfg.WebSocket.AllowedOrigins = []string{" "} },

			want: "websocket.allowed_origins",
		},

		{

			name: "rejects wildcard websocket origin",

			mutate: func(cfg *Config) { cfg.WebSocket.AllowedOrigins = []string{"*"} },

			want: "websocket.allowed_origins",
		},
	} {

		tc := tc

		t.Run(tc.name, func(t *testing.T) {

			cfg := validReleaseConfig()

			tc.mutate(cfg)
			err := ValidateRuntime(cfg)

			if err == nil {

				t.Fatalf("ValidateRuntime returned nil error")

			}

			if !strings.Contains(err.Error(), tc.want) {

				t.Fatalf("ValidateRuntime error = %q, want it to contain %q", err.Error(), tc.want)

			}

		})
	}
}
func TestLoadAppliesStorageEnvOverrides(t *testing.T) {
	t.Setenv("GENERIC_IM_STORAGE_PROVIDER", "oss")
	t.Setenv("GENERIC_IM_STORAGE_ALIYUN_ENDPOINT", "oss-cn-hangzhou.aliyuncs.com")
	t.Setenv("GENERIC_IM_STORAGE_ALIYUN_BUCKET", "genericim-media")
	t.Setenv("GENERIC_IM_STORAGE_ALIYUN_ACCESS_KEY_ID", "test-key")
	t.Setenv("GENERIC_IM_STORAGE_ALIYUN_ACCESS_KEY_SECRET", "test-secret")
	t.Setenv("GENERIC_IM_STORAGE_ALIYUN_PUBLIC_BASE_URL", "https://media.example.com")
	t.Setenv("GENERIC_IM_STORAGE_ALIYUN_USE_HTTPS", "true")
	t.Setenv("GENERIC_IM_STORAGE_LOCAL_BASE_URL", "https://api.example.com")
	cfg, err := Load("../../config.yaml")
	if err != nil {

		t.Fatalf("load config: %v", err)
	}
	if cfg.Storage.Provider != "oss" {

		t.Fatalf("provider=%q, want oss", cfg.Storage.Provider)
	}
	if cfg.Storage.Aliyun.Endpoint != "oss-cn-hangzhou.aliyuncs.com" {

		t.Fatalf("aliyun endpoint=%q", cfg.Storage.Aliyun.Endpoint)
	}
	if cfg.Storage.Aliyun.Bucket != "genericim-media" {

		t.Fatalf("aliyun bucket=%q", cfg.Storage.Aliyun.Bucket)
	}
	if cfg.Storage.Aliyun.AccessKeyID != "test-key" {

		t.Fatalf("aliyun access key id=%q", cfg.Storage.Aliyun.AccessKeyID)
	}
	if cfg.Storage.Aliyun.AccessKeySecret != "test-secret" {

		t.Fatalf("aliyun access key secret=%q", cfg.Storage.Aliyun.AccessKeySecret)
	}
	if cfg.Storage.Aliyun.PublicBaseURL != "https://media.example.com" {

		t.Fatalf("aliyun public base url=%q", cfg.Storage.Aliyun.PublicBaseURL)
	}
	if !cfg.Storage.Aliyun.UseHTTPS {

		t.Fatal("aliyun use_https=false, want true")
	}
	if cfg.Storage.Local.BaseURL != "https://api.example.com" {

		t.Fatalf("local base url=%q", cfg.Storage.Local.BaseURL)
	}
}
func TestMessageStorageEnvOverridesKeepIdempotencyAtLeastRetention(t *testing.T) {
	t.Setenv("GENERIC_IM_MESSAGE_RETENTION_MONTHS", "48")
	t.Setenv("GENERIC_IM_MESSAGE_IDEMPOTENCY_MONTHS", "12")
	cfg, err := Load("../../config.yaml")
	if err != nil {

		t.Fatalf("load config: %v", err)
	}
	if cfg.MessageStorage.RetentionMonths != 48 {

		t.Fatalf("retention=%d, want 48", cfg.MessageStorage.RetentionMonths)
	}
	if cfg.MessageStorage.IdempotencyMonths != 48 {

		t.Fatalf("idempotency=%d, want retention floor 48", cfg.MessageStorage.IdempotencyMonths)
	}
}
func validReleaseConfig() *Config {
	return &Config{

		Server: ServerConfig{

			Mode: "release",

			AllowedOrigins: []string{"https://admin.example.com"},
		},

		WebSocket: WebSocketConfig{

			AllowedOrigins: []string{"https://app.example.com"},
		},

		JWT: JWTConfig{

			Secret: "0123456789abcdefghijklmnopqrstuvwxyz",
		},
	}
}
