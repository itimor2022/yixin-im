package models

import (
	"time"

	"gorm.io/gorm"
)

// Call 通话记录模型
type Call struct {
	gorm.Model
	ChannelName string    `gorm:"type:varchar(100);index" json:"channel_name"` // 声网频道名
	CallerID    uint64    `gorm:"index" json:"caller_id"`                      // 主叫方用户ID
	CalleeID    uint64    `gorm:"index" json:"callee_id"`                      // 被叫方用户ID
	CallType    string    `gorm:"type:varchar(20)" json:"call_type"`           // voice/video
	Status      string    `gorm:"type:varchar(20)" json:"status"`              // calling/connected/ended/rejected/cancelled/missed
	StartTime   time.Time `json:"start_time"`                                  // 开始时间
	ConnectTime time.Time `json:"connect_time"`                                // 接通时间
	EndTime     time.Time `json:"end_time"`                                    // 结束时间
	Duration    int       `json:"duration"`                                    // 通话时长（秒）
	EndReason   string    `gorm:"type:varchar(50)" json:"end_reason"`          // 结束原因

	// 关联
	Caller User `gorm:"foreignKey:CallerID" json:"-"`
	Callee User `gorm:"foreignKey:CalleeID" json:"-"`
}

// TableName 表名
func (Call) TableName() string {
	return "calls"
}
