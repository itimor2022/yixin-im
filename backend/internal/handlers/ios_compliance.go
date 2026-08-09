// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"encoding/json"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"strings"
	"genericim/internal/models"
)

// iosComplianceConfig is a production feature gate for all iOS users. It must
// never be enabled only for App Review accounts or other reviewer detection.
type iosComplianceConfig struct {
	Enabled               bool `json:"enabled"`
	VIPEnabled            bool `json:"vip_enabled"`
	WalletEnabled         bool `json:"wallet_enabled"`
	WalletRechargeEnabled bool `json:"wallet_recharge_enabled"`
	MomentVideoEnabled    bool `json:"moment_video_enabled"`
	CustomPortalEnabled   bool `json:"custom_portal_enabled"`
}

func defaultIOSComplianceConfig() iosComplianceConfig {
	return iosComplianceConfig{
		Enabled:               true,
		VIPEnabled:            false,
		WalletEnabled:         false,
		WalletRechargeEnabled: false,
		MomentVideoEnabled:    false,
		CustomPortalEnabled:   false,
	}
}

func normalizeIOSComplianceConfig(raw interface{}) iosComplianceConfig {
	cfg := defaultIOSComplianceConfig()
	if raw == nil {
		return cfg
	}

	var payload []byte
	switch value := raw.(type) {
	case string:
		payload = []byte(strings.TrimSpace(value))
	case []byte:
		payload = value
	default:
		encoded, err := json.Marshal(value)
		if err != nil {
			return cfg
		}
		payload = encoded
	}
	if len(payload) == 0 || !json.Valid(payload) {
		return cfg
	}
	_ = json.Unmarshal(payload, &cfg)
	if !cfg.WalletEnabled {
		cfg.WalletRechargeEnabled = false
	}
	return cfg
}

func loadIOSComplianceConfig(db *gorm.DB) iosComplianceConfig {
	if db == nil {
		return defaultIOSComplianceConfig()
	}
	var setting models.SystemSetting
	if err := db.Where("`key` = ?", models.SettingIOSCompliance).First(&setting).Error; err != nil {
		return defaultIOSComplianceConfig()
	}
	return normalizeIOSComplianceConfig(setting.Value)
}

func isIOSClientRequest(c *gin.Context, db *gorm.DB, userID uint64) bool {
	if strings.EqualFold(strings.TrimSpace(c.GetHeader("X-Client-Platform")), "ios") {
		return true
	}
	if db == nil {
		return false
	}
	deviceID := strings.TrimSpace(c.GetString("device_id"))
	if deviceID == "" {
		return false
	}
	if userID == 0 {
		userUUID := strings.TrimSpace(c.GetString("user_id"))
		if userUUID == "" {
			return false
		}
		var user models.User
		if err := db.Select("id").Where("uuid = ?", userUUID).First(&user).Error; err != nil {
			return false
		}
		userID = user.ID
	}
	var device models.UserDevice
	if err := db.Select("device_type").
		Where("user_id = ? AND device_id = ?", userID, deviceID).
		First(&device).Error; err != nil {
		return false
	}
	return strings.EqualFold(strings.TrimSpace(device.DeviceType), "ios")
}

// IOSComplianceFeatureGuard blocks direct API access when a feature is hidden
// for all iOS users by the production compliance configuration.
func IOSComplianceFeatureGuard(db *gorm.DB, feature string) gin.HandlerFunc {
	return func(c *gin.Context) {
		cfg := loadIOSComplianceConfig(db)
		if !cfg.Enabled || !isIOSClientRequest(c, db, 0) {
			c.Next()
			return
		}
		allowed := true
		switch feature {
		case "wallet":
			allowed = cfg.WalletEnabled
		case "wallet_recharge":
			allowed = cfg.WalletEnabled && cfg.WalletRechargeEnabled
		case "vip":
			allowed = cfg.VIPEnabled
		}
		if !allowed {
			c.AbortWithStatusJSON(403, gin.H{
				"code":    403,
				"message": "当前 iOS 版本暂不提供此功能",
			})
			return
		}
		c.Next()
	}
}
