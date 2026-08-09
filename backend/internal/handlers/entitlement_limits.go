// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"gorm.io/gorm"
	"genericim/internal/models"
	"genericim/internal/services"
)

func getUploadLimitBytes(db *gorm.DB, userID uint64, mediaType string) int64 {
	if db != nil && userID > 0 {
		return services.NewVipService(db).UploadLimitBytes(userID, mediaType)
	}
	return int64(services.DefaultVipEntitlements(models.VipLevelFree).UploadFileLimitMB) * 1024 * 1024
}

func getPinnedChatLimit(db *gorm.DB, userID uint64) int {
	if db != nil && userID > 0 {
		return services.NewVipService(db).PinnedChatLimit(userID)
	}
	return services.DefaultVipEntitlements(models.VipLevelFree).MaxPinnedChats
}

func getOwnedChatCreationLimit(db *gorm.DB, userID uint64, chatType int8) int {
	if db != nil && userID > 0 {
		return services.NewVipService(db).EffectiveOwnedChatLimit(userID, chatType)
	}
	return 0
}
