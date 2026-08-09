// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import (
	"gorm.io/gorm"
	"time"
)

const (
	HotUpdatePatchPlatformAndroid = "android"
	HotUpdatePatchPlatformIOS     = "ios"
	HotUpdatePatchPlatformAll     = "all"
)

const (
	HotUpdatePatchStatusDraft      = "draft"
	HotUpdatePatchStatusPublished  = "published"
	HotUpdatePatchStatusPaused     = "paused"
	HotUpdatePatchStatusRolledBack = "rolled_back"
)

const (
	HotUpdatePatchDeliveryModeSelfHosted = "self_hosted"
	HotUpdatePatchDeliveryModeShorebird  = "shorebird"
)

// HotUpdatePatch 热更新补丁配置
type HotUpdatePatch struct {
	ID                uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	PatchID           string         `gorm:"type:char(36);uniqueIndex;not null" json:"patch_id"`
	Name              string         `gorm:"type:varchar(120);not null" json:"name"`
	Description       string         `gorm:"type:varchar(500)" json:"description"`
	Platform          string         `gorm:"type:varchar(20);not null;default:'android';index" json:"platform"`
	Channel           string         `gorm:"type:varchar(30);not null;default:'stable';index" json:"channel"`
	DeliveryMode      string         `gorm:"type:varchar(20);not null;default:'self_hosted';index" json:"delivery_mode"`
	MinAppVersion     string         `gorm:"type:varchar(64)" json:"min_app_version"`
	MaxAppVersion     string         `gorm:"type:varchar(64)" json:"max_app_version"`
	MinBuildNumber    int            `gorm:"not null;default:0" json:"min_build_number"`
	MaxBuildNumber    int            `gorm:"not null;default:0" json:"max_build_number"`
	TargetAppVersion  string         `gorm:"type:varchar(64)" json:"target_app_version"`
	PatchVersion      string         `gorm:"type:varchar(64);not null" json:"patch_version"`
	PatchURL          string         `gorm:"type:varchar(500);not null" json:"patch_url"`
	PatchHash         string         `gorm:"type:varchar(128)" json:"patch_hash"`
	ReleaseNotes      string         `gorm:"type:text" json:"release_notes"`
	RolloutPercentage int            `gorm:"not null;default:100;index" json:"rollout_percentage"`
	IsMandatory       bool           `gorm:"not null;default:false" json:"is_mandatory"`
	Priority          int            `gorm:"not null;default:0;index" json:"priority"`
	Status            string         `gorm:"type:varchar(20);not null;default:'draft';index" json:"status"`
	StartAt           *time.Time     `gorm:"index" json:"start_at"`
	EndAt             *time.Time     `gorm:"index" json:"end_at"`
	PublishedAt       *time.Time     `json:"published_at"`
	PausedAt          *time.Time     `json:"paused_at"`
	RollbackAt        *time.Time     `json:"rollback_at"`
	CreatedBy         uint64         `json:"created_by"`
	UpdatedBy         uint64         `json:"updated_by"`
	CreatedAt         time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt         time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt         gorm.DeletedAt `gorm:"index" json:"-"`
}

func (HotUpdatePatch) TableName() string {
	return "hot_update_patches"
}
