package handlers

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"gaoranim/internal/authsession"
	"gaoranim/internal/cache"
	"gaoranim/internal/models"
	"gaoranim/internal/services"
	"gaoranim/pkg/jwt"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"
)

// AuthHandler 认证处理器
type AuthHandler struct {
	db         *gorm.DB
	cache      *cache.Cache
	msgService *services.MessageService
	smsSvc     *services.SMSService
}

// NewAuthHandler 创建认证处理器
func NewAuthHandler(
	db *gorm.DB,
	cache *cache.Cache,
	msgService *services.MessageService,
	smsSvc *services.SMSService,
) *AuthHandler {
	return &AuthHandler{
		db:         db,
		cache:      cache,
		msgService: msgService,
		smsSvc:     smsSvc,
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
	InviteCode string `json:"invite_code"` // 邀请码（可选）
	DeviceID   string `json:"device_id" binding:"required"`
	DeviceType string `json:"device_type"` // ios/android/web
	DeviceName string `json:"device_name"`
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

	// 检查是否强制填写邀请码
	var requireInviteSetting models.SystemSetting
	if err := h.db.Where("`key` = ?", models.SettingRequireInviteCode).First(&requireInviteSetting).Error; err == nil {
		if isSettingTrue(requireInviteSetting.Value) && req.InviteCode == "" {
			response.Error(c, 400, "当前注册必须填写邀请码")
			return
		}
	}

	// 检查用户名是否已存在
	var existUser models.User
	if err := h.db.Where("username = ?", req.Username).First(&existUser).Error; err == nil {
		response.Error(c, 400, "用户名已存在")
		return
	}

	// 先预校验邀请码，避免先建号再失败导致用户名被占用
	if req.InviteCode != "" {
		result := ValidateInviteCode(h.db, req.InviteCode)
		if result != nil && !result.Valid {
			response.Error(c, 400, result.Message)
			return
		}
	}

	// 创建用户（主流程事务化，避免出现“返回失败但部分写入成功”）
	user := models.User{
		UUID:     uuid.New().String(),
		Username: req.Username,
		Nickname: req.Nickname,
		Status:   1,
		LastSeen: time.Now(),
	}

	// 设置密码
	if err := user.SetPassword(req.Password); err != nil {
		response.ServerError(c, "注册失败")
		return
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
		DeviceLockEnabled:     false,
		AutoDeleteAccount:     "6 个月",
	}).Error; err != nil {
		tx.Rollback()
		response.ServerError(c, "注册失败")
		return
	}

	// 处理邀请码（自动加官方客服为好友 + 创建私聊 + 发送欢迎语）
	boundService := false
	var inviteWelcomeInfo *InviteWelcomeInfo
	if req.InviteCode != "" {
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
				tx.Where("is_service_enabled = ?", true).Find(&officialUsers)

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
			tx.Find(&officialGroups)
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
			tx.Find(&officialChannels)
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

	// 事务提交后再发送欢迎语，避免提交前外发消息造成不一致
	SendInviteWelcomeMessageByInfo(h.db, h.msgService, inviteWelcomeInfo)

	// 生成 Token
	sessionVersion := authsession.IssueUserSession(c.Request.Context(), h.cache, user.UUID)

	token, err := jwt.GenerateToken(user.UUID, req.DeviceID, sessionVersion)
	if err != nil {
		response.ServerError(c, "生成Token失败")
		return
	}

	// 记录设备与会话。会话表用于多设备列表和按会话下线。
	if err := recordUserLogin(h.db, user.ID, token, req.DeviceID, req.DeviceType, req.DeviceName, c.ClientIP(), time.Now()); err != nil {
		response.ServerError(c, "记录登录会话失败")
		return
	}

	resp := gin.H{
		"token": token,
		"user":  user,
	}
	response.Success(c, resp)
}

// LoginRequest 登录请求
type LoginRequest struct {
	Username   string `json:"username" binding:"required"`
	Password   string `json:"password" binding:"required"`
	DeviceID   string `json:"device_id" binding:"required"`
	DeviceType string `json:"device_type"` // ios/android/web
	DeviceName string `json:"device_name"`
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
	result := h.db.Where("username = ?", req.Username).First(&user)

	if result.Error == gorm.ErrRecordNotFound {
		response.Error(c, 400, "用户名或密码错误")
		return
	}

	if result.Error != nil {
		response.ServerError(c, "登录失败，请稍后重试")
		return
	}

	// 验证密码
	if !user.CheckPassword(req.Password) {
		response.Error(c, 400, "用户名或密码错误")
		return
	}

	// 检查用户状态
	if user.Status == 0 {
		response.Error(c, 403, "账号已被禁用")
		return
	}

	// 更新最后登录时间
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

	// 普通登录复用现有会话版本，避免新设备登录挤掉其他在线设备。
	sessionVersion := authsession.EnsureLoginSession(c.Request.Context(), h.cache, user.UUID)

	// 生成 Token
	token, err := jwt.GenerateToken(user.UUID, req.DeviceID, sessionVersion)
	if err != nil {
		response.ServerError(c, "生成Token失败")
		return
	}

	// 记录设备与会话。普通登录复用同一会话版本，不挤掉其他设备。
	if err := recordUserLogin(h.db, user.ID, token, req.DeviceID, req.DeviceType, req.DeviceName, c.ClientIP(), time.Now()); err != nil {
		response.ServerError(c, "记录登录会话失败")
		return
	}

	response.Success(c, gin.H{
		"token": token,
		"user":  user,
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
	go func() {
		thirtyDaysAgo := time.Now().AddDate(0, 0, -30)
		h.db.Where("user_id = ? AND device_id != ? AND last_active < ?", userID, deviceID, thirtyDaysAgo).
			Delete(&models.UserDevice{})
	}()
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
	h.db.Model(&user).Update("last_seen", time.Now())
	sessionVersion := authsession.EnsureLoginSession(c.Request.Context(), h.cache, user.UUID)
	token, err := jwt.GenerateToken(user.UUID, payload.DeviceID, sessionVersion)
	if err != nil {
		response.ServerError(c, "生成Token失败")
		return
	}
	if err := recordUserLogin(h.db, user.ID, token, payload.DeviceID, payload.DeviceType, payload.DeviceName, c.ClientIP(), time.Now()); err != nil {
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

	// 保持与 Auth 中间件一致：冻结/改密/退出登录/会话更新后禁止继续续期
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
	authHeader := c.GetHeader("Authorization")
	parts := strings.SplitN(authHeader, " ", 2)
	rawToken := ""
	if len(parts) == 2 && parts[0] == "Bearer" {
		rawToken = strings.TrimSpace(parts[1])
	}
	if userUUID != "" && h.cache != nil {
		if deviceID != "" {
			authsession.InvalidateDeviceSession(c.Request.Context(), h.cache, userUUID, deviceID)
		}
		if rawToken != "" {
			authsession.RevokeUserToken(c.Request.Context(), h.cache, userUUID, rawToken)
		}
	}
	if userUUID != "" && rawToken != "" {
		var user models.User
		if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err == nil {
			_ = deleteUserSessionByToken(h.db, user.ID, rawToken)
		}
	}
	response.SuccessWithMessage(c, "已登出", nil)
}
