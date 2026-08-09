// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import "time"

// AccountDeletionAudit records cross-store cleanup results for account deletion.
type AccountDeletionAudit struct {
	ID                  uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	UserUUID            string    `gorm:"type:char(36);index;not null" json:"user_uuid"`
	MongoStatus         string    `gorm:"type:varchar(32);not null" json:"mongo_status"`
	MongoDeletedCount   int64     `gorm:"type:bigint;not null;default:0" json:"mongo_deleted_count"`
	LocalFilesDeleted   int       `gorm:"type:int;not null;default:0" json:"local_files_deleted"`
	LocalFilesFailed    int       `gorm:"type:int;not null;default:0" json:"local_files_failed"`
	ExternalQueuedCount int       `gorm:"type:int;not null;default:0" json:"external_queued_count"`
	ExternalCleanupHint string    `gorm:"type:varchar(64);not null;default:'pending_or_not_configured'" json:"external_cleanup_hint"`
	CreatedAt           time.Time `gorm:"type:datetime;not null" json:"created_at"`
}

func (AccountDeletionAudit) TableName() string {
	return "account_deletion_audits"
}
