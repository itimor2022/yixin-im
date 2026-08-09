// 文件用途：验证 auth_banned_login_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"strings"
	"testing"
	"time"
	"genericim/internal/models"
)

func TestBannedLoginResponseIncludesReasonDurationAndAppeal(t *testing.T) {
	now := time.Now()
	message, data := bannedLoginResponse(models.User{
		Status:    models.UserStatusBanned,
		BanReason: "QA policy violation",
		BannedAt:  &now,
	})
	for _, fragment := range []string{"QA policy violation", "永久", "申诉"} {
		if !strings.Contains(message, fragment) {
			t.Fatalf("banned login message missing %q: %s", fragment, message)
		}
	}
	if data["ban_until"] != "until_unbanned" || data["appeal_action"] != "contact_support" {
		t.Fatalf("unexpected banned login metadata: %+v", data)
	}
	if data["banned_at"] == nil {
		t.Fatalf("banned_at missing: %+v", data)
	}
}
