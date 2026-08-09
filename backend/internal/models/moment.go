// 文件用途：定义业务实体的 ORM 字段、关联关系和持久化约束。
// 核心逻辑：统一描述字段映射、状态值、索引和表名，作为各层共享数据契约。

package models

import (
	"gorm.io/gorm"
	"time"
)

// 动态可见性
const (
	VisibilityPublic   = 1 // 公开（所有人可见）
	VisibilityContacts = 2 // 仅联系人
	VisibilitySelected = 3 // 选择特定联系人
	VisibilityPrivate  = 4 // 仅自己可见
)

// 动态内容类型
const (
	ContentTypeText  = 1 // 纯文字
	ContentTypeImage = 2 // 图片
	ContentTypeVideo = 3 // 视频
)

// 动态状态
const (
	MomentStatusPending = 0 // 待审核
	MomentStatusNormal  = 1 // 正常
	MomentStatusHidden  = 2 // 隐藏（违规）
	MomentStatusDeleted = 3 // 已删除
)

// Moment 动态
type Moment struct {
	ID               uint64         `gorm:"primaryKey;index:idx_moments_status_visibility_created,priority:4,sort:desc;index:idx_moments_user_status_created,priority:4,sort:desc;index:idx_moments_status_created,priority:3,sort:desc" json:"id"`
	UUID             string         `gorm:"type:varchar(36);uniqueIndex" json:"uuid"`
	UserID           uint64         `gorm:"index;index:idx_moments_user_status_created,priority:1" json:"user_id"`
	Content          string         `gorm:"type:text" json:"content"`
	ContentType      int8           `gorm:"type:tinyint;default:1" json:"content_type"` // 1:文字 2:图片 3:视频
	MediaUrls        JSON           `gorm:"type:json" json:"media_urls"`
	VideoThumbnail   string         `gorm:"type:varchar(500)" json:"video_thumbnail"`
	Topics           JSON           `gorm:"type:json" json:"topics"` // 话题标签数组
	Visibility       int8           `gorm:"type:tinyint;default:1;index:idx_moments_status_visibility_created,priority:2" json:"visibility"`
	SelectedContacts JSON           `gorm:"type:json" json:"selected_contacts"` // 选择可见的联系人ID
	LikeCount        int            `gorm:"default:0" json:"like_count"`
	CommentCount     int            `gorm:"default:0" json:"comment_count"`
	ShareCount       int            `gorm:"default:0" json:"share_count"`
	ViewCount        int            `gorm:"default:0" json:"view_count"`
	Status           int8           `gorm:"type:tinyint;index:idx_moments_status_visibility_created,priority:1;index:idx_moments_user_status_created,priority:2;index:idx_moments_status_created,priority:1" json:"status"` // 0:待审核 1:正常 2:隐藏 3:删除
	ReviewReason     string         `gorm:"type:varchar(500)" json:"review_reason"`
	ReviewedBy       *uint64        `gorm:"index" json:"reviewed_by,omitempty"`
	ReviewedAt       *time.Time     `gorm:"type:datetime" json:"reviewed_at,omitempty"`
	Location         string         `gorm:"type:varchar(200)" json:"location"`
	CreatedAt        time.Time      `gorm:"index:idx_moments_status_visibility_created,priority:3,sort:desc;index:idx_moments_user_status_created,priority:3,sort:desc;index:idx_moments_status_created,priority:2,sort:desc" json:"created_at"`
	UpdatedAt        time.Time      `json:"updated_at"`
	DeletedAt        gorm.DeletedAt `gorm:"index" json:"-"`

	// 关联
	User User `gorm:"foreignKey:UserID" json:"-"`
}

// MomentLike 动态点赞
type MomentLike struct {
	ID        uint64    `gorm:"primaryKey" json:"id"`
	MomentID  uint64    `gorm:"index;not null" json:"moment_id"`
	UserID    uint64    `gorm:"index;not null" json:"user_id"`
	CreatedAt time.Time `json:"created_at"`
}

// TableName 设置唯一索引
func (MomentLike) TableName() string {
	return "moment_likes"
}

// MomentComment 动态评论
type MomentComment struct {
	ID        uint64         `gorm:"primaryKey" json:"id"`
	UUID      string         `gorm:"type:varchar(36);uniqueIndex" json:"uuid"`
	MomentID  uint64         `gorm:"index;not null" json:"moment_id"`
	UserID    uint64         `gorm:"index;not null" json:"user_id"`
	ParentID  *uint64        `gorm:"index" json:"parent_id"`   // 回复的评论ID
	ReplyToID *uint64        `gorm:"index" json:"reply_to_id"` // 回复的用户ID
	Content   string         `gorm:"type:text;not null" json:"content"`
	LikeCount int            `gorm:"default:0" json:"like_count"`
	Status    int8           `gorm:"type:tinyint;default:1" json:"status"` // 1:正常 2:隐藏
	CreatedAt time.Time      `json:"created_at"`
	UpdatedAt time.Time      `json:"updated_at"`
	DeletedAt gorm.DeletedAt `gorm:"index" json:"-"`

	// 关联
	User    User            `gorm:"foreignKey:UserID" json:"-"`
	Moment  Moment          `gorm:"foreignKey:MomentID" json:"-"`
	Replies []MomentComment `gorm:"foreignKey:ParentID" json:"replies,omitempty"`
}

// Topic 话题
type Topic struct {
	ID          uint64    `gorm:"primaryKey" json:"id"`
	Name        string    `gorm:"type:varchar(100);uniqueIndex;not null" json:"name"`
	Description string    `gorm:"type:varchar(500)" json:"description"`
	Icon        string    `gorm:"type:varchar(100)" json:"icon"` // emoji 或图标名称
	CoverImage  string    `gorm:"type:varchar(500)" json:"cover_image"`
	PostCount   int       `gorm:"default:0" json:"post_count"`
	FollowCount int       `gorm:"default:0" json:"follow_count"`
	IsHot       bool      `gorm:"default:false" json:"is_hot"`
	IsOfficial  bool      `gorm:"default:false" json:"is_official"`     // 官方话题
	Status      int8      `gorm:"type:tinyint;default:1" json:"status"` // 1:正常 2:禁用
	Sort        int       `gorm:"default:0" json:"sort"`                // 排序权重
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// BannedWord 违禁词
type BannedWord struct {
	ID          uint64    `gorm:"primaryKey" json:"id"`
	Word        string    `gorm:"type:varchar(100);uniqueIndex;not null" json:"word"`
	Category    string    `gorm:"type:varchar(50);index" json:"category"` // 分类：政治、色情、广告等
	Level       int8      `gorm:"type:tinyint;default:1" json:"level"`    // 1:警告 2:屏蔽 3:禁止发布
	Replacement string    `gorm:"type:varchar(100)" json:"replacement"`   // 替换词（屏蔽时使用）
	Status      int8      `gorm:"type:tinyint;default:1" json:"status"`   // 1:启用 2:禁用
	HitCount    int       `gorm:"default:0" json:"hit_count"`             // 命中次数统计
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
}

// 违禁词级别
const (
	BannedLevelWarn   = 1 // 警告（记录但不阻止）
	BannedLevelFilter = 2 // 屏蔽（替换为*）
	BannedLevelBlock  = 3 // 禁止发布
)

// 违禁词分类
const (
	BannedCategoryPolitics = "politics" // 政治敏感
	BannedCategoryPorn     = "porn"     // 色情
	BannedCategoryAds      = "ads"      // 广告
	BannedCategoryViolence = "violence" // 暴力
	BannedCategoryFraud    = "fraud"    // 欺诈
	BannedCategoryOther    = "other"    // 其他
)

// JSON 类型用于存储 JSON 数组
type JSON []byte

func (j *JSON) Scan(value interface{}) error {
	if value == nil {
		*j = nil
		return nil
	}
	switch v := value.(type) {
	case []byte:
		// 必须复制切片，否则 MySQL 驱动会复用底层缓冲区导致数据损坏
		cp := make([]byte, len(v))
		copy(cp, v)
		*j = cp
	case string:
		*j = []byte(v)
	}
	return nil
}

func (j JSON) Value() (interface{}, error) {
	if len(j) == 0 {
		return "[]", nil
	}
	return string(j), nil
}

// MomentBlock 屏蔽的动态
type MomentBlock struct {
	ID        uint64    `gorm:"primaryKey" json:"id"`
	UserID    uint64    `gorm:"index:idx_user_moment,unique:1" json:"user_id"`   // 执行屏蔽的用户
	MomentID  uint64    `gorm:"index:idx_user_moment,unique:2" json:"moment_id"` // 被屏蔽的动态
	CreatedAt time.Time `json:"created_at"`
}

func (MomentBlock) TableName() string {
	return "moment_blocks"
}

// UserMomentBlock 屏蔽用户的动态
type UserMomentBlock struct {
	ID            uint64    `gorm:"primaryKey" json:"id"`
	UserID        uint64    `gorm:"index:idx_user_blocked,unique:1" json:"user_id"`         // 执行屏蔽的用户
	BlockedUserID uint64    `gorm:"index:idx_user_blocked,unique:2" json:"blocked_user_id"` // 被屏蔽的用户
	CreatedAt     time.Time `json:"created_at"`
}

func (UserMomentBlock) TableName() string {
	return "user_moment_blocks"
}
