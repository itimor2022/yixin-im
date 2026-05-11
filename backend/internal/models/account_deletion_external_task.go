package models

import "time"

const (
	AccountDeletionExternalTaskPending  = "pending"
	AccountDeletionExternalTaskRetrying = "retrying"
	AccountDeletionExternalTaskSuccess  = "success"
	AccountDeletionExternalTaskFailed   = "failed"
	AccountDeletionExternalTaskManual   = "manual_required"
)

// AccountDeletionExternalTask stores asynchronous external-media cleanup tasks.
type AccountDeletionExternalTask struct {
	ID          uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserUUID    string     `gorm:"type:char(36);index;not null" json:"user_uuid"`
	ResourceURL string     `gorm:"type:varchar(2048);not null" json:"resource_url"`
	Status      string     `gorm:"type:varchar(32);index;not null;default:'pending'" json:"status"`
	RetryCount  int        `gorm:"type:int;not null;default:0" json:"retry_count"`
	NextRetryAt *time.Time `gorm:"type:datetime;index" json:"next_retry_at"`
	LastError   string     `gorm:"type:varchar(500)" json:"last_error"`
	FinishedAt  *time.Time `gorm:"type:datetime" json:"finished_at"`
	CreatedAt   time.Time  `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt   time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (AccountDeletionExternalTask) TableName() string {
	return "account_deletion_external_tasks"
}
