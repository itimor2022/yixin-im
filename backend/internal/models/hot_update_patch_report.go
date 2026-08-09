// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import "time"

const (
	HotUpdatePatchReportStatusCheckHit         = "check_hit"
	HotUpdatePatchReportStatusDeferred         = "deferred"
	HotUpdatePatchReportStatusApplySuccess     = "apply_success"
	HotUpdatePatchReportStatusInstallStarted   = "install_started"
	HotUpdatePatchReportStatusInstallConfirmed = "install_confirmed"
	HotUpdatePatchReportStatusApplyFailed      = "apply_failed"
	HotUpdatePatchReportStatusSDKNotIntegrated = "sdk_not_integrated"
	HotUpdatePatchReportStatusSDKNotAvailable  = "sdk_not_available"
)

// HotUpdatePatchReport
type HotUpdatePatchReport struct {
	ID           uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	PatchID      uint64    `gorm:"not null;default:0;index" json:"patch_id"`
	PatchRefID   string    `gorm:"type:char(36);index" json:"patch_ref_id"`
	PatchVersion string    `gorm:"type:varchar(64)" json:"patch_version"`
	Platform     string    `gorm:"type:varchar(20);not null;default:'android';index" json:"platform"`
	Channel      string    `gorm:"type:varchar(30);not null;default:'stable';index" json:"channel"`
	DeliveryMode string    `gorm:"type:varchar(20);not null;default:'self_hosted';index" json:"delivery_mode"`
	AppVersion   string    `gorm:"type:varchar(64)" json:"app_version"`
	BuildNumber  int       `gorm:"not null;default:0" json:"build_number"`
	DeviceID     string    `gorm:"type:varchar(128);index" json:"device_id"`
	UserUUID     string    `gorm:"type:char(36);index" json:"user_uuid"`
	Status       string    `gorm:"type:varchar(32);not null;index" json:"status"`
	Message      string    `gorm:"type:varchar(500)" json:"message"`
	ClientIP     string    `gorm:"type:varchar(64)" json:"client_ip"`
	CreatedAt    time.Time `gorm:"type:datetime;not null;index" json:"created_at"`
}

func (HotUpdatePatchReport) TableName() string {
	return "hot_update_patch_reports"
}
