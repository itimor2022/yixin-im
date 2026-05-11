package handlers

import (
	"strings"

	"gaoranim/internal/models"

	"gorm.io/gorm"
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
