// 文件用途：实现后端 HTTP 接口的请求处理和统一响应。
// 核心逻辑：绑定参数，校验身份与权限，调用业务服务并持久化关键状态。

package handlers

import (
	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"net/http"
	"strconv"
	"strings"
	"time"
	"genericim/internal/cache"
	"genericim/internal/models"
	"genericim/pkg/jwt"
	"genericim/pkg/response"
)

type AdminHandler struct {
	db    *gorm.DB
	cache *cache.Cache
}

func NewAdminHandler(db *gorm.DB, cacheStore *cache.Cache) *AdminHandler {
	return &AdminHandler{db: db, cache: cacheStore}
}

// AdminLoginRequest 管理员登录请求
type AdminLoginRequest struct {
	Username string `json:"username" binding:"required"`
	Password string `json:"password" binding:"required"`
}

// AdminLoginResponse 管理员登录响应
type AdminLoginResponse struct {
	Token string        `json:"token"`
	Admin *models.Admin `json:"admin"`
}

// Login 管理员登录
func (h *AdminHandler) Login(c *gin.Context) {
	var req AdminLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	// 查询管理员
	req.Username = strings.TrimSpace(req.Username)
	if !checkLoginThrottle(c, h.cache, "admin", req.Username) {
		h.logLoginAttempt(0, req.Username, c.ClientIP(), c.Request.UserAgent(), 0, "throttled", true)
		return
	}

	var admin models.Admin
	if err := h.db.Where("username = ?", req.Username).First(&admin).Error; err != nil {
		recordLoginFailure(c, h.cache, "admin", req.Username)
		// 记录失败日志
		h.logLoginAttempt(0, req.Username, c.ClientIP(), c.Request.UserAgent(), 0, "not_found", false)
		response.Error(c, http.StatusUnauthorized, "用户名或密码错误")
		return
	}

	// 验证密码
	if !admin.CheckPassword(req.Password) {
		recordLoginFailure(c, h.cache, "admin", req.Username)
		h.logLoginAttempt(admin.ID, admin.Username, c.ClientIP(), c.Request.UserAgent(), 0, "bad_password", false)
		response.Error(c, http.StatusUnauthorized, "用户名或密码错误")
		return
	}

	// 检查状态
	if admin.Status != 1 {
		h.logLoginAttempt(admin.ID, admin.Username, c.ClientIP(), c.Request.UserAgent(), 0, "disabled", false)
		response.Error(c, http.StatusForbidden, "账号已被禁用")
		return
	}

	clearLoginAccountThrottle(c, h.cache, "admin", req.Username)

	// 生成 Token
	token, err := jwt.GenerateAdminToken(admin.ID, admin.Username, admin.Role)
	if err != nil {
		response.Error(c, http.StatusInternalServerError, "生成Token失败")
		return
	}

	// 更新最后登录时间
	now := time.Now()
	h.db.Model(&admin).Updates(map[string]interface{}{
		"last_login_at": now,
		"last_login_ip": c.ClientIP(),
	})

	// 记录登录日志
	h.logLoginAttempt(admin.ID, admin.Username, c.ClientIP(), c.Request.UserAgent(), 1, "", false)
	response.Success(c, AdminLoginResponse{
		Token: token,
		Admin: &admin,
	})
}

// ListLoginLogs 获取管理员登录审计日志
func (h *AdminHandler) ListLoginLogs(c *gin.Context) {
	page, _ := strconv.Atoi(c.DefaultQuery("page", "1"))
	pageSize, _ := strconv.Atoi(c.DefaultQuery("page_size", "20"))
	if page <= 0 {
		page = 1
	}
	if pageSize <= 0 || pageSize > 100 {
		pageSize = 20
	}
	query := h.db.Model(&models.AdminLoginLog{})
	if username := strings.TrimSpace(c.Query("username")); username != "" {
		query = query.Where("username LIKE ?", "%"+username+"%")
	}
	if ip := strings.TrimSpace(c.Query("ip")); ip != "" {
		query = query.Where("ip LIKE ?", "%"+ip+"%")
	}
	if status := strings.TrimSpace(c.Query("status")); status != "" {
		switch status {
		case "success", "1":
			query = query.Where("status = ?", 1)
		case "failed", "0":
			query = query.Where("status = ?", 0)
		}
	}
	if throttled := strings.TrimSpace(c.Query("throttled")); throttled != "" {
		query = query.Where("throttle_applied = ?", throttled == "1" || strings.EqualFold(throttled, "true"))
	}

	var total int64
	if err := query.Count(&total).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询登录日志失败")
		return
	}

	var logs []models.AdminLoginLog
	if err := query.Order("created_at DESC, id DESC").
		Offset((page - 1) * pageSize).
		Limit(pageSize).
		Find(&logs).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询登录日志失败")
		return
	}
	items := make([]gin.H, 0, len(logs))
	for _, item := range logs {
		items = append(items, gin.H{
			"id":               item.ID,
			"admin_id":         item.AdminID,
			"username":         item.Username,
			"ip":               item.IP,
			"user_agent":       item.UserAgent,
			"status":           item.Status,
			"failure_reason":   item.FailureReason,
			"throttle_applied": item.ThrottleApplied,
			"created_at":       formatAdminTime(item.CreatedAt),
		})
	}
	since := time.Now().Add(-24 * time.Hour)
	var total24h, success24h, failed24h, throttled24h int64
	_ = h.db.Model(&models.AdminLoginLog{}).Where("created_at >= ?", since).Count(&total24h).Error
	_ = h.db.Model(&models.AdminLoginLog{}).Where("created_at >= ? AND status = ?", since, 1).Count(&success24h).Error
	_ = h.db.Model(&models.AdminLoginLog{}).Where("created_at >= ? AND status = ?", since, 0).Count(&failed24h).Error
	_ = h.db.Model(&models.AdminLoginLog{}).Where("created_at >= ? AND throttle_applied = ?", since, true).Count(&throttled24h).Error

	response.Success(c, gin.H{
		"list":      items,
		"total":     total,
		"page":      page,
		"page_size": pageSize,
		"summary": gin.H{
			"total_24h":     total24h,
			"success_24h":   success24h,
			"failed_24h":    failed24h,
			"throttled_24h": throttled24h,
		},
		"throttle_policy": gin.H{
			"window_minutes": loginThrottleWindow / time.Minute,
			"ip_limit":       loginThrottleIPLimit,
			"account_limit":  loginThrottleAccountLimit,
		},
	})
}

// GetCurrentAdmin 获取当前管理员信息
func (h *AdminHandler) GetCurrentAdmin(c *gin.Context) {
	adminID, exists := c.Get("admin_id")
	if !exists {
		response.Error(c, http.StatusUnauthorized, "未登录")
		return
	}

	var admin models.Admin
	if err := h.db.First(&admin, adminID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "管理员不存在")
		return
	}
	response.Success(c, admin)
}

// UpdatePassword 修改密码
func (h *AdminHandler) UpdatePassword(c *gin.Context) {
	adminID, _ := c.Get("admin_id")

	var req struct {
		OldPassword string `json:"old_password" binding:"required"`
		NewPassword string `json:"new_password" binding:"required,min=6"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	var admin models.Admin
	if err := h.db.First(&admin, adminID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "管理员不存在")
		return
	}

	// 验证旧密码
	if !admin.CheckPassword(req.OldPassword) {
		response.Error(c, http.StatusBadRequest, "原密码错误")
		return
	}

	// 设置新密码
	if err := admin.SetPassword(req.NewPassword); err != nil {
		response.Error(c, http.StatusInternalServerError, "密码加密失败")
		return
	}
	if err := h.db.Save(&admin).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "保存失败")
		return
	}
	response.Success(c, nil)
}

// ListAdmins 获取管理员列表（仅超级管理员）
func (h *AdminHandler) ListAdmins(c *gin.Context) {
	var admins []models.Admin
	if err := h.db.Find(&admins).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}
	response.Success(c, admins)
}

// CreateAdmin 创建管理员（仅超级管理员）
func (h *AdminHandler) CreateAdmin(c *gin.Context) {
	var req struct {
		Username string `json:"username" binding:"required"`
		Password string `json:"password" binding:"required,min=6"`
		Nickname string `json:"nickname" binding:"required"`
		Email    string `json:"email" binding:"omitempty,email"`
		Role     string `json:"role" binding:"required,oneof=admin operator demo_admin"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	// 检查用户名是否存在
	var count int64
	h.db.Model(&models.Admin{}).Where("username = ?", req.Username).Count(&count)
	if count > 0 {
		response.Error(c, http.StatusBadRequest, "用户名已存在")
		return
	}
	admin := models.Admin{
		Username: req.Username,
		Nickname: req.Nickname,
		Email:    req.Email,
		Role:     req.Role,
		Status:   1,
	}
	if err := admin.SetPassword(req.Password); err != nil {
		response.Error(c, http.StatusInternalServerError, "密码加密失败")
		return
	}
	query := h.db
	if strings.TrimSpace(admin.Email) == "" {
		query = query.Omit("Email")
	}
	if err := query.Create(&admin).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "创建失败")
		return
	}
	response.Success(c, admin)
}

// DeleteAdmin 删除管理员（仅超级管理员）
func (h *AdminHandler) DeleteAdmin(c *gin.Context) {
	adminID := c.Param("id")

	var admin models.Admin
	if err := h.db.First(&admin, adminID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "管理员不存在")
		return
	}
	if admin.Role == "super_admin" {
		response.Error(c, http.StatusForbidden, "不能删除超级管理员")
		return
	}
	if err := h.db.Delete(&admin).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "删除失败")
		return
	}
	response.Success(c, nil)
}

// logLoginAttempt 记录登录日志
func (h *AdminHandler) logLoginAttempt(adminID uint64, username, ip, userAgent string, status int8, failureReason string, throttleApplied bool) {
	log := models.AdminLoginLog{
		AdminID:         adminID,
		Username:        strings.TrimSpace(username),
		IP:              ip,
		UserAgent:       userAgent,
		Status:          status,
		FailureReason:   failureReason,
		ThrottleApplied: throttleApplied,
		CreatedAt:       time.Now(),
	}
	h.db.Create(&log)
}
