// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"errors"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
	"regexp"
	"strings"
	"time"
	"genericim/internal/authsession"
	"genericim/internal/models"
	jwtpkg "genericim/pkg/jwt"
	"genericim/pkg/response"
)

var (
	iosLogicalDeviceIDPattern = regexp.MustCompile(`^ios:(idfv|install):[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)
	errIdentitySessionMissing = errors.New("current identity session not found")
	errIdentityConflict       = errors.New("target device identity already has an active session")
)

func bearerToken(c *gin.Context) string {
	parts := strings.SplitN(strings.TrimSpace(c.GetHeader("Authorization")), " ", 2)
	if len(parts) != 2 || !strings.EqualFold(parts[0], "Bearer") {
		return ""
	}
	return strings.TrimSpace(parts[1])
}

// MigrateDeviceIdentity moves only the current raw-token session to the new
// non-migratable iOS identity. It never renames or copies the old device row.
func (h *UserHandler) MigrateDeviceIdentity(c *gin.Context) {
	var req struct {
		NewDeviceID string `json:"new_device_id"`
		DeviceType  string `json:"device_type"`
		DeviceName  string `json:"device_name"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	newDeviceID := strings.ToLower(strings.TrimSpace(req.NewDeviceID))
	deviceType := strings.ToLower(strings.TrimSpace(req.DeviceType))
	if deviceType != "ios" || !iosLogicalDeviceIDPattern.MatchString(newDeviceID) || len(newDeviceID) > 100 {
		response.BadRequest(c, "iOS 设备标识格式错误")
		return
	}
	rawToken := bearerToken(c)
	if rawToken == "" {
		response.Unauthorized(c, "登录状态无效")
		return
	}
	claims, err := jwtpkg.ParseToken(rawToken)
	if err != nil {
		response.Unauthorized(c, "登录状态无效")
		return
	}
	oldDeviceID := strings.TrimSpace(claims.DeviceID)
	if oldDeviceID == newDeviceID {
		response.Success(c, gin.H{
			"migrated":  false,
			"token":     rawToken,
			"device_id": newDeviceID,
		})
		return
	}
	if h.cache == nil {
		response.ServerError(c, "设备身份迁移暂不可用，请重新登录")
		return
	}

	var user models.User
	if err := h.db.Where("uuid = ?", claims.UserID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	newToken, err := jwtpkg.GenerateToken(user.UUID, newDeviceID, claims.SessionVersion)
	if err != nil {
		response.ServerError(c, "生成新登录凭证失败")
		return
	}
	now := time.Now()
	deviceName := strings.TrimSpace(req.DeviceName)
	if deviceName == "" {
		deviceName = "iPhone"
	}

	err = h.db.Transaction(func(tx *gorm.DB) error {
		var current models.UserSession
		if err := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("user_id = ? AND token = ? AND device_id = ?", user.ID, rawToken, oldDeviceID).
			First(&current).Error; err != nil {
			if errors.Is(err, gorm.ErrRecordNotFound) {
				return errIdentitySessionMissing
			}
			return err
		}

		var targetCount int64
		if err := tx.Model(&models.UserSession{}).
			Where("user_id = ? AND device_id = ? AND token != ?", user.ID, newDeviceID, rawToken).
			Count(&targetCount).Error; err != nil {
			return err
		}
		if targetCount > 0 {
			return errIdentityConflict
		}

		var targetDevice models.UserDevice
		result := tx.Clauses(clause.Locking{Strength: "UPDATE"}).
			Where("user_id = ? AND device_id = ?", user.ID, newDeviceID).
			First(&targetDevice)
		if errors.Is(result.Error, gorm.ErrRecordNotFound) {
			targetDevice = models.UserDevice{
				UserID:     user.ID,
				DeviceID:   newDeviceID,
				DeviceType: deviceType,
				DeviceName: deviceName,
				IP:         c.ClientIP(),
				LastActive: now,
				CreatedAt:  now,
			}
			if err := tx.Create(&targetDevice).Error; err != nil {
				return err
			}
		} else if result.Error != nil {
			return result.Error
		} else if err := tx.Model(&targetDevice).Updates(map[string]interface{}{
			"device_type": deviceType,
			"device_name": deviceName,
			"ip":          c.ClientIP(),
			"last_active": now,
		}).Error; err != nil {
			return err
		}
		update := tx.Model(&models.UserSession{}).
			Where("id = ? AND user_id = ? AND token = ? AND device_id = ?", current.ID, user.ID, rawToken, oldDeviceID).
			Updates(map[string]interface{}{
				"token":       newToken,
				"device_id":   newDeviceID,
				"device_type": deviceType,
				"device_name": deviceName,
				"ip":          c.ClientIP(),
				"last_active": now,
			})
		if update.Error != nil {
			return update.Error
		}
		if update.RowsAffected != 1 {
			return errIdentitySessionMissing
		}
		return authsession.RevokeUserToken(c.Request.Context(), h.cache, user.UUID, rawToken)
	})
	if err != nil {
		switch {
		case errors.Is(err, errIdentityConflict):
			response.Error(c, deviceIdentityConflictCode, "device_identity_conflict")
		case errors.Is(err, errIdentitySessionMissing):
			response.Unauthorized(c, "当前会话已变化，请重新登录")
		default:
			response.ServerError(c, "设备身份迁移失败，请重新登录")
		}
		return
	}
	response.Success(c, gin.H{
		"migrated":      true,
		"token":         newToken,
		"device_id":     newDeviceID,
		"old_device_id": oldDeviceID,
	})
}
