// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import (
	"encoding/json"
	"time"
)

// MessageFavorite is a user-owned immutable snapshot of a message. DeletedAt
// is an explicit tombstone(not GORM soft-delete) so other devices can consume
// incremental removals.
type MessageFavorite struct {
	ID          uint64          `gorm:"primaryKey;autoIncrement" json:"-"`
	UUID        string          `gorm:"type:char(36);uniqueIndex;not null" json:"favorite_id"`
	UserID      uint64          `gorm:"uniqueIndex:idx_message_favorite_owner;index;not null" json:"-"`
	ChatUUID    string          `gorm:"type:char(36);uniqueIndex:idx_message_favorite_owner;not null" json:"chat_id"`
	MessageID   string          `gorm:"type:varchar(64);uniqueIndex:idx_message_favorite_owner;not null" json:"message_id"`
	MessageSeq  uint64          `gorm:"default:0" json:"message_seq,omitempty"`
	Snapshot    json.RawMessage `gorm:"type:json;not null" json:"snapshot"`
	CollectedAt time.Time       `gorm:"type:datetime(3);not null;index" json:"collected_at"`
	DeletedAt   *time.Time      `gorm:"type:datetime(3);index" json:"deleted_at,omitempty"`
	CreatedAt   time.Time       `gorm:"type:datetime(3);not null" json:"created_at"`
	UpdatedAt   time.Time       `gorm:"type:datetime(3);not null;index" json:"updated_at"`
}

func (MessageFavorite) TableName() string {
	return "message_favorites"
}
