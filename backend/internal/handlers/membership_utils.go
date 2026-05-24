package handlers

import (
	"time"

	"gaoranim/internal/models"

	"gorm.io/gorm"
)

func getActiveMembershipForUser(db *gorm.DB, userID uint64) (*models.UserMembership, error) {
	var membership models.UserMembership
	err := db.Preload("Plan").Where("user_id = ? AND status = ?", userID, models.MembershipStatusActive).Order("expire_at DESC").First(&membership).Error
	if err != nil {
		return nil, err
	}
	if membership.ExpireAt.Before(time.Now()) {
		now := time.Now()
		_ = db.Model(&membership).Updates(map[string]interface{}{
			"status":       models.MembershipStatusExpired,
			"cancelled_at": now,
			"updated_at":   now,
		}).Error
		_ = db.Model(&models.User{}).Where("id = ?", userID).Updates(map[string]interface{}{
			"premium_type":   "",
			"nickname_color": "",
		}).Error
		membership.Status = models.MembershipStatusExpired
	}
	return &membership, nil
}

func hasPremiumMembership(db *gorm.DB, userID uint64) bool {
	membership, err := getActiveMembershipForUser(db, userID)
	return err == nil && membership != nil && membership.IsActive()
}

func getUploadLimitBytes(db *gorm.DB, userID uint64, mediaType string) int64 {
	premium := hasPremiumMembership(db, userID)

	switch mediaType {
	case "image":
		if premium {
			return 20 * 1024 * 1024
		}
		return 10 * 1024 * 1024
	case "video":
		if premium {
			return 300 * 1024 * 1024
		}
		return 100 * 1024 * 1024
	case "voice":
		if premium {
			return 40 * 1024 * 1024
		}
		return 20 * 1024 * 1024
	case "file":
		if premium {
			return 300 * 1024 * 1024
		}
		return 100 * 1024 * 1024
	default:
		return 100 * 1024 * 1024
	}
}

func getPinnedChatLimit(db *gorm.DB, userID uint64) int {
	if hasPremiumMembership(db, userID) {
		return 10
	}
	return 5
}

func getOwnedChatCreationLimit(db *gorm.DB, userID uint64, chatType int8) int {
	if hasPremiumMembership(db, userID) {
		if chatType == 2 {
			return 20
		}
		if chatType == 3 {
			return 10
		}
	}
	if chatType == 2 {
		return 9999
	}
	if chatType == 3 {
		return 9999
	}
	return 0
}
