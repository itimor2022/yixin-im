// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"net/http"
	"strings"
	"time"
	"genericim/internal/authsession"
	"genericim/internal/cache"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/jwt"
	"genericim/pkg/response"
)

type ServiceAdminHandler struct {
	db     *gorm.DB
	cache  *cache.Cache
	smsSvc *services.SMSService
}

func NewServiceAdminHandler(db *gorm.DB, cache *cache.Cache, smsSvc *services.SMSService) *ServiceAdminHandler {
	return &ServiceAdminHandler{db: db, cache: cache, smsSvc: smsSvc}
}

type ServiceAdminLoginRequest struct {
	Username   string `json:"username" binding:"required"`
	Password   string `json:"password" binding:"required"`
	DeviceID   string `json:"device_id" binding:"required"`
	DeviceType string `json:"device_type"`
	DeviceName string `json:"device_name"`
}

func (h *ServiceAdminHandler) Login(c *gin.Context) {
	var req ServiceAdminLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	req.Username = strings.TrimSpace(req.Username)
	if !checkLoginThrottle(c, h.cache, "service-admin", req.Username) {
		return
	}

	var user models.User
	if err := h.db.Where("username = ?", req.Username).First(&user).Error; err != nil {
		recordLoginFailure(c, h.cache, "service-admin", req.Username)
		response.Error(c, http.StatusUnauthorized, "用户名或密码错误")
		return
	}
	if !user.CheckPassword(req.Password) {
		recordLoginFailure(c, h.cache, "service-admin", req.Username)
		response.Error(c, http.StatusUnauthorized, "用户名或密码错误")
		return
	}
	if user.Status == models.UserStatusDisabled {
		response.Error(c, http.StatusForbidden, "账号已被禁用")
		return
	}

	var official models.OfficialUser
	if err := h.db.Where("user_id = ? AND is_service_enabled = ?", user.ID, true).First(&official).Error; err != nil {
		recordLoginFailure(c, h.cache, "service-admin", req.Username)
		response.Error(c, http.StatusForbidden, "当前账号不是已启用的官方客服")
		return
	}

	clearLoginAccountThrottle(c, h.cache, "service-admin", req.Username)
	h.db.Model(&user).Update("last_seen", time.Now())
	sessionVersion := authsession.EnsureLoginSession(c.Request.Context(), h.cache, user.UUID)

	token, err := jwt.GenerateToken(user.UUID, req.DeviceID, sessionVersion)
	if err != nil {
		response.ServerError(c, "生成Token失败")
		return
	}
	response.Success(c, gin.H{
		"token": token,
		"user": gin.H{
			"id":       user.ID,
			"uuid":     user.UUID,
			"username": user.Username,
			"nickname": user.Nickname,
			"phone":    user.Phone,
			"avatar":   user.Avatar,
		},
	})
}

func (h *ServiceAdminHandler) Logout(c *gin.Context) {
	userUUID := strings.TrimSpace(c.GetString("user_id"))
	deviceID := strings.TrimSpace(c.GetString("device_id"))
	if userUUID != "" && h.cache != nil {
		if deviceID != "" {
			authsession.InvalidateDeviceSession(c.Request.Context(), h.cache, userUUID, deviceID)
		}
		authHeader := c.GetHeader("Authorization")
		parts := strings.SplitN(authHeader, " ", 2)
		if len(parts) == 2 && parts[0] == "Bearer" {
			authsession.RevokeUserToken(c.Request.Context(), h.cache, userUUID, strings.TrimSpace(parts[1]))
		}
	}
	response.Success(c, gin.H{"success": true})
}

func (h *ServiceAdminHandler) officialUserByContext(c *gin.Context) (*models.User, *models.OfficialUser, error) {
	userUUID := strings.TrimSpace(c.GetString("user_id"))
	if userUUID == "" {
		return nil, nil, gorm.ErrRecordNotFound
	}

	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {
		return nil, nil, err
	}

	var official models.OfficialUser
	if err := h.db.Where("user_id = ? AND is_service_enabled = ?", user.ID, true).First(&official).Error; err != nil {
		return nil, nil, err
	}
	return &user, &official, nil
}

func (h *ServiceAdminHandler) GetProfile(c *gin.Context) {
	user, _, err := h.officialUserByContext(c)
	if err != nil {
		response.Forbidden(c, "仅官方客服可访问")
		return
	}

	var invite models.InviteCode
	inviteCode := ""
	if err := h.db.Where("service_user_id = ?", user.ID).Order("id ASC").First(&invite).Error; err == nil {
		inviteCode = invite.Code
	}
	phone := ""
	if user.Phone != nil {
		phone = *user.Phone
	}
	response.Success(c, gin.H{
		"nickname":   user.Nickname,
		"phone":      phone,
		"role":       "official_service",
		"inviteCode": inviteCode,
		"status":     "enabled",
		"username":   user.Username,
		"avatar":     user.Avatar,
		"userId":     user.ID,
		"userUuid":   user.UUID,
	})
}

func (h *ServiceAdminHandler) serviceAdminRegisterURL(code string) string {
	path := "/register?invite_code=" + code
	registerBaseURL := resolveRegisterBaseURL(h.db)
	if registerBaseURL == "" {
		return path
	}
	return strings.TrimRight(registerBaseURL, "/") + path
}

func (h *ServiceAdminHandler) GetDashboard(c *gin.Context) {
	user, _, err := h.officialUserByContext(c)
	if err != nil {
		response.Forbidden(c, "仅官方客服可访问")
		return
	}

	var invite models.InviteCode
	inviteCode := ""
	usedCount := 0
	registerURL := ""
	if err := h.db.Where("service_user_id = ?", user.ID).Order("id ASC").First(&invite).Error; err == nil {
		inviteCode = invite.Code
		usedCount = invite.UsedCount
		registerURL = h.serviceAdminRegisterURL(invite.Code)
	}

	var inviteeCount int64
	h.db.Table("invite_code_usages AS icu").
		Joins("JOIN invite_codes ic ON ic.id = icu.invite_code_id").
		Where("ic.service_user_id = ?", user.ID).
		Count(&inviteeCount)
	now := time.Now()
	currentLocation := now.Location()
	todayStart := time.Date(now.Year(), now.Month(), now.Day(), 0, 0, 0, 0, currentLocation)
	weekStart := todayStart.AddDate(0, 0, -6)

	var inviteeToday int64
	h.db.Table("invite_code_usages AS icu").
		Joins("JOIN invite_codes ic ON ic.id = icu.invite_code_id").
		Where("ic.service_user_id = ? AND icu.created_at >= ?", user.ID, todayStart).
		Count(&inviteeToday)

	var weeklyConversion int64
	h.db.Table("invite_code_usages AS icu").
		Joins("JOIN invite_codes ic ON ic.id = icu.invite_code_id").
		Where("ic.service_user_id = ? AND icu.created_at >= ?", user.ID, weekStart).
		Count(&weeklyConversion)

	type trendItem struct {
		Date  string `json:"date"`
		Count int64  `json:"count"`
	}
	type recentInviteeItem struct {
		Name         string `json:"name"`
		UUID         string `json:"uuid"`
		RegisteredAt string `json:"registeredAt"`
	}
	var trend []trendItem
	if err := h.db.Table("invite_code_usages AS icu").
		Select("DATE_FORMAT(icu.created_at, '%Y-%m-%d') AS date, COUNT(*) AS count").
		Joins("JOIN invite_codes ic ON ic.id = icu.invite_code_id").
		Where("ic.service_user_id = ? AND icu.created_at >= ?", user.ID, weekStart).
		Group("DATE_FORMAT(icu.created_at, '%Y-%m-%d')").
		Order("date ASC").
		Scan(&trend).Error; err != nil {
		trend = []trendItem{}
	}
	trendMap := make(map[string]int64, len(trend))
	for _, item := range trend {
		trendMap[item.Date] = item.Count
	}
	series := make([]gin.H, 0, 7)
	for i := 0; i < 7; i++ {
		day := weekStart.AddDate(0, 0, i)
		key := day.Format("2006-01-02")
		series = append(series, gin.H{
			"date":  key,
			"count": trendMap[key],
		})
	}

	var recentInvitees []recentInviteeItem
	if err := h.db.Table("invite_code_usages AS icu").
		Select("u.nickname AS name, u.uuid AS uuid, DATE_FORMAT(icu.created_at, '%Y-%m-%d %H:%i') AS registered_at").
		Joins("JOIN invite_codes ic ON ic.id = icu.invite_code_id").
		Joins("JOIN users u ON u.id = icu.user_id AND u.deleted_at IS NULL").
		Where("ic.service_user_id = ?", user.ID).
		Order("icu.created_at DESC").
		Limit(5).
		Scan(&recentInvitees).Error; err != nil {
		recentInvitees = []recentInviteeItem{}
	}
	response.Success(c, gin.H{
		"inviteCode":        inviteCode,
		"inviteeCount":      inviteeCount,
		"inviteeToday":      inviteeToday,
		"serviceStatusText": "启用",
		"weeklyConversion":  weeklyConversion,
		"usedCount":         usedCount,
		"registerUrl":       registerURL,
		"recentTrend":       series,
		"recentInvitees":    recentInvitees,
	})
}

func (h *ServiceAdminHandler) GetInviteCode(c *gin.Context) {
	user, _, err := h.officialUserByContext(c)
	if err != nil {
		response.Forbidden(c, "仅官方客服可访问")
		return
	}

	var invite models.InviteCode
	if err := h.db.Where("service_user_id = ?", user.ID).Order("id ASC").First(&invite).Error; err != nil {
		response.NotFound(c, "邀请码不存在")
		return
	}
	response.Success(c, gin.H{
		"code":             invite.Code,
		"updatedAt":        invite.UpdatedAt.Format("2006-01-02 15:04"),
		"statusText":       map[bool]string{true: "可用", false: "停用"}[invite.Status == 1],
		"registerUrl":      h.serviceAdminRegisterURL(invite.Code),
		"usedCount":        invite.UsedCount,
		"weeklyConversion": 0,
	})
}

func (h *ServiceAdminHandler) GetInvitees(c *gin.Context) {
	user, _, err := h.officialUserByContext(c)
	if err != nil {
		response.Forbidden(c, "仅官方客服可访问")
		return
	}

	type inviteeItem struct {
		ID           uint64    `json:"id"`
		Name         string    `json:"name"`
		UUID         string    `json:"uuid"`
		RegisteredAt time.Time `json:"registered_at"`
		Active       bool      `json:"active"`
	}
	latestUsageSubQuery := h.db.Table("invite_code_usages").
		Select("MAX(id)").
		Group("user_id")

	var list []inviteeItem
	if err := h.db.Table("invite_code_usages AS icu").
		Select(` 			u.id AS id, u.nickname AS name, u.uuid AS uuid, icu.created_at AS registered_at, CASE WHEN u.status = 1 THEN true ELSE false END AS active 		`).
		Joins("JOIN invite_codes ic ON ic.id = icu.invite_code_id").
		Joins("JOIN users u ON u.id = icu.user_id AND u.deleted_at IS NULL").
		Where("icu.id IN(?)", latestUsageSubQuery).
		Where("ic.service_user_id = ?", user.ID).
		Order("icu.created_at DESC").
		Scan(&list).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "获取失败")
		return
	}
	result := make([]gin.H, 0, len(list))
	for _, item := range list {
		result = append(result, gin.H{
			"id":           item.ID,
			"name":         item.Name,
			"uuid":         item.UUID,
			"registeredAt": item.RegisteredAt.Format("2006-01-02 15:04"),
			"active":       item.Active,
		})
	}
	response.Success(c, result)
}

func (h *ServiceAdminHandler) GetWelcomeMessage(c *gin.Context) {
	_, official, err := h.officialUserByContext(c)
	if err != nil {
		response.Forbidden(c, "仅官方客服可访问")
		return
	}
	message := strings.TrimSpace(official.WelcomeMessage)
	if message == "" {
		message = defaultServiceWelcomeMessage()
	}
	response.Success(c, gin.H{"message": message})
}

func (h *ServiceAdminHandler) UpdateWelcomeMessage(c *gin.Context) {
	_, official, err := h.officialUserByContext(c)
	if err != nil {
		response.Forbidden(c, "仅官方客服可访问")
		return
	}

	var req struct {
		Message string `json:"message"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	message := strings.TrimSpace(req.Message)
	if message == "" {
		message = defaultServiceWelcomeMessage()
	}
	if !validateOfficialWelcomeMessage(message) {
		response.Error(c, http.StatusBadRequest, "欢迎语不能超过500个字符")
		return
	}
	if err := h.db.Model(&models.OfficialUser{}).Where("id = ?", official.ID).Update("welcome_message", message).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "更新失败")
		return
	}
	response.Success(c, gin.H{"success": true, "message": message, "length": len([]rune(message))})
}

func (h *ServiceAdminHandler) UpdatePassword(c *gin.Context) {
	user, _, err := h.officialUserByContext(c)
	if err != nil {
		response.Forbidden(c, "仅官方客服可访问")
		return
	}

	var req struct {
		OldPassword string `json:"old_password" binding:"required"`
		NewPassword string `json:"new_password" binding:"required,min=6,max=20"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误：新密码长度需为6-20位")
		return
	}
	if !user.CheckPassword(req.OldPassword) {
		response.Error(c, http.StatusBadRequest, "原密码错误")
		return
	}
	if err := user.SetPassword(req.NewPassword); err != nil {
		response.Error(c, http.StatusInternalServerError, "密码加密失败")
		return
	}
	if err := h.db.Model(&models.User{}).Where("id = ?", user.ID).Update("password", user.Password).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "更新失败")
		return
	}
	if h.cache != nil {
		authsession.MarkPasswordReset(c.Request.Context(), h.cache, user.UUID)
	}
	response.SuccessWithMessage(c, "密码已更新，请重新登录", gin.H{"success": true})
}

func (h *ServiceAdminHandler) SendPhoneBindCode(c *gin.Context) {
	if h.smsSvc == nil || !h.smsSvc.CanSend() || h.cache == nil {
		response.Error(c, http.StatusServiceUnavailable, "短信服务未配置或未启用")
		return
	}

	user, _, err := h.officialUserByContext(c)
	if err != nil {
		response.Forbidden(c, "仅官方客服可访问")
		return
	}
	if user.Phone != nil && *user.Phone != "" {
		response.Error(c, http.StatusBadRequest, "已绑定手机号，如需更换请联系管理员")
		return
	}

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

	var taken int64
	h.db.Model(&models.User{}).Where("phone = ? AND id != ?", phone, user.ID).Count(&taken)
	if taken > 0 {
		response.Error(c, http.StatusBadRequest, "该手机号已被其他账号使用")
		return
	}
	ctx := c.Request.Context()
	ok, rateErr := h.cache.RateLimit(ctx, "service-admin:smsbind:"+phone, 1, time.Minute)
	if rateErr != nil || !ok {
		response.Error(c, http.StatusTooManyRequests, "发送过于频繁，请稍后再试")
		return
	}
	code := services.GenPhoneBindCode()
	if err := h.cache.SetVerifyCode(ctx, phone, code); err != nil {
		response.ServerError(c, "验证码缓存失败")
		return
	}
	if err := h.smsSvc.SendOTP(ctx, phone, code); err != nil {
		_ = h.cache.DeleteVerifyCode(ctx, phone)
		response.Error(c, http.StatusBadGateway, "短信发送失败，请稍后重试")
		return
	}
	clearSMSVerifyAttempts(ctx, h.cache, "service-admin-bind-phone:"+phone)
	response.Success(c, gin.H{
		"message":    "验证码已发送",
		"expires_in": int(cache.TTLVerifyCode / time.Second),
	})
}

func (h *ServiceAdminHandler) BindPhone(c *gin.Context) {
	if h.cache == nil {
		response.ServerError(c, "服务异常")
		return
	}

	user, _, err := h.officialUserByContext(c)
	if err != nil {
		response.Forbidden(c, "仅官方客服可访问")
		return
	}
	if user.Phone != nil && *user.Phone != "" {
		response.Error(c, http.StatusBadRequest, "已绑定手机号")
		return
	}

	var req struct {
		Phone string `json:"phone" binding:"required"`
		Code  string `json:"code" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.BadRequest(c, "参数错误")
		return
	}
	phone := services.NormalizeCNMobile(req.Phone)
	if phone == "" {
		response.BadRequest(c, "手机号无效")
		return
	}
	ctx := c.Request.Context()
	stored, cacheErr := h.cache.GetVerifyCode(ctx, phone)
	if cacheErr != nil || stored == "" {
		response.Error(c, http.StatusBadRequest, "验证码已失效，请重新获取")
		return
	}
	if !allowSMSVerifyAttempt(c, h.cache, "service-admin-bind-phone:"+phone, cache.KeyVerifyCode+phone) {
		return
	}
	if stored != strings.TrimSpace(req.Code) {
		response.Error(c, http.StatusBadRequest, "验证码错误")
		return
	}

	var taken int64
	h.db.Model(&models.User{}).Where("phone = ? AND id != ?", phone, user.ID).Count(&taken)
	if taken > 0 {
		response.Error(c, http.StatusBadRequest, "该手机号已被占用")
		return
	}
	if err := h.db.Model(&models.User{}).Where("id = ?", user.ID).Updates(map[string]interface{}{
		"phone":      phone,
		"updated_at": time.Now(),
	}).Error; err != nil {
		response.ServerError(c, "绑定失败")
		return
	}

	_ = h.cache.DeleteVerifyCode(ctx, phone)
	clearSMSVerifyAttempts(ctx, h.cache, "service-admin-bind-phone:"+phone)
	user.Phone = &phone

	response.Success(c, gin.H{
		"phone":   phone,
		"success": true,
	})
}
