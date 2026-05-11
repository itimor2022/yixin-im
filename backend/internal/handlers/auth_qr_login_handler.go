package handlers

import (
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"gaoranim/internal/authsession"
	"gaoranim/internal/cache"
	"gaoranim/internal/models"
	"gaoranim/pkg/jwt"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"
	"gorm.io/gorm"
)

const (
	qrLoginStatusPending   = "pending"
	qrLoginStatusConfirmed = "confirmed"
	qrLoginStatusExpired   = "expired"

	qrLoginPendingTTL   = 2 * time.Minute
	qrLoginConfirmedTTL = 30 * time.Second
	qrLoginKeyPrefix    = "qr_login:"
)

type QRLoginHandler struct {
	db    *gorm.DB
	cache *cache.Cache
}

func NewQRLoginHandler(db *gorm.DB, cache *cache.Cache) *QRLoginHandler {
	return &QRLoginHandler{db: db, cache: cache}
}

type qrLoginCreateRequest struct {
	DeviceID   string `json:"device_id" binding:"required"`
	DeviceType string `json:"device_type"`
	DeviceName string `json:"device_name"`
}

type qrLoginSession struct {
	Ticket      string     `json:"ticket"`
	Secret      string     `json:"secret"`
	Status      string     `json:"status"`
	DeviceID    string     `json:"device_id"`
	DeviceType  string     `json:"device_type"`
	DeviceName  string     `json:"device_name"`
	DeviceIP    string     `json:"device_ip"`
	UserUUID    string     `json:"user_uuid,omitempty"`
	Token       string     `json:"token,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
	ConfirmedAt *time.Time `json:"confirmed_at,omitempty"`
}

// Create 创建桌面端二维码登录票据
func (h *QRLoginHandler) Create(c *gin.Context) {
	var req qrLoginCreateRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}

	deviceType := strings.TrimSpace(req.DeviceType)
	if deviceType == "" {
		deviceType = "desktop"
	}

	deviceName := strings.TrimSpace(req.DeviceName)
	if deviceName == "" {
		deviceName = "Desktop"
	}

	ticket := uuid.New().String()
	secret := uuid.New().String()
	session := qrLoginSession{
		Ticket:     ticket,
		Secret:     secret,
		Status:     qrLoginStatusPending,
		DeviceID:   strings.TrimSpace(req.DeviceID),
		DeviceType: deviceType,
		DeviceName: deviceName,
		DeviceIP:   c.ClientIP(),
		CreatedAt:  time.Now(),
	}

	if err := h.cache.Set(c.Request.Context(), h.cacheKey(ticket), session, qrLoginPendingTTL); err != nil {
		response.ServerError(c, "创建二维码登录失败")
		return
	}

	response.Success(c, gin.H{
		"ticket":     ticket,
		"secret":     secret,
		"qr_text":    fmt.Sprintf("onechat://login/%s", ticket),
		"status":     qrLoginStatusPending,
		"expires_in": int(qrLoginPendingTTL.Seconds()),
	})
}

// GetStatus 获取二维码登录状态
func (h *QRLoginHandler) GetStatus(c *gin.Context) {
	ticket := strings.TrimSpace(c.Param("ticket"))
	secret := strings.TrimSpace(c.Query("secret"))
	if ticket == "" {
		response.BadRequest(c, "参数错误")
		return
	}

	session, exists, err := h.loadSession(c, ticket)
	if err != nil {
		response.ServerError(c, "获取二维码登录状态失败")
		return
	}
	if !exists {
		response.Success(c, gin.H{"status": qrLoginStatusExpired})
		return
	}

	data := gin.H{
		"status":       session.Status,
		"device_id":    session.DeviceID,
		"device_type":  session.DeviceType,
		"device_name":  session.DeviceName,
		"device_ip":    session.DeviceIP,
		"created_at":   session.CreatedAt,
		"confirmed_at": session.ConfirmedAt,
	}

	if secret != "" && secret == session.Secret && session.Status == qrLoginStatusConfirmed && session.Token != "" {
		data["token"] = session.Token
	}

	response.Success(c, data)
}

// Confirm 手机端确认登录桌面设备
func (h *QRLoginHandler) Confirm(c *gin.Context) {
	ticket := strings.TrimSpace(c.Param("ticket"))
	userUUID := c.GetString("user_id")
	if ticket == "" || userUUID == "" {
		response.BadRequest(c, "参数错误")
		return
	}

	session, exists, err := h.loadSession(c, ticket)
	if err != nil {
		response.ServerError(c, "确认登录失败")
		return
	}
	if !exists {
		response.Error(c, http.StatusNotFound, "二维码已过期")
		return
	}
	if session.Status != qrLoginStatusPending {
		response.BadRequest(c, "二维码已处理")
		return
	}

	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	sessionVersion := authsession.EnsureLoginSession(c.Request.Context(), h.cache, user.UUID)

	token, err := jwt.GenerateToken(user.UUID, session.DeviceID, sessionVersion)
	if err != nil {
		response.ServerError(c, "确认登录失败")
		return
	}

	now := time.Now()
	session.Status = qrLoginStatusConfirmed
	session.UserUUID = user.UUID
	session.Token = token
	session.ConfirmedAt = &now

	if err := h.cache.Set(c.Request.Context(), h.cacheKey(ticket), session, qrLoginConfirmedTTL); err != nil {
		response.ServerError(c, "确认登录失败")
		return
	}

	if err := recordUserLogin(h.db, user.ID, token, session.DeviceID, session.DeviceType, session.DeviceName, session.DeviceIP, now); err != nil {
		response.ServerError(c, "确认登录失败")
		return
	}

	response.SuccessWithMessage(c, "登录确认成功", gin.H{
		"status": qrLoginStatusConfirmed,
	})
}

func (h *QRLoginHandler) loadSession(c *gin.Context, ticket string) (*qrLoginSession, bool, error) {
	var session qrLoginSession
	err := h.cache.Get(c.Request.Context(), h.cacheKey(ticket), &session)
	if err == nil {
		return &session, true, nil
	}
	if errors.Is(err, redis.Nil) {
		return nil, false, nil
	}
	return nil, false, err
}

func (h *QRLoginHandler) recordDeviceLogin(userID uint64, deviceID, deviceType, deviceName, ip string, now time.Time) error {
	if strings.TrimSpace(deviceType) == "" {
		deviceType = "desktop"
	}
	if strings.TrimSpace(deviceName) == "" {
		deviceName = "Desktop"
	}

	var device models.UserDevice
	result := h.db.Where("user_id = ? AND device_id = ?", userID, deviceID).First(&device)
	if errors.Is(result.Error, gorm.ErrRecordNotFound) {
		device = models.UserDevice{
			UserID:     userID,
			DeviceID:   deviceID,
			DeviceType: deviceType,
			DeviceName: deviceName,
			IP:         ip,
			LastActive: now,
			CreatedAt:  now,
		}
		return h.db.Create(&device).Error
	}
	if result.Error != nil {
		return result.Error
	}

	return h.db.Model(&device).Updates(map[string]interface{}{
		"device_type": deviceType,
		"device_name": deviceName,
		"ip":          ip,
		"last_active": now,
	}).Error
}

func (h *QRLoginHandler) cacheKey(ticket string) string {
	return qrLoginKeyPrefix + ticket
}
