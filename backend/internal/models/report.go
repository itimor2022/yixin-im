package models

import (
	"time"

	"gorm.io/gorm"
)

// 举报状态
const (
	ReportStatusPending   = 0 // 待处理
	ReportStatusProcessed = 1 // 已处理
	ReportStatusRejected  = 2 // 已驳回
)

// 举报类型
const (
	ReportTypeUser    = "user"
	ReportTypeGroup   = "group"
	ReportTypeChannel = "channel"
	ReportTypeMessage = "message"
)

// Report 举报记录
type Report struct {
	ID          uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	UUID        string         `gorm:"type:varchar(36);uniqueIndex;not null" json:"uuid"`
	ReporterID  uint64         `gorm:"index;not null" json:"reporter_id"`
	TargetID    string         `gorm:"type:varchar(36);index;not null" json:"target_id"`
	TargetType  string         `gorm:"type:varchar(20);not null" json:"target_type"` // user, group, channel, message
	Reason      string         `gorm:"type:varchar(50);not null" json:"reason"`
	Description string         `gorm:"type:text" json:"description"`
	Status      int8           `gorm:"default:0" json:"status"` // 0-待处理, 1-已处理, 2-已驳回
	ProcessedBy *uint64        `json:"processed_by"`
	ProcessedAt *time.Time     `json:"processed_at"`
	ProcessNote string         `gorm:"type:text" json:"process_note"`
	CreatedAt   time.Time      `json:"created_at"`
	UpdatedAt   time.Time      `json:"updated_at"`
	DeletedAt   gorm.DeletedAt `gorm:"index" json:"-"`

	// 关联
	Reporter User `gorm:"foreignKey:ReporterID" json:"reporter,omitempty"`
}

func (Report) TableName() string {
	return "reports"
}

// GetReasonText 获取举报原因文本
func GetReasonText(reason string) string {
	reasons := map[string]string{
		"spam":       "垃圾信息",
		"fake":       "虚假信息/诈骗",
		"violence":   "暴力或危险内容",
		"porn":       "色情内容",
		"harassment": "骚扰或欺凌",
		"copyright":  "侵犯版权",
		"other":      "其他",
	}
	if text, ok := reasons[reason]; ok {
		return text
	}
	return reason
}
