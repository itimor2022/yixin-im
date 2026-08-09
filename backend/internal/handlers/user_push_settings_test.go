// 文件用途：验证 user_push_settings_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"testing"
	"time"
)

func boolPointer(value bool) *bool {
	return &value
}

func TestPushSettingUpsertValuesPreservesExplicitFalse(t *testing.T) {
	now := time.Date(2026, 7, 17, 4, 0, 0, 0, time.UTC)
	createValues, updateValues := pushSettingUpsertValues(
		42,
		updatePushSettingsRequest{
			Enabled:     boolPointer(false),
			ShowPreview: boolPointer(false),
		},
		now,
	)
	if enabled, ok := createValues["enabled"].(bool); !ok || enabled {
		t.Fatalf("create enabled=%v, want explicit false", createValues["enabled"])
	}
	if preview, ok := createValues["show_preview"].(bool); !ok || preview {
		t.Fatalf("create show_preview=%v, want explicit false", createValues["show_preview"])
	}
	if enabled, ok := updateValues["enabled"].(bool); !ok || enabled {
		t.Fatalf("update enabled=%v, want explicit false", updateValues["enabled"])
	}
	if preview, ok := updateValues["show_preview"].(bool); !ok || preview {
		t.Fatalf("update show_preview=%v, want explicit false", updateValues["show_preview"])
	}
}

func TestPushSettingUpsertValuesKeepsDefaultsForMissingFields(t *testing.T) {
	now := time.Date(2026, 7, 17, 4, 0, 0, 0, time.UTC)
	createValues, updateValues := pushSettingUpsertValues(
		42,
		updatePushSettingsRequest{ShowPreview: boolPointer(false)},
		now,
	)
	if createValues["enabled"] != true {
		t.Fatalf("create enabled=%v, want default true", createValues["enabled"])
	}
	if _, exists := updateValues["enabled"]; exists {
		t.Fatalf("partial update unexpectedly contains enabled: %v", updateValues)
	}
	if updateValues["show_preview"] != false {
		t.Fatalf("partial update show_preview=%v, want false", updateValues["show_preview"])
	}
}
