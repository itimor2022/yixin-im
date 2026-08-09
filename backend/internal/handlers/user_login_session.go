// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"errors"
	"fmt"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"strings"
	"time"
	"genericim/internal/models"
	"genericim/internal/services"
)

const multiDeviceLoginPolicy = "coexist"

type multiDeviceLoginContext struct {
	Policy                 string
	OtherActiveDeviceCount int
}

type loginSecurityHub interface {
	SendToUser(userID string, data interface{})
}

type loginSecurityPusher interface {
	PushToUserExceptDevice(userID uint64, excludedDeviceID, title, body string, data map[string]interface{}) error
}

type loginDeviceSecurityContext struct {
	IsNewDevice           bool
	OtherKnownDeviceCount int
}

func loadMultiDeviceLoginContext(db *gorm.DB, userID uint64, currentDeviceID string) (multiDeviceLoginContext, error) {
	context := multiDeviceLoginContext{Policy: multiDeviceLoginPolicy}
	if db == nil || userID == 0 {
		return context, nil
	}

	var sessions []models.UserSession
	if err := db.Select("device_id").Where("user_id = ?", userID).Find(&sessions).Error; err != nil {
		return context, err
	}
	return multiDeviceLoginContextFromSessions(sessions, currentDeviceID), nil
}

func multiDeviceLoginContextFromSessions(sessions []models.UserSession, currentDeviceID string) multiDeviceLoginContext {
	context := multiDeviceLoginContext{Policy: multiDeviceLoginPolicy}
	currentDeviceID = services.LogicalPushDeviceID(currentDeviceID)
	seen := make(map[string]struct{}, len(sessions))
	for _, session := range sessions {
		deviceID := services.LogicalPushDeviceID(session.DeviceID)
		if deviceID == "" || deviceID == currentDeviceID {
			continue
		}
		seen[deviceID] = struct{}{}
	}
	context.OtherActiveDeviceCount = len(seen)
	return context
}

func loadLoginDeviceSecurityContext(db *gorm.DB, userID uint64, currentDeviceID string) (loginDeviceSecurityContext, error) {
	if db == nil || userID == 0 {
		return loginDeviceSecurityContext{}, nil
	}
	var devices []models.UserDevice
	if err := db.Select("device_id").Where("user_id = ?", userID).Find(&devices).Error; err != nil {
		return loginDeviceSecurityContext{}, err
	}
	return loginDeviceSecurityContextFromDevices(devices, currentDeviceID), nil
}

func loginDeviceSecurityContextFromDevices(devices []models.UserDevice, currentDeviceID string) loginDeviceSecurityContext {
	currentDeviceID = services.LogicalPushDeviceID(currentDeviceID)
	knownCurrentDevice := false
	otherDevices := make(map[string]struct{}, len(devices))
	for _, device := range devices {
		deviceID := services.LogicalPushDeviceID(device.DeviceID)
		if deviceID == "" {
			continue
		}
		if deviceID == currentDeviceID {
			knownCurrentDevice = true
			continue
		}
		otherDevices[deviceID] = struct{}{}
	}
	return loginDeviceSecurityContext{
		IsNewDevice:           currentDeviceID != "" && !knownCurrentDevice,
		OtherKnownDeviceCount: len(otherDevices),
	}
}

func buildNewDeviceLoginEvent(deviceID, deviceType, deviceName, ip string, occurredAt time.Time) map[string]interface{} {
	if occurredAt.IsZero() {
		occurredAt = time.Now()
	}
	deviceType, deviceName = normalizeLoginDevice(deviceType, deviceName)
	return map[string]interface{}{
		"type":        "new_device_login",
		"event_id":    uuid.NewString(),
		"device_id":   services.LogicalPushDeviceID(deviceID),
		"device_type": deviceType,
		"device_name": deviceName,
		"ip":          strings.TrimSpace(ip),
		"occurred_at": occurredAt.UTC().Format(time.RFC3339),
	}
}

func recordUserLoginWithSecurityNotice(
	db *gorm.DB,
	user models.User,
	token, deviceID, deviceType, deviceName, ip string,
	now time.Time,
	hub loginSecurityHub,
	pusher loginSecurityPusher,
) error {
	securityContext, err := loadLoginDeviceSecurityContext(db, user.ID, deviceID)
	if err != nil {
		return err
	}
	if err := recordUserLogin(db, user.ID, token, deviceID, deviceType, deviceName, ip, now); err != nil {
		return err
	}
	if !securityContext.IsNewDevice || securityContext.OtherKnownDeviceCount == 0 {
		return nil
	}
	event := buildNewDeviceLoginEvent(deviceID, deviceType, deviceName, ip, now)
	if hub != nil {
		hub.SendToUser(user.UUID, event)
	}
	if pusher != nil {
		title := "新设备登录提醒"
		body := fmt.Sprintf("%s 刚刚登录了你的账号。如非本人操作，请立即在设备管理中下线。", event["device_name"])
		go func() {
			_ = pusher.PushToUserExceptDevice(user.ID, deviceID, title, body, event)
		}()
	}
	return nil
}

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
			device.PushTokenHash = extra.PushTokenHash
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
		"push_token_hash":            device.PushTokenHash,
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

func cleanupInactiveUserDevices(db *gorm.DB, userID uint64, currentDeviceID string, before time.Time) {
	if db == nil || userID == 0 {
		return
	}
	currentLogicalID := services.LogicalPushDeviceID(currentDeviceID)
	var candidates []models.UserDevice
	if err := db.Where(
		"user_id = ? AND last_active < ? AND(push_token = '' OR push_token IS NULL)",
		userID,
		before,
	).Find(&candidates).Error; err != nil {
		return
	}
	for _, candidate := range candidates {
		logicalID := services.LogicalPushDeviceID(candidate.DeviceID)
		if logicalID == "" || logicalID == currentLogicalID || strings.TrimSpace(candidate.E2EEPublicKey) != "" {
			continue
		}
		var sessionCount int64
		if err := db.Model(&models.UserSession{}).
			Where("user_id = ? AND device_id = ?", userID, logicalID).
			Count(&sessionCount).Error; err != nil || sessionCount != 0 {
			continue
		}
		_ = db.Where("id = ? AND(push_token = '' OR push_token IS NULL)", candidate.ID).
			Delete(&models.UserDevice{}).Error
	}
}
