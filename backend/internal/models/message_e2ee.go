// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

// EncryptedKeyEnvelope stores one wrapped content key for one recipient device.
type EncryptedKeyEnvelope struct {
	UserID       string `bson:"user_id" json:"user_id"`
	DeviceID     string `bson:"device_id" json:"device_id"`
	Algo         string `bson:"algo" json:"algo"`
	EncryptedKey string `bson:"encrypted_key" json:"encrypted_key"`
}

// EncryptedMessagePayload stores the encrypted message body and wrapped keys.
type EncryptedMessagePayload struct {
	Version    int                    `bson:"version" json:"version"`
	Algo       string                 `bson:"algo" json:"algo"`
	Ciphertext string                 `bson:"ciphertext" json:"ciphertext"`
	IV         string                 `bson:"iv" json:"iv"`
	Mac        string                 `bson:"mac" json:"mac"`
	Envelopes  []EncryptedKeyEnvelope `bson:"envelopes" json:"envelopes"`
}
