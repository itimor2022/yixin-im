package handlers

import (
	"errors"
	"strings"
	"time"

	"gaoranim/internal/models"

	"gorm.io/gorm"
)

func recordUserLogin(db *gorm.DB, userID uint64, token, deviceID, deviceType, deviceName, ip string, now time.Time) error {
	if db == nil || userID == 0 {
		return nil
	}
	deviceID = strings.TrimSpace(deviceID)
	token = strings.TrimSpace(token)
	deviceType, deviceName = normalizeLoginDevice(deviceType, deviceName)
	ip = strings.TrimSpace(ip)
	if now.IsZero() {
		now = time.Now()
	}

	if deviceID != "" {
		if err := upsertUserDeviceLogin(db, userID, deviceID, deviceType, deviceName, ip, now); err != nil {
			return err
		}
	}
	if token == "" {
		return nil
	}

	var session models.UserSession
	err := db.Where("token = ?", token).First(&session).Error
	if err == nil {
		return db.Model(&session).Updates(map[string]interface{}{
			"user_id":     userID,
			"device_id":   deviceID,
			"device_type": deviceType,
			"device_name": deviceName,
			"ip":          ip,
			"last_active": now,
		}).Error
	}
	if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
		return err
	}

	return db.Create(&models.UserSession{
		UserID:     userID,
		Token:      token,
		DeviceID:   deviceID,
		DeviceType: deviceType,
		DeviceName: deviceName,
		IP:         ip,
		LastActive: now,
		CreatedAt:  now,
	}).Error
}

func rotateUserSessionToken(db *gorm.DB, userID uint64, oldToken, newToken, deviceID, deviceType, deviceName, ip string, now time.Time) error {
	if db == nil || userID == 0 {
		return nil
	}
	oldToken = strings.TrimSpace(oldToken)
	newToken = strings.TrimSpace(newToken)
	if newToken == "" {
		return nil
	}
	deviceID = strings.TrimSpace(deviceID)
	deviceType, deviceName = normalizeLoginDevice(deviceType, deviceName)
	ip = strings.TrimSpace(ip)
	if now.IsZero() {
		now = time.Now()
	}

	if deviceID != "" {
		if err := upsertUserDeviceLogin(db, userID, deviceID, deviceType, deviceName, ip, now); err != nil {
			return err
		}
	}

	var session models.UserSession
	if oldToken != "" {
		err := db.Where("user_id = ? AND token = ?", userID, oldToken).First(&session).Error
		if err == nil {
			return db.Model(&session).Updates(map[string]interface{}{
				"token":       newToken,
				"device_id":   deviceID,
				"device_type": deviceType,
				"device_name": deviceName,
				"ip":          ip,
				"last_active": now,
			}).Error
		}
		if err != nil && !errors.Is(err, gorm.ErrRecordNotFound) {
			return err
		}
	}
	return recordUserLogin(db, userID, newToken, deviceID, deviceType, deviceName, ip, now)
}

func deleteUserSessionByToken(db *gorm.DB, userID uint64, token string) error {
	token = strings.TrimSpace(token)
	if db == nil || userID == 0 || token == "" {
		return nil
	}
	return db.Where("user_id = ? AND token = ?", userID, token).Delete(&models.UserSession{}).Error
}

func upsertUserDeviceLogin(db *gorm.DB, userID uint64, deviceID, deviceType, deviceName, ip string, now time.Time) error {
	var devices []models.UserDevice
	if err := db.Where("user_id = ? AND device_id = ?", userID, deviceID).
		Order("last_active DESC, id DESC").
		Find(&devices).Error; err != nil {
		return err
	}

	if len(devices) == 0 {
		return db.Create(&models.UserDevice{
			UserID:     userID,
			DeviceID:   deviceID,
			DeviceType: deviceType,
			DeviceName: deviceName,
			IP:         ip,
			LastActive: now,
			CreatedAt:  now,
		}).Error
	}

	device := devices[0]
	for _, extra := range devices[1:] {
		if strings.TrimSpace(device.PushToken) == "" && strings.TrimSpace(extra.PushToken) != "" {
			device.PushToken = extra.PushToken
		}
		if strings.TrimSpace(device.PushChannel) == "" && strings.TrimSpace(extra.PushChannel) != "" {
			device.PushChannel = extra.PushChannel
		}
		if strings.TrimSpace(device.Location) == "" && strings.TrimSpace(extra.Location) != "" {
			device.Location = extra.Location
		}
		if strings.TrimSpace(device.E2EEPublicKey) == "" && strings.TrimSpace(extra.E2EEPublicKey) != "" {
			device.E2EEPublicKey = extra.E2EEPublicKey
			device.E2EEPublicKeyAlgo = extra.E2EEPublicKeyAlgo
			device.E2EEPublicKeyUpdatedAt = extra.E2EEPublicKeyUpdatedAt
		}
	}

	if err := db.Model(&device).Updates(map[string]interface{}{
		"device_type":                deviceType,
		"device_name":                deviceName,
		"ip":                         ip,
		"last_active":                now,
		"push_token":                 device.PushToken,
		"push_channel":               device.PushChannel,
		"location":                   device.Location,
		"e2ee_public_key":            device.E2EEPublicKey,
		"e2ee_public_key_algo":       device.E2EEPublicKeyAlgo,
		"e2ee_public_key_updated_at": device.E2EEPublicKeyUpdatedAt,
	}).Error; err != nil {
		return err
	}

	if len(devices) > 1 {
		duplicateIDs := make([]uint64, 0, len(devices)-1)
		for _, extra := range devices[1:] {
			duplicateIDs = append(duplicateIDs, extra.ID)
		}
		if len(duplicateIDs) > 0 {
			if err := db.Where("id IN ?", duplicateIDs).Delete(&models.UserDevice{}).Error; err != nil {
				return err
			}
		}
	}

	return nil
}

func normalizeLoginDevice(deviceType, deviceName string) (string, string) {
	deviceType = strings.TrimSpace(deviceType)
	if deviceType == "" {
		deviceType = "unknown"
	}
	deviceName = strings.TrimSpace(deviceName)
	if deviceName != "" {
		return deviceType, deviceName
	}
	switch deviceType {
	case "ios":
		deviceName = "iPhone"
	case "android":
		deviceName = "Android"
	case "windows":
		deviceName = "Windows PC"
	case "macos":
		deviceName = "Mac"
	case "web":
		deviceName = "Web Browser"
	case "linux":
		deviceName = "Linux"
	default:
		deviceName = "Unknown Device"
	}
	return deviceType, deviceName
}
