// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import "time"

// UploadLog
type UploadLog struct {
	ID          uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	ActorType   string    `gorm:"type:varchar(20);index" json:"actor_type"`
	UserID      uint64    `gorm:"index" json:"user_id"`
	AdminID     uint64    `gorm:"index" json:"admin_id"`
	MediaType   string    `gorm:"type:varchar(30);index" json:"media_type"`
	Provider    string    `gorm:"type:varchar(20);index" json:"provider"`
	ObjectKey   string    `gorm:"type:varchar(500)" json:"object_key"`
	URL         string    `gorm:"type:varchar(800)" json:"url"`
	FileName    string    `gorm:"type:varchar(255)" json:"file_name"`
	ContentType string    `gorm:"type:varchar(120)" json:"content_type"`
	Size        int64     `gorm:"index" json:"size"`
	Success     bool      `gorm:"type:tinyint(1);not null;default:0;index" json:"success"`
	Error       string    `gorm:"type:varchar(512)" json:"error"`
	DurationMS  int64     `json:"duration_ms"`
	IP          string    `gorm:"type:varchar(50);index" json:"ip"`
	UserAgent   string    `gorm:"type:varchar(500)" json:"user_agent"`
	CreatedAt   time.Time `gorm:"type:datetime;not null;index" json:"created_at"`
}

func (UploadLog) TableName() string {
	return "upload_logs"
}

// AdminSecurityEvent
type AdminSecurityEvent struct {
	ID            uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	AdminID       uint64    `gorm:"index" json:"admin_id"`
	AdminUsername string    `gorm:"type:varchar(50);index" json:"admin_username"`
	AdminRole     string    `gorm:"type:varchar(30);index" json:"admin_role"`
	EventType     string    `gorm:"type:varchar(50);index" json:"event_type"`
	Action        string    `gorm:"type:varchar(80);index" json:"action"`
	Target        string    `gorm:"type:varchar(160);index" json:"target"`
	Success       bool      `gorm:"type:tinyint(1);not null;default:1;index" json:"success"`
	Error         string    `gorm:"type:varchar(512)" json:"error"`
	Metadata      string    `gorm:"type:text" json:"metadata"`
	IP            string    `gorm:"type:varchar(50);index" json:"ip"`
	UserAgent     string    `gorm:"type:varchar(500)" json:"user_agent"`
	CreatedAt     time.Time `gorm:"type:datetime;not null;index" json:"created_at"`
}

func (AdminSecurityEvent) TableName() string {
	return "admin_security_events"
}

// HealthMetricSnapshot
type HealthMetricSnapshot struct {
	ID                  uint64    `gorm:"primaryKey;autoIncrement" json:"id"`
	Status              string    `gorm:"type:varchar(20);index" json:"status"`
	MysqlStatus         string    `gorm:"type:varchar(20);index" json:"mysql_status"`
	MongoStatus         string    `gorm:"type:varchar(20);index" json:"mongo_status"`
	RedisStatus         string    `gorm:"type:varchar(20);index" json:"redis_status"`
	StorageStatus       string    `gorm:"type:varchar(20);index" json:"storage_status"`
	UploadStatus        string    `gorm:"type:varchar(20);index" json:"upload_status"`
	WebsocketStatus     string    `gorm:"type:varchar(20);index" json:"websocket_status"`
	PushStatus          string    `gorm:"type:varchar(20);index" json:"push_status"`
	QueueStatus         string    `gorm:"type:varchar(20);index" json:"queue_status"`
	QueueMessageSend    int64     `gorm:"index" json:"queue_message_send"`
	QueueMessageSync    int64     `gorm:"index" json:"queue_message_sync"`
	QueuePushNotify     int64     `gorm:"index" json:"queue_push_notify"`
	QueueDelayed        int64     `gorm:"index" json:"queue_delayed"`
	QueueDead           int64     `gorm:"index" json:"queue_dead"`
	UploadTotal         int64     `gorm:"index" json:"upload_total"`
	UploadFailed        int64     `gorm:"index" json:"upload_failed"`
	PushTotal           int64     `gorm:"index" json:"push_total"`
	PushFailed          int64     `gorm:"index" json:"push_failed"`
	WSOnlineConnections int64     `gorm:"index" json:"ws_online_connections"`
	WSOnlineUsers       int64     `gorm:"index" json:"ws_online_users"`
	WSTotalDisconnects  int64     `gorm:"index" json:"ws_total_disconnects"`
	WSDroppedMessages   int64     `gorm:"index" json:"ws_dropped_messages"`
	Goroutines          int64     `gorm:"index" json:"goroutines"`
	MemoryAllocMB       int64     `gorm:"index" json:"memory_alloc_mb"`
	CreatedAt           time.Time `gorm:"type:datetime;not null;index" json:"created_at"`
}

func (HealthMetricSnapshot) TableName() string {
	return "health_metric_snapshots"
}
