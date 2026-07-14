package models

import (
	"strings"
	"time"

	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
)

// SuperAdminUsername 内置超级管理员账号名——不受 IP 白名单限制，
// 也不允许被"角色管理"/"管理员管理"删除或降级。
const SuperAdminUsername = "admin"

// Admin 管理员表
//
// 白名单字段 WhitelistIPs：
//   - 存储时按换行 / 逗号 / 空白拆行，每行一个 IP；
//   - 为空或空白 → 视作不限制；
//   - 内置 super_admin (Username=="admin") 一律豁免；
//   - 中间件是否强制启用取决于 Admin 认证链的实现——目前后端已经
//     暴露了字段与后台管理 API，如需真正拦截，可在 middleware.AdminAuth 中
//     调用 admin.IsIPAllowed(c.ClientIP()) 后 return 404。
type Admin struct {
	ID           uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	Username     string         `gorm:"type:varchar(50);uniqueIndex;not null" json:"username"`
	Password     string         `gorm:"type:varchar(100);not null" json:"-"`
	Nickname     string         `gorm:"type:varchar(100);not null" json:"nickname"`
	Email        string         `gorm:"type:varchar(100);uniqueIndex" json:"email"`
	Avatar       string         `gorm:"type:varchar(500)" json:"avatar"`
	Role         string         `gorm:"type:varchar(20);not null;default:'admin'" json:"role"` // super_admin/admin/operator/demo_admin
	Status       int8           `gorm:"type:tinyint;default:1" json:"status"`                  // 1:正常 0:禁用
	WhitelistIPs string         `gorm:"type:text" json:"whitelist_ips"`                        // 登录 IP 白名单：换行分隔，为空则不限制
	LastLoginAt  *time.Time     `gorm:"type:datetime" json:"last_login_at"`
	LastLoginIP  string         `gorm:"type:varchar(50)" json:"last_login_ip"`
	CreatedAt    time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt    time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"-"`
}

func (Admin) TableName() string {
	return "admins"
}

// SetPassword 设置密码（使用bcrypt加密）
func (a *Admin) SetPassword(password string) error {
	hashedPassword, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	a.Password = string(hashedPassword)
	return nil
}

// CheckPassword 验证密码
func (a *Admin) CheckPassword(password string) bool {
	err := bcrypt.CompareHashAndPassword([]byte(a.Password), []byte(password))
	return err == nil
}

// IsIPAllowed 判断当前请求 IP 是否允许访问后台。
// 规则：内置 admin 账号不受限；WhitelistIPs 为空视为不限；否则要求 IP 精确匹配。
func (a *Admin) IsIPAllowed(clientIP string) bool {
	if a.Username == SuperAdminUsername {
		return true
	}
	list := strings.TrimSpace(a.WhitelistIPs)
	if list == "" {
		return true
	}
	items := strings.FieldsFunc(list, func(r rune) bool {
		return r == '\n' || r == '\r' || r == ',' || r == ' ' || r == '\t'
	})
	for _, ip := range items {
		if strings.TrimSpace(ip) == clientIP {
			return true
		}
	}
	return false
}

// AdminLoginLog 管理员登录日志
type AdminLoginLog struct {
	ID        uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	AdminID   uint64    `gorm:"index;not null" json:"admin_id"`
	IP        string    `gorm:"type:varchar(50)" json:"ip"`
	UserAgent string    `gorm:"type:varchar(500)" json:"user_agent"`
	Status    int8      `gorm:"type:tinyint;default:1" json:"status"` // 1:成功 0:失败
	CreatedAt time.Time `gorm:"type:datetime;not null" json:"created_at"`
}

func (AdminLoginLog) TableName() string {
	return "admin_login_logs"
}
