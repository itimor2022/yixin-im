// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"gorm.io/gorm"
	"strings"
	"genericim/internal/models"
)

// RequirePhoneBindIfPolicy 当系统设置「需要绑定手机」开启时，用户未绑定则返回 false。
// actionHint 非空时错误文案为「请先绑定手机号后再…」。
func RequirePhoneBindIfPolicy(db *gorm.DB, userID uint64, actionHint string) (ok bool, msg string) {
	var st models.SystemSetting
	if err := db.Where("`key` = ?", models.SettingRequirePhoneBind).First(&st).Error; err != nil {
		return true, ""
	}
	if !isSystemSettingTrue(st.Value) {
		return true, ""
	}
	var user models.User
	if err := db.First(&user, userID).Error; err != nil {
		return false, "用户不存在"
	}
	if user.Phone == nil || strings.TrimSpace(*user.Phone) == "" {
		if actionHint != "" {
			return false, "请先绑定手机号后再" + actionHint
		}
		return false, "请先绑定手机号"
	}
	return true, ""
}
