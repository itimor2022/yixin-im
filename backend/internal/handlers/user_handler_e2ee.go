package handlers

import (
	"errors"
	"log"
	"strings"
	"time"

	"gaoranim/internal/models"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type updateDeviceE2EEKeyRequest struct {
	PublicKey string `json:"public_key" binding:"required"`
	Algo      string `json:"algo"`
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
	var device models.UserDevice
	err := h.db.Where("user_id = ? AND device_id = ?", user.ID, deviceID).First(&device).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		device = models.UserDevice{
			UserID:                 user.ID,
			DeviceID:               deviceID,
			DeviceType:             "unknown",
			LastActive:             now,
			CreatedAt:              now,
			E2EEPublicKey:          publicKey,
			E2EEPublicKeyAlgo:      algo,
			E2EEPublicKeyUpdatedAt: &now,
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
		if err := h.db.Model(&device).Updates(map[string]interface{}{
			"e2ee_public_key":            publicKey,
			"e2ee_public_key_algo":       algo,
			"e2ee_public_key_updated_at": &updatedAt,
			"last_active":                now,
		}).Error; err != nil {
			e2eeDeviceKeySaveError(c, userUUID, deviceID, err)
			return
		}
		device.E2EEPublicKey = publicKey
		device.E2EEPublicKeyAlgo = algo
		device.E2EEPublicKeyUpdatedAt = &updatedAt
	}

	response.Success(c, gin.H{
		"device_id":  deviceID,
		"algo":       algo,
		"updated_at": now,
	})
}
