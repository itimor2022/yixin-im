package handlers

import (
	"time"

	"gaoranim/internal/models"

	"gorm.io/gorm"
)

// ensureContactRelation 确保单向联系人关系存在且为启用状态。
// 返回值 changed=true 表示本次有新增或状态修复。
func ensureContactRelation(db *gorm.DB, userID, contactUserID uint64, now time.Time) (bool, error) {
	var contacts []models.Contact
	if err := db.Where("user_id = ? AND contact_user_id = ?", userID, contactUserID).
		Order("id ASC").
		Find(&contacts).Error; err != nil {
		return false, err
	}

	if len(contacts) == 0 {
		if err := db.Create(&models.Contact{
			UserID:        userID,
			ContactUserID: contactUserID,
			Status:        1,
			CreatedAt:     now,
			UpdatedAt:     now,
		}).Error; err != nil {
			return false, err
		}
		return true, nil
	}

	// 清理重复数据：保留最早一条，删除其余记录
	if len(contacts) > 1 {
		duplicateIDs := make([]uint64, 0, len(contacts)-1)
		for i := 1; i < len(contacts); i++ {
			duplicateIDs = append(duplicateIDs, contacts[i].ID)
		}
		if err := db.Where("id IN ?", duplicateIDs).Delete(&models.Contact{}).Error; err != nil {
			return false, err
		}
	}
	contact := contacts[0]

	// 若历史数据被标记删除，则恢复为启用状态（包含重复记录一起修复）
	if err := db.Model(&models.Contact{}).
		Where("user_id = ? AND contact_user_id = ? AND status <> 1", userID, contactUserID).
		Updates(map[string]interface{}{
			"status":     1,
			"updated_at": now,
		}).Error; err != nil {
		return false, err
	}

	return contact.Status != 1 || len(contacts) > 1, nil
}
