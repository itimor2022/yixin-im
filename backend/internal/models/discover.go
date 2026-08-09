// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import (
	"time"
)

// DiscoverItem 发现页入口配置
type DiscoverItem struct {
	ID        uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	Title     string    `gorm:"type:varchar(100);not null" json:"title"`
	IconURL   string    `gorm:"type:varchar(500)" json:"icon_url"`
	URL       string    `gorm:"type:varchar(1000);not null" json:"url"`
	Sort      int       `gorm:"default:0;index" json:"sort"`
	Enabled   bool      `gorm:"default:true;index" json:"enabled"`
	CreatedAt time.Time `gorm:"type:datetime;not null;index" json:"created_at"`
	UpdatedAt time.Time `gorm:"type:datetime;not null" json:"updated_at"`
}

func (DiscoverItem) TableName() string {
	return "discover_items"
}

// DiscoverBanner 发现页轮播图配置
type DiscoverBanner struct {
	ID        uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	Title     string    `gorm:"type:varchar(100);not null" json:"title"`
	ImageURL  string    `gorm:"type:varchar(500);not null" json:"image_url"`
	URL       string    `gorm:"type:varchar(1000)" json:"url"`
	Sort      int       `gorm:"default:0;index" json:"sort"`
	Enabled   bool      `gorm:"default:true;index" json:"enabled"`
	CreatedAt time.Time `gorm:"type:datetime;not null;index" json:"created_at"`
	UpdatedAt time.Time `gorm:"type:datetime;not null" json:"updated_at"`
}

func (DiscoverBanner) TableName() string {
	return "discover_banners"
}
