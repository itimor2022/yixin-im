// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import "time"

const (
	MediaObjectStatusUploading   = "uploading"
	MediaObjectStatusUploaded    = "uploaded"
	MediaObjectStatusBinding     = "binding"
	MediaObjectStatusBound       = "bound"
	MediaObjectStatusQuarantined = "quarantined"
	MediaObjectStatusDeleting    = "deleting"
	MediaObjectStatusDeleted     = "deleted"
	MediaObjectStatusFailed      = "failed"
) // MediaObject is the durable lifecycle record for one uploaded object. // UploadLog remains diagnostic-only; business binding and cleanup use this table.
type MediaObject struct {
	ID              uint64     `gorm:"primaryKey" json:"id"`
	MediaID         string     `gorm:"type:char(36);not null;uniqueIndex" json:"media_id"`
	UserID          uint64     `gorm:"not null;default:0;index;uniqueIndex:idx_media_actor_request,priority:1" json:"user_id"`
	AdminID         uint64     `gorm:"not null;default:0;index" json:"admin_id"`
	ClientRequestID string     `gorm:"type:varchar(64);not null;uniqueIndex:idx_media_actor_request,priority:2" json:"client_request_id"`
	Category        string     `gorm:"type:varchar(30);not null;index" json:"category"`
	Provider        string     `gorm:"type:varchar(20);not null;index" json:"provider"`
	Bucket          string     `gorm:"type:varchar(255);not null;default:''" json:"bucket"`
	ObjectKey       string     `gorm:"type:varchar(500);not null;uniqueIndex" json:"object_key"`
	URL             string     `gorm:"type:varchar(800);not null;default:''" json:"url"`
	OriginalName    string     `gorm:"type:varchar(255);not null;default:''" json:"original_name"`
	NormalizedExt   string     `gorm:"type:varchar(20);not null;default:''" json:"normalized_ext"`
	DeclaredMIME    string     `gorm:"type:varchar(120);not null;default:''" json:"declared_mime"`
	DetectedMIME    string     `gorm:"type:varchar(120);not null;default:''" json:"detected_mime"`
	SizeBytes       int64      `gorm:"not null;default:0" json:"size_bytes"`
	ChecksumSHA256  string     `gorm:"type:char(64);not null;default:''" json:"checksum_sha256"`
	ExpectedSHA256  string     `gorm:"type:char(64);not null;default:''" json:"expected_sha256"`
	UploadMode      string     `gorm:"type:varchar(20);not null;default:'proxy';index" json:"upload_mode"`
	RemoteUploadID  string     `gorm:"type:varchar(512);not null;default:''" json:"-"`
	PartSizeBytes   int64      `gorm:"not null;default:0" json:"part_size_bytes"`
	Status          string     `gorm:"type:varchar(20);not null;index" json:"status"`
	BusinessType    string     `gorm:"type:varchar(30);not null;default:'';index" json:"business_type"`
	BusinessID      string     `gorm:"type:varchar(64);not null;default:'';index" json:"business_id"`
	BusinessScopeID string     `gorm:"type:varchar(64);not null;default:'';index" json:"business_scope_id"`
	ReferenceCount  int        `gorm:"not null;default:0" json:"reference_count"`
	RetryCount      int        `gorm:"not null;default:0" json:"retry_count"`
	LastError       string     `gorm:"type:varchar(512);not null;default:''" json:"last_error"`
	ExpiresAt       *time.Time `gorm:"index" json:"expires_at,omitempty"`
	NextRetryAt     *time.Time `gorm:"index" json:"next_retry_at,omitempty"`
	BoundAt         *time.Time `json:"bound_at,omitempty"`
	DeletedAt       *time.Time `gorm:"index" json:"deleted_at,omitempty"`
	CreatedAt       time.Time  `gorm:"index" json:"created_at"`
	UpdatedAt       time.Time  `json:"updated_at"`
}

func (MediaObject) TableName() string {
	return "media_objects"
}
