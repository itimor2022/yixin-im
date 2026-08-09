// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import (
	"gorm.io/gorm"
	"time"
)

type ChatAnnouncement struct {
	ID        uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	ChatID    uint64         `gorm:"index;not null" json:"chat_id"`
	Content   string         `gorm:"type:text;not null" json:"content"`
	AuthorID  uint64         `gorm:"not null" json:"author_id"`
	IsPinned  bool           `gorm:"default:true" json:"is_pinned"`
	CreatedAt time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`
}

func (ChatAnnouncement) TableName() string {
	return "chat_announcements"
}

type ChatAnnouncementAcknowledgement struct {
	ID             uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	AnnouncementID uint64    `gorm:"uniqueIndex:idx_announcement_user;index;not null" json:"announcement_id"`
	UserID         uint64    `gorm:"uniqueIndex:idx_announcement_user;index;not null" json:"user_id"`
	AcknowledgedAt time.Time `gorm:"type:datetime;not null" json:"acknowledged_at"`
}

func (ChatAnnouncementAcknowledgement) TableName() string {
	return "chat_announcement_acknowledgements"
}
