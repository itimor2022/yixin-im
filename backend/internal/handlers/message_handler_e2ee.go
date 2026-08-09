// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"strings"
	"genericim/internal/models"
	"genericim/pkg/response"
)

// GetChatDeviceKeys returns all registered E2EE device public keys for a chat.
func (h *MessageHandler) GetChatDeviceKeys(c *gin.Context) {
	userUUID := c.GetString("user_id")
	chatUUID := strings.TrimSpace(c.Query("chat_id"))
	if chatUUID == "" {
		response.BadRequest(c, "缺少会话ID")
		return
	}

	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.Unauthorized(c, "请先登录")
		return
	}

	var chat models.Chat
	if err := h.db.Where("uuid = ?", chatUUID).First(&chat).Error; err != nil {
		response.NotFound(c, "会话不存在")
		return
	}

	var memberCount int64
	h.db.Model(&models.ChatMember{}).
		Where("chat_id = ? AND user_id = ?", chat.ID, user.ID).
		Count(&memberCount)
	if memberCount == 0 {
		response.Forbidden(c, "无权访问该会话")
		return
	}

	var memberIDs []uint64
	h.db.Model(&models.ChatMember{}).
		Where("chat_id = ?", chat.ID).
		Pluck("user_id", &memberIDs)
	if len(memberIDs) == 0 {
		response.Success(c, gin.H{
			"members": []string{},
			"devices": []gin.H{},
		})
		return
	}

	var users []models.User
	h.db.Where("id IN ?", memberIDs).Find(&users)
	userUUIDByID := make(map[uint64]string, len(users))
	memberUUIDs := make([]string, 0, len(users))
	for _, item := range users {
		userUUIDByID[item.ID] = item.UUID
		memberUUIDs = append(memberUUIDs, item.UUID)
	}

	var devices []models.UserDevice
	h.db.Where("user_id IN ? AND e2ee_public_key <> ''", memberIDs).Find(&devices)
	result := make([]gin.H, 0, len(devices))
	for _, device := range devices {
		if !isValidE2EEPublicJWK(device.E2EEPublicKey) {
			continue
		}
		userID := userUUIDByID[device.UserID]
		if userID == "" {
			continue
		}
		result = append(result, gin.H{
			"user_id":     userID,
			"device_id":   device.DeviceID,
			"device_type": device.DeviceType,
			"algo":        device.E2EEPublicKeyAlgo,
			"public_key":  device.E2EEPublicKey,
		})
	}
	response.Success(c, gin.H{
		"members": memberUUIDs,
		"devices": result,
	})
}
