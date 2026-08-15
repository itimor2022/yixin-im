package models

import "time"

// UserCheckin 用户签到记录
type UserCheckin struct {
	ID        uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID    string    `gorm:"type:varchar(36);not null;index:idx_user_date,unique" json:"user_id"`
	CheckinAt time.Time `gorm:"type:date;not null;index:idx_user_date,unique" json:"checkin_at"`
	CreatedAt time.Time `gorm:"type:datetime;not null" json:"created_at"`
}

func (UserCheckin) TableName() string {
	return "user_checkins"
}
