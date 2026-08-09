// 文件用途：定义消息提交后派生工作的持久 Outbox 记录。
// 核心逻辑：使用唯一事件键、处理租约、阶段标记和退避时间保证进程重启后可恢复且数据库投影不重复应用。

package models

import (
	"encoding/json"
	"time"
)

const (
	MessageOutboxStatusPending    = "pending"
	MessageOutboxStatusProcessing = "processing"
	MessageOutboxStatusRetrying   = "retrying"
	MessageOutboxStatusCompleted  = "completed"
	MessageOutboxStatusDead       = "dead"

	MessageOutboxTypeProjection          = "projection"
	MessageOutboxTypeMediaCommit         = "media_commit"
	MessageOutboxTypePush                = "push"
	MessageOutboxTypeServiceConversation = "service_conversation"
)

// MessageOutboxEvent stores a durable, idempotent derivation event for one
// already-committed MongoDB message.
type MessageOutboxEvent struct {
	ID          uint64          `gorm:"primaryKey;autoIncrement" json:"id"`
	EventKey    string          `gorm:"type:varchar(191);uniqueIndex;not null" json:"event_key"`
	EventType   string          `gorm:"type:varchar(40);index:idx_message_outbox_ready,priority:3;not null" json:"event_type"`
	ChatID      uint64          `gorm:"index;not null" json:"chat_id"`
	ChatUUID    string          `gorm:"type:char(36);index;not null" json:"chat_uuid"`
	MessageID   string          `gorm:"type:varchar(64);index;not null" json:"message_id"`
	MessageSeq  uint64          `gorm:"index;not null" json:"message_seq"`
	Payload     json.RawMessage `gorm:"type:json;not null" json:"payload"`
	Status      string          `gorm:"type:varchar(20);index:idx_message_outbox_ready,priority:1;not null;default:'pending'" json:"status"`
	Attempts    int             `gorm:"not null;default:0" json:"attempts"`
	AvailableAt time.Time       `gorm:"type:datetime(3);index:idx_message_outbox_ready,priority:2;not null" json:"available_at"`
	LeaseUntil  *time.Time      `gorm:"type:datetime(3);index" json:"lease_until,omitempty"`
	WorkerID    string          `gorm:"type:varchar(80);index" json:"worker_id"`
	DBAppliedAt *time.Time      `gorm:"type:datetime(3);index" json:"db_applied_at,omitempty"`
	CompletedAt *time.Time      `gorm:"type:datetime(3);index" json:"completed_at,omitempty"`
	LastError   string          `gorm:"type:varchar(1000)" json:"last_error"`
	CreatedAt   time.Time       `gorm:"type:datetime(3);not null" json:"created_at"`
	UpdatedAt   time.Time       `gorm:"type:datetime(3);not null" json:"updated_at"`
}

func (MessageOutboxEvent) TableName() string {
	return "message_outbox_events"
}
