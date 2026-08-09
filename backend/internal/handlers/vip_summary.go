// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"time"
	"genericim/internal/models"
	"genericim/internal/services"
)

func inactiveVipSummary() gin.H {
	return gin.H{
		"level":      0,
		"level_name": services.LevelName(models.VipLevelFree),
		"is_active":  false,
		"badge":      "",
		"badge_icon": "",
	}
}

func buildUserVipSummary(db *gorm.DB, userID uint64) gin.H {
	summaries := buildUserVipSummaries(db, []uint64{userID})
	if summary, ok := summaries[userID]; ok {
		return summary
	}
	return inactiveVipSummary()
}

func buildUserVipSummaries(db *gorm.DB, userIDs []uint64) map[uint64]gin.H {
	result := make(map[uint64]gin.H, len(userIDs))
	uniqueIDs := make([]uint64, 0, len(userIDs))
	seen := make(map[uint64]struct{}, len(userIDs))
	for _, userID := range userIDs {
		if userID == 0 {
			continue
		}
		if _, ok := seen[userID]; ok {
			continue
		}
		seen[userID] = struct{}{}
		uniqueIDs = append(uniqueIDs, userID)
		result[userID] = inactiveVipSummary()
	}
	if db == nil || len(uniqueIDs) == 0 {
		return result
	}

	type vipSummaryRow struct {
		UserID       uint64 `gorm:"column:user_id"`
		Level        int8   `gorm:"column:level"`
		BenefitsJSON string `gorm:"column:benefits_json"`
	}

	var rows []vipSummaryRow
	if err := db.Table("user_vip_memberships m").
		Select("m.user_id, m.level, COALESCE(p.benefits_json, '') AS benefits_json").
		Joins("LEFT JOIN vip_plans p ON p.id = m.plan_id AND p.deleted_at IS NULL").
		Where("m.user_id IN ? AND m.status = ? AND m.expired_at > ?", uniqueIDs, models.VipMembershipStatusActive, time.Now()).
		Scan(&rows).Error; err != nil {
		return result
	}
	for _, row := range rows {
		level := services.NormalizeVipLevel(row.Level)
		if level <= models.VipLevelFree {
			continue
		}
		entitlements := services.MergeVipEntitlements(level, row.BenefitsJSON)
		result[row.UserID] = gin.H{
			"level":      level,
			"level_name": services.LevelName(level),
			"is_active":  true,
			"badge":      entitlements.Badge,
			"badge_icon": entitlements.BadgeIcon,
		}
	}
	return result
}
