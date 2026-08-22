// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"context"
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"net/http"
	"strconv"
	"strings"
	"time"
	"genericim/internal/cache"
	"genericim/internal/models"
	"genericim/internal/services"
	"genericim/pkg/response"
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

var adminTimeLocation = time.FixedZone("Asia/Shanghai", 8*60*60)

func NewUserMgmtHandler(db *gorm.DB, hub UserMgmtHub, c *cache.Cache, pushServices ...*services.PushService) *UserMgmtHandler {
	h := &UserMgmtHandler{db: db, hub: hub, cache: c}
	if len(pushServices) > 0 {
		h.push = pushServices[0]
	}
	return h
}

// UserListItem 用户列表项（包含设备和在线信息）
type UserListItem struct {
	ID                     uint64  `json:"id"`
	UUID                   string  `json:"uuid"`
	Username               string  `json:"username"`
	Nickname               string  `json:"nickname"`
	Gender                 string  `json:"gender"`
	RegisterSource         string  `json:"register_source"`
	CredentialsInitialized bool    `json:"credentials_initialized"`
	Phone                  *string `json:"phone"`
	Avatar                 *string `json:"avatar"`
	Bio                    *string `json:"bio"`
	Status                 int8    `json:"status"`
	BanReason              *string `json:"ban_reason"`
	BannedAt               *string `json:"banned_at"`
	IsOnline               bool    `json:"is_online"`
	LastSeen               *string `json:"last_seen"`
	CreatedAt              string  `json:"created_at"`
	DeviceType             *string `json:"device_type"`
	DeviceName             *string `json:"device_name"`
	DeviceIP               *string `json:"device_ip"`
	PushChannel            *string `json:"push_channel"`
	PushTokenBound         *bool   `json:"push_token_bound"`
	PushTokenLength        *int    `json:"push_token_length"`
	ServiceUserID          *uint64 `json:"service_user_id"`
	ServiceUsername        *string `json:"service_username"`
	ServiceNickname        *string `json:"service_nickname"`
	ServiceInviteCode      *string `json:"service_invite_code"`
	// InviteCode 用户个人邀请码（10 位数字，首位 1-9）
	InviteCode            *string `json:"invite_code,omitempty"`
	// BindID 绑定的官方客服用户 ID，可空
	BindID                *uint64 `json:"bind_id,omitempty"`
	// BindUserName 绑定的官方客服昵称（冗余字段，仅展示用），可空
	BindUserName          *string `json:"bind_user_name,omitempty"`
	// RecommenderID 推荐人用户 ID，可空
	RecommenderID         *uint64 `json:"recommender_id,omitempty"`
	// RecommenderName 推荐人昵称（冗余字段，方便后台展示），可空
	RecommenderName       *string `json:"recommender_name,omitempty"`
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
	return t.In(adminTimeLocation).Format("2006-01-02 15:04:05")
}

func formatAdminTimePtr(t *time.Time) string {
	if t == nil {
		return ""
	}
	return formatAdminTime(*t)
}

// ListUsers

func (h *UserMgmtHandler) ListUsers(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page <= 0 {
		page = 1
	}
	if pageSize <= 0 {
		pageSize = 20
	}
	keyword := strings.TrimSpace(c.Query("keyword"))
	searchMode := strings.ToLower(strings.TrimSpace(c.DefaultQuery("search_mode", "exact")))
	status := c.Query("status")
	gender := strings.ToLower(strings.TrimSpace(c.Query("gender")))
	registerSource := strings.ToLower(strings.TrimSpace(c.Query("register_source")))
	credentialsStatus := strings.ToLower(strings.TrimSpace(c.Query("credentials_status")))
	onlineOnly := isSystemSettingTrue(c.Query("online_only"))
	inviteCodeQuery := strings.TrimSpace(c.Query("invite_code"))
	// recommender_id 允许 0 表示未绑定推荐人
	var recommenderIDQuery *uint64
	if rawRec := strings.TrimSpace(c.Query("recommender_id")); rawRec != "" {
		if v, parseErr := strconv.ParseUint(rawRec, 10, 64); parseErr == nil {
			recommenderIDQuery = &v
		}
	}
	offset := (page - 1) * pageSize

	query := h.db.Model(&models.User{})

	// 状态筛选
	if status != "" {
		query = query.Where("status = ?", status)
	}
	if gender != "" {
		switch gender {
		case "male", "female":
			query = query.Where("gender = ?", gender)
		case "unknown":
			query = query.Where("gender IS NULL OR gender = '' OR gender = 'unknown'")
		default:
			response.Error(c, http.StatusBadRequest, "性别筛选参数错误")
			return
		}
	}
	if registerSource != "" {
		if registerSource != models.UserRegisterSourceManual && registerSource != models.UserRegisterSourceQuick {
			response.Error(c, http.StatusBadRequest, "注册来源筛选参数错误")
			return
		}
		query = query.Where("register_source = ?", registerSource)
	}
	if inviteCodeQuery != "" {
		query = query.Where("invite_code = ?", inviteCodeQuery)
	}
	if recommenderIDQuery != nil {
		query = query.Where("recommender_id = ?", *recommenderIDQuery)
	}
	if credentialsStatus != "" {
		switch credentialsStatus {
		case "initialized":
			query = query.Where("credentials_initialized = ?", true)
		case "pending":
			query = query.Where("credentials_initialized = ?", false)
		default:
			response.Error(c, http.StatusBadRequest, "登录凭证筛选参数错误")
			return
		}
	}

	// 搜索模式由后台显式控制：精确账号用于定位单个账号，模糊搜索用于批量排查。
	if keyword != "" {
		exactCondition := "uuid = ? OR username = ? OR phone = ?"
		if searchMode == "fuzzy" {
			query = query.Where("uuid = ? OR nickname LIKE ? OR username LIKE ? OR phone LIKE ?",
				keyword, "%"+keyword+"%", "%"+keyword+"%", "%"+keyword+"%")
		} else {
			query = query.Where(exactCondition, keyword, keyword, keyword)
		}
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	var users []models.User
	userQuery := query.Order("created_at DESC")
	if !onlineOnly {
		userQuery = userQuery.Offset(offset).Limit(pageSize)
	}
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

	// 获取用户邀请码归属信息（通过邀请码注册绑定的客服）
	type userInviteBinding struct {
		UserID          uint64 `gorm:"column:user_id"`
		ServiceUserID   uint64 `gorm:"column:service_user_id"`
		ServiceUsername string `gorm:"column:service_username"`
		ServiceNickname string `gorm:"column:service_nickname"`
		InviteCode      string `gorm:"column:invite_code"`
	}
	inviteBindingMap := make(map[uint64]userInviteBinding)
	if len(userIDs) > 0 {
		latestUsageSubQuery := h.db.Table("invite_code_usages").
			Select("MAX(id)").
			Where("user_id IN ?", userIDs).
			Group("user_id")

		var bindings []userInviteBinding
		if err := h.db.Table("invite_code_usages AS icu").
			Select(` 				icu.user_id AS user_id, ic.service_user_id AS service_user_id, su.username AS service_username, su.nickname AS service_nickname, ic.code AS invite_code 			`).
			Joins("JOIN invite_codes ic ON ic.id = icu.invite_code_id").
			Joins("LEFT JOIN users su ON su.id = ic.service_user_id AND su.deleted_at IS NULL").
			Where("icu.id IN(?)", latestUsageSubQuery).
			Scan(&bindings).Error; err != nil {
			response.Error(c, http.StatusInternalServerError, "查询失败")
			return
		}
		for _, b := range bindings {
			inviteBindingMap[b.UserID] = b
		}
	}

	// 构建推荐人 / 绑定客服的昵称映射，用于列表展示
	recommenderIDSet := map[uint64]struct{}{}
	bindIDSet := map[uint64]struct{}{}
	for _, u := range users {
		if u.RecommenderID != nil {
			recommenderIDSet[*u.RecommenderID] = struct{}{}
		}
		if u.BindID != nil {
			bindIDSet[*u.BindID] = struct{}{}
		}
	}
	recommenderNameMap := make(map[uint64]string)
	bindNameMap := make(map[uint64]string)
	fillUserBriefs := func(idSet map[uint64]struct{}, target map[uint64]string) {
		if len(idSet) == 0 {
			return
		}
		ids := make([]uint64, 0, len(idSet))
		for id := range idSet {
			ids = append(ids, id)
		}
		type brief struct {
			ID       uint64
			Nickname string
			Username string
		}
		var rows []brief
		if err := h.db.Model(&models.User{}).
			Select("id, nickname, username").
			Where("id IN ? AND deleted_at IS NULL", ids).
			Scan(&rows).Error; err == nil {
			for _, r := range rows {
				display := r.Nickname
				if display == "" {
					display = r.Username
				}
				target[r.ID] = display
			}
		}
	}
	fillUserBriefs(recommenderIDSet, recommenderNameMap)
	fillUserBriefs(bindIDSet, bindNameMap)

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
			ID:                     u.ID,
			UUID:                   u.UUID,
			Username:               u.Username,
			Nickname:               u.Nickname,
			Gender:                 u.Gender,
			RegisterSource:         u.RegisterSource,
			CredentialsInitialized: u.CredentialsInitialized,
			Status:                 u.Status,
			IsOnline:               false,
			CreatedAt:              formatAdminTime(u.CreatedAt),
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
			lastSeen := formatAdminTime(u.LastSeen)
			item.LastSeen = &lastSeen
		}
		// 封禁信息
		if u.BanReason != "" {
			item.BanReason = &u.BanReason
		}
		if u.BannedAt != nil {
			bannedAt := formatAdminTime(*u.BannedAt)
			item.BannedAt = &bannedAt
		}

		// 邀请码 / 绑定客服 / 推荐人信息
		if u.InviteCode != "" {
			ic := u.InviteCode
			item.InviteCode = &ic
		}
		if u.BindID != nil && *u.BindID > 0 {
			bid := *u.BindID
			item.BindID = &bid
			if name, ok := bindNameMap[*u.BindID]; ok && name != "" {
				item.BindUserName = &name
			}
		}
		if u.RecommenderID != nil && *u.RecommenderID > 0 {
			rid := *u.RecommenderID
			item.RecommenderID = &rid
			if name, ok := recommenderNameMap[*u.RecommenderID]; ok && name != "" {
				item.RecommenderName = &name
			}
		}

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
			lastActive := formatAdminTime(device.LastActive)
			item.LastSeen = &lastActive
		}

		// 添加邀请码归属信息
		if bind, ok := inviteBindingMap[u.ID]; ok {
			item.ServiceUserID = uint64Ptr(bind.ServiceUserID)
			if bind.ServiceUsername != "" {
				item.ServiceUsername = stringPtr(bind.ServiceUsername)
			}
			if bind.ServiceNickname != "" {
				item.ServiceNickname = stringPtr(bind.ServiceNickname)
			}
			if bind.InviteCode != "" {
				item.ServiceInviteCode = stringPtr(bind.InviteCode)
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
		Nickname *string  `json:"nickname"`
		Username *string  `json:"username"`
		Phone    *string  `json:"phone"`
		Bio      *string  `json:"bio"`
		Status   *int8    `json:"status"`
		Gender   *string  `json:"gender"`
		// BindID 绑定客服用户 ID，0 或 nil 表示解绑
		BindID *uint64 `json:"bind_id"`
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
	if req.Gender != nil {
		gender := strings.ToLower(strings.TrimSpace(*req.Gender))
		if gender != "male" && gender != "female" && gender != "unknown" {
			response.Error(c, http.StatusBadRequest, "性别必须为 male、female 或 unknown")
			return
		}
		updates["gender"] = gender
	}
	if req.BindID != nil {
		// 0 表示解绑客服
		if *req.BindID == 0 {
			updates["bind_id"] = nil
		} else {
			// 校验客服用户是否存在
			var serviceUser models.User
			if err := h.db.First(&serviceUser, *req.BindID).Error; err != nil {
				response.Error(c, http.StatusBadRequest, "绑定的客服用户不存在")
				return
			}
			if serviceUser.ID == user.ID {
				response.Error(c, http.StatusBadRequest, "不能将自己绑定为客服")
				return
			}
			updates["bind_id"] = *req.BindID
		}
	}
	if len(updates) > 0 {
		if err := h.db.Model(&user).Updates(updates).Error; err != nil {
			response.Error(c, http.StatusInternalServerError, "更新失败")
			return
		}
	}

	// 重新查询用户
	h.db.First(&user, userID)
	response.Success(c, user)
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
	h.db.Model(&models.User{}).
		Where("created_at >= CURDATE() AND created_at < DATE_ADD(CURDATE(), INTERVAL 1 DAY)").
		Count(&newUsersToday)

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

// KickUser

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

// FreezeUser

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

// ResetUserPassword

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
