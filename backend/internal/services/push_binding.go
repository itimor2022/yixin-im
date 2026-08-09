// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"strings"
	"time"
	"unicode"
	"genericim/internal/models"
)

var (
	ErrInvalidPushChannel = errors.New("invalid push channel")
	ErrInvalidPushToken   = errors.New("invalid push token")
	ErrPushDeviceMismatch = errors.New("push device identity mismatch")
)

// PushBindingRequest

type PushBindingRequest struct {
	BindingID uint64 `json:"binding_id"`
	DeviceID  string `json:"device_id"`
	Channel   string `json:"push_channel"`
	PushToken string `json:"push_token"`
}

// PushBindingMetadata

type PushBindingMetadata struct {
	DeviceType string
	Brand      string
	Model      string
	DeviceName string
	AppVersion string
}

type canonicalWebPushSubscription struct {
	Endpoint string               `json:"endpoint"`
	Keys     canonicalWebPushKeys `json:"keys"`
}

type canonicalWebPushKeys struct {
	Auth   string `json:"auth"`
	P256dh string `json:"p256dh"`
}

// NormalizePushToken

func NormalizePushToken(channel, raw string) (string, string, error) {
	normalizedChannel := NormalizePushChannel(channel, "")
	if normalizedChannel == PushChannelUnknown {
		return "", "", ErrInvalidPushChannel
	}

	var normalized string
	switch normalizedChannel {
	case PushChannelAPNs, PushChannelAPNsVoIP:
		normalized = strings.TrimSpace(raw)
		normalized = strings.TrimPrefix(normalized, "<")
		normalized = strings.TrimSuffix(normalized, ">")
		normalized = strings.Map(func(r rune) rune {
			if unicode.IsSpace(r) {
				return -1
			}
			return r
		}, normalized)
		normalized = strings.ToLower(normalized)
		if normalized == "" || len(normalized)%2 != 0 {
			return "", "", ErrInvalidPushToken
		}
		if _, err := hex.DecodeString(normalized); err != nil {
			return "", "", ErrInvalidPushToken
		}
	case PushChannelWebPush:
		var payload canonicalWebPushSubscription
		if err := json.Unmarshal([]byte(strings.TrimSpace(raw)), &payload); err != nil {
			return "", "", ErrInvalidPushToken
		}
		payload.Endpoint = strings.TrimSpace(payload.Endpoint)
		payload.Keys.Auth = strings.TrimSpace(payload.Keys.Auth)
		payload.Keys.P256dh = strings.TrimSpace(payload.Keys.P256dh)
		if payload.Endpoint == "" || payload.Keys.Auth == "" || payload.Keys.P256dh == "" {
			return "", "", ErrInvalidPushToken
		}
		encoded, err := json.Marshal(payload)
		if err != nil {
			return "", "", fmt.Errorf("marshal web push subscription: %w", err)
		}
		normalized = string(encoded)
	default:
		normalized = strings.TrimSpace(raw)
		if normalized == "" {
			return "", "", ErrInvalidPushToken
		}
	}
	sum := sha256.Sum256([]byte(normalized))
	return normalized, hex.EncodeToString(sum[:]), nil
}

func ClearPushTokenUpdates() map[string]interface{} {
	return map[string]interface{}{
		"push_token":            "",
		"push_token_hash":       nil,
		"push_token_updated_at": nil,
	}
}

// BindPushToken

func BindPushToken(
	db *gorm.DB,
	userID uint64,
	logicalDeviceID string,
	channel string,
	rawToken string,
	metadata PushBindingMetadata,
) (models.UserDevice, error) {
	var bound models.UserDevice
	if db == nil || userID == 0 {
		return bound, errors.New("push binding database unavailable")
	}
	logicalDeviceID = strings.TrimSpace(logicalDeviceID)
	if logicalDeviceID == "" || LogicalPushDeviceID(logicalDeviceID) != logicalDeviceID {
		return bound, ErrPushDeviceMismatch
	}
	normalizedChannel := NormalizeExplicitPushChannel(channel, metadata.DeviceType)
	normalizedToken, tokenHash, err := NormalizePushToken(normalizedChannel, rawToken)
	if err != nil {
		return bound, err
	}
	storageDeviceID := PushStorageDeviceID(logicalDeviceID, normalizedChannel)
	if storageDeviceID == "" {
		return bound, ErrPushDeviceMismatch
	}
	now := time.Now()
	for attempt := 0; attempt < 2; attempt++ {
		bound = models.UserDevice{}
		err = db.Transaction(func(tx *gorm.DB) error {
			var owners []models.UserDevice
			if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
				Where("push_channel = ? AND push_token_hash = ?", normalizedChannel, tokenHash).
				Find(&owners).Error; err != nil {
				return err
			}
			for _, owner := range owners {
				if owner.UserID == userID && owner.DeviceID == storageDeviceID {
					continue
				}
				if err := tx.Model(&models.UserDevice{}).
					Where("id = ? AND push_channel = ? AND push_token_hash = ? AND push_token = ?", owner.ID, normalizedChannel, tokenHash, normalizedToken).
					Updates(ClearPushTokenUpdates()).Error; err != nil {
					return err
				}
			}
			result := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
				Where("user_id = ? AND device_id = ?", userID, storageDeviceID).
				Order("id DESC").First(&bound)
			if errors.Is(result.Error, gorm.ErrRecordNotFound) {
				bound = models.UserDevice{
					UserID:             userID,
					DeviceID:           storageDeviceID,
					DeviceType:         strings.TrimSpace(metadata.DeviceType),
					Brand:              strings.TrimSpace(metadata.Brand),
					Model:              strings.TrimSpace(metadata.Model),
					DeviceName:         strings.TrimSpace(metadata.DeviceName),
					PushChannel:        normalizedChannel,
					PushToken:          normalizedToken,
					PushTokenHash:      &tokenHash,
					AppVersion:         strings.TrimSpace(metadata.AppVersion),
					PushTokenUpdatedAt: &now,
					LastActive:         now,
					CreatedAt:          now,
				}
				if bound.DeviceType == "" {
					bound.DeviceType = "unknown"
				}
				return tx.Create(&bound).Error
			}
			if result.Error != nil {
				return result.Error
			}
			updates := map[string]interface{}{
				"push_token":            normalizedToken,
				"push_token_hash":       tokenHash,
				"push_channel":          normalizedChannel,
				"push_token_updated_at": now,
				"last_active":           now,
			}
			if value := strings.TrimSpace(metadata.DeviceType); value != "" {
				updates["device_type"] = value
			}
			if value := strings.TrimSpace(metadata.Brand); value != "" {
				updates["brand"] = value
			}
			if value := strings.TrimSpace(metadata.Model); value != "" {
				updates["model"] = value
			}
			if value := strings.TrimSpace(metadata.DeviceName); value != "" {
				updates["device_name"] = value
			}
			if value := strings.TrimSpace(metadata.AppVersion); value != "" {
				updates["app_version"] = value
			}
			if err := tx.Model(&bound).Updates(updates).Error; err != nil {
				return err
			}
			bound.PushToken = normalizedToken
			bound.PushTokenHash = &tokenHash
			bound.PushChannel = normalizedChannel
			bound.PushTokenUpdatedAt = &now
			return nil
		})
		if err == nil || !isDuplicatePushBindingError(err) {
			break
		}
	}
	return bound, err
}

func isDuplicatePushBindingError(err error) bool {
	if err == nil {
		return false
	}
	message := strings.ToLower(err.Error())
	return strings.Contains(message, "duplicate entry") ||
		strings.Contains(message, "error 1062") ||
		strings.Contains(message, "unique constraint")
}

// ClearPushBinding
func ClearPushBinding(db *gorm.DB, userID uint64, jwtDeviceID string, binding PushBindingRequest) (bool, error) {
	if db == nil || userID == 0 {
		return false, errors.New("push binding database unavailable")
	}
	jwtDeviceID = strings.TrimSpace(jwtDeviceID)
	requestDeviceID := strings.TrimSpace(binding.DeviceID)
	if requestDeviceID == "" || requestDeviceID != jwtDeviceID || LogicalPushDeviceID(requestDeviceID) != requestDeviceID {
		return false, ErrPushDeviceMismatch
	}
	channel := NormalizePushChannel(binding.Channel, "")
	normalizedToken, tokenHash, err := NormalizePushToken(channel, binding.PushToken)
	if err != nil {
		return false, err
	}
	storageDeviceID := PushStorageDeviceID(jwtDeviceID, channel)
	query := db.Model(&models.UserDevice{}).
		Where("user_id = ? AND device_id = ? AND push_channel = ? AND push_token_hash = ? AND push_token = ?",
			userID, storageDeviceID, channel, tokenHash, normalizedToken)
	if binding.BindingID != 0 {
		query = query.Where("id = ?", binding.BindingID)
	}
	result := query.Updates(ClearPushTokenUpdates())
	return result.RowsAffected > 0, result.Error
}

// ClearPushBindingsForDevice

func ClearPushBindingsForDevice(db *gorm.DB, userID uint64, jwtDeviceID string) (int64, error) {
	if db == nil || userID == 0 {
		return 0, errors.New("push binding database unavailable")
	}
	deviceIDs := PushStorageDeviceIDs(strings.TrimSpace(jwtDeviceID))
	if len(deviceIDs) == 0 {
		return 0, ErrPushDeviceMismatch
	}
	result := db.Model(&models.UserDevice{}).
		Where("user_id = ? AND device_id IN ?", userID, deviceIDs).
		Updates(ClearPushTokenUpdates())
	return result.RowsAffected, result.Error
}

// ClearInvalidPushToken
//

func ClearInvalidPushToken(db *gorm.DB, device models.UserDevice) error {
	if db == nil || device.ID == 0 {
		return nil
	}
	channel := NormalizePushChannel(device.PushChannel, device.DeviceType)
	normalizedToken, tokenHash, err := NormalizePushToken(channel, device.PushToken)
	if err != nil {
		return err
	}
	query := db.Model(&models.UserDevice{}).
		Where("id = ? AND push_channel = ? AND push_token = ?", device.ID, channel, normalizedToken)
	if device.PushTokenHash != nil && strings.TrimSpace(*device.PushTokenHash) != "" {
		query = query.Where("push_token_hash = ?", tokenHash)
	}
	return query.Updates(ClearPushTokenUpdates()).Error
}
