package privacy

import (
	"strings"

	"gaoranim/internal/models"

	"gorm.io/gorm"
)

const (
	LastSeenVisibilityAll      = "所有人"
	LastSeenVisibilityContacts = "联系人"
	LastSeenVisibilityNobody   = "无"
)

func NormalizeLastSeenVisibility(value string) string {
	switch strings.TrimSpace(value) {
	case LastSeenVisibilityContacts:
		return LastSeenVisibilityContacts
	case LastSeenVisibilityNobody:
		return LastSeenVisibilityNobody
	default:
		return LastSeenVisibilityAll
	}
}

func CanViewerSeeOnlineStatus(db *gorm.DB, viewerID, targetID uint64) (bool, error) {
	if viewerID == 0 || targetID == 0 {
		return false, nil
	}
	if viewerID == targetID {
		return true, nil
	}

	result, err := BatchCanViewerSeeOnlineStatus(db, viewerID, []uint64{targetID})
	if err != nil {
		return false, err
	}
	return result[targetID], nil
}

func CanViewerSeeOnlineStatusByUUID(db *gorm.DB, viewerUUID, targetUUID string) (bool, error) {
	viewerUUID = strings.TrimSpace(viewerUUID)
	targetUUID = strings.TrimSpace(targetUUID)
	if viewerUUID == "" || targetUUID == "" {
		return false, nil
	}
	if viewerUUID == targetUUID {
		return true, nil
	}

	var users []models.User
	if err := db.Select("id", "uuid").
		Where("uuid IN ?", []string{viewerUUID, targetUUID}).
		Find(&users).Error; err != nil {
		return false, err
	}

	var viewerID uint64
	var targetID uint64
	for _, user := range users {
		switch user.UUID {
		case viewerUUID:
			viewerID = user.ID
		case targetUUID:
			targetID = user.ID
		}
	}

	return CanViewerSeeOnlineStatus(db, viewerID, targetID)
}

func BatchCanViewerSeeOnlineStatus(db *gorm.DB, viewerID uint64, targetIDs []uint64) (map[uint64]bool, error) {
	result := make(map[uint64]bool, len(targetIDs))
	if len(targetIDs) == 0 {
		return result, nil
	}

	uniqueTargetIDs := make([]uint64, 0, len(targetIDs))
	seen := make(map[uint64]struct{}, len(targetIDs))
	for _, targetID := range targetIDs {
		if targetID == 0 {
			continue
		}
		if _, ok := seen[targetID]; ok {
			continue
		}
		seen[targetID] = struct{}{}
		uniqueTargetIDs = append(uniqueTargetIDs, targetID)
	}
	if len(uniqueTargetIDs) == 0 {
		return result, nil
	}

	if db == nil {
		for _, targetID := range uniqueTargetIDs {
			result[targetID] = targetID == viewerID
		}
		return result, nil
	}

	var settings []models.UserPrivacySetting
	if err := db.Select("user_id", "last_seen_visibility").
		Where("user_id IN ?", uniqueTargetIDs).
		Find(&settings).Error; err != nil {
		return nil, err
	}

	visibilityByUserID := make(map[uint64]string, len(settings))
	for _, setting := range settings {
		visibilityByUserID[setting.UserID] = NormalizeLastSeenVisibility(setting.LastSeenVisibility)
	}

	contactOnlyTargetIDs := make([]uint64, 0)
	for _, targetID := range uniqueTargetIDs {
		if targetID == viewerID {
			result[targetID] = true
			continue
		}

		switch visibilityByUserID[targetID] {
		case LastSeenVisibilityContacts:
			contactOnlyTargetIDs = append(contactOnlyTargetIDs, targetID)
		case LastSeenVisibilityNobody:
			result[targetID] = false
		default:
			result[targetID] = true
		}
	}

	if len(contactOnlyTargetIDs) == 0 {
		return result, nil
	}

	var visibleContacts []struct {
		UserID uint64 `gorm:"column:user_id"`
	}
	if err := db.Model(&models.Contact{}).
		Select("user_id").
		Where("user_id IN ? AND contact_user_id = ? AND status = 1", contactOnlyTargetIDs, viewerID).
		Find(&visibleContacts).Error; err != nil {
		return nil, err
	}

	contactVisibleSet := make(map[uint64]struct{}, len(visibleContacts))
	for _, row := range visibleContacts {
		contactVisibleSet[row.UserID] = struct{}{}
	}

	for _, targetID := range contactOnlyTargetIDs {
		_, visible := contactVisibleSet[targetID]
		result[targetID] = visible
	}

	return result, nil
}
