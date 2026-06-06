package models

import "time"

// UserCheckin 签到记录（一天一条）
type UserCheckin struct {
	ID          uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID      uint64    `gorm:"uniqueIndex:uniq_user_date;not null" json:"user_id"`
	CheckinDate time.Time `gorm:"type:date;uniqueIndex:uniq_user_date;not null;index" json:"checkin_date"`
	CreatedAt   time.Time `gorm:"type:datetime;not null" json:"created_at"`
}

func (UserCheckin) TableName() string {
	return "user_checkins"
}

// UserCheckinStat 签到统计（累计/连续）
type UserCheckinStat struct {
	ID              uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID          uint64     `gorm:"uniqueIndex;not null" json:"user_id"`
	TotalDays       int        `gorm:"not null;default:0" json:"total_days"`
	ContinuousDays  int        `gorm:"not null;default:0" json:"continuous_days"`
	LastCheckinDate *time.Time `gorm:"type:date" json:"last_checkin_date"`
	CreatedAt       time.Time  `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt       time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (UserCheckinStat) TableName() string {
	return "user_checkin_stats"
}
