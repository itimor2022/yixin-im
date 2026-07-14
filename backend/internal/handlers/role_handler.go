package handlers

import (
	"net/http"
	"regexp"
	"strings"
	"time"

	"gaoranim/internal/models"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// RoleHandler 后台"角色管理"页面的 CRUD 接口。
// 前端在 /admin/src/views/system/roles/index.vue 消费，仅 super_admin 可访问。
type RoleHandler struct {
	db *gorm.DB
}

func NewRoleHandler(db *gorm.DB) *RoleHandler {
	return &RoleHandler{db: db}
}

// roleKeyRegex 角色 key 命名约束：小写字母开头 + [a-z0-9_]，长度 2~30
var roleKeyRegex = regexp.MustCompile(`^[a-z][a-z0-9_]{1,29}$`)

// RoleDTO 返回给前端的角色对象——附带引用统计，方便前端展示 "N 个管理员 / N 项菜单"。
type RoleDTO struct {
	models.Role
	AdminCount int64 `json:"admin_count"`
	MenuCount  int   `json:"menu_count"`
}

// ListRoles 列出所有角色（内置排前，普通角色按 ID 递增）。
func (h *RoleHandler) ListRoles(c *gin.Context) {
	var roles []models.Role
	if err := h.db.Order("is_built_in DESC, id ASC").Find(&roles).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}

	result := make([]RoleDTO, 0, len(roles))
	for _, r := range roles {
		var adminCount int64
		h.db.Model(&models.Admin{}).Where("role = ?", r.Key).Count(&adminCount)

		menuCount := 0
		var rm models.RoleMenu
		if err := h.db.Where("role = ?", r.Key).First(&rm).Error; err == nil {
			menuCount = len(splitMenuKeys(rm.MenuKeys))
		}

		result = append(result, RoleDTO{
			Role:       r,
			AdminCount: adminCount,
			MenuCount:  menuCount,
		})
	}
	response.Success(c, result)
}

// GetRoleAdmins 拉取某角色下的管理员列表（前端在角色详情弹窗使用）。
func (h *RoleHandler) GetRoleAdmins(c *gin.Context) {
	key := c.Param("key")
	var admins []models.Admin
	if err := h.db.Where("role = ?", key).Order("id ASC").Find(&admins).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}
	response.Success(c, admins)
}

// CreateRole 新增自定义角色。
// - 禁止使用 super_admin 作为 Key（内置保留）；
// - 权限码仅允许 R_ADMIN / R_DEMO——R_SUPER 由内置 super_admin 独占。
func (h *RoleHandler) CreateRole(c *gin.Context) {
	var req struct {
		Key         string `json:"key" binding:"required"`
		Name        string `json:"name" binding:"required"`
		Description string `json:"description"`
		Code        string `json:"code" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	req.Key = strings.TrimSpace(strings.ToLower(req.Key))
	req.Name = strings.TrimSpace(req.Name)
	req.Code = strings.TrimSpace(strings.ToUpper(req.Code))

	if !roleKeyRegex.MatchString(req.Key) {
		response.Error(c, http.StatusBadRequest, "角色标识须以字母开头，只能包含小写字母、数字、下划线（2-30 位）")
		return
	}
	if req.Code != models.RoleCodeAdmin && req.Code != models.RoleCodeDemo {
		response.Error(c, http.StatusBadRequest, "权限范围仅支持 R_ADMIN / R_DEMO")
		return
	}
	if req.Key == "super_admin" {
		response.Error(c, http.StatusBadRequest, "该角色标识已被系统保留")
		return
	}

	var count int64
	h.db.Model(&models.Role{}).Where("`key` = ?", req.Key).Count(&count)
	if count > 0 {
		response.Error(c, http.StatusBadRequest, "角色标识已存在")
		return
	}

	now := time.Now()
	role := models.Role{
		Key:         req.Key,
		Name:        req.Name,
		Description: req.Description,
		Code:        req.Code,
		IsBuiltIn:   false,
		CreatedAt:   now,
		UpdatedAt:   now,
	}
	if err := h.db.Create(&role).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "创建失败")
		return
	}
	response.Success(c, role)
}

// UpdateRole 编辑角色。
// - 内置角色只允许改 Name / Description（Key、Code、IsBuiltIn 均不可变）；
// - 自定义角色可以改 Name / Description / Code，但不允许改 Key（Key 会被写到 admins.role，动了会孤立数据）。
func (h *RoleHandler) UpdateRole(c *gin.Context) {
	id := c.Param("id")

	var role models.Role
	if err := h.db.First(&role, id).Error; err != nil {
		response.Error(c, http.StatusNotFound, "角色不存在")
		return
	}

	var req struct {
		Name        *string `json:"name"`
		Description *string `json:"description"`
		Code        *string `json:"code"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	updates := map[string]interface{}{}
	if req.Name != nil {
		name := strings.TrimSpace(*req.Name)
		if name == "" {
			response.Error(c, http.StatusBadRequest, "角色名称不能为空")
			return
		}
		updates["name"] = name
	}
	if req.Description != nil {
		updates["description"] = strings.TrimSpace(*req.Description)
	}
	if req.Code != nil {
		if role.IsBuiltIn {
			response.Error(c, http.StatusForbidden, "内置角色不能修改权限范围")
			return
		}
		code := strings.ToUpper(strings.TrimSpace(*req.Code))
		if code != models.RoleCodeAdmin && code != models.RoleCodeDemo {
			response.Error(c, http.StatusBadRequest, "权限范围仅支持 R_ADMIN / R_DEMO")
			return
		}
		updates["code"] = code
	}
	if len(updates) == 0 {
		response.Success(c, role)
		return
	}
	updates["updated_at"] = time.Now()

	if err := h.db.Model(&role).Updates(updates).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "更新失败")
		return
	}
	h.db.First(&role, id)
	response.Success(c, role)
}

// DeleteRole 删除角色。
// - 内置角色一律禁止删除；
// - 存在管理员仍绑定该角色时禁止删除（前端需先改绑）；
// - 顺带清理 role_menus 中残留的菜单权限行。
func (h *RoleHandler) DeleteRole(c *gin.Context) {
	id := c.Param("id")

	var role models.Role
	if err := h.db.First(&role, id).Error; err != nil {
		response.Error(c, http.StatusNotFound, "角色不存在")
		return
	}
	if role.IsBuiltIn {
		response.Error(c, http.StatusForbidden, "内置角色不允许删除")
		return
	}

	var adminCount int64
	h.db.Model(&models.Admin{}).Where("role = ?", role.Key).Count(&adminCount)
	if adminCount > 0 {
		response.Error(c, http.StatusBadRequest, "仍有管理员使用该角色，请先解除绑定")
		return
	}

	tx := h.db.Begin()
	if err := tx.Delete(&role).Error; err != nil {
		tx.Rollback()
		response.Error(c, http.StatusInternalServerError, "删除失败")
		return
	}
	tx.Where("role = ?", role.Key).Delete(&models.RoleMenu{})
	tx.Commit()

	response.Success(c, nil)
}

// GetRoleCodeByKey 供其他 handler / 中间件查询角色权限码。
// - 内置 super_admin 永远返回 R_SUPER，即使 roles 表被误删也不影响；
// - 未找到 → 保守返回 R_ADMIN，避免历史管理员因数据异常瞬间失去写权限被锁死。
func GetRoleCodeByKey(db *gorm.DB, key string) string {
	if key == "super_admin" {
		return models.RoleCodeSuper
	}
	if db == nil {
		return models.RoleCodeAdmin
	}
	var role models.Role
	if err := db.Select("code").Where("`key` = ?", key).First(&role).Error; err != nil {
		return models.RoleCodeAdmin
	}
	if role.Code == "" {
		return models.RoleCodeAdmin
	}
	return role.Code
}
