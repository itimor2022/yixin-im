package models

import (
	"time"

	"gorm.io/gorm"
)

type MembershipPlan struct {
	ID            uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	Name          string         `gorm:"type:varchar(100);not null" json:"name"`
	Slug          string         `gorm:"type:varchar(50);uniqueIndex;not null" json:"slug"`
	DurationDays  int            `gorm:"type:int;not null" json:"duration_days"`
	Price         float64        `gorm:"type:decimal(12,2);not null" json:"price"`
	OriginalPrice float64        `gorm:"type:decimal(12,2);default:0" json:"original_price"`
	BadgeLabel    string         `gorm:"type:varchar(50)" json:"badge_label"`
	BadgeColor    string         `gorm:"type:varchar(20)" json:"badge_color"`
	Description   string         `gorm:"type:varchar(300)" json:"description"`
	Features      string         `gorm:"type:text" json:"features"`
	Status        int8           `gorm:"type:tinyint;default:1;index" json:"status"`
	Sort          int            `gorm:"type:int;default:0" json:"sort"`
	CreatedAt     time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt     time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt     gorm.DeletedAt `gorm:"index" json:"-"`
}

func (MembershipPlan) TableName() string {
	return "membership_plans"
}

// UserMembership 用户会员记录
// Source: wallet/admin/gift
// Status: active/expired/cancelled
// OrderID 对应 membership_orders.id，可为空（后台赠送时）
type UserMembership struct {
	ID          uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID      uint64         `gorm:"index;not null" json:"user_id"`
	PlanID      uint64         `gorm:"index;not null" json:"plan_id"`
	Status      string         `gorm:"type:varchar(20);not null;default:'active';index" json:"status"`
	Source      string         `gorm:"type:varchar(20);not null;default:'wallet'" json:"source"`
	OrderID     *uint64        `gorm:"index" json:"order_id"`
	AutoRenew   bool           `gorm:"type:tinyint(1);default:0" json:"auto_renew"`
	StartAt     time.Time      `gorm:"type:datetime;not null;index" json:"start_at"`
	ExpireAt    time.Time      `gorm:"type:datetime;not null;index" json:"expire_at"`
	CancelledAt *time.Time     `gorm:"type:datetime" json:"cancelled_at"`
	CreatedAt   time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt   time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	Plan        MembershipPlan `gorm:"foreignKey:PlanID" json:"plan"`
}

func (UserMembership) TableName() string {
	return "user_memberships"
}

func (m UserMembership) IsActive() bool {
	return m.Status == MembershipStatusActive && m.ExpireAt.After(time.Now())
}

// MembershipOrder 会员订单
type MembershipOrder struct {
	ID         uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	OrderNo    string         `gorm:"type:varchar(50);uniqueIndex;not null" json:"order_no"`
	UserID     uint64         `gorm:"index;not null" json:"user_id"`
	PlanID     uint64         `gorm:"index;not null" json:"plan_id"`
	Amount     float64        `gorm:"type:decimal(12,2);not null" json:"amount"`
	PayChannel string         `gorm:"type:varchar(20);not null;default:'wallet'" json:"pay_channel"`
	Status     string         `gorm:"type:varchar(20);not null;default:'pending';index" json:"status"`
	Remark     string         `gorm:"type:varchar(200)" json:"remark"`
	PaidAt     *time.Time     `gorm:"type:datetime" json:"paid_at"`
	CreatedAt  time.Time      `gorm:"type:datetime;not null;index" json:"created_at"`
	UpdatedAt  time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	Plan       MembershipPlan `gorm:"foreignKey:PlanID" json:"plan"`
}

func (MembershipOrder) TableName() string {
	return "membership_orders"
}

const (
	MembershipPlanStatusDisabled int8 = 0
	MembershipPlanStatusEnabled  int8 = 1
)

const (
	MembershipStatusActive    = "active"
	MembershipStatusExpired   = "expired"
	MembershipStatusCancelled = "cancelled"
)

const (
	MembershipOrderStatusPending = "pending"
	MembershipOrderStatusPaid    = "paid"
	MembershipOrderStatusClosed  = "closed"
)
