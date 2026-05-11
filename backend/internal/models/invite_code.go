package models

import (
	"time"

	"gorm.io/gorm"
)

type InviteCode struct {
	ID              uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	Code            string         `gorm:"type:varchar(32);uniqueIndex;not null" json:"code"`
	ServiceUserID   uint64         `gorm:"not null" json:"service_user_id"`
	ServiceUserUUID string         `gorm:"type:char(36)" json:"service_user_uuid"`
	ServiceUserName string         `gorm:"-" json:"service_user_name"`
	MaxUses         int            `gorm:"default:0" json:"max_uses"`
	UsedCount       int            `gorm:"default:0" json:"used_count"`
	Status          int8           `gorm:"default:1" json:"status"`
	Remark          string         `gorm:"type:varchar(200)" json:"remark"`
	ExpiresAt       *time.Time     `gorm:"type:datetime" json:"expires_at"`
	CreatedAt       time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt       time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt       gorm.DeletedAt `gorm:"index" json:"-"`
}

func (InviteCode) TableName() string {
	return "invite_codes"
}

type InviteCodeUsage struct {
	ID           uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	InviteCodeID uint64    `gorm:"index;not null" json:"invite_code_id"`
	UserID       uint64    `gorm:"index;not null" json:"user_id"`
	CreatedAt    time.Time `gorm:"type:datetime;not null" json:"created_at"`
}

func (InviteCodeUsage) TableName() string {
	return "invite_code_usages"
}
