package handlers

import (
	"net/http"
	"time"

	"gaoranim/internal/models"
	"gaoranim/pkg/jwt"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

type AdminHandler struct {
	db *gorm.DB
}

func NewAdminHandler(db *gorm.DB) *AdminHandler {
	return &AdminHandler{db: db}
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
	var admin models.Admin
	if err := h.db.Where("username = ?", req.Username).First(&admin).Error; err != nil {
		// 记录失败日志
		h.logLogin(0, c.ClientIP(), c.Request.UserAgent(), 0)
		response.Error(c, http.StatusUnauthorized, "用户名或密码错误")
		return
	}

	// 检查状态
	if admin.Status != 1 {
		response.Error(c, http.StatusForbidden, "账号已被禁用")
		return
	}

	// 验证密码
	if !admin.CheckPassword(req.Password) {
		h.logLogin(admin.ID, c.ClientIP(), c.Request.UserAgent(), 0)
		response.Error(c, http.StatusUnauthorized, "用户名或密码错误")
		return
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
		"last_login_ip": c.ClientIP(),
	})

	// 记录登录日志
	h.logLogin(admin.ID, c.ClientIP(), c.Request.UserAgent(), 1)

	response.Success(c, AdminLoginResponse{
		Token: token,
		Admin: &admin,
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
		Email    string `json:"email" binding:"email"`
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

	if err := h.db.Create(&admin).Error; err != nil {
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
