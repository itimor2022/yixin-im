package handlers

import (
	"context"
	"net/http"
	"strconv"
	"strings"
	"time"

	"gaoranim/internal/cache"
	"gaoranim/internal/models"
	"gaoranim/internal/services"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type UserMgmtHub interface {
	IsUserOnline(string) bool
	DisconnectUser(string)
}

type UserMgmtHandler struct {
	db    *gorm.DB
	hub   UserMgmtHub
	cache *cache.Cache
	push  *services.PushService
}

func NewUserMgmtHandler(db *gorm.DB, hub UserMgmtHub, c *cache.Cache, pushServices ...*services.PushService) *UserMgmtHandler {
	h := &UserMgmtHandler{db: db, hub: hub, cache: c}
	if len(pushServices) > 0 {
		h.push = pushServices[0]
	}
	return h
}

// UserListItem 用户列表项（包含设备和在线信息）
type UserListItem struct {
	ID              uint64  `json:"id"`
	UUID            string  `json:"uuid"`
	Username        string  `json:"username"`
	Nickname        string  `json:"nickname"`
	Phone           *string `json:"phone"`
	Avatar          *string `json:"avatar"`
	Bio             *string `json:"bio"`
	Status          int8    `json:"status"`
	BanReason       *string `json:"ban_reason"`
	BannedAt        *string `json:"banned_at"`
	IsMember        bool    `json:"is_member"`
	BadgeText       string  `json:"badge_text"`
	BadgeColor      string  `json:"badge_color"`
	IsOnline        bool    `json:"is_online"`
	LastSeen        *string `json:"last_seen"`
	CreatedAt       string  `json:"created_at"`
	DeviceType      *string `json:"device_type"`
	DeviceName      *string `json:"device_name"`
	DeviceIP        *string `json:"device_ip"`
	PushChannel     *string `json:"push_channel"`
	PushTokenBound  *bool   `json:"push_token_bound"`
	PushTokenLength *int    `json:"push_token_length"`
	InviterPhone    *string `json:"inviter_phone"`    // 上级手机号（邀请码）
	InviterNickname *string `json:"inviter_nickname"` // 上级昵称
	EnableWhitelist bool    `json:"enable_whitelist"`
	WhitelistIps    string  `json:"whitelist_ips"`
}

func uint64Ptr(v uint64) *uint64 {
	return &v
}

func stringPtr(v string) *string {
	return &v
}

func boolPtr(v bool) *bool {
	return &v
}

func intPtr(v int) *int {
	return &v
}

func formatAdminTime(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.Format("2006-01-02 15:04:05")
}

// ListUsers 获取用户列表（包含在线状态和设备信息）
func (h *UserMgmtHandler) ListUsers(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page <= 0 {
		page = 1
	}
	if pageSize <= 0 {
		pageSize = 20
	}
	keyword := c.Query("keyword")
	status := c.Query("status")
	onlineOnly := isSystemSettingTrue(c.Query("online_only"))

	offset := (page - 1) * pageSize

	query := h.db.Model(&models.User{})

	// 搜索（支持 UUID 精确匹配）
	if keyword != "" {
		query = query.Where("uuid = ? OR nickname LIKE ? OR username LIKE ? OR phone LIKE ?",
			keyword, "%"+keyword+"%", "%"+keyword+"%", "%"+keyword+"%")
	}

	// 状态筛选
	if status != "" {
		query = query.Where("status = ?", status)
	}

	// onlineOnly 模式：先从 Redis SCAN 拿在线 UUID，再查 MySQL，避免全表扫描
	if onlineOnly {
		onlineUUIDs, err := h.cache.GetOnlineUserUUIDs(c.Request.Context())
		if err != nil || len(onlineUUIDs) == 0 {
			response.Success(c, gin.H{"total": 0, "list": []interface{}{}})
			return
		}
		query = query.Where("uuid IN ?", onlineUUIDs)
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	var users []models.User
	userQuery := query.Order("created_at DESC").Offset(offset).Limit(pageSize)
	if err := userQuery.Find(&users).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	// 获取用户ID列表
	userIDs := make([]uint64, len(users))
	for i, u := range users {
		userIDs[i] = u.ID
	}

	// 获取最近设备信息
	var devices []models.UserDevice
	if len(userIDs) > 0 {
		if err := h.db.Where("user_id IN ?", userIDs).
			Order("last_active DESC").
			Find(&devices).Error; err != nil {
			response.Error(c, http.StatusInternalServerError, "查询失败")
			return
		}
	}

	// 获取用户邀请码归属信息（通过邀请码注册绑定的上级）
	// 现在邀请码是手机号，直接通过contacts表查找上级
	type userInviteBinding struct {
		UserID          uint64 `gorm:"column:user_id"`
		InviterID       uint64 `gorm:"column:inviter_id"`
		InviterPhone    string `gorm:"column:inviter_phone"`
		InviterNickname string `gorm:"column:inviter_nickname"`
	}
	inviteBindingMap := make(map[uint64]userInviteBinding)
	if len(userIDs) > 0 {
		// 通过contacts表查找每个用户的上级（第一个添加他为好友的官方客服）
		var bindings []userInviteBinding
		if err := h.db.Table("contacts AS c").
			Select(`
				c.target_id AS user_id,
				c.user_id AS inviter_id,
				su.phone AS inviter_phone,
				su.nickname AS inviter_nickname
			`).
			Joins("JOIN users su ON su.id = c.user_id AND su.deleted_at IS NULL").
			Where("c.target_id IN ? AND c.status = 1", userIDs).
			Scan(&bindings).Error; err == nil {
			for _, b := range bindings {
				// 只取第一个绑定（最新的）
				if _, exists := inviteBindingMap[b.UserID]; !exists {
					inviteBindingMap[b.UserID] = b
				}
			}
		}
	}

	// 构建设备映射（每个用户只取最近活跃的设备）
	deviceMap := make(map[uint64]models.UserDevice)
	for _, d := range devices {
		if _, exists := deviceMap[d.UserID]; !exists {
			deviceMap[d.UserID] = d
		}
	}

	// 判断在线：优先使用 WebSocket Hub 实时状态，回退到设备活跃时间
	now := time.Now()
	onlineThreshold := now.Add(-5 * time.Minute)

	// 构建结果
	result := make([]UserListItem, 0, len(users))
	for _, u := range users {
		item := UserListItem{
			ID:              u.ID,
			UUID:            u.UUID,
			Username:        u.Username,
			Nickname:        u.Nickname,
			Status:          u.Status,
			IsOnline:        false,
			CreatedAt:       u.CreatedAt.Format("2006-01-02 15:04:05"),
			EnableWhitelist: u.EnableWhitelist,
			WhitelistIps:    u.WhitelistIps,
		}

		// 设置可选字段
		if u.Phone != nil && *u.Phone != "" {
			item.Phone = u.Phone
		}
		if u.Avatar != "" {
			item.Avatar = &u.Avatar
		}
		if u.Bio != "" {
			item.Bio = &u.Bio
		}
		if !u.LastSeen.IsZero() {
			lastSeen := u.LastSeen.Format("2006-01-02 15:04:05")
			item.LastSeen = &lastSeen
		}
		// 封禁信息
		if u.BanReason != "" {
			item.BanReason = &u.BanReason
		}
		if u.BannedAt != nil {
			bannedAt := u.BannedAt.Format("2006-01-02 15:04:05")
			item.BannedAt = &bannedAt
		}
		// 会员信息
		item.IsMember = u.IsMember
		item.BadgeText = u.BadgeText
		item.BadgeColor = u.BadgeColor

		// 通过 WebSocket Hub 判断实时在线状态
		if h.hub != nil && h.hub.IsUserOnline(u.UUID) {
			item.IsOnline = true
		}

		// 添加设备信息
		if device, ok := deviceMap[u.ID]; ok {
			item.DeviceType = &device.DeviceType
			item.DeviceName = &device.DeviceName
			item.DeviceIP = &device.IP
			channel := strings.TrimSpace(device.PushChannel)
			token := strings.TrimSpace(device.PushToken)
			item.PushChannel = &channel
			item.PushTokenBound = boolPtr(token != "")
			item.PushTokenLength = intPtr(len(token))

			// 如果 Hub 未判断为在线，回退到设备活跃时间
			if !item.IsOnline && device.LastActive.After(onlineThreshold) {
				item.IsOnline = true
			}
			lastActive := device.LastActive.Format("2006-01-02 15:04:05")
			item.LastSeen = &lastActive
		}

		// 添加上级信息（邀请码绑定）
		if bind, ok := inviteBindingMap[u.ID]; ok {
			if bind.InviterPhone != "" {
				item.InviterPhone = stringPtr(bind.InviterPhone)
			}
			if bind.InviterNickname != "" {
				item.InviterNickname = stringPtr(bind.InviterNickname)
			}
		}

		// 如果只要在线用户
		if onlineOnly && !item.IsOnline {
			continue
		}

		result = append(result, item)
	}

	// 重新计算总数（如果是在线筛选）
	if onlineOnly {
		total = int64(len(result))
		start := offset
		if start > len(result) {
			start = len(result)
		}
		end := start + pageSize
		if end > len(result) {
			end = len(result)
		}
		result = result[start:end]
	}

	response.Success(c, gin.H{
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}

// UpdateUser 更新用户信息
func (h *UserMgmtHandler) UpdateUser(c *gin.Context) {
	userID := c.Param("id")

	var req struct {
		Nickname        *string `json:"nickname"`
		Username        *string `json:"username"`
		Phone           *string `json:"phone"`
		Bio             *string `json:"bio"`
		Status          *int8   `json:"status"`
		EnableWhitelist *bool   `json:"enable_whitelist"`
		WhitelistIps    *string `json:"whitelist_ips"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	// 更新字段
	updates := make(map[string]interface{})
	if req.Nickname != nil {
		updates["nickname"] = *req.Nickname
	}
	if req.Username != nil {
		// 检查用户名是否已存在
		var existUser models.User
		if err := h.db.Where("username = ? AND id != ?", *req.Username, user.ID).First(&existUser).Error; err == nil {
			response.Error(c, http.StatusBadRequest, "用户名已存在")
			return
		}
		updates["username"] = *req.Username
	}
	if req.Phone != nil {
		updates["phone"] = *req.Phone
	}
	if req.Bio != nil {
		updates["bio"] = *req.Bio
	}
	if req.Status != nil {
		updates["status"] = *req.Status
	}
	if req.EnableWhitelist != nil {
		updates["enable_whitelist"] = *req.EnableWhitelist
	}
	if req.WhitelistIps != nil {
		updates["whitelist_ips"] = *req.WhitelistIps
	}

	if len(updates) > 0 {
		if err := h.db.Model(&user).Updates(updates).Error; err != nil {
			response.Error(c, http.StatusInternalServerError, "更新失败")
			return
		}
	}
	if h.cache != nil {
		userIDStr := strconv.FormatUint(user.ID, 10)
		redisKey := "user:whitelist:" + user.UUID

		if req.EnableWhitelist != nil && *req.EnableWhitelist {
			ips := ""
			if req.WhitelistIps != nil {
				ips = *req.WhitelistIps
			}
			h.cache.Set(context.Background(), redisKey, ips, 365*24*time.Hour)

			type UserSession struct {
				Token string `gorm:"column:token"`
				IP    string `gorm:"column:ip"`
			}
			var sessions []UserSession

			if err := h.db.Table("user_sessions").Where("user_id = ?", user.ID).Find(&sessions).Error; err == nil {
				needDisconnect := false
				for _, sess := range sessions {
					if !CheckIPInWhitelist(sess.IP, ips) {
						needDisconnect = true
						h.db.Table("user_sessions").Where("token = ?", sess.Token).Delete(nil)
					}
				}

				if needDisconnect || len(sessions) == 0 {
					h.hub.DisconnectUser(user.UUID)
					h.hub.DisconnectUser(userIDStr)
				}
			}
		} else if req.EnableWhitelist != nil && !*req.EnableWhitelist {
			h.cache.Delete(context.Background(), redisKey)
		}
	}

	// 重新查询用户并返回
	h.db.First(&user, userID)
	response.Success(c, user)
}

func CheckIPInWhitelist(clientIP string, whitelistStr string) bool {
	if whitelistStr == "" {
		return false
	}
	ips := strings.FieldsFunc(whitelistStr, func(r rune) bool {
		return r == '\n' || r == '\r' || r == ',' || r == ' '
	})
	for _, ip := range ips {
		if strings.TrimSpace(ip) == clientIP {
			return true
		}
	}
	return false
}

// UpdateUserStatus 更新用户状态
func (h *UserMgmtHandler) UpdateUserStatus(c *gin.Context) {
	userID := c.Param("id")

	var req struct {
		Status int8 `json:"status" binding:"oneof=0 1 2 3"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	user.Status = req.Status
	if err := h.db.Save(&user).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "更新失败")
		return
	}

	response.Success(c, user)
}

// GetUserStats 获取用户统计
func (h *UserMgmtHandler) GetUserStats(c *gin.Context) {
	var totalUsers int64
	var activeUsers int64
	var newUsersToday int64
	var onlineUsers int64

	h.db.Model(&models.User{}).Count(&totalUsers)
	h.db.Model(&models.User{}).Where("status = 1").Count(&activeUsers)
	h.db.Model(&models.User{}).Where("DATE(created_at) = CURDATE()").Count(&newUsersToday)

	// 在线用户数（最近5分钟活跃）
	h.db.Model(&models.UserDevice{}).
		Where("last_active > DATE_SUB(NOW(), INTERVAL 5 MINUTE)").
		Distinct("user_id").
		Count(&onlineUsers)

	response.Success(c, gin.H{
		"total_users":     totalUsers,
		"active_users":    activeUsers,
		"new_users_today": newUsersToday,
		"online_users":    onlineUsers,
	})
}

// KickUser 强制下线用户
func (h *UserMgmtHandler) KickUser(c *gin.Context) {
	userID := c.Param("id")

	// 删除用户所有设备记录
	h.db.Where("user_id = ?", userID).Delete(&models.UserDevice{})

	// 通过 UUID 获取用户以断开 WebSocket
	var user models.User
	if err := h.db.Where("id = ?", userID).First(&user).Error; err == nil {
		h.hub.DisconnectUser(user.UUID)
	}

	response.SuccessWithMessage(c, "用户已强制下线", nil)
}

// BanUser 封禁用户（可登录但不能发消息）
func (h *UserMgmtHandler) BanUser(c *gin.Context) {
	userID := c.Param("id")

	var req struct {
		Reason string `json:"reason" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "请提供封禁原因")
		return
	}

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	// 不能封禁管理员（可选：检查用户角色）
	if user.Status == models.UserStatusDisabled {
		response.Error(c, http.StatusBadRequest, "用户已被禁用，无需封禁")
		return
	}

	now := time.Now()
	result := h.db.Model(&user).Updates(map[string]interface{}{
		"status":     models.UserStatusBanned,
		"ban_reason": req.Reason,
		"banned_at":  now,
		"updated_at": now,
	})

	if result.Error != nil {
		response.Error(c, http.StatusInternalServerError, "封禁失败")
		return
	}

	response.SuccessWithMessage(c, "用户已被封禁", gin.H{
		"user_id":    user.ID,
		"uuid":       user.UUID,
		"ban_reason": req.Reason,
		"banned_at":  now.Format("2006-01-02 15:04:05"),
	})
}

// UnbanUser 解封用户
func (h *UserMgmtHandler) UnbanUser(c *gin.Context) {
	userID := c.Param("id")

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	if user.Status != models.UserStatusBanned {
		response.Error(c, http.StatusBadRequest, "用户未被封禁")
		return
	}

	result := h.db.Model(&user).Updates(map[string]interface{}{
		"status":     models.UserStatusNormal,
		"ban_reason": "",
		"banned_at":  nil,
		"updated_at": time.Now(),
	})

	if result.Error != nil {
		response.Error(c, http.StatusInternalServerError, "解封失败")
		return
	}

	response.SuccessWithMessage(c, "用户已解封", gin.H{
		"user_id": user.ID,
		"uuid":    user.UUID,
	})
}

// FreezeUser 冻结用户（禁用账号 + Token失效 + 强制断开WebSocket）
func (h *UserMgmtHandler) FreezeUser(c *gin.Context) {
	userID := c.Param("id")

	var req struct {
		Reason string `json:"reason"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	now := time.Now()
	h.db.Model(&user).Updates(map[string]interface{}{
		"status":     models.UserStatusDisabled,
		"ban_reason": req.Reason,
		"banned_at":  now,
		"updated_at": now,
	})

	// 删除所有设备记录（使 Token 无法续期）
	h.db.Where("user_id = ?", user.ID).Delete(&models.UserDevice{})

	// 断开所有 WebSocket 连接
	h.hub.DisconnectUser(user.UUID)

	// 在 Redis 中标记用户冻结（使后续 Token 请求被拦截）
	if h.cache != nil {
		h.cache.Set(context.Background(), "user:frozen:"+user.UUID, "1", 365*24*time.Hour)
	}

	response.SuccessWithMessage(c, "用户已冻结并强制下线", gin.H{
		"user_id": user.ID,
		"uuid":    user.UUID,
	})
}

// UnfreezeUser 解冻用户
func (h *UserMgmtHandler) UnfreezeUser(c *gin.Context) {
	userID := c.Param("id")

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		response.NotFound(c, "用户不存在")
		return
	}

	h.db.Model(&user).Updates(map[string]interface{}{
		"status":     models.UserStatusNormal,
		"ban_reason": "",
		"banned_at":  nil,
		"updated_at": time.Now(),
	})

	// 删除 Redis 冻结标记
	if h.cache != nil {
		h.cache.Delete(context.Background(), "user:frozen:"+user.UUID)
	}

	response.SuccessWithMessage(c, "用户已解冻", nil)
}

// ResetUserPassword 重置用户登录密码（重置后强制下线）
func (h *UserMgmtHandler) ResetUserPassword(c *gin.Context) {
	userID := c.Param("id")

	var req struct {
		NewPassword string `json:"new_password" binding:"required,min=6"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "请输入至少6位密码")
		return
	}

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	if err := user.SetPassword(req.NewPassword); err != nil {
		response.Error(c, http.StatusInternalServerError, "设置密码失败")
		return
	}

	user.UpdatedAt = time.Now()
	if err := h.db.Save(&user).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "保存失败")
		return
	}

	// 重置密码后强制下线
	h.db.Where("user_id = ?", user.ID).Delete(&models.UserDevice{})
	h.hub.DisconnectUser(user.UUID)

	// 在 Redis 标记该用户需要重新登录（使旧 Token 失效）
	if h.cache != nil {
		h.cache.Set(context.Background(), "user:pwd_reset:"+user.UUID, "1", 24*time.Hour)
	}

	response.SuccessWithMessage(c, "密码重置成功，用户已强制下线", gin.H{
		"user_id": user.ID,
		"uuid":    user.UUID,
	})
}

// SetMembership sets or clears the member badge for a user.
// PATCH /api/v1/admin/users/:id/membership
func (h *UserMgmtHandler) SetMembership(c *gin.Context) {
	idStr := c.Param("id")
	userID, err := strconv.ParseUint(idStr, 10, 64)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 400, "message": "无效的用户ID"})
		return
	}

	var req struct {
		IsMember   bool   `json:"is_member"`
		BadgeText  string `json:"badge_text"`
		BadgeColor string `json:"badge_color"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"code": 400, "message": "参数错误"})
		return
	}

	updates := map[string]interface{}{
		"is_member":   req.IsMember,
		"badge_text":  req.BadgeText,
		"badge_color": req.BadgeColor,
	}
	if err := h.db.Model(&models.User{}).Where("id = ?", userID).Updates(updates).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"code": 500, "message": "更新失败"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"code": 0, "message": "success"})
}

// GetSubordinates 获取用户的下级列表（通过该用户手机号作为邀请码注册的用户）
func (h *UserMgmtHandler) GetSubordinates(c *gin.Context) {
	userID := c.Param("id")
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page <= 0 {
		page = 1
	}
	if pageSize <= 0 {
		pageSize = 20
	}

	var user models.User
	if err := h.db.First(&user, userID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "用户不存在")
		return
	}

	// 如果用户没有手机号，返回空列表
	if user.Phone == nil || *user.Phone == "" {
		response.Success(c, gin.H{"list": []interface{}{}, "total": 0})
		return
	}

	offset := (page - 1) * pageSize

	// 通过contacts表查找下级（被该用户邀请注册的用户）
	type SubordinateItem struct {
		ID         uint64  `json:"id"`
		UUID       string  `json:"uuid"`
		Username   string  `json:"username"`
		Nickname   string  `json:"nickname"`
		Phone      *string `json:"phone"`
		Avatar     *string `json:"avatar"`
		Status     int8    `json:"status"`
		IsMember   bool    `json:"is_member"`
		BadgeText  string  `json:"badge_text"`
		BadgeColor string  `json:"badge_color"`
		IsOnline   bool    `json:"is_online"`
		LastSeen   *string `json:"last_seen"`
		CreatedAt  string  `json:"created_at"`
	}

	var total int64
	if err := h.db.Table("contacts AS c").
		Joins("JOIN users u ON u.id = c.target_id AND u.deleted_at IS NULL").
		Where("c.user_id = ? AND c.status = 1", user.ID).
		Count(&total).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	var subordinates []SubordinateItem
	if err := h.db.Table("contacts AS c").
		Select(`
			u.id AS id,
			u.uuid AS uuid,
			u.username AS username,
			u.nickname AS nickname,
			u.phone AS phone,
			u.avatar AS avatar,
			u.status AS status,
			u.is_member AS is_member,
			u.badge_text AS badge_text,
			u.badge_color AS badge_color,
			u.last_seen AS last_seen,
			u.created_at AS created_at
		`).
		Joins("JOIN users u ON u.id = c.target_id AND u.deleted_at IS NULL").
		Where("c.user_id = ? AND c.status = 1", user.ID).
		Order("c.created_at DESC").
		Offset(offset).Limit(pageSize).
		Scan(&subordinates).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	// 格式化时间并查询在线状态
	now := time.Now()
	onlineThreshold := now.Add(-5 * time.Minute)

	// 获取下级用户ID列表
	subordinateIDs := make([]uint64, len(subordinates))
	for i, s := range subordinates {
		subordinateIDs[i] = s.ID
	}

	// 获取设备信息
	var devices []models.UserDevice
	if len(subordinateIDs) > 0 {
		if err := h.db.Where("user_id IN ?", subordinateIDs).
			Order("last_active DESC").
			Find(&devices).Error; err != nil {
			response.Error(c, http.StatusInternalServerError, "查询失败")
			return
		}
	}

	deviceMap := make(map[uint64]models.UserDevice)
	for _, d := range devices {
		if _, exists := deviceMap[d.UserID]; !exists {
			deviceMap[d.UserID] = d
		}
	}

	// 格式化返回数据
	result := make([]gin.H, 0, len(subordinates))
	for _, s := range subordinates {
		item := gin.H{
			"id":          s.ID,
			"uuid":        s.UUID,
			"username":    s.Username,
			"nickname":    s.Nickname,
			"phone":       s.Phone,
			"avatar":      s.Avatar,
			"status":      s.Status,
			"is_member":   s.IsMember,
			"badge_text":  s.BadgeText,
			"badge_color": s.BadgeColor,
			"is_online":   false,
			"last_seen":   s.LastSeen,
			"created_at":  s.CreatedAt,
		}

		// 检查在线状态
		if h.hub != nil && h.hub.IsUserOnline(s.UUID) {
			item["is_online"] = true
		} else if device, ok := deviceMap[s.ID]; ok && device.LastActive.After(onlineThreshold) {
			item["is_online"] = true
			lastActive := device.LastActive.Format("2006-01-02 15:04:05")
			item["last_seen"] = lastActive
		}

		result = append(result, item)
	}

	response.Success(c, gin.H{
		"list":      result,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
	})
}
