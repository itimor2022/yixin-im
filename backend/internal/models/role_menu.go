package models

import "time"

// RoleMenu 每个自定义/普通角色可访问的后台菜单白名单。
//
// 存储策略：
//   - 一个角色一行，MenuKeys 以换行分隔的菜单标识（对应前端路由 name）；
//   - super_admin / 内置 admin **不需要写入本表**——程序里直接放行所有菜单，
//     两者在 role_menu_handler 里被过滤掉；
//   - 未在 roles 表登记的历史角色 → 保守放行，避免自锁。
type RoleMenu struct {
	ID        uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	Role      string    `gorm:"type:varchar(30);uniqueIndex;not null" json:"role"`
	MenuKeys  string    `gorm:"type:text" json:"menu_keys"`
	UpdatedAt time.Time `gorm:"type:datetime;not null" json:"updated_at"`
	CreatedAt time.Time `gorm:"type:datetime;not null" json:"created_at"`
}

func (RoleMenu) TableName() string {
	return "role_menus"
}
