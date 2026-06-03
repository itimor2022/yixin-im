package models

import (
	"time"

	"gorm.io/gorm"
)

// Chat 会话表 - MySQL
type Chat struct {
	ID          uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UUID        string     `gorm:"type:char(36);uniqueIndex;not null" json:"uuid"`
	Type        int8       `gorm:"type:tinyint;not null" json:"type"` // 1:私聊 2:群聊 3:频道
	Name        string     `gorm:"type:varchar(100)" json:"name"`
	Avatar      string     `gorm:"type:varchar(500)" json:"avatar"`
	Description string     `gorm:"type:varchar(1000)" json:"description"`
	OwnerID     uint64     `gorm:"index" json:"owner_id"`
	MemberCount int        `gorm:"default:0" json:"member_count"`
	MaxMembers  int        `gorm:"default:200" json:"max_members"`
	IsPublic    bool       `gorm:"default:false" json:"is_public"`
	InviteLink  string     `gorm:"type:varchar(100);uniqueIndex" json:"invite_link"`
	Username    string     `gorm:"type:varchar(32);index" json:"username"` // 群组用户名 (公开链接)
	Status      int8       `gorm:"type:tinyint;default:0" json:"status"`   // 0:正常 1:封禁 2:解散
	BanReason   string     `gorm:"type:varchar(500)" json:"ban_reason"`    // 封禁原因
	BannedAt    *time.Time `gorm:"type:datetime" json:"banned_at"`         // 封禁时间
	// 权限设置
	CanSendMessage   bool `gorm:"default:true" json:"can_send_message"`   // 成员可发送消息
	CanSendMedia     bool `gorm:"default:true" json:"can_send_media"`     // 成员可发送媒体
	CanSendLinks     bool `gorm:"default:true" json:"can_send_links"`     // 成员可发送链接
	CanAddMembers    bool `gorm:"default:false" json:"can_add_members"`   // 成员可添加成员
	CanPinMessages     bool   `gorm:"default:false" json:"can_pin_messages"`     // 成员可置顶消息
	MemberProtection   bool   `gorm:"default:true" json:"member_protection"`   // 开启后普通成员仅可见管理员/群主，且不可打开成员资料
	PinnedMessageID    string `gorm:"type:varchar(36);default:''" json:"pinned_message_id"` // 置顶消息ID (msg_id UUID)
	PinnedMessageText  string `gorm:"type:varchar(500)" json:"pinned_message_text"` // 置顶消息预览文本
	PinnedMessageBy    uint64 `gorm:"default:0" json:"pinned_message_by"`       // 置顶操作者ID
	PinnedMessageAt    *time.Time `gorm:"type:datetime" json:"pinned_message_at"` // 置顶时间
	// 加入审批设置
	JoinApproval bool           `gorm:"default:false" json:"join_approval"` // 是否需要审批加入
	CreatedAt    time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt    time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt    gorm.DeletedAt `gorm:"index" json:"-"`
}

// Chat 状态常量
const (
	ChatStatusNormal    = 0 // 正常
	ChatStatusBanned    = 1 // 封禁
	ChatStatusDissolved = 2 // 解散
)

func (Chat) TableName() string {
	return "chats"
}

// ChatMember 会话成员表
type ChatMember struct {
	ID          uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	ChatID      uint64     `gorm:"index:idx_chat_user;not null" json:"chat_id"`
	UserID      uint64     `gorm:"index:idx_chat_user;not null" json:"user_id"`
	Role        int8       `gorm:"type:tinyint;default:0" json:"role"` // 0:成员 1:管理员 2:创建者
	Nickname    string     `gorm:"type:varchar(100)" json:"nickname"`  // 群昵称
	IsMuted     bool       `gorm:"default:false" json:"is_muted"`
	IsPinned    bool       `gorm:"default:false" json:"is_pinned"`
	MuteEndTime *time.Time `gorm:"type:datetime" json:"mute_end_time"`
	LastReadSeq uint64     `gorm:"default:0" json:"last_read_seq"` // 最后已读消息序号
	JoinedAt    time.Time  `gorm:"type:datetime;not null" json:"joined_at"`
	UpdatedAt   time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (ChatMember) TableName() string {
	return "chat_members"
}

// UserChat 用户会话列表（快速查询）
type UserChat struct {
	ID          uint64     `gorm:"primaryKey;autoIncrement" json:"id"`
	UserID      uint64     `gorm:"index:idx_user_chat;not null" json:"user_id"`
	ChatID      uint64     `gorm:"index:idx_user_chat;not null" json:"chat_id"`
	TargetID    uint64     `gorm:"index" json:"target_id"` // 私聊对方ID
	LastMsgID     string     `gorm:"type:varchar(36);default:''" json:"last_msg_id"` // MongoDB msg_id (UUID)
	LastMsgSeq    uint64     `gorm:"default:0" json:"last_msg_seq"`
	LastMsgTime   time.Time  `gorm:"type:datetime" json:"last_msg_time"`
	LastMsgText   string     `gorm:"type:varchar(200)" json:"last_msg_text"`
	LastMsgType   int        `gorm:"default:1" json:"last_msg_type"`   // 最后消息类型
	LastMsgSender string     `gorm:"type:varchar(100)" json:"last_msg_sender"` // 最后消息发送者名称（群聊预览用）
	UnreadCount  int        `gorm:"default:0" json:"unread_count"`
	LastReadSeq  uint64     `gorm:"default:0" json:"last_read_seq"` // 最后已读消息序号
	IsPinned    bool       `gorm:"default:false" json:"is_pinned"`
	IsMuted     bool       `gorm:"default:false" json:"is_muted"`
	IsArchived  bool       `gorm:"default:false" json:"is_archived"`
	ClearedAt   *time.Time `gorm:"type:datetime" json:"cleared_at"` // 清空聊天记录时间点
	SortTime    time.Time  `gorm:"type:datetime;index" json:"sort_time"`
	UpdatedAt   time.Time  `gorm:"type:datetime;not null" json:"updated_at"`
}

func (UserChat) TableName() string {
	return "user_chats"
}

// JoinRequest 加入群组请求
type JoinRequest struct {
	ID         uint64         `gorm:"primaryKey;autoIncrement" json:"id"`
	ChatID     uint64         `gorm:"index;not null" json:"chat_id"`
	UserID     uint64         `gorm:"index;not null" json:"user_id"`
	Message    string         `gorm:"type:varchar(500)" json:"message"`     // 申请留言
	Status     int8           `gorm:"type:tinyint;default:0" json:"status"` // 0:待审批 1:已通过 2:已拒绝
	ReviewerID uint64         `gorm:"default:0" json:"reviewer_id"`         // 审批人ID
	ReviewedAt *time.Time     `gorm:"type:datetime" json:"reviewed_at"`     // 审批时间
	CreatedAt  time.Time      `gorm:"type:datetime;not null" json:"created_at"`
	UpdatedAt  time.Time      `gorm:"type:datetime;not null" json:"updated_at"`
	DeletedAt  gorm.DeletedAt `gorm:"index" json:"-"`
}

// JoinRequest 状态常量
const (
	JoinRequestPending  = 0 // 待审批
	JoinRequestApproved = 1 // 已通过
	JoinRequestRejected = 2 // 已拒绝
)

func (JoinRequest) TableName() string {
	return "join_requests"
}

// ChatLastMsg 群/私聊最新消息摘要（每个会话只有1行，读扩散架构核心表）
type ChatLastMsg struct {
	ChatID        uint64    `gorm:"primaryKey" json:"chat_id"`
	LastSeq       uint64    `gorm:"default:0" json:"last_seq"`
	LastMsgTime   time.Time `gorm:"type:datetime" json:"last_msg_time"`
	LastMsgText   string    `gorm:"type:varchar(200)" json:"last_msg_text"`
	LastMsgType   int       `gorm:"default:1" json:"last_msg_type"`
	LastMsgSender string    `gorm:"type:varchar(100)" json:"last_msg_sender"`
	UpdatedAt     time.Time `gorm:"type:datetime;not null" json:"updated_at"`
}

func (ChatLastMsg) TableName() string {
	return "chat_last_msg"
}

