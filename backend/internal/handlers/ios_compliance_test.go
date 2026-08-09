// 文件用途：验证 ios_compliance_test.go 对应模块的正常流程、异常处理和回归行为。
// 核心逻辑：覆盖输入校验、状态变化、错误返回、边界条件和并发幸命。

package handlers

import (
	"github.com/gin-gonic/gin"
	"net/http/httptest"
	"testing"
	"genericim/internal/models"
)

func TestNormalizeIOSComplianceConfigDefaults(t *testing.T) {
	cfg := normalizeIOSComplianceConfig(nil)
	if !cfg.Enabled || cfg.VIPEnabled || cfg.WalletEnabled ||
		cfg.WalletRechargeEnabled || cfg.MomentVideoEnabled || cfg.CustomPortalEnabled {
		t.Fatalf("unexpected safe default: %+v", cfg)
	}
}

func TestNormalizeIOSComplianceConfigDisablesRechargeWithoutWallet(t *testing.T) {
	cfg := normalizeIOSComplianceConfig(map[string]interface{}{
		"enabled":                 true,
		"wallet_enabled":          false,
		"wallet_recharge_enabled": true,
	})
	if !cfg.Enabled {
		t.Fatal("expected compliance mode to be enabled")
	}
	if cfg.WalletRechargeEnabled {
		t.Fatal("wallet recharge must be disabled when wallet is disabled")
	}
}

func TestIsIOSClientRequestUsesPlatformHeader(t *testing.T) {
	gin.SetMode(gin.TestMode)
	context, _ := gin.CreateTestContext(httptest.NewRecorder())
	context.Request = httptest.NewRequest("GET", "/", nil)
	context.Request.Header.Set("X-Client-Platform", "iOS")
	if !isIOSClientRequest(context, nil, 0) {
		t.Fatal("expected iOS platform header to be recognized")
	}
}

func TestValidateSystemSettingsForUpdateAllowsIOSCompliance(t *testing.T) {
	t.Parallel()
	handler := &SettingHandler{}
	err := handler.validateSystemSettingsForUpdate(map[string]interface{}{
		models.SettingIOSCompliance: map[string]interface{}{
			"enabled":                 true,
			"vip_enabled":             false,
			"wallet_enabled":          false,
			"wallet_recharge_enabled": false,
			"moment_video_enabled":    false,
			"custom_portal_enabled":   false,
		},
	})
	if err != nil {
		t.Fatalf("expected ios compliance setting to be accepted: %v", err)
	}
}
