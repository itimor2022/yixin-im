package handlers

import (
	"net/http"
	"strings"
	"time"

	"gaoranim/internal/models"
	"gaoranim/pkg/response"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

// RoleMenuHandler 后台"角色权限"页面：控制每个角色可访问的菜单白名单。
// 前端 /admin/src/views/system/role-permissions/index.vue 消费；仅 super_admin 可访问。
type RoleMenuHandler struct {
	db *gorm.DB
}

func NewRoleMenuHandler(db *gorm.DB) *RoleMenuHandler {
	return &RoleMenuHandler{db: db}
}

// reservedFullAccessRoles 内置全权限角色——不需要（也不允许）在本页面配置菜单：
//   - super_admin：内置超级管理员，享有一切；
//   - admin      ：内置管理员，作为"默认可写角色"始终开放全部菜单，防止误配把整个后台锁死。
var reservedFullAccessRoles = map[string]struct{}{
	"super_admin": {},
	"admin":       {},
}

// isManagedRole 判断某个 role 是否可以在本页面配置菜单：
// 必须存在于 roles 表 + 不在保留全权列表内。
func isManagedRole(db *gorm.DB, role string) bool {
	if _, reserved := reservedFullAccessRoles[role]; reserved {
		return false
	}
	var count int64
	db.Model(&models.Role{}).Where("`key` = ?", role).Count(&count)
	return count > 0
}

// splitMenuKeys 将存储字符串拆成菜单 key slice——按 换行 / 逗号 / 空白 分割，去空去重。
func splitMenuKeys(raw string) []string {
	items := strings.FieldsFunc(raw, func(r rune) bool {
		return r == '\n' || r == '\r' || r == ',' || r == ' ' || r == '\t'
	})
	seen := make(map[string]struct{}, len(items))
	out := make([]string, 0, len(items))
	for _, it := range items {
		it = strings.TrimSpace(it)
		if it == "" {
			continue
		}
		if _, ok := seen[it]; ok {
			continue
		}
		seen[it] = struct{}{}
		out = append(out, it)
	}
	return out
}

// joinMenuKeys 用换行拼接菜单 key（存储表现形式）。
func joinMenuKeys(keys []string) string {
	return strings.Join(keys, "\n")
}

// GetRoleMenuKeys 供其他 handler / 前端 /admin/me 查询指定角色允许访问的菜单：
//   - super_admin / admin 返回 nil，前端把 nil 视作"不限制"；
//   - 已知角色但未配置菜单 → 返回 []（空列表，明确无任何菜单）；
//   - 未知角色（数据异常）→ 返回 nil，保守放行避免自锁。
func GetRoleMenuKeys(db *gorm.DB, role string) []string {
	if _, reserved := reservedFullAccessRoles[role]; reserved {
		return nil
	}
	if db == nil {
		return nil
	}
	if !isManagedRole(db, role) {
		return nil
	}
	var rm models.RoleMenu
	if err := db.Where("role = ?", role).First(&rm).Error; err != nil {
		return []string{}
	}
	return splitMenuKeys(rm.MenuKeys)
}

// RoleMenuItem 单条角色-菜单响应
type RoleMenuItem struct {
	Role      string   `json:"role"`
	MenuKeys  []string `json:"menu_keys"`
	UpdatedAt string   `json:"updated_at"`
}

// ListRoleMenus 列出所有可配置角色的菜单快照（super_admin/admin 会被过滤掉）。
func (h *RoleMenuHandler) ListRoleMenus(c *gin.Context) {
	var roles []models.Role
	if err := h.db.Order("is_built_in DESC, id ASC").Find(&roles).Error; err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	}
	var menuList []models.RoleMenu
	h.db.Find(&menuList)
	menuMap := make(map[string]models.RoleMenu, len(menuList))
	for _, item := range menuList {
		menuMap[item.Role] = item
	}

	result := make([]RoleMenuItem, 0, len(roles))
	for _, r := range roles {
		if _, reserved := reservedFullAccessRoles[r.Key]; reserved {
			continue
		}
		item := RoleMenuItem{
			Role:     r.Key,
			MenuKeys: []string{},
		}
		if rm, ok := menuMap[r.Key]; ok {
			item.MenuKeys = splitMenuKeys(rm.MenuKeys)
			item.UpdatedAt = rm.UpdatedAt.Format(time.RFC3339)
		}
		result = append(result, item)
	}
	response.Success(c, result)
}

// UpdateRoleMenu 覆盖指定角色的菜单白名单——前端每次全量提交。
func (h *RoleMenuHandler) UpdateRoleMenu(c *gin.Context) {
	role := c.Param("role")
	if _, reserved := reservedFullAccessRoles[role]; reserved {
		response.Error(c, http.StatusBadRequest, "该角色拥有全部菜单权限，无需配置")
		return
	}
	if !isManagedRole(h.db, role) {
		response.Error(c, http.StatusBadRequest, "角色不存在")
		return
	}

	var req struct {
		MenuKeys []string `json:"menu_keys"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		response.Error(c, http.StatusBadRequest, "参数错误")
		return
	}

	// 去空 & 去重（不信任前端顺序 / 重复）
	keys := make([]string, 0, len(req.MenuKeys))
	seen := make(map[string]struct{}, len(req.MenuKeys))
	for _, k := range req.MenuKeys {
		k = strings.TrimSpace(k)
		if k == "" {
			continue
		}
		if _, ok := seen[k]; ok {
			continue
		}
		seen[k] = struct{}{}
		keys = append(keys, k)
	}

	now := time.Now()
	var rm models.RoleMenu
	err := h.db.Where("role = ?", role).First(&rm).Error
	if err == gorm.ErrRecordNotFound {
		rm = models.RoleMenu{
			Role:      role,
			MenuKeys:  joinMenuKeys(keys),
			CreatedAt: now,
			UpdatedAt: now,
		}
		if err := h.db.Create(&rm).Error; err != nil {
			response.Error(c, http.StatusInternalServerError, "保存失败")
			return
		}
	} else if err != nil {
		response.Error(c, http.StatusInternalServerError, "查询失败")
		return
	} else {
		rm.MenuKeys = joinMenuKeys(keys)
		rm.UpdatedAt = now
		if err := h.db.Save(&rm).Error; err != nil {
			response.Error(c, http.StatusInternalServerError, "保存失败")
			return
		}
	}

	response.Success(c, RoleMenuItem{
		Role:      role,
		MenuKeys:  keys,
		UpdatedAt: rm.UpdatedAt.Format(time.RFC3339),
	})
}
