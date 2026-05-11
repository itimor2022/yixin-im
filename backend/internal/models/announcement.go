package models

import (
	"time"

	"gorm.io/gorm"
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
