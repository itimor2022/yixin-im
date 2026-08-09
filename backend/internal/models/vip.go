// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import (
	"gorm.io/gorm"
	"time"
)

const (
	VipLevelFree = 0
	VipLevelVIP  = 1
	VipLevelSVIP = 2
)

const (
	VipMembershipStatusActive   = "active"
	VipMembershipStatusExpired  = "expired"
	VipMembershipStatusCanceled = "canceled"
	VipMembershipStatusFrozen   = "frozen"
)

const (
	VipOrderStatusPending  = "pending"
	VipOrderStatusPaid     = "paid"
	VipOrderStatusCanceled = "canceled"
	VipOrderStatusFailed   = "failed"
	VipOrderStatusRefunded = "refunded"
)

const (
	VipPayMethodWallet = "wallet"
	VipPayMethodManual = "manual"
)

// VipPlan
type VipPlan struct {
	ID            uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	Code          string         `gorm:"type:varchar(32);uniqueIndex;not null" json:"code"`
	Name          string         `gorm:"type:varchar(50);not null" json:"name"`
	Level         int8           `gorm:"type:tinyint;not null;index" json:"level"`
	DurationDays  int            `gorm:"type:int;not null;default:30" json:"duration_days"`
	Price         float64        `gorm:"type:decimal(12,2);not null;default:0" json:"price"`
	OriginalPrice float64        `gorm:"type:decimal(12,2);not null;default:0" json:"original_price"`
	BenefitsJSON  string         `gorm:"type:longtext" json:"benefits_json"`
	Description   string         `gorm:"type:varchar(500)" json:"description"`
	Sort          int            `gorm:"type:int;default:0;index" json:"sort"`
	Enabled       bool           `gorm:"type:tinyint(1);not null;default:1;index" json:"enabled"`
	CreatedAt     time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt     time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`
}

func (VipPlan) TableName() string {
	return "vip_plans"
}

// UserVipMembership
type UserVipMembership struct {
	ID         uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID     uint64     `gorm:"uniqueIndex;not null" json:"user_id"`
	PlanID     *uint64    `gorm:"index" json:"plan_id"`
	Level      int8       `gorm:"type:tinyint;not null;default:0;index" json:"level"`
	Source     string     `gorm:"type:varchar(20);not null;default:'manual'" json:"source"`
	Status     string     `gorm:"type:varchar(20);not null;default:'active';index" json:"status"`
	StartedAt  time.Time  `gorm:"type:datetime;not null" json:"started_at"`
	ExpiredAt  time.Time  `gorm:"type:datetime;not null;index" json:"expired_at"`
	CanceledAt *time.Time `gorm:"type:datetime" json:"canceled_at"`
	Remark     string     `gorm:"type:varchar(500)" json:"remark"`
	CreatedAt  time.Time  `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt  time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (UserVipMembership) TableName() string {
	return "user_vip_memberships"
}

// VipOrder
type VipOrder struct {
	ID            uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	OrderNo       string     `gorm:"type:varchar(64);uniqueIndex;not null" json:"order_no"`
	UserID        uint64     `gorm:"index;not null" json:"user_id"`
	PlanID        uint64     `gorm:"index;not null" json:"plan_id"`
	Amount        float64    `gorm:"type:decimal(12,2);not null;default:0" json:"amount"`
	PayMethod     string     `gorm:"type:varchar(20);not null;default:'wallet';index" json:"pay_method"`
	Status        string     `gorm:"type:varchar(20);not null;default:'pending';index" json:"status"`
	PaidAt        *time.Time `gorm:"type:datetime" json:"paid_at"`
	CanceledAt    *time.Time `gorm:"type:datetime" json:"canceled_at"`
	TransactionID string     `gorm:"type:varchar(64);index" json:"transaction_id"`
	Remark        string     `gorm:"type:varchar(500)" json:"remark"`
	CreatedAt     time.Time  `gorm:"type:datetime;not null;index" json:"created_at"`
	UpdatedAt     time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (VipOrder) TableName() string {
	return "vip_orders"
}
