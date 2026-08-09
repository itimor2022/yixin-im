// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"crypto/sha256"
	"encoding/binary"
	"encoding/json"
	"gorm.io/gorm"
	"strconv"
	"strings"
	"genericim/internal/models"
)

const (
	DefaultChatImageDirectUploadRolloutPercent = 0
	DefaultChatImageDirectUploadMaxConcurrency = 3
)

var defaultChatImageDirectUploadPlatforms = []string{"android", "ios"}

type ChatImageDirectUploadConfig struct {
	Enabled        bool     `json:"enabled"`
	Platforms      []string `json:"platforms"`
	RolloutPercent int      `json:"rollout_percent"`
	MaxConcurrency int      `json:"max_concurrency"`
}

func DefaultChatImageDirectUploadConfig() ChatImageDirectUploadConfig {
	return ChatImageDirectUploadConfig{

		Enabled: false,

		Platforms: append([]string(nil), defaultChatImageDirectUploadPlatforms...),

		RolloutPercent: DefaultChatImageDirectUploadRolloutPercent,

		MaxConcurrency: DefaultChatImageDirectUploadMaxConcurrency,
	}
}
func LoadChatImageDirectUploadConfig(db *gorm.DB) ChatImageDirectUploadConfig {
	cfg := DefaultChatImageDirectUploadConfig()
	if db == nil {

		return cfg
	}
	keys := []string{

		models.SettingChatImageDirectUploadEnabled,

		models.SettingChatImageDirectUploadPlatforms,

		models.SettingChatImageDirectUploadRolloutPercent,

		models.SettingChatImageDirectUploadMaxConcurrency,
	}
	var settings []models.SystemSetting
	if err := db.Where("`key` IN ?", keys).Find(&settings).Error; err != nil {

		return cfg
	}
	for _, setting := range settings {

		switch setting.Key {

		case models.SettingChatImageDirectUploadEnabled:

			cfg.Enabled, _ = strconv.ParseBool(strings.TrimSpace(setting.Value))

		case models.SettingChatImageDirectUploadPlatforms:
			var values []string

			if json.Unmarshal([]byte(setting.Value), &values) == nil {

				if normalized := NormalizeDirectUploadPlatforms(values); len(normalized) > 0 {

					cfg.Platforms = normalized

				}

			}

		case models.SettingChatImageDirectUploadRolloutPercent:

			if value, err := strconv.Atoi(strings.TrimSpace(setting.Value)); err == nil {

				cfg.RolloutPercent = clamp(value, 0, 100)

			}

		case models.SettingChatImageDirectUploadMaxConcurrency:

			if value, err := strconv.Atoi(strings.TrimSpace(setting.Value)); err == nil {

				cfg.MaxConcurrency = clamp(value, 1, 3)

			}

		}
	}
	return cfg
}
func NormalizeDirectUploadPlatform(platform string) string {
	switch strings.ToLower(strings.TrimSpace(platform)) {
	case "android":

		return "android"
	case "ios", "iphone", "ipad":

		return "ios"
	case "windows":

		return "windows"
	case "macos", "mac":

		return "macos"
	case "linux":

		return "linux"
	case "web":

		return "web"
	default:

		return ""
	}
}
func NormalizeDirectUploadPlatforms(platforms []string) []string {
	result := make([]string, 0, len(platforms))
	seen := make(map[string]struct{}, len(platforms))
	for _, raw := range platforms {

		platform := NormalizeDirectUploadPlatform(raw)

		if platform == "" {

			continue

		}

		if _, exists := seen[platform]; exists {

			continue

		}

		seen[platform] = struct{}{}
		result = append(result, platform)
	}
	return result
}
func IsDirectUploadPlatformAllowed(platform string, allowed []string) bool {
	platform = NormalizeDirectUploadPlatform(platform)
	if platform == "" {

		return false
	}
	for _, candidate := range allowed {

		if NormalizeDirectUploadPlatform(candidate) == platform {

			return true

		}
	}
	return false
}
func IsUserInDirectUploadRollout(userID string, rolloutPercent int) bool {
	if rolloutPercent <= 0 {

		return false
	}
	if rolloutPercent >= 100 {

		return true
	}
	sum := sha256.Sum256([]byte(strings.TrimSpace(userID)))
	bucket := int(binary.BigEndian.Uint32(sum[:4]) % 100)
	return bucket < rolloutPercent
}
func clamp(value, minValue, maxValue int) int {
	if value < minValue {

		return minValue
	}
	if value > maxValue {

		return maxValue
	}
	return value
}
