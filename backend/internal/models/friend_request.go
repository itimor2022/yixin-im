// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import "time"

const (
	FriendRequestPending  = "pending"
	FriendRequestAccepted = "accepted"
	FriendRequestRejected = "rejected"
	FriendRequestExpired  = "expired"
)

type FriendRequest struct {
	ID          uint64     `gorm:"primaryKey;autoIncrement" json:"-"`
	UUID        string     `gorm:"type:char(36);uniqueIndex;not null" json:"id"`
	SenderID    uint64     `gorm:"index:idx_friend_request_sender_status;index:idx_friend_request_pair;not null" json:"-"`
	RecipientID uint64     `gorm:"index:idx_friend_request_recipient_status;index:idx_friend_request_pair;not null" json:"-"`
	Message     string     `gorm:"type:varchar(200)" json:"message"`
	Status      string     `gorm:"type:varchar(20);index:idx_friend_request_sender_status;index:idx_friend_request_recipient_status;default:'pending';not null" json:"status"`
	ExpiresAt   time.Time  `gorm:"type:datetime(3);index;not null" json:"expires_at"`
	RespondedAt *time.Time `gorm:"type:datetime(3)" json:"responded_at,omitempty"`
	CreatedAt   time.Time  `gorm:"type:datetime(3);not null" json:"created_at"`
	UpdatedAt   time.Time  `gorm:"type:datetime(3);not null" json:"updated_at"`
}

func (FriendRequest) TableName() string {
	return "friend_requests"
}
