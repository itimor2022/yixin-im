// 文件用途：验证 setting_handler_update_url_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import "testing"

func TestValidateAppStoreURLSetting(t *testing.T) {
	tests := []struct {
		name    string
		value   string
		wantErr bool
	}{
		{name: "empty", value: "", wantErr: false},
		{name: "apps apple", value: "https://apps.apple.com/cn/app/id123456789", wantErr: false},
		{name: "itunes", value: "https://itunes.apple.com/app/id123456789", wantErr: false},
		{name: "http rejected", value: "http://apps.apple.com/app/id123456789", wantErr: true},
		{name: "lookalike rejected", value: "https://apps.apple.com.example.com/app/id123", wantErr: true},
		{name: "enterprise manifest rejected", value: "https://download.example.com/manifest.plist", wantErr: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validateAppStoreURLSetting(tt.value)
			if (err != nil) != tt.wantErr {
				t.Fatalf("validateAppStoreURLSetting(%q) error = %v, wantErr %v", tt.value, err, tt.wantErr)
			}
		})
	}
}

func TestFirstNonEmptySetting(t *testing.T) {
	if got := firstNonEmptySetting("", "legacy"); got != "legacy" {
		t.Fatalf("expected legacy fallback, got %q", got)
	}
	if got := firstNonEmptySetting("platform", "legacy"); got != "platform" {
		t.Fatalf("expected platform value, got %q", got)
	}
}
