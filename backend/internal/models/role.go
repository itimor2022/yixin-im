package models

import "time"

// Role 后台角色（供 admin 后台的"角色管理"页面维护）
//
// 字段说明：
//   - Key  ：角色唯一标识（存到 admins.role 列，例 super_admin/admin/operator/demo_admin）
//   - Code ：权限范围码——决定业务侧写保护逻辑
//       R_SUPER：超级管理员，拥有一切权限（仅内置 super_admin 使用）
//       R_ADMIN：普通管理员，可写；受 role_menus 的菜单白名单限制前端菜单展示
//       R_DEMO ：演示账号，一律只读；写接口在中间件层直接拒绝
//   - IsBuiltIn ：内置角色（super_admin/admin/operator/demo_admin），
//                 前端展示 "不可删除"、Key/Code 不允许修改
//
// 由 backend/cmd/server/main.go 的 initDefaultRoles() 在启动时自动种入。
// 不落 DeletedAt 软删除——删角色是低频操作，且需要先手动解绑 admins.role。
type Role struct {
	ID          uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	Key         string    `gorm:"type:varchar(30);uniqueIndex;not null" json:"key"`
	Name        string    `gorm:"type:varchar(50);not null" json:"name"`
	Description string    `gorm:"type:varchar(200)" json:"description"`
	Code        string    `gorm:"type:varchar(20);not null;default:'R_ADMIN'" json:"code"`
	IsBuiltIn   bool      `gorm:"default:false" json:"is_built_in"`
	CreatedAt   time.Time `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt   time.Time `gorm:"type:datetime;not null" json:"updated_at"`
}

func (Role) TableName() string {
	return "roles"
}

// 权限码常量
const (
	RoleCodeSuper = "R_SUPER"
	RoleCodeAdmin = "R_ADMIN"
	RoleCodeDemo  = "R_DEMO"
)

// BuiltInRoleSeed 内置角色元数据（用于 initDefaultRoles 种子）
type BuiltInRoleSeed struct {
	Key         string
	Name        string
	Description string
	Code        string
}

// BuiltInRoles 首次启动时自动写入 roles 表的 4 个内置角色。
// 已存在时按 Key 幂等——不覆盖运维已经手动改过的 Name/Description/Code。
var BuiltInRoles = []BuiltInRoleSeed{
	{Key: "super_admin", Name: "超级管理员", Description: "内置超级管理员，拥有全部权限", Code: RoleCodeSuper},
	{Key: "admin", Name: "管理员", Description: "系统管理员，拥有除超管专有能力外的所有菜单", Code: RoleCodeAdmin},
	{Key: "operator", Name: "运营", Description: "日常运营人员，可根据菜单权限限制访问范围", Code: RoleCodeAdmin},
	{Key: "demo_admin", Name: "演示账号", Description: "只读演示账号，不能进行任何写操作", Code: RoleCodeDemo},
}
