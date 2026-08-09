// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import (
	"gorm.io/gorm"
	"time"
)

const (
	ServiceFollowUpPending  = "pending"
	ServiceFollowUpDone     = "done"
	ServiceFollowUpCanceled = "canceled"
)

// ServiceQuickReply stores team-shared response templates for the service workbench.
type ServiceQuickReply struct {
	ID               uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	UUID             string         `gorm:"type:char(36);uniqueIndex;not null" json:"uuid"`
	Category         string         `gorm:"type:varchar(50);not null;default:'通用';index" json:"category"`
	Title            string         `gorm:"type:varchar(100);not null" json:"title"`
	Content          string         `gorm:"type:text;not null" json:"content"`
	Shortcut         string         `gorm:"type:varchar(30);index" json:"shortcut"`
	Keywords         string         `gorm:"type:varchar(255)" json:"keywords"`
	SortOrder        int            `gorm:"not null;default:0;index" json:"sort_order"`
	Enabled          bool           `gorm:"type:tinyint(1);not null;default:1;index" json:"enabled"`
	CreatedByAgentID uint64         `gorm:"index;not null" json:"created_by_agent_id"`
	UpdatedByAgentID uint64         `gorm:"index;not null" json:"updated_by_agent_id"`
	CreatedAt        time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt        time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt        gorm.DeletedAt `gorm:"index" json:"-"`
}

func (ServiceQuickReply) TableName() string { return "service_quick_replies" }

// ServiceCustomerProfile contains private team metadata that is never exposed
// through customer-facing user APIs.
type ServiceCustomerProfile struct {
	ID               uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	CustomerUserID   uint64    `gorm:"uniqueIndex;not null" json:"customer_user_id"`
	TagsJSON         string    `gorm:"type:longtext" json:"-"`
	InternalNote     string    `gorm:"type:text" json:"internal_note"`
	UpdatedByAgentID uint64    `gorm:"index;not null" json:"updated_by_agent_id"`
	CreatedAt        time.Time `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt        time.Time `gorm:"type:datetime;not null" json:"updated_at"`
}

func (ServiceCustomerProfile) TableName() string { return "service_customer_profiles" }

// ServiceFollowUp is a concrete reminder owned by an agent. It remains
// independent from the conversation lifecycle so completed chats can still be
// followed up later.
type ServiceFollowUp struct {
	ID               uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UUID             string     `gorm:"type:char(36);uniqueIndex;not null" json:"uuid"`
	CustomerUserID   uint64     `gorm:"index:idx_service_followup_customer_status,priority:1;not null" json:"customer_user_id"`
	ConversationID   *uint64    `gorm:"index" json:"conversation_id,omitempty"`
	AssignedAgentID  uint64     `gorm:"index:idx_service_followup_agent_due,priority:1;not null" json:"assigned_agent_id"`
	Content          string     `gorm:"type:varchar(500);not null" json:"content"`
	DueAt            time.Time  `gorm:"type:datetime;index:idx_service_followup_agent_due,priority:2;not null" json:"due_at"`
	Status           string     `gorm:"type:varchar(20);index:idx_service_followup_customer_status,priority:2;not null;default:'pending'" json:"status"`
	CompletedAt      *time.Time `gorm:"type:datetime" json:"completed_at,omitempty"`
	CreatedByAgentID uint64     `gorm:"index;not null" json:"created_by_agent_id"`
	CreatedAt        time.Time  `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt        time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (ServiceFollowUp) TableName() string { return "service_follow_ups" }
