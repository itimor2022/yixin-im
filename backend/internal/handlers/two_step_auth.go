// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"crypto/rand"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"errors"
	"github.com/gin-gonic/gin"
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"
	"genericim/internal/authsession"
	"genericim/internal/cache"
	"genericim/internal/models"
	"genericim/pkg/jwt"
	"genericim/pkg/response"
)

const (
	twoStepRequiredCode      = 1007
	twoStepClientUpgradeCode = 1008
	twoStepChallengePrefix   = "auth:two-step:"
	twoStepMaxAttempts       = 5
	twoStepAttemptWindow     = 5 * time.Minute
)

type twoStepLoginChallenge struct {
	UserUUID   string    `json:"user_uuid"`
	DeviceID   string    `json:"device_id"`
	DeviceType string    `json:"device_type"`
	DeviceName string    `json:"device_name"`
	ClientIP   string    `json:"client_ip"`
	CreatedAt  time.Time `json:"created_at"`
}

type verifyTwoStepLoginRequest struct {
	Ticket   string `json:"ticket" binding:"required"`
	Password string `json:"password" binding:"required"`
}

func generateTwoStepTicket() (string, error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	return hex.EncodeToString(raw), nil
}

func validateTwoStepPassword(password string) error {
	if utf8.RuneCountInString(password) < 6 {
		return errors.New("两步验证密码至少6位")
	}
	// bcrypt

	if len([]byte(password)) > 72 {
		return errors.New("两步验证密码过长")
	}
	return nil
}

func hashTwoStepPassword(password string) (string, error) {
	if err := validateTwoStepPassword(password); err != nil {
		return "", err
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return "", err
	}
	return string(hash), nil
}

func isLegacyTwoStepHash(hash string) bool {
	hash = strings.TrimSpace(hash)
	if len(hash) != sha256.Size*2 {
		return false
	}
	_, err := hex.DecodeString(hash)
	return err == nil
}

func verifyTwoStepPassword(hash, password string) (valid bool, legacy bool) {
	hash = strings.TrimSpace(hash)
	if hash == "" {
		return false, false
	}
	if isLegacyTwoStepHash(hash) {
		digest := sha256.Sum256([]byte(password))
		expected, err := hex.DecodeString(hash)
		if err != nil || len(expected) != len(digest) {
			return false, true
		}
		return subtle.ConstantTimeCompare(expected, digest[:]) == 1, true
	}
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil, false
}

func (h *AuthHandler) issueTwoStepChallenge(
	c *gin.Context,
	user models.User,
	deviceID string,
	deviceType string,
	deviceName string,
	clientIP string,
) bool {
	var settings models.UserPrivacySetting
	if err := h.db.Where("user_id = ?", user.ID).First(&settings).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			return false
		}
		response.ServerError(c, "登录安全设置读取失败")
		return true
	}
	if !settings.TwoStepEnabled {
		return false
	}
	if strings.TrimSpace(settings.TwoStepPasswordHash) == "" {
		// Fail closed: an inconsistent enabled row must never become a bypass.
		response.ServerError(c, "两步验证配置异常，请先恢复两步验证密码")
		return true
	}
	if h.cache == nil {
		response.Error(c, http.StatusServiceUnavailable, "两步验证服务暂不可用")
		return true
	}

	ticket, err := generateTwoStepTicket()
	if err != nil {
		response.ServerError(c, "两步验证初始化失败")
		return true
	}
	payload := twoStepLoginChallenge{
		UserUUID:   user.UUID,
		DeviceID:   strings.TrimSpace(deviceID),
		DeviceType: strings.TrimSpace(deviceType),
		DeviceName: strings.TrimSpace(deviceName),
		ClientIP:   strings.TrimSpace(clientIP),
		CreatedAt:  time.Now(),
	}
	if err := h.cache.Set(
		c.Request.Context(),
		twoStepChallengePrefix+ticket,
		payload,
		cache.TTLVerifyCode,
	); err != nil {
		response.ServerError(c, "两步验证初始化失败")
		return true
	}
	c.JSON(http.StatusOK, response.Response{
		Code:    twoStepRequiredCode,
		Message: "请输入两步验证密码",
		Data: gin.H{
			"verify_ticket": ticket,
			"password_hint": strings.TrimSpace(settings.TwoStepPasswordHint),
			"expires_in":    int(cache.TTLVerifyCode / time.Second),
		},
	})
	return true
}

func (h *AuthHandler) VerifyTwoStepLogin(c *gin.Context) {
	if h.cache == nil {
		response.Error(c, http.StatusServiceUnavailable, "两步验证服务暂不可用")
		return
	}
	var req verifyTwoStepLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	req.Ticket = strings.TrimSpace(req.Ticket)
	key := twoStepChallengePrefix + req.Ticket

	var challenge twoStepLoginChallenge
	if err := h.cache.Get(c.Request.Context(), key, &challenge); err != nil {
		response.Error(c, 400, "验证已过期，请重新登录")
		return
	}
	allowed, err := h.cache.RateLimit(
		c.Request.Context(),
		"two-step:"+challenge.UserUUID+":"+challenge.DeviceID,
		twoStepMaxAttempts,
		twoStepAttemptWindow,
	)
	if err != nil {
		response.Error(c, http.StatusServiceUnavailable, "两步验证服务暂不可用")
		return
	}
	if !allowed {
		_ = h.cache.Delete(c.Request.Context(), key)
		response.Error(c, 429, "尝试次数过多，请稍后重新登录")
		return
	}

	var user models.User
	if err := h.db.Where("uuid = ?", challenge.UserUUID).First(&user).Error; err != nil {
		response.Error(c, 400, "验证已失效，请重新登录")
		return
	}
	if user.Status == models.UserStatusDisabled {
		response.Error(c, 403, "账号已被禁用")
		return
	}
	var settings models.UserPrivacySetting
	if err := h.db.Where("user_id = ?", user.ID).First(&settings).Error; err != nil ||
		!settings.TwoStepEnabled {
		response.Error(c, 400, "两步验证状态已变化，请重新登录")
		return
	}
	valid, legacy := verifyTwoStepPassword(settings.TwoStepPasswordHash, req.Password)
	if !valid {
		response.Error(c, 400, "两步验证密码错误")
		return
	}

	//
	var consumed twoStepLoginChallenge
	if err := h.cache.Take(c.Request.Context(), key, &consumed); err != nil ||
		consumed.UserUUID != challenge.UserUUID ||
		consumed.DeviceID != challenge.DeviceID {
		response.Error(c, 400, "验证已使用或已过期，请重新登录")
		return
	}
	if legacy {
		if upgraded, hashErr := hashTwoStepPassword(req.Password); hashErr == nil {
			_ = h.db.Model(&settings).Update("two_step_password_hash", upgraded).Error
		}
	}
	sessionVersion := authsession.EnsureLoginSession(c.Request.Context(), h.cache, user.UUID)
	authsession.ActivateDeviceSession(c.Request.Context(), h.cache, user.UUID, challenge.DeviceID)
	token, err := jwt.GenerateToken(user.UUID, challenge.DeviceID, sessionVersion)
	if err != nil {
		response.ServerError(c, "生成Token失败")
		return
	}
	loginIP := challenge.ClientIP
	if loginIP == "" {
		loginIP = c.ClientIP()
	}
	if err := recordUserLoginWithSecurityNotice(
		h.db,
		user,
		token,
		challenge.DeviceID,
		challenge.DeviceType,
		challenge.DeviceName,
		loginIP,
		time.Now(),
		h.loginHub,
		h.loginPush,
	); err != nil {
		response.ServerError(c, "记录登录会话失败")
		return
	}
	_ = h.db.Model(&user).Update("last_seen", time.Now()).Error
	response.Success(c, gin.H{"token": token, "user": user})
}

type enableTwoStepRequest struct {
	CurrentPassword string `json:"current_password" binding:"required"`
	Password        string `json:"password" binding:"required"`
	Hint            string `json:"hint"`
}

func (h *UserHandler) EnableTwoStep(c *gin.Context) {
	userUUID := strings.TrimSpace(c.GetString("user_id"))
	var req enableTwoStepRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	if !user.CheckPassword(req.CurrentPassword) {
		response.Error(c, 400, "当前账号密码错误")
		return
	}
	if user.CheckPassword(req.Password) {
		response.Error(c, 400, "两步验证密码不能与账号密码相同")
		return
	}
	hash, err := hashTwoStepPassword(req.Password)
	if err != nil {
		response.Error(c, 400, err.Error())
		return
	}
	var settings models.UserPrivacySetting
	if err := h.db.Where("user_id = ?", user.ID).First(&settings).Error; err != nil {
		if !errors.Is(err, gorm.ErrRecordNotFound) {
			response.ServerError(c, "读取安全设置失败")
			return
		}
		settings = defaultUserPrivacySetting(user.ID)
	}
	settings.TwoStepEnabled = true
	settings.TwoStepPasswordHash = hash
	settings.TwoStepPasswordHint = trimAndClampRunes(req.Hint, 100)
	if err := h.db.Save(&settings).Error; err != nil {
		response.ServerError(c, "开启两步验证失败")
		return
	}
	response.Success(c, gin.H{
		"two_step_enabled":       true,
		"two_step_password_hint": settings.TwoStepPasswordHint,
	})
}

type disableTwoStepRequest struct {
	Password string `json:"password" binding:"required"`
}

func (h *UserHandler) DisableTwoStep(c *gin.Context) {
	userUUID := strings.TrimSpace(c.GetString("user_id"))
	var req disableTwoStepRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	var settings models.UserPrivacySetting
	if err := h.db.Where("user_id = ?", user.ID).First(&settings).Error; err != nil {
		response.Error(c, 400, "两步验证未开启")
		return
	}
	valid, _ := verifyTwoStepPassword(settings.TwoStepPasswordHash, req.Password)
	if !settings.TwoStepEnabled || !valid {
		response.Error(c, 400, "两步验证密码错误")
		return
	}
	settings.TwoStepEnabled = false
	settings.TwoStepPasswordHash = ""
	settings.TwoStepPasswordHint = ""
	if err := h.db.Save(&settings).Error; err != nil {
		response.ServerError(c, "关闭两步验证失败")
		return
	}
	response.Success(c, gin.H{"two_step_enabled": false})
}

// UpdateTwoStep

func (h *UserHandler) UpdateTwoStep(c *gin.Context) {
	response.Error(c, twoStepClientUpgradeCode, "当前版本的两步验证不安全，请升级客户端后重新设置")
}
