// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import "time"

const (
	ServiceAgentRoleAgent      = "agent"
	ServiceAgentRoleSupervisor = "supervisor"
)

const (
	ServicePresenceOnline  = "online"
	ServicePresenceBusy    = "busy"
	ServicePresenceOffline = "offline"
)

const (
	ServiceConversationWaiting  = "waiting"
	ServiceConversationAssigned = "assigned"
	ServiceConversationServing  = "serving"
	ServiceConversationPending  = "pending"
	ServiceConversationClosed   = "closed"
)

const (
	ServiceOperatorCustomer   = "customer"
	ServiceOperatorAgent      = "agent"
	ServiceOperatorSupervisor = "supervisor"
	ServiceOperatorAI         = "ai"
	ServiceOperatorSystem     = "system"
)

// ServiceAgent
type ServiceAgent struct {
	ID                           uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID                       uint64     `gorm:"uniqueIndex;not null" json:"user_id"`
	DefaultServiceIdentityUserID uint64     `gorm:"index;not null" json:"default_service_identity_user_id"`
	Role                         string     `gorm:"type:varchar(20);not null;default:'agent';index" json:"role"`
	Presence                     string     `gorm:"type:varchar(20);not null;default:'offline';index" json:"presence"`
	MaxConcurrent                int        `gorm:"not null;default:5" json:"max_concurrent"`
	CurrentServing               int        `gorm:"not null;default:0" json:"current_serving"`
	AutoAssignEnabled            bool       `gorm:"type:tinyint(1);not null;default:1;index" json:"auto_assign_enabled"`
	LastAssignedAt               *time.Time `gorm:"type:datetime;index" json:"last_assigned_at,omitempty"`
	LastHeartbeatAt              *time.Time `gorm:"type:datetime;index" json:"last_heartbeat_at,omitempty"`
	CreatedAt                    time.Time  `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt                    time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (ServiceAgent) TableName() string { return "service_agents" }

// ServiceConversation
type ServiceConversation struct {
	ID                     uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UUID                   string     `gorm:"type:char(36);uniqueIndex;not null" json:"uuid"`
	ChatID                 uint64     `gorm:"uniqueIndex:idx_service_chat_round;index;not null" json:"chat_id"`
	ChatUUID               string     `gorm:"type:char(36);index;not null" json:"chat_uuid"`
	CustomerUserID         uint64     `gorm:"index:idx_service_customer_created,priority:1;not null" json:"customer_user_id"`
	ServiceIdentityUserID  uint64     `gorm:"index;not null" json:"service_identity_user_id"`
	AssignedAgentID        *uint64    `gorm:"index:idx_service_agent_queue,priority:1" json:"assigned_agent_id,omitempty"`
	Status                 string     `gorm:"type:varchar(20);index:idx_service_queue,priority:1;index:idx_service_agent_queue,priority:2;not null" json:"status"`
	Priority               int8       `gorm:"type:tinyint;index:idx_service_queue,priority:2,sort:desc;not null;default:0" json:"priority"`
	Source                 string     `gorm:"type:varchar(30);not null;default:'direct';index" json:"source"`
	RoundNo                int        `gorm:"uniqueIndex:idx_service_chat_round;not null;default:1" json:"round_no"`
	LastMessageID          string     `gorm:"type:char(36)" json:"last_message_id"`
	LastCustomerMessageSeq uint64     `gorm:"not null;default:0;index" json:"last_customer_message_seq"`
	LastMessageText        string     `gorm:"type:varchar(500)" json:"last_message_text"`
	LastMessageType        int        `gorm:"not null;default:1" json:"last_message_type"`
	LastMessageAt          *time.Time `gorm:"type:datetime;index:idx_service_agent_queue,priority:3,sort:desc" json:"last_message_at,omitempty"`
	CustomerUnreadCount    int        `gorm:"not null;default:0" json:"customer_unread_count"`
	QueuedAt               time.Time  `gorm:"type:datetime;index:idx_service_queue,priority:3;not null" json:"queued_at"`
	AssignedAt             *time.Time `gorm:"type:datetime" json:"assigned_at,omitempty"`
	AcceptedAt             *time.Time `gorm:"type:datetime" json:"accepted_at,omitempty"`
	FirstResponseAt        *time.Time `gorm:"type:datetime" json:"first_response_at,omitempty"`
	ClosedAt               *time.Time `gorm:"type:datetime" json:"closed_at,omitempty"`
	CloseReason            string     `gorm:"type:varchar(100)" json:"close_reason"`
	AIStatus               string     `gorm:"type:varchar(20);not null;default:'disabled';index" json:"ai_status"`
	CreatedAt              time.Time  `gorm:"type:datetime;index:idx_service_customer_created,priority:2,sort:desc;not null" json:"created_at"`
	UpdatedAt              time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (ServiceConversation) TableName() string { return "service_conversations" }

// ServiceConversationEvent
type ServiceConversationEvent struct {
	ID             uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	ConversationID uint64    `gorm:"index;not null" json:"conversation_id"`
	EventType      string    `gorm:"type:varchar(40);index;not null" json:"event_type"`
	OperatorType   string    `gorm:"type:varchar(20);index;not null" json:"operator_type"`
	OperatorID     uint64    `gorm:"index;not null;default:0" json:"operator_id"`
	FromStatus     string    `gorm:"type:varchar(20)" json:"from_status"`
	ToStatus       string    `gorm:"type:varchar(20)" json:"to_status"`
	PayloadJSON    string    `gorm:"type:longtext" json:"payload_json"`
	CreatedAt      time.Time `gorm:"type:datetime;index;not null" json:"created_at"`
}

func (ServiceConversationEvent) TableName() string { return "service_conversation_events" }
