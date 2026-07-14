package handlers

import (
	"context"
	"fmt"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"

	"gaoranim/internal/cache"
	"gaoranim/internal/models"
	"gaoranim/pkg/jwt"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// emailRegex 邮箱格式的轻量校验——只覆盖常见形态，避免绑定 `binding:"email"`
// 时空字符串 / 指针字段的兼容问题。
var emailRegex = regexp.MustCompile(`^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$`)

// normalizeWhitelist 规范化 IP 白名单：按 换行/逗号/空白 拆行，去空后以换行拼接。
// 存储层保持"每行一条 IP"的形态，方便前端 textarea 编辑。
func normalizeWhitelist(raw string) string {
	items := strings.FieldsFunc(raw, func(r rune) bool {
		return r == '\n' || r == '\r' || r == ',' || r == ' ' || r == '\t'
	})
	cleaned := make([]string, 0, len(items))
	for _, ip := range items {
		ip = strings.TrimSpace(ip)
		if ip != "" {
			cleaned = append(cleaned, ip)
		}
	}
	return strings.Join(cleaned, "\n")
}

type AdminHandler struct {
	db    *gorm.DB
	cache *cache.Cache // nil 时降级为仅 DB 校验，登录锁定/限流功能失效
}

func NewAdminHandler(db *gorm.DB, ca *cache.Cache) *AdminHandler {
	return &AdminHandler{db: db, cache: ca}
}

// admin 登录防爆破常量（写死，不需要暴露给配置）：
//   - 单 IP 每分钟最多 10 次登录尝试（无论用户名）
//   - 单账号连续 5 次失败即锁定 15 分钟
//   - 锁定期间提示"账号已被锁定"，但不告知剩余时间，防止 timing / 状态泄露
const (
	adminLoginIPLimit       = 10
	adminLoginIPWindow      = time.Minute
	adminLoginFailThreshold = 5
	adminLoginLockDuration  = 15 * time.Minute
	adminLoginFailWindow    = 30 * time.Minute
	adminLoginFailKeyPrefix = "admin:login:fail:"
	adminLoginLockKeyPrefix = "admin:login:lock:"
)

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
//
// 防爆破策略（后台登录必须有的三重防线）：
//  1. IP 级滑窗限流：单 IP 每 60 秒最多 10 次尝试，任何用户名都算，用来挡自动化脚本；
//  2. 账号级失败计数：某账号 30 分钟内累计失败 >= 5 次 → 锁定 15 分钟；
//  3. 统一错误信息：用户名不存在 / 密码错误 / 账号禁用 / 账号锁定，全部返回同样的
//     "用户名或密码错误"，避免根据错误提示枚举账号。
//
// Redis 不可用时降级为"只做 DB 密码校验"，登录仍然可用，但失去限流/锁定能力 ——
// 这是可接受的降级，因为 admin 账号数量少、通常有独立堡垒机保护。
func (h *AdminHandler) Login(c *gin.Context) {
	var req AdminLoginRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	ctx := c.Request.Context()
	clientIP := c.ClientIP()

	// ── 防线 1：IP 级限流 ────────────────────────────────────────────
	if h.cache != nil {
		ipKey := "admin:login:ip:" + clientIP
		if ok, err := h.cache.RateLimit(ctx, ipKey, adminLoginIPLimit, adminLoginIPWindow); err == nil && !ok {
			response.Error(c, http.StatusTooManyRequests, "请求过于频繁，请稍后再试")
			return
		}
	}

	// ── 防线 2：账号级锁定检查（未查 DB 前先看 Redis，省一次查询）─────────
	if h.cache != nil {
		lockKey := adminLoginLockKeyPrefix + req.Username
		if v, err := h.cache.GetRaw(ctx, lockKey); err == nil && v != "" {
			// 锁定期内一律拒绝，且回统一错误信息，不暴露"账号存在"
			response.Error(c, http.StatusUnauthorized, "用户名或密码错误")
			return
		}
	}

	// 查询管理员
	var admin models.Admin
	if err := h.db.Where("username = ?", req.Username).First(&admin).Error; err != nil {
		h.logLogin(0, clientIP, c.Request.UserAgent(), 0)
		// 注意：不区分"用户不存在"和"密码错误"
		response.Error(c, http.StatusUnauthorized, "用户名或密码错误")
		return
	}

	// 状态非启用同样返回通用错误（防枚举）
	if admin.Status != 1 {
		h.logLogin(admin.ID, clientIP, c.Request.UserAgent(), 0)
		response.Error(c, http.StatusUnauthorized, "用户名或密码错误")
		return
	}

	// 验证密码
	if !admin.CheckPassword(req.Password) {
		h.logLogin(admin.ID, clientIP, c.Request.UserAgent(), 0)
		h.recordAdminLoginFailure(ctx, req.Username)
		response.Error(c, http.StatusUnauthorized, "用户名或密码错误")
		return
	}

	// 登录成功，清掉失败计数
	if h.cache != nil {
		_ = h.cache.Delete(ctx,
			adminLoginFailKeyPrefix+admin.Username,
			adminLoginLockKeyPrefix+admin.Username,
		)
	}

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
		"last_login_ip": clientIP,
	})

	// 记录登录日志
	h.logLogin(admin.ID, clientIP, c.Request.UserAgent(), 1)

	response.Success(c, AdminLoginResponse{
		Token: token,
		Admin: &admin,
	})
}

// recordAdminLoginFailure 累计账号失败次数，达到阈值即锁定 15 分钟。
// 用简单的 counter + expire 语义（GetRaw → +1 → SetRaw with TTL），比滑窗更省资源。
// Redis 不可用时静默降级，不影响正常登录。
func (h *AdminHandler) recordAdminLoginFailure(ctx context.Context, username string) {
	if h.cache == nil || username == "" {
		return
	}
	failKey := adminLoginFailKeyPrefix + username
	raw, _ := h.cache.GetRaw(ctx, failKey)
	count := 0
	if raw != "" {
		if n, err := strconv.Atoi(raw); err == nil {
			count = n
		}
	}
	count++
	_ = h.cache.SetRaw(ctx, failKey, fmt.Sprintf("%d", count), int(adminLoginFailWindow.Seconds()))
	if count >= adminLoginFailThreshold {
		_ = h.cache.SetRaw(ctx, adminLoginLockKeyPrefix+username, "1", int(adminLoginLockDuration.Seconds()))
	}
}

// GetCurrentAdmin 获取当前管理员信息，附带前端菜单过滤所需的两个字段：
//   - role_code  ：R_SUPER / R_ADMIN / R_DEMO，前端据此禁用写操作
//   - menu_keys  ：允许访问的菜单 name 列表；nil 表示不限制（super_admin/admin）
//
// 之所以在 me 接口一次性返给前端，是为了避免登录后前端还要再发一次
// /admin/roles + /admin/role-menus 才能渲染菜单——白屏时间会显著变长。
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

	menuKeys := GetRoleMenuKeys(h.db, admin.Role)
	roleCode := GetRoleCodeByKey(h.db, admin.Role)

	response.Success(c, gin.H{
		"id":            admin.ID,
		"username":      admin.Username,
		"nickname":      admin.Nickname,
		"email":         admin.Email,
		"avatar":        admin.Avatar,
		"role":          admin.Role,
		"role_code":     roleCode,
		"status":        admin.Status,
		"whitelist_ips": admin.WhitelistIPs,
		"last_login_at": admin.LastLoginAt,
		"last_login_ip": admin.LastLoginIP,
		"created_at":    admin.CreatedAt,
		"updated_at":    admin.UpdatedAt,
		"menu_keys":     menuKeys, // nil = 不限制
	})
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
	if err := h.db.Order("id ASC").Find(&admins).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	response.Success(c, admins)
}

// CreateAdmin 创建管理员（仅超级管理员）
//
// 角色校验改为动态查 roles 表：不再硬编码 oneof=admin/operator/demo_admin，
// 这样"角色管理"页面新增的自定义角色也能被这里接受。同时 super_admin 保留
// 为内置账号，禁止通过接口再建一个。
func (h *AdminHandler) CreateAdmin(c *gin.Context) {
	// 邮箱不用 binding:"email"——空字符串 vs 空指针的绑定语义太脏，手动校验更稳。
	var req struct {
		Username     string `json:"username" binding:"required"`
		Password     string `json:"password" binding:"required,min=6"`
		Nickname     string `json:"nickname" binding:"required"`
		Email        string `json:"email"`
		Role         string `json:"role" binding:"required"`
		WhitelistIPs string `json:"whitelist_ips"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	if req.Role == "super_admin" {
		response.Error(c, http.StatusBadRequest, "不能创建超级管理员")
		return
	}
	var roleCount int64
	h.db.Model(&models.Role{}).Where("`key` = ?", req.Role).Count(&roleCount)
	if roleCount == 0 {
		response.Error(c, http.StatusBadRequest, "角色不存在")
		return
	}

	email := strings.TrimSpace(req.Email)
	if email != "" && !emailRegex.MatchString(email) {
		response.Error(c, http.StatusBadRequest, "邮箱格式不正确")
		return
	}

	var count int64
	h.db.Model(&models.Admin{}).Where("username = ?", req.Username).Count(&count)
	if count > 0 {
		response.Error(c, http.StatusBadRequest, "用户名已存在")
		return
	}

	admin := models.Admin{
		Username:     req.Username,
		Nickname:     req.Nickname,
		Email:        email,
		Role:         req.Role,
		Status:       1,
		WhitelistIPs: normalizeWhitelist(req.WhitelistIPs),
	}

	if err := admin.SetPassword(req.Password); err != nil {
		response.Error(c, http.StatusInternalServerError, "密码加密失败")
		return
	}

	// 邮箱为空时 Omit，防止空字符串撞唯一索引（历史上被这个坑过一次）
	tx := h.db
	if email == "" {
		tx = tx.Omit("Email")
	}
	if err := tx.Create(&admin).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "创建失败")
		return
	}

	response.Success(c, admin)
}

// UpdateAdmin 编辑管理员（仅超级管理员）
//
// 允许修改：nickname / email / role / status / password / whitelist_ips。
// 说明：
//   - 不允许改 username（写死 admins.username 唯一索引）；
//   - super_admin 的 role / status 不允许修改，也不允许把别人升成 super_admin；
//   - 邮箱为空 → 写 NULL，避免多个空字符串撞唯一索引；
//   - 密码字段：不传 或 空字符串 都视作"不改密码"；传了则要 >= 6 位。
func (h *AdminHandler) UpdateAdmin(c *gin.Context) {
	adminID := c.Param("id")

	var admin models.Admin
	if err := h.db.First(&admin, adminID).Error; err != nil {
		response.Error(c, http.StatusNotFound, "管理员不存在")
		return
	}

	// 注意：邮箱字段不能用 binding:"omitempty,email"
	// 因为非 nil 但指向空字符串的指针 不 会被 omitempty 跳过，会导致"清空邮箱"操作 400。
	var req struct {
		Nickname     *string `json:"nickname"`
		Email        *string `json:"email"`
		Role         *string `json:"role"`
		Status       *int8   `json:"status" binding:"omitempty,oneof=0 1"`
		Password     *string `json:"password"`
		WhitelistIPs *string `json:"whitelist_ips"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	updates := make(map[string]interface{})
	if req.Nickname != nil {
		updates["nickname"] = strings.TrimSpace(*req.Nickname)
	}
	if req.Email != nil {
		email := strings.TrimSpace(*req.Email)
		if email == "" {
			updates["email"] = nil
		} else {
			if !emailRegex.MatchString(email) {
				response.Error(c, http.StatusBadRequest, "邮箱格式不正确")
				return
			}
			updates["email"] = email
		}
	}
	if req.Role != nil {
		if admin.Role == "super_admin" {
			response.Error(c, http.StatusForbidden, "不能修改超级管理员的角色")
			return
		}
		if *req.Role == "super_admin" {
			response.Error(c, http.StatusForbidden, "不能设置为超级管理员")
			return
		}
		var roleCount int64
		h.db.Model(&models.Role{}).Where("`key` = ?", *req.Role).Count(&roleCount)
		if roleCount == 0 {
			response.Error(c, http.StatusBadRequest, "角色不存在")
			return
		}
		updates["role"] = *req.Role
	}
	if req.Status != nil {
		if admin.Role == "super_admin" {
			response.Error(c, http.StatusForbidden, "不能修改超级管理员的状态")
			return
		}
		updates["status"] = *req.Status
	}
	if req.WhitelistIPs != nil {
		updates["whitelist_ips"] = normalizeWhitelist(*req.WhitelistIPs)
	}

	if len(updates) > 0 {
		if err := h.db.Model(&admin).Updates(updates).Error; err != nil {
			response.Error(c, http.StatusInternalServerError, "更新失败")
			return
		}
	}

	// 密码独立更新（需要 bcrypt 加密，且空字符串明确表示不改）
	if req.Password != nil && *req.Password != "" {
		if len(*req.Password) < 6 {
			response.Error(c, http.StatusBadRequest, "密码长度不能少于6位")
			return
		}
		if err := admin.SetPassword(*req.Password); err != nil {
			response.Error(c, http.StatusInternalServerError, "密码加密失败")
			return
		}
		if err := h.db.Model(&admin).Update("password", admin.Password).Error; err != nil {
			response.Error(c, http.StatusInternalServerError, "密码更新失败")
			return
		}
	}

	h.db.First(&admin, adminID)
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

// logLogin 记录登录日志
func (h *AdminHandler) logLogin(adminID uint64, ip, userAgent string, status int8) {
	log := models.AdminLoginLog{
		AdminID:   adminID,
		IP:        ip,
		UserAgent: userAgent,
		Status:    status,
		CreatedAt: time.Now(),
	}
	h.db.Create(&log)
}
