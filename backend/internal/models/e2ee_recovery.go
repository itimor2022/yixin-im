// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import "time"

const (
	E2EERecoveryPending   = "pending"
	E2EERecoveryApproved  = "approved"
	E2EERecoveryConsumed  = "consumed"
	E2EERecoveryCancelled = "cancelled"
)

// E2EERecoveryRequest brokers an opaque, end-to-end encrypted recovery
// package from an already trusted device to a newly signed-in device. The
// server never receives the source private key in plaintext.
type E2EERecoveryRequest struct {
	ID                     uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	RequestID              string     `gorm:"type:char(36);uniqueIndex;not null" json:"request_id"`
	UserID                 uint64     `gorm:"index;not null" json:"user_id"`
	RequesterDeviceID      string     `gorm:"type:varchar(100);index;not null" json:"requester_device_id"`
	RequesterPublicKey     string     `gorm:"type:text;not null" json:"requester_public_key"`
	RequesterPublicKeyAlgo string     `gorm:"type:varchar(64);not null" json:"requester_public_key_algo"`
	SourceDeviceID         string     `gorm:"type:varchar(100);index" json:"source_device_id"`
	SourceKeyFingerprint   string     `gorm:"type:char(64);index" json:"source_key_fingerprint"`
	SourceKeyVersion       uint64     `gorm:"not null;default:0" json:"source_key_version"`
	EncryptedPayload       string     `gorm:"type:longtext" json:"encrypted_payload,omitempty"`
	PayloadAlgo            string     `gorm:"type:varchar(64)" json:"payload_algo,omitempty"`
	Status                 string     `gorm:"type:varchar(20);index;not null" json:"status"`
	ExpiresAt              time.Time  `gorm:"type:datetime;index;not null" json:"expires_at"`
	ApprovedAt             *time.Time `gorm:"type:datetime" json:"approved_at,omitempty"`
	ConsumedAt             *time.Time `gorm:"type:datetime" json:"consumed_at,omitempty"`
	CreatedAt              time.Time  `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt              time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (E2EERecoveryRequest) TableName() string {
	return "e2ee_recovery_requests"
}
