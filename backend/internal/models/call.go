// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import (
	"gorm.io/gorm"
	"time"
)

// Call

type Call struct {
	gorm.Model
	ChannelName     string     `gorm:"type:varchar(100);index" json:"channel_name"`
	RTCProvider     string     `gorm:"type:varchar(20);index;default:'agora'" json:"rtc_provider"`
	CallerID        uint64     `gorm:"index" json:"caller_id"`
	CalleeID        uint64     `gorm:"index" json:"callee_id"`
	CallType        string     `gorm:"type:varchar(20)" json:"call_type"` // voice/video
	Status          string     `gorm:"type:varchar(20)" json:"status"`    // calling/connected/ended/rejected/cancelled/missed
	StartTime       time.Time  `gorm:"type:datetime;not null" json:"start_time"`
	ConnectTime     *time.Time `gorm:"type:datetime" json:"connect_time"`
	LastHeartbeatAt *time.Time `gorm:"type:datetime" json:"last_heartbeat_at"`
	EndTime         *time.Time `gorm:"type:datetime" json:"end_time"`
	Duration        int        `json:"duration"`
	EndReason       string     `gorm:"type:varchar(50)" json:"end_reason"`
	Caller          User       `gorm:"foreignKey:CallerID" json:"-"`
	Callee          User       `gorm:"foreignKey:CalleeID" json:"-"`
}

func (Call) TableName() string {
	return "calls"
}
