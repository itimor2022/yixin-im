// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/gin-gonic/gin"
	"go.mongodb.org/mongo-driver/bson"
	"go.mongodb.org/mongo-driver/mongo"
	"go.mongodb.org/mongo-driver/mongo/options"
	"gorm.io/gorm"
	"gorm.io/gorm/clause" // UserHandler 用户处理器
	"log"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
	"genericim/internal/authsession"
	"genericim/internal/cache"
	"genericim/internal/models"
	"genericim/internal/privacy"
	"genericim/internal/services"
	"genericim/internal/ws"
	"genericim/pkg/response"
)

type UserHandler struct {
	db        *gorm.DB
	cache     *cache.Cache
	hub       *ws.Hub
	smsSvc    *services.SMSService
	pushSvc   *services.PushService
	relSvc    *services.RelationshipService
	mongoDB   *mongo.Database
	uploadDir string
}

const (
	deviceIdentityMismatchCode      = 1003
	deviceIdentityConflictCode      = 1004
	pushProtocolUpgradeRequiredCode = 1005
) // NewUserHandler 创建用户处理器（smsSvc 可为 nil，则无法发送绑定验证码）
func NewUserHandler(
	db *gorm.DB,
	cache *cache.Cache,
	hub *ws.Hub,
	smsSvc *services.SMSService,
	mongoDB *mongo.Database,
	uploadDir string,
	pushSvc ...*services.PushService) *UserHandler {
	var pushService *services.PushService
	if len(pushSvc) > 0 {

		pushService = pushSvc[0]
	}
	return &UserHandler{

		db: db,

		cache: cache,

		hub: hub,

		smsSvc: smsSvc,

		pushSvc: pushService,

		relSvc: services.NewRelationshipService(db),

		mongoDB: mongoDB,

		uploadDir: uploadDir,
	}
}

var deleteAccountAllowedUploadDirs = map[string]struct{}{
	"images":   {},
	"videos":   {},
	"voices":   {},
	"files":    {},
	"avatars":  {},
	"discover": {}}

// GetMe 获取当前用户信息
func (h *UserHandler) GetMe(c *gin.Context) {
	userID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	response.Success(c, user)
}

// GetPublicUser 获取可公开访问的用户资料（支持 UUID、用户名、短 ID、数字 ID）。
func (h *UserHandler) GetPublicUser(c *gin.Context) {
	identifier := strings.TrimSpace(c.Param("id"))
	identifier = strings.TrimPrefix(identifier, "@")
	if identifier == "" {

		response.BadRequest(c, "用户标识不能为空")

		return
	}
	user, err := h.findUserByPublicIdentifier(identifier)
	if err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	response.Success(c, gin.H{

		"id": user.UUID,

		"short_id": user.ShortID,

		"nickname": user.Nickname,

		"username": user.Username,

		"avatar": user.Avatar,

		"bio": user.Bio,

		"gender": user.Gender,

		"emoji_avatar": user.EmojiAvatar,

		"nickname_color": user.NicknameColor,

		"vip": h.buildVipSummary(user.ID),
	})
}
func (h *UserHandler) findUserByPublicIdentifier(identifier string) (models.User, error) {
	queries := []struct {
		where string

		args []interface{}
	}{

		{where: "uuid = ?", args: []interface{}{identifier}},

		{where: "username = ?", args: []interface{}{identifier}},
	}
	if shortID, ok := models.ParseUserShortIDKeyword(identifier); ok {

		queries = append(queries, struct {
			where string

			args []interface{}
		}{where: "short_id = ?", args: []interface{}{shortID}})
	}
	if numericID, err := strconv.ParseUint(identifier, 10, 64); err == nil && numericID > 0 {

		queries = append(queries, struct {
			where string

			args []interface{}
		}{where: "id = ?", args: []interface{}{numericID}})
	}
	var lastErr error
	for _, query := range queries {
		var user models.User

		err := h.db.Where(query.where, query.args...).First(&user).Error

		if err == nil {

			return user, nil

		}

		if !errors.Is(err, gorm.ErrRecordNotFound) {

			return models.User{}, err

		}
		lastErr = err
	}
	if lastErr == nil {

		lastErr = gorm.ErrRecordNotFound
	}
	return models.User{}, lastErr
}

// CheckUsernameRequest 检查用户名可用性请求
type CheckUsernameRequest struct {
	Username string `json:"username" binding:"required"`
}

// CheckUsername 检查用户名是否可用
func (h *UserHandler) CheckUsername(c *gin.Context) {
	userID := c.GetString("user_id")
	var req CheckUsernameRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "请输入用户名")

		return
	}
	username := req.Username
	// 验证用户名格式
	if len(username) < 3 {

		response.Success(c, gin.H{"available": false, "message": "用户名至少3个字符"})

		return
	}
	if len(username) > 20 {

		response.Success(c, gin.H{"available": false, "message": "用户名最多20个字符"})

		return
	}
	// 检查是否只包含允许的字符
	for _, ch := range username {

		if !((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '_') {

			response.Success(c, gin.H{"available": false, "message": "只能使用字母、数字和下划线"})

			return

		}
	}
	// 获取当前用户
	var currentUser models.User
	h.db.Where("uuid = ?", userID).First(&currentUser)
	// 如果是当前用户名，直接返回可用
	if username == currentUser.Username {

		response.Success(c, gin.H{"available": true, "message": "当前用户名"})

		return
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

// UpdateMeRequest 更新用户信息请求
type UpdateMeRequest struct {
	Nickname      *string `json:"nickname"`
	Username      *string `json:"username"`
	Avatar        *string `json:"avatar"`
	Bio           *string `json:"bio"`
	Gender        *string `json:"gender"`
	EmojiAvatar   *string `json:"emoji_avatar"`   // 表情头像（可为null清空）
	NicknameColor string  `json:"nickname_color"` // 昵称颜色
}

func normalizeProfileNickname(value string) (string, bool) {
	nickname := strings.TrimSpace(value)
	length := utf8.RuneCountInString(nickname)
	if length < 1 || length > 50 || strings.ContainsAny(nickname, "\r\n") {

		return "", false
	}
	return nickname, true
}
func normalizeProfileUsername(value string) (string, bool) {
	username := strings.TrimSpace(value)
	if len(username) < 3 || len(username) > 20 {

		return "", false
	}
	for _, char := range username {

		if !((char >= 'a' && char <= 'z') ||

			(char >= 'A' && char <= 'Z') ||

			(char >= '0' && char <= '9') || char == '_') {

			return "", false

		}
	}
	return username, true
}
func validateProfileBio(value string) bool {
	return utf8.RuneCountInString(value) <= 500
}

// UpdateMe 更新当前用户信息
func (h *UserHandler) UpdateMe(c *gin.Context) {
	userID := c.GetString("user_id")
	var req UpdateMeRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var nextNickname *string
	if req.Nickname != nil {

		nickname, valid := normalizeProfileNickname(*req.Nickname)

		if !valid {

			response.BadRequest(c, "昵称需为 1-50 个字符且不能包含换行")

			return

		}
		nextNickname = &nickname
	}
	var nextUsername *string
	if req.Username != nil {

		username, valid := normalizeProfileUsername(*req.Username)

		if !valid {

			response.BadRequest(c, "用户名需为 3-20 位字母、数字或下划线")

			return

		}
		nextUsername = &username
	}
	if req.Bio != nil && !validateProfileBio(*req.Bio) {

		response.BadRequest(c, "个性签名不能超过 500 个字符")

		return
	}
	// 检查用户名是否已被使用
	if nextUsername != nil && *nextUsername != user.Username {

		if !user.CredentialsInitialized {

			response.Error(c, 400, "请先在账号与安全中设置登录账号和密码")

			return

		}
		var count int64

		h.db.Model(&models.User{}).Where("username = ? AND id != ?", *nextUsername, user.ID).Count(&count)

		if count > 0 {

			response.Error(c, 400, "该用户名已被使用")

			return

		}
	}
	// 更新字段
	updates := map[string]interface{}{

		"updated_at": time.Now(),
	}
	if nextNickname != nil {

		updates["nickname"] = *nextNickname
	}
	if nextUsername != nil {

		updates["username"] = *nextUsername
	}
	if req.Avatar != nil {

		updates["avatar"] = strings.TrimSpace(*req.Avatar)
	}
	if req.Bio != nil {

		updates["bio"] = *req.Bio
	}
	if req.Gender != nil {
		gender := normalizeGender(*req.Gender)

		if gender != "male" && gender != "female" {

			response.BadRequest(c, "gender must be male or female")

			return

		}

		updates["gender"] = gender
	}
	// 表情头像（可为null清空）
	if req.EmojiAvatar != nil {

		updates["emoji_avatar"] = *req.EmojiAvatar
	}
	if req.NicknameColor != "" {

		updates["nickname_color"] = req.NicknameColor
	}
	if err := h.db.Model(&user).Updates(updates).Error; err != nil {

		response.ServerError(c, "更新失败")

		return
	}
	// 重新获取用户信息
	h.db.Where("uuid = ?", userID).First(&user)
	// 通知当前用户的其他设备同步个人资料更新
	if h.hub != nil {

		h.hub.SendToUser(userID, h.buildUserProfilePayload(user, "profile_updated", true))

		h.broadcastUserProfileToRelatedUsers(user)
	}
	response.Success(c, user)
}
func (h *UserHandler) buildVipSummary(userID uint64) gin.H {
	return buildUserVipSummary(h.db, userID)
}
func (h *UserHandler) buildUserProfilePayload(user models.User, eventType string, includePhone bool) map[string]interface{} {
	payload := map[string]interface{}{

		"type": eventType,

		"user_id": user.UUID,

		"nickname": user.Nickname,

		"username": user.Username,

		"avatar": user.Avatar,

		"bio": user.Bio,

		"gender": user.Gender,

		"emoji_avatar": user.EmojiAvatar,

		"nickname_color": user.NicknameColor,

		"vip": h.buildVipSummary(user.ID),
	}
	if includePhone {
		var phone any
		if user.Phone != nil {

			phone = *user.Phone

		}

		payload["phone"] = phone
	}
	return payload
}
func (h *UserHandler) broadcastUserProfileToRelatedUsers(user models.User) {
	if h.hub == nil || h.db == nil || user.ID == 0 || strings.TrimSpace(user.UUID) == "" {

		return
	}
	recipients := make(map[string]struct{})
	addRecipients := func(userUUIDs []string) {

		for _, userUUID := range userUUIDs {

			userUUID = strings.TrimSpace(userUUID)

			if userUUID == "" || userUUID == user.UUID {

				continue

			}

			recipients[userUUID] = struct{}{}

		}
	}
	var contactRecipientUUIDs []string
	if err := h.db.Model(&models.User{}).
		Joins("JOIN contacts ON contacts.user_id = users.id").
		Where("contacts.contact_user_id = ? AND contacts.status = 1", user.ID).
		Distinct("users.uuid").
		Pluck("users.uuid", &contactRecipientUUIDs).Error; err == nil {

		addRecipients(contactRecipientUUIDs)
	} else {

		log.Printf("[User] load profile contact recipients failed: %v", err)
	}
	var chatRecipientUUIDs []string
	if err := h.db.Model(&models.User{}).
		Joins("JOIN chat_members cm ON cm.user_id = users.id").
		Joins("JOIN chat_members self_cm ON self_cm.chat_id = cm.chat_id AND self_cm.user_id = ?", user.ID).
		Where("cm.user_id <> ?", user.ID).
		Distinct("users.uuid").
		Pluck("users.uuid", &chatRecipientUUIDs).Error; err == nil {

		addRecipients(chatRecipientUUIDs)
	} else {

		log.Printf("[User] load profile chat recipients failed: %v", err)
	}
	if len(recipients) == 0 {

		return
	}
	userUUIDs := make([]string, 0, len(recipients))
	for userUUID := range recipients {

		userUUIDs = append(userUUIDs, userUUID)
	}
	h.hub.SendToUsers(userUUIDs, h.buildUserProfilePayload(user, "user_profile", false))
}

// SendPhoneBindCode 发送绑定手机号验证码（需登录）
func (h *UserHandler) SendPhoneBindCode(c *gin.Context) {
	if h.smsSvc == nil || !h.smsSvc.CanSend() || h.cache == nil {

		response.Error(c, http.StatusServiceUnavailable, "短信服务未配置或未启用")

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
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	if user.Phone != nil && *user.Phone != "" {

		response.Error(c, 400, "已绑定手机号，如需更换请联系客服")

		return
	}
	var taken int64
	h.db.Model(&models.User{}).Where("phone = ?", phone).Count(&taken)
	if taken > 0 {

		response.Error(c, 400, "该手机号已被其他账号使用")

		return
	}
	ctx := c.Request.Context()
	ok, err := h.cache.RateLimit(ctx, "smsbind:"+phone, 1, time.Minute)
	if err != nil || !ok {

		response.Error(c, 429, "发送过于频繁，请稍后再试")

		return
	}
	code := services.GenPhoneBindCode()
	if err := h.cache.SetVerifyCode(ctx, phone, code); err != nil {

		response.ServerError(c, "验证码缓存失败")

		return
	}
	if err := h.smsSvc.SendOTP(ctx, phone, code); err != nil {

		log.Printf("[SMS] send bind code err: %v", err)
		_ = h.cache.DeleteVerifyCode(ctx, phone)

		response.Error(c, 502, "短信发送失败，请稍后重试")

		return
	}
	clearSMSVerifyAttempts(ctx, h.cache, "bind-phone:"+phone)
	response.Success(c, gin.H{"message": "验证码已发送", "expires_in": int(cache.TTLVerifyCode / time.Second)})
}

// BindPhone 校验验证码并绑定手机号（需登录）
func (h *UserHandler) BindPhone(c *gin.Context) {
	if h.cache == nil {

		response.ServerError(c, "服务异常")

		return
	}
	var req struct {
		Phone string `json:"phone" binding:"required"`

		Code string `json:"code" binding:"required"`
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
	stored, err := h.cache.GetVerifyCode(ctx, phone)
	if err != nil || stored == "" {

		response.Error(c, 400, "验证码已失效，请重新获取")

		return
	}
	if !allowSMSVerifyAttempt(c, h.cache, "bind-phone:"+phone, cache.KeyVerifyCode+phone) {

		return
	}
	if stored != strings.TrimSpace(req.Code) {

		response.Error(c, 400, "验证码错误")

		return
	}
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	if user.Phone != nil && *user.Phone != "" {

		response.Error(c, 400, "已绑定手机号")

		return
	}
	var taken int64
	h.db.Model(&models.User{}).Where("phone = ? AND id != ?", phone, user.ID).Count(&taken)
	if taken > 0 {

		response.Error(c, 400, "该手机号已被占用")

		return
	}
	if err := h.db.Model(&user).Updates(map[string]interface{}{

		"phone": phone,

		"updated_at": time.Now(),
	}).Error; err != nil {

		response.ServerError(c, "绑定失败")

		return
	}
	_ = h.cache.DeleteVerifyCode(ctx, phone)
	clearSMSVerifyAttempts(ctx, h.cache, "bind-phone:"+phone)
	h.db.Where("uuid = ?", userUUID).First(&user)
	if h.hub != nil {
		var phone any
		if user.Phone != nil {

			phone = *user.Phone

		}

		h.hub.SendToUser(userUUID, map[string]interface{}{

			"type": "profile_updated", "user_id": user.UUID,

			"nickname": user.Nickname, "username": user.Username, "avatar": user.Avatar,

			"bio": user.Bio, "emoji_avatar": user.EmojiAvatar, "nickname_color": user.NicknameColor,

			"phone": phone,
		})
	}
	response.Success(c, user)
}
func (h *UserHandler) requireBoundPhone(user models.User) (string, bool) {
	if user.Phone == nil {

		return "", false
	}
	phone := strings.TrimSpace(*user.Phone)
	return phone, phone != ""
}

// SendPasswordChangeCode 发送短信验证码用于修改登录密码
func (h *UserHandler) SendPasswordChangeCode(c *gin.Context) {
	if h.smsSvc == nil || !h.smsSvc.CanSend() || h.cache == nil {

		response.Error(c, http.StatusServiceUnavailable, "短信服务不可用")

		return
	}
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	phone, ok := h.requireBoundPhone(user)
	if !ok {

		response.Error(c, 400, "请先绑定手机号")

		return
	}
	ctx := c.Request.Context()
	allow, err := h.cache.RateLimit(ctx, "smspwd:"+phone, 1, time.Minute)
	if err != nil || !allow {

		response.Error(c, 429, "发送过于频繁，请稍后再试")

		return
	}
	code := services.GenPhoneBindCode()
	cacheKey := "verify:change_password:" + user.UUID
	if err := h.cache.Set(ctx, cacheKey, code, cache.TTLVerifyCode); err != nil {

		response.ServerError(c, "验证码缓存失败")

		return
	}
	if err := h.smsSvc.SendOTP(ctx, phone, code); err != nil {

		_ = h.cache.Delete(ctx, cacheKey)

		response.Error(c, 502, "短信发送失败，请稍后重试")

		return
	}
	clearSMSVerifyAttempts(ctx, h.cache, "change-password:"+user.UUID)
	response.Success(c, gin.H{

		"message": "验证码已发送",

		"expires_in": int(cache.TTLVerifyCode / time.Second),
	})
}

// ChangePasswordByCode 通过验证码修改登录密码
func (h *UserHandler) ChangePasswordByCode(c *gin.Context) {
	if h.cache == nil {

		response.ServerError(c, "服务异常")

		return
	}
	var req struct {
		Code string `json:"code" binding:"required"`

		NewPassword string `json:"new_password" binding:"required,min=6,max=20"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	if _, ok := h.requireBoundPhone(user); !ok {

		response.Error(c, 400, "请先绑定手机号")

		return
	}
	cacheKey := "verify:change_password:" + user.UUID
	var storedCode string
	if err := h.cache.Get(c.Request.Context(), cacheKey, &storedCode); err != nil || storedCode == "" {

		response.Error(c, 400, "验证码已失效，请重新获取")

		return
	}
	if !allowSMSVerifyAttempt(c, h.cache, "change-password:"+user.UUID, cacheKey) {

		return
	}
	if strings.TrimSpace(req.Code) != storedCode {

		response.Error(c, 400, "验证码错误")

		return
	}
	if err := user.SetPassword(req.NewPassword); err != nil {

		response.ServerError(c, "修改失败")

		return
	}
	if err := h.db.Model(&user).Updates(map[string]interface{}{

		"password": user.Password,

		"updated_at": time.Now(),
	}).Error; err != nil {

		response.ServerError(c, "修改失败")

		return
	}
	_ = h.cache.Delete(c.Request.Context(), cacheKey)
	clearSMSVerifyAttempts(c.Request.Context(), h.cache, "change-password:"+user.UUID)
	authsession.MarkPasswordReset(c.Request.Context(), h.cache, user.UUID)
	response.SuccessWithMessage(c, "密码修改成功", nil)
}

// SendDeleteAccountCode 发送注销账号验证码
func (h *UserHandler) SendDeleteAccountCode(c *gin.Context) {
	if h.smsSvc == nil || !h.smsSvc.CanSend() || h.cache == nil {

		response.Error(c, http.StatusServiceUnavailable, "短信服务不可用")

		return
	}
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	phone, ok := h.requireBoundPhone(user)
	if !ok {

		response.Error(c, 400, "请先绑定手机号")

		return
	}
	ctx := c.Request.Context()
	allow, err := h.cache.RateLimit(ctx, "smsdel:"+phone, 1, time.Minute)
	if err != nil || !allow {

		response.Error(c, 429, "发送过于频繁，请稍后再试")

		return
	}
	code := services.GenPhoneBindCode()
	cacheKey := "verify:delete_account:" + user.UUID
	if err := h.cache.Set(ctx, cacheKey, code, cache.TTLVerifyCode); err != nil {

		response.ServerError(c, "验证码缓存失败")

		return
	}
	if err := h.smsSvc.SendOTP(ctx, phone, code); err != nil {

		_ = h.cache.Delete(ctx, cacheKey)

		response.Error(c, 502, "短信发送失败，请稍后重试")

		return
	}
	clearSMSVerifyAttempts(ctx, h.cache, "delete-account:"+user.UUID)
	response.Success(c, gin.H{

		"message": "验证码已发送",

		"expires_in": int(cache.TTLVerifyCode / time.Second),
	})
}

// GetUser 获取指定用户信息（支持数字ID和UUID）
func (h *UserHandler) GetUser(c *gin.Context) {
	// 这是对外资料接口：在线状态和最后活跃时间必须经过隐私服务裁决，不能直接透传用户表字段。
	userIDParam := c.Param("id")
	currentUserUUID := strings.TrimSpace(c.GetString("user_id"))
	var user models.User
	// 尝试用 UUID 查询，如果失败则用数字 ID 查询
	if err := h.db.Where("uuid = ?", userIDParam).First(&user).Error; err != nil {

		// UUID 查询失败，尝试用数字 ID 查询

		if err := h.db.First(&user, userIDParam).Error; err != nil {

			response.NotFound(c, "用户不存在")

			return

		}
	}
	// 使用 WebSocket hub 检查实时在线状态
	// 这与 /chat/{id} API 使用相同的数据源，保证一致性
	status := user.Status
	canSeeOnlineStatus, err := privacy.CanViewerSeeOnlineStatusByUUID(h.db, currentUserUUID, user.UUID)
	if err != nil {

		canSeeOnlineStatus = false
	}
	if canSeeOnlineStatus && h.hub != nil {

		if h.hub.IsUserOnline(user.UUID) {

			status = 1 // 在线

		} else {

			status = 0 // 离线

		}
	} else if !canSeeOnlineStatus {

		status = 0
	}
	var lastSeen interface{}
	if canSeeOnlineStatus {

		lastSeen = user.LastSeen
	}
	// 返回公开信息
	response.Success(c, gin.H{

		"id": user.UUID,

		"user_id": user.ID, // 同时返回数字ID

		"short_id": user.ShortID,

		"nickname": user.Nickname,

		"username": user.Username,

		"avatar": user.Avatar,

		"bio": user.Bio,

		"status": status, // 使用实时在线状态

		"last_seen": lastSeen,

		"emoji_avatar": user.EmojiAvatar, // 表情状态

		"nickname_color": user.NicknameColor, // 个人资料背景颜色

		"vip": h.buildVipSummary(user.ID),
	})
}
func (h *UserHandler) searchUsersExactFirst(currentUserUUID, keyword string, limit int) []models.User {
	if limit <= 0 {

		return []models.User{}
	}
	shortID, hasShortID := models.ParseUserShortIDKeyword(keyword)
	baseQuery := func() *gorm.DB {

		return h.db.Model(&models.User{}).
			Select("users.*").
			Joins("LEFT JOIN user_privacy_settings ups ON ups.user_id = users.id").
			Where("users.uuid != ?", currentUserUUID)
	}
	exactQuery := baseQuery()
	if hasShortID {

		exactQuery = exactQuery.Where(

			"(users.uuid = ? OR users.username = ? OR (users.phone = ? AND COALESCE(ups.allow_phone_search, 1) = 1) OR (users.short_id = ? AND COALESCE(ups.allow_short_id_search, 1) = 1))",

			keyword, keyword, keyword, shortID,
		).Order(gorm.Expr(

			"CASE WHEN users.username = ? THEN 0 WHEN users.phone = ? THEN 1 WHEN users.short_id = ? THEN 2 WHEN users.uuid = ? THEN 3 ELSE 4 END",

			keyword, keyword, shortID, keyword,
		))
	} else {

		exactQuery = exactQuery.Where(

			"(users.uuid = ? OR users.username = ? OR (users.phone = ? AND COALESCE(ups.allow_phone_search, 1) = 1))",

			keyword, keyword, keyword,
		).Order(gorm.Expr(

			"CASE WHEN users.username = ? THEN 0 WHEN users.phone = ? THEN 1 WHEN users.uuid = ? THEN 2 ELSE 3 END",

			keyword, keyword, keyword,
		))
	}
	users := make([]models.User, 0, limit)
	exactQuery.Limit(limit).Find(&users)
	if len(users) >= limit {

		return users
	}
	seenIDs := make([]uint64, 0, len(users))
	for _, user := range users {

		seenIDs = append(seenIDs, user.ID)
	}
	keywordLike := "%" + keyword + "%"
	fuzzyQuery := baseQuery().
		Where("(users.nickname LIKE ? OR users.username LIKE ?)", keywordLike, keywordLike).
		Order(gorm.Expr(

			"CASE WHEN users.username LIKE ? THEN 0 WHEN users.nickname LIKE ? THEN 1 ELSE 2 END",

			keyword+"%", keyword+"%",
		)).
		Order("users.last_seen DESC").
		Limit(limit - len(users))
	if len(seenIDs) > 0 {

		fuzzyQuery = fuzzyQuery.Where("users.id NOT IN ?", seenIDs)
	}
	var fuzzyUsers []models.User
	fuzzyQuery.Find(&fuzzyUsers)
	users = append(users, fuzzyUsers...)
	return users
}

// SearchUsers 搜索用户
type UpdateNearbyLocationRequest struct {
	Latitude      float64 `json:"latitude"`
	Longitude     float64 `json:"longitude"`
	NearbyVisible *bool   `json:"nearby_visible"`
	Gender        *string `json:"gender"`
}

func (h *UserHandler) UpdateNearbyLocation(c *gin.Context) {
	userUUID := c.GetString("user_id")
	var req UpdateNearbyLocationRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	if req.Latitude < -90 || req.Latitude > 90 || req.Longitude < -180 || req.Longitude > 180 {

		response.BadRequest(c, "位置坐标无效")

		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	now := time.Now()
	updates := map[string]interface{}{

		"latitude": req.Latitude,

		"longitude": req.Longitude,

		"location_at": now,

		"updated_at": now,
	}
	if req.NearbyVisible != nil {

		updates["nearby_visible"] = *req.NearbyVisible
	} else {

		updates["nearby_visible"] = true
	}
	if req.Gender != nil {
		gender := normalizeGender(*req.Gender)

		if gender != "male" && gender != "female" {

			response.BadRequest(c, "gender must be male or female")

			return

		}

		updates["gender"] = gender
	}
	if err := h.db.Model(&user).Updates(updates).Error; err != nil {

		response.ServerError(c, "更新附近位置失败")

		return
	}
	if err := h.db.Where("id = ?", user.ID).First(&user).Error; err != nil {

		response.ServerError(c, "更新附近位置失败")

		return
	}
	response.Success(c, gin.H{

		"nearby_visible": user.NearbyVisible,

		"latitude": user.Latitude,

		"longitude": user.Longitude,

		"location_at": user.LocationAt,

		"gender": user.Gender,
	})
}
func (h *UserHandler) SearchNearbyUsers(c *gin.Context) {
	userUUID := c.GetString("user_id")
	var currentUser models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&currentUser).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	lat, latOK := parseFloatQuery(c.Query("latitude"))
	lng, lngOK := parseFloatQuery(c.Query("longitude"))
	if !latOK || !lngOK {

		if currentUser.Latitude == nil || currentUser.Longitude == nil {

			response.BadRequest(c, "请先授权当前位置")

			return

		}
		lat = *currentUser.Latitude

		lng = *currentUser.Longitude
	}
	if lat < -90 || lat > 90 || lng < -180 || lng > 180 {

		response.BadRequest(c, "位置坐标无效")

		return
	}
	radiusKM, ok := parseFloatQuery(c.DefaultQuery("radius_km", "10"))
	if !ok || radiusKM <= 0 {

		radiusKM = 10
	}
	if radiusKM > 200 {

		radiusKM = 200
	}
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page < 1 {

		page = 1
	}
	if pageSize < 1 || pageSize > 100 {

		pageSize = 20
	}
	offset := (page - 1) * pageSize
	gender := normalizeGender(c.Query("gender"))
	hasAvatar := strings.ToLower(strings.TrimSpace(c.Query("has_avatar")))
	cutoff := time.Now().Add(-30 * 24 * time.Hour)
	type nearbyRow struct {
		ID uint64 `gorm:"column:id"`

		UUID string `gorm:"column:uuid"`

		ShortID *uint64 `gorm:"column:short_id"`

		Nickname string `gorm:"column:nickname"`

		Username string `gorm:"column:username"`

		Avatar string `gorm:"column:avatar"`

		Bio string `gorm:"column:bio"`

		Gender string `gorm:"column:gender"`

		EmojiAvatar string `gorm:"column:emoji_avatar"`

		NicknameColor string `gorm:"column:nickname_color"`

		LocationAt *time.Time `gorm:"column:location_at"`

		DistanceKM float64 `gorm:"column:distance_km"`

		ContactID *uint64 `gorm:"column:contact_id"`
	}
	sql := ` SELECT 
users.id, 
users.uuid, 
users.short_id, 
users.nickname, 
users.username, 
users.avatar, 
users.bio, 
users.gender, 
users.emoji_avatar, 
users.nickname_color, 
users.location_at, 
contacts.id AS contact_id, 
(6371 * ACOS(LEAST(1, GREATEST(-1, 

COS(RADIANS(?)) * COS(RADIANS(users.latitude)) * 

COS(RADIANS(users.longitude) - RADIANS(?)) + 

SIN(RADIANS(?)) * SIN(RADIANS(users.latitude)) 
)))) AS distance_km FROM users LEFT JOIN contacts ON contacts.user_id = ? AND contacts.contact_user_id = users.id AND contacts.status = 1 WHERE users.deleted_at IS NULL 
AND users.status = ? 
AND users.id <> ? 
AND users.nearby_visible = ? 
AND users.latitude IS NOT NULL 
AND users.longitude IS NOT NULL 
AND users.location_at IS NOT NULL 
AND users.location_at >= ?`
	args := []interface{}{lat, lng, lat, currentUser.ID, models.UserStatusNormal, currentUser.ID, true, cutoff}
	if gender != "" && gender != "unknown" {

		sql += " AND users.gender = ?"

		args = append(args, gender)
	}
	switch hasAvatar {
	case "true", "1", "yes":

		sql += " AND TRIM(users.avatar) <> ''"
	case "false", "0", "no":

		sql += " AND (users.avatar IS NULL OR TRIM(users.avatar) = '')"
	}
	sql += " HAVING distance_km <= ? ORDER BY distance_km ASC LIMIT ? OFFSET ?"
	args = append(args, radiusKM, pageSize, offset)
	var rows []nearbyRow
	if err := h.db.Raw(sql, args...).Scan(&rows).Error; err != nil {

		response.ServerError(c, "搜索附近的人失败")

		return
	}
	userIDs := make([]uint64, 0, len(rows))
	for _, row := range rows {

		userIDs = append(userIDs, row.ID)
	}
	vipSummaries := buildUserVipSummaries(h.db, userIDs)
	list := make([]gin.H, 0, len(rows))
	for _, row := range rows {

		list = append(list, gin.H{

			"id": row.UUID,

			"short_id": row.ShortID,

			"name": row.Nickname,

			"nickname": row.Nickname,

			"username": row.Username,

			"avatar": row.Avatar,

			"bio": row.Bio,

			"gender": row.Gender,

			"distance_km": row.DistanceKM,

			"location_at": row.LocationAt,

			"is_contact": row.ContactID != nil,

			"type": "user",

			"vip": vipSummaries[row.ID],

			"emoji_avatar": row.EmojiAvatar,

			"nickname_color": row.NicknameColor,
		})
	}
	response.Success(c, gin.H{

		"list": list,

		"total": len(list),

		"page": page,

		"page_size": pageSize,

		"radius_km": radiusKM,
	})
}
func parseFloatQuery(value string) (float64, bool) {
	value = strings.TrimSpace(value)
	if value == "" {

		return 0, false
	}
	parsed, err := strconv.ParseFloat(value, 64)
	if err != nil {

		return 0, false
	}
	return parsed, true
}
func normalizeGender(value string) string {
	switch strings.ToLower(strings.TrimSpace(value)) {
	case "male", "m", "男", "男生":

		return "male"
	case "female", "f", "女", "女生":

		return "female"
	case "other", "其他":

		return "other"
	default:

		return "unknown"
	}
}
func (h *UserHandler) SearchUsers(c *gin.Context) {
	keyword := strings.TrimSpace(c.Query("keyword"))
	if keyword == "" {

		response.BadRequest(c, "请输入搜索关键词")

		return
	}
	currentUserID := c.GetString("user_id")
	users := h.searchUsersExactFirst(currentUserID, keyword, 20)
	// 转换为公开信息
	userIDs := make([]uint64, 0, len(users))
	for _, u := range users {

		userIDs = append(userIDs, u.ID)
	}
	vipSummaries := buildUserVipSummaries(h.db, userIDs)
	result := make([]gin.H, 0, len(users))
	for _, u := range users {

		result = append(result, gin.H{

			"id": u.UUID,

			"short_id": u.ShortID,

			"nickname": u.Nickname,

			"username": u.Username,

			"avatar": u.Avatar,

			"bio": u.Bio,

			"gender": u.Gender,

			"type": "user",

			"vip": vipSummaries[u.ID],

			"emoji_avatar": u.EmojiAvatar,

			"nickname_color": u.NicknameColor,
		})
	}
	response.Success(c, gin.H{

		"list": result,

		"total": len(result),
	})
}

// SearchAll 搜索用户和公开群组/频道
func (h *UserHandler) SearchAll(c *gin.Context) {
	keyword := strings.TrimSpace(c.Query("keyword"))
	searchType := c.DefaultQuery("type", "all") // all, user, group, channel
	if keyword == "" {

		response.BadRequest(c, "请输入搜索关键词")

		return
	}
	currentUserID := c.GetString("user_id")
	result := make([]gin.H, 0)
	// 获取当前用户
	var currentUser models.User
	h.db.Where("uuid = ?", currentUserID).First(&currentUser)
	// 搜索用户
	if searchType == "all" || searchType == "user" {
		users := h.searchUsersExactFirst(currentUserID, keyword, 10)
		userIDs := make([]uint64, 0, len(users))

		for _, u := range users {

			userIDs = append(userIDs, u.ID)

		}
		vipSummaries := buildUserVipSummaries(h.db, userIDs)

		for _, u := range users {

			result = append(result, gin.H{

				"id": u.UUID,

				"short_id": u.ShortID,

				"name": u.Nickname,

				"username": u.Username,

				"avatar": u.Avatar,

				"bio": u.Bio,

				"gender": u.Gender,

				"type": "user",

				"member_count": 0,

				"is_member": false,

				"vip": vipSummaries[u.ID],

				"emoji_avatar": u.EmojiAvatar,

				"nickname_color": u.NicknameColor,
			})

		}
	}
	// 搜索公开群组
	if searchType == "all" || searchType == "group" {
		var groups []models.Chat

		h.db.Where("type = 2 AND is_public = true AND (name LIKE ? OR username LIKE ?)",

			"%"+keyword+"%", "%"+keyword+"%").
			Order(gorm.Expr(

				"CASE WHEN username = ? THEN 0 WHEN name = ? THEN 1 WHEN username LIKE ? THEN 2 ELSE 3 END",

				keyword, keyword, keyword+"%",
			)).
			Limit(10).
			Find(&groups)

		for _, g := range groups {

			// 检查当前用户是否是成员
			var isMember bool
			if currentUser.ID > 0 {
				var count int64

				h.db.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id = ?", g.ID, currentUser.ID).Count(&count)
				isMember = count > 0

			}
			result = append(result, gin.H{

				"id": g.UUID,

				"name": g.Name,

				"username": g.Username,

				"avatar": g.Avatar,

				"bio": g.Description,

				"type": "group",

				"member_count": g.MemberCount,

				"is_member": isMember,
			})

		}
	}
	// 搜索公开频道
	if searchType == "all" || searchType == "channel" {
		var channels []models.Chat

		h.db.Where("type = 3 AND is_public = true AND (name LIKE ? OR username LIKE ?)",

			"%"+keyword+"%", "%"+keyword+"%").
			Order(gorm.Expr(

				"CASE WHEN username = ? THEN 0 WHEN name = ? THEN 1 WHEN username LIKE ? THEN 2 ELSE 3 END",

				keyword, keyword, keyword+"%",
			)).
			Limit(10).
			Find(&channels)

		for _, ch := range channels {

			// 检查当前用户是否已订阅
			var isMember bool
			if currentUser.ID > 0 {
				var count int64

				h.db.Model(&models.ChatMember{}).Where("chat_id = ? AND user_id = ?", ch.ID, currentUser.ID).Count(&count)
				isMember = count > 0

			}
			result = append(result, gin.H{

				"id": ch.UUID,

				"name": ch.Name,

				"username": ch.Username,

				"avatar": ch.Avatar,

				"bio": ch.Description,

				"type": "channel",

				"member_count": ch.MemberCount,

				"is_member": isMember,
			})

		}
	}
	response.Success(c, gin.H{

		"list": result,

		"total": len(result),
	})
}

// GetCommonGroups 获取与指定用户的共同群组（支持数字ID和UUID）
func (h *UserHandler) GetCommonGroups(c *gin.Context) {
	commonGroups, err := h.relSvc.CommonGroups(

		c.Request.Context(),

		c.GetString("user_id"),

		c.Param("id"),
	)
	if err != nil {

		h.respondRelationshipError(c, err)

		return
	}
	groups := make([]gin.H, 0, len(commonGroups))
	for _, g := range commonGroups {

		groups = append(groups, gin.H{

			"id": g.ID,

			"name": g.Name,

			"avatar": g.Avatar,

			"type": g.Type,

			"member_count": g.MemberCount,
		})
	}
	response.Success(c, gin.H{

		"groups": groups,

		"total": len(groups),
	})
}

// GetCommonInfo 获取与指定用户的共同关系摘要（共同群聊、共同联系人）
func (h *UserHandler) GetCommonInfo(c *gin.Context) {
	info, err := h.relSvc.CommonInfo(

		c.Request.Context(),

		c.GetString("user_id"),

		c.Param("id"),

		3,
	)
	if err != nil {

		h.respondRelationshipError(c, err)

		return
	}
	contacts := make([]gin.H, 0, len(info.CommonContacts))
	for _, row := range info.CommonContacts {

		contacts = append(contacts, gin.H{

			"id": row.ID,

			"username": row.Username,

			"nickname": row.Nickname,

			"avatar": row.Avatar,
		})
	}
	response.Success(c, gin.H{

		"common_group_count": info.CommonGroupCount,

		"common_contact_count": info.CommonContactCount,

		"common_contacts": contacts,
	})
}
func (h *UserHandler) respondRelationshipError(c *gin.Context, err error) {
	switch {
	case errors.Is(err, services.ErrRelationshipCurrentUserNotFound):

		response.Unauthorized(c, "用户未登录")
	case errors.Is(err, services.ErrRelationshipTargetUserNotFound):

		response.NotFound(c, "用户不存在")
	default:

		response.ServerError(c, "获取共同信息失败")
	}
}

// ========== 隐私设置相关 API ==========  // GetPrivacySettings 获取隐私设置
func defaultUserPrivacySetting(userID uint64) models.UserPrivacySetting {
	return models.UserPrivacySetting{

		UserID: userID,

		LastSeenVisibility: "所有人",

		PhoneVisibility: "联系人",

		GroupInvitePermission: "所有人",

		AllowPhoneSearch: true,

		AllowShortIDSearch: true,

		SendReadReceipts: true,

		ShowTypingStatus: true,

		DeviceLockEnabled: false,

		TwoStepEnabled: false,

		AutoDeleteAccount: "6 个月",
	}
}
func (h *UserHandler) GetPrivacySettings(c *gin.Context) {
	userID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var settings models.UserPrivacySetting
	if err := h.db.Where("user_id = ?", user.ID).First(&settings).Error; err != nil {

		if !errors.Is(err, gorm.ErrRecordNotFound) {

			response.ServerError(c, "获取隐私设置失败")

			return

		}

		// 如果不存在，创建默认设置

		settings = defaultUserPrivacySetting(user.ID)

		if createErr := h.db.Create(&settings).Error; createErr != nil {

			response.ServerError(c, "初始化隐私设置失败")

			return

		}
	}
	response.Success(c, settings)
}

// UpdatePrivacySettingsRequest 更新隐私设置请求
type UpdatePrivacySettingsRequest struct {
	LastSeenVisibility    string `json:"last_seen_visibility"`
	PhoneVisibility       string `json:"phone_visibility"`
	GroupInvitePermission string `json:"group_invite_permission"`
	AllowPhoneSearch      *bool  `json:"allow_phone_search"`
	AllowShortIDSearch    *bool  `json:"allow_short_id_search"`
	SendReadReceipts      *bool  `json:"send_read_receipts"`
	ShowTypingStatus      *bool  `json:"show_typing_status"`
	DeviceLockEnabled     *bool  `json:"device_lock_enabled"`
	TwoStepEnabled        *bool  `json:"two_step_enabled"`
	AutoDeleteAccount     string `json:"auto_delete_account"`
}

// UpdatePrivacySettings 更新隐私设置
func (h *UserHandler) UpdatePrivacySettings(c *gin.Context) {
	// 此记录是搜索、在线状态、手机号展示和群邀请等下游能力的统一权限来源。
	userID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var req UpdatePrivacySettingsRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	// 获取或创建设置
	var settings models.UserPrivacySetting
	if err := h.db.Where("user_id = ?", user.ID).First(&settings).Error; err != nil {

		if !errors.Is(err, gorm.ErrRecordNotFound) {

			response.ServerError(c, "获取隐私设置失败")

			return

		}
		settings = defaultUserPrivacySetting(user.ID)
	}
	// 更新字段（只更新非空值）
	if req.LastSeenVisibility != "" {

		settings.LastSeenVisibility = req.LastSeenVisibility
	}
	if req.PhoneVisibility != "" {

		settings.PhoneVisibility = req.PhoneVisibility
	}
	if req.GroupInvitePermission != "" {

		settings.GroupInvitePermission = req.GroupInvitePermission
	}
	if req.AllowPhoneSearch != nil {

		settings.AllowPhoneSearch = *req.AllowPhoneSearch
	}
	if req.AllowShortIDSearch != nil {

		settings.AllowShortIDSearch = *req.AllowShortIDSearch
	}
	if req.SendReadReceipts != nil {

		settings.SendReadReceipts = *req.SendReadReceipts
	}
	if req.ShowTypingStatus != nil {

		settings.ShowTypingStatus = *req.ShowTypingStatus
	}
	if req.DeviceLockEnabled != nil {

		settings.DeviceLockEnabled = *req.DeviceLockEnabled
	}
	if req.TwoStepEnabled != nil {

		response.Error(c, twoStepClientUpgradeCode, "请使用专用的两步验证安全接口")

		return
	}
	if req.AutoDeleteAccount != "" {

		settings.AutoDeleteAccount = req.AutoDeleteAccount
	}
	if err := h.db.Save(&settings).Error; err != nil {

		response.ServerError(c, "保存失败")

		return
	}
	response.Success(c, settings)
}

// ========== 表情商店云同步 API ==========
type UpdateEmojiStoreRequest struct {
	InstalledPackIDs []string                 `json:"installed_pack_ids"`
	FavoriteCodes    []string                 `json:"favorite_codes"`
	CustomEmojis     []map[string]interface{} `json:"custom_emojis"`
	BaseUpdatedAt    string                   `json:"base_updated_at"`
}

const (
	emojiStoreMaxPayloadBytes  = 512 * 1024
	emojiStoreMaxInstalled     = 200
	emojiStoreMaxFavorites     = 500
	emojiStoreMaxCustomEmojis  = 300
	emojiStoreMaxPackIDRunes   = 64
	emojiStoreMaxFavoriteRunes = 128
	emojiStoreMaxCustomIDRunes = 64
	emojiStoreMaxPathRunes     = 1024
	emojiStoreMaxCatalogPacks  = 200
	emojiStoreMaxPackNameRunes = 100
	emojiStoreMaxPackDescRunes = 255
	emojiStoreMaxStickerFiles  = 1000
)

func trimAndClampRunes(v string, maxRunes int) string {
	s := strings.TrimSpace(v)
	if s == "" {

		return ""
	}
	if maxRunes <= 0 {

		return s
	}
	if utf8.RuneCountInString(s) <= maxRunes {

		return s
	}
	runes := []rune(s)
	return string(runes[:maxRunes])
}
func sanitizeStringList(
	raw []string,
	maxItems int,
	maxRunes int,
	allow func(string) bool) []string {
	if len(raw) == 0 {

		return []string{}
	}
	out := make([]string, 0, len(raw))
	seen := make(map[string]struct{}, len(raw))
	for _, v := range raw {
		item := trimAndClampRunes(v, maxRunes)

		if item == "" {

			continue

		}

		if allow != nil && !allow(item) {

			continue

		}

		if _, ok := seen[item]; ok {

			continue

		}

		seen[item] = struct{}{}
		out = append(out, item)

		if maxItems > 0 && len(out) >= maxItems {

			break

		}
	}
	return out
}
func sanitizeCustomEmojiList(raw []map[string]interface{}) []map[string]interface{} {
	if len(raw) == 0 {

		return []map[string]interface{}{}
	}
	out := make([]map[string]interface{}, 0, len(raw))
	seenIDs := make(map[string]struct{}, len(raw))
	for _, item := range raw {
		id := trimAndClampRunes(toTrimmedString(item["id"]), emojiStoreMaxCustomIDRunes)

		if id == "" {

			continue

		}

		if _, ok := seenIDs[id]; ok {

			continue

		}
		path := trimAndClampRunes(toTrimmedString(item["path"]), emojiStoreMaxPathRunes)

		if path != "" && !isHTTPURL(path) && !isUploadRelativePath(path) {

			// 云端只保留可跨设备复用的路径（HTTP URL 或 /uploads/...）

			path = ""

		}
		remoteURL := trimAndClampRunes(toTrimmedString(item["remote_url"]), emojiStoreMaxPathRunes)

		if remoteURL != "" && !isHTTPURL(remoteURL) {

			remoteURL = ""

		}

		if remoteURL == "" && isHTTPURL(path) {

			remoteURL = path

			path = ""

		}

		if path == "" && remoteURL == "" {

			continue

		}
		createdAt := normalizeTimeString(toTrimmedString(item["created_at"]))
		next := map[string]interface{}{

			"id": id,

			"path": path,

			"created_at": createdAt,
		}

		if remoteURL != "" {

			next["remote_url"] = remoteURL

		}
		out = append(out, next)

		seenIDs[id] = struct{}{}

		if len(out) >= emojiStoreMaxCustomEmojis {

			break

		}
	}
	return out
}
func filterInstalledPackIDsByActiveCatalog(installed []string, activePackIDs map[string]struct{}) []string {
	if len(installed) == 0 {

		return []string{}
	}
	if len(activePackIDs) == 0 {

		return installed
	}
	out := make([]string, 0, len(installed))
	for _, id := range installed {

		if _, ok := activePackIDs[id]; ok {

			out = append(out, id)

		}
	}
	return out
}
func activeCatalogPackIDSet(db *gorm.DB) map[string]struct{} {
	var rows []models.EmojiStorePackCatalog
	if err := db.Model(&models.EmojiStorePackCatalog{}).
		Select("pack_id").
		Where("is_active = ?", true).
		Find(&rows).Error; err != nil {

		return map[string]struct{}{}
	}
	if len(rows) == 0 {

		return map[string]struct{}{}
	}
	out := make(map[string]struct{}, len(rows))
	for _, row := range rows {
		id := trimAndClampRunes(row.PackID, emojiStoreMaxPackIDRunes)

		if id == "" {

			continue

		}

		out[id] = struct{}{}
	}
	return out
}
func filterFavoriteCodesWithCustomEmojis(favorites []string, customEmojis []map[string]interface{}) []string {
	if len(favorites) == 0 {

		return []string{}
	}
	customIDs := make(map[string]struct{}, len(customEmojis))
	for _, item := range customEmojis {
		id := trimAndClampRunes(toTrimmedString(item["id"]), emojiStoreMaxCustomIDRunes)

		if id == "" {

			continue

		}

		customIDs[id] = struct{}{}
	}
	out := make([]string, 0, len(favorites))
	for _, code := range favorites {

		switch {

		case strings.HasPrefix(code, "emoji:"):

			out = append(out, code)

		case strings.HasPrefix(code, "custom:"):

			id := strings.TrimPrefix(code, "custom:")

			if _, ok := customIDs[id]; ok {

				out = append(out, code)

			}

		}
	}
	return out
}
func toTrimmedString(v interface{}) string {
	if v == nil {

		return ""
	}
	s, ok := v.(string)
	if !ok {

		return ""
	}
	return strings.TrimSpace(s)
}
func normalizeTimeString(v string) string {
	s := strings.TrimSpace(v)
	if s == "" {

		return time.Now().UTC().Format(time.RFC3339)
	}
	if t, err := time.Parse(time.RFC3339Nano, s); err == nil {

		return t.UTC().Format(time.RFC3339)
	}
	if t, err := time.Parse(time.RFC3339, s); err == nil {

		return t.UTC().Format(time.RFC3339)
	}
	return time.Now().UTC().Format(time.RFC3339)
}
func isHTTPURL(v string) bool {
	return strings.HasPrefix(v, "http://") || strings.HasPrefix(v, "https://")
}
func isUploadRelativePath(v string) bool {
	s := strings.ReplaceAll(strings.TrimSpace(v), "\\", "/")
	return strings.HasPrefix(s, "/uploads/") || strings.HasPrefix(s, "uploads/")
}
func decodeJSONList(raw string) []interface{} {
	if strings.TrimSpace(raw) == "" {

		return []interface{}{}
	}
	var out []interface{}
	if err := json.Unmarshal([]byte(raw), &out); err != nil {

		return []interface{}{}
	}
	return out
}
func encodeJSON(v interface{}) string {
	b, err := json.Marshal(v)
	if err != nil {

		return "[]"
	}
	return string(b)
}
func parseRFC3339Time(v string) (time.Time, bool) {
	s := strings.TrimSpace(v)
	if s == "" {

		return time.Time{}, false
	}
	if t, err := time.Parse(time.RFC3339Nano, s); err == nil {

		return t.UTC(), true
	}
	if t, err := time.Parse(time.RFC3339, s); err == nil {

		return t.UTC(), true
	}
	return time.Time{}, false
}
func buildEmojiStoreSyncPayload(setting models.UserEmojiStoreSetting) gin.H {
	return gin.H{

		"installed_pack_ids": sanitizeStringList(

			interfaceSliceToStringSlice(decodeJSONList(setting.InstalledPackIDs)),

			emojiStoreMaxInstalled,

			emojiStoreMaxPackIDRunes,

			nil,
		),

		"favorite_codes": sanitizeStringList(

			interfaceSliceToStringSlice(decodeJSONList(setting.FavoriteCodes)),

			emojiStoreMaxFavorites,

			emojiStoreMaxFavoriteRunes,

			func(v string) bool {

				return strings.HasPrefix(v, "emoji:") || strings.HasPrefix(v, "custom:")

			},
		),

		"custom_emojis": sanitizeCustomEmojiList(

			interfaceSliceToMapSlice(decodeJSONList(setting.CustomEmojis)),
		),

		"updated_at": setting.UpdatedAt.UTC().Format(time.RFC3339),
	}
}

type emojiStoreCatalogSeed struct {
	PackID       string
	Name         string
	Description  string
	PreviewEmoji string
	PreviewFile  string
	StickerFiles []string
}

func defaultEmojiStoreCatalogSeeds() []emojiStoreCatalogSeed {
	return []emojiStoreCatalogSeed{

		{

			PackID: "animated_faces",

			Name: "动态笑脸",

			Description: "丰富的表情动画",

			PreviewEmoji: "😂",

			PreviewFile: "joy.json",

			StickerFiles: []string{

				"joy.json", "laughing.json", "smiling.json", "wink.json",

				"heart_eyes.json", "blush.json", "yum.json", "relieved.json",

				"star_eyes.json", "smirk.json", "unamused.json", "sweat.json",

				"pensive.json", "confused.json", "confounded.json", "kissing.json",

				"kiss.json", "kissing_closed.json", "stuck_out.json", "wink_tongue.json",

				"disappointed.json", "worried.json", "surprised.json", "crying.json",

				"triumph.json", "frowning.json", "anguished.json", "fearful.json",

				"weary.json", "sleepy.json", "tired.json", "grimacing.json",

				"loudly_crying.json", "scream.json", "astonished.json", "flushed.json",

				"angry.json", "thinking.json", "sunglasses.json", "hot.json",

				"cold.json", "hug.json", "shush.json", "vomit.json",

				"sleeping.json", "devil.json", "angel.json", "exploding_head.json",
			},
		},

		{

			PackID: "animated_animals",

			Name: "动态动物",

			Description: "可爱的动物动画",

			PreviewEmoji: "🐱",

			PreviewFile: "cat.json",

			StickerFiles: []string{

				"dog.json", "cat.json", "pig.json", "monkey.json",

				"monkey_face.json", "rabbit.json", "tiger.json", "frog.json",

				"bird.json", "hatching_chick.json", "baby_chick.json", "hatched_chick.json",

				"butterfly.json", "bee.json", "turtle.json", "snake.json",

				"dragon.json", "octopus.json", "dolphin.json", "whale.json",

				"fish.json", "unicorn.json",
			},
		},

		{

			PackID: "animated_nature",

			Name: "动态自然",

			Description: "自然元素动画",

			PreviewEmoji: "🌈",

			PreviewFile: "rainbow.json",

			StickerFiles: []string{

				"rainbow.json", "snowflake.json", "lightning.json",

				"rose.json", "four_leaf.json",
			},
		},

		{

			PackID: "animated_gestures",

			Name: "动态手势",

			Description: "手势表情动画",

			PreviewEmoji: "👍",

			PreviewFile: "thumbs_up.json",

			StickerFiles: []string{

				"thumbs_up.json", "thumbs_down.json", "clap.json", "wave.json",

				"ok.json", "muscle.json", "pray.json", "eyes.json",

				"raised_hands.json", "point_up.json", "point_down.json",

				"point_left.json", "point_right.json", "fist.json",

				"v_sign.json", "call_me.json", "love_you.json",
			},
		},

		{

			PackID: "animated_symbols",

			Name: "动态爱心",

			Description: "爱心和符号动画",

			PreviewEmoji: "❤️",

			PreviewFile: "heart.json",

			StickerFiles: []string{

				"heart.json", "orange_heart.json", "yellow_heart.json",

				"green_heart.json", "blue_heart.json", "purple_heart.json",

				"broken_heart.json", "sparkling_heart.json", "heartbeat.json",

				"fire.json", "hundred.json", "sparkles.json",

				"party.json", "tada.json", "rocket.json", "ghost.json",

				"skull.json", "poop.json",
			},
		},

		{

			PackID: "cubigator",

			Name: "小恐龙",

			Description: "小恐龙动画贴纸",

			PreviewEmoji: "🦖",

			PreviewFile: "/uploads/stickers/cubigator/cubigator_01.json",

			StickerFiles: emojiStoreRemoteStickerFiles("cubigator", "cubigator", 30),
		},

		{

			PackID: "duck",

			Name: "小黄鸭",

			Description: "小黄鸭动画贴纸",

			PreviewEmoji: "🐤",

			PreviewFile: "/uploads/stickers/duck/duck_01.json",

			StickerFiles: emojiStoreRemoteStickerFiles("duck", "duck", 29),
		},

		{

			PackID: "premium_gifts",

			Name: "高级礼品",

			Description: "高级礼品动画贴纸",

			PreviewEmoji: "🎁",

			PreviewFile: "/uploads/stickers/premium_gifts/premium_gifts_01.json",

			StickerFiles: emojiStoreRemoteStickerFiles("premium_gifts", "premium_gifts", 30),
		},
	}
}
func emojiStoreRemoteStickerFiles(dir, prefix string, count int) []string {
	files := make([]string, 0, count)
	for i := 1; i <= count; i++ {

		files = append(files, fmt.Sprintf("/uploads/stickers/%s/%s_%02d.json", dir, prefix, i))
	}
	return files
}
func (h *UserHandler) seedDefaultEmojiStoreCatalogIfEmpty() {
	seeds := defaultEmojiStoreCatalogSeeds()
	for i, seed := range seeds {
		var existing models.EmojiStorePackCatalog

		err := h.db.Where("pack_id = ?", seed.PackID).First(&existing).Error

		if err == nil {

			if existing.IsBuiltIn {

				_ = h.db.Model(&existing).Updates(map[string]interface{}{

					"name": seed.Name,

					"description": seed.Description,

					"preview_emoji": seed.PreviewEmoji,

					"preview_file": seed.PreviewFile,

					"sticker_files": encodeJSON(seed.StickerFiles),

					"sort_order": i + 1,

					"is_active": true,
				}).Error

			}

			continue

		}

		if !errors.Is(err, gorm.ErrRecordNotFound) {

			continue

		}
		row := models.EmojiStorePackCatalog{

			PackID: seed.PackID,

			Name: seed.Name,

			Description: seed.Description,

			PreviewEmoji: seed.PreviewEmoji,

			PreviewFile: seed.PreviewFile,

			StickerFiles: encodeJSON(seed.StickerFiles),

			SortOrder: i + 1,

			IsBuiltIn: true,

			IsActive: true,
		}
		_ = h.db.Create(&row).Error
	}
}
func sanitizeCatalogPackRows(rows []models.EmojiStorePackCatalog) []gin.H {
	if len(rows) == 0 {

		return []gin.H{}
	}
	out := make([]gin.H, 0, len(rows))
	seenPackIDs := make(map[string]struct{}, len(rows))
	for _, row := range rows {
		packID := trimAndClampRunes(row.PackID, emojiStoreMaxPackIDRunes)

		if packID == "" {

			continue

		}

		if _, ok := seenPackIDs[packID]; ok {

			continue

		}
		name := trimAndClampRunes(row.Name, emojiStoreMaxPackNameRunes)

		if name == "" {

			continue

		}
		description := trimAndClampRunes(row.Description, emojiStoreMaxPackDescRunes)
		previewEmoji := trimAndClampRunes(row.PreviewEmoji, 16)
		previewFile := trimAndClampRunes(row.PreviewFile, emojiStoreMaxPackIDRunes)
		stickerFiles := sanitizeStringList(

			interfaceSliceToStringSlice(decodeJSONList(row.StickerFiles)),

			emojiStoreMaxStickerFiles,

			emojiStoreMaxPackIDRunes,

			nil,
		)

		if len(stickerFiles) == 0 {

			continue

		}

		if previewFile == "" {

			previewFile = stickerFiles[0]

		}
		out = append(out, gin.H{

			"id": packID,

			"name": name,

			"description": description,

			"preview_emoji": previewEmoji,

			"preview_file": previewFile,

			"sticker_files": stickerFiles,

			"sort_order": row.SortOrder,

			"is_built_in": row.IsBuiltIn,
		})

		seenPackIDs[packID] = struct{}{}

		if len(out) >= emojiStoreMaxCatalogPacks {

			break

		}
	}
	return out
}

// GetEmojiStoreCatalog 获取可配置的表情包目录
func (h *UserHandler) GetEmojiStoreCatalog(c *gin.Context) {
	h.seedDefaultEmojiStoreCatalogIfEmpty()
	var rows []models.EmojiStorePackCatalog
	if err := h.db.Where("is_active = ?", true).
		Order("sort_order ASC, id ASC").
		Find(&rows).Error; err != nil {

		response.ServerError(c, "获取失败")

		return
	}
	list := sanitizeCatalogPackRows(rows)
	updatedAt := time.Time{}
	for _, row := range rows {

		if row.UpdatedAt.After(updatedAt) {

			updatedAt = row.UpdatedAt

		}
	}
	response.Success(c, gin.H{

		"list": list,

		"total": len(list),

		"updated_at": updatedAt.UTC().Format(time.RFC3339),
	})
}

// GetEmojiStore 获取用户表情商店云同步数据
func (h *UserHandler) GetEmojiStore(c *gin.Context) {
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var setting models.UserEmojiStoreSetting
	if err := h.db.Where("user_id = ?", user.ID).First(&setting).Error; err != nil {

		setting = models.UserEmojiStoreSetting{

			UserID: user.ID,

			InstalledPackIDs: "[]",

			FavoriteCodes: "[]",

			CustomEmojis: "[]",
		}
		_ = h.db.Create(&setting).Error
	}
	response.Success(c, buildEmojiStoreSyncPayload(setting))
}

// UpdateEmojiStore 更新用户表情商店云同步数据
func (h *UserHandler) UpdateEmojiStore(c *gin.Context) {
	userUUID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userUUID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var req UpdateEmojiStoreRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	var setting models.UserEmojiStoreSetting
	settingExists := true
	if err := h.db.Where("user_id = ?", user.ID).First(&setting).Error; err != nil {

		if errors.Is(err, gorm.ErrRecordNotFound) {

			settingExists = false

			setting = models.UserEmojiStoreSetting{UserID: user.ID}

		} else {

			response.ServerError(c, "读取失败")

			return

		}
	}
	if req.InstalledPackIDs == nil {

		req.InstalledPackIDs = []string{}
	}
	if req.FavoriteCodes == nil {

		req.FavoriteCodes = []string{}
	}
	if req.CustomEmojis == nil {

		req.CustomEmojis = []map[string]interface{}{}
	}
	req.BaseUpdatedAt = strings.TrimSpace(req.BaseUpdatedAt)
	rawBytes, _ := json.Marshal(req)
	if len(rawBytes) > emojiStoreMaxPayloadBytes {

		response.BadRequest(c, "数据过大")

		return
	}
	if req.BaseUpdatedAt != "" {

		baseUpdatedAt, ok := parseRFC3339Time(req.BaseUpdatedAt)

		if !ok {

			response.BadRequest(c, "base_updated_at 格式错误")

			return

		}

		if settingExists && setting.UpdatedAt.UTC().After(baseUpdatedAt) {

			c.JSON(http.StatusOK, response.Response{

				Code: 409,

				Message: "emoji_store_conflict",

				Data: buildEmojiStoreSyncPayload(setting),
			})

			return

		}
	}
	safeInstalled := sanitizeStringList(

		req.InstalledPackIDs,

		emojiStoreMaxInstalled,

		emojiStoreMaxPackIDRunes,

		nil,
	)
	safeCustom := sanitizeCustomEmojiList(req.CustomEmojis)
	safeFavorites := sanitizeStringList(

		req.FavoriteCodes,

		emojiStoreMaxFavorites,

		emojiStoreMaxFavoriteRunes,

		func(v string) bool {

			return strings.HasPrefix(v, "emoji:") || strings.HasPrefix(v, "custom:")

		},
	)
	safeFavorites = filterFavoriteCodesWithCustomEmojis(safeFavorites, safeCustom)
	activePackIDs := activeCatalogPackIDSet(h.db)
	safeInstalled = filterInstalledPackIDsByActiveCatalog(safeInstalled, activePackIDs)
	setting.InstalledPackIDs = encodeJSON(safeInstalled)
	setting.FavoriteCodes = encodeJSON(safeFavorites)
	setting.CustomEmojis = encodeJSON(safeCustom)
	if err := h.db.Save(&setting).Error; err != nil {

		response.ServerError(c, "保存失败")

		return
	}
	_ = h.db.Where("user_id = ?", user.ID).First(&setting).Error
	response.Success(c, buildEmojiStoreSyncPayload(setting))
}
func interfaceSliceToStringSlice(raw []interface{}) []string {
	if len(raw) == 0 {

		return []string{}
	}
	out := make([]string, 0, len(raw))
	for _, v := range raw {

		s, ok := v.(string)

		if !ok {

			continue

		}
		out = append(out, s)
	}
	return out
}
func interfaceSliceToMapSlice(raw []interface{}) []map[string]interface{} {
	if len(raw) == 0 {

		return []map[string]interface{}{}
	}
	out := make([]map[string]interface{}, 0, len(raw))
	for _, v := range raw {

		m, ok := v.(map[string]interface{})

		if !ok {

			continue

		}
		out = append(out, m)
	}
	return out
}

// ========== 屏蔽用户相关 API ==========  // CheckBlockStatus 检查是否已屏蔽某用户
func (h *UserHandler) CheckBlockStatus(c *gin.Context) {
	userID := c.GetString("user_id")
	targetID := c.Query("user_id")
	if targetID == "" {

		response.BadRequest(c, "请指定目标用户")

		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var targetUser models.User
	if err := h.db.Where("uuid = ?", targetID).First(&targetUser).Error; err != nil {

		response.NotFound(c, "目标用户不存在")

		return
	}
	var count int64
	h.db.Model(&models.UserBlock{}).
		Where("user_id = ? AND blocked_user_id = ?", user.ID, targetUser.ID).
		Count(&count)
	response.Success(c, gin.H{"is_blocked": count > 0})
}

// GetBlockedUsers 获取已屏蔽用户列表
func (h *UserHandler) GetBlockedUsers(c *gin.Context) {
	userID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	// 获取屏蔽列表
	var blocks []models.UserBlock
	h.db.Where("user_id = ?", user.ID).Find(&blocks)
	// 获取被屏蔽用户信息
	list := make([]gin.H, 0, len(blocks))
	for _, block := range blocks {
		var blockedUser models.User
		if err := h.db.First(&blockedUser, block.BlockedUserID).Error; err == nil {

			list = append(list, gin.H{

				"id": block.ID,

				"user_id": blockedUser.UUID,

				"username": blockedUser.Username,

				"nickname": blockedUser.Nickname,

				"avatar": blockedUser.Avatar,

				"blocked_at": block.CreatedAt,
			})

		}
	}
	response.Success(c, gin.H{

		"list": list,

		"total": len(list),
	})
}

// BlockUserRequest 屏蔽用户请求
type BlockUserRequest struct {
	UserID string `json:"user_id" binding:"required"`
}

// BlockUser 屏蔽用户
func (h *UserHandler) BlockUser(c *gin.Context) {
	// 屏蔽关系是单向的：UserID 为操作人，BlockedUserID 为被屏蔽人。
	userID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var req BlockUserRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "请指定要屏蔽的用户")

		return
	}
	// 查找目标用户
	var targetUser models.User
	if err := h.db.Where("uuid = ?", req.UserID).First(&targetUser).Error; err != nil {

		response.NotFound(c, "目标用户不存在")

		return
	}
	// 不能屏蔽自己
	if user.ID == targetUser.ID {

		response.BadRequest(c, "不能屏蔽自己")

		return
	}
	// 检查是否已屏蔽
	var existing models.UserBlock
	if err := h.db.Where("user_id = ? AND blocked_user_id = ?", user.ID, targetUser.ID).First(&existing).Error; err == nil {

		response.BadRequest(c, "已经屏蔽该用户")

		return
	}
	// 创建屏蔽记录
	block := models.UserBlock{

		UserID: user.ID,

		BlockedUserID: targetUser.ID,
	}
	if err := h.db.Create(&block).Error; err != nil {

		response.ServerError(c, "屏蔽失败")

		return
	}
	response.Success(c, gin.H{"message": "已屏蔽"})
}

// UnblockUser 解除屏蔽
func (h *UserHandler) UnblockUser(c *gin.Context) {
	userID := c.GetString("user_id")
	targetID := c.Param("blocked_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	// 查找目标用户
	var targetUser models.User
	if err := h.db.Where("uuid = ?", targetID).First(&targetUser).Error; err != nil {

		response.NotFound(c, "目标用户不存在")

		return
	}
	// 删除屏蔽记录
	result := h.db.Where("user_id = ? AND blocked_user_id = ?", user.ID, targetUser.ID).Delete(&models.UserBlock{})
	if result.RowsAffected == 0 {

		response.NotFound(c, "未屏蔽该用户")

		return
	}
	response.Success(c, gin.H{"message": "已解除屏蔽"})
}

// ========== 设备管理相关 API ==========
func buildForceLogoutEvent(
	targetDeviceIDs []string,
	reason string,
	actorDeviceID string,
	actorDeviceName string,
	actorDeviceType string,
	occurredAt time.Time) map[string]interface{} {
	if occurredAt.IsZero() {

		occurredAt = time.Now()
	}
	return map[string]interface{}{

		"type": "force_logout",

		"device_ids": targetDeviceIDs,

		"reason": strings.TrimSpace(reason),

		"actor_device_id": services.LogicalPushDeviceID(actorDeviceID),

		"actor_device_name": strings.TrimSpace(actorDeviceName),

		"actor_device_type": strings.TrimSpace(actorDeviceType),

		"occurred_at": occurredAt.UTC().Format(time.RFC3339),
	}
}
func (h *UserHandler) currentDeviceForForceLogout(userID uint64, deviceID string) models.UserDevice {
	var device models.UserDevice
	logicalID := services.LogicalPushDeviceID(deviceID)
	if h.db == nil || userID == 0 || logicalID == "" {

		return device
	}
	h.db.Where("user_id = ? AND device_id IN ?", userID, services.PushStorageDeviceIDs(logicalID)).
		Order("last_active DESC, id DESC").
		First(&device)
	return device
}

// GetDevices 获取用户设备列表
func (h *UserHandler) GetDevices(c *gin.Context) {
	userID := c.GetString("user_id")
	currentDeviceID := c.GetString("device_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	// 获取设备列表
	var devices []models.UserDevice
	h.db.Where("user_id = ?", user.ID).Order("last_active DESC").Find(&devices)
	var sessions []models.UserSession
	h.db.Where("user_id = ?", user.ID).Find(&sessions)
	sessionCountByDevice := make(map[string]int, len(sessions))
	for _, s := range sessions {
		deviceID := services.LogicalPushDeviceID(s.DeviceID)

		if deviceID == "" {

			continue

		}

		sessionCountByDevice[deviceID]++
	}
	deduped := make(map[string]models.UserDevice, len(devices))
	for _, device := range devices {
		deviceID := services.LogicalPushDeviceID(device.DeviceID)

		if deviceID == "" {

			continue

		}
		existing, ok := deduped[deviceID]

		if !ok {

			deduped[deviceID] = device

			continue

		}
		keepIncoming := false

		if deviceID == currentDeviceID && services.LogicalPushDeviceID(existing.DeviceID) != currentDeviceID {

			keepIncoming = true

		} else if device.LastActive.After(existing.LastActive) {

			keepIncoming = true

		} else if device.LastActive.Equal(existing.LastActive) && device.ID > existing.ID {

			keepIncoming = true

		}
		primary := existing

		secondary := device

		if keepIncoming {

			primary = device

			secondary = existing

		}

		if strings.TrimSpace(primary.PushToken) == "" && strings.TrimSpace(secondary.PushToken) != "" {

			primary.PushToken = secondary.PushToken

		}

		if strings.TrimSpace(primary.PushChannel) == "" && strings.TrimSpace(secondary.PushChannel) != "" {

			primary.PushChannel = secondary.PushChannel

		}

		if strings.TrimSpace(primary.Location) == "" && strings.TrimSpace(secondary.Location) != "" {

			primary.Location = secondary.Location

		}

		if strings.TrimSpace(primary.E2EEPublicKey) == "" && strings.TrimSpace(secondary.E2EEPublicKey) != "" {

			primary.E2EEPublicKey = secondary.E2EEPublicKey

			primary.E2EEPublicKeyAlgo = secondary.E2EEPublicKeyAlgo

			primary.E2EEPublicKeyUpdatedAt = secondary.E2EEPublicKeyUpdatedAt

		}

		deduped[deviceID] = primary
	}
	devices = make([]models.UserDevice, 0, len(deduped))
	for _, device := range deduped {

		devices = append(devices, device)
	}
	sort.Slice(devices, func(i, j int) bool {
		leftID := services.LogicalPushDeviceID(devices[i].DeviceID)
		rightID := services.LogicalPushDeviceID(devices[j].DeviceID)

		if leftID == currentDeviceID && rightID != currentDeviceID {

			return true

		}

		if rightID == currentDeviceID && leftID != currentDeviceID {

			return false

		}

		if devices[i].LastActive.Equal(devices[j].LastActive) {

			return devices[i].ID > devices[j].ID

		}

		return devices[i].LastActive.After(devices[j].LastActive)
	})
	// 构建响应
	list := make([]gin.H, 0, len(devices))
	for _, d := range devices {
		pushToken := strings.TrimSpace(d.PushToken)
		logicalDeviceID := services.LogicalPushDeviceID(d.DeviceID)
		list = append(list, gin.H{

			"id": d.ID,

			"device_id": logicalDeviceID,

			"device_type": d.DeviceType,

			"device_name": d.DeviceName,

			"ip": d.IP,

			"location": d.Location,

			"is_current": logicalDeviceID == currentDeviceID,

			"session_count": sessionCountByDevice[logicalDeviceID],

			"has_active_session": sessionCountByDevice[logicalDeviceID] > 0,

			"push_channel": strings.TrimSpace(d.PushChannel),

			"push_token_bound": pushToken != "",

			"push_token_length": len(pushToken),

			"last_active": d.LastActive,

			"created_at": d.CreatedAt,
		})
	}
	response.Success(c, gin.H{

		"devices": list,

		"total": len(list),
	})
}

// TerminateDevice 终止指定设备会话
func (h *UserHandler) TerminateDevice(c *gin.Context) {
	userID := c.GetString("user_id")
	deviceID := services.LogicalPushDeviceID(c.Param("device_id"))
	currentDeviceID := c.GetString("device_id")
	// 不能终止当前设备
	if deviceID == currentDeviceID {

		response.BadRequest(c, "不能终止当前设备")

		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	actorDevice := h.currentDeviceForForceLogout(user.ID, currentDeviceID)
	// 发送强制下线 WS 通知（在删除前发送，确保设备还在线能收到）
	if h.hub != nil {

		h.hub.SendToUser(userID, buildForceLogoutEvent(

			[]string{deviceID},

			"device_terminated",

			currentDeviceID,

			actorDevice.DeviceName,

			actorDevice.DeviceType,

			time.Now(),
		))
	}
	if h.cache != nil {

		authsession.InvalidateDeviceSession(c.Request.Context(), h.cache, user.UUID, deviceID)
	}
	var targetSessions []models.UserSession
	h.db.Where("user_id = ? AND device_id = ?", user.ID, deviceID).Find(&targetSessions)
	if h.cache != nil {

		for _, s := range targetSessions {

			authsession.RevokeUserToken(c.Request.Context(), h.cache, user.UUID, s.Token)

		}
	}
	// 删除该设备上的会话
	sessionResult := h.db.Where("user_id = ? AND device_id = ?", user.ID, deviceID).Delete(&models.UserSession{})
	// 删除指定设备
	result := h.db.Where("device_id IN ? AND user_id = ?", services.PushStorageDeviceIDs(deviceID), user.ID).Delete(&models.UserDevice{})
	if result.RowsAffected == 0 {

		response.NotFound(c, "设备不存在")

		return
	}
	response.Success(c, gin.H{

		"message": "已终止设备会话",

		"terminated_sessions": sessionResult.RowsAffected,
	})
}

// TerminateOtherDevices 终止其他所有设备会话
func (h *UserHandler) TerminateOtherDevices(c *gin.Context) {
	userID := c.GetString("user_id")
	currentDeviceID := c.GetString("device_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	actorDevice := h.currentDeviceForForceLogout(user.ID, currentDeviceID)
	// 先查询其他设备列表，用于发送强制下线通知
	var otherDevices []models.UserDevice
	h.db.Where("user_id = ?", user.ID).Find(&otherDevices)
	otherDeviceIDs := make([]string, 0, len(otherDevices))
	seen := make(map[string]struct{}, len(otherDevices))
	for _, d := range otherDevices {
		deviceID := services.LogicalPushDeviceID(d.DeviceID)

		if deviceID == "" || deviceID == currentDeviceID {

			continue

		}

		if _, ok := seen[deviceID]; ok {

			continue

		}

		seen[deviceID] = struct{}{}
		otherDeviceIDs = append(otherDeviceIDs, deviceID)
	}
	// 发送强制下线 WS 通知（在删除前发送）
	if h.hub != nil && len(otherDeviceIDs) > 0 {

		h.hub.SendToUser(userID, buildForceLogoutEvent(

			otherDeviceIDs,

			"device_terminated",

			currentDeviceID,

			actorDevice.DeviceName,

			actorDevice.DeviceType,

			time.Now(),
		))
	}
	if h.cache != nil {

		for _, deviceID := range otherDeviceIDs {

			authsession.InvalidateDeviceSession(c.Request.Context(), h.cache, user.UUID, deviceID)

		}
	}
	// 删除其他设备对应会话
	var terminatedSessions int64
	if len(otherDeviceIDs) > 0 {
		var sessions []models.UserSession

		h.db.Where("user_id = ? AND device_id IN ?", user.ID, otherDeviceIDs).Find(&sessions)

		if h.cache != nil {

			for _, s := range sessions {

				authsession.RevokeUserToken(c.Request.Context(), h.cache, user.UUID, s.Token)

			}

		}
		sr := h.db.Where("user_id = ? AND device_id IN ?", user.ID, otherDeviceIDs).Delete(&models.UserSession{})
		terminatedSessions = sr.RowsAffected
	}
	// 删除其他设备（保留当前设备）
	keepDeviceIDs := services.PushStorageDeviceIDs(currentDeviceID)
	result := h.db.Where("user_id = ? AND device_id NOT IN ?", user.ID, keepDeviceIDs).Delete(&models.UserDevice{})
	response.Success(c, gin.H{

		"message": "已终止其他设备",

		"terminated": result.RowsAffected,

		"terminated_sessions": terminatedSessions,
	})
}

// ========== 会话管理相关 API ==========  // GetSessions 获取活动会话列表
func (h *UserHandler) GetSessions(c *gin.Context) {
	userID := c.GetString("user_id")
	currentToken := c.GetHeader("Authorization")
	if len(currentToken) > 7 && currentToken[:7] == "Bearer " {

		currentToken = currentToken[7:]
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	// 获取会话列表
	var sessions []models.UserSession
	h.db.Where("user_id = ?", user.ID).Order("last_active DESC").Find(&sessions)
	// 标记当前会话
	list := make([]gin.H, 0, len(sessions))
	for _, s := range sessions {

		list = append(list, gin.H{

			"id": s.ID,

			"device_type": s.DeviceType,

			"device_name": s.DeviceName,

			"ip": s.IP,

			"location": s.Location,

			"is_current": s.Token == currentToken,

			"last_active": s.LastActive,

			"created_at": s.CreatedAt,
		})
	}
	response.Success(c, gin.H{

		"sessions": list,

		"total": len(list),
	})
}

// TerminateOtherSessions 终止其他会话
func (h *UserHandler) TerminateOtherSessions(c *gin.Context) {
	userID := c.GetString("user_id")
	currentToken := c.GetHeader("Authorization")
	if len(currentToken) > 7 && currentToken[:7] == "Bearer " {

		currentToken = currentToken[7:]
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var otherSessions []models.UserSession
	h.db.Where("user_id = ? AND token != ?", user.ID, currentToken).Find(&otherSessions)
	// 删除其他会话（保留当前会话）
	result := h.db.Where("user_id = ? AND token != ?", user.ID, currentToken).Delete(&models.UserSession{})
	if h.cache != nil {

		for _, s := range otherSessions {

			authsession.RevokeUserToken(c.Request.Context(), h.cache, user.UUID, s.Token)

		}
	}
	response.Success(c, gin.H{

		"message": "已终止其他会话",

		"terminated": result.RowsAffected,
	})
}

// TerminateSession 终止指定会话
func (h *UserHandler) TerminateSession(c *gin.Context) {
	userID := c.GetString("user_id")
	sessionID := c.Param("session_id")
	currentToken := c.GetHeader("Authorization")
	if len(currentToken) > 7 && currentToken[:7] == "Bearer " {

		currentToken = currentToken[7:]
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var session models.UserSession
	if err := h.db.Where("id = ? AND user_id = ?", sessionID, user.ID).First(&session).Error; err != nil {

		response.NotFound(c, "会话不存在")

		return
	}
	if currentToken != "" && session.Token == currentToken {

		response.BadRequest(c, "不能终止当前会话")

		return
	}
	if h.cache != nil {

		authsession.RevokeUserToken(c.Request.Context(), h.cache, user.UUID, session.Token)
	}
	// 删除指定会话
	if err := h.db.Where("id = ? AND user_id = ?", sessionID, user.ID).Delete(&models.UserSession{}).Error; err != nil {

		response.ServerError(c, "终止会话失败")

		return
	}
	response.Success(c, gin.H{"message": "已终止会话"})
}

// DeleteAccount 删除用户账号
func (h *UserHandler) DeleteAccount(c *gin.Context) {
	if h.cache == nil {

		response.ServerError(c, "服务异常")

		return
	}
	userID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	if _, ok := h.requireBoundPhone(user); !ok {

		response.Error(c, 400, "请先绑定手机号")

		return
	}
	code := strings.TrimSpace(c.Query("code"))
	if code == "" {
		var req struct {
			Code string `json:"code"`
		}

		if err := c.ShouldBindJSON(&req); err == nil {

			code = strings.TrimSpace(req.Code)

		}
	}
	if code == "" {

		response.Error(c, 400, "请填写短信验证码")

		return
	}
	cacheKey := "verify:delete_account:" + user.UUID
	var storedCode string
	if err := h.cache.Get(c.Request.Context(), cacheKey, &storedCode); err != nil || storedCode == "" {

		response.Error(c, 400, "验证码已失效，请重新获取")

		return
	}
	if !allowSMSVerifyAttempt(c, h.cache, "delete-account:"+user.UUID, cacheKey) {

		return
	}
	if code != storedCode {

		response.Error(c, 400, "验证码错误")

		return
	}
	_ = h.cache.Delete(c.Request.Context(), cacheKey)
	clearSMSVerifyAttempts(c.Request.Context(), h.cache, "delete-account:"+user.UUID)
	staticMediaRefs := h.collectDeleteAccountStaticMediaRefs(user)
	// 开启事务
	// 关系型数据先在一个事务内完成删除；Mongo、文件和外部对象属于提交后的尽力清理边界。
	tx := h.db.Begin()
	if tx.Error != nil {

		response.ServerError(c, "删除账号失败")

		return
	}
	failAndRollback := func(err error) {

		_ = tx.Rollback().Error

		log.Printf("[DeleteAccount] rollback user_id=%d err=%v", user.ID, err)

		response.ServerError(c, "删除账号失败")
	}
	var (
		ownMomentIDs []uint64

		ownRedPacketIDs []uint64

		ownInviteCodeIDs []uint64

		ownMeetingIDs []uint64
	)
	if err := tx.Model(&models.Moment{}).
		Where("user_id = ?", user.ID).
		Pluck("id", &ownMomentIDs).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Model(&models.RedPacket{}).
		Where("sender_id = ?", user.ID).
		Pluck("id", &ownRedPacketIDs).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Model(&models.InviteCode{}).
		Where("service_user_id = ?", user.ID).
		Pluck("id", &ownInviteCodeIDs).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Model(&models.Meeting{}).
		Where("creator_id = ?", user.ID).
		Pluck("id", &ownMeetingIDs).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 1. 删除用户设备
	if err := tx.Where("user_id = ?", user.ID).Delete(&models.UserDevice{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 2. 删除用户会话
	if err := tx.Where("user_id = ?", user.ID).Delete(&models.UserSession{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 3. 删除用户会议数据（邀请/参会记录/创建会议）
	if len(ownMeetingIDs) > 0 {

		if err := tx.Where("meeting_id IN ?", ownMeetingIDs).Delete(&models.MeetingInvite{}).Error; err != nil {

			failAndRollback(err)

			return

		}

		if err := tx.Where("meeting_id IN ?", ownMeetingIDs).Delete(&models.MeetingParticipant{}).Error; err != nil {

			failAndRollback(err)

			return

		}

		if err := tx.Where("id IN ?", ownMeetingIDs).Delete(&models.Meeting{}).Error; err != nil {

			failAndRollback(err)

			return

		}
	}
	if err := tx.Where("inviter_id = ? OR invitee_id = ?", user.ID, user.ID).Delete(&models.MeetingInvite{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Where("user_id = ?", user.ID).Delete(&models.MeetingParticipant{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Model(&models.MeetingParticipant{}).
		Where("inviter_id = ?", user.ID).
		Update("inviter_id", 0).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 4. 删除用户隐私设置
	if err := tx.Where("user_id = ?", user.ID).Delete(&models.UserPrivacySetting{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 4. 删除用户屏蔽关系
	if err := tx.Where("user_id = ? OR blocked_user_id = ?", user.ID, user.ID).Delete(&models.UserBlock{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 5. 删除用户的聊天成员记录
	if err := tx.Where("user_id = ?", user.ID).Delete(&models.ChatMember{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 删除用户会话索引，并清理其他人的私聊目标引用
	if err := tx.Where("user_id = ? OR target_id = ?", user.ID, user.ID).Delete(&models.UserChat{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 清理加入申请（申请人/审批人）
	if err := tx.Unscoped().Where("user_id = ? OR reviewer_id = ?", user.ID, user.ID).Delete(&models.JoinRequest{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 清理群公告作者引用
	if err := tx.Unscoped().Where("author_id = ?", user.ID).Delete(&models.ChatAnnouncement{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 清理会话中的所有者/置顶操作者引用
	if err := tx.Model(&models.Chat{}).
		Where("owner_id = ? OR pinned_message_by = ?", user.ID, user.ID).
		Updates(map[string]interface{}{

			"owner_id": 0,

			"pinned_message_by": 0,

			"updated_at": time.Now(),
		}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 6. 删除用户的联系人关系
	if err := tx.Where("user_id = ? OR contact_user_id = ?", user.ID, user.ID).Delete(&models.Contact{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 7. 删除用户好友关系
	if err := tx.Where("user_id = ? OR friend_id = ?", user.ID, user.ID).Delete(&models.UserRelation{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 8. 删除用户推送设置
	if err := tx.Where("user_id = ?", user.ID).Delete(&models.UserPushSetting{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 9. 删除用户表情商店云同步数据
	if err := tx.Where("user_id = ?", user.ID).Delete(&models.UserEmojiStoreSetting{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 10. 动态相关数据
	if err := tx.Where("user_id = ?", user.ID).Delete(&models.MomentLike{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Unscoped().Where("user_id = ? OR reply_to_id = ?", user.ID, user.ID).Delete(&models.MomentComment{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	if len(ownMomentIDs) > 0 {

		if err := tx.Where("moment_id IN ?", ownMomentIDs).Delete(&models.MomentLike{}).Error; err != nil {

			failAndRollback(err)

			return

		}

		if err := tx.Unscoped().Where("moment_id IN ?", ownMomentIDs).Delete(&models.MomentComment{}).Error; err != nil {

			failAndRollback(err)

			return

		}

		if err := tx.Where("moment_id IN ?", ownMomentIDs).Delete(&models.MomentBlock{}).Error; err != nil {

			failAndRollback(err)

			return

		}

		if err := tx.Unscoped().Where("id IN ?", ownMomentIDs).Delete(&models.Moment{}).Error; err != nil {

			failAndRollback(err)

			return

		}
	}
	if err := tx.Where("user_id = ? OR blocked_user_id = ?", user.ID, user.ID).Delete(&models.UserMomentBlock{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Where("user_id = ?", user.ID).Delete(&models.MomentBlock{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 11. 举报相关
	if err := tx.Unscoped().Where("reporter_id = ?", user.ID).Delete(&models.Report{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Unscoped().Where("target_type = ? AND target_id = ?", models.ReportTypeUser, user.UUID).Delete(&models.Report{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 12. 钱包与资金流水
	if err := tx.Where("user_id = ? OR related_user_id = ?", user.ID, user.ID).Delete(&models.Transaction{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Unscoped().Where("user_id = ?", user.ID).Delete(&models.Wallet{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Where("user_id = ?", user.ID).Delete(&models.WithdrawRequest{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Where("user_id = ?", user.ID).Delete(&models.RechargeOrder{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Where("sender_id = ? OR receiver_id = ?", user.ID, user.ID).Delete(&models.Transfer{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Where("user_id = ?", user.ID).Delete(&models.RedPacketClaim{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	if len(ownRedPacketIDs) > 0 {

		if err := tx.Where("red_packet_id IN ?", ownRedPacketIDs).Delete(&models.RedPacketClaim{}).Error; err != nil {

			failAndRollback(err)

			return

		}
	}
	if err := tx.Where("sender_id = ?", user.ID).Delete(&models.RedPacket{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Where("user_id = ?", user.ID).Delete(&models.ThirdPartyPaymentOrder{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 13. 邀请体系
	if err := tx.Where("user_id = ?", user.ID).Delete(&models.InviteCodeUsage{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	if len(ownInviteCodeIDs) > 0 {

		if err := tx.Where("invite_code_id IN ?", ownInviteCodeIDs).Delete(&models.InviteCodeUsage{}).Error; err != nil {

			failAndRollback(err)

			return

		}
	}
	if err := tx.Unscoped().Where("service_user_id = ?", user.ID).Delete(&models.InviteCode{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Unscoped().Where("user_id = ? OR user_uuid = ?", user.ID, user.UUID).Delete(&models.OfficialUser{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 14. 通话记录
	if err := tx.Where("caller_id = ? OR callee_id = ?", user.ID, user.ID).Delete(&models.Call{}).Error; err != nil {

		failAndRollback(err)

		return
	}
	// 15. 物理删除用户账号
	if err := tx.Unscoped().Delete(&user).Error; err != nil {

		failAndRollback(err)

		return
	}
	if err := tx.Commit().Error; err != nil {

		response.ServerError(c, "删除账号失败")

		return
	}
	services.MarkUserMediaForDeletion(h.db, user.ID)
	mongoStatus := "skipped"
	mongoDeletedMessages := int64(0)
	localFilesDeleted := 0
	localFilesFailed := 0
	externalQueued := 0
	allMediaRefs := append([]string{}, staticMediaRefs...)
	// 外部资源清理失败不回滚已经提交的账号删除，通过状态摘要和重试任务保留可追踪性。
	if h.mongoDB == nil {

		mongoStatus = "skipped"
	} else {

		cleanupCtx, cancel := context.WithTimeout(context.Background(), 90*time.Second)

		defer cancel()
		messageMediaRefs, messageCollections, err := h.collectDeleteAccountMessageMediaRefs(cleanupCtx, user.UUID)

		if err != nil {

			log.Printf("[DeleteAccount] collect mongo media refs failed user_uuid=%s err=%v", user.UUID, err)
			mongoStatus = "scan_failed"

		} else {

			allMediaRefs = append(allMediaRefs, messageMediaRefs...)
			deletedMessages, delErr := h.deleteAccountMongoMessages(cleanupCtx, user.UUID, messageCollections)

			if delErr != nil {

				log.Printf("[DeleteAccount] delete mongo messages failed user_uuid=%s err=%v", user.UUID, delErr)
				mongoStatus = "delete_failed"

			} else {

				mongoStatus = "ok"

				mongoDeletedMessages = deletedMessages

			}

		}
	}
	deletedFiles, failedFiles := h.deleteAccountUploadFiles(allMediaRefs)
	localFilesDeleted = deletedFiles
	localFilesFailed = failedFiles
	externalRefs := h.collectDeleteAccountExternalMediaRefs(allMediaRefs)
	externalQueued = h.enqueueDeleteAccountExternalCleanupTasks(user.UUID, externalRefs)
	cleanupSummary := gin.H{

		"mongo_status": mongoStatus,

		"mongo_deleted_messages": mongoDeletedMessages,

		"local_files_deleted": localFilesDeleted,

		"local_files_failed": localFilesFailed,

		"external_queued": externalQueued,
	}
	externalHint := "none"
	if externalQueued > 0 {

		externalHint = "queued"
	}
	audit := models.AccountDeletionAudit{

		UserUUID: user.UUID,

		MongoStatus: mongoStatus,

		MongoDeletedCount: mongoDeletedMessages,

		LocalFilesDeleted: localFilesDeleted,

		LocalFilesFailed: localFilesFailed,

		ExternalQueuedCount: externalQueued,

		ExternalCleanupHint: externalHint,

		CreatedAt: time.Now(),
	}
	if err := h.db.Create(&audit).Error; err != nil {

		log.Printf("[DeleteAccount] create cleanup audit failed user_uuid=%s err=%v", user.UUID, err)
	}
	response.Success(c, gin.H{

		"message": "账号已删除",

		"cleanup": cleanupSummary,
	})
}

type deleteAccountMessageContentProjection struct {
	Content struct {
		Media *struct {
			URL string `bson:"url"`

			Thumbnail string `bson:"thumbnail"`
		} `bson:"media"`

		Voice *struct {
			URL string `bson:"url"`
		} `bson:"voice"`

		File *struct {
			URL string `bson:"url"`
		} `bson:"file"`

		Sticker *struct {
			URL string `bson:"url"`
		} `bson:"sticker"`
	} `bson:"content"`
}

func (h *UserHandler) collectDeleteAccountStaticMediaRefs(user models.User) []string {
	out := make([]string, 0, 8)
	if avatar := strings.TrimSpace(user.Avatar); avatar != "" {

		out = append(out, avatar)
	}
	var setting models.UserEmojiStoreSetting
	if err := h.db.Where("user_id = ?", user.ID).First(&setting).Error; err == nil {

		for _, item := range interfaceSliceToMapSlice(decodeJSONList(setting.CustomEmojis)) {

			if remoteURL := strings.TrimSpace(toTrimmedString(item["remote_url"])); remoteURL != "" {

				out = append(out, remoteURL)

			}

			if path := strings.TrimSpace(toTrimmedString(item["path"])); path != "" {

				out = append(out, path)

			}

		}
	} else if !errors.Is(err, gorm.ErrRecordNotFound) {

		log.Printf("[DeleteAccount] read custom emoji setting failed user_id=%d err=%v", user.ID, err)
	}
	return dedupeStringsPreserveOrder(out)
}
func (h *UserHandler) listDeleteAccountMessageCollections(ctx context.Context) ([]string, error) {
	if h.mongoDB == nil {

		return nil, errors.New("mongoDB is nil")
	}
	collections, err := h.mongoDB.ListCollectionNames(ctx, bson.M{

		"name": bson.M{"$regex": "^messages"},
	})
	if err != nil {

		return nil, err
	}
	if len(collections) == 0 {

		collections = []string{"messages"}
	}
	sort.Sort(sort.Reverse(sort.StringSlice(collections)))
	seen := make(map[string]struct{}, len(collections))
	unique := make([]string, 0, len(collections))
	for _, name := range collections {

		if _, ok := seen[name]; ok {

			continue

		}

		seen[name] = struct{}{}
		unique = append(unique, name)
	}
	return unique, nil
}
func (h *UserHandler) collectDeleteAccountMessageMediaRefs(ctx context.Context, userUUID string) ([]string, []string, error) {
	collections, err := h.listDeleteAccountMessageCollections(ctx)
	if err != nil {

		return nil, nil, err
	}
	projection := bson.M{

		"content.media.url": 1,

		"content.media.thumbnail": 1,

		"content.voice.url": 1,

		"content.file.url": 1,

		"content.sticker.url": 1,
	}
	out := make([]string, 0, 64)
	for _, name := range collections {

		cursor, err := h.mongoDB.Collection(name).Find(

			ctx,

			bson.M{"sender_id": userUUID},

			options.Find().SetProjection(projection),
		)

		if err != nil {

			return nil, nil, err

		}

		for cursor.Next(ctx) {
			var row deleteAccountMessageContentProjection
			if err := cursor.Decode(&row); err != nil {

				_ = cursor.Close(ctx)

				return nil, nil, err

			}

			if row.Content.Media != nil {

				if v := strings.TrimSpace(row.Content.Media.URL); v != "" {

					out = append(out, v)

				}

				if v := strings.TrimSpace(row.Content.Media.Thumbnail); v != "" {

					out = append(out, v)

				}

			}

			if row.Content.Voice != nil {

				if v := strings.TrimSpace(row.Content.Voice.URL); v != "" {

					out = append(out, v)

				}

			}

			if row.Content.File != nil {

				if v := strings.TrimSpace(row.Content.File.URL); v != "" {

					out = append(out, v)

				}

			}

			if row.Content.Sticker != nil {

				if v := strings.TrimSpace(row.Content.Sticker.URL); v != "" {

					out = append(out, v)

				}

			}

		}

		if err := cursor.Err(); err != nil {

			_ = cursor.Close(ctx)

			return nil, nil, err

		}
		_ = cursor.Close(ctx)
	}
	return dedupeStringsPreserveOrder(out), collections, nil
}
func (h *UserHandler) deleteAccountMongoMessages(ctx context.Context, userUUID string, collections []string) (int64, error) {
	if h.mongoDB == nil {

		return 0, nil
	}
	var total int64
	for _, name := range collections {

		res, err := h.mongoDB.Collection(name).DeleteMany(ctx, bson.M{"sender_id": userUUID})

		if err != nil {

			return total, err

		}

		if res != nil {

			total += res.DeletedCount

		}
	}
	return total, nil
}
func (h *UserHandler) deleteAccountUploadFiles(urls []string) (int, int) {
	if strings.TrimSpace(h.uploadDir) == "" {

		return 0, 0
	}
	unique := make(map[string]struct{}, len(urls))
	for _, raw := range urls {

		if path, ok := resolveDeleteAccountUploadLocalPath(h.uploadDir, raw); ok {

			unique[path] = struct{}{}

		}
	}
	deleted := 0
	failed := 0
	for path := range unique {

		if err := os.Remove(path); err != nil {

			if errors.Is(err, os.ErrNotExist) {

				continue

			}

			failed++

			log.Printf("[DeleteAccount] delete local media failed path=%s err=%v", path, err)

			continue

		}

		deleted++
	}
	return deleted, failed
}
func (h *UserHandler) collectDeleteAccountExternalMediaRefs(rawRefs []string) []string {
	if len(rawRefs) == 0 {

		return []string{}
	}
	out := make([]string, 0, len(rawRefs))
	seen := make(map[string]struct{}, len(rawRefs))
	for _, raw := range rawRefs {
		value := strings.TrimSpace(raw)

		if value == "" {

			continue

		}

		if _, ok := resolveDeleteAccountUploadLocalPath(h.uploadDir, value); ok {

			continue

		}
		parsed, err := url.Parse(value)

		if err != nil || parsed == nil {

			continue

		}

		if parsed.Scheme != "http" && parsed.Scheme != "https" {

			continue

		}

		if strings.TrimSpace(parsed.Host) == "" {

			continue

		}

		parsed.Fragment = ""

		u := strings.TrimSpace(parsed.String())

		if u == "" {

			continue

		}

		if _, ok := seen[u]; ok {

			continue

		}

		seen[u] = struct{}{}
		out = append(out, u)
	}
	return out
}
func (h *UserHandler) enqueueDeleteAccountExternalCleanupTasks(userUUID string, externalRefs []string) int {
	if strings.TrimSpace(userUUID) == "" || len(externalRefs) == 0 {

		return 0
	}
	now := time.Now()
	tasks := make([]models.AccountDeletionExternalTask, 0, len(externalRefs))
	for _, u := range externalRefs {
		url := strings.TrimSpace(u)

		if url == "" {

			continue

		}
		tasks = append(tasks, models.AccountDeletionExternalTask{

			UserUUID: userUUID,

			ResourceURL: url,

			Status: models.AccountDeletionExternalTaskPending,

			RetryCount: 0,

			NextRetryAt: &now,

			CreatedAt: now,

			UpdatedAt: now,
		})
	}
	if len(tasks) == 0 {

		return 0
	}
	if err := h.db.Create(&tasks).Error; err != nil {

		log.Printf("[DeleteAccount] enqueue external cleanup task failed user_uuid=%s err=%v", userUUID, err)

		return 0
	}
	return len(tasks)
}
func resolveDeleteAccountUploadLocalPath(uploadDir, raw string) (string, bool) {
	baseDir := strings.TrimSpace(uploadDir)
	value := strings.TrimSpace(raw)
	if baseDir == "" || value == "" {

		return "", false
	}
	if parsed, err := url.Parse(value); err == nil && parsed.Path != "" {

		value = parsed.Path
	}
	value = strings.SplitN(value, "?", 2)[0]
	value = strings.SplitN(value, "#", 2)[0]
	value = strings.ReplaceAll(value, "\\", "/")
	switch {
	case strings.Contains(value, "/uploads/"):

		value = value[strings.Index(value, "/uploads/")+len("/uploads/"):]
	case strings.HasPrefix(value, "uploads/"):

		value = strings.TrimPrefix(value, "uploads/")
	case strings.HasPrefix(value, "/uploads/"):

		value = strings.TrimPrefix(value, "/uploads/")
	default:

		return "", false
	}
	value = strings.TrimLeft(value, "/")
	if value == "" {

		return "", false
	}
	rel := filepath.Clean(filepath.FromSlash(value))
	if rel == "." || rel == ".." || strings.HasPrefix(rel, ".."+string(filepath.Separator)) {

		return "", false
	}
	relSlash := filepath.ToSlash(rel)
	topDir := strings.Split(relSlash, "/")[0]
	if _, ok := deleteAccountAllowedUploadDirs[strings.ToLower(topDir)]; !ok {

		return "", false
	}
	baseAbs, err := filepath.Abs(baseDir)
	if err != nil {

		return "", false
	}
	targetAbs, err := filepath.Abs(filepath.Join(baseAbs, rel))
	if err != nil {

		return "", false
	}
	if !isPathWithinBaseDir(baseAbs, targetAbs) {

		return "", false
	}
	return targetAbs, true
}
func isPathWithinBaseDir(baseDir, targetPath string) bool {
	rel, err := filepath.Rel(baseDir, targetPath)
	if err != nil {

		return false
	}
	rel = filepath.Clean(rel)
	if rel == "." {

		return true
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}
func dedupeStringsPreserveOrder(in []string) []string {
	if len(in) == 0 {

		return []string{}
	}
	seen := make(map[string]struct{}, len(in))
	out := make([]string, 0, len(in))
	for _, item := range in {
		v := strings.TrimSpace(item)

		if v == "" {

			continue

		}

		if _, ok := seen[v]; ok {

			continue

		}

		seen[v] = struct{}{}
		out = append(out, v)
	}
	return out
}

// ========== 推送通知相关 API ==========  // GetWebPushConfig 获取 H5 WebPush 订阅配置
func (h *UserHandler) GetWebPushConfig(c *gin.Context) {
	if h.pushSvc == nil {

		response.Success(c, gin.H{

			"enabled": false,

			"public_key": "",
		})

		return
	}
	publicKey, enabled := h.pushSvc.WebPushPublicKey()
	response.Success(c, gin.H{

		"enabled": enabled,

		"public_key": publicKey,
	})
}
func isValidWebPushSubscription(raw string) bool {
	var payload struct {
		Endpoint string `json:"endpoint"`

		Keys struct {
			Auth string `json:"auth"`

			P256dh string `json:"p256dh"`
		} `json:"keys"`
	}
	if err := json.Unmarshal([]byte(raw), &payload); err != nil {

		return false
	}
	return strings.TrimSpace(payload.Endpoint) != "" &&

		strings.TrimSpace(payload.Keys.Auth) != "" &&

		strings.TrimSpace(payload.Keys.P256dh) != ""
}

// UpdatePushToken 更新推送 token
func (h *UserHandler) UpdatePushToken(c *gin.Context) {
	userID := c.GetString("user_id")
	jwtDeviceID := strings.TrimSpace(c.GetString("device_id"))
	var req struct {
		DeviceID string `json:"device_id"`

		PushToken string `json:"push_token"`

		RegistrationID string `json:"registration_id"`

		DeviceType string `json:"device_type"` // ios/android/web

		Platform string `json:"platform"` // ios/android/web

		PushChannel string `json:"push_channel"` // apns/apns_voip/fcm/hms/jpush/xiaomi/oppo/webpush

		PushProvider string `json:"push_provider"` // jpush/apns/apns_voip/fcm/hms/xiaomi/oppo/webpush

		Brand string `json:"brand"` // HUAWEI/HONOR/XIAOMI/OPPO/VIVO/APPLE

		Model string `json:"model"` // device model

		DeviceName string `json:"device_name"` // display name

		AppVersion string `json:"app_version"` // app version/build
	}
	if err := c.ShouldBindJSON(&req); err != nil {

		log.Printf("[Push Token] Bad request: %v", err)

		response.BadRequest(c, "参数错误")

		return
	}
	req.PushToken = strings.TrimSpace(req.PushToken)
	if req.PushToken == "" {

		req.PushToken = strings.TrimSpace(req.RegistrationID)
	}
	req.DeviceType = strings.ToLower(strings.TrimSpace(req.DeviceType))
	if req.DeviceType == "" {

		req.DeviceType = strings.ToLower(strings.TrimSpace(req.Platform))
	}
	if req.PushToken == "" {

		response.BadRequest(c, "push token 不能为空")

		return
	}
	pushChannelInput := strings.TrimSpace(req.PushChannel)
	if pushChannelInput == "" {

		pushChannelInput = strings.TrimSpace(req.PushProvider)
	}
	pushChannel := services.NormalizeExplicitPushChannel(pushChannelInput, req.DeviceType)
	requestDeviceID := strings.TrimSpace(req.DeviceID)
	if requestDeviceID != "" && requestDeviceID != jwtDeviceID {

		response.Error(c, deviceIdentityMismatchCode, "device_identity_mismatch")

		return
	}
	maxTokenLen := 2048
	if pushChannel == services.PushChannelWebPush {

		maxTokenLen = 8192

		if !isValidWebPushSubscription(req.PushToken) {

			response.BadRequest(c, "WebPush 订阅格式错误")

			return

		}
	}
	if len(req.PushToken) > maxTokenLen {

		response.BadRequest(c, "push token 长度超过限制")

		return
	}
	log.Printf("[Push Token] Received token for user %s, device %s, type %s, channel %s, token length: %d",

		userID, jwtDeviceID, req.DeviceType, pushChannel, len(req.PushToken))
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	device, err := services.BindPushToken(

		h.db,

		user.ID,

		jwtDeviceID,

		pushChannel,

		req.PushToken,

		services.PushBindingMetadata{

			DeviceType: req.DeviceType,

			Brand: req.Brand,

			Model: req.Model,

			DeviceName: req.DeviceName,

			AppVersion: req.AppVersion,
		},
	)
	if err != nil {

		log.Printf("[Push Token] Bind failed: %v", err)

		switch {

		case errors.Is(err, services.ErrPushDeviceMismatch):

			response.Error(c, deviceIdentityMismatchCode, "device_identity_mismatch")

		case errors.Is(err, services.ErrInvalidPushChannel), errors.Is(err, services.ErrInvalidPushToken):

			response.BadRequest(c, "push token 或通道格式错误")

		default:

			response.ServerError(c, "推送 token 更新失败")

		}

		return
	}
	response.Success(c, gin.H{

		"message": "推送 token 已更新",

		"binding_id": device.ID,

		"device_id": jwtDeviceID,

		"push_channel": device.PushChannel,

		"updated_at": device.PushTokenUpdatedAt,
	})
}

// DeletePushToken 精确解绑当前设备的单条推送 token。
func (h *UserHandler) DeletePushToken(c *gin.Context) {
	if c.Request.Method == http.MethodDelete {

		response.Error(c, pushProtocolUpgradeRequiredCode, "upgrade_required")

		return
	}
	userID := c.GetString("user_id")
	deviceID := strings.TrimSpace(c.GetString("device_id"))
	var binding services.PushBindingRequest
	if err := c.ShouldBindJSON(&binding); err != nil {

		response.BadRequest(c, "完整的推送绑定参数不能为空")

		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	cleared, err := services.ClearPushBinding(h.db, user.ID, deviceID, binding)
	if err != nil {

		switch {

		case errors.Is(err, services.ErrPushDeviceMismatch):

			response.Error(c, deviceIdentityMismatchCode, "device_identity_mismatch")

		case errors.Is(err, services.ErrInvalidPushChannel), errors.Is(err, services.ErrInvalidPushToken):

			response.BadRequest(c, "push token 或通道格式错误")

		default:

			response.ServerError(c, "推送 token 解绑失败")

		}

		return
	}
	response.Success(c, gin.H{"message": "推送 token 已清除", "cleared": cleared})
}

type updatePushSettingsRequest struct {
	ShowPreview *bool `json:"show_preview"`
	Enabled     *bool `json:"enabled"`
}

func pushSettingUpsertValues(
	userID uint64,
	req updatePushSettingsRequest,
	now time.Time) (map[string]interface{}, map[string]interface{}) {
	createValues := map[string]interface{}{

		"user_id": userID,

		"enabled": true,

		"show_preview": true,

		"created_at": now,

		"updated_at": now,
	}
	updateValues := map[string]interface{}{"updated_at": now}
	if req.Enabled != nil {

		createValues["enabled"] = *req.Enabled

		updateValues["enabled"] = *req.Enabled
	}
	if req.ShowPreview != nil {

		createValues["show_preview"] = *req.ShowPreview

		updateValues["show_preview"] = *req.ShowPreview
	}
	return createValues, updateValues
}

// UpdatePushSettings 更新推送设置（消息预览等）
func (h *UserHandler) UpdatePushSettings(c *gin.Context) {
	userID := c.GetString("user_id")
	var req updatePushSettingsRequest
	if err := c.ShouldBindJSON(&req); err != nil {

		response.BadRequest(c, "参数错误")

		return
	}
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	// Map-based upsert preserves an explicit false on the first write. Creating
	// the model struct directly would let GORM replace bool zero values with the
	// model's default:1 tags, silently re-enabling notifications and previews.
	createValues, updateValues := pushSettingUpsertValues(user.ID, req, time.Now())
	if err := h.db.Model(&models.UserPushSetting{}).
		Clauses(clause.OnConflict{

			Columns: []clause.Column{{Name: "user_id"}},

			DoUpdates: clause.Assignments(updateValues),
		}).
		Create(createValues).Error; err != nil {

		log.Printf("[Push Settings] Upsert failed for user %s: %v", userID, err)

		response.ServerError(c, "推送设置更新失败")

		return
	}
	var setting models.UserPushSetting
	if err := h.db.Where("user_id = ?", user.ID).First(&setting).Error; err != nil {

		log.Printf("[Push Settings] Reload failed for user %s: %v", userID, err)

		response.ServerError(c, "推送设置更新失败")

		return
	}
	log.Printf("[Push Settings] Updated for user %s: enabled=%v show_preview=%v", userID, setting.Enabled, setting.ShowPreview)
	response.Success(c, gin.H{

		"message": "推送设置已更新",

		"enabled": setting.Enabled,

		"show_preview": setting.ShowPreview,
	})
}

// GetPushSettings 获取推送设置
func (h *UserHandler) GetPushSettings(c *gin.Context) {
	userID := c.GetString("user_id")
	var user models.User
	if err := h.db.Where("uuid = ?", userID).First(&user).Error; err != nil {

		response.NotFound(c, "用户不存在")

		return
	}
	var setting models.UserPushSetting
	if err := h.db.Where("user_id = ?", user.ID).First(&setting).Error; err != nil {

		if !errors.Is(err, gorm.ErrRecordNotFound) {

			response.ServerError(c, "推送设置读取失败")

			return

		}

		// 返回默认设置

		response.Success(c, gin.H{

			"enabled": true,

			"show_preview": true,
		})

		return
	}
	response.Success(c, gin.H{

		"enabled": setting.Enabled,

		"show_preview": setting.ShowPreview,
	})
}
