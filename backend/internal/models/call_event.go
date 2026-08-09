// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import "time"

// CallEvent records every important one-to-one call state transition so
// support and operations can replay why a call was released or blocked.
type CallEvent struct {
	ID        uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	CallID    uint64    `gorm:"index" json:"call_id"`
	EventType string    `gorm:"type:varchar(50);index;not null" json:"event_type"`
	ActorID   *uint64   `gorm:"index" json:"actor_id,omitempty"`
	CallerID  uint64    `gorm:"index" json:"caller_id"`
	CalleeID  uint64    `gorm:"index" json:"callee_id"`
	OldStatus string    `gorm:"type:varchar(20)" json:"old_status"`
	NewStatus string    `gorm:"type:varchar(20)" json:"new_status"`
	Reason    string    `gorm:"type:varchar(50);index" json:"reason"`
	Duration  int       `gorm:"type:int;not null;default:0" json:"duration"`
	LatencyMS int64     `gorm:"type:bigint;not null;default:0" json:"latency_ms"`
	RequestID string    `gorm:"type:varchar(100);index" json:"request_id"`
	Payload   string    `gorm:"type:longtext" json:"payload"`
	CreatedAt time.Time `gorm:"type:datetime;not null;index" json:"created_at"`
}

func (CallEvent) TableName() string {
	return "call_events"
}
