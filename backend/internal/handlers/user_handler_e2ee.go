// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"crypto/sha256"
	"errors"
	"fmt"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"log"
	"strings"
	"time"
	"genericim/internal/models"
	"genericim/pkg/response"
)

type updateDeviceE2EEKeyRequest struct {
	PublicKey string `json:"public_key" binding:"required"`
	Algo      string `json:"algo"`
}

func e2eePublicKeyFingerprint(publicKey string) string {
	return fmt.Sprintf("%x", sha256.Sum256([]byte(strings.TrimSpace(publicKey))))
}

func e2eeDeviceKeySaveError(c *gin.Context, userUUID, deviceID string, err error) {
	log.Printf("[E2EE] save device public key failed user=%s device=%s err=%v", userUUID, deviceID, err)
	errText := strings.ToLower(strings.TrimSpace(err.Error()))
	if strings.Contains(errText, "unknown column") ||
		strings.Contains(errText, "doesn't exist") ||
		strings.Contains(errText, "e2ee_public_key") {
		response.ServerError(c, "数据库未升级，请重启后端后再试")
		return
	}
	response.ServerError(c, "保存设备公钥失败")
}

// UpdateCurrentDeviceE2EEKey stores the current device public key for message E2EE.
func (h *UserHandler) UpdateCurrentDeviceE2EEKey(c *gin.Context) {
	userUUID := c.GetString("user_id")
	deviceID := strings.TrimSpace(c.GetString("device_id"))
	if deviceID == "" {
		response.BadRequest(c, "缺少设备标识")
		return
	}

	var req updateDeviceE2EEKeyRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	publicKey := strings.TrimSpace(req.PublicKey)
	if publicKey == "" || len(publicKey) > 16384 {
		response.BadRequest(c, "设备公钥无效")
		return
	}
	if err := validateE2EEPublicJWK(publicKey); err != nil {
		response.BadRequest(c, "设备公钥格式无效")
		return
	}
	algo := strings.TrimSpace(req.Algo)
	if algo == "" {
		algo = "rsa-jwk-oaep-2048"
	}

	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	now := time.Now()
	fingerprint := e2eePublicKeyFingerprint(publicKey)
	var device models.UserDevice
	err := h.db.Where("user_id = ? AND device_id = ?", user.ID, deviceID).First(&device).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		device = models.UserDevice{
			UserID:                   user.ID,
			DeviceID:                 deviceID,
			DeviceType:               "unknown",
			LastActive:               now,
			CreatedAt:                now,
			E2EEPublicKey:            publicKey,
			E2EEPublicKeyAlgo:        algo,
			E2EEPublicKeyFingerprint: fingerprint,
			E2EEKeyVersion:           1,
			E2EEPublicKeyUpdatedAt:   &now,
		}
		if err := h.db.Create(&device).Error; err != nil {
			e2eeDeviceKeySaveError(c, userUUID, deviceID, err)
			return
		}
	} else if err != nil {
		response.ServerError(c, "读取设备信息失败")
		return
	} else {
		updatedAt := now
		keyVersion := device.E2EEKeyVersion
		if keyVersion == 0 || device.E2EEPublicKeyFingerprint != fingerprint {
			keyVersion++
		}
		if err := h.db.Model(&device).Updates(map[string]interface{}{
			"e2ee_public_key":             publicKey,
			"e2ee_public_key_algo":        algo,
			"e2ee_public_key_fingerprint": fingerprint,
			"e2ee_key_version":            keyVersion,
			"e2ee_public_key_updated_at":  &updatedAt,
			"last_active":                 now,
		}).Error; err != nil {
			e2eeDeviceKeySaveError(c, userUUID, deviceID, err)
			return
		}
		device.E2EEPublicKey = publicKey
		device.E2EEPublicKeyAlgo = algo
		device.E2EEPublicKeyUpdatedAt = &updatedAt
		if err := h.db.Where("id = ?", device.ID).First(&device).Error; err != nil {
			response.ServerError(c, "读取设备密钥版本失败")
			return
		}
	}
	response.Success(c, gin.H{
		"device_id":   deviceID,
		"algo":        algo,
		"fingerprint": fingerprint,
		"key_version": device.E2EEKeyVersion,
		"updated_at":  now,
	})
}

// RevokeCurrentDeviceE2EEKey removes only the current device public key. It
// intentionally leaves other devices and encrypted message payloads intact.
func (h *UserHandler) RevokeCurrentDeviceE2EEKey(c *gin.Context) {
	userUUID := c.GetString("user_id")
	deviceID := strings.TrimSpace(c.GetString("device_id"))
	if deviceID == "" {
		response.BadRequest(c, "缺少设备标识")
		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	now := time.Now()
	result := h.db.Model(&models.UserDevice{}).
		Where("user_id = ? AND device_id = ?", user.ID, deviceID).
		Updates(map[string]interface{}{
			"e2ee_public_key": "", "e2ee_public_key_algo": "",
			"e2ee_public_key_fingerprint": "",
			"e2ee_key_version":            gorm.Expr("e2ee_key_version + 1"),
			"e2ee_public_key_updated_at":  &now,
		})
	if result.Error != nil {
		response.ServerError(c, "撤销设备公钥失败")
		return
	}
	response.Success(c, gin.H{"device_id": deviceID, "revoked_at": now})
}
