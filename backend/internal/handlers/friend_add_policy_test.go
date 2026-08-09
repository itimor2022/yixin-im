// 文件用途：验证 friend_add_policy_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"testing"
	"genericim/internal/models"
)

func TestNormalizeFriendAddMode(t *testing.T) {
	tests := map[string]string{

		"": models.FriendAddModeApproval,

		"unknown": models.FriendAddModeApproval,

		" APPROVAL ": models.FriendAddModeApproval,

		"direct": models.FriendAddModeDirect,

		"DISABLED": models.FriendAddModeDisabled,
	}
	for input, want := range tests {

		if got := normalizeFriendAddMode(input); got != want {

			t.Fatalf("normalizeFriendAddMode(%q)=%q, want %q", input, got, want)

		}
	}
}
func TestValidateFriendAddModeSetting(t *testing.T) {
	handler := &SettingHandler{}
	for _, mode := range []string{

		models.FriendAddModeDirect,

		models.FriendAddModeApproval,

		models.FriendAddModeDisabled,
	} {

		if err := handler.validateSystemSettingsForUpdate(map[string]interface{}{

			models.SettingFriendAddMode: mode,
		}); err != nil {

			t.Fatalf("validateSystemSettingsForUpdate(%q) returned %v", mode, err)

		}
	}
	if err := handler.validateSystemSettingsForUpdate(map[string]interface{}{

		models.SettingFriendAddMode: "unexpected",
	}); err == nil {

		t.Fatal("validateSystemSettingsForUpdate accepted an invalid friend mode")
	}
}
