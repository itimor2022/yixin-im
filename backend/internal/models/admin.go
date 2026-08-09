// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import (
	"golang.org/x/crypto/bcrypt"
	"gorm.io/gorm"
	"time"
)

// Admin 管理员表
type Admin struct {
	ID          uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	Username    string         `gorm:"type:varchar(50);uniqueIndex;not null" json:"username"`
	Password    string         `gorm:"type:varchar(100);not null" json:"-"`
	Nickname    string         `gorm:"type:varchar(100);not null" json:"nickname"`
	Email       string         `gorm:"type:varchar(100);uniqueIndex" json:"email"`
	Avatar      string         `gorm:"type:varchar(500)" json:"avatar"`
	Role        string         `gorm:"type:varchar(20);not null;default:'admin'" json:"role"` // super_admin/admin/operator/demo_admin
	Status      int8           `gorm:"type:tinyint;default:1" json:"status"`                  // 1:正常 0:禁用
	LastLoginAt *time.Time     `gorm:"type:datetime" json:"last_login_at"`
	LastLoginIP string         `gorm:"type:varchar(50)" json:"last_login_ip"`
	CreatedAt   time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt   time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`
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

// AdminLoginLog 管理员登录日志
type AdminLoginLog struct {
	ID              uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	AdminID         uint64    `gorm:"index;not null" json:"admin_id"`
	Username        string    `gorm:"type:varchar(50);index" json:"username"`
	IP              string    `gorm:"type:varchar(50);index" json:"ip"`
	UserAgent       string    `gorm:"type:varchar(500)" json:"user_agent"`
	Status          int8      `gorm:"type:tinyint;default:1;index" json:"status"` // 1:成功 0:失败
	FailureReason   string    `gorm:"type:varchar(100)" json:"failure_reason"`
	ThrottleApplied bool      `gorm:"type:tinyint(1);not null;default:0" json:"throttle_applied"`
	CreatedAt       time.Time `gorm:"type:datetime;not null;index" json:"created_at"`
}

func (AdminLoginLog) TableName() string {
	return "admin_login_logs"
}
