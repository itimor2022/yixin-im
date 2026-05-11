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
