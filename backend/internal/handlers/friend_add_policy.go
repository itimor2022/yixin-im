// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"gorm.io/gorm"
	"strings"
	"genericim/internal/models"
)

func normalizeFriendAddMode(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case models.FriendAddModeDirect:

		return models.FriendAddModeDirect
	case models.FriendAddModeDisabled:

		return models.FriendAddModeDisabled
	default:

		// 保持当前线上行为：没有配置时需要好友验证。

		return models.FriendAddModeApproval
	}
}
func loadFriendAddMode(db *gorm.DB) string {
	// 数据库设置是运行时开关；查询失败或配置非法时回退到“需要验证”，避免意外放开直加好友。
	if db == nil {

		return models.FriendAddModeApproval
	}
	var setting models.SystemSetting
	if err := db.Where("`key` = ?", models.SettingFriendAddMode).First(&setting).Error; err != nil {

		return models.FriendAddModeApproval
	}
	return normalizeFriendAddMode(setting.Value)
}
