// 文件用途：实现可复用的后端业务服务和领域逻辑。
// 核心逻辑：协调数据库、缓存、队列和外部服务，集中处理事务、幂等、重试和错误传播。

package services

import (
	"errors"
	"fmt"
	"gorm.io/gorm"
	"sort"
	"strings"
	"time"
	"genericim/internal/models"
)

// MigratePushBindings normalizes existing rows, backfills token hashes, merges
// duplicate storage-device rows, and only then creates the two uniqueness
// constraints required by the binding model. It is safe to run repeatedly.
func MigratePushBindings(db *gorm.DB) error {
	if db == nil {
		return errors.New("push binding database unavailable")
	}
	migrator := db.Migrator()
	if migrator.HasIndex(&models.UserDevice{}, "uk_user_device") &&
		migrator.HasIndex(&models.UserDevice{}, "uk_push_channel_token_hash") {
		return nil
	}
	if err := db.Transaction(func(tx *gorm.DB) error {
		var devices []models.UserDevice
		if err := tx.Order("id ASC").Find(&devices).Error; err != nil {
			return err
		}
		for _, device := range devices {
			if err := normalizeStoredPushDevice(tx, device); err != nil {
				return err
			}
		}
		if err := tx.Order("user_id ASC, device_id ASC, id ASC").Find(&devices).Error; err != nil {
			return err
		}
		if err := mergeDuplicateStorageDevices(tx, devices); err != nil {
			return err
		}

		devices = nil
		if err := tx.Where("push_token_hash IS NOT NULL AND push_token != ''").Find(&devices).Error; err != nil {
			return err
		}
		sort.SliceStable(devices, func(i, j int) bool {
			return pushBindingNewer(devices[i], devices[j])
		})
		seen := make(map[string]uint64, len(devices))
		for _, device := range devices {
			if device.PushTokenHash == nil || strings.TrimSpace(*device.PushTokenHash) == "" {
				continue
			}
			key := strings.TrimSpace(device.PushChannel) + "\x00" + strings.TrimSpace(*device.PushTokenHash)
			if _, exists := seen[key]; !exists {
				seen[key] = device.ID
				continue
			}
			if err := tx.Model(&models.UserDevice{}).
				Where("id = ? AND push_channel = ? AND push_token_hash = ? AND push_token = ?", device.ID, device.PushChannel, *device.PushTokenHash, device.PushToken).
				Updates(ClearPushTokenUpdates()).Error; err != nil {
				return err
			}
		}
		return nil
	}); err != nil {
		return err
	}
	if db.Dialector.Name() == "mysql" {
		if err := db.Exec("UPDATE user_devices SET push_channel = '' WHERE push_channel IS NULL").Error; err != nil {
			return err
		}
		var column struct {
			IsNullable string `gorm:"column:is_nullable"`
		}
		if err := db.Raw(` 			SELECT IS_NULLABLE AS is_nullable 			FROM information_schema.COLUMNS 			WHERE TABLE_SCHEMA = DATABASE() 			  AND TABLE_NAME = 'user_devices' 			  AND COLUMN_NAME = 'push_channel' 		`).Scan(&column).Error; err != nil {
			return err
		}
		if strings.EqualFold(strings.TrimSpace(column.IsNullable), "YES") {
			if err := db.Exec("ALTER TABLE user_devices MODIFY COLUMN push_channel VARCHAR(20) NOT NULL DEFAULT ''").Error; err != nil {
				return err
			}
		}
	}
	if !migrator.HasIndex(&models.UserDevice{}, "uk_user_device") {
		if err := db.Exec("CREATE UNIQUE INDEX uk_user_device ON user_devices(user_id, device_id)").Error; err != nil {
			return fmt.Errorf("create uk_user_device: %w", err)
		}
	}
	if !migrator.HasIndex(&models.UserDevice{}, "uk_push_channel_token_hash") {
		if err := db.Exec("CREATE UNIQUE INDEX uk_push_channel_token_hash ON user_devices(push_channel, push_token_hash)").Error; err != nil {
			return fmt.Errorf("create uk_push_channel_token_hash: %w", err)
		}
	}
	return nil
}

func normalizeStoredPushDevice(tx *gorm.DB, device models.UserDevice) error {
	updates := map[string]interface{}{}
	deviceID := strings.TrimSpace(device.DeviceID)
	channelInput := strings.TrimSpace(device.PushChannel)
	tokenInput := strings.TrimSpace(device.PushToken)
	if tokenInput == "" && channelInput == "" {
		if device.PushTokenHash != nil || device.PushTokenUpdatedAt != nil {
			for key, value := range ClearPushTokenUpdates() {
				updates[key] = value
			}
		}
	} else {
		channel := NormalizeExplicitPushChannel(channelInput, device.DeviceType)
		if channel == PushChannelUnknown {
			return fmt.Errorf("user_devices id=%d has unknown push channel %q", device.ID, channelInput)
		}
		storageDeviceID := PushStorageDeviceID(deviceID, channel)
		if storageDeviceID == "" {
			return fmt.Errorf("user_devices id=%d has empty device id", device.ID)
		}
		updates["device_id"] = storageDeviceID
		updates["push_channel"] = channel
		if tokenInput == "" {
			for key, value := range ClearPushTokenUpdates() {
				updates[key] = value
			}
		} else {
			normalizedToken, tokenHash, err := NormalizePushToken(channel, device.PushToken)
			if err != nil {
				return fmt.Errorf("user_devices id=%d normalize token: %w", device.ID, err)
			}
			updates["push_token"] = normalizedToken
			updates["push_token_hash"] = tokenHash
		}
	}
	if len(updates) == 0 {
		return nil
	}
	return tx.Model(&models.UserDevice{}).Where("id = ?", device.ID).Updates(updates).Error
}

func mergeDuplicateStorageDevices(tx *gorm.DB, devices []models.UserDevice) error {
	groups := make(map[string][]models.UserDevice)
	order := make([]string, 0)
	for _, device := range devices {
		key := fmt.Sprintf("%d\x00%s", device.UserID, strings.TrimSpace(device.DeviceID))
		if _, exists := groups[key]; !exists {
			order = append(order, key)
		}
		groups[key] = append(groups[key], device)
	}
	for _, key := range order {
		group := groups[key]
		if len(group) <= 1 {
			continue
		}
		sort.SliceStable(group, func(i, j int) bool {
			return pushBindingNewer(group[i], group[j])
		})
		winner := group[0]
		for _, extra := range group[1:] {
			winnerKey := strings.TrimSpace(winner.E2EEPublicKey)
			extraKey := strings.TrimSpace(extra.E2EEPublicKey)
			if winnerKey != "" && extraKey != "" && winnerKey != extraKey {
				return fmt.Errorf("user_devices user=%d device=%s has conflicting E2EE public keys", winner.UserID, winner.DeviceID)
			}
			if winnerKey == "" && extraKey != "" {
				winner.E2EEPublicKey = extra.E2EEPublicKey
				winner.E2EEPublicKeyAlgo = extra.E2EEPublicKeyAlgo
				winner.E2EEPublicKeyUpdatedAt = extra.E2EEPublicKeyUpdatedAt
			}
			if strings.TrimSpace(winner.PushToken) == "" && strings.TrimSpace(extra.PushToken) != "" {
				winner.PushToken = extra.PushToken
				winner.PushTokenHash = extra.PushTokenHash
				winner.PushChannel = extra.PushChannel
				winner.PushTokenUpdatedAt = extra.PushTokenUpdatedAt
			}
			if strings.TrimSpace(winner.DeviceName) == "" {
				winner.DeviceName = extra.DeviceName
			}
			if strings.TrimSpace(winner.Brand) == "" {
				winner.Brand = extra.Brand
			}
			if strings.TrimSpace(winner.Model) == "" {
				winner.Model = extra.Model
			}
			if strings.TrimSpace(winner.AppVersion) == "" {
				winner.AppVersion = extra.AppVersion
			}
			if strings.TrimSpace(winner.Location) == "" {
				winner.Location = extra.Location
			}
		}
		if err := tx.Model(&models.UserDevice{}).Where("id = ?", winner.ID).Updates(map[string]interface{}{
			"device_name":                winner.DeviceName,
			"brand":                      winner.Brand,
			"model":                      winner.Model,
			"app_version":                winner.AppVersion,
			"location":                   winner.Location,
			"push_channel":               winner.PushChannel,
			"push_token":                 winner.PushToken,
			"push_token_hash":            winner.PushTokenHash,
			"push_token_updated_at":      winner.PushTokenUpdatedAt,
			"e2ee_public_key":            winner.E2EEPublicKey,
			"e2ee_public_key_algo":       winner.E2EEPublicKeyAlgo,
			"e2ee_public_key_updated_at": winner.E2EEPublicKeyUpdatedAt,
		}).Error; err != nil {
			return err
		}
		extraIDs := make([]uint64, 0, len(group)-1)
		for _, extra := range group[1:] {
			extraIDs = append(extraIDs, extra.ID)
		}
		if err := tx.Where("id IN ?", extraIDs).Delete(&models.UserDevice{}).Error; err != nil {
			return err
		}
	}
	return nil
}

func pushBindingNewer(left, right models.UserDevice) bool {
	leftTokenAt := time.Time{}
	rightTokenAt := time.Time{}
	if left.PushTokenUpdatedAt != nil {
		leftTokenAt = *left.PushTokenUpdatedAt
	}
	if right.PushTokenUpdatedAt != nil {
		rightTokenAt = *right.PushTokenUpdatedAt
	}
	if !leftTokenAt.Equal(rightTokenAt) {
		return leftTokenAt.After(rightTokenAt)
	}
	if !left.LastActive.Equal(right.LastActive) {
		return left.LastActive.After(right.LastActive)
	}
	return left.ID > right.ID
}
