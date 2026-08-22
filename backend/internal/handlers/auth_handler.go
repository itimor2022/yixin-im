// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"
	"genericim/internal/authsession"
	"genericim/internal/cache"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/jwt"
	"genericim/pkg/response"
)

// AuthHandler 认证处理器
type AuthHandler struct {
	db         *gorm.DB
	cache      *cache.Cache
	msgService *services.MessageService
	smsSvc     *services.SMSService
	emailSvc   *services.EmailService
	loginHub   loginSecurityHub
	loginPush  loginSecurityPusher
}

// NewAuthHandler 创建认证处理器
func NewAuthHandler(
	db *gorm.DB,
	cache *cache.Cache,
	msgService *services.MessageService,
	smsSvc *services.SMSService,
	emailSvc *services.EmailService,
	loginHub loginSecurityHub,
	loginPush loginSecurityPusher,
) *AuthHandler {
	return &AuthHandler{
		db:         db,
		cache:      cache,
		msgService: msgService,
		smsSvc:     smsSvc,
		emailSvc:   emailSvc,
		loginHub:   loginHub,
		loginPush:  loginPush,
	}
}

const deviceLockVerifyRequiredCode = 1001

type deviceLockTicketPayload struct {
	UserUUID   string `json:"user_uuid"`
	DeviceID   string `json:"device_id"`
	DeviceType string `json:"device_type"`
	DeviceName string `json:"device_name"`
	Code       string `json:"code"`
}

// CheckUsernameRequest 检查用户名请求（公开接口，无需认证）
type CheckUsernamePublicRequest struct {
	Username string `json:"username" binding:"required"`
}

// CheckUsername 检查用户名是否可用（公开接口，用于注册时检测）
func (h *AuthHandler) CheckUsername(c *gin.Context) {
	var req CheckUsernamePublicRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	username := strings.TrimSpace(req.Username)

	// 验证长度
	if len(username) < 3 {
		response.Success(c, gin.H{"available": false, "message": "用户名至少3位"})
		return
	}
	if len(username) > 20 {
		response.Success(c, gin.H{"available": false, "message": "用户名最多20位"})
		return
	}

	// 验证格式（只允许 a-z, 0-9, _）
	for _, char := range username {
		if !((char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z') || (char >= '0' && char <= '9') || char == '_') {
			response.Success(c, gin.H{"available": false, "message": "只能包含字母、数字和下划线"})
			return
		}
	}

	// 检查是否已被使用
	var count int64
	h.db.Model(&models.User{}).Where("username = ?", username).Count(&count)
	if count > 0 {
		response.Success(c, gin.H{"available": false, "message": "该用户名已被使用"})
		return
	}
	response.Success(c, gin.H{"available": true, "message": "用户名可用"})
}

// RegisterRequest 注册请求
type RegisterRequest struct {
	Username   string `json:"username" binding:"required,min=3,max=20"`
	Password   string `json:"password" binding:"required,min=6,max=20"`
	Nickname   string `json:"nickname" binding:"required,min=1,max=50"`
	Gender     string `json:"gender"`
	InviteCode string `json:"invite_code"` // 邀请码（可选）
	DeviceID   string `json:"device_id" binding:"required"`
	DeviceType string `json:"device_type"` // ios/android/web
	DeviceName string `json:"device_name"`
	Phone      string `json:"phone"`
	SMSCode    string `json:"sms_code"`
	Email      string `json:"email"`
	EmailCode  string `json:"email_code"`
}

const registerSMSCodePrefix = "auth:register:sms:"
const registerEmailCodePrefix = "auth:register:email:"

func registerSMSCodeKey(phone string) string {
	return registerSMSCodePrefix + phone
}

func registerEmailCodeKey(email string) string {
	return registerEmailCodePrefix + email
}

func isSixDigitSMSCode(code string) bool {
	if len(code) != 6 {
		return false
	}
	for _, char := range code {
		if char < '0' || char > '9' {
			return false
		}
	}
	return true
}

func normalizeRegisterPhoneCredentials(rawPhone, rawCode string) (
	phone string,
	code string,
	provided bool,
	valid bool,
) {
	rawPhone = strings.TrimSpace(rawPhone)
	code = strings.TrimSpace(rawCode)
	provided = rawPhone != "" || code != ""
	if !provided {
		return "", "", false, true
	}
	phone = services.NormalizeCNMobile(rawPhone)
	return phone, code, true, phone != "" && isSixDigitSMSCode(code)
}

func normalizeRegisterEmailCredentials(rawEmail, rawCode string) (
	email string,
	code string,
	provided bool,
	valid bool,
) {
	rawEmail = strings.TrimSpace(rawEmail)
	code = strings.TrimSpace(rawCode)
	provided = rawEmail != "" || code != ""
	if !provided {
		return "", "", false, true
	}
	email = services.NormalizeEmailAddress(rawEmail)
	return email, code, true, email != "" && isSixDigitSMSCode(code)
}

// SendRegisterCode sends a one-time code for optional phone-backed
// registration. The code is scoped away from bind/reset flows and is consumed
// only after the user transaction commits successfully.
func (h *AuthHandler) SendRegisterCode(c *gin.Context) {
	var req struct {
		Phone string `json:"phone" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "请输入手机号")
		return
	}
	phone := services.NormalizeCNMobile(req.Phone)
	if phone == "" {
		response.BadRequest(c, "请输入有效的中国大陆手机号")
		return
	}
	if h.smsSvc == nil || !h.smsSvc.CanSend() || h.cache == nil {
		response.Error(c, http.StatusServiceUnavailable, "短信服务未配置或未启用")
		return
	}
	var count int64
	if err := h.db.Model(&models.User{}).Where("phone = ?", phone).Count(&count).Error; err != nil {
		response.ServerError(c, "手机号校验失败")
		return
	}
	if count > 0 {
		response.Error(c, http.StatusConflict, "该手机号已注册")
		return
	}
	ctx := c.Request.Context()
	phoneAllowed, err := h.cache.RateLimit(ctx, "sms-register:phone:"+phone, 1, time.Minute)
	if err != nil || !phoneAllowed {
		response.Error(c, http.StatusTooManyRequests, "发送过于频繁，请稍后再试")
		return
	}
	ipAllowed, err := h.cache.RateLimit(ctx, "sms-register:ip:"+c.ClientIP(), 10, time.Hour)
	if err != nil || !ipAllowed {
		response.Error(c, http.StatusTooManyRequests, "发送次数过多，请稍后再试")
		return
	}
	code := services.GenPhoneBindCode()
	key := registerSMSCodeKey(phone)
	if err := h.cache.Set(ctx, key, code, cache.TTLVerifyCode); err != nil {
		response.ServerError(c, "验证码缓存失败")
		return
	}
	if err := h.smsSvc.SendOTP(ctx, phone, code); err != nil {
		_ = h.cache.Delete(ctx, key)
		response.Error(c, http.StatusBadGateway, "短信发送失败，请稍后重试")
		return
	}
	clearSMSVerifyAttempts(ctx, h.cache, "register-phone:"+phone)
	response.Success(c, gin.H{
		"message":    "验证码已发送",
		"expires_in": int(cache.TTLVerifyCode / time.Second),
	})
}

// VerifyRegisterCode validates the SMS code before the client advances to the
// profile step. Register performs the final validation and consumes the code
// only after the user transaction commits.
func (h *AuthHandler) VerifyRegisterCode(c *gin.Context) {
	var req struct {
		Phone   string `json:"phone" binding:"required"`
		SMSCode string `json:"sms_code" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "请填写手机号和短信验证码")
		return
	}

	phone, code, provided, valid :=
		normalizeRegisterPhoneCredentials(req.Phone, req.SMSCode)
	if !provided || !valid {
		response.Error(c, http.StatusBadRequest, "请填写有效手机号和短信验证码")
		return
	}
	if h.cache == nil {
		response.ServerError(c, "验证服务异常")
		return
	}
	key := registerSMSCodeKey(phone)
	var storedCode string
	if err := h.cache.Get(c.Request.Context(), key, &storedCode); err != nil ||
		storedCode == "" {
		response.Error(c, http.StatusBadRequest, "验证码已失效，请重新获取")
		return
	}
	if !allowSMSVerifyAttempt(
		c,
		h.cache,
		"register-phone:"+phone,
		key,
	) {
		return
	}
	if storedCode != code {
		response.Error(c, http.StatusBadRequest, "验证码错误")
		return
	}

	clearSMSVerifyAttempts(c.Request.Context(), h.cache, "register-phone:"+phone)
	response.Success(c, gin.H{"verified": true})
}

// SendRegisterEmailCode sends an email registration code. Debug console
// delivery stores no code outside Redis and never includes it in responses.
func (h *AuthHandler) SendRegisterEmailCode(c *gin.Context) {
	var req struct {
		Email string `json:"email" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "请输入邮箱地址")
		return
	}
	email := services.NormalizeEmailAddress(req.Email)
	if email == "" {
		response.BadRequest(c, "请输入有效的邮箱地址")
		return
	}
	if h.emailSvc == nil || !h.emailSvc.CanSend() || h.cache == nil {
		response.Error(c, http.StatusServiceUnavailable, "邮件服务未配置或未启用")
		return
	}
	var count int64
	if err := h.db.Model(&models.User{}).Where("email = ?", email).Count(&count).Error; err != nil {
		response.ServerError(c, "邮箱校验失败")
		return
	}
	if count > 0 {
		response.Error(c, http.StatusConflict, "该邮箱已注册")
		return
	}
	ctx := c.Request.Context()
	emailAllowed, err := h.cache.RateLimit(ctx, "email-register:address:"+email, 1, time.Minute)
	if err != nil || !emailAllowed {
		response.Error(c, http.StatusTooManyRequests, "发送过于频繁，请稍后再试")
		return
	}
	ipAllowed, err := h.cache.RateLimit(ctx, "email-register:ip:"+c.ClientIP(), 10, time.Hour)
	if err != nil || !ipAllowed {
		response.Error(c, http.StatusTooManyRequests, "发送次数过多，请稍后再试")
		return
	}
	code := services.GenPhoneBindCode()
	key := registerEmailCodeKey(email)
	if err := h.cache.Set(ctx, key, code, cache.TTLVerifyCode); err != nil {
		response.ServerError(c, "验证码缓存失败")
		return
	}
	if err := h.emailSvc.SendOTP(ctx, email, code); err != nil {
		_ = h.cache.Delete(ctx, key)
		response.Error(c, http.StatusBadGateway, "邮件发送失败，请稍后重试")
		return
	}
	clearSMSVerifyAttempts(ctx, h.cache, "register-email:"+email)
	response.Success(c, gin.H{
		"message":    "验证码已发送",
		"expires_in": int(cache.TTLVerifyCode / time.Second),
	})
}

type QuickRegisterRequest struct {
	DeviceID   string `json:"device_id" binding:"required,max=100"`
	DeviceType string `json:"device_type"`
	DeviceName string `json:"device_name"`
	RequestID  string `json:"request_id" binding:"required"`
}

const (
	quickRegisterWindow       = 24 * time.Hour
	quickRegisterReplayWindow = 10 * time.Minute
)

// QuickRegister 创建正式账号并立即登录，不向客户端暴露内部随机凭证。
func (h *AuthHandler) QuickRegister(c *gin.Context) {
	if !h.quickRegisterEnabled() {
		response.Error(c, http.StatusForbidden, "系统暂未开放一键注册登录")
		return
	}

	var req QuickRegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "设备信息或请求编号无效")
		return
	}
	req.DeviceID = strings.TrimSpace(req.DeviceID)
	req.DeviceType = strings.TrimSpace(req.DeviceType)
	req.DeviceName = strings.TrimSpace(req.DeviceName)
	req.RequestID = strings.TrimSpace(req.RequestID)
	if req.DeviceID == "" || len(req.DeviceID) > 100 {
		response.BadRequest(c, "设备信息无效")
		return
	}
	if _, err := uuid.Parse(req.RequestID); err != nil {
		response.BadRequest(c, "请求编号无效")
		return
	}
	deviceHash := hashQuickRegisterValue(req.DeviceID)
	var existing models.QuickRegistration
	if err := h.db.Where("request_id = ?", req.RequestID).First(&existing).Error; err == nil {
		if existing.DeviceHash != deviceHash {
			response.Error(c, http.StatusConflict, "该请求编号已被使用")
			return
		}
		if time.Since(existing.CreatedAt) > quickRegisterReplayWindow {
			response.Error(c, http.StatusConflict, "一键注册请求已过期")
			return
		}
		var user models.User
		if err := h.db.First(&user, existing.UserID).Error; err != nil {
			response.ServerError(c, "恢复一键注册结果失败")
			return
		}
		if user.Status == models.UserStatusDisabled {
			response.Error(c, http.StatusForbidden, "账号已被禁用")
			return
		}
		h.issueUserLoginResponse(c, user, req.DeviceID, req.DeviceType, req.DeviceName, false, gin.H{
			"needs_credentials_setup": !user.CredentialsInitialized,
			"idempotent_replay":       true,
		})
		return
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		response.ServerError(c, "一键注册失败")
		return
	}
	if !h.checkQuickRegisterLimits(c, deviceHash) {
		return
	}

	username, password, nickname, err := h.newQuickRegisterCredentials()
	if err != nil {
		response.ServerError(c, "生成账号失败")
		return
	}
	payload, err := json.Marshal(RegisterRequest{
		Username:   username,
		Password:   password,
		Nickname:   nickname,
		DeviceID:   req.DeviceID,
		DeviceType: req.DeviceType,
		DeviceName: req.DeviceName,
	})
	if err != nil {
		response.ServerError(c, "生成账号失败")
		return
	}
	c.Set("quick_register", true)
	c.Set("quick_register_request_id", req.RequestID)
	c.Set("quick_register_device_hash", deviceHash)
	c.Request.Body = io.NopCloser(bytes.NewReader(payload))
	h.Register(c)
}

func (h *AuthHandler) quickRegisterEnabled() bool {
	settings := map[string]string{}
	var rows []models.SystemSetting
	h.db.Where("`key` IN ?", []string{
		models.SettingAllowRegister,
		models.SettingAllowQuickRegister,
		models.SettingRequireInviteCode,
	}).Find(&rows)
	for _, row := range rows {
		settings[row.Key] = row.Value
	}
	return !isSystemSettingFalse(settings[models.SettingAllowRegister]) &&
		isSystemSettingTrue(settings[models.SettingAllowQuickRegister]) &&
		!isSystemSettingTrue(settings[models.SettingRequireInviteCode])
}

func (h *AuthHandler) checkQuickRegisterLimits(c *gin.Context, deviceHash string) bool {
	if h.cache == nil {
		return true
	}
	deviceLimit := h.quickRegisterLimit(models.SettingQuickRegisterDeviceLimit, 1, 20)
	ipLimit := h.quickRegisterLimit(models.SettingQuickRegisterIPLimit, 5, 1000)
	ipHash := hashQuickRegisterValue(strings.TrimSpace(c.ClientIP()))
	checks := []struct {
		key   string
		limit int
	}{
		{key: "quick-register:device:" + deviceHash, limit: deviceLimit},
		{key: "quick-register:ip:" + ipHash, limit: ipLimit},
	}
	for _, check := range checks {
		count, err := h.cache.RateLimitCount(c.Request.Context(), check.key, quickRegisterWindow)
		if err == nil && count >= int64(check.limit) {
			response.TooManyRequests(c, "一键注册次数过多，请稍后再试")
			return false
		}
	}
	for _, check := range checks {
		_ = h.cache.RecordRateLimit(c.Request.Context(), check.key, quickRegisterWindow)
	}
	return true
}

func (h *AuthHandler) quickRegisterLimit(key string, fallback, maximum int) int {
	var setting models.SystemSetting
	if err := h.db.Where("`key` = ?", key).First(&setting).Error; err != nil {
		return fallback
	}
	value, err := strconv.Atoi(strings.TrimSpace(setting.Value))
	if err != nil || value < 1 || value > maximum {
		return fallback
	}
	return value
}

func hashQuickRegisterValue(value string) string {
	sum := sha256.Sum256([]byte(value))
	return hex.EncodeToString(sum[:])
}

func (h *AuthHandler) newQuickRegisterCredentials() (string, string, string, error) {
	for attempt := 0; attempt < 5; attempt++ {
		randomBytes := make([]byte, 12)
		if _, err := rand.Read(randomBytes); err != nil {
			return "", "", "", err
		}
		username, password, nickname := formatQuickRegisterCredentials(randomBytes)
		var count int64
		if err := h.db.Model(&models.User{}).Where("username = ?", username).Count(&count).Error; err != nil {
			return "", "", "", err
		}
		if count == 0 {
			return username, password, nickname, nil
		}
	}
	return "", "", "", errors.New("failed to allocate quick registration username")
}

func formatQuickRegisterCredentials(randomBytes []byte) (string, string, string) {
	randomText := hex.EncodeToString(randomBytes)
	return "q_" + randomText[:12],
		randomText[:20],
		"用户" + strings.ToUpper(randomText[18:24])
}

// Register 注册
func (h *AuthHandler) Register(c *gin.Context) {
	isSettingTrue := func(v string) bool {
		s := strings.ToLower(strings.TrimSpace(v))
		return s == "true" || s == "1"
	}
	isSettingFalse := func(v string) bool {
		s := strings.ToLower(strings.TrimSpace(v))
		return s == "false" || s == "0"
	}

	// 检查是否允许注册
	var allowRegisterSetting models.SystemSetting
	if err := h.db.Where("`key` = ?", models.SettingAllowRegister).First(&allowRegisterSetting).Error; err == nil {
		if isSettingFalse(allowRegisterSetting.Value) {
			response.Error(c, 403, "系统暂不开放注册，请联系管理员")
			return
		}
	}

	var req RegisterRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误：用户名3-20位，密码6-20位")
		return
	}
	req.Username = strings.TrimSpace(req.Username)
	req.Nickname = strings.TrimSpace(req.Nickname)
	req.InviteCode = strings.TrimSpace(req.InviteCode)
	phone, smsCode, phoneProvided, phoneCredentialsValid :=
		normalizeRegisterPhoneCredentials(req.Phone, req.SMSCode)
	req.Phone = phone
	req.SMSCode = smsCode
	email, emailCode, emailProvided, emailCredentialsValid :=
		normalizeRegisterEmailCredentials(req.Email, req.EmailCode)
	req.Email = email
	req.EmailCode = emailCode
	if len(req.Username) < 3 || len(req.Username) > 20 {
		response.Error(c, 400, "用户名长度需为3-20位")
		return
	}
	for _, char := range req.Username {
		if !((char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z') || (char >= '0' && char <= '9') || char == '_') {
			response.Error(c, 400, "用户名只能包含字母、数字和下划线")
			return
		}
	}
	if req.Nickname == "" {
		response.Error(c, 400, "昵称不能为空")
		return
	}
	quickRegister := c.GetBool("quick_register")
	registerCodeKey := ""
	registerAttemptKey := ""
	if !quickRegister && phoneProvided && emailProvided {
		response.Error(c, 400, "手机号和邮箱注册方式只能选择一种")
		return
	}
	if !quickRegister && phoneProvided {
		if !phoneCredentialsValid {
			response.Error(c, 400, "请填写有效手机号和短信验证码")
			return
		}
		if h.cache == nil {
			response.ServerError(c, "验证服务异常")
			return
		}
		registerCodeKey = registerSMSCodeKey(req.Phone)
		registerAttemptKey = "register-phone:" + req.Phone
		var storedCode string
		if err := h.cache.Get(c.Request.Context(), registerCodeKey, &storedCode); err != nil || storedCode == "" {
			response.Error(c, 400, "验证码已失效，请重新获取")
			return
		}
		if !allowSMSVerifyAttempt(c, h.cache, registerAttemptKey, registerCodeKey) {
			return
		}
		if storedCode != req.SMSCode {
			response.Error(c, 400, "验证码错误")
			return
		}
		var phoneTaken int64
		if err := h.db.Model(&models.User{}).Where("phone = ?", req.Phone).Count(&phoneTaken).Error; err != nil {
			response.ServerError(c, "手机号校验失败")
			return
		}
		if phoneTaken > 0 {
			response.Error(c, 409, "该手机号已注册")
			return
		}
	}
	if !quickRegister && emailProvided {
		if !emailCredentialsValid {
			response.Error(c, 400, "请填写有效邮箱和6位邮箱验证码")
			return
		}
		if h.cache == nil {
			response.ServerError(c, "验证服务异常")
			return
		}
		registerCodeKey = registerEmailCodeKey(req.Email)
		registerAttemptKey = "register-email:" + req.Email
		var storedCode string
		if err := h.cache.Get(c.Request.Context(), registerCodeKey, &storedCode); err != nil || storedCode == "" {
			response.Error(c, 400, "验证码已失效，请重新获取")
			return
		}
		if !allowSMSVerifyAttempt(c, h.cache, registerAttemptKey, registerCodeKey) {
			return
		}
		if storedCode != req.EmailCode {
			response.Error(c, 400, "验证码错误")
			return
		}
		var emailTaken int64
		if err := h.db.Model(&models.User{}).Where("email = ?", req.Email).Count(&emailTaken).Error; err != nil {
			response.ServerError(c, "邮箱校验失败")
			return
		}
		if emailTaken > 0 {
			response.Error(c, 409, "该邮箱已注册")
			return
		}
	}
	requireGender := !quickRegister
	var requireGenderSetting models.SystemSetting
	if !quickRegister {
		if err := h.db.Where("`key` = ?", models.SettingRequireGenderOnRegister).First(&requireGenderSetting).Error; err == nil {
			requireGender = !isSettingFalse(requireGenderSetting.Value)
		}
	}
	gender, validGender := resolveRegisterGender(req.Gender, requireGender)
	if !validGender {
		response.Error(c, 400, "请选择性别")
		return
	}
	req.Gender = gender

	// 检查是否强制填写邀请码
	var requireInviteSetting models.SystemSetting
	if !quickRegister {
		if err := h.db.Where("`key` = ?", models.SettingRequireInviteCode).First(&requireInviteSetting).Error; err == nil {
			if isSettingTrue(requireInviteSetting.Value) && req.InviteCode == "" {
				response.Error(c, 400, "当前注册必须填写邀请码")
				return
			}
		}
	}

	// 检查用户名是否已存在
	var existUser models.User
	if err := h.db.Where("username = ?", req.Username).First(&existUser).Error; err == nil {
		response.Error(c, 400, "用户名已存在")
		return
	}

	// 先预校验邀请码，避免先建号再失败导致用户名被占用。
	// 优先按「用户个人邀请码（10 位数字）」匹配；命中即视为合法，后置事务
	// 里会把它解析为 recommender_id。若不匹配再走「客服邀请码（hex）」校验，
	// 这样既兼容 require_invite_code 强制场景下用户填的是他人个人码的情况，
	// 也保留对原有客服邀请码链路的支持。
	if req.InviteCode != "" {
		if models.IsValidUserInviteCode(req.InviteCode) {
			if models.FindUserIDByInviteCode(h.db, req.InviteCode) == 0 {
				response.Error(c, 400, "邀请码无效")
				return
			}
		} else {
			result := ValidateInviteCode(h.db, req.InviteCode)
			if result != nil && !result.Valid {
				response.Error(c, 400, result.Message)
				return
			}
		}
	}

	// 创建用户（主流程事务化，避免出现“返回失败但部分写入成功”）
	user := models.User{
		UUID:                   uuid.New().String(),
		Username:               req.Username,
		Nickname:               req.Nickname,
		Gender:                 req.Gender,
		RegisterSource:         models.UserRegisterSourceManual,
		CredentialsInitialized: true,
		Status:                 1,
		LastSeen:               time.Now(),
	}
	if req.Phone != "" {
		phone := req.Phone
		user.Phone = &phone
	}
	if req.Email != "" {
		email := req.Email
		user.Email = &email
	}
	if quickRegister {
		user.RegisterSource = models.UserRegisterSourceQuick
		user.CredentialsInitialized = false
	}

	// 设置密码
	if err := user.SetPassword(req.Password); err != nil {
		response.ServerError(c, "注册失败")
		return
	}

	// 提前预解析邀请码：在事务开启前先用只读连接匹配用户个人邀请码，
	// 解析出 recommenderID 后直接写入 user 结构体，这样后续 tx.Create(&user)
	// 会把 recommender_id 一并写入，避免后置赋值后被遗忘（持久化丢失）。
	var pendingRecommenderID uint64
	pendingInviteValid := false
	if req.InviteCode != "" {
		if recommenderID := models.FindUserIDByInviteCode(h.db, req.InviteCode); recommenderID > 0 {
			pendingRecommenderID = recommenderID
			user.RecommenderID = &pendingRecommenderID
			pendingInviteValid = true
		}
	}

	tx := h.db.Begin()
	if tx.Error != nil {
		response.ServerError(c, "注册失败")
		return
	}
	ensureUserChat := func(chatID uint64, sortTime time.Time) error {
		var count int64
		if err := tx.Model(&models.UserChat{}).Where("chat_id = ? AND user_id = ?", chatID, user.ID).Count(&count).Error; err != nil {
			return err
		}
		if count > 0 {
			return nil
		}
		return tx.Create(&models.UserChat{
			UserID:   user.ID,
			ChatID:   chatID,
			SortTime: sortTime,
		}).Error
	}
	if err := tx.Create(&user).Error; err != nil {
		tx.Rollback()
		response.ServerError(c, "注册失败")
		return
	}

	// 如果用户通过个人邀请码注册（已有 recommender_id），把直接邀请人
	// 以及该邀请人的 bind_id 客服加为新用户的好友。不沿 recommender 链
	// 或 bind_id 链继续向上递归（业务侧只需要加直接上级这一层）。
	if user.RecommenderID != nil {
		if err := ensureDirectRecommenderAndBindAsContacts(tx, &user, time.Now()); err != nil {
			tx.Rollback()
			response.ServerError(c, "注册失败")
			return
		}
	}
	// 为新用户生成唯一个人邀请码（10 位数字，首位 1-9）。
	// 最多重试 5 次以应对极端冲突，仍失败则降级留空。
	for retry := 0; retry < 5; retry++ {
		generated, genErr := models.GenerateUserInviteCode()
		if genErr != nil {
			break
		}
		updateErr := tx.Model(&models.User{}).
			Where("id = ? AND invite_code = ?", user.ID, "").
			Update("invite_code", generated).Error
		if updateErr == nil {
			user.InviteCode = generated
			break
		}
		// 仅处理唯一索引冲突，其它错误直接退出。
		if !strings.Contains(updateErr.Error(), "Duplicate") &&
			!strings.Contains(updateErr.Error(), "1062") {
			break
		}
	}
	if quickRegister {
		if err := tx.Model(&user).Update("credentials_initialized", false).Error; err != nil {
			tx.Rollback()
			response.ServerError(c, "注册失败")
			return
		}
		user.CredentialsInitialized = false
	}
	shortID := models.BuildUserShortID(user.ID)
	if err := tx.Model(&models.User{}).Where("id = ? AND short_id IS NULL", user.ID).Update("short_id", shortID).Error; err != nil {
		tx.Rollback()
		response.ServerError(c, "注册失败")
		return
	}
	user.ShortID = &shortID
	if err := tx.Create(&models.UserPrivacySetting{
		UserID:                user.ID,
		LastSeenVisibility:    "所有人",
		PhoneVisibility:       "联系人",
		GroupInvitePermission: "所有人",
		AllowPhoneSearch:      true,
		AllowShortIDSearch:    true,
		SendReadReceipts:      true,
		ShowTypingStatus:      true,
		DeviceLockEnabled:     false,
		AutoDeleteAccount:     "6 个月",
	}).Error; err != nil {
		tx.Rollback()
		response.ServerError(c, "注册失败")
		return
	}
	if quickRegister {
		if err := tx.Create(&models.QuickRegistration{
			RequestID:  c.GetString("quick_register_request_id"),
			DeviceHash: c.GetString("quick_register_device_hash"),
			UserID:     user.ID,
		}).Error; err != nil {
			tx.Rollback()
			response.Error(c, http.StatusConflict, "一键注册请求已处理，请重试")
			return
		}
	}

	// 处理邀请码。优先匹配用户个人邀请码（10 位数字），命中则推荐人已在上方预解析完成；
	// 未命中再走客服邀请码流程。
	boundService := false
	var inviteWelcomeInfo *InviteWelcomeInfo
	if req.InviteCode != "" && !pendingInviteValid {
		result := ProcessInviteCode(tx, req.InviteCode, user.ID)
		if result != nil && !result.Valid {
			tx.Rollback()
			response.Error(c, 400, result.Message)
			return
		}
		if result != nil && result.ServiceUserID > 0 {
			boundService = true
			inviteWelcomeInfo = result.WelcomeInfo
		}
	}

	inviteRegisterBindOnly := false
	if boundService {
		var bindOnlySetting models.SystemSetting
		if err := h.db.Where("`key` = ?", models.SettingInviteRegisterBindOnly).First(&bindOnlySetting).Error; err == nil {
			inviteRegisterBindOnly = isSettingTrue(bindOnlySetting.Value)
		}
	}

	// 检查是否需要强制关注官方用户
	var followOfficialSetting models.SystemSetting
	if !(boundService && inviteRegisterBindOnly) {
		if err := h.db.Where("`key` = ?", models.SettingNewUserFollowOfficial).First(&followOfficialSetting).Error; err == nil {
			if isSettingTrue(followOfficialSetting.Value) {
				// 获取启用中的官方用户
				var officialUsers []models.OfficialUser
				if err := tx.Where("is_service_enabled = ?", true).Find(&officialUsers).Error; err != nil {
					tx.Rollback()
					response.ServerError(c, "注册失败")
					return
				}
				for _, official := range officialUsers {
					// 跳过自己
					if official.UserID == user.ID {
						continue
					}

					// 创建（或修复）双向联系人关系
					if _, err := ensureContactRelation(tx, user.ID, official.UserID, time.Now()); err != nil {
						tx.Rollback()
						response.ServerError(c, "注册失败")
						return
					}
					if _, err := ensureContactRelation(tx, official.UserID, user.ID, time.Now()); err != nil {
						tx.Rollback()
						response.ServerError(c, "注册失败")
						return
					}
				}
			}
		}
	}

	// 检查是否需要强制加入官方群组
	var joinGroupSetting models.SystemSetting
	if err := h.db.Where("`key` = ?", models.SettingNewUserJoinGroup).First(&joinGroupSetting).Error; err == nil {
		if isSettingTrue(joinGroupSetting.Value) {
			var officialGroups []models.OfficialGroup
			if err := tx.Find(&officialGroups).Error; err != nil {
				tx.Rollback()
				response.ServerError(c, "注册失败")
				return
			}
			now := time.Now()
			for _, og := range officialGroups {
				var exists int64
				if err := tx.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id = ?", og.ChatID, user.ID).Count(&exists).Error; err != nil {
					tx.Rollback()
					response.ServerError(c, "注册失败")
					return
				}
				if exists > 0 {
					if err := ensureUserChat(og.ChatID, now); err != nil {
						tx.Rollback()
						response.ServerError(c, "注册失败")
						return
					}
					continue
				}
				if err := tx.Create(&models.ChatMember{
					ChatID:   og.ChatID,
					UserID:   user.ID,
					Role:     0,
					JoinedAt: now,
				}).Error; err != nil {
					tx.Rollback()
					response.ServerError(c, "注册失败")
					return
				}
				if err := ensureUserChat(og.ChatID, now); err != nil {
					tx.Rollback()
					response.ServerError(c, "注册失败")
					return
				}
				if err := tx.Model(&models.Chat{}).Where("id = ?", og.ChatID).Update("member_count", gorm.Expr("member_count + 1")).Error; err != nil {
					tx.Rollback()
					response.ServerError(c, "注册失败")
					return
				}
			}
		}
	}

	// 检查是否需要强制订阅官方频道
	var joinChannelSetting models.SystemSetting
	if err := h.db.Where("`key` = ?", models.SettingNewUserJoinChannel).First(&joinChannelSetting).Error; err == nil {
		if isSettingTrue(joinChannelSetting.Value) {
			var officialChannels []models.OfficialChannel
			if err := tx.Find(&officialChannels).Error; err != nil {
				tx.Rollback()
				response.ServerError(c, "注册失败")
				return
			}
			now := time.Now()
			for _, oc := range officialChannels {
				var exists int64
				if err := tx.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id = ?", oc.ChatID, user.ID).Count(&exists).Error; err != nil {
					tx.Rollback()
					response.ServerError(c, "注册失败")
					return
				}
				if exists > 0 {
					if err := ensureUserChat(oc.ChatID, now); err != nil {
						tx.Rollback()
						response.ServerError(c, "注册失败")
						return
					}
					continue
				}
				if err := tx.Create(&models.ChatMember{
					ChatID:   oc.ChatID,
					UserID:   user.ID,
					Role:     0,
					JoinedAt: now,
				}).Error; err != nil {
					tx.Rollback()
					response.ServerError(c, "注册失败")
					return
				}
				if err := ensureUserChat(oc.ChatID, now); err != nil {
					tx.Rollback()
					response.ServerError(c, "注册失败")
					return
				}
				if err := tx.Model(&models.Chat{}).Where("id = ?", oc.ChatID).Update("member_count", gorm.Expr("member_count + 1")).Error; err != nil {
					tx.Rollback()
					response.ServerError(c, "注册失败")
					return
				}
			}
		}
	}
	if err := tx.Commit().Error; err != nil {
		tx.Rollback()
		response.ServerError(c, "注册失败")
		return
	}
	if registerCodeKey != "" {
		_ = h.cache.Delete(c.Request.Context(), registerCodeKey)
		clearSMSVerifyAttempts(c.Request.Context(), h.cache, registerAttemptKey)
	}

	// 事务提交后再发送欢迎语，避免提交前外发消息造成不一致
	SendInviteWelcomeMessageByInfo(h.db, h.msgService, inviteWelcomeInfo)
	extra := gin.H{}
	if quickRegister {
		extra["needs_credentials_setup"] = true
	}
	h.issueUserLoginResponse(c, user, req.DeviceID, req.DeviceType, req.DeviceName, true, extra)
}

func (h *AuthHandler) issueUserLoginResponse(
	c *gin.Context,
	user models.User,
	deviceID string,
	deviceType string,
	deviceName string,
	newAccount bool,
	extra gin.H,
) {
	var sessionVersion int64
	if newAccount {
		sessionVersion = authsession.IssueUserSession(c.Request.Context(), h.cache, user.UUID)
	} else {
		sessionVersion = authsession.EnsureLoginSession(c.Request.Context(), h.cache, user.UUID)
	}
	authsession.ActivateDeviceSession(c.Request.Context(), h.cache, user.UUID, deviceID)
	token, err := jwt.GenerateToken(user.UUID, deviceID, sessionVersion)
	if err != nil {
		response.ServerError(c, "生成Token失败")
		return
	}
	if err := recordUserLoginWithSecurityNotice(h.db, user, token, deviceID, deviceType, deviceName, c.ClientIP(), time.Now(), h.loginHub, h.loginPush); err != nil {
		response.ServerError(c, "记录登录会话失败")
		return
	}
	_ = h.db.Model(&user).Update("last_seen", time.Now()).Error
	resp := gin.H{"token": token, "user": user}
	for key, value := range extra {
		resp[key] = value
	}
	response.Success(c, resp)
}

func resolveRegisterGender(value string, required bool) (string, bool) {
	raw := strings.TrimSpace(value)
	if raw == "" {
		if required {
			return "", false
		}
		return "unknown", true
	}
	gender := normalizeGender(raw)
	if gender != "male" && gender != "female" {
		return "", false
	}
	return gender, true
}

// LoginRequest 登录请求
type LoginRequest struct {
	Username   string `json:"username" binding:"required"`
	Password   string `json:"password" binding:"required"`
	DeviceID   string `json:"device_id" binding:"required"`
	DeviceType string `json:"device_type"` // ios/android/web
	DeviceName string `json:"device_name"`
}

func bannedLoginResponse(user models.User) (string, gin.H) {
	reason := strings.TrimSpace(user.BanReason)
	if reason == "" {
		reason = "违反平台使用规则"
	}
	message := fmt.Sprintf(
		"账号已被封禁：%s。封禁期限：永久（直至管理员解除）。如需申诉，请联系客服。",
		reason,
	)
	data := gin.H{
		"reason":         reason,
		"ban_until":      "until_unbanned",
		"appeal_action":  "contact_support",
		"appeal_message": "请联系客服提交申诉",
	}
	if user.BannedAt != nil {
		data["banned_at"] = user.BannedAt.Format(time.RFC3339)
	}
	return message, data
}

// Login 登录

func (h *AuthHandler) Login(c *gin.Context) {
	// Device lock may require SMS verification for new devices.
	var req LoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	req.Username = strings.TrimSpace(req.Username)

	// 查找用户
	var user models.User
	if !checkLoginThrottle(c, h.cache, "user", req.Username) {
		return
	}
	result := h.db.Where("username = ?", req.Username).First(&user)
	if result.Error == gorm.ErrRecordNotFound {
		recordLoginFailure(c, h.cache, "user", req.Username)
		response.Error(c, 400, "用户名或密码错误")
		return
	}
	if result.Error != nil {
		response.ServerError(c, "登录失败，请稍后重试")
		return
	}
	if !user.CredentialsInitialized {
		recordLoginFailure(c, h.cache, "user", req.Username)
		response.Error(c, 400, "该账号尚未设置登录账号和密码")
		return
	}

	// 验证密码
	if !user.CheckPassword(req.Password) {
		recordLoginFailure(c, h.cache, "user", req.Username)
		response.Error(c, 400, "用户名或密码错误")
		return
	}

	// 检查用户状态
	if user.Status == models.UserStatusBanned {
		message, data := bannedLoginResponse(user)
		response.ErrorWithData(c, response.CodeAccountBanned, message, data)
		return
	}
	if user.Status == models.UserStatusDisabled {
		response.Error(c, 403, "账号已被禁用")
		return
	}

	// 更新最后登录时间
	clearLoginAccountThrottle(c, h.cache, "user", req.Username)
	h.db.Model(&user).Update("last_seen", time.Now())
	if needVerify, ticket := h.issueDeviceLockChallenge(c, user, req); needVerify {
		c.JSON(http.StatusOK, response.Response{
			Code:    deviceLockVerifyRequiredCode,
			Message: "新设备登录需要短信验证",
			Data: gin.H{
				"verify_ticket": ticket,
				"expires_in":    int(cache.TTLVerifyCode / time.Second),
			},
		})
		return
	}
	if h.issueTwoStepChallenge(
		c,
		user,
		req.DeviceID,
		req.DeviceType,
		req.DeviceName,
		c.ClientIP(),
	) {
		return
	}

	// 普通登录复用现有会话版本，避免新设备登录挤掉其他在线设备。
	sessionVersion := authsession.EnsureLoginSession(c.Request.Context(), h.cache, user.UUID)
	authsession.ActivateDeviceSession(c.Request.Context(), h.cache, user.UUID, req.DeviceID)

	// 生成 Token
	token, err := jwt.GenerateToken(user.UUID, req.DeviceID, sessionVersion)
	if err != nil {
		response.ServerError(c, "生成Token失败")
		return
	}

	// 记录设备与会话。普通登录复用同一会话版本，不挤掉其他设备。
	if err := recordUserLoginWithSecurityNotice(h.db, user, token, req.DeviceID, req.DeviceType, req.DeviceName, c.ClientIP(), time.Now(), h.loginHub, h.loginPush); err != nil {
		response.ServerError(c, "记录登录会话失败")
		return
	}
	multiDevice, err := loadMultiDeviceLoginContext(h.db, user.ID, req.DeviceID)
	if err != nil {
		multiDevice = multiDeviceLoginContext{Policy: multiDeviceLoginPolicy}
	}
	response.Success(c, gin.H{
		"token":                     token,
		"user":                      user,
		"multi_device_policy":       multiDevice.Policy,
		"other_active_device_count": multiDevice.OtherActiveDeviceCount,
	})
}

// updateDevice 更新设备信息
func (h *AuthHandler) updateDevice(c *gin.Context, userID uint64, deviceID, deviceType, deviceName string) {
	if deviceType == "" {
		deviceType = "unknown"
	}

	var device models.UserDevice
	result := h.db.Where("user_id = ? AND device_id = ?", userID, deviceID).First(&device)
	if result.Error == gorm.ErrRecordNotFound {
		// 创建新设备记录
		device = models.UserDevice{
			UserID:     userID,
			DeviceID:   deviceID,
			DeviceType: deviceType,
			DeviceName: deviceName,
			IP:         c.ClientIP(),
			LastActive: time.Now(),
			CreatedAt:  time.Now(),
		}
		h.db.Create(&device)
	} else {
		// 更新设备信息
		h.db.Model(&device).Updates(map[string]interface{}{
			"device_name": deviceName,
			"ip":          c.ClientIP(),
			"last_active": time.Now(),
		})
	}

	// 清理过期设备（超过30天未活动的设备记录）
	go cleanupInactiveUserDevices(h.db, userID, deviceID, time.Now().AddDate(0, 0, -30))
}

// RefreshToken 刷新Token
func (h *AuthHandler) issueDeviceLockChallenge(
	c *gin.Context,
	user models.User,
	req LoginRequest,
) (bool, string) {
	var privacy models.UserPrivacySetting
	if err := h.db.Where("user_id = ?", user.ID).First(&privacy).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			privacy = models.UserPrivacySetting{
				UserID:                user.ID,
				LastSeenVisibility:    "所有人",
				PhoneVisibility:       "联系人",
				GroupInvitePermission: "所有人",
				AllowPhoneSearch:      true,
				AllowShortIDSearch:    true,
				SendReadReceipts:      true,
				ShowTypingStatus:      true,
				DeviceLockEnabled:     false,
				AutoDeleteAccount:     "6 个月",
			}
			if createErr := h.db.Create(&privacy).Error; createErr != nil {
				response.ServerError(c, "登录失败，请稍后重试")
				return true, ""
			}
		} else {
			response.ServerError(c, "登录失败，请稍后重试")
			return true, ""
		}
	}
	if !privacy.DeviceLockEnabled {
		return false, ""
	}
	if user.Phone == nil || strings.TrimSpace(*user.Phone) == "" {
		response.Error(c, 400, "已开启设备锁，请先绑定手机号")
		return true, ""
	}
	if h.smsSvc == nil || !h.smsSvc.CanSend() || h.cache == nil {
		response.Error(c, http.StatusServiceUnavailable, "设备锁已开启，但短信服务不可用")
		return true, ""
	}

	var device models.UserDevice
	if err := h.db.Where("user_id = ? AND device_id = ?", user.ID, req.DeviceID).
		First(&device).Error; err == nil {
		return false, ""
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {
		response.ServerError(c, "登录失败，请稍后重试")
		return true, ""
	}
	phone := strings.TrimSpace(*user.Phone)
	ctx := c.Request.Context()
	ok, rateErr := h.cache.RateLimit(ctx, "devlock:"+phone, 1, time.Minute)
	if rateErr != nil || !ok {
		response.Error(c, 429, "请求过于频繁，请1分钟后再试")
		return true, ""
	}
	ticket := uuid.New().String()
	payload := deviceLockTicketPayload{
		UserUUID:   user.UUID,
		DeviceID:   req.DeviceID,
		DeviceType: req.DeviceType,
		DeviceName: req.DeviceName,
		Code:       services.GenPhoneBindCode(),
	}
	if err := h.cache.Set(ctx, "auth:device-lock:"+ticket, payload, cache.TTLVerifyCode); err != nil {
		response.ServerError(c, "验证码缓存失败")
		return true, ""
	}
	if err := h.smsSvc.SendOTP(ctx, phone, payload.Code); err != nil {
		_ = h.cache.Delete(ctx, "auth:device-lock:"+ticket)
		response.Error(c, 502, "短信发送失败，请稍后重试")
		return true, ""
	}
	return true, ticket
}

type VerifyDeviceLockLoginRequest struct {
	Ticket string `json:"ticket" binding:"required"`
	Code   string `json:"code" binding:"required"`
}

func (h *AuthHandler) VerifyDeviceLockLogin(c *gin.Context) {
	if h.cache == nil {
		response.ServerError(c, "服务异常")
		return
	}

	var req VerifyDeviceLockLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	key := "auth:device-lock:" + strings.TrimSpace(req.Ticket)
	var payload deviceLockTicketPayload
	if err := h.cache.Get(c.Request.Context(), key, &payload); err != nil {
		response.Error(c, 400, "验证已过期，请重新登录")
		return
	}
	if !allowSMSVerifyAttempt(c, h.cache, "device-lock:"+strings.TrimSpace(req.Ticket), key) {
		return
	}
	if strings.TrimSpace(req.Code) != payload.Code {
		response.Error(c, 400, "验证码错误")
		return
	}

	var user models.User
	if err := h.db.Where("uuid = ?", payload.UserUUID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	if user.Status == 0 {
		response.Error(c, 403, "账号已被禁用")
		return
	}

	_ = h.cache.Delete(c.Request.Context(), key)
	clearSMSVerifyAttempts(c.Request.Context(), h.cache, "device-lock:"+strings.TrimSpace(req.Ticket))
	if h.issueTwoStepChallenge(
		c,
		user,
		payload.DeviceID,
		payload.DeviceType,
		payload.DeviceName,
		c.ClientIP(),
	) {
		return
	}
	h.db.Model(&user).Update("last_seen", time.Now())
	sessionVersion := authsession.EnsureLoginSession(c.Request.Context(), h.cache, user.UUID)
	authsession.ActivateDeviceSession(c.Request.Context(), h.cache, user.UUID, payload.DeviceID)
	token, err := jwt.GenerateToken(user.UUID, payload.DeviceID, sessionVersion)
	if err != nil {
		response.ServerError(c, "生成Token失败")
		return
	}
	if err := recordUserLoginWithSecurityNotice(h.db, user, token, payload.DeviceID, payload.DeviceType, payload.DeviceName, c.ClientIP(), time.Now(), h.loginHub, h.loginPush); err != nil {
		response.ServerError(c, "记录登录会话失败")
		return
	}
	response.Success(c, gin.H{
		"token": token,
		"user":  user,
	})
}

const passwordResetCodePrefix = "auth:password-reset:"

type SendPasswordResetCodeRequest struct {
	Phone string `json:"phone" binding:"required"`
}

type ResetPasswordByCodeRequest struct {
	Phone       string `json:"phone" binding:"required"`
	Code        string `json:"code" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=6,max=20"`
}

func passwordResetCodeKey(phone string) string {
	return passwordResetCodePrefix + phone
}

// SendPasswordResetCode sends an SMS code to a bound phone for password recovery.
func (h *AuthHandler) SendPasswordResetCode(c *gin.Context) {
	if h.smsSvc == nil || !h.smsSvc.CanSend() || h.cache == nil {
		response.Error(c, http.StatusServiceUnavailable, "短信服务不可用")
		return
	}

	var req SendPasswordResetCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	phone := services.NormalizeCNMobile(req.Phone)
	if phone == "" {
		response.BadRequest(c, "手机号格式错误")
		return
	}
	ctx := c.Request.Context()
	if ok, err := h.cache.RateLimit(ctx, "pwd_reset_ip:"+c.ClientIP(), 10, time.Hour); err != nil {
		response.Error(c, http.StatusServiceUnavailable, "请求校验失败，请稍后再试")
		return
	} else if !ok {
		response.Error(c, 429, "请求过于频繁，请稍后再试")
		return
	}
	if ok, err := h.cache.RateLimit(ctx, "pwd_reset_phone:"+phone, 3, time.Hour); err != nil {
		response.Error(c, http.StatusServiceUnavailable, "请求校验失败，请稍后再试")
		return
	} else if !ok {
		response.Error(c, 429, "请求过于频繁，请稍后再试")
		return
	}

	var user models.User
	if err := h.db.Where("phone = ?", phone).First(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			response.NotFound(c, "手机号未绑定账号")
			return
		}
		response.ServerError(c, "发送失败")
		return
	}
	if user.Status == 0 {
		response.Error(c, 403, "账号已被禁用")
		return
	}
	code := services.GenPhoneBindCode()
	key := passwordResetCodeKey(phone)
	if err := h.cache.Set(ctx, key, code, cache.TTLVerifyCode); err != nil {
		response.ServerError(c, "验证码缓存失败")
		return
	}
	if err := h.smsSvc.SendOTP(ctx, phone, code); err != nil {
		_ = h.cache.Delete(ctx, key)
		response.Error(c, 502, "短信发送失败，请稍后重试")
		return
	}
	clearSMSVerifyAttempts(ctx, h.cache, "password-reset:"+phone)
	response.Success(c, gin.H{
		"message":    "验证码已发送",
		"expires_in": int(cache.TTLVerifyCode / time.Second),
	})
}

// ResetPasswordByCode resets a password after verifying the bound phone code.
func (h *AuthHandler) ResetPasswordByCode(c *gin.Context) {
	if h.cache == nil {
		response.ServerError(c, "服务异常")
		return
	}

	var req ResetPasswordByCodeRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "新密码需要6-20位")
		return
	}
	phone := services.NormalizeCNMobile(req.Phone)
	if phone == "" {
		response.BadRequest(c, "手机号格式错误")
		return
	}
	key := passwordResetCodeKey(phone)
	var expectedCode string
	if err := h.cache.Get(c.Request.Context(), key, &expectedCode); err != nil {
		response.Error(c, 400, "验证码已过期，请重新获取")
		return
	}
	if !allowSMSVerifyAttempt(c, h.cache, "password-reset:"+phone, key) {
		return
	}
	if strings.TrimSpace(req.Code) != expectedCode {
		response.Error(c, 400, "验证码错误")
		return
	}

	var user models.User
	if err := h.db.Where("phone = ?", phone).First(&user).Error; err != nil {
		response.NotFound(c, "手机号未绑定账号")
		return
	}
	if user.Status == 0 {
		response.Error(c, 403, "账号已被禁用")
		return
	}
	if err := user.SetPassword(req.NewPassword); err != nil {
		response.ServerError(c, "重置失败")
		return
	}
	if err := h.db.Save(&user).Error; err != nil {
		response.ServerError(c, "重置失败")
		return
	}

	_ = h.cache.Delete(c.Request.Context(), key)
	clearSMSVerifyAttempts(c.Request.Context(), h.cache, "password-reset:"+phone)
	authsession.MarkPasswordReset(c.Request.Context(), h.cache, user.UUID)
	response.SuccessWithMessage(c, "密码已重置，请重新登录", gin.H{
		"username": user.Username,
		"nickname": user.Nickname,
	})
}

func (h *AuthHandler) RefreshToken(c *gin.Context) {
	authHeader := c.GetHeader("Authorization")
	parts := strings.SplitN(authHeader, " ", 2)
	if len(parts) != 2 || parts[0] != "Bearer" || strings.TrimSpace(parts[1]) == "" {
		response.Unauthorized(c, "未登录")
		return
	}
	rawToken := strings.TrimSpace(parts[1])

	claims, err := jwt.ParseTokenForRefresh(rawToken)
	if err != nil {
		response.Unauthorized(c, "刷新Token失败，请重新登录")
		return
	}

	// 与登录保持一致：账号不存在/禁用时不允许续期
	var user models.User
	if err := h.db.Where("uuid = ?", claims.UserID).First(&user).Error; err != nil {
		response.Unauthorized(c, "账号不存在，请重新登录")
		return
	}
	if user.Status == 0 {
		response.Unauthorized(c, "账号已被禁用")
		return
	}

	// 设备维度校验：设备记录不存在时，拒绝续期
	// （管理员冻结/重置密码时会清理设备记录，用于阻断旧设备继续刷新 token）
	var device models.UserDevice
	if err := h.db.Where("user_id = ? AND device_id = ?", user.ID, claims.DeviceID).First(&device).Error; err != nil {
		response.Unauthorized(c, "登录状态已失效，请重新登录")
		return
	}

	//
	if authError := authsession.ValidateUserTokenStateWithToken(c.Request.Context(), h.cache, claims, rawToken); authError != "" {
		if authError == "会话已更新，请重新登录" {
			response.Unauthorized(c, authError)
			return
		}
		response.Unauthorized(c, "登录状态已失效，请重新登录")
		return
	}

	token, err := jwt.RefreshToken(rawToken)
	if err != nil {
		response.Unauthorized(c, "刷新Token失败，请重新登录")
		return
	}
	if err := rotateUserSessionToken(h.db, user.ID, rawToken, token, claims.DeviceID, device.DeviceType, device.DeviceName, c.ClientIP(), time.Now()); err != nil {
		response.ServerError(c, "刷新Token失败，请稍后重试")
		return
	}
	response.Success(c, gin.H{
		"token": token,
	})
}

type InitializeCredentialsRequest struct {
	Username string `json:"username" binding:"required,min=3,max=20"`
	Password string `json:"password" binding:"required,min=6,max=20"`
}

// InitializeCredentials 为一键注册账号设置可跨设备登录的账号密码。
func (h *AuthHandler) InitializeCredentials(c *gin.Context) {
	userUUID := c.GetString("user_id")
	if userUUID == "" {
		response.Unauthorized(c, "未登录")
		return
	}
	var req InitializeCredentialsRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "账号需3-20位，密码需6-20位")
		return
	}
	req.Username = strings.TrimSpace(req.Username)
	if len(req.Username) < 3 || len(req.Username) > 20 {
		response.BadRequest(c, "账号长度需为3-20位")
		return
	}
	for _, char := range req.Username {
		if !((char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z') || (char >= '0' && char <= '9') || char == '_') {
			response.BadRequest(c, "账号只能包含字母、数字和下划线")
			return
		}
	}

	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	if user.CredentialsInitialized {
		response.Error(c, http.StatusConflict, "该账号已经设置过登录账号和密码")
		return
	}
	var count int64
	if err := h.db.Model(&models.User{}).Where("username = ? AND id <> ?", req.Username, user.ID).Count(&count).Error; err != nil {
		response.ServerError(c, "检查账号失败")
		return
	}
	if count > 0 {
		response.Error(c, 400, "该账号已被使用")
		return
	}
	if err := user.SetPassword(req.Password); err != nil {
		response.ServerError(c, "设置密码失败")
		return
	}
	now := time.Now()
	if err := h.db.Model(&user).Updates(map[string]interface{}{
		"username":                   req.Username,
		"password":                   user.Password,
		"credentials_initialized":    true,
		"credentials_initialized_at": now,
		"updated_at":                 now,
	}).Error; err != nil {
		response.ServerError(c, "设置账号密码失败")
		return
	}
	if h.cache != nil {
		_ = h.cache.DeleteUser(c.Request.Context(), user.UUID)
	}
	if err := h.db.Where("id = ?", user.ID).First(&user).Error; err != nil {
		response.ServerError(c, "读取账号失败")
		return
	}
	response.SuccessWithMessage(c, "账号密码设置成功", gin.H{
		"user":                    user,
		"needs_credentials_setup": false,
	})
}

// ChangePasswordRequest 修改密码请求
type ChangePasswordRequest struct {
	OldPassword string `json:"old_password" binding:"required"`
	NewPassword string `json:"new_password" binding:"required,min=6,max=20"`
}

// ChangePassword 修改密码
func (h *AuthHandler) ChangePassword(c *gin.Context) {
	userUUID := c.GetString("user_id")
	if userUUID == "" {
		response.Unauthorized(c, "未登录")
		return
	}

	var req ChangePasswordRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "新密码需要6-20位")
		return
	}

	// 查找用户
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	// 验证旧密码
	if !user.CheckPassword(req.OldPassword) {
		response.Error(c, 400, "原密码错误")
		return
	}

	// 设置新密码
	if err := user.SetPassword(req.NewPassword); err != nil {
		response.ServerError(c, "修改失败")
		return
	}
	if err := h.db.Save(&user).Error; err != nil {
		response.ServerError(c, "修改失败")
		return
	}
	if h.cache != nil {
		authsession.MarkPasswordReset(c.Request.Context(), h.cache, user.UUID)
	}
	response.SuccessWithMessage(c, "密码修改成功", nil)
}

// Logout 登出
func (h *AuthHandler) Logout(c *gin.Context) {
	userUUID := strings.TrimSpace(c.GetString("user_id"))
	deviceID := strings.TrimSpace(c.GetString("device_id"))
	rawToken := bearerToken(c)
	if userUUID == "" || rawToken == "" {
		response.Unauthorized(c, "登录状态无效")
		return
	}

	var req struct {
		PushBindings []services.PushBindingRequest `json:"push_bindings"`
	}
	if c.Request.ContentLength != 0 {
		if err := c.ShouldBindJSON(&req); err != nil && !errors.Is(err, io.EOF) {
			response.BadRequest(c, "登出参数错误")
			return
		}
	}

	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}
	type bindingResult struct {
		BindingID uint64 `json:"binding_id,omitempty"`
		Channel   string `json:"push_channel,omitempty"`
		Cleared   bool   `json:"cleared"`
		Error     string `json:"error,omitempty"`
	}
	results := make([]bindingResult, 0, len(req.PushBindings))
	err := h.db.Transaction(func(tx *gorm.DB) error {
		for _, binding := range req.PushBindings {
			cleared, clearErr := services.ClearPushBinding(tx, user.ID, deviceID, binding)
			result := bindingResult{
				BindingID: binding.BindingID,
				Channel:   services.NormalizePushChannel(binding.Channel, ""),
				Cleared:   cleared,
			}
			if clearErr != nil {
				if errors.Is(clearErr, services.ErrPushDeviceMismatch) ||
					errors.Is(clearErr, services.ErrInvalidPushChannel) ||
					errors.Is(clearErr, services.ErrInvalidPushToken) {
					result.Error = "binding_mismatch"
					results = append(results, result)
					continue
				}
				return clearErr
			}
			results = append(results, result)
		}
		if _, err := services.ClearPushBindingsForDevice(tx, user.ID, deviceID); err != nil {
			return err
		}
		if err := deleteUserSessionByToken(tx, user.ID, rawToken); err != nil {
			return err
		}
		return authsession.RevokeUserToken(c.Request.Context(), h.cache, userUUID, rawToken)
	})
	if err != nil {
		response.ServerError(c, "登出失败")
		return
	}
	response.SuccessWithMessage(c, "已登出", gin.H{
		"logged_out": true,
		"bindings":   results,
	})
}
