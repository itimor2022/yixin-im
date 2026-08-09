// 文件用途：验证 setting_handler_chat_attachment_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"testing"
	"genericim/internal/models"
)

func TestChatAttachmentMenuSettingValueDefaultsToEnabled(t *testing.T) {
	t.Parallel()
	got := chatAttachmentMenuSettingValue(nil)
	if !got.Enabled || !got.Album || !got.Camera || !got.Call ||
		!got.Location || !got.RedPacket || !got.Transfer ||
		!got.Favorite || !got.File {
		t.Fatalf("expected all attachment menu options enabled by default: %+v", got)
	}
}

func TestChatAttachmentMenuSettingValueMergesPartialJSON(t *testing.T) {
	t.Parallel()
	got := chatAttachmentMenuSettingValue(`{"album":false,"file":false}`)
	if got.Album || got.File {
		t.Fatalf("expected explicit false values to be preserved: %+v", got)
	}
	if !got.Enabled || !got.Camera || !got.Call || !got.Location ||
		!got.RedPacket || !got.Transfer || !got.Favorite {
		t.Fatalf("expected missing values to stay enabled: %+v", got)
	}
}

func TestValidateSystemSettingsForUpdateChatAttachmentMenu(t *testing.T) {
	t.Parallel()
	handler := &SettingHandler{}
	tests := []struct {
		name      string
		value     interface{}
		wantError bool
	}{
		{
			name: "valid complete object",
			value: map[string]interface{}{
				"enabled": true, "album": true, "camera": true,
				"call": true, "location": true, "red_packet": true,
				"transfer": true, "favorite": true, "file": true,
			},
		},
		{
			name:  "valid partial object",
			value: map[string]interface{}{"album": false},
		},
		{
			name:      "reject unknown key",
			value:     map[string]interface{}{"album": true, "unknown": true},
			wantError: true,
		},
		{
			name:      "reject non bool value",
			value:     map[string]interface{}{"album": "false"},
			wantError: true,
		},
		{
			name:      "reject non object",
			value:     "{}",
			wantError: true,
		},
	}
	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			err := handler.validateSystemSettingsForUpdate(map[string]interface{}{
				models.SettingChatAttachmentMenu: tc.value,
			})
			if tc.wantError && err == nil {
				t.Fatal("expected validation error")
			}
			if !tc.wantError && err != nil {
				t.Fatalf("unexpected validation error: %v", err)
			}
		})
	}
}
