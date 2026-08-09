// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"encoding/base64"
	"errors"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"strings"
	"time"
	"genericim/internal/models"
	"genericim/pkg/response"
)

const e2eeRecoveryRequestLifetime = 24 * time.Hour

type createE2EERecoveryRequestInput struct {
	PublicKey string `json:"public_key" binding:"required"`
	Algo      string `json:"algo"`
}

type approveE2EERecoveryRequestInput struct {
	EncryptedPayload string `json:"encrypted_payload" binding:"required"`
	PayloadAlgo      string `json:"payload_algo"`
}

func (h *UserHandler) currentE2EEUserAndDevice(c *gin.Context) (*models.User, string, bool) {
	userUUID := c.GetString("user_id")
	deviceID := strings.TrimSpace(c.GetString("device_id"))
	if deviceID == "" {
		response.BadRequest(c, "缺少设备标识")
		return nil, "", false
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return nil, "", false
	}
	return &user, deviceID, true
}

func (h *UserHandler) CreateE2EERecoveryRequest(c *gin.Context) {
	user, deviceID, ok := h.currentE2EEUserAndDevice(c)
	if !ok {
		return
	}
	var input createE2EERecoveryRequestInput
	if err := c.ShouldBindJSON(&input); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	publicKey := strings.TrimSpace(input.PublicKey)
	if len(publicKey) == 0 || len(publicKey) > 16384 || validateE2EEPublicJWK(publicKey) != nil {
		response.BadRequest(c, "恢复公钥格式无效")
		return
	}
	algo := strings.TrimSpace(input.Algo)
	if algo == "" {
		algo = "rsa-jwk-oaep-2048"
	}
	now := time.Now()
	// A device has only one actionable request. Older pending requests are
	// cancelled so a trusted device cannot approve a stale key accidentally.
	if err := h.db.Model(&models.E2EERecoveryRequest{}).
		Where("user_id = ? AND requester_device_id = ? AND status = ?", user.ID, deviceID, models.E2EERecoveryPending).
		Updates(map[string]interface{}{"status": models.E2EERecoveryCancelled, "updated_at": now}).Error; err != nil {
		response.ServerError(c, "取消旧恢复请求失败")
		return
	}
	request := models.E2EERecoveryRequest{
		RequestID: uuid.NewString(), UserID: user.ID, RequesterDeviceID: deviceID,
		RequesterPublicKey: publicKey, RequesterPublicKeyAlgo: algo,
		Status: models.E2EERecoveryPending, ExpiresAt: now.Add(e2eeRecoveryRequestLifetime),
		CreatedAt: now, UpdatedAt: now,
	}
	if err := h.db.Create(&request).Error; err != nil {
		response.ServerError(c, "创建恢复请求失败")
		return
	}
	response.Success(c, gin.H{
		"request_id": request.RequestID, "status": request.Status,
		"expires_at": request.ExpiresAt,
	})
}

func (h *UserHandler) ListE2EERecoveryRequests(c *gin.Context) {
	user, deviceID, ok := h.currentE2EEUserAndDevice(c)
	if !ok {
		return
	}
	now := time.Now()
	h.db.Model(&models.E2EERecoveryRequest{}).
		Where("user_id = ? AND status = ? AND expires_at <= ?", user.ID, models.E2EERecoveryPending, now).
		Updates(map[string]interface{}{"status": models.E2EERecoveryCancelled, "updated_at": now})

	var requests []models.E2EERecoveryRequest
	if err := h.db.Where(
		"user_id = ? AND((status = ? AND expires_at > ?) OR(requester_device_id = ? AND status = ?))",
		user.ID, models.E2EERecoveryPending, now, deviceID, models.E2EERecoveryApproved,
	).Order("created_at DESC").Find(&requests).Error; err != nil {
		response.ServerError(c, "读取恢复请求失败")
		return
	}
	deviceIDs := make([]string, 0, len(requests))
	for _, item := range requests {
		deviceIDs = append(deviceIDs, item.RequesterDeviceID)
	}
	var devices []models.UserDevice
	if len(deviceIDs) > 0 {
		h.db.Where("user_id = ? AND device_id IN ?", user.ID, deviceIDs).Find(&devices)
	}
	deviceByID := make(map[string]models.UserDevice, len(devices))
	for _, item := range devices {
		deviceByID[item.DeviceID] = item
	}
	result := make([]gin.H, 0, len(requests))
	for _, item := range requests {
		requester := deviceByID[item.RequesterDeviceID]
		row := gin.H{
			"request_id": item.RequestID, "status": item.Status,
			"requester_device_id":       item.RequesterDeviceID,
			"requester_device_name":     requester.DeviceName,
			"requester_device_type":     requester.DeviceType,
			"requester_public_key":      item.RequesterPublicKey,
			"requester_public_key_algo": item.RequesterPublicKeyAlgo,
			"source_device_id":          item.SourceDeviceID,
			"source_key_fingerprint":    item.SourceKeyFingerprint,
			"source_key_version":        item.SourceKeyVersion,
			"expires_at":                item.ExpiresAt, "created_at": item.CreatedAt,
			"is_requester": item.RequesterDeviceID == deviceID,
		}
		if item.RequesterDeviceID == deviceID && item.Status == models.E2EERecoveryApproved {
			row["encrypted_payload"] = item.EncryptedPayload
			row["payload_algo"] = item.PayloadAlgo
		}
		result = append(result, row)
	}
	response.Success(c, gin.H{"requests": result})
}

func (h *UserHandler) ApproveE2EERecoveryRequest(c *gin.Context) {
	user, deviceID, ok := h.currentE2EEUserAndDevice(c)
	if !ok {
		return
	}
	var input approveE2EERecoveryRequestInput
	if err := c.ShouldBindJSON(&input); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	payload := strings.TrimSpace(input.EncryptedPayload)
	if len(payload) == 0 || len(payload) > 131072 {
		response.BadRequest(c, "加密恢复包无效")
		return
	}
	if _, err := base64.RawURLEncoding.DecodeString(payload); err != nil {
		response.BadRequest(c, "加密恢复包编码无效")
		return
	}
	var source models.UserDevice
	if err := h.db.Where("user_id = ? AND device_id = ?", user.ID, deviceID).First(&source).Error; err != nil || strings.TrimSpace(source.E2EEPublicKey) == "" {
		response.BadRequest(c, "当前设备没有可用于恢复的加密身份")
		return
	}
	requestID := strings.TrimSpace(c.Param("id"))
	now := time.Now()
	updates := map[string]interface{}{
		"status": models.E2EERecoveryApproved, "source_device_id": deviceID,
		"source_key_fingerprint": source.E2EEPublicKeyFingerprint,
		"source_key_version":     source.E2EEKeyVersion,
		"encrypted_payload":      payload, "payload_algo": strings.TrimSpace(input.PayloadAlgo),
		"approved_at": &now, "updated_at": now,
	}
	result := h.db.Model(&models.E2EERecoveryRequest{}).
		Where("request_id = ? AND user_id = ? AND requester_device_id <> ? AND status = ? AND expires_at > ?",
			requestID, user.ID, deviceID, models.E2EERecoveryPending, now).
		Updates(updates)
	if result.Error != nil {
		response.ServerError(c, "批准恢复请求失败")
		return
	}
	if result.RowsAffected == 0 {
		response.NotFound(c, "恢复请求不存在、已处理或已过期")
		return
	}
	response.Success(c, gin.H{"request_id": requestID, "status": models.E2EERecoveryApproved})
}

func (h *UserHandler) ConsumeE2EERecoveryRequest(c *gin.Context) {
	user, deviceID, ok := h.currentE2EEUserAndDevice(c)
	if !ok {
		return
	}
	requestID := strings.TrimSpace(c.Param("id"))
	now := time.Now()
	result := h.db.Model(&models.E2EERecoveryRequest{}).
		Where("request_id = ? AND user_id = ? AND requester_device_id = ? AND status = ?",
			requestID, user.ID, deviceID, models.E2EERecoveryApproved).
		Updates(map[string]interface{}{
			"status": models.E2EERecoveryConsumed, "consumed_at": &now,
			"encrypted_payload": "", "updated_at": now,
		})
	if result.Error != nil {
		response.ServerError(c, "确认恢复结果失败")
		return
	}
	if result.RowsAffected == 0 {
		response.NotFound(c, "可用的恢复结果不存在")
		return
	}
	response.Success(c, gin.H{"request_id": requestID, "status": models.E2EERecoveryConsumed})
}

func (h *UserHandler) CancelE2EERecoveryRequest(c *gin.Context) {
	user, deviceID, ok := h.currentE2EEUserAndDevice(c)
	if !ok {
		return
	}
	requestID := strings.TrimSpace(c.Param("id"))
	now := time.Now()
	result := h.db.Model(&models.E2EERecoveryRequest{}).
		Where("request_id = ? AND user_id = ? AND requester_device_id = ? AND status IN ?",
			requestID, user.ID, deviceID, []string{models.E2EERecoveryPending, models.E2EERecoveryApproved}).
		Updates(map[string]interface{}{
			"status": models.E2EERecoveryCancelled, "encrypted_payload": "", "updated_at": now,
		})
	if result.Error != nil && !errors.Is(result.Error, gorm.ErrRecordNotFound) {
		response.ServerError(c, "取消恢复请求失败")
		return
	}
	if result.RowsAffected == 0 {
		response.NotFound(c, "恢复请求不存在或已结束")
		return
	}
	response.Success(c, gin.H{"request_id": requestID, "status": models.E2EERecoveryCancelled})
}
