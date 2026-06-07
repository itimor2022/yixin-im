package models

import "time"

// PopupAnnouncement 启动弹窗公告（全局，App 启动拉取，只弹一次）
// 区别于 ChatAnnouncement（群公告）与 SystemBroadcast（在线实时广播）
type PopupAnnouncement struct {
	ID        uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	Title     string    `gorm:"type:varchar(200);not null;default:''" json:"title"`
	Content   string    `gorm:"type:text;not null" json:"content"`
	ImageURL  string    `gorm:"type:varchar(500);not null;default:''" json:"image_url"`
	LinkURL   string    `gorm:"type:varchar(500);not null;default:''" json:"link_url"`
	Enabled   int8      `gorm:"type:tinyint;not null;default:0;index" json:"enabled"`
	CreatedAt time.Time `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt time.Time `gorm:"type:datetime;not null" json:"updated_at"`
}

func (PopupAnnouncement) TableName() string {
	return "popup_announcements"
}
